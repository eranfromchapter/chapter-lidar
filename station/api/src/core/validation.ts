// Request validation for every route (F7: "Request validation never coerces types: a wrong
// type is rejected with 400, not converted").
//
// - Bodies (JSON) are validated without type coercion: {"count": "5"} against an integer is
//   400, never stored as 5. The same holds for any other part Fastify may add later.
// - Query strings, path parameters and headers are always text on the wire, so their values are
//   parsed to the declared type as Fastify does by default (coerceTypes "array": "2" -> 2, a
//   single value -> a one-item array). A value that is not of the declared type ("two") is
//   still 400.
// - Otherwise both follow Fastify's defaults (@fastify/ajv-compiler): defaults applied, every
//   ajv-formats format, allErrors off (first error only; allErrors on is a DoS risk). Unknown
//   properties are rejected (additionalProperties: false -> 400), not stripped.
//
// Validation errors keep the Ajv shape, so the core error handler answers 400 invalid_request.

import { Ajv, type Options, type ValidateFunction } from "ajv";
import addFormatsModule from "ajv-formats";
import type { FastifySchema, FastifySchemaCompiler } from "fastify";

/** Request parts whose values arrive as text and are parsed to their declared types. */
export const TEXT_HTTP_PARTS: ReadonlySet<string> = new Set(["querystring", "params", "headers"]);

const SHARED_OPTIONS: Options = {
  useDefaults: true,
  removeAdditional: false,
  addUsedSchema: false,
  allErrors: false,
};

function createAjv(coerceTypes: Options["coerceTypes"]): Ajv {
  const ajv = new Ajv({ ...SHARED_OPTIONS, coerceTypes });
  // ajv-formats is CommonJS: under NodeNext the default import is module.exports, whose
  // .default is the plugin. Every format, as Fastify's default compiler adds.
  addFormatsModule.default(ajv);
  return ajv;
}

function compileWith(ajv: Ajv, schema: FastifySchema): ValidateFunction {
  const id = (schema as { $id?: unknown }).$id;
  if (typeof id === "string") {
    // Ajv refuses a second schema with the same $id in one instance; reuse the first.
    const stored = ajv.getSchema(id);
    if (stored !== undefined) {
      return stored;
    }
  }
  return ajv.compile(schema as object);
}

/**
 * A validator compiler: no coercion for bodies, text parsing for query strings, path
 * parameters and headers. Each call creates its own Ajv instances (one per server).
 */
export function createRequestValidatorCompiler(): FastifySchemaCompiler<FastifySchema> {
  const strict = createAjv(false);
  const text = createAjv("array");
  return ({ schema, httpPart }) =>
    compileWith(httpPart !== undefined && TEXT_HTTP_PARTS.has(httpPart) ? text : strict, schema);
}
