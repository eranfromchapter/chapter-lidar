// Swift <-> TypeScript parity of the measurement engine (spec 11.2, SR-AC4): the report's port
// of PlanExport's PlanMetrics gives the phone's numbers for every good fixture capture model.
//
// The goldens in ./parity were recorded from PlanExport's PlanMetrics (Swift) on each capture
// model under fixtures/generated. They stand in for fixtures/report-parity (track T5's
// ReportParityGoldenTests) until those land; then this test reads those files instead.
// Numbers agree within 1e-9 relative (1e-6 for the inscribed rectangle's raster search),
// printed strings exactly.

import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import type { CaptureModel } from "@chapter/capture-contract";
import { longSide, shortSide } from "../../src/report/metrics/metrics-geometry.js";
import { planMetrics } from "../../src/report/metrics/room-metrics.js";
import { decimals, feetInches, squareFeet } from "../../src/report/metrics/units.js";
import { REPO } from "./support.js";

interface Rect {
  alongM: number;
  acrossM: number;
  angle: number;
}

interface GoldenRoom {
  id: string;
  label: string;
  type: string | null;
  floorAreaM2: number;
  perimeterM: number;
  frameAngle: number;
  bbox: Rect;
  inscribed: Rect;
  ceiling: { heightM: number; approximate: boolean; reasons: string[]; basis: string };
  volumeM3: number;
  wallAreaInclM2: number;
  wallAreaExclM2: number;
  walledLengthM: number;
  openings: Array<{ id: string; type: string; widthM: number; heightM: number; areaM2: number }>;
  objects: Array<{ id: string; category: string; sizeM: [number, number, number] }>;
  strings: Record<
    | "bboxLong"
    | "bboxShort"
    | "inscribedLong"
    | "inscribedShort"
    | "perimeter"
    | "ceiling"
    | "floorArea",
    string
  >;
}

interface Golden {
  model: string;
  rooms: GoldenRoom[];
  totals: {
    roomCount: number;
    bedrooms: number;
    bathrooms: number;
    livableAreaM2: number;
    wallAreaM2: number;
    windowAreaM2: number;
    volumeM3: number;
    volumeIsApproximate: boolean;
    perimeterM: number;
    perimeter: string;
  };
}

const DIR = fileURLToPath(new URL("./parity/", import.meta.url));
const files = readdirSync(DIR)
  .filter((name) => name.endsWith(".json"))
  .sort();

function near(actual: number, expected: number, what: string, tolerance = 1e-9): void {
  const scale = Math.max(1, Math.abs(actual), Math.abs(expected));
  assert.ok(
    Math.abs(actual - expected) <= tolerance * scale,
    `${what}: ${actual} (TypeScript) vs ${expected} (Swift)`,
  );
}

describe("metrics parity with PlanExport", () => {
  it("has goldens for every good fixture with a capture model", () => {
    assert.ok(files.length >= 7, files.join(", "));
    assert.ok(files.includes("sample-424-floor-1.json"));
  });

  for (const file of files) {
    it(file, () => {
      const golden = JSON.parse(readFileSync(join(DIR, file), "utf8")) as Golden;
      const model = JSON.parse(readFileSync(join(REPO, golden.model), "utf8")) as CaptureModel;
      const metrics = planMetrics(model);
      assert.equal(metrics.rooms.length, golden.rooms.length);
      metrics.rooms.forEach((room, i) => {
        const swift = golden.rooms[i] as GoldenRoom;
        const w = `${file} ${room.label}`;
        assert.equal(room.roomId, swift.id);
        assert.equal(room.label, swift.label);
        assert.equal(room.type ?? null, swift.type);
        near(room.floorAreaM2, swift.floorAreaM2, `${w} floor area`);
        near(room.perimeterM, swift.perimeterM, `${w} perimeter`);
        near(room.frameAngleRadians, swift.frameAngle, `${w} frame angle`);
        near(room.boundingBox.alongM, swift.bbox.alongM, `${w} B along`);
        near(room.boundingBox.acrossM, swift.bbox.acrossM, `${w} B across`);
        near(room.inscribed.alongM, swift.inscribed.alongM, `${w} I along`, 1e-6);
        near(room.inscribed.acrossM, swift.inscribed.acrossM, `${w} I across`, 1e-6);
        near(room.ceiling.heightM, swift.ceiling.heightM, `${w} ceiling`);
        assert.equal(room.ceiling.basis, swift.ceiling.basis, `${w} ceiling basis`);
        assert.deepEqual(
          [...room.ceiling.approximateReasons],
          swift.ceiling.reasons,
          `${w} reasons`,
        );
        near(room.volumeM3, swift.volumeM3, `${w} volume`);
        near(room.wallAreaIncludingOpeningsM2, swift.wallAreaInclM2, `${w} wall incl`);
        near(room.wallAreaExcludingOpeningsM2, swift.wallAreaExclM2, `${w} wall excl`);
        near(room.walledLengthM, swift.walledLengthM, `${w} walled length`);
        assert.deepEqual(
          room.openings.map((o) => [o.id, o.type]),
          swift.openings.map((o) => [o.id, o.type]),
        );
        room.openings.forEach((o, k) => {
          const s = swift.openings[k];
          near(o.widthM, s?.widthM ?? Number.NaN, `${w} opening ${o.id} width`);
          near(o.heightM, s?.heightM ?? Number.NaN, `${w} opening ${o.id} height`);
          near(o.areaM2, s?.areaM2 ?? Number.NaN, `${w} opening ${o.id} area`);
        });
        assert.deepEqual(
          room.objects.map((o) => [o.id, o.category]),
          swift.objects.map((o) => [o.id, o.category]),
        );
        room.objects.forEach((o, k) => {
          const size = swift.objects[k]?.sizeM ?? [Number.NaN, Number.NaN, Number.NaN];
          near(o.widthM, size[0], `${w} object ${o.id} width`);
          near(o.heightM, size[1], `${w} object ${o.id} height`);
          near(o.depthM, size[2], `${w} object ${o.id} depth`);
        });
        // The printed strings, exactly.
        assert.deepEqual(
          {
            bboxLong: feetInches(longSide(room.boundingBox)),
            bboxShort: feetInches(shortSide(room.boundingBox)),
            inscribedLong: feetInches(longSide(room.inscribed)),
            inscribedShort: feetInches(shortSide(room.inscribed)),
            perimeter: feetInches(room.perimeterM),
            ceiling: feetInches(room.ceiling.heightM),
            floorArea: `${decimals(squareFeet(room.floorAreaM2), 1)} ft²`,
          },
          swift.strings,
          w,
        );
      });
      const t = metrics.totals;
      const s = golden.totals;
      assert.deepEqual(
        [t.roomCount, t.bedrooms, t.bathrooms, t.volumeIsApproximate],
        [s.roomCount, s.bedrooms, s.bathrooms, s.volumeIsApproximate],
      );
      near(t.livableAreaM2, s.livableAreaM2, `${file} livable area`);
      near(t.wallAreaM2, s.wallAreaM2, `${file} wall area`);
      near(t.windowAreaM2, s.windowAreaM2, `${file} window area`);
      near(t.volumeM3, s.volumeM3, `${file} volume`);
      near(t.perimeterM, s.perimeterM, `${file} perimeter`);
      assert.equal(feetInches(t.perimeterM), s.perimeter);
    });
  }
});
