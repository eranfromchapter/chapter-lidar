// sample-424 (critique R-19): the 424 sample apartment of the design artboards as one intake
// package, for the plan sheet and the spatial report.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { compassState, northSymbol } from "@chapter/capture-contract";
import { shoelace } from "../src/geometry.js";
import { SAMPLE_424_NAME } from "../src/sample424.js";
import { loadSample } from "./helpers.js";

const sample = loadSample(SAMPLE_424_NAME);
const [capture] = sample.record.captures;
const model = [...sample.models.values()][0];

/** Floor areas of the sample's room table, square feet. */
const SAMPLE_AREAS_SQFT: Record<string, number> = {
  "Living Room": 223.4,
  "Bedroom 1": 187.1,
  "Bedroom 2": 85.6,
  "Room 1": 59.9,
  "Room 2": 58.1,
  Kitchen: 46.0,
  "Room 3": 43.5,
  "Bathroom 2": 33.6,
  "Bathroom 1": 32.8,
  "Room 4": 14.7,
  Closet: 14.1,
  "Room 5": 8.7,
};

describe("sample-424", () => {
  it("is one floor with the sample's twelve rooms, five of them unlabeled Room N", () => {
    assert.ok(capture !== undefined && model !== undefined);
    assert.equal(sample.record.captures.length, 1);
    assert.equal(capture.mode, "floor");
    assert.equal(capture.units.display, "imperial");
    assert.deepEqual(
      [...model.rooms.map((room) => room.label)].sort(),
      Object.keys(SAMPLE_AREAS_SQFT).sort(),
    );
    assert.equal(model.rooms.filter((room) => /^Room \d+$/.test(room.label)).length, 5);
  });

  it("traces each room within 10% of the sample's floor area (a trace, close not exact), outlines counter-clockwise", () => {
    assert.ok(model !== undefined);
    for (const room of model.rooms) {
      const outline = room.polygon.map(([x, , z]) => [x, z] as [number, number]);
      assert.ok(shoelace(outline) < 0, `${room.label} is counter-clockwise from +Y`);
      const sqft = -shoelace(outline) / 0.09290304;
      const expected = SAMPLE_AREAS_SQFT[room.label] as number;
      assert.ok(
        Math.abs(sqft - expected) / expected < 0.1,
        `${room.label}: ${sqft} vs ${expected}`,
      );
    }
  });

  it("has 14 objects, 8 doors, 4 passages and 2 windows, each on a wall of its room", () => {
    assert.ok(model !== undefined);
    assert.equal(model.objects.length, 14);
    assert.deepEqual([...new Set(model.objects.map((object) => object.category))].sort(), [
      "bathtub",
      "bed",
      "sink",
      "sofa",
      "storage",
      "stove",
      "table",
      "toilet",
    ]);
    assert.equal(model.doors.length, 8);
    assert.equal(model.openings.length, 4);
    assert.equal(model.windows.length, 2);
    const walls = new Map(model.walls.map((wall) => [wall.id, wall]));
    for (const opening of [...model.doors, ...model.openings, ...model.windows]) {
      const wall = walls.get(opening.wallId);
      assert.ok(wall !== undefined, opening.id);
      const length = Math.hypot(wall.end[0] - wall.start[0], wall.end[2] - wall.start[2]);
      assert.ok(opening.offsetM - opening.widthM / 2 >= -1e-9, opening.id);
      assert.ok(opening.offsetM + opening.widthM / 2 <= length + 1e-9, opening.id);
      assert.ok(opening.bottomM + opening.heightM <= wall.heightM, opening.id);
    }
  });

  it("walls are the room outlines at thickness 0; Room 4's south wall is lower (approximate ceiling)", () => {
    assert.ok(model !== undefined);
    const edges = model.rooms.reduce((sum, room) => sum + room.polygon.length, 0);
    assert.equal(model.walls.length, edges);
    assert.ok(model.walls.every((wall) => wall.thicknessM === 0 && wall.roomIds?.length === 1));
    const room4 = model.rooms.find((room) => room.label === "Room 4");
    assert.ok(room4 !== undefined);
    const heights = model.walls
      .filter((wall) => (wall.roomIds ?? []).includes(room4.id))
      .map((wall) => wall.heightM)
      .sort();
    assert.deepEqual(heights, [2.3, 2.474, 2.474, 2.474]);
  });

  it("records the skipped rooms of the design: Primary closet locked, Storage room not entered", () => {
    assert.ok(capture !== undefined);
    assert.deepEqual(capture.omittedRooms, [{ name: "Primary closet", reason: "locked" }]);
    assert.deepEqual(capture.inaccessibleRooms, [{ name: "Storage room" }]);
  });

  it("has a verified compass reading: true north 212.4°, ±8°", () => {
    assert.ok(capture !== undefined);
    assert.equal(sample.record.schemaVersion, "1.1.0");
    const state = compassState(capture);
    assert.deepEqual(state, { kind: "verified", heading: 212.4, accuracy: 8, source: "true" });
    const symbol = northSymbol(state);
    assert.equal(symbol.kind, "arrow");
    assert.deepEqual(symbol.kind === "arrow" ? symbol.lines : [], [
      "True north · compass",
      "±8° · 212°",
    ]);
  });

  it("has 7 photos of the Living Room and one of every other room, with direction sources", () => {
    assert.ok(model !== undefined);
    const photos = sample.manifest.files.filter((file) => file.role === "photo");
    const living = photos.filter((file) => file.photo?.room === "Living Room");
    assert.equal(living.length, 7);
    assert.deepEqual(
      living.map((file) => file.photo?.directionSource),
      ["compass", "compass", "manual", "manual", "compass", "compass", "manual"],
    );
    for (const room of model.rooms.filter((entry) => entry.label !== "Living Room")) {
      assert.equal(photos.filter((file) => file.photo?.room === room.label).length, 1, room.label);
    }
    assert.equal(photos.length, 18);
    assert.equal(new Set(photos.map((file) => file.sha256)).size, 18, "every photo is distinct");
  });

  it("controls A and B are the Living Room's extents", () => {
    assert.ok(model !== undefined);
    const living = model.rooms.find((room) => room.label === "Living Room");
    assert.ok(living !== undefined);
    const xs = living.polygon.map(([x]) => x);
    const zs = living.polygon.map(([, , z]) => z);
    const [a, b] = sample.controls.distances;
    assert.ok(
      Math.abs((a?.measurement.valueMm ?? 0) - (Math.max(...xs) - Math.min(...xs)) * 1000) < 1e-6,
    );
    assert.ok(
      Math.abs((b?.measurement.valueMm ?? 0) - (Math.max(...zs) - Math.min(...zs)) * 1000) < 1e-6,
    );
  });

  it("keeps the placeholder address, deal and operator (no real customer data)", () => {
    assert.equal(sample.record.address.formatted, "100 Example Street, Testville, NY 00000");
    assert.equal(sample.record.hub.dealId, "fixture-deal-0001");
    assert.equal(sample.record.operator.name, "Test Operator");
  });
});
