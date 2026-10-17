// The jobs queue (station/db/migrations/0004_jobs.sql): claim with SKIP LOCKED, refresh and
// release the lock, retry with backoff, finish, and recover stale locks.
//
// Every lock is a per-claim token in locked_by. Each write that ends or requeues a job checks
// the token, so a worker whose lock expired (and whose job another worker took over) cannot
// overwrite the newer run: its transaction is rolled back with LeaseLostError.

import type { Queryable } from "./db.js";

export type JobType = "checks" | "publish";
export type JobStatus = "queued" | "running" | "succeeded" | "failed";

export interface JobRow {
  readonly job_id: string;
  readonly type: JobType;
  readonly package_id: string;
  readonly status: JobStatus;
  readonly attempts: number;
  readonly max_attempts: number;
  readonly run_after: Date;
  readonly locked_at: Date | null;
  readonly locked_by: string | null;
  readonly last_error: string | null;
  readonly payload: Record<string, unknown>;
  readonly created_at: Date;
}

/** A claimed job and the token that holds its lock. */
export interface Lease {
  readonly job: JobRow;
  readonly token: string;
}

/** The job's lock was lost (expired and recovered); this run must not write its result. */
export class LeaseLostError extends Error {
  constructor(jobId: string) {
    super(`lock of job ${jobId} was lost; the result of this run is discarded`);
    this.name = "LeaseLostError";
  }
}

export const MAX_LAST_ERROR = 1000;

/** The claim query of 0004_jobs.sql, verbatim. */
export const CLAIM_SQL = `
  UPDATE jobs SET status = 'running', locked_at = now(), locked_by = $1, attempts = attempts + 1
  WHERE job_id = (
    SELECT job_id FROM jobs
    WHERE status = 'queued' AND run_after <= now()
    ORDER BY run_after, created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1)
  RETURNING *`;

/** Claims the next due job, or undefined when none is due. */
export async function claimJob(db: Queryable, token: string): Promise<Lease | undefined> {
  const result = await db.query<JobRow>(CLAIM_SQL, [token]);
  const job = result.rows[0];
  return job === undefined ? undefined : { job, token };
}

/** Refreshes locked_at while the job runs. False when the lock is no longer ours. */
export async function refreshLock(db: Queryable, lease: Lease): Promise<boolean> {
  const result = await db.query(
    `UPDATE jobs SET locked_at = now()
      WHERE job_id = $1 AND locked_by = $2 AND status = 'running'`,
    [lease.job.job_id, lease.token],
  );
  return (result.rowCount ?? 0) === 1;
}

function clip(text: string): string {
  return text.length <= MAX_LAST_ERROR ? text : `${text.slice(0, MAX_LAST_ERROR - 1)}…`;
}

/** Ends the job (succeeded clears last_error). Throws LeaseLostError when the lock is gone. */
export async function finishJob(
  tx: Queryable,
  lease: Lease,
  status: "succeeded" | "failed",
  error?: string,
): Promise<void> {
  const result = await tx.query(
    `UPDATE jobs
        SET status = $3::text, locked_at = NULL, locked_by = NULL, finished_at = now(),
            last_error = $4
      WHERE job_id = $1 AND locked_by = $2 AND status = 'running'`,
    [lease.job.job_id, lease.token, status, status === "failed" ? clip(error ?? "failed") : null],
  );
  if ((result.rowCount ?? 0) !== 1) {
    throw new LeaseLostError(lease.job.job_id);
  }
}

/**
 * Puts the job back in the queue after `delaySeconds`, when it has attempts left. Returns
 * "exhausted" (and changes nothing) when it has none. `refund` gives the attempt back (used
 * when the job is requeued for a reason that is not a failure).
 */
export async function requeueJob(
  tx: Queryable,
  lease: Lease,
  error: string | null,
  delaySeconds: number,
  refund = false,
): Promise<"requeued" | "exhausted"> {
  const result = await tx.query(
    `UPDATE jobs
        SET status = 'queued', locked_at = NULL, locked_by = NULL,
            run_after = now() + make_interval(secs => $3::double precision),
            last_error = $4,
            attempts = CASE WHEN $5::boolean THEN GREATEST(attempts - 1, 0) ELSE attempts END
      WHERE job_id = $1 AND locked_by = $2 AND status = 'running'
        AND ($5::boolean OR attempts < max_attempts)`,
    [lease.job.job_id, lease.token, delaySeconds, error === null ? null : clip(error), refund],
  );
  if ((result.rowCount ?? 0) === 1) {
    return "requeued";
  }
  const held = await tx.query(
    `SELECT 1 FROM jobs WHERE job_id = $1 AND locked_by = $2 AND status = 'running'`,
    [lease.job.job_id, lease.token],
  );
  if ((held.rowCount ?? 0) === 0) {
    throw new LeaseLostError(lease.job.job_id);
  }
  return "exhausted";
}

/** Delay before the next attempt: base x 2^(attempts-1), capped. */
export function retryDelaySeconds(
  attempts: number,
  baseSeconds: number,
  maxSeconds: number,
): number {
  return Math.min(maxSeconds, baseSeconds * 2 ** Math.max(0, attempts - 1));
}

/** A job whose stale lock was recovered. */
export interface RecoveredJob {
  readonly job_id: string;
  readonly type: JobType;
  readonly package_id: string;
  readonly status: "queued" | "failed";
  readonly attempts: number;
  readonly last_error: string;
}

/**
 * Running jobs whose lock is older than the timeout go back to the queue (the claim already
 * counted the attempt), or fail when they have no attempts left.
 */
export async function recoverStaleLocks(
  db: Queryable,
  lockTimeoutSeconds: number,
): Promise<RecoveredJob[]> {
  const result = await db.query<RecoveredJob>(
    `UPDATE jobs
        SET status = CASE WHEN attempts >= max_attempts THEN 'failed' ELSE 'queued' END,
            finished_at = CASE WHEN attempts >= max_attempts THEN now() ELSE NULL END,
            run_after = now(),
            last_error = 'lock expired: the worker did not finish within '
              || $1::text || ' s (attempt ' || attempts || ' of ' || max_attempts || ')',
            locked_at = NULL,
            locked_by = NULL
      WHERE status = 'running'
        AND locked_at < now() - make_interval(secs => $1::double precision)
      RETURNING job_id, type, package_id, status, attempts, last_error`,
    [lockTimeoutSeconds],
  );
  return result.rows;
}
