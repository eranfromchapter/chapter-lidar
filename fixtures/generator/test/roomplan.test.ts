// The raw RoomPlan file (Codable shape) maps back to the capture model: this is the mapping
// the F2 adapter has to implement, written out as a test of the fixtures.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import type { CaptureModel } from "@chapter/capture-contract";
import { loadGood } from "./helpers.js";

type Column = [number, number, number, number];
interface Surface {
  identifier: string;
  parentIdentifier?: string;
  category: Record<string, unknown>;
  confidence: Record<string, unknown>;
  dimensions: [number, number, number];
  transform: [Column, Column, Column, Column];
  polygonCorners?: Array<[number, number, number]>;
}
interface RawRoom {
  walls: Surface[];
  doors: Surface[];
  windows: Surface[];
  openings: Surface[];
  floors: Surface[];
  objects: Surface[];
}

const TOLERANCE = 1e-5;

function near(actual: number, expected: number, label: string): void {
  assert.ok(Math.abs(actual - expected) < TOLERANCE, `${label}: ${actual} vs ${expected}`);
}

function nearVec(actual: readonly number[], expected: readonly number[], label: string): void {
  assert.equal(actual.length, expected.length, label);
  actual.forEach((value, i) => near(value, expected[i] as number, `${label}[${i}]`));
}

function roomsOf(raw: unknown): RawRoom[] {
  const value = raw as { rooms?: RawRoom[] };
  return value.rooms ?? [raw as RawRoom];
}

describe("raw RoomPlan JSON", () => {
  for (const name of ["box-room", "l-shaped-room", "two-room-apartment", "two-floor-house"]) {
    it(`${name}: maps to the capture model geometry`, () => {
      const fixture = loadGood(name);
      for (const capture of fixture.record.captures) {
        const model = fixture.models.get(capture.captureId) as CaptureModel;
        const rawPath = fixture.manifest.files.find(
          (file) => file.role === "raw_roomplan_json" && file.captureId === capture.captureId,
        )?.path as string;
        const raw = JSON.parse(readFileSync(join(fixture.root, rawPath), "utf8")) as unknown;
        const rooms = roomsOf(raw);
        const walls = rooms.flatMap((room) => room.walls);
        assert.equal(walls.length, model.walls.length);
        const wallSurfaceById = new Map(walls.map((wall) => [wall.identifier, wall]));
        const wallStarts = new Map<string, [number, number, number]>();
        walls.forEach((surface, index) => {
          const expected = model.walls[index];
          assert.ok(expected !== undefined);
          const [x, y, , t] = surface.transform;
          const length = surface.dimensions[0];
          const height = surface.dimensions[1];
          const base = [t[0] - (x[0] * length) / 2, t[1] - height / 2, t[2] - (x[2] * length) / 2];
          const end = [t[0] + (x[0] * length) / 2, t[1] - height / 2, t[2] + (x[2] * length) / 2];
          nearVec(base, expected.start, `${expected.id} start`);
          nearVec(end, expected.end, `${expected.id} end`);
          near(height, expected.heightM, `${expected.id} height`);
          near(surface.dimensions[2], expected.thicknessM, `${expected.id} thickness`);
          nearVec([y[0], y[1], y[2]], [0, 1, 0], "wall up axis");
          assert.deepEqual(surface.category, { wall: {} });
          wallStarts.set(surface.identifier, [
            base[0] as number,
            base[1] as number,
            base[2] as number,
          ]);
        });
        const opening = (list: Surface[], expected: CaptureModel["doors"]) => {
          assert.equal(list.length, expected.length);
          list.forEach((surface, index) => {
            const want = expected[index];
            assert.ok(want !== undefined);
            const parent = wallSurfaceById.get(surface.parentIdentifier ?? "");
            assert.ok(parent !== undefined, `${want.id} has a parent wall`);
            const start = wallStarts.get(parent.identifier) as [number, number, number];
            const dir = parent.transform[0];
            const t = surface.transform[3];
            const along = (t[0] - start[0]) * dir[0] + (t[2] - start[2]) * dir[2];
            near(along, want.offsetM, `${want.id} offset`);
            near(t[1] - surface.dimensions[1] / 2, want.bottomM, `${want.id} bottom`);
            near(surface.dimensions[0], want.widthM, `${want.id} width`);
            near(surface.dimensions[1], want.heightM, `${want.id} height`);
            const wallIndex = walls.indexOf(parent);
            assert.equal(model.walls[wallIndex]?.id, want.wallId, `${want.id} wall`);
          });
        };
        opening(
          rooms.flatMap((room) => room.doors),
          model.doors,
        );
        opening(
          rooms.flatMap((room) => room.windows),
          model.windows,
        );
        opening(
          rooms.flatMap((room) => room.openings),
          model.openings,
        );
        const floors = rooms.flatMap((room) => room.floors);
        assert.equal(floors.length, model.rooms.length);
        floors.forEach((floor, index) => {
          const want = model.rooms[index];
          assert.ok(want !== undefined);
          const t = floor.transform[3];
          const corners = (floor.polygonCorners ?? []).map(
            ([lx, ly]) => [t[0] + lx, 0, t[2] - ly] as [number, number, number],
          );
          assert.equal(corners.length, want.polygon.length);
          corners.forEach((corner, i) =>
            nearVec(corner, want.polygon[i] as number[], `${want.id} corner ${i}`),
          );
        });
        const objects = rooms.flatMap((room) => room.objects);
        assert.equal(objects.length, model.objects.length);
        objects.forEach((surface, index) => {
          const want = model.objects[index];
          assert.ok(want !== undefined);
          nearVec(surface.dimensions, want.box.sizeM, `${want.id} size`);
          nearVec(
            [surface.transform[3][0], surface.transform[3][1], surface.transform[3][2]],
            want.box.center,
            `${want.id} centre`,
          );
          const x = surface.transform[0];
          const yaw = Math.atan2(-x[2], x[0]);
          nearVec(
            [0, Math.sin(yaw / 2), 0, Math.cos(yaw / 2)],
            want.box.rotation,
            `${want.id} rotation`,
          );
        });
      }
    });
  }

  it("uses the CapturedRoom shape for one room and the CapturedStructure shape for several", () => {
    const single = loadGood("box-room");
    const apartment = loadGood("two-room-apartment");
    const read = (fixture: ReturnType<typeof loadGood>) =>
      JSON.parse(
        readFileSync(join(fixture.root, fixture.fileOfRole("raw_roomplan_json")), "utf8"),
      ) as Record<string, unknown>;
    assert.ok(Array.isArray(read(single).walls));
    assert.ok(Array.isArray(read(apartment).rooms));
    assert.equal((read(apartment).rooms as unknown[]).length, 2);
    // Enum cases with associated values encode as { case: {...} }.
    const raw = read(single) as { doors: Surface[]; walls: Surface[] };
    assert.deepEqual(raw.doors[0]?.category, { door: { isOpen: false } });
    assert.deepEqual(raw.walls[0]?.confidence, { high: {} });
  });
});
