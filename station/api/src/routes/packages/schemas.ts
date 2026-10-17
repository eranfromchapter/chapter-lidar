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

/** Path parameters of /packages/{packageId}/... routes. */
export interface PackageParams {
  packageId: string;
}
