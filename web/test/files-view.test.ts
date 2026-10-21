// web-review §6.4.6: Files card rows: order, photo groups, the manifest and spatial report rows,
// floor / role / text filters, HUB badges, the retired phone report.

import { describe, expect, it } from "vitest";
import {
  buildFileRows,
  fileCount,
  filterRows,
  floorOptions,
  hubBadge,
  NO_FILTERS,
  roleOptions,
  rowHolding,
} from "@/lib/files-view";
import type { StationPackage } from "@/lib/station-types";
import { contractExampleCase, loadFixture, stationPackage } from "./support/fixtures";
import { drawnScenario, IDS } from "./support/scenarios";

const now = new Date("2026-10-21T18:00:00Z");

function samplePackage(reportReady = false): StationPackage {
  const data = drawnScenario(now, { reportReady });
  return data.packages.find((pkg) => pkg.packageId === IDS.westEnd1) as StationPackage;
}

describe("rows of the 424 sample", () => {
  it("lists the drawn first eight in order, then the rest", () => {
    const rows = buildFileRows(samplePackage(true));
    expect(rows.slice(0, 8).map((row) => row.name)).toEqual([
      "Floor 1 / plan.dxf",
      "Floor 1 / rooms.csv",
      "Floor 1 / plan-sheet.pdf",
      "Floor 1 / plan.png",
      "Floor 1 / mesh.glb",
      "Floor 1 / points.las",
      "Site Photos / 18 files",
      "spatial-report.pdf",
    ]);
    expect(rows.slice(8).map((row) => row.role)).toEqual([
      "Plan SVG",
      "Mesh OBJ",
      "Mesh MTL",
      "Texture",
      "Capture model",
      "Raw RoomPlan",
      "Depth",
      "Field controls",
      "Capture record",
      "Manifest",
    ]);
  });

  it("groups the photos of a capture with their total size and common HUB state", () => {
    const pkg = samplePackage();
    const group = buildFileRows(pkg).find((row) => row.kind === "photoGroup");
    const photos = pkg.files.filter((file) => file.role === "photo");
    expect(group?.children).toHaveLength(photos.length);
    expect(group?.files).toBe(18);
    expect(group?.sha).toBe("per file");
    expect(group?.hub).toEqual({ text: "Linked", tone: "info" });
    expect(group?.children?.[0]?.download).toMatch(/^\/packages\/.+\/files\/download\?path=/);
  });

  it("adds the station's spatial report only when it is ready, and the manifest once sealed", () => {
    expect(buildFileRows(samplePackage(false)).some((row) => row.kind === "report")).toBe(false);
    const ready = buildFileRows(samplePackage(true));
    const report = ready.find((row) => row.kind === "report");
    expect(report).toMatchObject({
      name: "spatial-report.pdf",
      role: "Spatial report · station",
      group: "Spatial report",
      size: "3.2 MB",
      hub: { text: "Uploaded", tone: "neutral" },
    });
    expect(report?.download).toBe(`/packages/${IDS.westEnd1}/report/download`);
    const manifest = ready.find((row) => row.kind === "manifest");
    expect(manifest?.download).toContain(encodeURIComponent("Source Register/"));
    expect(manifest?.captureId).toBeUndefined();
  });

  it("maps the station's publication state to the drawn badges", () => {
    expect(hubBadge({ state: "uploaded" })).toEqual({ text: "Uploaded", tone: "neutral" });
    expect(hubBadge({ state: "linked", reason: "too_large" })).toEqual({
      text: "Linked · over 45 MB",
      tone: "info",
    });
    expect(hubBadge({ state: "linked", reason: "not_published" })).toEqual({
      text: "Linked",
      tone: "info",
    });
    expect(hubBadge(undefined)).toBeNull();
    const rows = buildFileRows(samplePackage());
    expect(rows.find((row) => row.role === "Plan DXF")?.hub?.text).toBe("Uploaded");
    expect(rows.find((row) => row.role === "Mesh GLB")?.hub?.text).toBe("Linked");
  });

  it("shows a mixed photo group as Mixed and nothing before publication", () => {
    const pkg = samplePackage();
    const photos = pkg.files.filter((file) => file.role === "photo");
    const mixed: StationPackage = {
      ...pkg,
      files: pkg.files.map((file) =>
        file === photos[0] ? { ...file, hub: { state: "uploaded" as const } } : file,
      ),
    };
    expect(buildFileRows(mixed).find((row) => row.kind === "photoGroup")?.hub).toEqual({
      text: "Mixed",
      tone: "neutral",
    });
    const unpublished: StationPackage = {
      ...pkg,
      files: pkg.files.map(({ hub: _hub, ...file }) => file),
    };
    expect(
      buildFileRows(unpublished).every((row) => row.kind === "manifest" || row.hub === null),
    ).toBe(true);
  });
});

describe("filters", () => {
  const { pkg } = contractExampleCase();
  const rows = buildFileRows(pkg);
  const floor2 = pkg.captureRecord?.captures[1]?.captureId ?? "";

  it("offers every floor and only the role groups present", () => {
    expect(floorOptions(pkg).map((option) => option.label)).toEqual([
      "All floors",
      "Floor 1",
      "Floor 2",
    ]);
    const roles = roleOptions(rows).map((option) => option.label);
    expect(roles[0]).toBe("All roles");
    expect(roles).toContain("Plan DXF");
    expect(roles).toContain("Manifest");
    expect(roles).not.toContain("Spatial report");
  });

  it("lists visit-wide files under All floors only", () => {
    const all = filterRows(rows, NO_FILTERS);
    expect(all.some(({ row }) => row.role === "Capture record")).toBe(true);
    const second = filterRows(rows, { ...NO_FILTERS, floor: floor2 });
    expect(second.length).toBeGreaterThan(0);
    expect(second.every(({ row }) => row.captureId === floor2)).toBe(true);
    expect(second.some(({ row }) => row.kind === "manifest")).toBe(false);
  });

  it("filters by role group and by text in the name or path", () => {
    const dxf = filterRows(rows, { ...NO_FILTERS, role: "Plan DXF" });
    expect(dxf.length).toBe(pkg.files.filter((file) => file.role === "plan_dxf").length);
    expect(dxf.every(({ row }) => row.role === "Plan DXF")).toBe(true);
    const text = filterRows(rows, { ...NO_FILTERS, text: "FLOOR 2 / PLAN" });
    expect(text.every(({ row }) => row.name.startsWith("Floor 2 / plan"))).toBe(true);
    expect(filterRows(rows, { ...NO_FILTERS, text: "no such file" })).toHaveLength(0);
  });

  it("keeps a photo group with only its matching photos when the text names a photo", () => {
    const sample = buildFileRows(samplePackage());
    const found = filterRows(sample, { ...NO_FILTERS, text: "photo-0003" });
    expect(found).toHaveLength(1);
    expect(found[0]?.row.kind).toBe("photoGroup");
    expect(found[0]?.matchedChildren?.map((child) => child.name)).toEqual([
      "Floor 1 / photo-0003.jpg",
    ]);
    expect(fileCount(found)).toBe(1);
    // The 33 package files and the manifest.
    expect(fileCount(filterRows(sample, NO_FILTERS))).toBe(34);
  });

  it("finds the row holding a deep-linked file, also inside a photo group", () => {
    const sample = buildFileRows(samplePackage());
    const photo = samplePackage().files.find((file) => file.role === "photo");
    expect(rowHolding(sample, photo?.path ?? "")?.kind).toBe("photoGroup");
    const mesh = samplePackage().files.find((file) => file.role === "mesh_glb");
    expect(rowHolding(sample, mesh?.path ?? "")?.path).toBe(mesh?.path);
  });
});

describe("legacy and unsealed packages", () => {
  it("labels the retired phone report and lists it last", () => {
    const legacy = loadFixture("legacy-1.0.0/package");
    const pkg = stationPackage(legacy, { dealId: "d", createdAt: legacy.manifest.sealedAt });
    const rows = buildFileRows(pkg);
    const last = rows[rows.length - 1];
    expect(last?.role).toBe("Spatial report · phone (retired)");
    expect(last?.group).toBe("Spatial report");
  });

  it("marks files that are not verified yet and offers no download for them", () => {
    const house = loadFixture("two-floor-house/package");
    const pkg = stationPackage(house, {
      dealId: "d",
      createdAt: "2026-10-21T15:00:00Z",
      status: "uploading",
      uploaded: 0.5,
    });
    const rows = buildFileRows(pkg).flatMap((row) => row.children ?? [row]);
    expect(rows.some((row) => row.download === undefined)).toBe(true);
    expect(rows.some((row) => row.download !== undefined)).toBe(true);
    expect(rows.some((row) => row.kind === "manifest")).toBe(false);
    // Before the seal, labels come from the area keys.
    expect(floorOptions(pkg).map((option) => option.label)).toEqual([
      "All floors",
      "Floor 1",
      "Floor 2",
    ]);
  });
});
