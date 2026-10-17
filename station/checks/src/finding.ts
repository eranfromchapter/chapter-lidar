// Finding construction and the outcome rule.

import type { Outcome } from "@chapter/capture-contract";
import type { RuleId, Severity, StationFinding } from "./types.js";

/** Schema limits of the verdict finding fields. */
const MAX_MESSAGE = 1000;
const MAX_FIELD = 500;

/** Next action text for findings that need nothing. */
export const NO_ACTION = "None";

/** Shortens text to a schema limit, marking the cut with an ellipsis. Empty text becomes "-". */
export function clip(text: string, max: number): string {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return "-";
  }
  return trimmed.length <= max ? trimmed : `${trimmed.slice(0, max - 1)}…`;
}

export interface FindingInput {
  ruleId: RuleId;
  severity: Severity;
  message: string;
  filePath: string;
  measured: string;
  nextAction: string;
  expected?: string;
  captureId?: string;
  areaKey?: string;
}

/** Builds a finding with every field inside the verdict schema limits. */
export function finding(input: FindingInput): StationFinding {
  const out: StationFinding = {
    ruleId: input.ruleId,
    severity: input.severity,
    message: clip(input.message, MAX_MESSAGE),
    filePath: input.filePath,
    measured: clip(input.measured, MAX_FIELD),
    nextAction: clip(input.nextAction, MAX_FIELD),
  };
  if (input.captureId !== undefined) {
    out.captureId = input.captureId;
  }
  if (input.areaKey !== undefined) {
    out.areaKey = input.areaKey;
  }
  if (input.expected !== undefined) {
    out.expected = clip(input.expected, MAX_FIELD);
  }
  return out;
}

/** captureId and areaKey of a manifest entry or capture, for spreading into a finding. */
export function scopeOf(item: { captureId?: string; areaKey?: string }): {
  captureId?: string;
  areaKey?: string;
} {
  return {
    ...(item.captureId === undefined ? {} : { captureId: item.captureId }),
    ...(item.areaKey === undefined ? {} : { areaKey: item.areaKey }),
  };
}

/** Outcome rule: any blocker -> blocked; else any limitation -> limited; else ready. */
export function outcomeOf(findings: ReadonlyArray<{ severity: Severity }>): Outcome {
  if (findings.some((item) => item.severity === "blocker")) {
    return "blocked";
  }
  if (findings.some((item) => item.severity === "limitation")) {
    return "limited";
  }
  return "ready";
}

/** True for blocker and limitation findings. */
export function isActionable(item: { severity: Severity }): boolean {
  return item.severity !== "info";
}

/** Formats a length in millimetres with one decimal, for example 3880.0 mm. */
export function mm(value: number): string {
  return `${value.toFixed(1)} mm`;
}

/** Formats a length in metres with three decimals, for example 2.700 m. */
export function metres(value: number): string {
  return `${value.toFixed(3)} m`;
}

/** Plural helper: "1 file", "2 files". */
export function count(n: number, singular: string, plural = `${singular}s`): string {
  return `${n} ${n === 1 ? singular : plural}`;
}
