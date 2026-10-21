// Modeling decision log (contract/openapi/station.yaml):
//
//   GET  /v1/packages/{packageId}/modeling-decisions   listModelingDecisions   bim, admin
//   POST /v1/packages/{packageId}/modeling-decisions   createModelingDecision  bim, admin
//   GET  /v1/modeling-decisions?dealId&limit           listAllModelingDecisions bim, admin
//
// Decisions are append-only (the table rejects UPDATE and DELETE). The station records the
// signed-in user and the time; each decision is audited in the same transaction. The list
// across packages (the review screen's decision log) is newest first, with each package's deal
// and revision.

import type { FastifyInstance } from "fastify";
import { audit } from "../../core/audit.js";
import { requirePrincipal } from "../../core/auth.js";
import type { Queryable } from "../../core/db.js";
import { ProblemError } from "../../core/problem.js";
import { toApiDateTime } from "../../core/time.js";
import { isContractUuid, type PackageParams } from "../packages/schemas.js";
import { packageExists } from "../packages/store.js";
import { decisionRuleErrors, type PackageFileRef } from "./rules.js";
import {
  LIST_ALL_DECISIONS_DEFAULT_LIMIT,
  listAllDecisionsQuerySchema,
  modelingDecisionInputSchema,
  type DecisionSource,
  type ListAllDecisionsQuery,
  type ModelingDecision,
  type ModelingDecisionInput,
  type ModelingDecisionWithContext,
} from "./schemas.js";

const DECISION_ROLES = ["bim", "admin"] as const;

interface DecisionRow {
  decision_id: string;
  package_id: string;
  element: string;
  decision: string;
  capture_id: string | null;
  area_key: string | null;
  sources: DecisionSource[];
  note: string | null;
  decided_by_id: string;
  decided_by_name: string;
  decided_at: Date;
}

const DECISION_COLUMNS = `decision_id, package_id, element, decision, capture_id, area_key,
  sources, note, decided_by_id, decided_by_name, decided_at`;

function toDecision(row: DecisionRow): ModelingDecision {
  const decision: ModelingDecision = {
    decisionId: row.decision_id,
    packageId: row.package_id,
    element: row.element,
    decision: row.decision,
    sources: row.sources,
    decidedBy: { name: row.decided_by_name, userId: row.decided_by_id },
    decidedAt: toApiDateTime(row.decided_at),
  };
  if (row.capture_id !== null) {
    decision.captureId = row.capture_id;
  }
  if (row.area_key !== null) {
    decision.areaKey = row.area_key;
  }
  if (row.note !== null) {
    decision.note = row.note;
  }
  return decision;
}

/** Only the documented source fields, in a fixed order. */
function normalizeSource(source: DecisionSource): DecisionSource {
  return {
    path: source.path,
    ...(source.controlId === undefined ? {} : { controlId: source.controlId }),
    ...(source.elementId === undefined ? {} : { elementId: source.elementId }),
  };
}

function packageNotFound(): ProblemError {
  return new ProblemError(404, "not_found", { detail: "No package with this id." });
}

/** Locks the package row against deletion and returns its files, or undefined if missing. */
async function lockPackageFiles(
  tx: Queryable,
  packageId: string,
): Promise<PackageFileRef[] | undefined> {
  const locked = await tx.query("SELECT 1 FROM packages WHERE package_id = $1 FOR KEY SHARE", [
    packageId,
  ]);
  if ((locked.rowCount ?? 0) === 0) {
    return undefined;
  }
  const files = await tx.query<{
    path: string;
    role: string;
    capture_id: string | null;
    area_key: string | null;
  }>("SELECT path, role, capture_id, area_key FROM package_files WHERE package_id = $1", [
    packageId,
  ]);
  return files.rows.map((row) => ({
    path: row.path,
    role: row.role,
    captureId: row.capture_id,
    areaKey: row.area_key,
  }));
}

export default async function decisionRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Querystring: ListAllDecisionsQuery }>(
    "/modeling-decisions",
    { config: { roles: DECISION_ROLES }, schema: { querystring: listAllDecisionsQuerySchema } },
    async (request) => {
      const { dealId, limit = LIST_ALL_DECISIONS_DEFAULT_LIMIT } = request.query;
      const result = await app.db.query<DecisionRow & { deal_id: string; revision: number }>(
        `SELECT d.decision_id, d.package_id, d.element, d.decision, d.capture_id, d.area_key,
                d.sources, d.note, d.decided_by_id, d.decided_by_name, d.decided_at,
                p.deal_id, p.revision
           FROM modeling_decisions d
           JOIN packages p ON p.package_id = d.package_id
          WHERE $1::text IS NULL OR p.deal_id = $1::text
          ORDER BY d.decided_at DESC, d.decision_id DESC
          LIMIT $2`,
        [dealId ?? null, limit + 1],
      );
      const decisions: ModelingDecisionWithContext[] = result.rows.slice(0, limit).map((row) => {
        const { decisionId, packageId, ...rest } = toDecision(row);
        return { decisionId, packageId, dealId: row.deal_id, revision: row.revision, ...rest };
      });
      return { decisions, truncated: result.rows.length > limit };
    },
  );

  app.get<{ Params: PackageParams }>(
    "/packages/:packageId/modeling-decisions",
    { config: { roles: DECISION_ROLES } },
    async (request) => {
      const { packageId } = request.params;
      if (!isContractUuid(packageId) || !(await packageExists(app.db, packageId))) {
        throw packageNotFound();
      }
      const result = await app.db.query<DecisionRow>(
        `SELECT ${DECISION_COLUMNS}
           FROM modeling_decisions
          WHERE package_id = $1
          ORDER BY decided_at, decision_id`,
        [packageId],
      );
      return { decisions: result.rows.map(toDecision) };
    },
  );

  app.post<{ Params: PackageParams; Body: ModelingDecisionInput }>(
    "/packages/:packageId/modeling-decisions",
    {
      config: { roles: DECISION_ROLES },
      // Bodies are never type-coerced (core validation.ts): {"element": 5} is 400.
      schema: { body: modelingDecisionInputSchema },
    },
    async (request, reply) => {
      const principal = requirePrincipal(request);
      const { packageId } = request.params;
      if (!isContractUuid(packageId)) {
        throw packageNotFound();
      }
      const input = request.body;
      const sources = input.sources.map(normalizeSource);

      const created = await app.db.transaction(async (tx) => {
        const files = await lockPackageFiles(tx, packageId);
        if (files === undefined) {
          throw packageNotFound();
        }
        const errors = decisionRuleErrors(input, files);
        if (errors.length > 0) {
          throw new ProblemError(422, "decision_rule_violation", {
            detail: "The decision breaks a contract rule.",
            errors,
          });
        }
        const inserted = await tx.query<DecisionRow>(
          `INSERT INTO modeling_decisions
             (package_id, element, decision, capture_id, area_key, sources, note,
              decided_by_id, decided_by_name)
           VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9)
           RETURNING ${DECISION_COLUMNS}`,
          [
            packageId,
            input.element,
            input.decision,
            input.captureId ?? null,
            input.areaKey ?? null,
            JSON.stringify(sources),
            input.note ?? null,
            principal.userId,
            principal.name,
          ],
        );
        const row = inserted.rows[0];
        if (row === undefined) {
          throw new Error("modeling decision insert returned no row");
        }
        await audit(
          request,
          "modeling_decision.create",
          { type: "modeling_decision", id: row.decision_id },
          {
            packageId,
            ...(input.captureId === undefined ? {} : { captureId: input.captureId }),
            sourceCount: sources.length,
          },
          tx,
        );
        return toDecision(row);
      });

      return reply.code(201).send(created);
    },
  );
}
