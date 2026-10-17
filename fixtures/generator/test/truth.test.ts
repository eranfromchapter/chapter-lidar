// F11 AC3: truth.json dimensions match the generated geometry to within 0.1 mm.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import type { CaptureModel } from "@chapter/capture-contract";
import { NOISE_M, readDepthSamples } from "../src/depth.js";
import { polygonArea, polygonPerimeter, toHouse } from "../src/geometry.js";
import { fixtureSpecs } from "../src/shapes.js";
import type { P2 } from "../src/util.js";
import { dxfNumbers, glbPositions, loadGood, parseDxf, type LoadedFixture } from "./helpers.js";

/** 0.1 mm in metres. */
const TOL = 1e-4;
const GOOD = ["box-room", "l-shaped-room", "two-room-apartment", "two-floor-house"];

function near(actual: number, expected: number, label: string, tolerance = TOL): void {
  assert.ok(Math.abs(actual - expected) <= tolerance, `${label}: ${actual} vs ${expected}`);
}

function planOf(model: CaptureModel, roomId: string): P2[] {
  const room = model.rooms.find((candidate) => candidate.id === roomId);
  assert.ok(room !== undefined);
  return room.polygon.map(([x, , z]) => [x, z] as P2);
}

function filesOf(fixture: LoadedFixture, role: string, captureId: string): Buffer {
  const path = fixture.manifest.files.find(
    (f) => f.role === role && f.captureId === captureId,
  )?.path;
  assert.ok(path !== undefined, `${role} for ${captureId}`);
  return fixture.bytes(path);
}

describe("truth.json matches the capture model", () => {
  for (const name of GOOD) {
    it(`${name}: rooms, walls, openings, objects`, () => {
      const fixture = loadGood(name);
      const truth = fixture.truth;
      assert.ok(truth !== undefined);
      assert.equal(truth.visitId, fixture.record.visitId);
      assert.equal(truth.hub.address, fixture.record.address.formatted);
      assert.equal(truth.hub.dealId, fixture.record.hub.dealId);
      for (const tc of truth.captures) {
        const model = fixture.models.get(tc.captureId);
        assert.ok(model !== undefined);
        assert.equal(model.areaKey, tc.areaKey);
        for (const room of tc.rooms) {
          const plan = planOf(model, room.id);
          const xs = plan.map((p) => p[0]);
          const zs = plan.map((p) => p[1]);
          near(Math.max(...xs) - Math.min(...xs), room.widthM, `${room.label} width`);
          near(Math.max(...zs) - Math.min(...zs), room.lengthM, `${room.label} length`);
          near(polygonArea(plan), room.areaM2, `${room.label} area`);
          near(polygonPerimeter(plan), room.perimeterM, `${room.label} perimeter`);
          near(model.rooms.find((r) => r.id === room.id)?.heightM ?? NaN, room.heightM, "height");
        }
        assert.equal(model.walls.length, tc.walls.length);
        for (const wall of tc.walls) {
          const actual = model.walls.find((w) => w.id === wall.id);
          assert.ok(actual !== undefined);
          near(
            Math.hypot(actual.end[0] - actual.start[0], actual.end[2] - actual.start[2]),
            wall.lengthM,
            `${wall.id} length`,
          );
          near(actual.heightM, wall.heightM, `${wall.id} height`);
        }
        const openings = [...model.doors, ...model.windows, ...model.openings];
        assert.equal(openings.length, tc.openings.length);
        for (const truthOpening of tc.openings) {
          const actual = openings.find((o) => o.id === truthOpening.id);
          assert.ok(actual !== undefined);
          near(actual.widthM, truthOpening.widthM, `${actual.id} width`);
          near(actual.heightM, truthOpening.heightM, `${actual.id} height`);
          near(actual.bottomM, truthOpening.bottomM, `${actual.id} bottom`);
          near(actual.offsetM, truthOpening.offsetM, `${actual.id} offset`);
          assert.equal(actual.wallId, truthOpening.wallId);
        }
        for (const object of tc.objects) {
          const actual = model.objects.find((o) => o.id === object.id);
          assert.ok(actual !== undefined);
          object.sizeM.forEach((v, i) =>
            near(actual.box.sizeM[i] as number, v, `${object.id} size`),
          );
          object.centerM.forEach((v, i) =>
            near(actual.box.center[i] as number, v, `${object.id} centre`),
          );
        }
      }
    });

    it(`${name}: mesh, DXF and CSV agree with truth`, () => {
      const fixture = loadGood(name);
      const truth = fixture.truth;
      assert.ok(truth !== undefined);
      for (const tc of truth.captures) {
        // GLB: accessor bounds and the positions themselves.
        const glb = glbPositions(filesOf(fixture, "mesh_glb", tc.captureId));
        const min = [Infinity, Infinity, Infinity];
        const max = [-Infinity, -Infinity, -Infinity];
        for (let i = 0; i < glb.positions.length; i += 3) {
          for (let a = 0; a < 3; a += 1) {
            min[a] = Math.min(min[a] as number, glb.positions[i + a] as number);
            max[a] = Math.max(max[a] as number, glb.positions[i + a] as number);
          }
        }
        for (let a = 0; a < 3; a += 1) {
          near(min[a] as number, tc.boundsM.min[a] as number, `GLB min ${a}`);
          near(max[a] as number, tc.boundsM.max[a] as number, `GLB max ${a}`);
          near(glb.min[a] as number, tc.boundsM.min[a] as number, `GLB accessor min ${a}`);
          near(glb.max[a] as number, tc.boundsM.max[a] as number, `GLB accessor max ${a}`);
        }
        // OBJ bounds (6 decimals).
        const obj = filesOf(fixture, "mesh_obj", tc.captureId).toString("utf8");
        const omin = [Infinity, Infinity, Infinity];
        const omax = [-Infinity, -Infinity, -Infinity];
        for (const line of obj.split("\n").filter((l) => l.startsWith("v "))) {
          line
            .split(" ")
            .slice(1)
            .map(Number)
            .forEach((v, a) => {
              omin[a] = Math.min(omin[a] as number, v);
              omax[a] = Math.max(omax[a] as number, v);
            });
        }
        for (let a = 0; a < 3; a += 1) {
          near(omin[a] as number, tc.boundsM.min[a] as number, `OBJ min ${a}`);
          near(omax[a] as number, tc.boundsM.max[a] as number, `OBJ max ${a}`);
        }
        // DXF: wall lines in millimetres, plan y = -z.
        const dxf = parseDxf(filesOf(fixture, "plan_dxf", tc.captureId).toString("utf8"));
        const wallLines = dxf.entities.filter((e) => e.type === "LINE" && e.layer === "A-WALL");
        assert.equal(wallLines.length, tc.walls.length);
        const dxfLengths = wallLines.map(
          (line) =>
            Math.hypot(
              (dxfNumbers(line, 11)[0] as number) - (dxfNumbers(line, 10)[0] as number),
              (dxfNumbers(line, 21)[0] as number) - (dxfNumbers(line, 20)[0] as number),
            ) / 1000,
        );
        tc.walls.forEach((wall, i) =>
          near(dxfLengths[i] as number, wall.lengthM, `DXF ${wall.id}`),
        );
        // CSV: per-room dimensions (mm) and area.
        const rows = filesOf(fixture, "rooms_csv", tc.captureId)
          .toString("utf8")
          .split("\n")
          .filter((line) => line !== "" && !line.startsWith("#"))
          .slice(1)
          .map((line) => line.split(","));
        assert.equal(rows.length, tc.rooms.length);
        tc.rooms.forEach((room, i) => {
          const row = rows[i] as string[];
          assert.equal(row[2], room.label);
          near(Number(row[3]) / 1000, room.widthM, `CSV ${room.label} width`);
          near(Number(row[4]) / 1000, room.lengthM, `CSV ${room.label} length`);
          near(Number(row[5]) / 1000, room.heightM, `CSV ${room.label} height`);
          near(Number(row[6]), room.areaM2, `CSV ${room.label} area`, 0.01);
        });
      }
    });

    it(`${name}: LAS extents and depth samples stay within the 5 mm noise`, () => {
      const fixture = loadGood(name);
      const truth = fixture.truth;
      assert.ok(truth !== undefined);
      for (const tc of truth.captures) {
        const model = fixture.models.get(tc.captureId) as CaptureModel;
        const las = filesOf(fixture, "point_cloud_las", tc.captureId);
        const view = new DataView(las.buffer, las.byteOffset, las.byteLength);
        // LAS is Z-up: x -> x, y -> -z, z -> y.
        const lasMax = [
          view.getFloat64(179, true),
          view.getFloat64(195, true),
          view.getFloat64(211, true),
        ];
        const lasMin = [
          view.getFloat64(187, true),
          view.getFloat64(203, true),
          view.getFloat64(219, true),
        ];
        const tolerance = NOISE_M + 0.0011;
        near(lasMin[0] as number, tc.boundsM.min[0] as number, "LAS min x", tolerance);
        near(lasMax[0] as number, tc.boundsM.max[0] as number, "LAS max x", tolerance);
        near(-(lasMax[1] as number), tc.boundsM.min[2] as number, "LAS min z", tolerance);
        near(-(lasMin[1] as number), tc.boundsM.max[2] as number, "LAS max z", tolerance);
        near(lasMin[2] as number, 0, "LAS min height", tolerance);
        near(lasMax[2] as number, tc.boundsM.max[1] as number, "LAS max height", tolerance);

        const samples = readDepthSamples(filesOf(fixture, "raw_depth", tc.captureId));
        assert.ok(samples.length > 300);
        const planes: Array<(x: number, y: number, z: number) => number> = [
          (_x, y) => y,
          ...model.rooms.map((room) => (_x: number, y: number) => y - room.heightM),
          ...model.walls.map((wall) => {
            const dx = wall.end[0] - wall.start[0];
            const dz = wall.end[2] - wall.start[2];
            const length = Math.hypot(dx, dz);
            return (x: number, _y: number, z: number) =>
              ((x - wall.start[0]) * -dz + (z - wall.start[2]) * dx) / length;
          }),
        ];
        let maxOffset = 0;
        for (const sample of samples) {
          const distance = Math.min(
            ...planes.map((plane) => Math.abs(plane(sample.x, sample.y, sample.z))),
          );
          assert.ok(
            distance <= NOISE_M * Math.sqrt(3) + 1e-6,
            `sample ${distance} m from every surface`,
          );
          maxOffset = Math.max(maxOffset, distance);
        }
        assert.ok(maxOffset > 0.001, "noise is present");
      }
    });
  }

  it("field controls equal truth and are two perpendicular long distances per floor", () => {
    for (const name of GOOD) {
      const fixture = loadGood(name);
      const truth = fixture.truth;
      assert.ok(truth !== undefined);
      for (const tc of truth.captures) {
        const mine = fixture.controls.distances.filter((d) => d.capture.captureId === tc.captureId);
        assert.deepEqual(mine.map((d) => d.axis).sort(), ["A", "B"]);
        for (const distance of tc.controlDistances) {
          const control = mine.find((d) => d.axis === distance.axis);
          assert.ok(control !== undefined);
          near(control.measurement.valueMm / 1000, distance.lengthM, `${name} ${distance.axis}`);
          assert.ok(["tape", "laser"].includes(control.measurement.method));
        }
        // The two distances are the two extents of the floor: perpendicular by construction.
        const extents = [
          tc.boundsM.max[0] - tc.boundsM.min[0],
          tc.boundsM.max[2] - tc.boundsM.min[2],
        ].sort();
        const lengths = tc.controlDistances.map((d) => d.lengthM).sort();
        extents.forEach((extent, i) => near(extent, lengths[i] as number, `${name} extent`));
        for (const ceiling of fixture.controls.ceilingHeights.filter(
          (c) => c.capture.captureId === tc.captureId,
        )) {
          const room = tc.rooms.find((r) => r.label === ceiling.room);
          assert.ok(room !== undefined);
          near(ceiling.measurement.valueMm / 1000, room.heightM, `${ceiling.room} ceiling`);
        }
        const model = fixture.models.get(tc.captureId) as CaptureModel;
        for (const control of fixture.controls.openings.filter(
          (o) => o.capture.captureId === tc.captureId,
        )) {
          const opening = tc.openings.find((o) => `${tc.areaKey}-opening-${o.id}` === control.id);
          assert.ok(opening !== undefined);
          near(control.width.valueMm / 1000, opening.widthM, `${control.id} width`);
          near((control.height?.valueMm ?? NaN) / 1000, opening.heightM, `${control.id} height`);
          assert.ok(model.rooms.some((room) => room.label === control.room));
        }
      }
    }
  });

  it("the two-floor house: stair void, floor-to-floor and shared landmarks", () => {
    const fixture = loadGood("two-floor-house");
    const truth = fixture.truth;
    assert.ok(truth !== undefined);
    assert.equal(truth.captures.length, 2);
    const [floor1, floor2] = truth.captures;
    assert.ok(floor1 !== undefined && floor2 !== undefined);
    near(truth.floorToFloorM ?? NaN, 2.95, "floor-to-floor");
    const control = fixture.controls.floorToFloor[0];
    assert.ok(control !== undefined);
    near(control.measurement.valueMm / 1000, 2.95, "floor-to-floor control");
    // Stair void: the upper floor is the lower floor minus the void.
    const void_ = truth.stairVoid;
    assert.ok(void_ !== undefined);
    assert.equal(void_.areaM2, 3);
    near(
      (floor1.rooms[0]?.areaM2 ?? 0) - (floor2.rooms[0]?.areaM2 ?? 0),
      void_.areaM2,
      "void area",
    );
    // Two shared landmarks, visible in both captures; mapping floor 2 back to the house frame
    // gives the floor-1 position, so the landmarks really tie the two frames together.
    assert.equal(truth.landmarks.length, 2);
    assert.equal(fixture.controls.landmarks.length, 2);
    const spec = fixtureSpecs().find((s) => s.name === "two-floor-house");
    const frame2 = spec?.captures[1]?.frame;
    assert.ok(frame2 !== undefined);
    for (const landmark of truth.landmarks) {
      const p1 = landmark.positionM["floor-1"];
      const p2 = landmark.positionM["floor-2"];
      assert.ok(p1 !== undefined && p2 !== undefined);
      assert.notDeepEqual(p1, p2, "frames are deliberately different");
      toHouse(frame2, p2).forEach((v, i) => near(v, p1[i] as number, `${landmark.id} axis ${i}`));
    }
    for (const landmark of fixture.controls.landmarks) {
      assert.equal(new Set(landmark.captures.map((c) => c.captureId)).size, 2);
    }
    // Floor 2 is in its own frame: rotated 90 degrees, so its long side runs along Z.
    assert.equal(floor2.frame.rotYDeg, 90);
  });

  it("the committed truth files are readable JSON with the documented shape", () => {
    for (const name of GOOD) {
      const fixture = loadGood(name);
      const text = readFileSync(join(fixture.root, "..", "truth.json"), "utf8");
      assert.equal(JSON.parse(text).fixture, name);
    }
  });
});
