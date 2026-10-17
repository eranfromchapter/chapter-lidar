// Check 5: up direction and orientation.
// - GLB/glTF: +Y up (height extent agrees with the ceiling height) with a horizontal floor plane
//   (horizontal faces at the lowest Y).
// - LAS: Z extent agrees with the ceiling height.
// - DXF: $INSUNITS is 4 (millimetres).
// Ceiling heights: the maximum field-control ceiling height of the capture, and the maximum room
// height of the capture model when its scale is not blocked. Agreement uses the same
// max(1%, 25.4 mm) tolerance as check 4. Failures are limitations: they are fixable by rotating
// or rescaling the export, without recapture.

import type { FileEntry } from "@chapter/capture-contract";
import type { CaptureInfo, CheckContext } from "../context.js";
import { NO_ACTION, finding, metres, scopeOf } from "../finding.js";
import { INSUNITS_NAMES } from "../parsers/dxf.js";
import { horizontalFloorArea, sceneBounds } from "../parsers/gltf.js";
import { ONE_INCH_MM, withinPassTolerance } from "../tolerance.js";
import type { CheckOutput, StationFinding } from "../types.js";
import { gltfBuffers } from "./companions.js";
import { assessScale } from "./scale.js";

interface HeightReference {
  source: string;
  mm: number;
}

function heightReferences(ctx: CheckContext, capture: CaptureInfo): HeightReference[] {
  const references: HeightReference[] = [];
  const ceilings = (ctx.pkg.fieldControls?.ceilingHeights ?? []).filter(
    (item) =>
      item.capture.captureId === capture.captureId && item.capture.areaKey === capture.areaKey,
  );
  if (ceilings.length > 0) {
    references.push({
      source: "field-control ceiling",
      mm: Math.max(...ceilings.map((item) => item.measurement.valueMm)),
    });
  }
  const lookup = ctx.model(capture.captureId);
  const scale = assessScale(ctx).get(capture.captureId);
  const scaleBlocked = scale?.state === "graded" && scale.grade === "blocker";
  if (lookup.state === "ok" && !scaleBlocked && lookup.model.rooms.length > 0) {
    references.push({
      source: "capture model room height",
      mm: Math.max(...lookup.model.rooms.map((room) => room.heightM)) * 1000,
    });
  }
  return references;
}

const AXES = ["X", "Y", "Z"] as const;

function describeReferences(references: HeightReference[]): string {
  return references.map((ref) => `${ref.source} ${metres(ref.mm / 1000)}`).join(", ");
}

/** Axes whose extent agrees with a reference height. */
function matchingAxes(extents: number[], references: HeightReference[]): string[] {
  return AXES.filter((_, axis) =>
    references.some((ref) => withinPassTolerance((extents[axis] as number) * 1000, ref.mm)),
  );
}

function agrees(extentM: number, references: HeightReference[]): boolean {
  return references.some((ref) => withinPassTolerance(extentM * 1000, ref.mm));
}

function checkMesh(
  ctx: CheckContext,
  entry: FileEntry,
  references: HeightReference[],
  findings: StationFinding[],
): string | undefined {
  const parsed = ctx.readable(entry);
  if (parsed?.kind !== "gltf") {
    return undefined;
  }
  const name = entry.path.split("/").pop() ?? entry.path;
  const base = { filePath: entry.path, ...scopeOf(entry) };
  const buffers = gltfBuffers(ctx, entry, parsed.value);
  const bounds = sceneBounds(parsed.value.json, buffers);
  if (bounds === undefined) {
    return `${name}: bounds not available, not evaluated`;
  }
  const extents = AXES.map(
    (_, axis) => (bounds.max[axis] as number) - (bounds.min[axis] as number),
  );
  const extentText = AXES.map((axis, i) => `${axis} ${metres(extents[i] as number)}`).join(", ");
  const problems: string[] = [];
  const notes: string[] = [];
  if (references.length > 0) {
    if (!agrees(extents[1] as number, references)) {
      const match = matchingAxes(extents, references);
      problems.push(
        `height (Y) extent ${metres(extents[1] as number)} does not agree with ${describeReferences(references)}${match.length > 0 ? `; ${match.join(" and ")} extent agrees, so the mesh looks ${match[0]}-up` : ""}`,
      );
    }
  } else {
    notes.push("no ceiling height to compare");
  }
  const area = horizontalFloorArea(parsed.value.json, buffers, bounds.min[1], ONE_INCH_MM / 1000);
  if (area === undefined) {
    notes.push("floor plane not evaluated (triangle data unavailable)");
  } else if (area <= 0) {
    problems.push(`no horizontal faces at the lowest Y (${metres(bounds.min[1])})`);
  } else {
    notes.push(`horizontal floor faces ${area.toFixed(2)} m2 at Y ${metres(bounds.min[1])}`);
  }
  if (problems.length > 0) {
    findings.push(
      finding({
        ruleId: "orientation.up",
        severity: "limitation",
        message: "Mesh is not +Y up with a horizontal floor plane.",
        ...base,
        measured: `extents ${extentText}; ${problems.join("; ")}`,
        expected:
          "+Y up: height extent within max(1%, 25.4 mm) of the ceiling height, floor faces horizontal at the lowest Y",
        nextAction: `Rotate ${name} so +Y is up (glTF convention) and re-export; recapture is not needed.`,
      }),
    );
    return undefined;
  }
  return `${name}: +Y up (extents ${extentText}${notes.length > 0 ? `; ${notes.join("; ")}` : ""})`;
}

function checkCloud(
  ctx: CheckContext,
  entry: FileEntry,
  references: HeightReference[],
  findings: StationFinding[],
): string | undefined {
  const parsed = ctx.readable(entry);
  if (parsed?.kind !== "las") {
    return undefined;
  }
  const name = entry.path.split("/").pop() ?? entry.path;
  const header = parsed.value;
  const extents = AXES.map(
    (_, axis) => (header.max[axis] as number) - (header.min[axis] as number),
  );
  if (references.length === 0) {
    return `${name}: no ceiling height to compare`;
  }
  if (agrees(extents[2] as number, references)) {
    return `${name}: Z extent ${metres(extents[2] as number)}`;
  }
  const match = matchingAxes(extents, references);
  findings.push(
    finding({
      ruleId: "orientation.up",
      severity: "limitation",
      message: "Point cloud Z extent does not agree with the ceiling height.",
      filePath: entry.path,
      ...scopeOf(entry),
      measured: `header Z extent ${metres(extents[2] as number)} vs ${describeReferences(references)}${match.length > 0 ? `; ${match.join(" and ")} extent agrees` : ""}`,
      expected: "LAS Z up: Z extent within max(1%, 25.4 mm) of the ceiling height",
      nextAction: `Check the up axis and units of ${name}; re-export LAS with Z up in metres.`,
    }),
  );
  return undefined;
}

function checkPlanUnits(
  ctx: CheckContext,
  entry: FileEntry,
  findings: StationFinding[],
): string | undefined {
  const parsed = ctx.readable(entry);
  if (parsed?.kind !== "dxf") {
    return undefined;
  }
  const name = entry.path.split("/").pop() ?? entry.path;
  const raw = parsed.value.header.get("$INSUNITS");
  const code = raw === undefined ? undefined : Number(raw);
  if (code === 4) {
    return `${name}: millimetres ($INSUNITS 4)`;
  }
  findings.push(
    finding({
      ruleId: "orientation.up",
      severity: "limitation",
      message: "Plan DXF is not declared in millimetres.",
      filePath: entry.path,
      ...scopeOf(entry),
      measured:
        code === undefined
          ? "no $INSUNITS header variable"
          : `$INSUNITS ${raw} (${INSUNITS_NAMES[code] ?? "unknown"})`,
      expected: "$INSUNITS 4 (millimetres)",
      nextAction: `Re-export ${name} in millimetres ($INSUNITS 4), or rescale it before use.`,
    }),
  );
  return undefined;
}

export function checkOrientation(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  let evaluated = 0;
  for (const capture of ctx.captures()) {
    const references = heightReferences(ctx, capture);
    const passed: string[] = [];
    const before = findings.length;
    const run = (role: FileEntry["role"], fn: (entry: FileEntry) => string | undefined) => {
      for (const entry of ctx.entriesFor(capture.captureId, role)) {
        if (ctx.readable(entry) === undefined) {
          continue;
        }
        evaluated += 1;
        const ok = fn(entry);
        if (ok !== undefined) {
          passed.push(ok);
        }
      }
    };
    run("mesh_glb", (entry) => checkMesh(ctx, entry, references, findings));
    run("point_cloud_las", (entry) => checkCloud(ctx, entry, references, findings));
    run("plan_dxf", (entry) => checkPlanUnits(ctx, entry, findings));
    if (findings.length === before && passed.length > 0) {
      findings.push(
        finding({
          ruleId: "orientation.up",
          severity: "info",
          message: `Up direction and units of ${capture.label} agree with the known heights.`,
          filePath: ctx.capturePath(capture.captureId),
          ...scopeOf(capture),
          measured: passed.join("; "),
          expected: references.length > 0 ? describeReferences(references) : "known heights",
          nextAction: NO_ACTION,
        }),
      );
    }
  }
  return evaluated === 0 ? { findings, notApplicable: true } : { findings };
}
