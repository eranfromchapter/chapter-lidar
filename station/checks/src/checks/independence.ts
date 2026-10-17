// Check 12: independence of evidence. Exports of one capture (capture model, DXF, CSV, PDFs,
// previews, meshes, point cloud) come from the same scan, so their agreement is never counted as
// an independent measurement; only field controls are. The station's scale check compares the
// capture model with field controls only. A field-controls file that the manifest records as
// derived from package files is not independent, which is a limitation.

import type { Role } from "@chapter/capture-contract";
import type { CheckContext } from "../context.js";
import { NO_ACTION, count, finding, scopeOf } from "../finding.js";
import type { CheckOutput, StationFinding } from "../types.js";

const EXPORT_ROLES: ReadonlySet<Role> = new Set<Role>([
  "capture_model",
  "plan_dxf",
  "rooms_csv",
  "plan_pdf",
  "spatial_report_pdf",
  "plan_png",
  "plan_svg",
  "mesh_glb",
  "mesh_obj",
  "point_cloud_las",
]);

export function checkIndependence(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  const controlsEntry = ctx.firstOfRole("field_controls");
  if (controlsEntry !== undefined && controlsEntry.derivedFrom.length > 0) {
    findings.push(
      finding({
        ruleId: "evidence.independence",
        severity: "limitation",
        message:
          "Field controls are recorded as derived from package files, so they are not independent measurements.",
        filePath: controlsEntry.path,
        measured: `derivedFrom: ${controlsEntry.derivedFrom.join(", ")}`,
        expected: "field controls measured on site with tape or laser (derivedFrom empty)",
        nextAction:
          "Measure the controls on site with tape or laser and record them as independent controls.",
      }),
    );
  }
  const controls = ctx.pkg.fieldControls;
  for (const capture of ctx.captures()) {
    const exports = ctx.entries.filter(
      (entry) => entry.captureId === capture.captureId && EXPORT_ROLES.has(entry.role),
    );
    const mine = (ref: { captureId: string; areaKey: string }) =>
      ref.captureId === capture.captureId && ref.areaKey === capture.areaKey;
    const distances = controls?.distances.filter((item) => mine(item.capture)).length ?? 0;
    const ceilings = controls?.ceilingHeights.filter((item) => mine(item.capture)).length ?? 0;
    const openings = controls?.openings.filter((item) => mine(item.capture)).length ?? 0;
    const names = exports.map((entry) => entry.path.split("/").pop() ?? entry.path);
    findings.push(
      finding({
        ruleId: "evidence.independence",
        severity: "info",
        message: `Exports of ${capture.label} come from one scan; their agreement is not counted as an independent measurement. Only field controls are independent evidence.`,
        filePath: ctx.capturePath(capture.captureId),
        ...scopeOf(capture),
        measured: `${count(exports.length, "export")} of one capture (${names.join(", ") || "none"}); independent controls: ${count(distances, "distance")}, ${count(ceilings, "ceiling height")}, ${count(openings, "opening")}`,
        expected: "scale and heights checked against field controls only",
        nextAction: NO_ACTION,
      }),
    );
  }
  return { findings };
}
