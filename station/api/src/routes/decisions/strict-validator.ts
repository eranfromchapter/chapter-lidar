// Validator for JSON request bodies that does not coerce types.
//
// Fastify's default validator coerces scalars (coerceTypes "array"), so {"element": 5} would
// be stored as "5" although the OpenAPI document rejects it. Routes whose body must match the
// document exactly use this compiler instead: no coercion, no defaults, unknown properties
// rejected (not removed). Errors keep the Ajv shape, so the core error handler answers 400
// invalid_request with JSON Pointers as for any other body.

import { Ajv } from "ajv";
import addFormatsModule from "ajv-formats";
import type { FastifySchemaCompiler } from "fastify";

const ajv = new Ajv({
  coerceTypes: false,
  useDefaults: false,
  removeAdditional: false,
  allErrors: true,
  strict: true,
});
// ajv-formats is CommonJS: under NodeNext the default import is module.exports, whose
// .default is the plugin.
addFormatsModule.default(ajv, ["uuid", "date-time"]);

export const strictBodyValidator: FastifySchemaCompiler<unknown> = ({ schema }) =>
  ajv.compile(schema as object);
