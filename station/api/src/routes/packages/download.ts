// Signed, short-lived, read-only download links for one verified original.
//
// - A link is a blob SAS with permission r only, for exactly one blob, valid for 10 minutes
//   (start backdated 5 minutes for clock skew), https-only unless the endpoint itself is http
//   (Azurite).
// - Azure (AZURE_STORAGE_ACCOUNT_URL): signed with a user delegation key of the station's
//   managed identity; no account key is used. Keys are cached for an hour and refreshed while
//   they still outlive any link signed with them.
// - Local (AZURE_STORAGE_CONNECTION_STRING, Azurite): signed with the connection string's
//   account key.
// - Only bim and admin may get a link; only verified files with a stored blob; every link
//   handed out is audited (the URL itself never is).
//
// NOT EXPOSED YET: contract/openapi/station.yaml defines no download operation, so no route
// calls issueDownloadLink. A route needs only an OpenAPI operation that maps to it.
//
// DUPLICATION: the uploads area builds its own storage client (write SAS) in parallel. Merge
// the credential and endpoint handling here with that module once both have landed.

import { ManagedIdentityCredential, type TokenCredential } from "@azure/identity";
import {
  BlobSASPermissions,
  BlobServiceClient,
  SASProtocol,
  StorageSharedKeyCredential,
  generateBlobSASQueryParameters,
  type UserDelegationKey,
} from "@azure/storage-blob";
import type { FastifyRequest } from "fastify";
import { audit } from "../../core/audit.js";
import type { Role } from "../../core/auth.js";
import type { StationConfig } from "../../core/config.js";
import { ProblemError } from "../../core/problem.js";
import { toApiDateTime } from "../../core/time.js";
import { isContractUuid } from "./schemas.js";

/** How long a download link is valid. */
export const DOWNLOAD_LINK_TTL_MS = 10 * 60_000;
/** Start time backdating, for clients whose clock runs behind. */
export const CLOCK_SKEW_MS = 5 * 60_000;
/** Lifetime requested for a user delegation key. */
export const DELEGATION_KEY_TTL_MS = 60 * 60_000;
/** Roles that may download originals. */
export const DOWNLOAD_ROLES: readonly Role[] = ["bim", "admin"];

export interface DownloadLink {
  /** Blob URL with a read-only SAS. A secret: never log or audit it. */
  readonly url: string;
  readonly expiresAt: Date;
}

export interface ReadLinkSigner {
  /** Signs a read-only link for one blob of the originals container. */
  signRead(blobName: string, options?: { fileName?: string }): Promise<DownloadLink>;
}

declare module "../../core/services.js" {
  interface StationServices {
    /** Read-only SAS signer for download links (tests inject one). */
    downloadLinks: ReadLinkSigner;
  }
}

/** Gets a user delegation key valid from startsOn to expiresOn. */
export type DelegationKeySource = (startsOn: Date, expiresOn: Date) => Promise<UserDelegationKey>;

interface SignerBase {
  readonly containerName: string;
  /** Blob service URL the station uses, for example https://acct.blob.core.windows.net. */
  readonly serviceUrl: string;
  /** Blob service URL as clients reach it, when different (local stack). */
  readonly publicBlobEndpoint?: string;
  /** Clock, for tests. */
  readonly now?: () => number;
}

export type ReadLinkSignerOptions =
  | (SignerBase & { readonly kind: "shared-key"; readonly credential: StorageSharedKeyCredential })
  | (SignerBase & {
      readonly kind: "user-delegation";
      readonly accountName: string;
      readonly getDelegationKey: DelegationKeySource;
    });

function trimSlash(url: string): string {
  return url.replace(/\/+$/, "");
}

/** RFC 6266 attachment disposition with a UTF-8 file name. */
export function attachmentDisposition(fileName: string): string {
  const encoded = encodeURIComponent(fileName).replace(
    /['()*]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  );
  return `attachment; filename*=UTF-8''${encoded}`;
}

export function createReadLinkSigner(options: ReadLinkSignerOptions): ReadLinkSigner {
  const now = options.now ?? Date.now;
  const serviceUrl = trimSlash(options.serviceUrl);
  const clientBase =
    options.publicBlobEndpoint === undefined ? serviceUrl : trimSlash(options.publicBlobEndpoint);
  // Only used to build correctly escaped blob URLs; it makes no requests.
  const container = new BlobServiceClient(clientBase).getContainerClient(options.containerName);
  const protocol =
    new URL(clientBase).protocol === "https:" ? SASProtocol.Https : SASProtocol.HttpsAndHttp;

  let cachedKey: UserDelegationKey | undefined;
  let pendingKey: Promise<UserDelegationKey> | undefined;

  const delegationKey = async (
    source: DelegationKeySource,
    linkExpiresOn: Date,
  ): Promise<UserDelegationKey> => {
    if (cachedKey !== undefined && cachedKey.signedExpiresOn.getTime() > linkExpiresOn.getTime()) {
      return cachedKey;
    }
    pendingKey ??= (async () => {
      const startsOn = new Date(now() - CLOCK_SKEW_MS);
      const expiresOn = new Date(now() + DELEGATION_KEY_TTL_MS);
      const key = await source(startsOn, expiresOn);
      cachedKey = key;
      return key;
    })().finally(() => {
      pendingKey = undefined;
    });
    const key = await pendingKey;
    if (key.signedExpiresOn.getTime() <= linkExpiresOn.getTime()) {
      throw new Error("user delegation key expires before the download link would");
    }
    return key;
  };

  return {
    async signRead(blobName, signOptions = {}) {
      if (blobName.length === 0) {
        throw new RangeError("blob name is empty");
      }
      const startsOn = new Date(now() - CLOCK_SKEW_MS);
      const expiresOn = new Date(now() + DOWNLOAD_LINK_TTL_MS);
      const values = {
        containerName: options.containerName,
        blobName,
        permissions: BlobSASPermissions.parse("r"),
        startsOn,
        expiresOn,
        protocol,
        ...(signOptions.fileName === undefined
          ? {}
          : { contentDisposition: attachmentDisposition(signOptions.fileName) }),
      };
      const sas =
        options.kind === "shared-key"
          ? generateBlobSASQueryParameters(values, options.credential)
          : generateBlobSASQueryParameters(
              values,
              await delegationKey(options.getDelegationKey, expiresOn),
              options.accountName,
            );
      const blobUrl = container.getBlobClient(blobName).url;
      return { url: `${blobUrl}?${sas.toString()}`, expiresAt: expiresOn };
    },
  };
}

/** Account name of a blob service URL (first host label, or the path for Azurite). */
export function accountNameFromUrl(accountUrl: string): string {
  const url = new URL(accountUrl);
  const firstLabel = url.hostname.split(".")[0] ?? "";
  if (url.hostname.endsWith(".blob.core.windows.net") && firstLabel !== "") {
    return firstLabel;
  }
  const pathAccount = url.pathname.split("/").filter(Boolean)[0];
  if (pathAccount !== undefined) {
    return pathAccount;
  }
  if (firstLabel === "") {
    throw new Error("cannot read the storage account name from AZURE_STORAGE_ACCOUNT_URL");
  }
  return firstLabel;
}

/**
 * The signer for the configured storage: managed identity (user delegation key) when
 * AZURE_STORAGE_ACCOUNT_URL is set, else the account key of AZURE_STORAGE_CONNECTION_STRING.
 * Throws when neither is configured or the connection string carries no account key.
 */
export function readLinkSignerFromConfig(
  config: StationConfig,
  credential?: TokenCredential,
): ReadLinkSigner {
  const storage = config.storage;
  const containerName = storage.originalsContainer;
  const publicEndpoint =
    storage.publicBlobEndpoint === undefined
      ? {}
      : { publicBlobEndpoint: storage.publicBlobEndpoint };

  if (storage.accountUrl !== undefined) {
    const connection = config.database.connection;
    const clientId = connection.auth === "entra" ? connection.managedIdentityClientId : undefined;
    const identity =
      credential ??
      (clientId === undefined
        ? new ManagedIdentityCredential()
        : new ManagedIdentityCredential({ clientId }));
    const service = new BlobServiceClient(storage.accountUrl, identity);
    return createReadLinkSigner({
      kind: "user-delegation",
      containerName,
      serviceUrl: storage.accountUrl,
      ...publicEndpoint,
      accountName: accountNameFromUrl(storage.accountUrl),
      getDelegationKey: async (startsOn, expiresOn) => {
        const response = await service.getUserDelegationKey(startsOn, expiresOn);
        return response;
      },
    });
  }

  if (storage.connectionString !== undefined) {
    const service = BlobServiceClient.fromConnectionString(storage.connectionString);
    if (!(service.credential instanceof StorageSharedKeyCredential)) {
      throw new Error(
        "AZURE_STORAGE_CONNECTION_STRING must carry an account key to sign download links",
      );
    }
    return createReadLinkSigner({
      kind: "shared-key",
      containerName,
      serviceUrl: service.url,
      ...publicEndpoint,
      credential: service.credential,
    });
  }

  throw new Error(
    "download links need AZURE_STORAGE_ACCOUNT_URL or AZURE_STORAGE_CONNECTION_STRING",
  );
}

/** The injected signer, or one created from config on first use. */
export function downloadSigner(request: FastifyRequest): ReadLinkSigner {
  const services = request.server.services as { downloadLinks?: ReadLinkSigner };
  services.downloadLinks ??= readLinkSignerFromConfig(request.server.config);
  return services.downloadLinks;
}

export interface IssuedDownloadLink {
  readonly path: string;
  readonly url: string;
  /** Contract DateTime. */
  readonly expiresAt: string;
}

interface DownloadFileRow {
  status: string;
  blob_name: string | null;
}

/**
 * Hands the signed-in bim/admin caller a read-only link to one verified file and audits it.
 * 404 when the package or file does not exist, 409 file_not_verified when the file has no
 * verified blob, 403 for any other role (also enforced by the route's roles).
 */
export async function issueDownloadLink(
  request: FastifyRequest,
  packageId: string,
  path: string,
): Promise<IssuedDownloadLink> {
  const principal = request.principal;
  if (principal === null || !principal.roles.some((role) => DOWNLOAD_ROLES.includes(role))) {
    throw new ProblemError(403, "forbidden", {
      detail: `This operation requires one of the roles: ${DOWNLOAD_ROLES.join(", ")}.`,
    });
  }
  if (!isContractUuid(packageId)) {
    throw new ProblemError(404, "not_found", { detail: "No package with this id." });
  }
  const db = request.server.db;
  const result = await db.query<DownloadFileRow>(
    "SELECT status, blob_name FROM package_files WHERE package_id = $1 AND path = $2",
    [packageId, path],
  );
  const row = result.rows[0];
  if (row === undefined) {
    throw new ProblemError(404, "not_found", { detail: "No file with this path in the package." });
  }
  if (row.status !== "verified" || row.blob_name === null) {
    throw new ProblemError(409, "file_not_verified", {
      detail: "The file has no verified upload to download.",
    });
  }
  const fileName = path.split("/").pop() ?? path;
  const link = await downloadSigner(request).signRead(row.blob_name, { fileName });
  const expiresAt = toApiDateTime(link.expiresAt);
  await audit(
    request,
    "package_file.download_link",
    { type: "package", id: packageId },
    {
      path,
      expiresAt,
    },
  );
  return { path, url: link.url, expiresAt };
}
