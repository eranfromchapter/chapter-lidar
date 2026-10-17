// Check 7 (DXF content type) and check 8 (LAS header equals the data).

import type { CheckContext } from "../context.js";
import { NO_ACTION, finding, scopeOf } from "../finding.js";
import type { DxfEntity } from "../parsers/dxf.js";
import {
  MIN_RECORD_LENGTH,
  declaredPointCount,
  scanLasPoints,
  type LasHeader,
} from "../parsers/las.js";
import type { CheckOutput, StationFinding } from "../types.js";

/** Two-dimensional drawing entities that a plan DXF may hold. */
const PLAN_ENTITIES = new Set([
  "LINE",
  "ARC",
  "CIRCLE",
  "ELLIPSE",
  "LWPOLYLINE",
  "POLYLINE",
  "VERTEX",
  "SEQEND",
  "SPLINE",
  "TEXT",
  "MTEXT",
  "ATTRIB",
  "ATTDEF",
  "DIMENSION",
  "LEADER",
  "MLEADER",
  "MULTILEADER",
  "HATCH",
  "SOLID",
  "INSERT",
  "XLINE",
  "RAY",
]);

/** Mesh, surface, solid and point entities: not plan geometry. */
const MESH_OR_POINT_ENTITIES = new Set([
  "3DFACE",
  "MESH",
  "POLYFACE",
  "POINT",
  "3DSOLID",
  "BODY",
  "REGION",
  "SURFACE",
  "PLANESURFACE",
  "NURBSURFACE",
  "EXTRUDEDSURFACE",
  "LOFTEDSURFACE",
  "REVOLVEDSURFACE",
  "SWEPTSURFACE",
  "POINTCLOUD",
  "ACAD_PROXY_ENTITY",
]);

/** POLYLINE flag bits 16 (polygon mesh) and 64 (polyface mesh). */
function isMeshPolyline(entity: DxfEntity): boolean {
  return (
    entity.type === "POLYLINE" && entity.flags !== undefined && (entity.flags & (16 | 64)) !== 0
  );
}

function tally(entities: readonly DxfEntity[]): Map<string, number> {
  const counts = new Map<string, number>();
  for (const entity of entities) {
    const key = isMeshPolyline(entity) ? "POLYLINE(mesh)" : entity.type;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return counts;
}

function describe(counts: Map<string, number>): string {
  return [...counts.entries()].map(([type, n]) => `${type} ${n}`).join(", ") || "none";
}

export function checkDxfContent(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  let evaluated = 0;
  for (const entry of ctx.entries) {
    if (entry.role !== "plan_dxf") {
      continue;
    }
    const parsed = ctx.readable(entry);
    if (parsed?.kind !== "dxf") {
      continue; // Missing, empty or unreadable: checks 1 and 2 report it.
    }
    evaluated += 1;
    const all = [...parsed.value.entities, ...parsed.value.blockEntities];
    const counts = tally(all);
    const flagged = new Map(
      [...counts.entries()].filter(
        ([type]) => MESH_OR_POINT_ENTITIES.has(type) || type === "POLYLINE(mesh)",
      ),
    );
    const plan = [...counts.entries()].filter(([type]) => PLAN_ENTITIES.has(type));
    const other = [...counts.entries()].filter(
      ([type]) => !PLAN_ENTITIES.has(type) && !flagged.has(type),
    );
    const base = { filePath: entry.path, ...scopeOf(entry) };
    if (flagged.size > 0) {
      findings.push(
        finding({
          ruleId: "dxf.content",
          severity: "limitation",
          message: "Plan DXF holds mesh or point entities, not plan geometry only.",
          ...base,
          measured: `flagged: ${describe(flagged)}; plan entities: ${plan.reduce((s, [, n]) => s + n, 0)}`,
          expected: "plan entities only (lines, arcs, polylines, text)",
          nextAction:
            "Use the DXF as reference only, or request a plan-only DXF export of this capture.",
        }),
      );
      continue;
    }
    if (plan.length === 0) {
      findings.push(
        finding({
          ruleId: "dxf.content",
          severity: "limitation",
          message: "Plan DXF holds no plan entities.",
          ...base,
          measured: `entities: ${describe(counts)}`,
          expected: "plan entities (lines, arcs, polylines, text)",
          nextAction: "Re-export the plan DXF of this capture and re-upload the package.",
        }),
      );
      continue;
    }
    findings.push(
      finding({
        ruleId: "dxf.content",
        severity: "info",
        message: "Plan DXF holds plan entities only.",
        ...base,
        measured:
          describe(new Map(plan)) +
          (other.length > 0 ? `; other: ${describe(new Map(other))}` : ""),
        expected: "plan entities only",
        nextAction: NO_ACTION,
      }),
    );
  }
  return evaluated === 0 ? { findings, notApplicable: true } : { findings };
}

/** Header extents agree with the data when within half a scale step (header rounding). */
function extentDiffers(header: number, data: number, scale: number): boolean {
  return Math.abs(header - data) > Math.abs(scale) / 2 + 1e-9;
}

function lasProblems(
  bytes: Uint8Array,
  header: LasHeader,
): { problems: string[]; summary: string } {
  const problems: string[] = [];
  const version = `${header.versionMajor}.${header.versionMinor}`;
  const format = header.pointFormatByte & 0x3f;
  const compressed = (header.pointFormatByte & 0x80) !== 0;
  if (header.versionMajor !== 1 || header.versionMinor > 4) {
    problems.push(`version ${version} is not LAS 1.0-1.4`);
  }
  if (compressed) {
    problems.push(`point format byte ${header.pointFormatByte} marks LAZ compression`);
  }
  const minLength = MIN_RECORD_LENGTH[format];
  if (minLength === undefined) {
    problems.push(`point format ${format} is not 0-10`);
  } else if (header.recordLength < minLength) {
    problems.push(
      `record length ${header.recordLength} is below ${minLength} for format ${format}`,
    );
  }
  if (format >= 6 && format <= 10 && !(header.versionMajor === 1 && header.versionMinor >= 4)) {
    problems.push(`point format ${format} needs LAS 1.4, header says ${version}`);
  }
  const declared = declaredPointCount(header);
  if (
    header.pointCount64 !== undefined &&
    header.legacyPointCount !== 0 &&
    BigInt(header.legacyPointCount) !== header.pointCount64
  ) {
    problems.push(
      `legacy point count ${header.legacyPointCount} differs from the 64-bit count ${header.pointCount64}`,
    );
  }
  const scan = scanLasPoints(bytes, header);
  if (declared !== BigInt(scan.recordCount)) {
    problems.push(`header point count ${declared}, data holds ${scan.recordCount} points`);
  }
  if (scan.remainderBytes !== 0) {
    problems.push(`${scan.remainderBytes} trailing bytes do not form a whole point record`);
  }
  if (scan.min !== undefined && scan.max !== undefined) {
    const axes = ["X", "Y", "Z"];
    for (let axis = 0; axis < 3; axis += 1) {
      const scale = header.scale[axis] as number;
      if (
        extentDiffers(header.min[axis] as number, scan.min[axis] as number, scale) ||
        extentDiffers(header.max[axis] as number, scan.max[axis] as number, scale)
      ) {
        problems.push(
          `${axes[axis]} extent header ${(header.min[axis] as number).toFixed(3)}..${(header.max[axis] as number).toFixed(3)}, data ${(scan.min[axis] as number).toFixed(3)}..${(scan.max[axis] as number).toFixed(3)}`,
        );
      }
    }
  }
  const summary = `LAS ${version}, point format ${format}, ${scan.recordCount} points, header count ${declared}`;
  return { problems, summary };
}

export function checkLasHeader(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  let evaluated = 0;
  for (const entry of ctx.entries) {
    if (entry.role !== "point_cloud_las") {
      continue;
    }
    const parsed = ctx.readable(entry);
    const bytes = ctx.bytes(entry.path);
    if (parsed?.kind !== "las" || bytes === undefined) {
      continue;
    }
    evaluated += 1;
    const { problems, summary } = lasProblems(bytes, parsed.value);
    const base = { filePath: entry.path, ...scopeOf(entry) };
    if (problems.length > 0) {
      findings.push(
        finding({
          ruleId: "las.header",
          severity: "limitation",
          message:
            "LAS header does not match its point data; the point cloud is not usable until re-exported (the point cloud is optional for preliminary plans).",
          ...base,
          measured: problems.join("; "),
          expected: "LAS 1.0-1.4, supported point format, counts and extents equal the data",
          nextAction:
            "Re-export points.las on the device and re-upload, or continue without the point cloud.",
        }),
      );
    } else {
      findings.push(
        finding({
          ruleId: "las.header",
          severity: "info",
          message: "LAS header matches its point data.",
          ...base,
          measured: `${summary}; extents match`,
          expected: "counts and extents equal the data",
          nextAction: NO_ACTION,
        }),
      );
    }
  }
  return evaluated === 0 ? { findings, notApplicable: true } : { findings };
}
