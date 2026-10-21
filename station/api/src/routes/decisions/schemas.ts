// Request schema of POST /packages/{packageId}/modeling-decisions (OpenAPI
// components.schemas.ModelingDecisionInput), built from the contract value rules.
// test/packages/openapi-conformance.decisions.test.ts checks it against the document.

import {
  areaKeySchema,
  dealIdSchema,
  relativePathSchema,
  uuidSchema,
} from "../packages/schemas.js";

const shortId = { type: "string", minLength: 1, maxLength: 128 } as const;

/** OpenAPI components.schemas.DecisionSource. */
export const decisionSourceSchema = {
  type: "object",
  additionalProperties: false,
  required: ["path"],
  properties: {
    path: relativePathSchema,
    controlId: shortId,
    elementId: shortId,
  },
} as const;

/** OpenAPI components.schemas.ModelingDecisionInput. */
export const modelingDecisionInputSchema = {
  type: "object",
  additionalProperties: false,
  required: ["element", "decision", "sources"],
  properties: {
    element: { type: "string", minLength: 1, maxLength: 300 },
    decision: { type: "string", minLength: 1, maxLength: 2000 },
    captureId: uuidSchema,
    areaKey: areaKeySchema,
    sources: { type: "array", minItems: 1, items: decisionSourceSchema },
    note: { type: "string", minLength: 1, maxLength: 2000 },
  },
} as const;

export interface DecisionSource {
  path: string;
  controlId?: string;
  elementId?: string;
}

export interface ModelingDecisionInput {
  element: string;
  decision: string;
  captureId?: string;
  areaKey?: string;
  sources: DecisionSource[];
  note?: string;
}

export interface ModelingDecision extends ModelingDecisionInput {
  decisionId: string;
  packageId: string;
  decidedBy: { name: string; userId: string };
  decidedAt: string;
}

/** OpenAPI ModelingDecisionWithContext: a decision with its package's deal and revision. */
export interface ModelingDecisionWithContext extends ModelingDecision {
  dealId: string;
  revision: number;
}

export const LIST_ALL_DECISIONS_DEFAULT_LIMIT = 100;

/** GET /modeling-decisions query string. Unknown parameters are rejected (400). */
export const listAllDecisionsQuerySchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    dealId: dealIdSchema,
    limit: { type: "integer", minimum: 1, maximum: 200, default: LIST_ALL_DECISIONS_DEFAULT_LIMIT },
  },
} as const;

export interface ListAllDecisionsQuery {
  dealId?: string;
  limit?: number;
}
