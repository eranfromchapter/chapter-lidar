// OriginalsStorage over Azure Blob Storage (@azure/storage-blob).
//
// - Account URL (Azure): the station signs in with DefaultAzureCredential (its managed identity
//   in Container Apps; AZURE_CLIENT_ID selects a user-assigned one) and signs upload targets as
//   user delegation SAS. The identity needs Storage Blob Data Contributor on the account (read
//   and create blobs, get a user delegation key). The container is created by infra with its
//   immutability policy; the station never creates or changes it.
// - Connection string (Azurite locally): shared key SAS, and the container is created on first
//   use.
//
// Every SAS is for one blob, create permission only, HTTPS only in Azure. Errors are rethrown as
// OriginalsStorageError without request details, so no SAS, token or key reaches a log.

import { createHash } from "node:crypto";
import { DefaultAzureCredential, type TokenCredential } from "@azure/identity";
import {
  BlobSASPermissions,
  BlobServiceClient,
  type ContainerClient,
  RestError,
  SASProtocol,
  StorageSharedKeyCredential,
  type UserDelegationKey,
  generateBlobSASQueryParameters,
} from "@azure/storage-blob";
import type { StationConfig } from "../core/config.js";
import {
  BlobExistsError,
  BlobTooLargeError,
  type BlobContent,
  type BlobDigest,
  type CreateOnceResult,
  type OriginalsStorage,
  OriginalsStorageError,
  type OriginalsStorageOptions,
  type UploadGrant,
  UPLOAD_TARGET_TTL_MS,
} from "./originals.js";

/** Permission letters of an upload target: create only. */
export const UPLOAD_SAS_PERMISSIONS = "c";
/** Allowance for client clock skew on the SAS start time. */
const CLOCK_SKEW_MS = 5 * 60_000;
/** Lifetime of a requested user delegation key (Azure allows up to 7 days). */
const DELEGATION_KEY_TTL_MS = 6 * 60 * 60_000;

type StorageConfig = StationConfig["storage"];

function safeMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message.replace(/\s+/g, " ").slice(0, 300);
  }
  return "unknown error";
}

/** Wraps any storage failure without its request (URL, headers) or response body. */
function wrap(error: unknown, operation: string): OriginalsStorageError {
  if (error instanceof OriginalsStorageError) {
    return error;
  }
  if (error instanceof RestError) {
    return new OriginalsStorageError(
      `${operation} failed (${error.code ?? "RestError"}, HTTP ${error.statusCode ?? "n/a"})`,
      error.code ?? "RestError",
      error.statusCode,
    );
  }
  return new OriginalsStorageError(`${operation} failed: ${safeMessage(error)}`, "ClientError");
}

function isBlobNotFound(error: unknown): boolean {
  return error instanceof RestError && error.statusCode === 404 && error.code === "BlobNotFound";
}

function isAlreadyExists(error: unknown): boolean {
  return error instanceof RestError && (error.statusCode === 409 || error.statusCode === 412);
}

function wholeSeconds(epochMs: number): Date {
  return new Date(Math.floor(epochMs / 1000) * 1000);
}

function trimSlash(url: string): string {
  return url.replace(/\/+$/, "");
}

interface Signer {
  sign(containerName: string, blobName: string, startsOn: Date, expiresOn: Date): Promise<string>;
}

function sharedKeySigner(credential: StorageSharedKeyCredential): Signer {
  return {
    async sign(containerName, blobName, startsOn, expiresOn) {
      return generateBlobSASQueryParameters(
        {
          containerName,
          blobName,
          permissions: BlobSASPermissions.parse(UPLOAD_SAS_PERMISSIONS),
          startsOn,
          expiresOn,
          // Azurite serves plain http on loopback.
          protocol: SASProtocol.HttpsAndHttp,
        },
        credential,
      ).toString();
    },
  };
}

function userDelegationSigner(service: BlobServiceClient, now: () => Date): Signer {
  let cached: { key: UserDelegationKey; expiresOn: number } | undefined;
  let pending: Promise<UserDelegationKey> | undefined;

  const delegationKey = async (sasExpiresOn: Date): Promise<UserDelegationKey> => {
    if (cached && cached.expiresOn >= sasExpiresOn.getTime() + 60_000) {
      return cached.key;
    }
    pending ??= (async () => {
      const start = now().getTime();
      const expiresOn = wholeSeconds(start + DELEGATION_KEY_TTL_MS);
      try {
        const key = await service.getUserDelegationKey(
          wholeSeconds(start - CLOCK_SKEW_MS),
          expiresOn,
        );
        cached = { key, expiresOn: expiresOn.getTime() };
        return key;
      } catch (error) {
        throw wrap(error, "get user delegation key");
      }
    })().finally(() => {
      pending = undefined;
    });
    return pending;
  };

  return {
    async sign(containerName, blobName, startsOn, expiresOn) {
      const key = await delegationKey(expiresOn);
      return generateBlobSASQueryParameters(
        {
          containerName,
          blobName,
          permissions: BlobSASPermissions.parse(UPLOAD_SAS_PERMISSIONS),
          startsOn,
          expiresOn,
          protocol: SASProtocol.Https,
        },
        key,
        service.accountName,
      ).toString();
    },
  };
}

interface AzureParts {
  readonly service: BlobServiceClient;
  readonly signer: Signer;
  /** Create the container on first use (Azurite only). */
  readonly createContainer: boolean;
}

function connectionStringParts(connectionString: string): AzureParts {
  let service: BlobServiceClient;
  try {
    service = BlobServiceClient.fromConnectionString(connectionString);
  } catch {
    // The SDK error may quote the connection string: do not pass it on.
    throw new OriginalsStorageError(
      "AZURE_STORAGE_CONNECTION_STRING is not a valid storage connection string",
      "InvalidConnectionString",
    );
  }
  const credential = service.credential;
  if (!(credential instanceof StorageSharedKeyCredential)) {
    throw new OriginalsStorageError(
      "AZURE_STORAGE_CONNECTION_STRING must carry an account key (needed to sign upload targets)",
      "InvalidConnectionString",
    );
  }
  return { service, signer: sharedKeySigner(credential), createContainer: true };
}

function accountUrlParts(
  accountUrl: string,
  credential: TokenCredential,
  now: () => Date,
): AzureParts {
  const service = new BlobServiceClient(accountUrl, credential);
  return { service, signer: userDelegationSigner(service, now), createContainer: false };
}

/**
 * Azure Blob originals storage from the station config. Returns undefined when neither
 * AZURE_STORAGE_ACCOUNT_URL nor AZURE_STORAGE_CONNECTION_STRING is set. The account URL wins
 * when both are set.
 */
export function createAzureOriginalsStorage(
  config: StorageConfig,
  options: OriginalsStorageOptions = {},
): OriginalsStorage | undefined {
  const now = options.now ?? (() => new Date());
  let parts: AzureParts;
  if (config.accountUrl !== undefined) {
    parts = accountUrlParts(
      config.accountUrl,
      options.credential ?? new DefaultAzureCredential(),
      now,
    );
  } else if (config.connectionString !== undefined) {
    parts = connectionStringParts(config.connectionString);
  } else {
    return undefined;
  }
  return azureOriginalsStorage(parts, config, now);
}

function azureOriginalsStorage(
  parts: AzureParts,
  config: StorageConfig,
  now: () => Date,
): OriginalsStorage {
  const containerName = config.originalsContainer;
  const container: ContainerClient = parts.service.getContainerClient(containerName);
  const serviceUrl = trimSlash(parts.service.url.split("?")[0] ?? parts.service.url);
  const publicEndpoint =
    config.publicBlobEndpoint === undefined ? undefined : trimSlash(config.publicBlobEndpoint);

  let containerReady: Promise<void> | undefined;
  const ready = async (): Promise<void> => {
    if (!parts.createContainer) {
      return;
    }
    containerReady ??= container.createIfNotExists().then(
      () => undefined,
      (error: unknown) => {
        containerReady = undefined;
        throw wrap(error, "create container");
      },
    );
    return containerReady;
  };

  /** Blob URL as clients reach it (STORAGE_PUBLIC_BLOB_ENDPOINT replaces the service URL). */
  const clientUrl = (blobUrl: string): string => {
    if (publicEndpoint === undefined) {
      return blobUrl;
    }
    if (!blobUrl.startsWith(`${serviceUrl}/`)) {
      throw new OriginalsStorageError("blob URL is outside the service URL", "UnexpectedUrl");
    }
    return `${publicEndpoint}${blobUrl.slice(serviceUrl.length)}`;
  };

  const download = async (blobName: string) => {
    await ready();
    try {
      return await container.getBlobClient(blobName).download(0, undefined, {
        maxRetryRequests: 5,
      });
    } catch (error) {
      if (isBlobNotFound(error)) {
        return undefined;
      }
      throw wrap(error, "blob download");
    }
  };

  const storage: OriginalsStorage = {
    container: containerName,

    async grantUpload(blobName: string): Promise<UploadGrant> {
      await ready();
      const start = now().getTime();
      const startsOn = wholeSeconds(start - CLOCK_SKEW_MS);
      const expiresAt = wholeSeconds(start + UPLOAD_TARGET_TTL_MS);
      const blob = container.getBlockBlobClient(blobName);
      const query = await parts.signer.sign(containerName, blobName, startsOn, expiresAt);
      return {
        url: `${clientUrl(blob.url)}?${query}`,
        method: "PUT",
        headers: { "x-ms-blob-type": "BlockBlob" },
        expiresAt,
      };
    },

    async digest(blobName: string): Promise<BlobDigest | undefined> {
      const response = await download(blobName);
      if (response === undefined) {
        return undefined;
      }
      const body = response.readableStreamBody;
      if (body === undefined) {
        throw new OriginalsStorageError("blob download returned no body", "NoBody");
      }
      const hash = createHash("sha256");
      let bytes = 0;
      try {
        for await (const chunk of body) {
          const buffer = typeof chunk === "string" ? Buffer.from(chunk) : (chunk as Buffer);
          hash.update(buffer);
          bytes += buffer.length;
        }
      } catch (error) {
        throw wrap(error, "blob read");
      }
      if (response.contentLength !== undefined && bytes !== response.contentLength) {
        throw new OriginalsStorageError("blob read ended before the end of the blob", "ShortRead");
      }
      return { sha256: hash.digest("hex"), bytes };
    },

    async read(blobName: string, maxBytes: number): Promise<BlobContent | undefined> {
      const response = await download(blobName);
      if (response === undefined) {
        return undefined;
      }
      const body = response.readableStreamBody;
      if (body === undefined) {
        throw new OriginalsStorageError("blob download returned no body", "NoBody");
      }
      if (response.contentLength !== undefined && response.contentLength > maxBytes) {
        body.resume();
        throw new BlobTooLargeError(blobName, maxBytes);
      }
      const chunks: Buffer[] = [];
      let bytes = 0;
      try {
        for await (const chunk of body) {
          const buffer = typeof chunk === "string" ? Buffer.from(chunk) : (chunk as Buffer);
          bytes += buffer.length;
          if (bytes > maxBytes) {
            throw new BlobTooLargeError(blobName, maxBytes);
          }
          chunks.push(buffer);
        }
      } catch (error) {
        throw wrap(error, "blob read");
      }
      if (response.contentLength !== undefined && bytes !== response.contentLength) {
        throw new OriginalsStorageError("blob read ended before the end of the blob", "ShortRead");
      }
      const data = Buffer.concat(chunks);
      return { data, sha256: createHash("sha256").update(data).digest("hex"), bytes };
    },

    async createOnce(
      blobName: string,
      data: Buffer,
      contentType: string,
    ): Promise<CreateOnceResult> {
      await ready();
      try {
        await container.getBlockBlobClient(blobName).upload(data, data.length, {
          conditions: { ifNoneMatch: "*" },
          blobHTTPHeaders: { blobContentType: contentType },
        });
        return "created";
      } catch (error) {
        if (!isAlreadyExists(error)) {
          throw wrap(error, "blob upload");
        }
      }
      const existing = await storage.digest(blobName);
      const expected = createHash("sha256").update(data).digest("hex");
      if (
        existing !== undefined &&
        existing.sha256 === expected &&
        existing.bytes === data.length
      ) {
        return "identical";
      }
      throw new BlobExistsError(blobName);
    },
  };
  return storage;
}
