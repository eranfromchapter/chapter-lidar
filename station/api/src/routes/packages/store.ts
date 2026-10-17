// Registry reads for the package routes, and the mapping from rows to the OpenAPI shapes
// (PackageSummary, Package, PackageFile, VerdictSummary). Optional fields are omitted, never
// null; timestamps are contract DateTimes.

import type { Queryable } from "../../core/db.js";
import { toApiDateTime } from "../../core/time.js";

export type PackageStatus =
  "uploading" | "checks_queued" | "checking" | "verdict_ready" | "check_error";

export type FileStatus =
  "pending" | "verified" | "sha256_mismatch" | "bytes_mismatch" | "not_uploaded";

export interface VerdictSummary {
  verdictId: string;
  outcome: "ready" | "limited" | "blocked";
  evaluatedAt: string;
}

export interface PackageSummary {
  packageId: string;
  visitId: string;
  dealId: string;
  revision: number;
  supersedesPackageId?: string;
  status: PackageStatus;
  createdAt: string;
  sealedAt?: string;
  verdict?: VerdictSummary;
}

export interface PackageFile {
  path: string;
  role: string;
  captureId?: string;
  areaKey?: string;
  sha256: string;
  bytes: number;
  status: FileStatus;
  checkedAt?: string;
}

export interface PackageDetail extends PackageSummary {
  files: PackageFile[];
  manifest?: Record<string, unknown>;
  captureRecord?: Record<string, unknown>;
}

interface PackageRow {
  package_id: string;
  visit_id: string;
  deal_id: string;
  revision: number;
  supersedes_package_id: string | null;
  status: PackageStatus;
  created_at: Date;
  sealed_at: Date | null;
  verdict_id: string | null;
  outcome: VerdictSummary["outcome"] | null;
  evaluated_at: Date | null;
}

interface PackageDetailRow extends PackageRow {
  manifest: Record<string, unknown> | null;
  capture_record: Record<string, unknown> | null;
}

interface FileRow {
  path: string;
  role: string;
  capture_id: string | null;
  area_key: string | null;
  sha256: string;
  bytes: number;
  status: FileStatus;
  checked_at: Date | null;
}

const SUMMARY_COLUMNS = `
  p.package_id, p.visit_id, p.deal_id, p.revision, p.supersedes_package_id, p.status,
  p.created_at, p.sealed_at, v.verdict_id, v.outcome, v.evaluated_at`;

function toSummary(row: PackageRow): PackageSummary {
  const summary: PackageSummary = {
    packageId: row.package_id,
    visitId: row.visit_id,
    dealId: row.deal_id,
    revision: row.revision,
    status: row.status,
    createdAt: toApiDateTime(row.created_at),
  };
  if (row.supersedes_package_id !== null) {
    summary.supersedesPackageId = row.supersedes_package_id;
  }
  if (row.sealed_at !== null) {
    summary.sealedAt = toApiDateTime(row.sealed_at);
  }
  // The summary is present only when status is verdict_ready (a stale verdict row of a package
  // whose checks are running again is not shown).
  if (
    row.status === "verdict_ready" &&
    row.verdict_id !== null &&
    row.outcome !== null &&
    row.evaluated_at !== null
  ) {
    summary.verdict = {
      verdictId: row.verdict_id,
      outcome: row.outcome,
      evaluatedAt: toApiDateTime(row.evaluated_at),
    };
  }
  return summary;
}

function toFile(row: FileRow): PackageFile {
  const file: PackageFile = {
    path: row.path,
    role: row.role,
    sha256: row.sha256,
    bytes: row.bytes,
    status: row.status,
  };
  if (row.capture_id !== null) {
    file.captureId = row.capture_id;
  }
  if (row.area_key !== null) {
    file.areaKey = row.area_key;
  }
  if (row.checked_at !== null) {
    file.checkedAt = toApiDateTime(row.checked_at);
  }
  return file;
}

/** Packages of a deal (optionally one visit), newest first. */
export async function listPackages(
  db: Queryable,
  dealId: string,
  visitId: string | undefined,
): Promise<PackageSummary[]> {
  const result = await db.query<PackageRow>(
    `SELECT ${SUMMARY_COLUMNS}
       FROM packages p
       LEFT JOIN verdicts v ON v.package_id = p.package_id
      WHERE p.deal_id = $1 AND ($2::uuid IS NULL OR p.visit_id = $2::uuid)
      ORDER BY p.created_at DESC, p.revision DESC, p.package_id`,
    [dealId, visitId ?? null],
  );
  return result.rows.map(toSummary);
}

/** One package with its files (path order), or undefined when it does not exist. */
export async function getPackage(
  db: Queryable,
  packageId: string,
): Promise<PackageDetail | undefined> {
  const packages = await db.query<PackageDetailRow>(
    `SELECT ${SUMMARY_COLUMNS}, p.manifest, p.capture_record
       FROM packages p
       LEFT JOIN verdicts v ON v.package_id = p.package_id
      WHERE p.package_id = $1`,
    [packageId],
  );
  const row = packages.rows[0];
  if (row === undefined) {
    return undefined;
  }
  const files = await db.query<FileRow>(
    `SELECT path, role, capture_id, area_key, sha256, bytes, status, checked_at
       FROM package_files
      WHERE package_id = $1
      ORDER BY path COLLATE "C"`,
    [packageId],
  );
  const detail: PackageDetail = { ...toSummary(row), files: files.rows.map(toFile) };
  if (row.manifest !== null) {
    detail.manifest = row.manifest;
  }
  if (row.capture_record !== null) {
    detail.captureRecord = row.capture_record;
  }
  return detail;
}

export interface StoredVerdict {
  status: PackageStatus;
  /** The verdict document, when a verdict row exists. */
  document?: Record<string, unknown>;
}

/** Package status and verdict document, or undefined when the package does not exist. */
export async function getVerdict(
  db: Queryable,
  packageId: string,
): Promise<StoredVerdict | undefined> {
  const result = await db.query<{
    status: PackageStatus;
    document: Record<string, unknown> | null;
  }>(
    `SELECT p.status, v.document
       FROM packages p
       LEFT JOIN verdicts v ON v.package_id = p.package_id
      WHERE p.package_id = $1`,
    [packageId],
  );
  const row = result.rows[0];
  if (row === undefined) {
    return undefined;
  }
  return row.document === null
    ? { status: row.status }
    : { status: row.status, document: row.document };
}

/** True when the package exists. */
export async function packageExists(db: Queryable, packageId: string): Promise<boolean> {
  const result = await db.query("SELECT 1 FROM packages WHERE package_id = $1", [packageId]);
  return (result.rowCount ?? 0) > 0;
}
