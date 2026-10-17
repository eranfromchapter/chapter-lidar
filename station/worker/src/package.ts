// Reading a sealed package: registry rows and verified bytes from the originals container.
//
// Every file is read from package_files.blob_name (never rebuilt from the path) and re-hashed;
// the manifest is read from the blob the station API stored at sealing and checked against
// packages.manifest_sha256. A missing blob, a size or SHA-256 mismatch is an integrity error:
// the job ends (check_error / publish_failed) and an audit row records it. It is never a verdict.

import { TerminalJobError } from "./context.js";
import type { Queryable } from "./db.js";
import { manifestBlobName, manifestPath, type OriginalsReader } from "./storage.js";

export type PackageStatus =
  "uploading" | "checks_queued" | "checking" | "verdict_ready" | "check_error";

export interface PackageRow {
  readonly package_id: string;
  readonly visit_id: string;
  readonly deal_id: string;
  readonly revision: number;
  readonly status: PackageStatus;
  readonly manifest: Record<string, unknown> | null;
  readonly manifest_sha256: string | null;
  readonly capture_record: Record<string, unknown> | null;
}

export interface FileRow {
  readonly path: string;
  readonly role: string;
  readonly capture_id: string | null;
  readonly area_key: string | null;
  readonly sha256: string;
  readonly bytes: number;
  readonly status: string;
  readonly blob_name: string | null;
}

/** Largest manifest the worker reads. */
export const MAX_MANIFEST_BYTES = 16 * 1024 * 1024;

export async function selectPackage(
  db: Queryable,
  packageId: string,
): Promise<PackageRow | undefined> {
  const result = await db.query<PackageRow>(
    `SELECT package_id, visit_id, deal_id, revision, status, manifest, manifest_sha256, capture_record
       FROM packages WHERE package_id = $1`,
    [packageId],
  );
  return result.rows[0];
}

export async function selectFiles(db: Queryable, packageId: string): Promise<FileRow[]> {
  const result = await db.query<FileRow>(
    `SELECT path, role, capture_id, area_key, sha256, bytes, status, blob_name
       FROM package_files WHERE package_id = $1
      ORDER BY path COLLATE "C"`,
    [packageId],
  );
  return result.rows;
}

/** An integrity failure: audited as package.integrity_error. */
export class IntegrityError extends TerminalJobError {
  constructor(message: string, details: Record<string, unknown>) {
    super(message, "package.integrity_error", details);
    this.name = "IntegrityError";
  }
}

/** Reads one blob and checks its size and SHA-256 against the registry. */
export async function readVerified(
  originals: OriginalsReader,
  file: { path: string; blobName: string; sha256: string; bytes: number },
): Promise<Buffer> {
  const details = {
    path: file.path,
    blobName: file.blobName,
    container: originals.container,
    expectedSha256: file.sha256,
    expectedBytes: file.bytes,
  };
  const content = await originals.read(file.blobName, file.bytes);
  if (content === undefined) {
    throw new IntegrityError(`Stored blob of ${file.path} is missing`, {
      ...details,
      reason: "missing",
    });
  }
  if (content === "too_large") {
    throw new IntegrityError(`Stored blob of ${file.path} is larger than its recorded size`, {
      ...details,
      reason: "bytes_mismatch",
    });
  }
  if (content.bytes !== file.bytes || content.sha256 !== file.sha256) {
    throw new IntegrityError(
      `Stored blob of ${file.path} does not match its recorded SHA-256 and size`,
      {
        ...details,
        reason: content.bytes !== file.bytes ? "bytes_mismatch" : "sha256_mismatch",
        actualSha256: content.sha256,
        actualBytes: content.bytes,
      },
    );
  }
  return content.data;
}

/** The sealed manifest bytes, checked against packages.manifest_sha256. */
export async function readManifest(originals: OriginalsReader, pkg: PackageRow): Promise<Buffer> {
  if (pkg.manifest_sha256 === null) {
    throw new TerminalJobError(`Package ${pkg.package_id} is not sealed`);
  }
  const blobName = manifestBlobName(pkg.package_id, pkg.visit_id);
  const content = await originals.read(blobName, MAX_MANIFEST_BYTES);
  const details = {
    path: manifestPath(pkg.visit_id),
    blobName,
    container: originals.container,
    expectedSha256: pkg.manifest_sha256,
  };
  if (content === undefined) {
    throw new IntegrityError("Stored manifest is missing", { ...details, reason: "missing" });
  }
  if (content === "too_large") {
    throw new IntegrityError("Stored manifest is larger than the worker reads", {
      ...details,
      reason: "too_large",
    });
  }
  if (content.sha256 !== pkg.manifest_sha256) {
    throw new IntegrityError("Stored manifest does not match its recorded SHA-256", {
      ...details,
      reason: "sha256_mismatch",
      actualSha256: content.sha256,
    });
  }
  return content.data;
}

/** Every file of a sealed package must be verified and have a blob. */
export function requireVerified(files: readonly FileRow[]): Array<FileRow & { blob_name: string }> {
  const bad = files.filter((file) => file.status !== "verified" || file.blob_name === null);
  if (bad.length > 0) {
    throw new IntegrityError(`${bad.length} file(s) of the sealed package are not verified`, {
      reason: "not_verified",
      paths: bad.slice(0, 20).map((file) => file.path),
    });
  }
  return files as Array<FileRow & { blob_name: string }>;
}

/** Reads the whole sealed package (every file and the manifest) into memory, verified. */
export async function loadSealedFiles(
  originals: OriginalsReader,
  pkg: PackageRow,
  files: readonly FileRow[],
): Promise<Map<string, Uint8Array>> {
  const verified = requireVerified(files);
  const map = new Map<string, Uint8Array>();
  for (const file of verified) {
    map.set(
      file.path,
      await readVerified(originals, {
        path: file.path,
        blobName: file.blob_name,
        sha256: file.sha256,
        bytes: file.bytes,
      }),
    );
  }
  map.set(manifestPath(pkg.visit_id), await readManifest(originals, pkg));
  return map;
}
