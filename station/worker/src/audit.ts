// Audit rows for the worker's writes (table audit_log, append-only). The worker is a system
// actor. Details hold ids, counts, statuses and station-written messages only; they pass through
// scrub so nothing token-shaped is stored.

import { scrub } from "@chapter/station-hub";
import type { Queryable } from "./db.js";

export const WORKER_ACTOR_NAME = "chapter-station-worker";
const ACTION = /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/;

function clean(value: unknown, secrets: readonly string[], depth = 0): unknown {
  if (typeof value === "string") {
    return scrub(value, secrets, 2000);
  }
  if (value === null || typeof value !== "object" || depth > 8) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((item) => clean(item, secrets, depth + 1));
  }
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [key, clean(item, secrets, depth + 1)]),
  );
}

export async function auditPackage(
  db: Queryable,
  action: string,
  packageId: string,
  details: Record<string, unknown>,
  secrets: readonly string[] = [],
): Promise<void> {
  if (!ACTION.test(action) || action.length > 100) {
    throw new RangeError(`invalid audit action: ${action}`);
  }
  await db.query(
    `INSERT INTO audit_log (actor_type, actor_name, action, target_type, target_id, details)
     VALUES ('system', $1, $2, 'package', $3, $4::jsonb)`,
    [WORKER_ACTOR_NAME, action, packageId, JSON.stringify(clean(details, secrets))],
  );
}
