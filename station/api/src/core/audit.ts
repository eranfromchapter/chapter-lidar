// Audit log: every write records who did what to which target, and when.
//
// Pass the transaction client of the write so the audit row commits or rolls back with it:
//
//   await app.db.transaction(async (tx) => {
//     await tx.query("INSERT INTO packages ...", [...]);
//     await audit(request, "package.create", { type: "package", id: packageId }, { revision }, tx);
//   });
//
// Details are passed through redactSecrets, so tokens, SAS URLs and keys never reach the table.
// audit_log is append-only (enforced by a trigger).

import type { FastifyRequest } from "fastify";
import type { Principal } from "./auth.js";
import type { Queryable } from "./db.js";
import { redactSecrets } from "./redact.js";

/** Dotted lowercase action, for example package.create or file.verify. */
export const AUDIT_ACTION_PATTERN = /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/;
/** Lowercase target type, for example package or modeling_decision. */
export const AUDIT_TARGET_TYPE_PATTERN = /^[a-z][a-z0-9_]*$/;

export interface AuditTarget {
  readonly type: string;
  readonly id?: string;
}

export interface AuditActor {
  readonly type: "user" | "service" | "system";
  /** Entra object id; omitted only for system actors. */
  readonly id?: string;
  readonly name?: string;
  readonly roles?: readonly string[];
}

export interface AuditRecord {
  readonly actor: AuditActor;
  readonly action: string;
  readonly target: AuditTarget;
  readonly details?: Record<string, unknown>;
  readonly requestId?: string;
}

export function actorFromPrincipal(principal: Principal): AuditActor {
  return {
    type: principal.kind,
    id: principal.userId,
    name: principal.name,
    roles: principal.roles,
  };
}

const INSERT_AUDIT = `
  INSERT INTO audit_log
    (actor_type, actor_id, actor_name, actor_roles, action, target_type, target_id, details, request_id)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9)
  RETURNING audit_id`;

/** Writes one audit row with the given executor (pool or transaction client). */
export async function writeAudit(db: Queryable, record: AuditRecord): Promise<number> {
  if (!AUDIT_ACTION_PATTERN.test(record.action) || record.action.length > 100) {
    throw new RangeError(`invalid audit action: ${record.action}`);
  }
  if (!AUDIT_TARGET_TYPE_PATTERN.test(record.target.type) || record.target.type.length > 64) {
    throw new RangeError(`invalid audit target type: ${record.target.type}`);
  }
  if (record.actor.type !== "system" && !record.actor.id) {
    throw new RangeError("audit actor id is required for user and service actors");
  }
  const details = redactSecrets(record.details ?? {});
  const result = await db.query<{ audit_id: number }>(INSERT_AUDIT, [
    record.actor.type,
    record.actor.id ?? null,
    record.actor.name ?? null,
    [...(record.actor.roles ?? [])],
    record.action,
    record.target.type,
    record.target.id ?? null,
    JSON.stringify(details),
    record.requestId ?? null,
  ]);
  const row = result.rows[0];
  if (row === undefined) {
    throw new Error("audit insert returned no row");
  }
  return row.audit_id;
}

/**
 * Audits a write made by the signed-in caller of request. Use the transaction client of the
 * write as executor whenever there is one; otherwise the pool (request.server.db) is used.
 */
export async function audit(
  request: FastifyRequest,
  action: string,
  target: AuditTarget,
  details: Record<string, unknown> = {},
  executor?: Queryable,
): Promise<number> {
  const principal = request.principal;
  if (principal === null) {
    throw new Error("audit() needs a signed-in principal; use writeAudit() for system actors");
  }
  return writeAudit(executor ?? request.server.db, {
    actor: actorFromPrincipal(principal),
    action,
    target,
    details,
    requestId: request.id,
  });
}
