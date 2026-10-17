// contract/openapi/station.yaml as executable JSON Schemas (Ajv, JSON Schema 2020-12, the
// dialect of OpenAPI 3.1), for the uploads conformance test.
//
// References to ../schema/<name>.schema.json resolve to the contract schemas by their $id.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { SCHEMAS } from "@chapter/capture-contract";
import { Ajv2020, type ValidateFunction } from "ajv/dist/2020.js";
import addFormatsModule from "ajv-formats";
import type { LightMyRequestResponse } from "fastify";
import { parse } from "yaml";

export const OPENAPI_PATH = fileURLToPath(
  new URL("../../../../../contract/openapi/station.yaml", import.meta.url),
);
const SCHEMA_BASE = "https://hellochapter.com/schemas/chapter-capture/v1/";
const OPENAPI_ID = `${SCHEMA_BASE}openapi/station.json`;
const METHODS = ["get", "put", "post", "delete", "patch", "head", "options"] as const;

type Json = Record<string, unknown>;

export interface Operation {
  readonly operationId: string;
  readonly method: string;
  /** OpenAPI path, for example /packages/{packageId}/seal. */
  readonly path: string;
  /** Fastify route URL under /v1, for example /v1/packages/:packageId/seal. */
  readonly routeUrl: string;
  readonly roles: readonly string[];
  readonly statuses: readonly string[];
  readonly pointer: string;
}

function escapePointer(token: string): string {
  return token.replace(/~/g, "~0").replace(/\//g, "~1");
}

function rewriteRefs(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(rewriteRefs);
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => {
        if (key === "$ref" && typeof item === "string" && item.startsWith("../schema/")) {
          return [key, `${SCHEMA_BASE}${item.slice("../schema/".length)}`];
        }
        return [key, rewriteRefs(item)];
      }),
    );
  }
  return value;
}

function at(doc: Json, pointer: string): unknown {
  return pointer
    .split("/")
    .slice(1)
    .reduce<unknown>((node, token) => {
      const key = token.replace(/~1/g, "/").replace(/~0/g, "~");
      return node !== null && typeof node === "object" ? (node as Json)[key] : undefined;
    }, doc);
}

export class OpenApiContract {
  readonly doc: Json;
  private readonly ajv: Ajv2020;
  private readonly cache = new Map<string, ValidateFunction>();

  constructor() {
    this.doc = rewriteRefs(parse(readFileSync(OPENAPI_PATH, "utf8"))) as Json;
    // strict off: the OpenAPI document carries non-schema keys (paths, x-roles, ...).
    this.ajv = new Ajv2020({ strict: false, allErrors: true });
    addFormatsModule.default(this.ajv, ["uuid", "date-time", "uri", "uri-reference"]);
    this.ajv.addFormat("int64", true);
    for (const schema of Object.values(SCHEMAS)) {
      assert.ok(String(schema.$id).startsWith(SCHEMA_BASE), String(schema.$id));
      this.ajv.addSchema(schema);
    }
    this.ajv.addSchema({ ...this.doc, $id: OPENAPI_ID });
  }

  operation(operationId: string): Operation {
    const paths = this.doc.paths as Record<string, Json>;
    for (const [path, item] of Object.entries(paths)) {
      for (const method of METHODS) {
        const op = item[method] as Json | undefined;
        if (op?.operationId === operationId) {
          return {
            operationId,
            method: method.toUpperCase(),
            path,
            routeUrl: `/v1${path.replace(/\{([^}]+)\}/g, ":$1")}`,
            roles: (op["x-roles"] as string[] | undefined) ?? [],
            statuses: Object.keys((op.responses as Json | undefined) ?? {}),
            pointer: `/paths/${escapePointer(path)}/${method}`,
          };
        }
      }
    }
    throw new Error(`operation ${operationId} is not in station.yaml`);
  }

  /** Validator of a schema at a JSON Pointer of the OpenAPI document. */
  validatorAt(pointer: string): ValidateFunction {
    let validator = this.cache.get(pointer);
    if (validator === undefined) {
      validator = this.ajv.compile({ $ref: `${OPENAPI_ID}#${pointer}` });
      this.cache.set(pointer, validator);
    }
    return validator;
  }

  /** Validator of the operation's application/json request body. */
  requestBody(operationId: string): ValidateFunction {
    const op = this.operation(operationId);
    return this.validatorAt(`${op.pointer}/requestBody/content/application~1json/schema`);
  }

  /** Validates any JSON Schema (for example a route schema) in the same dialect and formats. */
  compile(schema: Json): ValidateFunction {
    return this.ajv.compile(schema);
  }

  /** Pointer of the response object of a status, following a components/responses $ref. */
  private responsePointer(op: Operation, status: string): string {
    let pointer = `${op.pointer}/responses/${status}`;
    const response = at(this.doc, pointer) as Json | undefined;
    if (response === undefined) {
      throw new Error(`${op.operationId} documents no ${status} response`);
    }
    const ref = response.$ref;
    if (typeof ref === "string") {
      assert.ok(ref.startsWith("#/"), ref);
      pointer = ref.slice(1);
    }
    return pointer;
  }

  /** Asserts that a response is documented for the operation and matches its schema. */
  assertResponse(operationId: string, response: LightMyRequestResponse): void {
    const op = this.operation(operationId);
    const status = String(response.statusCode);
    assert.ok(
      op.statuses.includes(status),
      `${operationId} answered ${status}, which station.yaml does not document: ${response.body}`,
    );
    const pointer = this.responsePointer(op, status);
    const content = (at(this.doc, `${pointer}/content`) ?? {}) as Json;
    const contentType =
      String(response.headers["content-type"] ?? "")
        .split(";")[0]
        ?.trim() ?? "";
    assert.ok(
      contentType in content,
      `${operationId} ${status}: content type ${contentType} is not one of ${Object.keys(content).join(", ")}`,
    );
    const validate = this.validatorAt(`${pointer}/content/${escapePointer(contentType)}/schema`);
    const body: unknown = response.json();
    assert.ok(
      validate(body),
      `${operationId} ${status} body does not match station.yaml: ${this.ajv.errorsText(validate.errors)}\n${response.body}`,
    );
    const headers = (at(this.doc, `${pointer}/headers`) ?? {}) as Json;
    for (const name of Object.keys(headers)) {
      if (name.toLowerCase() === "www-authenticate" || name.toLowerCase() === "location") {
        assert.ok(response.headers[name.toLowerCase()], `${operationId} ${status}: header ${name}`);
      }
    }
  }
}
