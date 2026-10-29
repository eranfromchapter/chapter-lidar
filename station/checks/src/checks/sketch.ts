// Check 14: sketch measurements (spec F14 1.7). A sketch capture (capture record 1.2.0,
// `captureSource: sketch`) carries, in the record, what the sketch solver had: how many walls were
// measured and how many estimated, whether the ceiling height was measured or assumed, and the
// largest closure residual. The capture model carries the marking per element: a wall, door,
// window or opening the operator measured is `confidence: high`; a derived one `medium`; an
// estimated one `low`. For each sketch capture the check writes:
// - one info finding that says the geometry comes from a measured sketch, not a scan (the report's
//   checks table shows it); when everything was measured it carries the counts;
// - a limitation naming the estimated walls, a limitation when the ceiling height is assumed, a
//   limitation naming the estimated openings, each with the measurement to take on the next visit;
// - the closure residual against the scale tolerance of check 4, max(1% of the floor's extent,
//   25.4 mm): an info when within, a limitation when over;
// - a limitation when the originals of the capture (the sketch image and the entered measurements)
//   are missing from the manifest.
// A sketch capture without a capture model, or whose model cannot be read, is not evaluated (checks
// 2 and 4 report it). Not applicable when the package has no sketch capture, so LiDAR verdicts do
// not change.

import { captureSourceOf, type Capture, type CaptureModel } from "@chapter/capture-contract";
import type { CheckContext } from "../context.js";
import { NO_ACTION, count, finding, metres, mm, scopeOf } from "../finding.js";
import { extentsAlong, planOutline, principalAngle } from "../geometry.js";
import { ONE_INCH_MM, gradeDistance, type DistanceComparison } from "../tolerance.js";
import type { CheckOutput, StationFinding } from "../types.js";

/** What the rule expects of every sketch capture. */
export const SKETCH_EXPECTED =
  "every wall and opening measured, ceiling height measured, closure residual within max(1% of the floor's extent, 25.4 mm), sketch image and measurements in the package";

/** The ceiling height the solver assumes when the operator did not measure it (spec F14 1.5). */
export const ASSUMED_CEILING_M = 2.44;

type SketchInfo = NonNullable<Capture["sketch"]>;

interface Element {
  id: string;
  kind: string;
  wallId: string;
  confidence?: "low" | "medium" | "high";
}

/** The openings of a model (doors, windows and openings without a door) with their kind. */
function openingsOf(model: CaptureModel): Element[] {
  const of = (kind: string, items: CaptureModel["doors"]): Element[] =>
    items.map((item) => ({
      id: item.id,
      kind,
      wallId: item.wallId,
      ...(item.confidence === undefined ? {} : { confidence: item.confidence }),
    }));
  return [
    ...of("door", model.doors),
    ...of("window", model.windows),
    ...of("opening", model.openings),
  ];
}

function isEstimated(item: { confidence?: "low" | "medium" | "high" }): boolean {
  return item.confidence === "low";
}

/** The floor's extent in millimetres: the larger extent along its principal wall direction. */
function principalExtentMm(model: CaptureModel): number {
  const outline = planOutline(model);
  const extents = extentsAlong(outline.points, principalAngle(outline.edges));
  return Math.max(extents.u, extents.v) * 1000;
}

/**
 * The closure residual graded like a scale difference (check 4): the floor's extent is the
 * reference and the residual the difference. A floor with no extent gets the 25.4 mm floor alone.
 */
export function gradeClosure(residualMm: number, extentMm: number): DistanceComparison {
  const reference = extentMm > 0 ? extentMm : ONE_INCH_MM;
  return gradeDistance(reference + residualMm, reference);
}

function list(ids: readonly string[]): string {
  return ids.join(", ");
}

/** The ceiling heights of the model's rooms, distinct, in metres. */
function ceilingHeights(model: CaptureModel | undefined): number[] {
  return model === undefined ? [] : [...new Set(model.rooms.map((room) => room.heightM))];
}

/** The findings of one sketch capture, the source-of-geometry info first. */
function evaluateCapture(
  ctx: CheckContext,
  capture: Capture,
  sketch: SketchInfo,
): StationFinding[] {
  const label = ctx.label(capture.captureId);
  const scope = scopeOf(capture);
  const filePath = ctx.capturePath(capture.captureId);
  const findings: StationFinding[] = [];
  const base = { ruleId: "sketch.measurements" as const, ...scope, expected: SKETCH_EXPECTED };
  const limitation = (
    message: string,
    measured: string,
    nextAction: string,
    path: string = filePath,
  ) =>
    findings.push(
      finding({ ...base, severity: "limitation", message, filePath: path, measured, nextAction }),
    );
  const info = (message: string, measured: string, path: string = filePath) =>
    findings.push(
      finding({
        ...base,
        severity: "info",
        message,
        filePath: path,
        measured,
        nextAction: NO_ACTION,
      }),
    );

  // The originals: the sketch image and the entered measurements.
  const missingRoles = (["sketch_measurements", "sketch_image"] as const).filter(
    (role) => ctx.entriesFor(capture.captureId, role).length === 0,
  );
  if (missingRoles.length > 0) {
    const names = { sketch_measurements: "entered measurements", sketch_image: "sketch image" };
    const missing = missingRoles.map((role) => `${names[role]} (${role})`);
    limitation(
      `The originals of the sketch capture of ${label} are missing from the package: ${missing.join(" and ")}.`,
      `missing: ${missingRoles.join(", ")}`,
      `Re-export the sketch capture of ${label} so the package carries its sketch image and the entered measurements.`,
      ctx.manifestPath,
    );
  }

  const lookup = ctx.model(capture.captureId);
  const totalWalls = sketch.wallsMeasured + sketch.wallsEstimated;
  const summary = `sketch capture, measurements ${sketch.measurements}: ${count(sketch.wallsMeasured, "wall")} measured, ${sketch.wallsEstimated} estimated, ceiling ${sketch.ceilingHeightSource}${sketch.closureResidualMm === undefined ? "" : `, closure residual ${mm(sketch.closureResidualMm)}`}`;
  if (lookup.state !== "ok") {
    const reason =
      lookup.state === "absent"
        ? "the capture has no capture model"
        : "the capture model cannot be read (see files.parseable)";
    const path = lookup.state === "absent" ? ctx.recordPath() : lookup.entry.path;
    findings.unshift(
      finding({
        ...base,
        severity: "info",
        message: `Geometry of ${label} comes from a measured sketch, not a scan.`,
        filePath: path,
        measured: summary,
        nextAction: NO_ACTION,
      }),
    );
    info(`Sketch measurements of ${label} not evaluated: ${reason}.`, "not evaluated", path);
    if (sketch.ceilingHeightSource === "assumed") {
      limitation(
        `Ceiling height of ${label} is assumed (${metres(ASSUMED_CEILING_M)}), not measured.`,
        `ceiling height source: assumed`,
        `Measure the ceiling height of ${label} with tape or laser on the next visit.`,
        path,
      );
    }
    return findings;
  }
  const model = lookup.model;
  const before = findings.length;

  // Walls.
  const lowWalls = model.walls.filter(isEstimated).map((wall) => wall.id);
  if (sketch.wallsEstimated > 0 || lowWalls.length > 0) {
    const estimated = Math.max(sketch.wallsEstimated, lowWalls.length);
    const total = Math.max(totalWalls, model.walls.length);
    const named = lowWalls.length > 0 ? ` (${list(lowWalls)})` : "";
    limitation(
      `${estimated} of ${count(total, "wall")} of ${label} ${estimated === 1 ? "is" : "are"} estimated, not measured${named}.`,
      `${count(sketch.wallsMeasured, "wall")} measured, ${sketch.wallsEstimated} estimated; low confidence in the model: ${lowWalls.length > 0 ? list(lowWalls) : "none"}`,
      `Measure the estimated ${lowWalls.length === 1 ? "wall" : "walls"} of ${label}${named} with tape or laser on the next visit.`,
    );
  }

  // Ceiling height.
  if (sketch.ceilingHeightSource === "assumed") {
    const heights = ceilingHeights(model);
    const shown = heights.length === 0 ? ASSUMED_CEILING_M : (heights[0] as number);
    limitation(
      `Ceiling height of ${label} is assumed (${metres(shown)}), not measured.`,
      `ceiling height source: assumed; model ceilings ${heights.length === 0 ? "none" : heights.map(metres).join(", ")}`,
      `Measure the ceiling height of ${label} with tape or laser on the next visit.`,
    );
  }

  // Openings.
  const openings = openingsOf(model);
  const lowOpenings = openings.filter(isEstimated);
  if (lowOpenings.length > 0) {
    const named = lowOpenings.map((item) => `${item.kind} ${item.id} in ${item.wallId}`);
    limitation(
      `${count(lowOpenings.length, "opening")} of ${label} ${lowOpenings.length === 1 ? "is" : "are"} estimated, not measured (${list(lowOpenings.map((item) => item.id))}).`,
      `low confidence in the model: ${named.join(", ")}`,
      `Measure the width and position of ${list(lowOpenings.map((item) => `${item.kind} ${item.id}`))} on ${label} with tape on the next visit.`,
    );
  }

  // Closure residual against the scale tolerance of check 4.
  if (sketch.closureResidualMm !== undefined) {
    const extentMm = principalExtentMm(model);
    const graded = gradeClosure(sketch.closureResidualMm, extentMm);
    const measured = `closure residual ${mm(sketch.closureResidualMm)}; floor extent ${mm(extentMm)}; tolerance ${mm(graded.passLimitMm)}`;
    if (graded.grade === "pass") {
      info(`Closure residual of ${label} is within the tolerance.`, measured);
    } else {
      limitation(
        `Closure residual of ${label} is over the tolerance: ${mm(sketch.closureResidualMm)} against max(1% of ${mm(extentMm)}, 25.4 mm) = ${mm(graded.passLimitMm)}.`,
        measured,
        `Re-measure the walls of ${label} with tape or laser on the next visit; the lengths going one way along an axis do not agree with the lengths coming back.`,
      );
    }
  }

  // The record's own marking, when nothing above explains it.
  const limited = findings.slice(before).some((item) => item.severity === "limitation");
  if (!limited && sketch.measurements === "limited") {
    limitation(
      `Sketch measurements of ${label} are marked limited in the capture record.`,
      `sketch.measurements: limited; no estimated wall or opening in the model`,
      `Measure the estimated items of ${label} with tape or laser on the next visit.`,
      ctx.recordPath(),
    );
  }

  // The source of the geometry, first: with the counts when everything was measured.
  const anyLimitation = findings.some((item) => item.severity === "limitation");
  const measuredOpenings = openings.length - lowOpenings.length;
  findings.unshift(
    finding({
      ...base,
      severity: "info",
      message: anyLimitation
        ? `Geometry of ${label} comes from a measured sketch, not a scan.`
        : `Geometry of ${label} comes from a measured sketch, not a scan: ${count(sketch.wallsMeasured, "wall")} and ${count(measuredOpenings, "opening")} measured, ceiling measured.`,
      filePath,
      measured: summary,
      nextAction: NO_ACTION,
    }),
  );
  return findings;
}

export function checkSketchMeasurements(ctx: CheckContext): CheckOutput {
  const record = ctx.pkg.captureRecord;
  if (record === undefined) {
    return { findings: [], notApplicable: true };
  }
  const findings: StationFinding[] = [];
  let sketches = 0;
  for (const capture of record.captures) {
    if (captureSourceOf(capture) !== "sketch" || capture.sketch === undefined) {
      continue;
    }
    sketches += 1;
    findings.push(...evaluateCapture(ctx, capture, capture.sketch));
  }
  return sketches === 0 ? { findings: [], notApplicable: true } : { findings };
}
