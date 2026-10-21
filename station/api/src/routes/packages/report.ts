// Short-lived read-only link to the station's spatial report of a package's current verdict
// (OpenAPI getSpatialReportLink, GET /v1/packages/{packageId}/spatial-report, bim and admin).
//
// The worker renders the report after the checks, stores the PDF in the reports container
// (STORAGE_REPORTS_CONTAINER) and records it in spatial_reports (migration 0010). The link is a
// read-only SAS for that one blob, valid for 10 minutes, signed like file download links
// (download.ts). 404 report_not_ready while there is no report row, or the row belongs to an
// older verdict, or the package has no current verdict. Every link handed out is audited
// (report.download_link); the URL never is.

import type { FastifyRequest } from "fastify";
import { audit } from "../../core/audit.js";
import { ProblemError } from "../../core/problem.js";
import { toApiDateTime } from "../../core/time.js";
import { DOWNLOAD_ROLES, readLinkSignerFromConfig, type ReadLinkSigner } from "./download.js";
import { isContractUuid } from "./schemas.js";

declare module "../../core/services.js" {
  interface StationServices {
    /** Read-only SAS signer for the reports container (tests inject one). */
    reportLinks: ReadLinkSigner;
  }
}

/** OpenAPI components.schemas.SpatialReportLink. */
export interface SpatialReportLink {
  readonly verdictId: string;
  readonly name: string;
  readonly sha256: string;
  readonly bytes: number;
  readonly pages: number;
  readonly checksPage: number;
  readonly generatedAt: string;
  /** Read-only SAS URL. A secret: never log or audit it. */
  readonly url: string;
  readonly expiresAt: string;
}

interface ReportRow {
  status: string;
  current_verdict_id: string | null;
  verdict_id: string | null;
  file_name: string | null;
  blob_name: string | null;
  sha256: string | null;
  bytes: number | null;
  pages: number | null;
  checks_page: number | null;
  generated_at: Date | null;
}

/** The injected reports signer, or one created from config on first use. */
export function reportSigner(request: FastifyRequest): ReadLinkSigner {
  const services = request.server.services as { reportLinks?: ReadLinkSigner };
  const config = request.server.config;
  services.reportLinks ??= readLinkSignerFromConfig(
    config,
    undefined,
    config.storage.reportsContainer,
  );
  return services.reportLinks;
}

/** Hands the signed-in bim/admin caller a link to the current spatial report and audits it. */
export async function issueSpatialReportLink(
  request: FastifyRequest,
  packageId: string,
): Promise<SpatialReportLink> {
  const principal = request.principal;
  if (principal === null || !principal.roles.some((role) => DOWNLOAD_ROLES.includes(role))) {
    throw new ProblemError(403, "forbidden", {
      detail: `This operation requires one of the roles: ${DOWNLOAD_ROLES.join(", ")}.`,
    });
  }
  if (!isContractUuid(packageId)) {
    throw new ProblemError(404, "not_found", { detail: "No package with this id." });
  }
  const result = await request.server.db.query<ReportRow>(
    `SELECT p.status, v.verdict_id AS current_verdict_id, sr.verdict_id, sr.file_name,
            sr.blob_name, sr.sha256, sr.bytes, sr.pages, sr.checks_page, sr.generated_at
       FROM packages p
       LEFT JOIN verdicts v ON v.package_id = p.package_id
       LEFT JOIN spatial_reports sr ON sr.package_id = p.package_id
      WHERE p.package_id = $1`,
    [packageId],
  );
  const row = result.rows[0];
  if (row === undefined) {
    throw new ProblemError(404, "not_found", { detail: "No package with this id." });
  }
  if (
    row.status !== "verdict_ready" ||
    row.current_verdict_id === null ||
    row.verdict_id !== row.current_verdict_id ||
    row.file_name === null ||
    row.blob_name === null ||
    row.sha256 === null ||
    row.bytes === null ||
    row.pages === null ||
    row.checks_page === null ||
    row.generated_at === null
  ) {
    throw new ProblemError(404, "report_not_ready", {
      detail: "The station has no spatial report for the package's current verdict yet.",
    });
  }
  const link = await reportSigner(request).signRead(row.blob_name, { fileName: row.file_name });
  const expiresAt = toApiDateTime(link.expiresAt);
  await audit(
    request,
    "report.download_link",
    { type: "package", id: packageId },
    { verdictId: row.verdict_id, name: row.file_name, expiresAt },
  );
  return {
    verdictId: row.verdict_id,
    name: row.file_name,
    sha256: row.sha256,
    bytes: row.bytes,
    pages: row.pages,
    checksPage: row.checks_page,
    generatedAt: toApiDateTime(row.generated_at),
    url: link.url,
    expiresAt,
  };
}
