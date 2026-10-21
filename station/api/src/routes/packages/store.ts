// Registry reads for the package routes, and the mapping from rows to the OpenAPI shapes
// (PackageSummary, Package, PackageFile, VerdictSummary, OpenAPI 1.1.0). Every package body the
// station sends (package routes, seal, review lists) is built here from one summary query, so
// the phone and the web see the same values. Optional fields are omitted, never null;
// timestamps are contract DateTimes.
//
// Where each 1.1.0 summary field comes from:
// - updatedAt: the latest change of the package row, its files, verdict, HUB publication or
//   spatial report.
// - createdBy, visitedAt, operatorName, captures: the session (created_by_name) and, once
//   sealed, the capture record; before the seal, captures in order of first appearance in
//   path order.
// - totals: the declared files and the verified ones.
// - checks: by package status (queued, running, completed, failed), with the times of the
//   latest check run (or of the running checks job) and the number of rules of a completed run.
// - publication: hub_publications (or pending while only the publish job is queued); hubFolder
//   is always Capture/{visitId}/r{revision}.
// - report: spatial_reports of the current verdict (ready; floors cut to the ReportFloor
//   fields), the current verdict's failed publication (failed), else pending; omitted before a
//   verdict.
// - links: REVIEW_BASE_URL and HUB_WEB_DEAL_URL_TEMPLATE (omitted while REVIEW_BASE_URL is unset).
// HUB file states (PackageFile.hub, manifestFile.hub, report.hub) come from the entries the
// publisher recorded in hub_publications.files: a recorded entry is a file in the HUB.

import { type Queryable } from "../../core/db.js";
import { DEAL_ID_PLACEHOLDER, type StationConfig } from "../../core/config.js";
import { toApiDateTime } from "../../core/time.js";
import { manifestPath } from "../../storage/originals.js";

export type PackageStatus =
  "uploading" | "checks_queued" | "checking" | "verdict_ready" | "check_error";

export type FileStatus =
  "pending" | "verified" | "sha256_mismatch" | "bytes_mismatch" | "not_uploaded";

export interface VerdictSummary {
  verdictId: string;
  outcome: "ready" | "limited" | "blocked";
  evaluatedAt: string;
}

export interface PackageCapture {
  captureId: string;
  areaKey: string;
  label?: string;
  mode?: "room" | "floor" | "exterior";
}

export interface PackageTotals {
  files: number;
  bytes: number;
  filesVerified: number;
  bytesVerified: number;
}

export interface CheckRunSummary {
  status: "queued" | "running" | "completed" | "failed";
  startedAt?: string;
  finishedAt?: string;
  rules?: number;
}

export type PublicationStatus = "pending" | "publishing" | "published" | "publish_failed";

export interface PublicationSummary {
  status: PublicationStatus;
  publishedAt?: string;
  hubFolder: string;
}

export interface HubFileState {
  state: "uploaded" | "linked";
  reason?: "too_large" | "not_published";
}

export interface ReportFloor {
  captureId: string;
  areaKey: string;
  roomsScanned: number;
  roomsUnlabeled: number;
  floorAreaSqFt: number;
}

export interface ReportSummary {
  status: "pending" | "ready" | "failed";
  generatedAt?: string;
  pages?: number;
  bytes?: number;
  sha256?: string;
  checksPage?: number;
  floors?: ReportFloor[];
  hub?: HubFileState;
}

export interface PackageLinks {
  review: string;
  hub?: string;
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
  updatedAt: string;
  createdBy?: { name: string };
  visitedAt?: string;
  operatorName?: string;
  captures: PackageCapture[];
  totals: PackageTotals;
  checks?: CheckRunSummary;
  publication?: PublicationSummary;
  report?: ReportSummary;
  links?: PackageLinks;
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
  generator?: string;
  generatorVersion?: string;
  carriedOverFrom?: string;
  hub?: HubFileState;
}

export interface ManifestFile {
  path: string;
  sha256: string;
  bytes: number;
  hub?: HubFileState;
}

export interface NextRevisionChange {
  kind: "added" | "changed" | "removed";
  subject: "capture" | "room_names" | "field_control" | "photos" | "retired_file";
  title: string;
  detail: string;
  answersNextAction?: string;
  method?: "tape" | "laser";
}

export interface NextRevisionNotice {
  revision: number;
  updatedAt: string;
  updatedBy?: string;
  changes: NextRevisionChange[];
}

export interface PackageDetail extends PackageSummary {
  files: PackageFile[];
  manifest?: Record<string, unknown>;
  manifestFile?: ManifestFile;
  captureRecord?: Record<string, unknown>;
  fieldControls?: Record<string, unknown>;
  nextRevision?: NextRevisionNotice;
}

/** The web pages a package links to, from config.links. */
export type LinkSettings = StationConfig["links"];

/** One entry of hub_publications.files, as the publisher records it (station/hub store.ts). */
interface PublishedFileEntry {
  kind?: unknown;
  path?: unknown;
  role?: unknown;
  reason?: unknown;
  verdictId?: unknown;
}

/** Role of the spatial report's entry in hub_publications.files. */
export const SPATIAL_REPORT_HUB_ROLE = "spatial_report";
/** Role of the manifest's entry in hub_publications.files. */
export const MANIFEST_HUB_ROLE = "manifest";

export interface SummaryRow {
  package_id: string;
  visit_id: string;
  deal_id: string;
  revision: number;
  supersedes_package_id: string | null;
  status: PackageStatus;
  created_at: Date;
  sealed_at: Date | null;
  updated_at: Date;
  created_by_name: string | null;
  visited_at: string | null;
  operator_name: string | null;
  record_captures: unknown;
  file_captures: { captureId: string; areaKey: string }[];
  files: number;
  bytes: number;
  files_verified: number;
  bytes_verified: number;
  verdict_id: string | null;
  outcome: VerdictSummary["outcome"] | null;
  evaluated_at: Date | null;
  run_status: "running" | "completed" | "failed" | null;
  run_started_at: Date | null;
  run_finished_at: Date | null;
  run_rules: number | null;
  checks_job_locked_at: Date | null;
  publish_queued: boolean;
  publication_status: PublicationStatus | null;
  publication_verdict_id: string | null;
  published_at: Date | null;
  report_verdict_id: string | null;
  report_generated_at: Date | null;
  report_pages: number | null;
  report_bytes: number | null;
  report_sha256: string | null;
  report_checks_page: number | null;
  /** spatial_reports.floors as the worker wrote it (a JSON array; see reportFloors). */
  report_floors: unknown;
  report_hub: PublishedFileEntry | null;
}

/**
 * FROM clause of the summary query: packages p with the joins that updatedAt needs. Shared
 * with the review lists so "most recent change" means the same everywhere.
 */
export const PACKAGE_FROM = `
  packages p
  LEFT JOIN verdicts v ON v.package_id = p.package_id
  LEFT JOIN hub_publications pub ON pub.package_id = p.package_id
  LEFT JOIN spatial_reports sr ON sr.package_id = p.package_id
  LEFT JOIN LATERAL (
    SELECT count(*) AS files,
           COALESCE(sum(f.bytes), 0)::bigint AS bytes,
           count(*) FILTER (WHERE f.status = 'verified') AS files_verified,
           COALESCE(sum(f.bytes) FILTER (WHERE f.status = 'verified'), 0)::bigint AS bytes_verified,
           max(f.updated_at) AS updated_at
      FROM package_files f
     WHERE f.package_id = p.package_id
  ) totals ON true`;

/** Last change of a package (row, files, verdict, publication, report); needs PACKAGE_FROM. */
export const PACKAGE_UPDATED_AT = `
  GREATEST(p.updated_at, totals.updated_at, v.updated_at, pub.updated_at, sr.updated_at)`;

/** Newest first: the order of every package list. */
export const NEWEST_FIRST = "p.created_at DESC, p.revision DESC, p.package_id";

const SUMMARY_SELECT = `
  SELECT p.package_id, p.visit_id, p.deal_id, p.revision, p.supersedes_package_id, p.status,
         p.created_at, p.sealed_at, p.created_by_name,
         ${PACKAGE_UPDATED_AT} AS updated_at,
         p.capture_record ->> 'visitedAt' AS visited_at,
         p.capture_record -> 'operator' ->> 'name' AS operator_name,
         p.capture_record -> 'captures' AS record_captures,
         file_captures.captures AS file_captures,
         totals.files, totals.bytes, totals.files_verified, totals.bytes_verified,
         v.verdict_id, v.outcome, v.evaluated_at,
         run.status AS run_status, run.started_at AS run_started_at,
         run.finished_at AS run_finished_at, run.rules AS run_rules,
         checks_job.locked_at AS checks_job_locked_at,
         publish_job.queued IS TRUE AS publish_queued,
         pub.status AS publication_status, pub.verdict_id AS publication_verdict_id,
         pub.published_at,
         sr.verdict_id AS report_verdict_id, sr.generated_at AS report_generated_at,
         sr.pages AS report_pages, sr.bytes AS report_bytes, sr.sha256 AS report_sha256,
         sr.checks_page AS report_checks_page, sr.floors AS report_floors,
         report_hub.entry AS report_hub
    FROM ${PACKAGE_FROM}
    LEFT JOIN LATERAL (
      SELECT COALESCE(
               jsonb_agg(jsonb_build_object('captureId', c.capture_id, 'areaKey', c.area_key)
                         ORDER BY c.first_path COLLATE "C"),
               '[]'::jsonb) AS captures
        FROM (SELECT f.capture_id, f.area_key, min(f.path::text COLLATE "C") AS first_path
                FROM package_files f
               WHERE f.package_id = p.package_id AND f.capture_id IS NOT NULL
               GROUP BY f.capture_id, f.area_key) c
    ) file_captures ON true
    LEFT JOIN LATERAL (
      SELECT r.status, r.started_at, r.finished_at,
             (SELECT count(*) FROM check_results cr WHERE cr.run_id = r.run_id) AS rules
        FROM check_runs r
       WHERE r.package_id = p.package_id
       ORDER BY r.started_at DESC, r.run_id
       LIMIT 1
    ) run ON true
    LEFT JOIN LATERAL (
      SELECT j.locked_at
        FROM jobs j
       WHERE j.package_id = p.package_id AND j.type = 'checks' AND j.status = 'running'
       LIMIT 1
    ) checks_job ON true
    LEFT JOIN LATERAL (
      SELECT true AS queued FROM jobs j
       WHERE j.package_id = p.package_id AND j.type = 'publish'
       LIMIT 1
    ) publish_job ON true
    LEFT JOIN LATERAL (
      SELECT e AS entry
        FROM jsonb_array_elements(pub.files) e
       WHERE e ->> 'role' = '${SPATIAL_REPORT_HUB_ROLE}' AND e ->> 'verdictId' = v.verdict_id::text
       ORDER BY e ->> 'kind' DESC
       LIMIT 1
    ) report_hub ON true`;

/**
 * Summary rows of the packages matching where (SQL over p, with its own $n parameters), in
 * order, at most limit rows when given.
 */
export async function selectSummaryRows(
  db: Queryable,
  where: string,
  params: readonly unknown[],
  order: string = NEWEST_FIRST,
  limit?: number,
): Promise<SummaryRow[]> {
  const limited = limit !== undefined;
  const result = await db.query<SummaryRow>(
    `${SUMMARY_SELECT}
      WHERE ${where}
      ORDER BY ${order}
      ${limited ? `LIMIT $${params.length + 1}` : ""}`,
    limited ? [...params, limit] : params,
  );
  return result.rows;
}

/** Capture-record captures, or undefined when the record has none in the expected shape. */
function recordCaptures(value: unknown): PackageCapture[] | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }
  return value.flatMap((item: unknown) => {
    if (item === null || typeof item !== "object") {
      return [];
    }
    const capture = item as Record<string, unknown>;
    if (typeof capture.captureId !== "string" || typeof capture.areaKey !== "string") {
      return [];
    }
    return [
      {
        captureId: capture.captureId,
        areaKey: capture.areaKey,
        ...(typeof capture.label === "string" ? { label: capture.label } : {}),
        ...(capture.mode === "room" || capture.mode === "floor" || capture.mode === "exterior"
          ? { mode: capture.mode }
          : {}),
      },
    ];
  });
}

function isCount(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 0;
}

/**
 * The ReportFloors of spatial_reports.floors: each floor with exactly the five contract fields
 * (other keys are dropped); a floor without them in the expected shape is left out, so one bad
 * row never breaks a package body.
 */
export function reportFloors(value: unknown): ReportFloor[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.flatMap((item: unknown) => {
    if (item === null || typeof item !== "object") {
      return [];
    }
    const floor = item as Record<string, unknown>;
    if (
      typeof floor.captureId !== "string" ||
      typeof floor.areaKey !== "string" ||
      !isCount(floor.roomsScanned) ||
      !isCount(floor.roomsUnlabeled) ||
      typeof floor.floorAreaSqFt !== "number" ||
      !Number.isFinite(floor.floorAreaSqFt) ||
      floor.floorAreaSqFt < 0
    ) {
      return [];
    }
    return [
      {
        captureId: floor.captureId,
        areaKey: floor.areaKey,
        roomsScanned: floor.roomsScanned,
        roomsUnlabeled: floor.roomsUnlabeled,
        floorAreaSqFt: floor.floorAreaSqFt,
      },
    ];
  });
}

function hubStateOf(entry: PublishedFileEntry | null | undefined): HubFileState | undefined {
  if (entry === null || entry === undefined) {
    return undefined;
  }
  if (entry.kind === "uploaded") {
    return { state: "uploaded" };
  }
  if (entry.kind === "linked") {
    return entry.reason === "too_large" || entry.reason === "not_published"
      ? { state: "linked", reason: entry.reason }
      : { state: "linked" };
  }
  return undefined;
}

/** Visit-wide HUB folder of a revision (station/hub plan.ts visitFolder). */
export function hubFolderOf(visitId: string, revision: number): string {
  return `Capture/${visitId}/r${revision}`;
}

/** PackageLinks of a package, or undefined while REVIEW_BASE_URL is not configured. */
export function linksOf(
  links: LinkSettings,
  packageId: string,
  dealId: string,
): PackageLinks | undefined {
  if (links.reviewBaseUrl === undefined) {
    return undefined;
  }
  const review = `${links.reviewBaseUrl.replace(/\/+$/, "")}/packages/${packageId}`;
  return links.hubDealUrlTemplate === undefined
    ? { review }
    : {
        review,
        hub: links.hubDealUrlTemplate.split(DEAL_ID_PLACEHOLDER).join(encodeURIComponent(dealId)),
      };
}

function verdictOf(row: SummaryRow): VerdictSummary | undefined {
  // Present only when status is verdict_ready (a stale verdict row of a package whose checks
  // are running again is not shown).
  if (
    row.status !== "verdict_ready" ||
    row.verdict_id === null ||
    row.outcome === null ||
    row.evaluated_at === null
  ) {
    return undefined;
  }
  return {
    verdictId: row.verdict_id,
    outcome: row.outcome,
    evaluatedAt: toApiDateTime(row.evaluated_at),
  };
}

/** Start and finish of the latest check run when it has this status. */
function runTimes(row: SummaryRow, status: "completed" | "failed"): Partial<CheckRunSummary> {
  if (row.run_status !== status || row.run_started_at === null) {
    return {};
  }
  return {
    startedAt: toApiDateTime(row.run_started_at),
    ...(row.run_finished_at === null ? {} : { finishedAt: toApiDateTime(row.run_finished_at) }),
  };
}

function checksOf(
  row: SummaryRow,
  verdict: VerdictSummary | undefined,
): CheckRunSummary | undefined {
  switch (row.status) {
    case "uploading":
      return undefined;
    case "checks_queued":
      return { status: "queued" };
    case "checking": {
      // The worker records a run when it ends; while it runs, the claimed job has the start.
      const startedAt =
        row.checks_job_locked_at ?? (row.run_status === "running" ? row.run_started_at : null);
      return startedAt === null
        ? { status: "running" }
        : { status: "running", startedAt: toApiDateTime(startedAt) };
    }
    case "verdict_ready": {
      const times = runTimes(row, "completed");
      if (times.finishedAt === undefined) {
        return verdict === undefined
          ? { status: "completed" }
          : { status: "completed", finishedAt: verdict.evaluatedAt };
      }
      return {
        status: "completed",
        ...times,
        ...(row.run_rules === null ? {} : { rules: row.run_rules }),
      };
    }
    case "check_error":
      return { status: "failed", ...runTimes(row, "failed") };
  }
}

function publicationOf(row: SummaryRow): PublicationSummary | undefined {
  const hubFolder = hubFolderOf(row.visit_id, row.revision);
  if (row.publication_status !== null) {
    return {
      status: row.publication_status,
      ...(row.publication_status === "published" && row.published_at !== null
        ? { publishedAt: toApiDateTime(row.published_at) }
        : {}),
      hubFolder,
    };
  }
  return row.publish_queued ? { status: "pending", hubFolder } : undefined;
}

function reportOf(row: SummaryRow, verdict: VerdictSummary | undefined): ReportSummary | undefined {
  if (verdict === undefined) {
    return undefined;
  }
  if (
    row.report_verdict_id === verdict.verdictId &&
    row.report_generated_at !== null &&
    row.report_pages !== null &&
    row.report_bytes !== null &&
    row.report_sha256 !== null &&
    row.report_checks_page !== null &&
    row.report_floors !== null
  ) {
    const hub = hubStateOf(row.report_hub);
    return {
      status: "ready",
      generatedAt: toApiDateTime(row.report_generated_at),
      pages: row.report_pages,
      bytes: row.report_bytes,
      sha256: row.report_sha256,
      checksPage: row.report_checks_page,
      floors: reportFloors(row.report_floors),
      ...(hub === undefined ? {} : { hub }),
    };
  }
  const failed =
    row.publication_status === "publish_failed" &&
    (row.publication_verdict_id === null || row.publication_verdict_id === verdict.verdictId);
  return { status: failed ? "failed" : "pending" };
}

/** The OpenAPI PackageSummary of a summary row. */
export function toSummary(row: SummaryRow, links: LinkSettings): PackageSummary {
  const verdict = verdictOf(row);
  const checks = checksOf(row, verdict);
  const publication = publicationOf(row);
  const report = reportOf(row, verdict);
  const packageLinks = linksOf(links, row.package_id, row.deal_id);
  return {
    packageId: row.package_id,
    visitId: row.visit_id,
    dealId: row.deal_id,
    revision: row.revision,
    ...(row.supersedes_package_id === null
      ? {}
      : { supersedesPackageId: row.supersedes_package_id }),
    status: row.status,
    createdAt: toApiDateTime(row.created_at),
    ...(row.sealed_at === null ? {} : { sealedAt: toApiDateTime(row.sealed_at) }),
    updatedAt: toApiDateTime(row.updated_at),
    ...(row.created_by_name === null ? {} : { createdBy: { name: row.created_by_name } }),
    ...(row.visited_at === null ? {} : { visitedAt: row.visited_at }),
    ...(row.operator_name === null ? {} : { operatorName: row.operator_name }),
    captures: recordCaptures(row.record_captures) ?? row.file_captures,
    totals: {
      files: row.files,
      bytes: row.bytes,
      filesVerified: row.files_verified,
      bytesVerified: row.bytes_verified,
    },
    ...(checks === undefined ? {} : { checks }),
    ...(publication === undefined ? {} : { publication }),
    ...(report === undefined ? {} : { report }),
    ...(packageLinks === undefined ? {} : { links: packageLinks }),
    ...(verdict === undefined ? {} : { verdict }),
  };
}

/** Packages of a deal (optionally one visit), newest first. */
export async function listPackages(
  db: Queryable,
  links: LinkSettings,
  dealId: string,
  visitId: string | undefined,
): Promise<PackageSummary[]> {
  const rows = await selectSummaryRows(
    db,
    "p.deal_id = $1 AND ($2::uuid IS NULL OR p.visit_id = $2::uuid)",
    [dealId, visitId ?? null],
  );
  return rows.map((row) => toSummary(row, links));
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
  carried_over_from: string | null;
}

interface DetailRow {
  manifest: Record<string, unknown> | null;
  manifest_sha256: string | null;
  manifest_bytes: number | null;
  capture_record: Record<string, unknown> | null;
  field_controls: Record<string, unknown> | null;
  session_request: { files?: { path: string }[] };
  publication_files: PublishedFileEntry[] | null;
  notice: Omit<NextRevisionNotice, "updatedBy"> | null;
  notice_updated_by: string | null;
}

/** Manifest entry fields the station exposes on PackageFile. */
function manifestEntries(
  manifest: Record<string, unknown> | null,
): Map<string, { generator?: unknown; generatorVersion?: unknown }> {
  const files = manifest?.files;
  if (!Array.isArray(files)) {
    return new Map();
  }
  return new Map(
    files.flatMap((entry: unknown) =>
      entry !== null &&
      typeof entry === "object" &&
      typeof (entry as { path?: unknown }).path === "string"
        ? [
            [
              (entry as { path: string }).path,
              entry as { generator?: unknown; generatorVersion?: unknown },
            ],
          ]
        : [],
    ),
  );
}

/** HUB state per package path (an upload wins over a link of the same path). */
function hubStatesByPath(entries: readonly PublishedFileEntry[]): Map<string, HubFileState> {
  const states = new Map<string, HubFileState>();
  for (const entry of entries) {
    const state = hubStateOf(entry);
    if (typeof entry.path !== "string" || state === undefined) {
      continue;
    }
    if (states.get(entry.path)?.state !== "uploaded") {
      states.set(entry.path, state);
    }
  }
  return states;
}

function toFile(
  row: FileRow,
  entry: { generator?: unknown; generatorVersion?: unknown } | undefined,
  hub: HubFileState | undefined,
): PackageFile {
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
  if (typeof entry?.generator === "string") {
    file.generator = entry.generator;
  }
  if (typeof entry?.generatorVersion === "string") {
    file.generatorVersion = entry.generatorVersion;
  }
  if (row.carried_over_from !== null) {
    file.carriedOverFrom = row.carried_over_from;
  }
  if (hub !== undefined) {
    file.hub = hub;
  }
  return file;
}

export interface GetPackageOptions {
  /** Order of files: path order (default) or the order the upload session declared them. */
  readonly fileOrder?: "path" | "declared";
}

/** One package with its files, or undefined when it does not exist. */
export async function getPackage(
  db: Queryable,
  links: LinkSettings,
  packageId: string,
  options: GetPackageOptions = {},
): Promise<PackageDetail | undefined> {
  const [summary] = await selectSummaryRows(db, "p.package_id = $1", [packageId]);
  if (summary === undefined) {
    return undefined;
  }
  const details = await db.query<DetailRow>(
    `SELECT p.manifest, p.manifest_sha256, p.manifest_bytes, p.capture_record, p.field_controls,
            p.session_request, pub.files AS publication_files,
            n.notice, n.updated_by_name AS notice_updated_by
       FROM packages p
       LEFT JOIN hub_publications pub ON pub.package_id = p.package_id
       LEFT JOIN next_revision_notices n ON n.package_id = p.package_id
      WHERE p.package_id = $1`,
    [packageId],
  );
  const detail = details.rows[0];
  if (detail === undefined) {
    return undefined;
  }
  const files = await db.query<FileRow>(
    `SELECT path, role, capture_id, area_key, sha256, bytes, status, checked_at, carried_over_from
       FROM package_files
      WHERE package_id = $1
      ORDER BY path COLLATE "C"`,
    [packageId],
  );
  let fileRows = files.rows;
  if (options.fileOrder === "declared") {
    const order = new Map(
      (detail.session_request.files ?? []).map((file, index) => [file.path, index]),
    );
    fileRows = [...fileRows].sort(
      (a, b) =>
        (order.get(a.path) ?? Number.MAX_SAFE_INTEGER) -
        (order.get(b.path) ?? Number.MAX_SAFE_INTEGER),
    );
  }

  const published = detail.publication_files ?? [];
  const hubByPath = hubStatesByPath(
    published.filter(
      (entry) => entry.role !== MANIFEST_HUB_ROLE && entry.role !== SPATIAL_REPORT_HUB_ROLE,
    ),
  );
  const entries = manifestEntries(detail.manifest);
  const result: PackageDetail = {
    ...toSummary(summary, links),
    files: fileRows.map((row) => toFile(row, entries.get(row.path), hubByPath.get(row.path))),
  };
  if (detail.manifest !== null) {
    result.manifest = detail.manifest;
  }
  if (detail.manifest_sha256 !== null && detail.manifest_bytes !== null) {
    const hub = hubStateOf(
      published.find((entry) => entry.role === MANIFEST_HUB_ROLE && entry.kind === "uploaded") ??
        published.find((entry) => entry.role === MANIFEST_HUB_ROLE),
    );
    result.manifestFile = {
      path: manifestPath(summary.visit_id),
      sha256: detail.manifest_sha256,
      bytes: detail.manifest_bytes,
      ...(hub === undefined ? {} : { hub }),
    };
  }
  if (detail.capture_record !== null) {
    result.captureRecord = detail.capture_record;
  }
  if (detail.field_controls !== null) {
    result.fieldControls = detail.field_controls;
  }
  if (detail.notice !== null) {
    result.nextRevision = noticeView(detail.notice, detail.notice_updated_by);
  }
  return result;
}

/** The OpenAPI NextRevisionNotice of a stored notice. */
export function noticeView(
  notice: Omit<NextRevisionNotice, "updatedBy">,
  updatedBy: string | null,
): NextRevisionNotice {
  return {
    revision: notice.revision,
    updatedAt: notice.updatedAt,
    ...(updatedBy === null ? {} : { updatedBy }),
    changes: notice.changes,
  };
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
