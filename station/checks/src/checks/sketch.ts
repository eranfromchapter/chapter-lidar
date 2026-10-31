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
// 2 and 4 report it). Not applicable when the package has no sketch or walkthrough capture, so
// LiDAR verdicts do not change.
//
// An AR walkthrough capture (`captureSource: walkthrough`, spec F15 5) is converted into sketch
// measurements and solved by the same solver, so it carries the same `sketch` summary and gets the
// same findings, the first info saying the geometry comes from an AR walkthrough, not a LiDAR scan.
// Its `walkthrough` summary adds:
// - the scale: an info when one wall was taped (with the scale factor) or when the floor has a
//   field-control distance (check 4 compares it); a limitation when the scale comes from the
//   phone's motion tracking only and the floor has no field-control distance;
// - the loop closure (the gap before the closing tap, before it was distributed), graded like the
//   closure residual: an info when within, a limitation when over;
// - an info with the seconds of limited tracking, when there were any;
// - its originals: the walkthrough log (the raw record; missing is a limitation), the measurements
//   derived from it (missing is a limitation) and the video (missing is a limitation when the
//   record says it was recorded, an info otherwise). No sketch image is expected.

import {
  captureSourceOf,
  isMeasuredPlanSource,
  type Capture,
  type CaptureModel,
  type CaptureSource,
} from "@chapter/capture-contract";
import type { CheckContext } from "../context.js";
import { NO_ACTION, count, finding, metres, mm, scopeOf } from "../finding.js";
import { extentsAlong, planOutline, principalAngle } from "../geometry.js";
import { ONE_INCH_MM, gradeDistance, type DistanceComparison } from "../tolerance.js";
import type { CheckOutput, StationFinding } from "../types.js";

/** What the rule expects of every sketch capture. */
export const SKETCH_EXPECTED =
  "every wall and opening measured, ceiling height measured, closure residual within max(1% of the floor's extent, 25.4 mm), sketch image and measurements in the package";

/** What the rule expects of every AR walkthrough capture (spec F15 5). */
export const WALKTHROUGH_EXPECTED =
  "every wall and opening tapped, ceiling line tapped, scale checked with a tape or a field-control distance, loop closure and closure residual within max(1% of the floor's extent, 25.4 mm), walkthrough log and measurements in the package, and the video when it was recorded";

/** The ceiling height the solver assumes when the operator did not measure it (spec F14 1.5). */
export const ASSUMED_CEILING_M = 2.44;

type SketchInfo = NonNullable<Capture["sketch"]>;
type WalkthroughInfo = NonNullable<Capture["walkthrough"]>;

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

/** The originals of a walkthrough capture besides its measurements. */
type WalkthroughOriginal = "walkthrough_log" | "walkthrough_video";

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

/** The field-control distances recorded for the capture's floor (check 4 compares them). */
function controlDistances(ctx: CheckContext, capture: Capture): number {
  return (ctx.pkg.fieldControls?.distances ?? []).filter(
    (distance) =>
      distance.capture.captureId === capture.captureId &&
      distance.capture.areaKey === capture.areaKey,
  ).length;
}

/** A scale factor as the app shows it, up to five decimals, for example 0.99725. */
function factor(value: number): string {
  return String(Number(value.toFixed(5)));
}

/** Seconds with one decimal, for example 0.5 s. */
function seconds(value: number): string {
  return `${value.toFixed(1)} s`;
}

/** The walkthrough summary of the record, for the measured field of the source info. */
function walkthroughSummary(walk: WalkthroughInfo | undefined): string {
  if (walk === undefined) {
    return "";
  }
  const scale =
    walk.scaleSource === "tape"
      ? `tape${walk.scaleFactor === undefined ? "" : ` ×${factor(walk.scaleFactor)}`}`
      : "phone motion tracking";
  return `; scale ${scale}, loop closure ${mm(walk.loopClosureMm)}, tracking limited ${seconds(walk.trackingLimitedSeconds)}, video ${walk.recorded ? "recorded" : "not recorded"}`;
}

/** The findings of one sketch or walkthrough capture, the source-of-geometry info first. */
function evaluateCapture(
  ctx: CheckContext,
  capture: Capture,
  sketch: SketchInfo,
  source: CaptureSource,
): StationFinding[] {
  const label = ctx.label(capture.captureId);
  const scope = scopeOf(capture);
  const filePath = ctx.capturePath(capture.captureId);
  const findings: StationFinding[] = [];
  const isWalkthrough = source === "walkthrough";
  const walk = isWalkthrough ? capture.walkthrough : undefined;
  const base = {
    ruleId: "sketch.measurements" as const,
    ...scope,
    expected: isWalkthrough ? WALKTHROUGH_EXPECTED : SKETCH_EXPECTED,
  };
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

  const absent = (role: "sketch_measurements" | "sketch_image" | WalkthroughOriginal) =>
    ctx.entriesFor(capture.captureId, role).length === 0;

  // The originals of a walkthrough: the log (the raw record), the measurements derived from it
  // and the video. No sketch image is expected.
  if (isWalkthrough) {
    if (absent("walkthrough_log")) {
      limitation(
        `The walkthrough log of ${label} is missing from the package: the raw record of the walk (every tap and camera pose) is gone.`,
        "missing: walkthrough_log",
        `Re-export the walkthrough capture of ${label} so the package carries its walkthrough log (walkthrough-log.json).`,
        ctx.manifestPath,
      );
    }
    if (absent("sketch_measurements")) {
      limitation(
        `The measurements of the AR walkthrough of ${label} are missing from the package (sketch_measurements).`,
        "missing: sketch_measurements",
        `Re-export the walkthrough capture of ${label} so the package carries the measurements derived from the walk.`,
        ctx.manifestPath,
      );
    }
    if (absent("walkthrough_video")) {
      if (walk?.recorded === true) {
        limitation(
          `The walkthrough video of ${label} is missing from the package, although the capture record says it was recorded.`,
          "missing: walkthrough_video; walkthrough.recorded: true",
          `Re-export the walkthrough capture of ${label} so the package carries its video (walkthrough.mp4).`,
          ctx.manifestPath,
        );
      } else {
        info(
          `No walkthrough video of ${label}: the walk was not recorded.`,
          `no walkthrough_video; walkthrough.recorded: ${walk === undefined ? "absent" : "false"}`,
          ctx.manifestPath,
        );
      }
    }
  }

  // The originals of a sketch: the sketch image and the entered measurements.
  const missingRoles = isWalkthrough
    ? []
    : (["sketch_measurements", "sketch_image"] as const).filter(absent);
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
  const summary = `${isWalkthrough ? "AR walkthrough" : "sketch capture"}, measurements ${sketch.measurements}: ${count(sketch.wallsMeasured, "wall")} measured, ${sketch.wallsEstimated} estimated, ceiling ${sketch.ceilingHeightSource}${sketch.closureResidualMm === undefined ? "" : `, closure residual ${mm(sketch.closureResidualMm)}`}${walkthroughSummary(walk)}`;
  const origin = isWalkthrough
    ? "an AR walkthrough, not a LiDAR scan"
    : "a measured sketch, not a scan";

  // The walkthrough's scale, loop closure and tracking. The loop closure needs the floor's
  // extent, so it is graded only when the model was read.
  const walkthroughFindings = (extentMm: number | undefined, path: string) => {
    if (walk === undefined) {
      return;
    }
    const distances = controlDistances(ctx, capture);
    if (walk.scaleSource === "tape") {
      info(
        `Scale of ${label} checked with a tape${walk.scaleFactor === undefined ? "" : ` (×${factor(walk.scaleFactor)})`}.`,
        `scale source tape${walk.scaleFactor === undefined ? "" : `, scale factor ${factor(walk.scaleFactor)}`}; field-control distances for this floor: ${distances}`,
        path,
      );
    } else if (distances > 0) {
      info(
        `Scale of ${label} comes from the phone's motion tracking and is checked against ${count(distances, "field-control distance")} (units.scale).`,
        `scale source ar; field-control distances for this floor: ${distances}`,
        path,
      );
    } else {
      limitation(
        `Scale of ${label} comes from the phone's motion tracking only (about 1 to 3 %), not checked with a tape.`,
        "scale source ar; no field-control distance for this floor",
        `Tape one long wall of ${label} and record it as a field-control distance, or check the scale in the app on the next visit.`,
        path,
      );
    }
    if (extentMm !== undefined) {
      const graded = gradeClosure(walk.loopClosureMm, extentMm);
      const measured = `loop closure ${mm(walk.loopClosureMm)} before distribution; floor extent ${mm(extentMm)}; tolerance ${mm(graded.passLimitMm)}`;
      if (graded.grade === "pass") {
        info(`Loop closure of the walk of ${label} is within the tolerance.`, measured, path);
      } else {
        limitation(
          `The walk of ${label} drifted ${mm(walk.loopClosureMm)} before the loop was closed; over max(1% of ${mm(extentMm)}, 25.4 mm) = ${mm(graded.passLimitMm)}.`,
          measured,
          `Walk ${label} again on the next visit, room by room and slower, closing the loop in each room, or tape its walls and enter them as a sketch.`,
          path,
        );
      }
    }
    if (walk.trackingLimitedSeconds > 0) {
      info(
        `Tracking was limited for ${seconds(walk.trackingLimitedSeconds)} of the walk of ${label}; no tap was taken while it was.`,
        `tracking limited ${seconds(walk.trackingLimitedSeconds)}`,
        path,
      );
    }
  };
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
        message: `Geometry of ${label} comes from ${origin}.`,
        filePath: path,
        measured: summary,
        nextAction: NO_ACTION,
      }),
    );
    info(
      `${isWalkthrough ? "Walkthrough" : "Sketch"} measurements of ${label} not evaluated: ${reason}.`,
      "not evaluated",
      path,
    );
    if (sketch.ceilingHeightSource === "assumed") {
      limitation(
        `Ceiling height of ${label} is assumed (${metres(ASSUMED_CEILING_M)}), not measured.`,
        `ceiling height source: assumed`,
        `Measure the ceiling height of ${label} with tape or laser on the next visit.`,
        path,
      );
    }
    walkthroughFindings(undefined, path);
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
  const extentMm = principalExtentMm(model);
  if (sketch.closureResidualMm !== undefined) {
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

  walkthroughFindings(extentMm, filePath);

  // The record's own marking, when nothing above explains it.
  const limited = findings.slice(before).some((item) => item.severity === "limitation");
  if (!limited && sketch.measurements === "limited") {
    limitation(
      `${isWalkthrough ? "Walkthrough" : "Sketch"} measurements of ${label} are marked limited in the capture record.`,
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
        ? `Geometry of ${label} comes from ${origin}.`
        : `Geometry of ${label} comes from ${origin}: ${count(sketch.wallsMeasured, "wall")} and ${count(measuredOpenings, "opening")} measured, ceiling measured.`,
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
    const source = captureSourceOf(capture);
    if (!isMeasuredPlanSource(source) || capture.sketch === undefined) {
      continue;
    }
    sketches += 1;
    findings.push(...evaluateCapture(ctx, capture, capture.sketch, source));
  }
  return sketches === 0 ? { findings: [], notApplicable: true } : { findings };
}
