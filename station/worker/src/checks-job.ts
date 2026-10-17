// checks job: load the sealed package, look up the HUB address, run the acceptance checks and
// store the run, its results and the verdict; then queue the publish job.
//
// Package status: checks_queued -> checking -> verdict_ready, or check_error when the station
// cannot complete the checks (integrity failure, unreadable manifest, HUB address unavailable
// after every attempt). check_error is not a verdict.
//
// Idempotent: the job owns at most one check run. Re-running it deletes that run (its results
// cascade) and upserts the package's single verdict row.

import { validateVerdict, formatErrors, type Verdict } from "@chapter/capture-contract";
import { EVALUATOR, PackageLoadError, packageFromFiles, runChecks } from "@chapter/station-checks";
import { HubError, scrub } from "@chapter/station-hub";
import { auditPackage } from "./audit.js";
import {
  RetryableJobError,
  TerminalJobError,
  errorText,
  toApiDateTime,
  type WorkerContext,
} from "./context.js";
import type { Queryable } from "./db.js";
import { loadSealedFiles, selectFiles, selectPackage } from "./package.js";
import { LeaseLostError, finishJob, requeueJob, retryDelaySeconds, type Lease } from "./queue.js";

export async function runChecksJob(ctx: WorkerContext, lease: Lease): Promise<void> {
  const packageId = lease.job.package_id;
  const startedAt = ctx.now();
  try {
    const pkg = await selectPackage(ctx.db, packageId);
    if (pkg === undefined) {
      throw new TerminalJobError(`Package ${packageId} does not exist`);
    }
    if (pkg.manifest === null || pkg.status === "uploading") {
      throw new TerminalJobError(`Package ${packageId} is not sealed`);
    }
    await ctx.db.query(
      `UPDATE packages SET status = 'checking' WHERE package_id = $1 AND status <> 'uploading'`,
      [packageId],
    );

    const files = await loadSealedFiles(ctx.originals, pkg, await selectFiles(ctx.db, packageId));
    let loaded;
    try {
      loaded = packageFromFiles(files);
    } catch (error) {
      if (error instanceof PackageLoadError) {
        throw new TerminalJobError(`The sealed manifest cannot be loaded: ${error.message}`);
      }
      throw error;
    }
    if (
      loaded.manifest.packageId !== pkg.package_id ||
      loaded.manifest.visitId !== pkg.visit_id ||
      loaded.manifest.revision !== pkg.revision
    ) {
      throw new TerminalJobError(
        "The sealed manifest names another package, visit or revision than the registry",
        "package.integrity_error",
        { reason: "manifest_identity" },
      );
    }

    // Check 3 needs the HUB's own address for the deal: never the capture record's address.
    let address: string;
    try {
      const deal = await ctx.hub.getDeal(pkg.deal_id);
      if (deal === null) {
        throw new RetryableJobError(
          `The HUB has no deal ${pkg.deal_id} with a confirmed address; the property check cannot run`,
        );
      }
      address = deal.address;
    } catch (error) {
      if (error instanceof HubError) {
        throw new RetryableJobError(`HUB deal lookup failed: ${error.message}`);
      }
      throw error;
    }

    const evaluatedAt = toApiDateTime(ctx.now());
    const verdict = runChecks(loaded, address, { evaluatedAt });
    const checked = validateVerdict(verdict);
    if (!checked.ok) {
      throw new TerminalJobError(
        `The checks produced a verdict that breaks the contract: ${formatErrors(checked.errors.slice(0, 5)).replace(/\n/g, "; ")}`,
      );
    }
    await storeVerdict(ctx, lease, checked.value as Verdict, startedAt);
    ctx.logger.info(
      {
        jobId: lease.job.job_id,
        packageId,
        verdictId: verdict.verdictId,
        outcome: verdict.outcome,
      },
      "verdict stored",
    );
  } catch (error) {
    if (error instanceof LeaseLostError) {
      throw error;
    }
    await handleChecksFailure(ctx, lease, error, startedAt);
  }
}

async function storeVerdict(
  ctx: WorkerContext,
  lease: Lease,
  verdict: Verdict,
  startedAt: Date,
): Promise<void> {
  const packageId = lease.job.package_id;
  await ctx.db.transaction(async (tx) => {
    await finishJob(tx, lease, "succeeded");
    await tx.query(`DELETE FROM check_runs WHERE job_id = $1`, [lease.job.job_id]);
    const run = await tx.query<{ run_id: string }>(
      `INSERT INTO check_runs
         (package_id, job_id, status, evaluator_name, evaluator_version, started_at, finished_at)
       VALUES ($1, $2, 'completed', $3, $4, $5, now())
       RETURNING run_id`,
      [packageId, lease.job.job_id, verdict.evaluator.name, verdict.evaluator.version, startedAt],
    );
    const runId = run.rows[0]?.run_id;
    if (runId === undefined) {
      throw new Error("check run insert returned no row");
    }
    await tx.query(
      `INSERT INTO check_results (run_id, ordinal, rule_id, title, status, findings)
       SELECT $1, r.ordinal, r.rule_id, r.title, r.status, r.findings::jsonb
         FROM unnest($2::int[], $3::text[], $4::text[], $5::text[], $6::text[])
           AS r(ordinal, rule_id, title, status, findings)`,
      [
        runId,
        verdict.checks.map((_, index) => index),
        verdict.checks.map((check) => check.ruleId),
        verdict.checks.map((check) => check.title),
        verdict.checks.map((check) => check.status),
        verdict.checks.map((check) =>
          JSON.stringify(verdict.findings.filter((finding) => finding.ruleId === check.ruleId)),
        ),
      ],
    );
    await tx.query(
      `INSERT INTO verdicts (verdict_id, package_id, run_id, outcome, evaluated_at, document)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb)
       ON CONFLICT (package_id) DO UPDATE
         SET verdict_id = EXCLUDED.verdict_id, run_id = EXCLUDED.run_id,
             outcome = EXCLUDED.outcome, evaluated_at = EXCLUDED.evaluated_at,
             document = EXCLUDED.document`,
      [
        verdict.verdictId,
        packageId,
        runId,
        verdict.outcome,
        verdict.evaluatedAt,
        JSON.stringify(verdict),
      ],
    );
    await tx.query(`UPDATE packages SET status = 'verdict_ready' WHERE package_id = $1`, [
      packageId,
    ]);
    const publish = await tx.query<{ job_id: string }>(
      `INSERT INTO jobs (type, package_id, payload) VALUES ('publish', $1, $2::jsonb)
       ON CONFLICT (package_id, type) WHERE status IN ('queued', 'running') DO NOTHING
       RETURNING job_id`,
      [packageId, JSON.stringify({ verdictId: verdict.verdictId })],
    );
    await auditPackage(tx, "verdict.store", packageId, {
      jobId: lease.job.job_id,
      runId,
      verdictId: verdict.verdictId,
      outcome: verdict.outcome,
      evaluatedAt: verdict.evaluatedAt,
      evaluator: `${EVALUATOR.name} ${EVALUATOR.version}`,
      publishJobId: publish.rows[0]?.job_id ?? null,
    });
  });
}

/** Ends a checks job without a verdict: failed job, failed run, package check_error. */
export async function failChecksTerminally(
  tx: Queryable,
  packageId: string,
  jobId: string,
  message: string,
  startedAt: Date | null,
  audit: { action: string; details: Record<string, unknown> },
  secrets: readonly string[],
): Promise<void> {
  await tx.query(`DELETE FROM check_runs WHERE job_id = $1`, [jobId]);
  await tx.query(
    `INSERT INTO check_runs
       (package_id, job_id, status, evaluator_name, evaluator_version, started_at, finished_at, error)
     VALUES ($1, $2, 'failed', $3, $4, COALESCE($5::timestamptz, now()), now(), $6)`,
    [packageId, jobId, EVALUATOR.name, EVALUATOR.version, startedAt, message],
  );
  await tx.query(
    `UPDATE packages SET status = 'check_error' WHERE package_id = $1 AND status <> 'uploading'`,
    [packageId],
  );
  await auditPackage(
    tx,
    audit.action,
    packageId,
    { jobId, error: message, ...audit.details },
    secrets,
  );
}

async function handleChecksFailure(
  ctx: WorkerContext,
  lease: Lease,
  error: unknown,
  startedAt: Date,
): Promise<void> {
  const { job } = lease;
  const message = scrub(errorText(error), ctx.secrets, 1000);
  const terminal = error instanceof TerminalJobError;
  await ctx.db.transaction(async (tx) => {
    if (!terminal) {
      const delay = retryDelaySeconds(job.attempts, ctx.retryBaseSeconds, ctx.retryMaxSeconds);
      if ((await requeueJob(tx, lease, message, delay)) === "requeued") {
        await tx.query(
          `UPDATE packages SET status = 'checks_queued' WHERE package_id = $1 AND status = 'checking'`,
          [job.package_id],
        );
        ctx.logger.warn(
          {
            jobId: job.job_id,
            packageId: job.package_id,
            attempt: job.attempts,
            retryInSeconds: delay,
            error: message,
          },
          "checks job failed; retrying",
        );
        return;
      }
    }
    await finishJob(tx, lease, "failed", message);
    await failChecksTerminally(
      tx,
      job.package_id,
      job.job_id,
      message,
      startedAt,
      {
        action:
          terminal && error.auditAction !== undefined ? error.auditAction : "package.check_error",
        details: terminal
          ? { ...error.details, attempts: job.attempts }
          : { attempts: job.attempts },
      },
      ctx.secrets,
    );
    ctx.logger.error(
      { jobId: job.job_id, packageId: job.package_id, attempt: job.attempts, error: message },
      "checks job failed; package status check_error",
    );
  });
}
