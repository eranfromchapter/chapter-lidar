// Check 4: units and scale. Each field-control distance (the independent reference) is compared
// with the capture model's plan geometry using the tolerance rule in tolerance.ts.
//
// Matching a control to model geometry, without trusting compass words (the capture frame is
// not aligned to north):
// - The rooms a control spans are the model rooms whose label starts its "from" and "to" text
//   (for example "Living Room west wall" -> Living Room). When either end names no model room,
//   the whole capture is used.
// - The model distance is the extent of those rooms along the capture's principal wall
//   direction (u) or its perpendicular (v).
// - Axis A and axis B are perpendicular: either A runs along u and B along v, or the reverse.
//   The assignment with the smaller worst relative difference is used (ties: A along u).
// Only capture-model.json is compared: DXF, CSV and the meshes are exports of the same capture
// and are not independent evidence (check 12).

import type { CaptureModel, Distance } from "@chapter/capture-contract";
import type { CaptureInfo, CheckContext } from "../context.js";
import { NO_ACTION, finding, mm, scopeOf } from "../finding.js";
import { extentsAlong, planOutline, principalAngle } from "../geometry.js";
import {
  gradeDistance,
  worstGrade,
  type DistanceComparison,
  type ScaleGrade,
} from "../tolerance.js";
import type { CheckOutput, StationFinding } from "../types.js";

export const SCALE_EXPECTED =
  "within max(1% of control, 25.4 mm); over that up to 3% is a limitation; over 3% blocks the floor";

export interface ControlComparison {
  control: Distance;
  /** Rooms the model distance was measured over, or "whole capture". */
  basis: string;
  result: DistanceComparison;
}

export type ScaleAssessment =
  | { state: "graded"; grade: ScaleGrade; comparisons: ControlComparison[] }
  | { state: "unverified"; reason: string; filePath: string }
  | { state: "not_evaluated"; reason: string; filePath: string };

function normalizeLabel(text: string): string {
  return text.normalize("NFKC").toLowerCase().replace(/\s+/g, " ").trim();
}

/** Rooms whose label is the longest label that starts the text (followed by a space or end). */
function roomsNamedIn(model: CaptureModel, text: string): string[] {
  const subject = normalizeLabel(text);
  let best = "";
  for (const room of model.rooms) {
    const label = normalizeLabel(room.label);
    if (label.length > best.length && (subject === label || subject.startsWith(`${label} `))) {
      best = label;
    }
  }
  return best === ""
    ? []
    : model.rooms.filter((room) => normalizeLabel(room.label) === best).map((room) => room.id);
}

function compareControls(model: CaptureModel, controls: Distance[]): ControlComparison[] {
  const whole = planOutline(model);
  const angle = principalAngle(whole.edges);
  const spans = controls.map((control) => {
    const from = roomsNamedIn(model, control.from);
    const to = roomsNamedIn(model, control.to);
    if (from.length === 0 || to.length === 0) {
      return { control, basis: "whole capture", extents: extentsAlong(whole.points, angle) };
    }
    const ids = new Set([...from, ...to]);
    const labels = [...new Set(model.rooms.filter((room) => ids.has(room.id)).map((r) => r.label))];
    return {
      control,
      basis: labels.join(" + "),
      extents: extentsAlong(planOutline(model, ids).points, angle),
    };
  });
  const evaluate = (aAlongU: boolean) =>
    spans.map(({ control, basis, extents }) => {
      const alongU = control.axis === "A" ? aAlongU : !aAlongU;
      const modelMm = (alongU ? extents.u : extents.v) * 1000;
      return { control, basis, result: gradeDistance(modelMm, control.measurement.valueMm) };
    });
  const worst = (list: ControlComparison[]) =>
    Math.max(...list.map((item) => item.result.diffMm / item.result.controlMm));
  const first = evaluate(true);
  const second = evaluate(false);
  return worst(second) < worst(first) ? second : first;
}

function assessCapture(ctx: CheckContext, capture: CaptureInfo): ScaleAssessment {
  const controls = ctx.pkg.fieldControls;
  if (controls === undefined) {
    const entry = ctx.firstOfRole("field_controls");
    if (entry !== undefined) {
      return {
        state: "not_evaluated",
        reason: "field controls cannot be read (see manifest.fingerprints and files.parseable)",
        filePath: entry.path,
      };
    }
    return {
      state: "unverified",
      reason: "the package has no field controls",
      filePath: ctx.manifestPath,
    };
  }
  const lookup = ctx.model(capture.captureId);
  if (lookup.state === "absent") {
    return {
      state: "unverified",
      reason: "the capture has no capture model to compare with",
      filePath: ctx.recordPath(),
    };
  }
  if (lookup.state === "unreadable") {
    return {
      state: "not_evaluated",
      reason: "the capture model cannot be read (see files.parseable)",
      filePath: lookup.entry.path,
    };
  }
  const distances = controls.distances.filter(
    (distance) =>
      distance.capture.captureId === capture.captureId &&
      distance.capture.areaKey === capture.areaKey,
  );
  if (distances.length === 0) {
    return {
      state: "unverified",
      reason: "no field-control distance was recorded for this floor",
      filePath: ctx.controlsPath(),
    };
  }
  if (planOutline(lookup.model).points.length === 0) {
    return {
      state: "unverified",
      reason: "the capture model has no rooms or walls to measure",
      filePath: lookup.entry.path,
    };
  }
  const comparisons = compareControls(lookup.model, distances);
  return {
    state: "graded",
    grade: worstGrade(comparisons.map((item) => item.result.grade)),
    comparisons,
  };
}

/** Scale assessment per captureId, shared with the plausibility check. */
export function assessScale(ctx: CheckContext): Map<string, ScaleAssessment> {
  return ctx.shared(
    "scale",
    () =>
      new Map(ctx.captures().map((capture) => [capture.captureId, assessCapture(ctx, capture)])),
  );
}

function signed(value: number, digits: number): string {
  return `${value > 0 ? "+" : value < 0 ? "-" : "±"}${Math.abs(value).toFixed(digits)}`;
}

function describeComparison(item: ControlComparison): string {
  const { control, result } = item;
  return `${control.id} (axis ${control.axis}, ${item.basis}): model ${mm(result.modelMm)} vs control ${mm(result.controlMm)}, ${signed(result.signedDiffMm, 1)} mm (${signed(result.percentOfControl, 2)}%)`;
}

export function checkScale(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  const assessments = assessScale(ctx);
  for (const capture of ctx.captures()) {
    const assessment = assessments.get(capture.captureId);
    if (assessment === undefined) {
      continue;
    }
    const scope = scopeOf(capture);
    if (assessment.state === "not_evaluated") {
      findings.push(
        finding({
          ruleId: "units.scale",
          severity: "info",
          message: `Scale of ${capture.label} not evaluated: ${assessment.reason}.`,
          filePath: assessment.filePath,
          ...scope,
          measured: "not evaluated",
          nextAction: NO_ACTION,
        }),
      );
      continue;
    }
    if (assessment.state === "unverified") {
      findings.push(
        finding({
          ruleId: "units.scale",
          severity: "limitation",
          message: `Scale of ${capture.label} is not verified: ${assessment.reason}.`,
          filePath: assessment.filePath,
          ...scope,
          measured: assessment.reason,
          expected: "two long perpendicular tape or laser distances per floor",
          nextAction: `Measure two long perpendicular distances on ${capture.label} with tape or laser on the next visit.`,
        }),
      );
      continue;
    }
    const measured = assessment.comparisons.map(describeComparison).join("; ");
    const filePath = ctx.capturePath(capture.captureId);
    const messages: Record<ScaleGrade, string> = {
      pass: `Plan geometry of ${capture.label} agrees with the field-control distances.`,
      limitation: `Plan geometry of ${capture.label} differs from a field-control distance by more than max(1%, 25.4 mm) but not more than 3%.`,
      blocker: `Plan geometry of ${capture.label} differs from a field-control distance by more than 3%; scale is not established for this floor.`,
    };
    const actions: Record<ScaleGrade, string> = {
      pass: NO_ACTION,
      limitation: `Re-measure the flagged distance on ${capture.label} and confirm the plan dimensions there before relying on them.`,
      blocker: `Re-measure the control distances on ${capture.label} with tape or laser and check the capture's units; recapture ${capture.label} if the model is wrong.`,
    };
    findings.push(
      finding({
        ruleId: "units.scale",
        severity: assessment.grade === "pass" ? "info" : assessment.grade,
        message: messages[assessment.grade],
        filePath,
        ...scope,
        measured,
        expected: SCALE_EXPECTED,
        nextAction: actions[assessment.grade],
      }),
    );
  }
  return ctx.captures().length === 0 ? { findings, notApplicable: true } : { findings };
}
