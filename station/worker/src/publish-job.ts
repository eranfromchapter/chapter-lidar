// publish job: puts the package's current verdict into the HUB through HubPublisher, with the
// station's spatial report of that verdict (rendered by the publisher, stored here for the web
// review in the reports container and spatial_reports before anything is uploaded).
//
// The HUB-level retries (5 attempts with exponential backoff, then publish_failed) happen inside
// HubPublisher while this job holds its lock. The job ends succeeded when the publication is
// published, failed when it is publish_failed. When the checks ran again while publishing and
// stored a newer verdict, the job requeues itself (without spending an attempt) so the newer
// verdict is published too.

import {
  validateCaptureRecord,
  validateVerdict,
  type CaptureRecord,
  type Role,
  type Verdict,
} from "@chapter/capture-contract";
import {
  HubPublisher,
  scrub,
  type PackageFileRecord,
  type PublishPackage,
  type PublishRequest,
} from "@chapter/station-hub";
import { auditPackage } from "./audit.js";
import { storeSpatialReport } from "./report-store.js";
import { TerminalJobError, errorText, type WorkerContext } from "./context.js";
import {
  readManifest,
  readVerified,
  requireVerified,
  selectFiles,
  selectPackage,
} from "./package.js";
import { PgPublicationStore, markPublicationFailed } from "./publication-store.js";
import { LeaseLostError, finishJob, requeueJob, retryDelaySeconds, type Lease } from "./queue.js";
import { manifestPath } from "./storage.js";

const DIRECTIONS = new Set(["N", "E", "S", "W"]);
const SUBJECTS = new Set([
  "opening",
  "cabinetry",
  "ceiling",
  "fixture",
  "equipment",
  "defect",
  "general",
]);

/** The manifest photo labels the spatial report places a photo by, when complete. */
export function photoLabels(value: unknown): PackageFileRecord["photo"] {
  if (value === null || typeof value !== "object") {
    return undefined;
  }
  const { room, direction, subject, takenAt } = value as Record<string, unknown>;
  if (
    typeof room !== "string" ||
    typeof direction !== "string" ||
    !DIRECTIONS.has(direction) ||
    typeof subject !== "string" ||
    !SUBJECTS.has(subject) ||
    typeof takenAt !== "string"
  ) {
    return undefined;
  }
  return {
    room,
    direction: direction as NonNullable<PackageFileRecord["photo"]>["direction"],
    subject: subject as NonNullable<PackageFileRecord["photo"]>["subject"],
    takenAt,
  };
}

async function currentVerdictId(ctx: WorkerContext, packageId: string): Promise<string | null> {
  const result = await ctx.db.query<{ verdict_id: string }>(
    `SELECT verdict_id FROM verdicts WHERE package_id = $1`,
    [packageId],
  );
  return result.rows[0]?.verdict_id ?? null;
}

export async function runPublishJob(ctx: WorkerContext, lease: Lease): Promise<void> {
  const packageId = lease.job.package_id;
  let verdictId: string | null = null;
  try {
    const pkg = await selectPackage(ctx.db, packageId);
    const stored = await ctx.db.query<{ verdict_id: string; document: unknown }>(
      `SELECT verdict_id, document FROM verdicts WHERE package_id = $1`,
      [packageId],
    );
    const row = stored.rows[0];
    if (pkg === undefined || pkg.status !== "verdict_ready" || row === undefined) {
      // Nothing to publish now (the checks are running again or ended in check_error); a
      // finished checks job queues a new publish job.
      await ctx.db.transaction((tx) => finishJob(tx, lease, "succeeded"));
      ctx.logger.info(
        { jobId: lease.job.job_id, packageId, status: pkg?.status ?? "missing" },
        "publish job skipped: no verdict ready",
      );
      return;
    }
    verdictId = row.verdict_id;
    const checked = validateVerdict(row.document);
    if (!checked.ok) {
      throw new TerminalJobError("The stored verdict does not match the contract; not published");
    }
    const verdict = checked.value as Verdict;
    const files = requireVerified(await selectFiles(ctx.db, packageId));
    const manifestData = await readManifest(ctx.originals, pkg);

    const manifestFiles = Array.isArray(pkg.manifest?.files)
      ? (pkg.manifest.files as unknown[])
      : [];
    const mimes = new Map<string, string>();
    const photos = new Map<string, NonNullable<PackageFileRecord["photo"]>>();
    for (const entry of manifestFiles) {
      const { path, mime, photo } = (entry ?? {}) as {
        path?: unknown;
        mime?: unknown;
        photo?: unknown;
      };
      if (typeof path === "string" && typeof mime === "string") {
        mimes.set(path, mime);
      }
      const labels = photoLabels(photo);
      if (typeof path === "string" && labels !== undefined) {
        photos.set(path, labels);
      }
    }
    const sealedAt = typeof pkg.manifest?.sealedAt === "string" ? pkg.manifest.sealedAt : undefined;
    const publishPackage: PublishPackage = {
      packageId,
      dealId: pkg.deal_id,
      visitId: pkg.visit_id,
      revision: pkg.revision,
      manifestPath: manifestPath(pkg.visit_id),
      manifestSha256: pkg.manifest_sha256 ?? "",
      manifestBytes: manifestData.byteLength,
      ...(sealedAt === undefined ? {} : { sealedAt }),
      manifestFileCount: manifestFiles.length,
      files: files.map((file) => ({
        path: file.path,
        role: file.role as Role,
        ...(file.capture_id === null ? {} : { captureId: file.capture_id }),
        ...(file.area_key === null ? {} : { areaKey: file.area_key }),
        sha256: file.sha256,
        bytes: file.bytes,
        ...(mimes.has(file.path) ? { mime: mimes.get(file.path) as string } : {}),
        ...(photos.has(file.path)
          ? { photo: photos.get(file.path) as NonNullable<PackageFileRecord["photo"]> }
          : {}),
      })),
    };
    const byPath = new Map(files.map((file) => [file.path, file]));
    const record = validateCaptureRecord(pkg.capture_record);
    const request: PublishRequest = {
      pkg: publishPackage,
      verdict,
      ...(record.ok ? { captureRecord: record.value as CaptureRecord } : {}),
      readManifest: async () => manifestData,
      readFile: async (path) => {
        const file = byPath.get(path);
        if (file === undefined) {
          throw new TerminalJobError(`No verified file ${path} in the package`);
        }
        return readVerified(ctx.originals, {
          path,
          blobName: file.blob_name,
          sha256: file.sha256,
          bytes: file.bytes,
        });
      },
    };

    const publisher = new HubPublisher({
      hub: ctx.hub,
      store: new PgPublicationStore(ctx.db),
      reviewBaseUrl: ctx.reviewBaseUrl,
      baseDelayMs: ctx.publishRetryBaseMs,
      maxDelayMs: ctx.publishRetryMaxMs,
      logger: ctx.logger,
      reportTimeZone: ctx.reportTimeZone,
      // The spatial report is stored for the web review before anything goes to the HUB.
      onReportRendered: (report, rendered) =>
        storeSpatialReport(ctx, packageId, report, rendered, lease.job.job_id),
      ...(ctx.sleep === undefined ? {} : { sleep: ctx.sleep }),
    });
    const result = await publisher.publish(request);

    await ctx.db.transaction(async (tx) => {
      if (result.status === "published") {
        const latest = await currentVerdictId(ctx, packageId);
        if (latest !== null && latest !== verdict.verdictId) {
          await requeueJob(tx, lease, null, 0, true);
          ctx.logger.info(
            { jobId: lease.job.job_id, packageId, published: verdict.verdictId, latest },
            "a newer verdict was stored while publishing; publishing it next",
          );
        } else {
          await finishJob(tx, lease, "succeeded");
        }
        if (!result.alreadyPublished) {
          await auditPackage(tx, "hub.publish", packageId, {
            jobId: lease.job.job_id,
            dealId: pkg.deal_id,
            verdictId: verdict.verdictId,
            uploaded: result.uploaded,
            linked: result.linked,
            attempts: result.attempts,
          });
        }
        return;
      }
      const error = result.error ?? { status: null, message: "publish failed" };
      await finishJob(tx, lease, "failed", `publish_failed: ${error.message}`);
      await auditPackage(
        tx,
        "hub.publish_failed",
        packageId,
        {
          jobId: lease.job.job_id,
          dealId: pkg.deal_id,
          verdictId: verdict.verdictId,
          error,
          attempts: result.attempts,
        },
        ctx.secrets,
      );
    });
    ctx.logger.info(
      { jobId: lease.job.job_id, packageId, status: result.status, attempts: result.attempts },
      "publish job finished",
    );
  } catch (error) {
    if (error instanceof LeaseLostError) {
      throw error;
    }
    await handlePublishFailure(ctx, lease, error, verdictId);
  }
}

async function handlePublishFailure(
  ctx: WorkerContext,
  lease: Lease,
  error: unknown,
  verdictId: string | null,
): Promise<void> {
  const { job } = lease;
  const message = scrub(errorText(error), ctx.secrets, 500);
  await ctx.db.transaction(async (tx) => {
    if (!(error instanceof TerminalJobError)) {
      const delay = retryDelaySeconds(job.attempts, ctx.retryBaseSeconds, ctx.retryMaxSeconds);
      if ((await requeueJob(tx, lease, message, delay)) === "requeued") {
        ctx.logger.warn(
          {
            jobId: job.job_id,
            packageId: job.package_id,
            attempt: job.attempts,
            retryInSeconds: delay,
            error: message,
          },
          "publish job failed; retrying",
        );
        return;
      }
    }
    await finishJob(tx, lease, "failed", message);
    await markPublicationFailed(tx, job.package_id, verdictId, { status: null, message });
    const action =
      error instanceof TerminalJobError && error.auditAction !== undefined
        ? error.auditAction
        : "hub.publish_failed";
    await auditPackage(
      tx,
      action,
      job.package_id,
      {
        jobId: job.job_id,
        verdictId,
        error: message,
        ...(error instanceof TerminalJobError ? error.details : {}),
      },
      ctx.secrets,
    );
    ctx.logger.error(
      { jobId: job.job_id, packageId: job.package_id, error: message },
      "publish job failed; publication status publish_failed",
    );
  });
}
