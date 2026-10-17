// What the job handlers need, and the two kinds of job failure.

import type { HubApi } from "@chapter/station-hub";
import type { Database } from "./db.js";
import type { Logger } from "./logger.js";
import type { OriginalsReader } from "./storage.js";

export interface WorkerContext {
  readonly db: Database;
  readonly originals: OriginalsReader;
  readonly hub: HubApi;
  readonly logger: Logger;
  readonly reviewBaseUrl: string;
  readonly retryBaseSeconds: number;
  readonly retryMaxSeconds: number;
  readonly publishRetryBaseMs: number;
  readonly publishRetryMaxMs: number;
  /** Secrets to scrub from stored errors (the HUB credential). */
  readonly secrets: readonly string[];
  readonly now: () => Date;
  /** Sleep between HUB publish attempts (tests shorten it). */
  readonly sleep?: (ms: number) => Promise<void>;
}

/** A failure that another attempt cannot fix: the job ends now (checks: check_error). */
export class TerminalJobError extends Error {
  constructor(
    message: string,
    /** Audit action for the failure, for example package.integrity_error. */
    readonly auditAction?: string,
    readonly details: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = "TerminalJobError";
  }
}

/** A failure worth another attempt later (HUB unavailable, storage hiccup). */
export class RetryableJobError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RetryableJobError";
  }
}

/** Contract DateTime: UTC, whole seconds, RFC 3339 with Z. */
export function toApiDateTime(date: Date): string {
  if (Number.isNaN(date.getTime())) {
    throw new RangeError("invalid date");
  }
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** Safe text of any error for last_error and logs. */
export function errorText(error: unknown): string {
  if (error instanceof Error) {
    return `${error.name}: ${error.message}`;
  }
  return "unknown error";
}
