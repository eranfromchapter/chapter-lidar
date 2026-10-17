// The worker loop: recover stale locks, claim one due job (SKIP LOCKED), run it while
// refreshing its lock, repeat; sleep for the poll interval when nothing is due.

import { randomUUID } from "node:crypto";
import { auditPackage } from "./audit.js";
import { failChecksTerminally, runChecksJob } from "./checks-job.js";
import { errorText, type WorkerContext } from "./context.js";
import { markPublicationFailed } from "./publication-store.js";
import { runPublishJob } from "./publish-job.js";
import {
  claimJob,
  recoverStaleLocks,
  refreshLock,
  type Lease,
  type RecoveredJob,
} from "./queue.js";

export interface WorkerOptions {
  readonly workerId: string;
  readonly pollIntervalMs: number;
  readonly lockTimeoutSeconds: number;
}

export class Worker {
  readonly #ctx: WorkerContext;
  readonly #options: WorkerOptions;
  #stopping = false;
  #wake: (() => void) | undefined;
  #running: Promise<void> | undefined;

  constructor(ctx: WorkerContext, options: WorkerOptions) {
    this.#ctx = ctx;
    this.#options = options;
  }

  /** One cycle: recover stale locks, then run at most one job. True when a job ran. */
  async runOnce(): Promise<boolean> {
    await this.recoverStale();
    const token = `${this.#options.workerId}:${randomUUID()}`;
    const lease = await claimJob(this.#ctx.db, token);
    if (lease === undefined) {
      return false;
    }
    await this.#run(lease);
    return true;
  }

  /** Runs jobs until no job is due. Returns how many ran. */
  async drain(): Promise<number> {
    let count = 0;
    while (await this.runOnce()) {
      count += 1;
    }
    return count;
  }

  async recoverStale(): Promise<RecoveredJob[]> {
    const recovered = await recoverStaleLocks(this.#ctx.db, this.#options.lockTimeoutSeconds);
    for (const job of recovered) {
      this.#ctx.logger.warn(
        {
          jobId: job.job_id,
          packageId: job.package_id,
          type: job.type,
          status: job.status,
          attempts: job.attempts,
        },
        "recovered a job whose lock expired",
      );
      if (job.status === "failed") {
        await this.#failRecovered(job);
      }
    }
    return recovered;
  }

  async #failRecovered(job: RecoveredJob): Promise<void> {
    const ctx = this.#ctx;
    await ctx.db.transaction(async (tx) => {
      if (job.type === "checks") {
        await failChecksTerminally(
          tx,
          job.package_id,
          job.job_id,
          job.last_error,
          null,
          {
            action: "package.check_error",
            details: { attempts: job.attempts, reason: "lock_expired" },
          },
          ctx.secrets,
        );
        return;
      }
      const verdict = await tx.query<{ verdict_id: string }>(
        `SELECT verdict_id FROM verdicts WHERE package_id = $1`,
        [job.package_id],
      );
      const verdictId = verdict.rows[0]?.verdict_id ?? null;
      await markPublicationFailed(tx, job.package_id, verdictId, {
        status: null,
        message: job.last_error,
      });
      await auditPackage(tx, "hub.publish_failed", job.package_id, {
        jobId: job.job_id,
        verdictId,
        error: job.last_error,
        reason: "lock_expired",
      });
    });
  }

  async #run(lease: Lease): Promise<void> {
    const { job } = lease;
    const ctx = this.#ctx;
    ctx.logger.info(
      { jobId: job.job_id, packageId: job.package_id, type: job.type, attempt: job.attempts },
      "job claimed",
    );
    const refreshMs = Math.max(1000, Math.floor((this.#options.lockTimeoutSeconds * 1000) / 3));
    const timer = setInterval(() => {
      refreshLock(ctx.db, lease).then(
        (held) => {
          if (!held) {
            ctx.logger.warn({ jobId: job.job_id }, "job lock is no longer held by this worker");
          }
        },
        (error: unknown) => {
          ctx.logger.warn(
            { jobId: job.job_id, error: errorText(error) },
            "could not refresh the job lock",
          );
        },
      );
    }, refreshMs);
    timer.unref();
    try {
      if (job.type === "checks") {
        await runChecksJob(ctx, lease);
      } else {
        await runPublishJob(ctx, lease);
      }
    } catch (error) {
      // Lost lock or the database failed while recording the outcome: the lock expires and the
      // job is recovered by a later cycle.
      ctx.logger.error(
        { jobId: job.job_id, packageId: job.package_id, type: job.type, error: errorText(error) },
        "job ended without recording its outcome",
      );
    } finally {
      clearInterval(timer);
    }
  }

  /** Runs until stop() is called. */
  start(): Promise<void> {
    this.#running ??= this.#loop();
    return this.#running;
  }

  async #loop(): Promise<void> {
    while (!this.#stopping) {
      let ran = false;
      try {
        ran = await this.runOnce();
      } catch (error) {
        this.#ctx.logger.error({ error: errorText(error) }, "worker cycle failed");
      }
      if (!ran && !this.#stopping) {
        await new Promise<void>((resolve) => {
          const timer = setTimeout(resolve, this.#options.pollIntervalMs);
          this.#wake = () => {
            clearTimeout(timer);
            resolve();
          };
        });
        this.#wake = undefined;
      }
    }
  }

  /** Finishes the current job, then stops. */
  async stop(): Promise<void> {
    this.#stopping = true;
    this.#wake?.();
    await this.#running;
  }
}
