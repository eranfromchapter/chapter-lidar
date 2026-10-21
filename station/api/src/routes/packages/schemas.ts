// Request schemas of the package read routes, built from the contract so a value rule (uuid,
// area key, relative path) is never copied by hand. Mirrors contract/openapi/station.yaml;
// test/packages/openapi-conformance.packages.test.ts checks them against the document.

import { SCHEMAS } from "@chapter/capture-contract";

const manifestDefs = SCHEMAS.manifest.$defs as Record<string, Record<string, unknown>>;

function contractDef(name: string): Record<string, unknown> {
  const schema = manifestDefs[name];
  if (schema === undefined) {
    throw new Error(`contract manifest schema has no $defs/${name}`);
  }
  return schema;
}

/** Lowercase RFC 9562 UUID (contract manifest $defs/uuid). */
export const uuidSchema = contractDef("uuid");
/** Floor or area key (contract manifest $defs/areaKey). */
export const areaKeySchema = contractDef("areaKey");
/** Package-relative path (contract manifest $defs/relativePath). */
export const relativePathSchema = contractDef("relativePath");

/** HUB deal id (OpenAPI components.schemas.DealId). */
export const dealIdSchema = {
  type: "string",
  minLength: 1,
  maxLength: 64,
} as const;

const UUID_PATTERN = new RegExp(String(uuidSchema.pattern));

/** True for a contract UUID (lowercase). Path ids are checked with this, not a schema. */
export function isContractUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

/** GET /packages query string. Unknown parameters are rejected (400). */
export const listPackagesQuerySchema = {
  type: "object",
  additionalProperties: false,
  required: ["dealId"],
  properties: {
    dealId: dealIdSchema,
    visitId: uuidSchema,
  },
} as const;

export interface ListPackagesQuery {
  dealId: string;
  visitId?: string;
}

/** GET /packages/{packageId}/files/download query string. Unknown parameters are rejected (400). */
export const fileDownloadQuerySchema = {
  type: "object",
  additionalProperties: false,
  required: ["path"],
  properties: {
    path: relativePathSchema,
  },
} as const;

export interface FileDownloadQuery {
  path: string;
}

/** Path parameters of /packages/{packageId}/... routes. */
export interface PackageParams {
  packageId: string;
}

/** Contract DateTime (manifest $defs/dateTime): UTC, whole seconds, with Z. */
export const dateTimeSchema = contractDef("dateTime");

/** Largest revision the registry holds (Postgres integer). */
const MAX_REVISION = 2_147_483_647;

/** OpenAPI components.schemas.NextRevisionChange. */
export const nextRevisionChangeSchema = {
  type: "object",
  additionalProperties: false,
  required: ["kind", "subject", "title", "detail"],
  properties: {
    kind: { enum: ["added", "changed", "removed"] },
    subject: { enum: ["capture", "room_names", "field_control", "photos", "retired_file"] },
    title: { type: "string", minLength: 1, maxLength: 200 },
    detail: { type: "string", minLength: 1, maxLength: 300 },
    answersNextAction: { type: "string", minLength: 1, maxLength: 500 },
    method: { enum: ["tape", "laser"] },
  },
} as const;

/**
 * PUT /packages/{packageId}/next-revision body (OpenAPI NextRevisionNoticeInput). Deliberate
 * bound the document leaves open: revision fits the registry's integer.
 */
export const nextRevisionNoticeInputSchema = {
  type: "object",
  additionalProperties: false,
  required: ["revision", "updatedAt", "changes"],
  properties: {
    revision: { type: "integer", minimum: 2, maximum: MAX_REVISION },
    updatedAt: dateTimeSchema,
    changes: { type: "array", maxItems: 50, items: nextRevisionChangeSchema },
  },
} as const;
