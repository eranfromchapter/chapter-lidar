// Station API bodies used by the review screen (contract/openapi/station.yaml components).
// Verdict, manifest and capture record come from @chapter/capture-contract; the API-only
// shapes below mirror the OpenAPI components of the same name.

import type {
  CaptureRecord,
  Outcome,
  PackageManifest,
  Role,
  Verdict,
} from "@chapter/capture-contract";

export type { CaptureRecord, Outcome, PackageManifest, Role, Verdict };

/** OpenAPI HubProject. */
export interface HubProject {
  dealId: string;
  projectName?: string;
  address: { formatted: string };
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

/** OpenAPI PackageSummary. */
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
}

/** OpenAPI Package. */
export interface StationPackage {
  packageId: string;
  visitId: string;
  dealId: string;
  revision: number;
  supersedesPackageId?: string;
  status: PackageStatus;
  createdAt: string;
  sealedAt?: string;
  files: PackageFile[];
  manifest?: PackageManifest;
  captureRecord?: CaptureRecord;
  verdict?: VerdictSummary;
}

/** OpenAPI DownloadLink. The url is a secret until it expires. */
export interface DownloadLink {
  path: string;
  sha256: string;
  bytes: number;
  url: string;
  expiresAt: string;
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

/** OpenAPI Problem (RFC 9457). */
export interface Problem {
  type?: string;
  title?: string;
  status?: number;
  detail?: string;
  code?: string;
  errors?: { pointer: string; message: string }[];
}
