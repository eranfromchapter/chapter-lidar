// Check 10: plausibility of the capture model. Ceiling 2.0-6.0 m, door width 0.6-1.5 m, window
// sill >= 0 (bounds inclusive). Outliers are limitations. A floor whose scale is blocked by
// check 4 is not evaluated: its lengths are wrong as a whole, which check 4 already reports.

import type { CheckContext } from "../context.js";
import { NO_ACTION, finding, metres, scopeOf } from "../finding.js";
import type { CheckOutput, StationFinding } from "../types.js";
import { assessScale } from "./scale.js";

export const CEILING_RANGE_M = [2.0, 6.0] as const;
export const DOOR_WIDTH_RANGE_M = [0.6, 1.5] as const;
export const MIN_SILL_M = 0;

/** Rounds to 1e-9 m so float noise does not push a boundary value out of range. */
function r9(value: number): number {
  return Math.round(value * 1e9) / 1e9;
}

function inRange(value: number, [low, high]: readonly [number, number]): boolean {
  const v = r9(value);
  return v >= low && v <= high;
}

export function checkPlausibility(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  const scale = assessScale(ctx);
  let evaluated = 0;
  for (const capture of ctx.captures()) {
    const lookup = ctx.model(capture.captureId);
    if (lookup.state !== "ok") {
      continue; // No model (check 4 reports) or unreadable (check 2 reports).
    }
    const scope = scopeOf(capture);
    const filePath = lookup.entry.path;
    const assessment = scale.get(capture.captureId);
    if (assessment?.state === "graded" && assessment.grade === "blocker") {
      findings.push(
        finding({
          ruleId: "geometry.plausibility",
          severity: "info",
          message: `Plausibility of ${capture.label} not evaluated: its scale is blocked (see units.scale).`,
          filePath,
          ...scope,
          measured: "not evaluated",
          nextAction: NO_ACTION,
        }),
      );
      continue;
    }
    evaluated += 1;
    const model = lookup.model;
    const before = findings.length;
    const outlier = (message: string, measured: string, expected: string, nextAction: string) =>
      findings.push(
        finding({
          ruleId: "geometry.plausibility",
          severity: "limitation",
          message,
          filePath,
          ...scope,
          measured,
          expected,
          nextAction,
        }),
      );
    for (const room of model.rooms) {
      if (!inRange(room.heightM, CEILING_RANGE_M)) {
        outlier(
          `Ceiling height of ${room.label} is outside the plausible range.`,
          `${room.label} (${room.id}) ceiling ${metres(room.heightM)}`,
          "2.000 m to 6.000 m",
          `Measure the ceiling height of ${room.label} with tape or laser and photograph the ceiling.`,
        );
      }
    }
    for (const door of model.doors) {
      if (!inRange(door.widthM, DOOR_WIDTH_RANGE_M)) {
        outlier(
          `Door ${door.id} width is outside the plausible range.`,
          `${door.id} in ${door.wallId}: width ${metres(door.widthM)}`,
          "0.600 m to 1.500 m",
          `Measure the width of door ${door.id} with tape and photograph it.`,
        );
      }
    }
    for (const win of model.windows) {
      if (r9(win.bottomM) < MIN_SILL_M) {
        outlier(
          `Window ${win.id} sill is below the floor.`,
          `${win.id} in ${win.wallId}: sill ${metres(win.bottomM)}`,
          "sill at or above 0.000 m",
          `Measure the sill height of window ${win.id} and photograph it.`,
        );
      }
    }
    if (findings.length === before) {
      const list = (values: number[]) =>
        values.length === 0 ? "none" : [...new Set(values.map((v) => metres(v)))].join(", ");
      findings.push(
        finding({
          ruleId: "geometry.plausibility",
          severity: "info",
          message: `Ceiling heights, door widths and window sills of ${capture.label} are plausible.`,
          filePath,
          ...scope,
          measured: `ceilings ${list(model.rooms.map((r) => r.heightM))}; doors ${list(model.doors.map((d) => d.widthM))}; sills ${list(model.windows.map((w) => w.bottomM))}`,
          expected: "ceiling 2.0-6.0 m, door width 0.6-1.5 m, sill >= 0",
          nextAction: NO_ACTION,
        }),
      );
    }
  }
  return evaluated === 0 ? { findings, notApplicable: true } : { findings };
}
