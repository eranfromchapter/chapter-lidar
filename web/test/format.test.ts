// web-review §5.4: sizes, lengths, areas, Eastern Time dates, ids and role labels.

import { describe, expect, it } from "vitest";
import {
  areaCount,
  captureLabel,
  dayLabel,
  fileDisplayName,
  formatBytes,
  formatDate,
  formatDateTime,
  formatDateTime24,
  formatDayTime,
  formatMm,
  formatSqFt,
  humanizeAreaKey,
  modeSummary,
  pathDisplayName,
  plural,
  ROLE_FILTER_GROUP,
  ROLE_LABEL,
  shortId,
  shortSha,
  updatedAgo,
} from "@/lib/format";
import { contractExampleCase } from "./support/fixtures";

describe("formatBytes", () => {
  it.each([
    [0, "0 B"],
    [999, "999 B"],
    [1_000, "1 KB"],
    [14_000, "14 KB"],
    [1_204_000, "1.2 MB"],
    [96_000_000, "96 MB"],
    [768_400_000, "768 MB"],
    [999_600, "1 MB"],
    [2_500_000_000, "2.5 GB"],
  ])("%d bytes is %s", (bytes, text) => {
    expect(formatBytes(bytes)).toBe(text);
  });
});

describe("lengths and areas", () => {
  it("prints millimetres rounded with en-US grouping", () => {
    expect(formatMm(7520)).toBe("7,520 mm");
    expect(formatMm(2489.6)).toBe("2,490 mm");
    expect(formatMm(723)).toBe("723 mm");
  });

  it("prints square feet with one decimal", () => {
    expect(formatSqFt(807.5)).toBe("807.5 sq ft");
    expect(formatSqFt(1234)).toBe("1,234.0 sq ft");
  });
});

describe("dates in America/New_York", () => {
  it("formats dates and 24-hour times across daylight saving time", () => {
    expect(formatDate("2025-01-25T15:00:00Z")).toBe("Jan 25, 2025");
    // EDT (UTC-4) in May, EST (UTC-5) in January.
    expect(formatDateTime24("2026-05-16T18:02:00Z")).toBe("May 16, 2026 14:02");
    expect(formatDateTime24("2026-01-16T19:02:00Z")).toBe("Jan 16, 2026 14:02");
    expect(formatDateTime24("2026-05-17T03:30:00Z")).toBe("May 16, 2026 23:30");
    expect(formatDateTime("2026-10-17T15:20:44Z")).toBe("Oct 17, 2026, 11:20 AM EDT");
  });

  it("prints only the time when the previous time is on the same New York day", () => {
    expect(formatDayTime("2026-05-16T17:58:00Z")).toBe("May 16 · 13:58");
    expect(formatDayTime("2026-05-16T18:01:00Z", "2026-05-16T17:58:00Z")).toBe("14:01");
    // 01:00 UTC on May 17 is still May 16 in New York.
    expect(formatDayTime("2026-05-17T01:00:00Z", "2026-05-16T17:58:00Z")).toBe("21:00");
    expect(formatDayTime("2026-05-17T05:00:00Z", "2026-05-16T17:58:00Z")).toBe("May 17 · 01:00");
  });

  it("says Today for the current New York day", () => {
    const now = new Date("2026-10-21T02:00:00Z"); // Oct 20, 22:00 in New York
    expect(dayLabel("2026-10-20T14:00:00Z", now)).toBe("Today");
    expect(dayLabel("2026-10-21T05:00:00Z", now)).toBe("Oct 21, 2026");
    expect(dayLabel("2025-01-25T15:00:00Z", now)).toBe("Jan 25, 2025");
  });

  it("words how long ago the list changed", () => {
    const now = new Date("2026-10-21T18:00:00Z");
    expect(updatedAgo("2026-10-21T17:59:30Z", now)).toBe("just now");
    expect(updatedAgo("2026-10-21T17:58:00Z", now)).toBe("2 min ago");
    expect(updatedAgo("2026-10-21T17:00:01Z", now)).toBe("59 min ago");
    expect(updatedAgo("2026-10-21T15:00:00Z", now)).toBe("3 h ago");
    expect(updatedAgo("2026-10-12T15:00:00Z", now)).toBe("Oct 12");
    expect(updatedAgo("2025-10-12T15:00:00Z", now)).toBe("Oct 12, 2025");
  });
});

describe("ids, counts and modes", () => {
  it("shortens fingerprints and ids", () => {
    expect(shortSha("9f2c0000000000000000000000000000000000000000000000000000000a41e")).toBe(
      "9f2c…a41e",
    );
    expect(shortId("3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35")).toBe("3f6c2a9e…");
    expect(plural(1, "floor")).toBe("1 floor");
    expect(plural(2, "entry", "entries")).toBe("2 entries");
  });

  it("always counts modes and names areas", () => {
    expect(modeSummary(["floor"])).toBe("whole floor × 1");
    expect(modeSummary(["floor", "floor"])).toBe("whole floor × 2");
    expect(modeSummary(["floor", "exterior"])).toBe("whole floor × 1, exterior × 1");
    expect(areaCount(["floor", "floor"])).toBe("2 floors");
    expect(areaCount(["floor", "room"])).toBe("2 areas");
    expect(areaCount([undefined])).toBe("1 floor");
  });

  it("humanises area keys for captures without a record", () => {
    expect(humanizeAreaKey("primary-closet")).toBe("Primary closet");
    expect(humanizeAreaKey("floor-1")).toBe("Floor 1");
    expect(captureLabel(undefined, "x", "floor-2")).toBe("Floor 2");
  });
});

describe("file names and roles", () => {
  const { pkg } = contractExampleCase();
  const record = pkg.captureRecord;

  it("names capture files by their capture label and visit files by their name", () => {
    const dxf = pkg.files.find((file) => file.role === "plan_dxf");
    expect(dxf).toBeDefined();
    expect(fileDisplayName(dxf?.path ?? "", record, dxf?.captureId, dxf?.areaKey)).toBe(
      "Floor 1 / plan.dxf",
    );
    const visit = pkg.files.find((file) => file.role === "capture_record");
    expect(pathDisplayName(visit?.path ?? "", pkg.files, record)).toBe("capture-record.json");
  });

  it("recognises a capture file from its path when the package's files are not at hand", () => {
    expect(
      pathDisplayName(
        "Original Exports/floor-2/a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60/mesh.glb",
        [],
        undefined,
      ),
    ).toBe("Floor 2 / mesh.glb");
    expect(
      pathDisplayName(
        "Source Register/7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5/capture-record.json",
        [],
        undefined,
      ),
    ).toBe("capture-record.json");
  });

  it("labels the retired phone report and groups mesh companions", () => {
    expect(ROLE_LABEL.spatial_report_pdf).toBe("Spatial report · phone (retired)");
    expect(ROLE_LABEL.plan_pdf).toBe("Plan sheet PDF");
    expect(ROLE_FILTER_GROUP.mesh_mtl).toBe("OBJ + MTL");
    expect(ROLE_FILTER_GROUP.texture).toBe("OBJ + MTL");
    expect(ROLE_FILTER_GROUP.spatial_report_pdf).toBe("Spatial report");
  });
});
