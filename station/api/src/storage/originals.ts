// Originals storage: the Azure Blob container that holds every uploaded package file.
//
// Rules this module guarantees (the upload routes rely on them):
//
// - Upload targets are SAS URLs for exactly one blob with the CREATE permission only (no read,
//   write-over, delete or list) and a 30-minute expiry. A blob that already exists cannot be
//   overwritten or deleted through such a URL, so a file the station verified stays as verified.
// - The station never issues a target for a verified file (routes) and never overwrites or deletes
//   a blob itself: its own writes (the sealed manifest) are create-only too.
// - In Azure the container also has a time-based immutability policy (infra), which blocks
//   overwrite and delete for every identity, the station included.
//
// Blob names: attempt 1 of a file is `<packageId>/<path>`. When a stored blob does not match its
// declaration it cannot be replaced (immutability), so the next upload target points to a new
// blob `<packageId>.retry-<n>/<path>` (n = 2, 3, ...). package_files.blob_name records the blob
// the current target points to; readers must use it rather than rebuilding the name.

import type { TokenCredential } from "@azure/identity";

/** Lifetime of an upload target. */
export const UPLOAD_TARGET_TTL_MS = 30 * 60_000;

/** One write-only upload target. */
export interface UploadGrant {
  /** SAS URL (secret until it expires: never log it). */
  readonly url: string;
  readonly method: "PUT";
  readonly headers: Readonly<Record<string, string>>;
  readonly expiresAt: Date;
}

/** SHA-256 (lowercase hex) and size of a stored blob, computed by the station. */
export interface BlobDigest {
  readonly sha256: string;
  readonly bytes: number;
}

/** A blob read into memory, with its digest. */
export interface BlobContent extends BlobDigest {
  readonly data: Buffer;
}

export type CreateOnceResult = "created" | "identical";

/** The originals container as the upload routes use it. */
export interface OriginalsStorage {
  /** Container name, for audit details. */
  readonly container: string;
  /** Create-only SAS URL for one blob, valid for UPLOAD_TARGET_TTL_MS from now. */
  grantUpload(blobName: string): Promise<UploadGrant>;
  /** Streams the committed blob and hashes it; undefined when no committed blob exists. */
  digest(blobName: string): Promise<BlobDigest | undefined>;
  /** Reads a committed blob of at most maxBytes; undefined when it does not exist. */
  read(blobName: string, maxBytes: number): Promise<BlobContent | undefined>;
  /**
   * Creates a blob that must not exist yet. Returns "identical" when it already exists with
   * exactly these bytes; throws BlobExistsError when it exists with other bytes.
   */
  createOnce(blobName: string, data: Buffer, contentType: string): Promise<CreateOnceResult>;
}

/** A storage failure, without request details (URLs, headers) so it is safe to log. */
export class OriginalsStorageError extends Error {
  constructor(
    message: string,
    /** Storage error code (for example AuthorizationFailure) or a local reason. */
    readonly code: string,
    readonly statusCode?: number,
  ) {
    super(message);
    this.name = "OriginalsStorageError";
  }
}

/** createOnce found a different blob under the name. */
export class BlobExistsError extends OriginalsStorageError {
  constructor(blobName: string) {
    super(`blob ${blobName} already exists with different content`, "BlobExistsDifferent", 409);
    this.name = "BlobExistsError";
  }
}

/** A blob grew beyond the read limit. */
export class BlobTooLargeError extends OriginalsStorageError {
  constructor(blobName: string, maxBytes: number) {
    super(`blob ${blobName} is larger than ${maxBytes} bytes`, "BlobTooLarge");
    this.name = "BlobTooLargeError";
  }
}

declare module "../core/services.js" {
  interface StationServices {
    /** The originals container (Azure Blob; Azurite locally). */
    originals: OriginalsStorage;
  }
}

/** Optional overrides for the Azure client (tests, a specific credential). */
export interface OriginalsStorageOptions {
  /** Credential for account-URL mode; defaults to DefaultAzureCredential (managed identity). */
  readonly credential?: TokenCredential;
  /** Clock, for tests. */
  readonly now?: () => Date;
}

const RETRY_PATTERN = /^\.retry-([1-9][0-9]*)\/(.*)$/s;

/** Blob of attempt 1 of a declared file. */
export function firstBlobName(packageId: string, path: string): string {
  return `${packageId}/${path}`;
}

/** Blob name of an upload attempt (attempt 1 is firstBlobName). */
export function attemptBlobName(packageId: string, path: string, attempt: number): string {
  if (!Number.isSafeInteger(attempt) || attempt < 1) {
    throw new RangeError(`invalid upload attempt ${attempt}`);
  }
  return attempt === 1 ? firstBlobName(packageId, path) : `${packageId}.retry-${attempt}/${path}`;
}

/** Attempt number of a blob name of this file; throws when the name is not one of its blobs. */
export function attemptOf(packageId: string, path: string, blobName: string): number {
  if (blobName === firstBlobName(packageId, path)) {
    return 1;
  }
  if (blobName.startsWith(packageId)) {
    const match = RETRY_PATTERN.exec(blobName.slice(packageId.length));
    if (match?.[2] === path) {
      const attempt = Number(match[1]);
      if (Number.isSafeInteger(attempt) && attempt >= 2) {
        return attempt;
      }
    }
  }
  throw new RangeError(`blob name does not belong to file ${path} of package ${packageId}`);
}

/** Blob for the next upload attempt after blobName was rejected. */
export function nextAttemptBlobName(packageId: string, path: string, blobName: string): string {
  return attemptBlobName(packageId, path, attemptOf(packageId, path, blobName) + 1);
}

/** Where the station stores a sealed package's manifest (layout.json manifestPath). */
export function manifestPath(visitId: string): string {
  return `Source Register/${visitId}/manifest.json`;
}

/**
 * Storage used when no storage is configured: every call fails with code NotConfigured, so
 * routes answer 503 instead of the station refusing to start (the routes still check tokens).
 */
export function unconfiguredOriginals(container: string): OriginalsStorage {
  const fail = async (): Promise<never> => {
    throw new OriginalsStorageError(
      "originals storage is not configured (set AZURE_STORAGE_ACCOUNT_URL or AZURE_STORAGE_CONNECTION_STRING)",
      "NotConfigured",
    );
  };
  return { container, grantUpload: fail, digest: fail, read: fail, createOnce: fail };
}

/** Blob of the sealed manifest of a package. */
export function manifestBlobName(packageId: string, visitId: string): string {
  return firstBlobName(packageId, manifestPath(visitId));
}
