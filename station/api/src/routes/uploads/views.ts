// Registry rows of packages and package files as the upload routes read them, and the
// FileCheckResult shape (contract/openapi/station.yaml). The Package bodies the upload routes
// answer with are built by routes/packages/store.ts, like every other package body. Optional
// fields are omitted, never null.

import type { Queryable } from "../../core/db.js";
import { toApiDateTime } from "../../core/time.js";
import type { UploadFileDeclaration, UploadSessionRequest } from "./schemas.js";

export type PackageStatus =
  "uploading" | "checks_queued" | "checking" | "verdict_ready" | "check_error";
export type FileStatus =
  "pending" | "verified" | "sha256_mismatch" | "bytes_mismatch" | "not_uploaded";

export interface PackageRow {
  package_id: string;
  visit_id: string;
  deal_id: string;
  revision: number;
  supersedes_package_id: string | null;
  status: PackageStatus;
  session_request: UploadSessionRequest;
  created_at: Date;
  sealed_at: Date | null;
  manifest: Record<string, unknown> | null;
  capture_record: Record<string, unknown> | null;
}

export interface FileRow {
  path: string;
  role: UploadFileDeclaration["role"];
  capture_id: string | null;
  area_key: string | null;
  sha256: string;
  bytes: number;
  status: FileStatus;
  actual_sha256: string | null;
  actual_bytes: number | null;
  checked_at: Date | null;
  verified_at: Date | null;
  blob_name: string | null;
  /** The superseded package whose verified file this one reuses (carry-over). */
  carried_over_from: string | null;
}

export const PACKAGE_COLUMNS = `
  p.package_id, p.visit_id, p.deal_id, p.revision, p.supersedes_package_id, p.status,
  p.session_request, p.created_at, p.sealed_at, p.manifest, p.capture_record`;

export const FILE_COLUMNS = `
  path, role, capture_id, area_key, sha256, bytes, status, actual_sha256, actual_bytes,
  checked_at, verified_at, blob_name, carried_over_from`;

/** The package row or undefined. */
export async function selectPackage(
  db: Queryable,
  packageId: string,
): Promise<PackageRow | undefined> {
  const result = await db.query<PackageRow>(
    `SELECT ${PACKAGE_COLUMNS} FROM packages p WHERE p.package_id = $1`,
    [packageId],
  );
  return result.rows[0];
}

export async function selectFiles(db: Queryable, packageId: string): Promise<FileRow[]> {
  const result = await db.query<FileRow>(
    `SELECT ${FILE_COLUMNS} FROM package_files WHERE package_id = $1`,
    [packageId],
  );
  return result.rows;
}

/** Files in the order the upload session declared them. */
export function inDeclaredOrder(row: PackageRow, files: readonly FileRow[]): FileRow[] {
  const order = new Map(row.session_request.files.map((file, index) => [file.path, index]));
  return [...files].sort(
    (a, b) =>
      (order.get(a.path) ?? Number.MAX_SAFE_INTEGER) -
      (order.get(b.path) ?? Number.MAX_SAFE_INTEGER),
  );
}

export function declarationOf(file: FileRow): UploadFileDeclaration {
  return {
    path: file.path,
    role: file.role,
    ...(file.capture_id === null ? {} : { captureId: file.capture_id }),
    ...(file.area_key === null ? {} : { areaKey: file.area_key }),
    sha256: file.sha256,
    bytes: file.bytes,
  };
}

export function fileCheckResultView(file: FileRow): Record<string, unknown> {
  if (file.checked_at === null) {
    throw new Error("file check result requested for a file that was never checked");
  }
  return {
    path: file.path,
    status: file.status,
    expectedSha256: file.sha256,
    ...(file.actual_sha256 === null ? {} : { actualSha256: file.actual_sha256 }),
    expectedBytes: file.bytes,
    ...(file.actual_bytes === null ? {} : { actualBytes: file.actual_bytes }),
    checkedAt: toApiDateTime(file.checked_at),
  };
}
