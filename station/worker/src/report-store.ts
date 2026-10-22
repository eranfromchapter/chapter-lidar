// Stores the spatial report of a verdict for the web review: the PDF in the reports container
// (blob {packageId}/spatial-report-{verdictId}.pdf, written once) and its row in spatial_reports
// (station/db/migrations/0010: one row per package, a newer verdict replaces it; older blobs
// stay). Audited as report.store. Called by the publish job before anything goes to the HUB.

import type { Verdict } from "@chapter/capture-contract";
import type { RenderedReport } from "@chapter/station-hub";
import { auditPackage } from "./audit.js";
import { TerminalJobError, type WorkerContext } from "./context.js";
import { ReportConflictError } from "./storage.js";

/** Blob of a package's spatial report in the reports container. */
export function reportBlobName(packageId: string, fileName: string): string {
  return `${packageId}/${fileName}`;
}

export async function storeSpatialReport(
  ctx: Pick<WorkerContext, "db" | "reports" | "secrets">,
  packageId: string,
  report: RenderedReport,
  verdict: Verdict,
  jobId?: string,
): Promise<void> {
  const blobName = reportBlobName(packageId, report.name);
  let stored: "created" | "exists";
  try {
    stored = await ctx.reports.write(blobName, report.bytes, report.sha256);
  } catch (error) {
    if (error instanceof ReportConflictError) {
      throw new TerminalJobError(error.message, "report.conflict", {
        verdictId: verdict.verdictId,
        blobName,
      });
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
}
