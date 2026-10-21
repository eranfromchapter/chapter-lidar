// contract/openapi/station.yaml as executable JSON Schemas (Ajv, JSON Schema 2020-12, the
// dialect of OpenAPI 3.1), for the web's station-contract test: every call the review screen
// makes must be a documented operation with valid parameters, and every answer of the fake
// station must validate against the documented response.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { SCHEMAS } from "@chapter/capture-contract";
import { Ajv2020, type ValidateFunction } from "ajv/dist/2020.js";
import addFormatsModule from "ajv-formats";
import { parse } from "yaml";
import { REPO_ROOT } from "./fixtures";

const SCHEMA_BASE = "https://hellochapter.com/schemas/chapter-capture/v1/";
const DOC_ID = `${SCHEMA_BASE}openapi/station.json`;
const METHODS = ["get", "put", "post", "delete", "patch"] as const;

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type JsonObject = { [key: string]: Json };

export interface Operation {
  readonly operationId: string;
  readonly method: string;
  readonly path: string;
  readonly pattern: RegExp;
  /** The station roles allowed to call it (x-roles). */
  readonly roles: readonly string[];
  readonly node: JsonObject;
  readonly pointer: string;
}

function escapePointer(token: string): string {
  return token.replace(/~/g, "~0").replace(/\//g, "~1");
}

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

function object(value: Json | undefined, where: string): JsonObject {
  if (value === null || value === undefined || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`OpenAPI: ${where} is not an object`);
  }
  return value;
}

export class StationOpenApi {
  readonly version: string;
  readonly operations: readonly Operation[];
  private readonly doc: JsonObject;
  private readonly ajv: Ajv2020;
  private readonly cache = new Map<string, ValidateFunction>();

  constructor() {
    const raw = readFileSync(join(REPO_ROOT, "contract/openapi/station.yaml"), "utf8");
    this.doc = object(rewriteRefs(parse(raw) as Json), "document");
    this.version = String(object(this.doc.info, "info").version);
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
    for (const [path, item] of Object.entries(object(this.doc.paths, "paths"))) {
      for (const method of METHODS) {
        const node = object(item, path)[method];
        if (node === undefined) {
          continue;
        }
        const op = object(node, `${method} ${path}`);
        operations.push({
          operationId: String(op.operationId),
          method: method.toUpperCase(),
          path,
          pattern: new RegExp(`^${path.replace(/\{[^}]+\}/g, "[^/]+")}$`),
          roles: Array.isArray(op["x-roles"]) ? op["x-roles"].map(String) : [],
          node: op,
          pointer: `#/paths/${escapePointer(path)}/${method}`,
        });
      }
    }
    this.operations = operations;
  }

  /** The operation a request goes to (path under /v1), or undefined. */
  match(method: string, path: string): Operation | undefined {
    return this.operations.find((op) => op.method === method && op.pattern.test(path));
  }

  private validator(pointer: string): ValidateFunction {
    let found = this.cache.get(pointer);
    if (found === undefined) {
      found = this.ajv.compile({ $ref: `${DOC_ID}${pointer}` });
      this.cache.set(pointer, found);
    }
    return found;
  }

  private errorsAt(pointer: string, value: unknown): string[] {
    const validate = this.validator(pointer);
    return validate(value)
      ? []
      : (validate.errors ?? []).map(
          (error) => `${error.instancePath || "/"} ${error.message ?? error.keyword}`,
        );
  }

  /** Query parameters: declared, required ones present, values valid. */
  queryErrors(op: Operation, query: URLSearchParams): string[] {
    const params = Array.isArray(op.node.parameters) ? op.node.parameters : [];
    const errors: string[] = [];
    const declared = new Set<string>();
    params.forEach((raw, index) => {
      const param = object(raw, `${op.operationId} parameter ${index}`);
      if (param.in !== "query") {
        return;
      }
      const name = String(param.name);
      declared.add(name);
      const value = query.get(name);
      if (value === null) {
        if (param.required === true) {
          errors.push(`${name} is required`);
        }
        return;
      }
      const schema = param.schema as JsonObject | undefined;
      const parsed = schema?.type === "integer" && /^-?\d+$/.test(value) ? Number(value) : value;
      for (const message of this.errorsAt(`${op.pointer}/parameters/${index}/schema`, parsed)) {
        errors.push(`${name}: ${message}`);
      }
    });
    for (const name of query.keys()) {
      if (!declared.has(name)) {
        errors.push(`${name} is not a parameter of ${op.operationId}`);
      }
    }
    return errors;
  }

  /** The request body against the operation's schema. */
  bodyErrors(op: Operation, body: unknown): string[] {
    return this.errorsAt(`${op.pointer}/requestBody/content/application~1json/schema`, body);
  }

  /** A JSON answer against the documented response of its status. */
  responseErrors(op: Operation, status: number, body: unknown): string[] {
    const responses = object(op.node.responses, `${op.operationId} responses`);
    const node = responses[String(status)];
    if (node === undefined) {
      return [`status ${status} is not documented for ${op.operationId}`];
    }
    let pointer = `${op.pointer}/responses/${status}`;
    let resolved = object(node, pointer);
    if (typeof resolved.$ref === "string") {
      pointer = resolved.$ref;
      let walk: Json = this.doc;
      for (const token of pointer.replace(/^#\//, "").split("/")) {
        walk = object(walk, pointer)[token.replace(/~1/g, "/").replace(/~0/g, "~")] ?? null;
      }
      resolved = object(walk, pointer);
    }
    const content = resolved.content === undefined ? {} : object(resolved.content, pointer);
    const type = status >= 400 ? "application/problem+json" : "application/json";
    if (content[type] === undefined) {
      return [`${op.operationId} ${status} documents no ${type} body`];
    }
    return this.errorsAt(`${pointer}/content/${escapePointer(type)}/schema`, body);
  }
}
