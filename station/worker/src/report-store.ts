// Stores the spatial report of a verdict for the web review: the PDF in the reports container
// (blob {packageId}/spatial-report-{verdictId}.pdf, written once) and its row in spatial_reports
// (station/db/migrations/0010: one row per package, a newer verdict replaces it; older blobs
// stay). Audited as report.store. Called by the publish job before anything goes to the HUB.
//
// The first report stored for a verdict is the report of that verdict. A later attempt of the
// same job renders the same bytes (the renderer is deterministic) unless the worker changed in
// between (a rolling deploy, another REPORT_TIME_ZONE): then the stored blob is never replaced;
// its bytes, as described by the verdict's spatial_reports row, are what the HUB gets too
// (audited as report.kept), so the web review and the HUB always hold the same file. Only a
// stored blob that no row of this verdict describes ends the job (report.conflict).

import { createHash } from "node:crypto";
import type { Verdict } from "@chapter/capture-contract";
import type { RenderedReport, ReportFloor } from "@chapter/station-hub";
import { auditPackage } from "./audit.js";
import { TerminalJobError, type WorkerContext } from "./context.js";
import { ReportConflictError } from "./storage.js";

/** Blob of a package's spatial report in the reports container. */
export function reportBlobName(packageId: string, fileName: string): string {
  return `${packageId}/${fileName}`;
}

/**
 * Stores `report` for `verdict` and returns the report the station keeps for that verdict:
 * `report` itself, or the one an earlier attempt stored (see above).
 */
export async function storeSpatialReport(
  ctx: Pick<WorkerContext, "db" | "reports" | "secrets">,
  packageId: string,
  report: RenderedReport,
  verdict: Verdict,
  jobId?: string,
): Promise<RenderedReport> {
  const blobName = reportBlobName(packageId, report.name);
  let stored: "created" | "exists";
  try {
    stored = await ctx.reports.write(blobName, report.bytes, report.sha256);
  } catch (error) {
    if (error instanceof ReportConflictError) {
      return keptReport(ctx, packageId, report, verdict, blobName, error, jobId);
    }
    throw error;
  }
  await ctx.db.transaction(async (tx) => {
    await tx.query(
      `INSERT INTO spatial_reports
         (package_id, verdict_id, file_name, blob_name, sha256, bytes, pages, checks_page, floors,
          generated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::timestamptz)
       ON CONFLICT (package_id) DO UPDATE SET
         verdict_id = EXCLUDED.verdict_id, file_name = EXCLUDED.file_name,
         blob_name = EXCLUDED.blob_name, sha256 = EXCLUDED.sha256, bytes = EXCLUDED.bytes,
         pages = EXCLUDED.pages, checks_page = EXCLUDED.checks_page, floors = EXCLUDED.floors,
         generated_at = EXCLUDED.generated_at`,
      [
        packageId,
        verdict.verdictId,
        report.name,
        blobName,
        report.sha256,
        report.bytes.byteLength,
        report.pages,
        report.checksPage,
        JSON.stringify(report.floors),
        verdict.evaluatedAt,
      ],
    );
    await auditPackage(
      tx,
      "report.store",
      packageId,
      {
        ...(jobId === undefined ? {} : { jobId }),
        verdictId: verdict.verdictId,
        name: report.name,
        sha256: report.sha256,
        bytes: report.bytes.byteLength,
        pages: report.pages,
        checksPage: report.checksPage,
        blob: stored,
      },
      ctx.secrets,
    );
  });
  return report;
}

interface KeptRow {
  readonly sha256: string;
  readonly bytes: string | number;
  readonly pages: number;
  readonly checks_page: number;
  readonly floors: ReportFloor[];
}

/** A different report is stored for the verdict: keep it when its row describes it. */
async function keptReport(
  ctx: Pick<WorkerContext, "db" | "reports" | "secrets">,
  packageId: string,
  report: RenderedReport,
  verdict: Verdict,
  blobName: string,
  conflict: ReportConflictError,
  jobId: string | undefined,
): Promise<RenderedReport> {
  const fail = (reason: string) =>
    new TerminalJobError(`${conflict.message} (${reason})`, "report.conflict", {
      verdictId: verdict.verdictId,
      blobName,
      renderedSha256: report.sha256,
      ...(conflict.storedSha256 === undefined ? {} : { storedSha256: conflict.storedSha256 }),
    });
  const result = await ctx.db.query<KeptRow>(
    `SELECT sha256, bytes, pages, checks_page, floors FROM spatial_reports
      WHERE package_id = $1 AND verdict_id = $2 AND blob_name = $3`,
    [packageId, verdict.verdictId, blobName],
  );
  const row = result.rows[0];
  if (row === undefined || row.sha256 !== conflict.storedSha256) {
    throw fail("no spatial_reports row of this verdict describes the stored report");
  }
  const bytes = Buffer.from(await ctx.reports.read(blobName));
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  if (sha256 !== row.sha256 || bytes.byteLength !== Number(row.bytes)) {
    throw fail("the stored report does not match its spatial_reports row");
  }
  await auditPackage(
    ctx.db,
    "report.kept",
    packageId,
    {
      ...(jobId === undefined ? {} : { jobId }),
      verdictId: verdict.verdictId,
      name: report.name,
      sha256,
      renderedSha256: report.sha256,
    },
    ctx.secrets,
  );
  return {
    ...report,
    bytes,
    sha256,
    pages: row.pages,
    checksPage: row.checks_page,
    floors: row.floors,
  };
}
