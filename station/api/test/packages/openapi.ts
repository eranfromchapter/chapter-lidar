// Loads contract/openapi/station.yaml and validates requests and responses against it with
// Ajv (JSON Schema 2020-12, as OpenAPI 3.1 uses). External refs to ../schema/*.schema.json
// resolve to the contract schemas by their $id.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { SCHEMAS } from "@chapter/capture-contract";
import { Ajv2020, type ValidateFunction } from "ajv/dist/2020.js";
import addFormatsModule from "ajv-formats";
import { parse } from "yaml";

export const OPENAPI_PATH = fileURLToPath(
  new URL("../../../../contract/openapi/station.yaml", import.meta.url),
);
const SCHEMA_BASE = "https://hellochapter.com/schemas/chapter-capture/v1/";
const DOC_ID = `${SCHEMA_BASE}openapi/station.json`;
const METHODS = ["get", "put", "post", "delete", "patch", "head", "options"] as const;

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type JsonObject = { [key: string]: Json };

export interface Operation {
  readonly operationId: string;
  readonly method: string;
  /** OpenAPI path, for example /packages/{packageId}. */
  readonly path: string;
  /** Fastify route URL under /v1, for example /v1/packages/:packageId. */
  readonly routeUrl: string;
  readonly roles: readonly string[];
  readonly node: JsonObject;
  readonly pointer: string;
}

export interface CheckedResponse {
  readonly statusCode: number;
  readonly headers: Record<string, unknown>;
  readonly body: string;
}

function escapePointer(token: string): string {
  return token.replace(/~/g, "~0").replace(/\//g, "~1");
}

/** Rewrites "../schema/x.schema.json#..." refs to the contract schema $ids. */
function rewriteRefs(value: Json): Json {
  if (Array.isArray(value)) {
    return value.map(rewriteRefs);
  }
  if (value !== null && typeof value === "object") {
    const out: JsonObject = {};
    for (const [key, item] of Object.entries(value)) {
      out[key] =
        key === "$ref" && typeof item === "string" && item.startsWith("../schema/")
          ? `${SCHEMA_BASE}${item.slice("../schema/".length)}`
          : rewriteRefs(item);
    }
    return out;
  }
  return value;
}

function asObject(value: Json | undefined, where: string): JsonObject {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`OpenAPI: ${where} is not an object`);
  }
  return value;
}

export class OpenApi {
  readonly doc: JsonObject;
  readonly operations: readonly Operation[];
  private readonly ajv: Ajv2020;
  private readonly cache = new Map<string, ValidateFunction>();

  constructor(path = OPENAPI_PATH) {
    this.doc = asObject(rewriteRefs(parse(readFileSync(path, "utf8")) as Json), "document");
    // strict off: the document carries OpenAPI keywords (x-roles, format int64) that are not
    // JSON Schema vocabulary.
    this.ajv = new Ajv2020({ strict: false, allErrors: true });
    addFormatsModule.default(this.ajv, ["uuid", "date-time", "uri", "uri-reference"]);
    this.ajv.addFormat("int64", {
      type: "number",
      validate: (n: number) => Number.isSafeInteger(n),
    });
    for (const schema of Object.values(SCHEMAS)) {
      this.ajv.addSchema(schema);
    }
    this.ajv.addSchema({ ...this.doc, $id: DOC_ID });

    const operations: Operation[] = [];
    for (const [path, item] of Object.entries(asObject(this.doc.paths, "paths"))) {
      const pathItem = asObject(item, path);
      for (const method of METHODS) {
        const node = pathItem[method];
        if (node === undefined) {
          continue;
        }
        const op = asObject(node, `${method} ${path}`);
        operations.push({
          operationId: String(op.operationId),
          method: method.toUpperCase(),
          path,
          routeUrl: `/v1${path.replace(/\{([^}]+)\}/g, ":$1")}`,
          roles: Array.isArray(op["x-roles"]) ? op["x-roles"].map(String) : [],
          node: op,
          pointer: `#/paths/${escapePointer(path)}/${method}`,
        });
      }
    }
    this.operations = operations;
  }

  operation(operationId: string): Operation {
    const op = this.operations.find((candidate) => candidate.operationId === operationId);
    if (op === undefined) {
      throw new Error(`OpenAPI has no operation ${operationId}`);
    }
    return op;
  }

  private validator(pointer: string): ValidateFunction {
    let validate = this.cache.get(pointer);
    if (validate === undefined) {
      validate = this.ajv.compile({ $ref: `${DOC_ID}${pointer}` });
      this.cache.set(pointer, validate);
    }
    return validate;
  }

  /** Errors of value against the schema at pointer (empty when valid). */
  errorsAt(pointer: string, value: unknown): string[] {
    const validate = this.validator(pointer);
    if (validate(value)) {
      return [];
    }
    return (validate.errors ?? []).map(
      (error) => `${error.instancePath || "/"} ${error.message ?? error.keyword}`,
    );
  }

  /** Errors of a JSON request body against the operation's request body schema. */
  requestBodyErrors(operationId: string, body: unknown): string[] {
    const op = this.operation(operationId);
    return this.errorsAt(`${op.pointer}/requestBody/content/application~1json/schema`, body);
  }

  /**
   * Errors of a query string (name -> value or values) against the operation's query
   * parameters: required ones present, no undeclared ones, each value valid. A value of an
   * integer parameter is read as a number when it is one ("5"), as a server parses it.
   */
  queryErrors(operationId: string, query: Record<string, string | string[]>): string[] {
    const op = this.operation(operationId);
    const params = Array.isArray(op.node.parameters) ? op.node.parameters : [];
    const errors: string[] = [];
    const declared = new Set<string>();
    params.forEach((raw, index) => {
      const param = asObject(raw, `${op.operationId} parameter ${index}`);
      if (param.in !== "query") {
        return;
      }
      const name = String(param.name);
      declared.add(name);
      const value = query[name];
      if (value === undefined) {
        if (param.required === true) {
          errors.push(`${name} is required`);
        }
        return;
      }
      if (Array.isArray(value)) {
        errors.push(`${name} is repeated`);
        return;
      }
      const schema = param.schema as JsonObject | undefined;
      const numeric = schema?.type === "integer" && /^-?\d+$/.test(value);
      const parsed = numeric ? Number(value) : value;
      for (const message of this.errorsAt(`${op.pointer}/parameters/${index}/schema`, parsed)) {
        errors.push(`${name}: ${message}`);
      }
    });
    for (const name of Object.keys(query)) {
      if (!declared.has(name)) {
        errors.push(`${name} is not a parameter`);
      }
    }
    return errors;
  }

  /**
   * Errors of an HTTP response against the operation: the status is documented, the content
   * type matches and the body validates against the schema of that status.
   */
  responseErrors(operationId: string, response: CheckedResponse): string[] {
    const op = this.operation(operationId);
    const responses = asObject(op.node.responses, `${operationId} responses`);
    const status = String(response.statusCode);
    let node = responses[status];
    let pointer = `${op.pointer}/responses/${status}`;
    if (node === undefined) {
      return [`status ${status} is not documented for ${operationId}`];
    }
    let resolved = asObject(node, pointer);
    if (typeof resolved.$ref === "string") {
      pointer = resolved.$ref;
      node = asObject(this.doc.components, "components");
      for (const token of pointer.replace(/^#\//, "").split("/").slice(1)) {
        node = asObject(node, pointer)[token.replace(/~1/g, "/").replace(/~0/g, "~")];
      }
      resolved = asObject(node, pointer);
    }
    const content = resolved.content === undefined ? {} : asObject(resolved.content, pointer);
    const types = Object.keys(content);
    if (types.length === 0) {
      return response.body === "" ? [] : [`${status} documents no body`];
    }
    const contentType = String(response.headers["content-type"] ?? "")
      .split(";")[0]
      ?.trim();
    if (contentType === undefined || !types.includes(contentType)) {
      return [`content type ${contentType} is not one of ${types.join(", ")}`];
    }
    let body: unknown;
    try {
      body = JSON.parse(response.body);
    } catch {
      return ["body is not JSON"];
    }
    return this.errorsAt(`${pointer}/content/${escapePointer(contentType)}/schema`, body);
  }
}
