// Modeling decision form: field names, limits (OpenAPI ModelingDecisionInput) and parsing of
// the untrusted form data before it is sent to the station.

import type { ModelingDecisionInput } from "./station-types";

export interface DecisionFormValues {
  readonly element: string;
  readonly source: string;
  readonly decision: string;
  /** "Remaining uncertainty and next check", sent as the decision's note. */
  readonly note: string;
}

/** Form state; `attempt` counts answers so the form remounts with the echoed values. */
export type DecisionFormState =
  | { readonly status: "idle"; readonly attempt: number }
  | { readonly status: "saved"; readonly attempt: number; readonly message: string }
  | {
      readonly status: "error";
      readonly attempt: number;
      readonly message: string;
      readonly values: DecisionFormValues;
    };

export const EMPTY_VALUES: DecisionFormValues = { element: "", source: "", decision: "", note: "" };

export const LIMITS = {
  element: 300,
  decision: 2000,
  note: 2000,
  path: 1024,
} as const;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function isPackageId(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

function text(form: FormData, name: string): string {
  const value = form.get(name);
  return typeof value === "string" ? value.trim() : "";
}

/** The submitted values, echoed back so the form keeps them after an error. */
export function formValues(form: FormData): DecisionFormValues {
  return {
    element: text(form, "element"),
    source: text(form, "source"),
    decision: text(form, "decision"),
    note: text(form, "note"),
  };
}

export type ParsedDecision =
  | { readonly ok: true; readonly packageId: string; readonly input: ModelingDecisionInput }
  | { readonly ok: false; readonly message: string; readonly values: DecisionFormValues };

/** Validates the decision form. Everything else (source belongs to the package) is the station's. */
export function parseDecisionForm(form: FormData): ParsedDecision {
  const values = formValues(form);
  const packageId = text(form, "packageId");
  const problems: string[] = [];
  if (!isPackageId(packageId)) {
    problems.push("the package is unknown");
  }
  if (values.element.length === 0) {
    problems.push("name the element or area");
  } else if (values.element.length > LIMITS.element) {
    problems.push(`keep the element or area under ${LIMITS.element} characters`);
  }
  if (values.source.length === 0) {
    problems.push("choose the source used");
  } else if (values.source.length > LIMITS.path) {
    problems.push("the source is not a package file");
  }
  if (values.decision.length === 0) {
    problems.push("describe the decision");
  } else if (values.decision.length > LIMITS.decision) {
    problems.push(`keep the decision under ${LIMITS.decision} characters`);
  }
  if (values.note.length > LIMITS.note) {
    problems.push(`keep the uncertainty and next check under ${LIMITS.note} characters`);
  }
  if (problems.length > 0) {
    const message = problems.join("; ");
    return { ok: false, message: message.charAt(0).toUpperCase() + message.slice(1) + ".", values };
  }
  return {
    ok: true,
    packageId,
    input: {
      element: values.element,
      decision: values.decision,
      sources: [{ path: values.source }],
      ...(values.note.length > 0 ? { note: values.note } : {}),
    },
  };
}
