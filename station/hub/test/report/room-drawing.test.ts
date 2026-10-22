// Room page drawing (spec 5.5.1, 5.5.4): item markers are nudged off each other and never sit
// on the dimension strings around the room.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { dimensionRects } from "../../src/report/draw/floor.js";
import { layoutRoom } from "../../src/report/draw/room.js";
import { buildModel } from "../../src/report/model.js";
import { syntheticInput, testCanvas } from "./support.js";

/** One room with three doors close together on its top wall (the plan's far side). */
function crowdedTopWall() {
  const input = syntheticInput([
    { label: "Floor 1", rooms: [{ label: "Living Room", w: 5, d: 4, doors: 3 }] },
  ]);
  const floor = input.floors?.[0];
  assert.ok(floor !== undefined && floor.model.status === "ok");
  // Doors 0.25 m apart (about 13 pt at this scale): each later marker has to move.
  floor.model.model.doors.forEach((door, i) => {
    door.offsetM = 1.2 + i * 0.25;
    door.widthM = 0.2;
  });
  return buildModel(input);
}

const half = 6.5;
const overlaps = (
  p: { x: number; y: number },
  r: { x: number; y: number; width: number; height: number },
) =>
  p.x + half > r.x && p.x - half < r.x + r.width && p.y + half > r.y && p.y - half < r.y + r.height;

describe("room drawing markers", () => {
  it("keeps markers off the dimension strings and off each other", () => {
    const model = crowdedTopWall();
    const floor = model.floors[0];
    const room = model.rooms[0];
    assert.ok(floor !== undefined && room !== undefined);
    const canvas = testCanvas();
    const layout = layoutRoom(canvas, floor, room);
    assert.ok(layout);
    const doors = layout.markers.filter((m) => m.shape === "square");
    assert.equal(doors.length, 3);
    const strings = dimensionRects(canvas, layout.dims);
    for (const marker of layout.markers) {
      for (const rect of strings) {
        assert.ok(!overlaps(marker, rect), `marker ${marker.label} on a dimension string`);
      }
    }
    for (let i = 0; i < doors.length; i += 1) {
      for (let j = i + 1; j < doors.length; j += 1) {
        const a = doors[i] as (typeof doors)[number];
        const b = doors[j] as (typeof doors)[number];
        assert.ok(Math.hypot(a.x - b.x, a.y - b.y) >= 12.5, `markers ${a.label} and ${b.label}`);
      }
    }
  });
});
