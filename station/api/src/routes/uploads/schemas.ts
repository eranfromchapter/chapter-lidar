// Request schemas of the upload routes (contract/openapi/station.yaml operations
// createUploadSession, completeFile and sealPackage), built from the contract's manifest $defs so
// value rules (uuid, relative path, role, area key) have one source.
//
// Deliberate bounds the OpenAPI document leaves open, so no value can overflow the registry:
// revision <= 2147483647 (Postgres integer) and bytes <= Number.MAX_SAFE_INTEGER.
//
// The seal body is the manifest itself; it is validated with validateManifest from
// @chapter/capture-contract (JSON Schema 2020-12) in the handler, so the route schema only
// requires an object.

import { SCHEMAS, type Role } from "@chapter/capture-contract";

type JsonSchema = Record<string, unknown>;

const manifestDefs = (SCHEMAS.manifest as { $defs?: Record<string, JsonSchema> }).$defs ?? {};

function contractDef(name: string): JsonSchema {
  const def = manifestDefs[name];
  if (def === undefined) {
    throw new Error(`manifest.schema.json has no $defs/${name}`);
  }
  const { description: _description, ...rest } = def;
  return rest;
}

export const MAX_REVISION = 2_147_483_647;

export const uuidSchema = contractDef("uuid");
export const relativePathSchema = contractDef("relativePath");
export const roleSchema = contractDef("role");
export const areaKeySchema = contractDef("areaKey");
export const sha256Schema: JsonSchema = { type: "string", pattern: "^[0-9a-f]{64}$" };
export const dealIdSchema: JsonSchema = { type: "string", minLength: 1, maxLength: 64 };

export const uploadFileDeclarationSchema: JsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["path", "role", "sha256", "bytes"],
  properties: {
    path: relativePathSchema,
    role: roleSchema,
    captureId: uuidSchema,
    areaKey: areaKeySchema,
    sha256: sha256Schema,
    bytes: { type: "integer", minimum: 0, maximum: Number.MAX_SAFE_INTEGER },
  },
};

export const uploadSessionRequestSchema: JsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["packageId", "visitId", "dealId", "revision", "files"],
  properties: {
    packageId: uuidSchema,
    visitId: uuidSchema,
    dealId: dealIdSchema,
    revision: { type: "integer", minimum: 1, maximum: MAX_REVISION },
    supersedesPackageId: uuidSchema,
    files: { type: "array", minItems: 1, items: uploadFileDeclarationSchema },
  },
};

export const completeFileRequestSchema: JsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["path"],
  properties: { path: relativePathSchema },
};

export const sealRequestSchema: JsonSchema = { type: "object" };

export const packageIdParamsSchema: JsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["packageId"],
  properties: { packageId: uuidSchema },
};

export interface UploadFileDeclaration {
  path: string;
  role: Role;
  captureId?: string;
  areaKey?: string;
  sha256: string;
  bytes: number;
}

export interface UploadSessionRequest {
  packageId: string;
  visitId: string;
  dealId: string;
  revision: number;
  supersedesPackageId?: string;
  files: UploadFileDeclaration[];
}

export interface PackageIdParams {
  packageId: string;
}

export interface CompleteFileRequest {
  path: string;
}
