// Read access to the originals container and write-once access to the reports container
// (Azure Blob; Azurite locally).
//
// - Account URL (Azure): DefaultAzureCredential (the worker's managed identity). The worker
//   never writes, overwrites or deletes an original; it only creates spatial report blobs, each
//   once (createReportsWriter).
// - Connection string (Azurite locally).
//
// Blob names always come from package_files.blob_name (a re-uploaded file lives in
// `<packageId>.retry-<n>/<path>`); the one exception is the sealed manifest, which the station
// API stores at `<packageId>/Source Register/<visitId>/manifest.json` (manifestBlobName).
// Errors are rethrown without request details, so no key or token reaches a log.

import { createHash } from "node:crypto";
import { DefaultAzureCredential, type TokenCredential } from "@azure/identity";
import { BlobServiceClient, RestError, type ContainerClient } from "@azure/storage-blob";
import type { WorkerConfig } from "./config.js";

/** A blob read into memory with the digest the worker computed. */
export interface BlobContent {
  readonly data: Buffer;
  readonly sha256: string;
  readonly bytes: number;
}

export interface OriginalsReader {
  readonly container: string;
  /**
   * Reads a blob of at most maxBytes. Undefined when it does not exist; "too_large" when it is
   * bigger than maxBytes (the bytes are not kept).
   */
  read(blobName: string, maxBytes: number): Promise<BlobContent | "too_large" | undefined>;
}

/** A storage failure without request details (safe to log). Retryable. */
export class StorageError extends Error {
  readonly retryable = true;

  constructor(
    message: string,
    readonly code: string,
    readonly statusCode?: number,
  ) {
    super(message);
    this.name = "StorageError";
  }
}

/** Blob of the sealed manifest, as the station API stores it (storage/originals.ts). */
export function manifestBlobName(packageId: string, visitId: string): string {
  return `${packageId}/Source Register/${visitId}/manifest.json`;
}

/** Package path of the sealed manifest (contract layout.json manifestPath). */
export function manifestPath(visitId: string): string {
  return `Source Register/${visitId}/manifest.json`;
}

function wrap(error: unknown, operation: string): StorageError {
  if (error instanceof StorageError) {
    return error;
  }
  if (error instanceof RestError) {
    return new StorageError(
      `${operation} failed (${error.code ?? "RestError"}, HTTP ${error.statusCode ?? "n/a"})`,
      error.code ?? "RestError",
      error.statusCode,
    );
  }
  const message =
    error instanceof Error ? error.message.replace(/\s+/g, " ").slice(0, 200) : "unknown error";
  return new StorageError(`${operation} failed: ${message}`, "ClientError");
}

function serviceClient(
  config: WorkerConfig["storage"],
  credential?: TokenCredential,
): BlobServiceClient {
  let service: BlobServiceClient;
  if (config.accountUrl !== undefined) {
    service = new BlobServiceClient(config.accountUrl, credential ?? new DefaultAzureCredential());
  } else if (config.connectionString !== undefined) {
    try {
      service = BlobServiceClient.fromConnectionString(config.connectionString);
    } catch {
      // The SDK error may quote the connection string: do not pass it on.
      throw new StorageError(
        "AZURE_STORAGE_CONNECTION_STRING is not a valid storage connection string",
        "InvalidConnectionString",
      );
    }
  } else {
    throw new StorageError("originals storage is not configured", "NotConfigured");
  }
  return service;
}

export function createOriginalsReader(
  config: WorkerConfig["storage"],
  credential?: TokenCredential,
): OriginalsReader {
  return blobReader(
    serviceClient(config, credential).getContainerClient(config.originalsContainer),
  );
}

// MARK: Reports

/** Writes the station's spatial reports (container `reports`). */
export interface ReportsWriter {
  readonly container: string;
  /**
   * Stores a report under `blobName`, once: the blob is created only when it does not exist. An
   * existing blob with the same SHA-256 is success (a retried job); a different one is refused
   * (ReportConflictError): a stored report is never replaced.
   */
  write(blobName: string, data: Uint8Array, sha256: string): Promise<"created" | "exists">;
  /** The bytes of a stored report. */
  read(blobName: string): Promise<Uint8Array>;
}

/** A different report is already stored under the name. Another attempt cannot fix it. */
export class ReportConflictError extends Error {
  readonly retryable = false;

  constructor(
    readonly blobName: string,
    /** SHA-256 the stored blob was written with (its metadata), when it has one. */
    readonly storedSha256?: string,
  ) {
    super(`A different spatial report is already stored as ${blobName}; it is not replaced`);
    this.name = "ReportConflictError";
  }
}

/** Metadata key holding the SHA-256 of a stored report. */
export const REPORT_SHA256_METADATA = "sha256";

/** The part of a container client the reports writer uses (tests fake it). */
export interface ReportsContainer {
  readonly containerName: string;
  getBlockBlobClient(name: string): {
    upload(
      body: Uint8Array,
      length: number,
      options: {
        blobHTTPHeaders: { blobContentType: string };
        metadata: Record<string, string>;
        conditions: { ifNoneMatch: string };
      },
    ): Promise<unknown>;
    getProperties(): Promise<{ metadata?: Record<string, string>; contentLength?: number }>;
    downloadToBuffer(): Promise<Buffer>;
  };
}

export function reportsWriter(container: ReportsContainer): ReportsWriter {
  return {
    container: container.containerName,
    async write(blobName, data, sha256) {
      const blob = container.getBlockBlobClient(blobName);
      try {
        await blob.upload(data, data.byteLength, {
          blobHTTPHeaders: { blobContentType: "application/pdf" },
          metadata: { [REPORT_SHA256_METADATA]: sha256 },
          conditions: { ifNoneMatch: "*" },
        });
        return "created";
      } catch (error) {
        // If-None-Match: * on an existing blob: 409 BlobAlreadyExists (412 on some services).
        const exists =
          error instanceof RestError && (error.statusCode === 409 || error.statusCode === 412);
        if (!exists) {
          throw wrap(error, "report upload");
        }
      }
      let properties;
      try {
        properties = await blob.getProperties();
      } catch (error) {
        throw wrap(error, "report properties");
      }
      if (
        properties.metadata?.[REPORT_SHA256_METADATA] === sha256 &&
        properties.contentLength === data.byteLength
      ) {
        return "exists";
      }
      throw new ReportConflictError(blobName, properties.metadata?.[REPORT_SHA256_METADATA]);
    },
    async read(blobName) {
      try {
        return await container.getBlockBlobClient(blobName).downloadToBuffer();
      } catch (error) {
        throw wrap(error, "report download");
      }
    },
  };
}

export function createReportsWriter(
  config: WorkerConfig["storage"],
  credential?: TokenCredential,
): ReportsWriter {
  return reportsWriter(
    serviceClient(config, credential).getContainerClient(config.reportsContainer),
  );
}

export function blobReader(container: ContainerClient): OriginalsReader {
  return {
    container: container.containerName,
    async read(blobName, maxBytes) {
      let response;
      try {
        response = await container.getBlobClient(blobName).download(0, undefined, {
          maxRetryRequests: 5,
        });
      } catch (error) {
        // Only a missing blob is "absent"; a missing container is a configuration fault.
        if (
          error instanceof RestError &&
          error.statusCode === 404 &&
          error.code === "BlobNotFound"
        ) {
          return undefined;
        }
        throw wrap(error, "blob download");
      }
      const body = response.readableStreamBody;
      if (body === undefined) {
        throw new StorageError("blob download returned no body", "NoBody");
      }
      if (response.contentLength !== undefined && response.contentLength > maxBytes) {
        body.resume();
        return "too_large";
      }
      const hash = createHash("sha256");
      const chunks: Buffer[] = [];
      let bytes = 0;
      try {
        for await (const chunk of body) {
          const buffer = typeof chunk === "string" ? Buffer.from(chunk) : (chunk as Buffer);
          bytes += buffer.length;
          if (bytes > maxBytes) {
            body.resume();
            return "too_large";
          }
          hash.update(buffer);
          chunks.push(buffer);
        }
      } catch (error) {
        throw wrap(error, "blob read");
      }
      if (response.contentLength !== undefined && bytes !== response.contentLength) {
        throw new StorageError("blob read ended before the end of the blob", "ShortRead");
      }
      return { data: Buffer.concat(chunks), sha256: hash.digest("hex"), bytes };
    },
  };
}
