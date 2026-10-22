// The spatial report prints what the phone's plan sheet prints (spatial-report 11.2, critique
// R-35, R-7): for every capture of fixtures/report-parity (written by PlanExport's
// ReportParityGoldenTests from the same fixtures) the report model has the same rooms with the
// same names, fill classes and printed numbers, the same floor area (sum of rooms), the same
// compass state and the north symbol of its own drawing; and the room fill rule, lengths and
// areas give the sheet's answer for each of the rule's own cases.

import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import type { CaptureMode, RoomType } from "@chapter/capture-contract";
import { fixed, ftIn, sqFt } from "../../src/report/format.js";
import { buildModel, fillClass, floorNorthSymbol, type ModelRoom } from "../../src/report/model.js";
import { fixtureInput, REPO, verdict424 } from "./support.js";

const DIR = join(REPO, "fixtures/report-parity");

interface GoldenSymbol {
  kind: "arrow" | "not_verified";
  angleCcw?: number;
  approximate?: boolean;
  lines?: [string, string];
  box?: string;
  caption?: string;
}

interface GoldenCapture {
  fixture: string;
  captureId: string;
  areaKey: string;
  label: string;
  rooms: Array<{
    id: string;
    label: string;
    fillClass: string;
    floorAreaM2: number;
    formatted: {
      floorArea: string;
      floorAreaMetric: string;
      boundingBox: string;
      inscribed: string;
      perimeter: string;
      ceiling: string;
    };
  }>;
  totals: { livableAreaM2: number; floorArea: string };
  north: { state: string; reason?: string; dominantAngleDeg: number; report: GoldenSymbol };
}

interface Rules {
  fill: Array<{
    label: string;
    type?: RoomType;
    objects: string[];
    mode: CaptureMode;
    fillClass: string;
  }>;
  lengths: Array<{ metres: number; length: string }>;
  areas: Array<{ squareMetres: number; area: string; metric: string }>;
}

const files = readdirSync(DIR)
  .filter((name) => name.endsWith(".json") && name !== "rules.json")
  .sort();

function near(actual: number, expected: number, what: string): void {
  const scale = Math.max(1, Math.abs(actual), Math.abs(expected));
  assert.ok(Math.abs(actual - expected) <= 1e-9 * scale, `${what}: ${actual} vs ${expected}`);
}

describe("parity with the plan sheet (fixtures/report-parity)", () => {
  it("has a golden for every good fixture capture", () => {
    assert.ok(files.length >= 6, files.join(", "));
    assert.ok(files.includes("sample-424-floor-1.json"));
    assert.ok(files.includes("two-floor-house-floor-2.json"));
  });

  for (const file of files) {
    it(file, async () => {
      const golden = JSON.parse(readFileSync(join(DIR, file), "utf8")) as GoldenCapture;
      const model = buildModel(await fixtureInput(golden.fixture, verdict424("limited")));
      const floor = model.floors.find((f) => f.captureId === golden.captureId);
      assert.ok(floor?.metrics !== undefined, `${file}: no readable floor`);
      assert.equal(floor.label, golden.label);
      assert.deepEqual(
        floor.rooms.map((r) => r.metrics.roomId).sort(),
        golden.rooms.map((r) => r.id).sort(),
      );
      for (const sheet of golden.rooms) {
        const room: ModelRoom | undefined = floor.rooms.find((r) => r.metrics.roomId === sheet.id);
        const w = `${file} ${sheet.id}`;
        assert.ok(room !== undefined, w);
        assert.equal(room.name, sheet.label, `${w} name`);
        assert.equal(room.fill, sheet.fillClass, `${w} fill class`);
        assert.equal(`${room.words.area} sq ft`, sheet.formatted.floorArea, `${w} area`);
        assert.equal(`${fixed(room.metrics.floorAreaM2, 1)} m²`, sheet.formatted.floorAreaMetric);
        assert.equal(room.words.bbox, sheet.formatted.boundingBox, `${w} B`);
        assert.equal(room.words.inscribed, sheet.formatted.inscribed, `${w} I`);
        assert.equal(room.words.perimeter, sheet.formatted.perimeter, `${w} perimeter`);
        assert.equal(room.words.ceiling, sheet.formatted.ceiling, `${w} ceiling`);
      }
      // "Floor area, sum of rooms": the unrounded room areas added, rounded once.
      const total = floor.metrics.totals.livableAreaM2;
      near(total, golden.totals.livableAreaM2, `${file} floor area`);
      near(
        total,
        floor.rooms.reduce((sum, r) => sum + r.metrics.floorAreaM2, 0),
        `${file} sum of rooms`,
      );
      assert.equal(`${sqFt(total)} sq ft · ${fixed(total, 1)} m²`, golden.totals.floorArea);
      // North: the same state; the arrow of the report's own drawing (rho = -a).
      assert.equal(
        floor.compass.kind === "not_verified" ? "not_verified" : floor.compass.kind,
        golden.north.state,
      );
      near(floor.rotationDegrees, golden.north.dominantAngleDeg, `${file} squaring`);
      const symbol = floorNorthSymbol(floor);
      const expected = golden.north.report;
      if (expected.kind === "arrow") {
        assert.equal(symbol.kind, "arrow");
        if (symbol.kind === "arrow") {
          near(symbol.angleCcw, expected.angleCcw ?? Number.NaN, `${file} arrow angle`);
          assert.equal(symbol.approximate, expected.approximate);
          assert.deepEqual(symbol.lines, expected.lines);
        }
      } else {
        assert.deepEqual(symbol, { kind: "box", box: expected.box, caption: expected.caption });
      }
    });
  }

  it("fills every case of the sheet's rule the same way", () => {
    const rules = JSON.parse(readFileSync(join(DIR, "rules.json"), "utf8")) as Rules;
    assert.ok(rules.fill.length >= 20);
    for (const c of rules.fill) {
      assert.equal(
        fillClass(c.label, c.type, c.objects, c.mode),
        c.fillClass,
        JSON.stringify([c.label, c.type ?? null, c.objects, c.mode]),
      );
    }
  });

  it("prints every length and area of the rule cases the same way", () => {
    const rules = JSON.parse(readFileSync(join(DIR, "rules.json"), "utf8")) as Rules;
    for (const c of rules.lengths) {
      assert.equal(ftIn(c.metres), c.length, `${c.metres} m`);
    }
    for (const c of rules.areas) {
      assert.equal(`${sqFt(c.squareMetres)} sq ft`, c.area, `${c.squareMetres} m²`);
      assert.equal(`${fixed(c.squareMetres, 1)} m²`, c.metric, `${c.squareMetres} m²`);
    }
  });
});
