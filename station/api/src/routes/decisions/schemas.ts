// Request schema of POST /packages/{packageId}/modeling-decisions (OpenAPI
// components.schemas.ModelingDecisionInput), built from the contract value rules.
// test/packages/openapi-conformance.decisions.test.ts checks it against the document.

import { areaKeySchema, relativePathSchema, uuidSchema } from "../packages/schemas.js";

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
