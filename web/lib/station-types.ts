// Station API bodies used by the review screen (contract/openapi/station.yaml 1.1.0 components).
// Verdict, manifest, capture record and field controls come from @chapter/capture-contract; the
// API-only shapes below mirror the OpenAPI components of the same name. Optional fields are
// omitted by the station, never null.

import type {
  CaptureRecord,
  FieldControls,
  Outcome,
  PackageManifest,
  Role,
  Verdict,
} from "@chapter/capture-contract";

export type { CaptureRecord, FieldControls, Outcome, PackageManifest, Role, Verdict };

/** OpenAPI HubProject. */
export interface HubProject {
  dealId: string;
  projectName?: string;
  address: { formatted: string };
  /** The deal's project manager, when the HUB provides one. */
  projectManager?: { name: string; phone?: string };
}

/** OpenAPI PackageStatus. */
export type PackageStatus =
  "uploading" | "checks_queued" | "checking" | "verdict_ready" | "check_error";

/** OpenAPI FileStatus. */
export type FileStatus =
  "pending" | "verified" | "sha256_mismatch" | "bytes_mismatch" | "not_uploaded";

/** OpenAPI VerdictSummary. */
export interface VerdictSummary {
  verdictId: string;
  outcome: Outcome;
  evaluatedAt: string;
}

/** OpenAPI PackageCapture. */
export interface PackageCapture {
  captureId: string;
  areaKey: string;
  /** From the capture record, once sealed. */
  label?: string;
  /** From the capture record, once sealed. */
  mode?: "room" | "floor" | "exterior";
}

/** OpenAPI PackageTotals: all declared files and the verified ones. */
export interface PackageTotals {
  files: number;
  bytes: number;
  filesVerified: number;
  bytesVerified: number;
}

/** OpenAPI CheckRunSummary: the latest check run, omitted before the seal. */
export interface CheckRunSummary {
  status: "queued" | "running" | "completed" | "failed";
  startedAt?: string;
  finishedAt?: string;
  /** Rules run; present when completed. */
  rules?: number;
}

/** OpenAPI PublicationSummary: HUB publication of this revision. */
export interface PublicationSummary {
  status: "pending" | "publishing" | "published" | "publish_failed";
  publishedAt?: string;
  /** Capture/{visitId}/r{revision}. */
  hubFolder: string;
}

/** OpenAPI HubFileState: how a file appears in the HUB. */
export interface HubFileState {
  state: "uploaded" | "linked";
  reason?: "too_large" | "not_published";
}

/** OpenAPI ReportFloor: totals the spatial report computed for one floor or area. */
export interface ReportFloor {
  captureId: string;
  areaKey: string;
  roomsScanned: number;
  roomsUnlabeled: number;
  floorAreaSqFt: number;
}

/** OpenAPI ReportSummary: the station's spatial report of the current verdict. */
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

/** OpenAPI PackageLinks. */
export interface PackageLinks {
  review: string;
  /** The HUB page of the deal; omitted when the station has no HUB deal URL configured. */
  hub?: string;
}

/** OpenAPI PackageSummary (PackageSummaryFields). */
export interface PackageSummary {
  packageId: string;
  visitId: string;
  dealId: string;
  revision: number;
  supersedesPackageId?: string;
  status: PackageStatus;
  /** When the station registered the package (the upload session opened). */
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

/** OpenAPI PackageFile. */
export interface PackageFile {
  path: string;
  role: Role;
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

/** OpenAPI ManifestFile: the sealed manifest file. */
export interface ManifestFile {
  path: string;
  sha256: string;
  bytes: number;
  hub?: HubFileState;
}

/** OpenAPI NextRevisionChange: one row as the phone shows it. */
export interface NextRevisionChange {
  kind: "added" | "changed" | "removed";
  subject: "capture" | "room_names" | "field_control" | "photos" | "retired_file";
  title: string;
  detail: string;
  /** A next action of the base verdict, verbatim, that this change answers. */
  answersNextAction?: string;
  method?: "tape" | "laser";
}

/** OpenAPI NextRevisionNotice: the next revision as the phone last described it. */
export interface NextRevisionNotice {
  revision: number;
  updatedAt: string;
  updatedBy?: string;
  changes: NextRevisionChange[];
}

/** OpenAPI Package. */
export interface StationPackage extends PackageSummary {
  files: PackageFile[];
  manifest?: PackageManifest;
  manifestFile?: ManifestFile;
  captureRecord?: CaptureRecord;
  fieldControls?: FieldControls;
  nextRevision?: NextRevisionNotice;
}

/** OpenAPI DownloadLink. The url is a secret until it expires. */
export interface DownloadLink {
  path: string;
  sha256: string;
  bytes: number;
  url: string;
  expiresAt: string;
}

/** OpenAPI SpatialReportLink. The url is a secret until it expires. */
export interface SpatialReportLink {
  verdictId: string;
  name: string;
  sha256: string;
  bytes: number;
  pages: number;
  checksPage: number;
  generatedAt: string;
  url: string;
  expiresAt: string;
}

/** OpenAPI ReviewProject: a HUB project that has packages, with its newest package. */
export interface ReviewProject {
  dealId: string;
  projectName?: string;
  address: { formatted: string };
  packageCount: number;
  latest: PackageSummary;
}

/** OpenAPI ReviewPackage: a package summary with its project's name and address. */
export interface ReviewPackage extends PackageSummary {
  projectName?: string;
  address: { formatted: string };
}

/** A list page of the station (review lists, decisions across packages). */
export interface StationPage<T> {
  readonly items: T[];
  /** True when more match than the page holds. */
  readonly truncated: boolean;
}

/** OpenAPI DecisionSource. */
export interface DecisionSource {
  path: string;
  controlId?: string;
  elementId?: string;
}

/** OpenAPI ModelingDecisionInput. */
export interface ModelingDecisionInput {
  element: string;
  decision: string;
  captureId?: string;
  areaKey?: string;
  sources: DecisionSource[];
  note?: string;
}

/** OpenAPI ModelingDecision. */
export interface ModelingDecision extends ModelingDecisionInput {
  decisionId: string;
  packageId: string;
  decidedBy: { name: string; userId: string };
  decidedAt: string;
}

/** OpenAPI ModelingDecisionWithContext: a decision with its package's deal and revision. */
export interface ModelingDecisionWithContext extends ModelingDecision {
  dealId: string;
  revision: number;
}

/** OpenAPI Problem (RFC 9457). */
export interface Problem {
  type?: string;
  title?: string;
  status?: number;
  detail?: string;
  code?: string;
  errors?: { pointer: string; message: string }[];
}
