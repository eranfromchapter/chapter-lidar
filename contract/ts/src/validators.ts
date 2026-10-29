// Ajv validators for every contract schema.
//
// One Ajv 2020-12 instance in strict mode with the uuid and date-time formats.
// The schemas are self-contained, so each one compiles on its own. Validators
// compile on first use and are cached.

import { Ajv2020, type ErrorObject, type ValidateFunction } from "ajv/dist/2020.js";
import addFormatsModule from "ajv-formats";
import type { CaptureModel } from "./generated/capture-model.js";
import type { CaptureRecord } from "./generated/capture-record.js";
import type { FieldControls } from "./generated/field-controls.js";
import type { PackageManifest } from "./generated/manifest.js";
import {
  captureModelSchema,
  captureRecordSchema,
  fieldControlsSchema,
  manifestSchema,
  sketchMeasurementsSchema,
  verdictSchema,
} from "./generated/schemas.js";
import type { SketchMeasurements } from "./generated/sketch-measurements.js";
import type { Verdict } from "./generated/verdict.js";

/** Short schema names: the schema file name without `.schema.json`. */
export const SCHEMA_NAMES = [
  "capture-record",
  "capture-model",
  "field-controls",
  "manifest",
  "sketch-measurements",
  "verdict",
] as const;

export type SchemaName = (typeof SCHEMA_NAMES)[number];

/** The document type each schema describes. */
export interface SchemaTypes {
  "capture-record": CaptureRecord;
  "capture-model": CaptureModel;
  "field-controls": FieldControls;
  manifest: PackageManifest;
  "sketch-measurements": SketchMeasurements;
  verdict: Verdict;
}

/** The JSON Schema objects, exactly as in contract/schema/<name>.schema.json. */
export const SCHEMAS: Readonly<Record<SchemaName, Record<string, unknown>>> = {
  "capture-record": captureRecordSchema,
  "capture-model": captureModelSchema,
  "field-controls": fieldControlsSchema,
  manifest: manifestSchema,
  "sketch-measurements": sketchMeasurementsSchema,
  verdict: verdictSchema,
};

/** One schema violation. */
export interface ContractError {
  /** JSON Pointer to the failing value in the document ("" is the root). */
  instancePath: string;
  /** JSON Pointer to the failing keyword in the schema. */
  schemaPath: string;
  /** Failing JSON Schema keyword, for example "required" or "enum". */
  keyword: string;
  /** Keyword parameters from Ajv, for example { missingProperty: "captureId" }. */
  params: Record<string, unknown>;
  /** Human-readable message. */
  message: string;
}

export type ValidationResult<T> =
  { ok: true; value: T; errors: [] } | { ok: false; errors: ContractError[] };

function createAjv(): Ajv2020 {
  const ajv = new Ajv2020({ strict: true, allErrors: true });
  // ajv-formats is CommonJS: under NodeNext the default import is module.exports,
  // whose .default is the plugin. Bundlers resolve .default to the same function.
  addFormatsModule.default(ajv, ["uuid", "date-time"]);
  return ajv;
}

let ajv: Ajv2020 | undefined;
const compiled = new Map<SchemaName, ValidateFunction>();

/** Returns the compiled Ajv validator for a schema. Throws if the schema does not compile. */
export function getValidator<N extends SchemaName>(name: N): ValidateFunction<SchemaTypes[N]> {
  let validator = compiled.get(name);
  if (!validator) {
    ajv ??= createAjv();
    validator = ajv.compile(SCHEMAS[name]);
    compiled.set(name, validator);
  }
  return validator as ValidateFunction<SchemaTypes[N]>;
}

function toContractError(error: ErrorObject): ContractError {
  return {
    instancePath: error.instancePath,
    schemaPath: error.schemaPath,
    keyword: error.keyword,
    params: { ...error.params },
    message: error.message ?? error.keyword,
  };
}

/** Validates a parsed JSON document against one contract schema. */
export function validate<N extends SchemaName>(
  name: N,
  data: unknown,
): ValidationResult<SchemaTypes[N]> {
  const validator = getValidator(name);
  if (validator(data)) {
    return { ok: true, value: data, errors: [] };
  }
  return { ok: false, errors: (validator.errors ?? []).map(toContractError) };
}

export function validateCaptureRecord(data: unknown): ValidationResult<CaptureRecord> {
  return validate("capture-record", data);
}

export function validateCaptureModel(data: unknown): ValidationResult<CaptureModel> {
  return validate("capture-model", data);
}

export function validateFieldControls(data: unknown): ValidationResult<FieldControls> {
  return validate("field-controls", data);
}

export function validateManifest(data: unknown): ValidationResult<PackageManifest> {
  return validate("manifest", data);
}

export function validateVerdict(data: unknown): ValidationResult<Verdict> {
  return validate("verdict", data);
}

export function validateSketchMeasurements(data: unknown): ValidationResult<SketchMeasurements> {
  return validate("sketch-measurements", data);
}

/** Formats errors as one line each: "<instancePath or /> <message>". */
export function formatErrors(errors: readonly ContractError[]): string {
  return errors.map((error) => `${error.instancePath || "/"} ${error.message}`).join("\n");
}
