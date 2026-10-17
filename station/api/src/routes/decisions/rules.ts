// Cross-field rules of a modeling decision that the JSON Schema cannot express. A broken rule
// is a 422 with one error (JSON Pointer + message) per violation.
//
// - areaKey is present exactly when captureId is (OpenAPI ModelingDecisionInput.areaKey).
// - captureId/areaKey name a capture of the package (a file of the package carries that pair).
// - every source path is a file of the package (DecisionSource: "one package file").
// - controlId only on the field-controls file, elementId only on a capture model
//   (DecisionSource.controlId / elementId).

import type { ProblemFieldError } from "../../core/problem.js";
import type { ModelingDecisionInput } from "./schemas.js";

export interface PackageFileRef {
  readonly path: string;
  readonly role: string;
  readonly captureId: string | null;
  readonly areaKey: string | null;
}

export function decisionRuleErrors(
  input: ModelingDecisionInput,
  files: readonly PackageFileRef[],
): ProblemFieldError[] {
  const errors: ProblemFieldError[] = [];

  const hasCapture = input.captureId !== undefined;
  const hasArea = input.areaKey !== undefined;
  if (hasCapture !== hasArea) {
    errors.push({
      pointer: hasCapture ? "/areaKey" : "/captureId",
      message: "captureId and areaKey must be given together",
    });
  } else if (hasCapture) {
    const known = files.some(
      (file) => file.captureId === input.captureId && file.areaKey === input.areaKey,
    );
    if (!known) {
      errors.push({
        pointer: "/captureId",
        message: "the package has no capture with this captureId and areaKey",
      });
    }
  }

  const byPath = new Map(files.map((file) => [file.path, file]));
  input.sources.forEach((source, index) => {
    const file = byPath.get(source.path);
    if (file === undefined) {
      errors.push({ pointer: `/sources/${index}/path`, message: "not a file of the package" });
      return;
    }
    if (source.controlId !== undefined && file.role !== "field_controls") {
      errors.push({
        pointer: `/sources/${index}/controlId`,
        message: "controlId is allowed only when path is the field-controls file",
      });
    }
    if (source.elementId !== undefined && file.role !== "capture_model") {
      errors.push({
        pointer: `/sources/${index}/elementId`,
        message: "elementId is allowed only when path is a capture model",
      });
    }
  });

  return errors;
}
