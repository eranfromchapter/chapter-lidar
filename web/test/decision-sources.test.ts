// web-review §6.4.8: the "Source used" options built from the package and its field controls,
// resolved again on the server by key (a posted path is never forwarded); §6.4.7 entry words.

import { describe, expect, it } from "vitest";
import {
  decisionInput,
  parseDecisionForm,
  resolveSource,
  sourceGroups,
  sourceText,
} from "@/lib/decisions";
import type { StationPackage } from "@/lib/station-types";
import { contractExampleCase } from "./support/fixtures";
import { drawnScenario, IDS } from "./support/scenarios";

const sample = drawnScenario(new Date("2026-10-21T18:00:00Z")).packages.find(
  (pkg) => pkg.packageId === IDS.westEnd1,
) as StationPackage;
const controlsPath = sample.files.find((file) => file.role === "field_controls")?.path ?? "";
const dxfPath = sample.files.find((file) => file.role === "plan_dxf")?.path ?? "";
const floor1 = { captureId: "33ede7f4-cfcb-4cd6-9af5-7daffee829a9", areaKey: "floor-1" };

describe("source options of the 424 sample", () => {
  const groups = sourceGroups(sample);

  it("groups plans and models, plan checked against tape, field controls and site photos", () => {
    expect(groups.map((group) => group.label)).toEqual([
      "Plans and models",
      "Plan checked against tape",
      "Field controls",
      "Site photos",
    ]);
    expect(groups[0]?.options.map((option) => option.label)).toEqual([
      "Floor 1 / plan.dxf",
      "Floor 1 / rooms.csv",
      "Floor 1 / plan-sheet.pdf",
      "Floor 1 / plan.png",
      "Floor 1 / plan.svg",
      "Floor 1 / mesh.glb",
      "Floor 1 / mesh.obj",
      "Floor 1 / points.las",
      "Floor 1 / capture-model.json",
    ]);
  });

  it("words plan-plus-control and control options with their method", () => {
    const checked = groups[1]?.options.map((option) => option.label) ?? [];
    expect(checked[0]).toBe("Floor 1 / plan.dxf + Distance A (laser)");
    expect(checked).toContain("Floor 1 / plan.dxf + Bedroom 1 ceiling height (tape)");
    const controls = groups[2]?.options.map((option) => option.label) ?? [];
    expect(controls[0]).toBe("Distance A (laser) · Living Room west wall to Living Room east wall");
    expect(controls).toContain("Bedroom 1 ceiling height (tape)");
    expect(controls).toContain("Bedroom 1 Bedroom 1 window (tape)");
    expect(groups[3]?.options).toEqual([
      { value: `photos:${floor1.captureId}`, label: "Floor 1 / site photos (18)" },
    ]);
  });

  it("resolves each key to the sources and the capture it stands for", () => {
    expect(resolveSource(sample, `file:${dxfPath}`)).toEqual({
      sources: [{ path: dxfPath }],
      ...floor1,
    });
    expect(resolveSource(sample, `filectl:${dxfPath}|floor-1-distance-a`)).toEqual({
      sources: [{ path: dxfPath }, { path: controlsPath, controlId: "floor-1-distance-a" }],
      ...floor1,
    });
    expect(resolveSource(sample, "ctl:floor-1-distance-b")).toEqual({
      sources: [{ path: controlsPath, controlId: "floor-1-distance-b" }],
      ...floor1,
    });
    const photos = resolveSource(sample, `photos:${floor1.captureId}`);
    expect(photos?.sources).toHaveLength(18);
    expect(photos?.captureId).toBe(floor1.captureId);
  });

  it("rejects keys that are not one of the package's options", () => {
    expect(resolveSource(sample, "file:Original Exports/elsewhere/plan.dxf")).toBeUndefined();
    expect(resolveSource(sample, dxfPath)).toBeUndefined();
    expect(resolveSource(sample, "ctl:no-such-control")).toBeUndefined();
  });

  it("offers only verified files", () => {
    const unverified: StationPackage = {
      ...sample,
      files: sample.files.map((file) =>
        file.path === dxfPath ? { ...file, status: "pending" as const } : file,
      ),
    };
    expect(resolveSource(unverified, `file:${dxfPath}`)).toBeUndefined();
    expect(sourceGroups(unverified)[1]).toMatchObject({ label: "Field controls" });
  });
});

describe("several captures", () => {
  const { pkg } = contractExampleCase();

  it("prefixes control options with the floor, and leaves floor to floor without a capture", () => {
    const controls = sourceGroups(pkg).find((group) => group.label === "Field controls");
    expect(
      controls?.options.some((option) => option.label.startsWith("Floor 1 · Distance A")),
    ).toBe(true);
    const floorToFloor = pkg.fieldControls?.floorToFloor[0];
    if (floorToFloor !== undefined) {
      const resolved = resolveSource(pkg, `ctl:${floorToFloor.id}`);
      expect(resolved?.captureId).toBeUndefined();
      expect(controls?.options.map((option) => option.label)).toContain(
        `Floor to floor (${floorToFloor.measurement.method}) · ${floorToFloor.location}`,
      );
    }
  });
});

describe("form and station input", () => {
  it("parses the form and builds the input from the resolved key", () => {
    const form = new FormData();
    form.set("packageId", sample.packageId);
    form.set("element", " Living Room walls ");
    form.set("source", `filectl:${dxfPath}|floor-1-distance-a`);
    form.set("decision", "Native Revit walls");
    form.set("note", "");
    const parsed = parseDecisionForm(form);
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) {
      return;
    }
    const resolved = resolveSource(sample, parsed.sourceKey);
    expect(resolved).toBeDefined();
    expect(decisionInput(parsed, resolved ?? { sources: [] })).toEqual({
      element: "Living Room walls",
      decision: "Native Revit walls",
      ...floor1,
      sources: [{ path: dxfPath }, { path: controlsPath, controlId: "floor-1-distance-a" }],
    });
  });

  it("names every missing field", () => {
    const form = new FormData();
    form.set("packageId", "not-a-uuid");
    const parsed = parseDecisionForm(form);
    expect(parsed.ok).toBe(false);
    expect(parsed.ok ? "" : parsed.message).toBe(
      "The package is unknown; name the element or area; choose the source used; describe the decision.",
    );
  });
});

describe("entry words", () => {
  const context = {
    files: sample.files,
    ...(sample.captureRecord === undefined ? {} : { captureRecord: sample.captureRecord }),
    ...(sample.fieldControls === undefined ? {} : { fieldControls: sample.fieldControls }),
  };

  it("names files, controls by their short name and photos as one group", () => {
    expect(
      sourceText(
        { sources: [{ path: dxfPath }, { path: controlsPath, controlId: "floor-1-distance-a" }] },
        context,
      ),
    ).toBe("Floor 1 / plan.dxf + Distance A (laser)");
    const photos = resolveSource(sample, `photos:${floor1.captureId}`)?.sources ?? [];
    expect(sourceText({ sources: photos }, context)).toBe("Floor 1 / site photos (18)");
    expect(sourceText({ sources: [{ path: controlsPath, controlId: "gone" }] }, context)).toBe(
      "field-controls.json (gone)",
    );
  });

  it("names sources from their paths without the package at hand", () => {
    expect(sourceText({ sources: [{ path: dxfPath }] }, undefined)).toBe("Floor 1 / plan.dxf");
  });
});
