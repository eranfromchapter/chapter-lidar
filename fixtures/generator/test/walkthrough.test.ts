// The RoomPlan-only walk-through fixture: one CapturedRoom of a whole apartment, shaped like a
// real iPhone export, with expected.json as its ground truth. Everything here is measured from
// roomplan.json itself, so the fixture keeps the shape room naming and room splitting are
// tested against: gaps in the outline walls, interior walls that stop short, sections for some
// rooms only, RoomPlan attributes and confidences.

import assert from "node:assert/strict";
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import { pointInPolygon, polygonArea, shoelace } from "../src/geometry.js";
import { float32Short, type P2 } from "../src/util.js";
import { buildWalkthrough, WALKTHROUGH_NAME } from "../src/walkthrough.js";
import { generatedDir, readIndex, readJson } from "./helpers.js";

interface Surface {
  identifier: string;
  parentIdentifier: string | null;
  category: Record<string, { isOpen?: boolean }>;
  confidence: Record<string, unknown>;
  dimensions: number[];
  transform: number[];
  completedEdges: unknown[];
  story: number;
  curve: null;
  polygonCorners: number[][];
}

interface RawObject {
  identifier: string;
  parentIdentifier: string | null;
  category: Record<string, unknown>;
  confidence: Record<string, unknown>;
  dimensions: number[];
  transform: number[];
  attributes: Record<string, string>;
  story: number;
}

interface RawRoom {
  version: number;
  story: number;
  referenceOriginTransform: number[];
  walls: Surface[];
  doors: Surface[];
  windows: Surface[];
  openings: Surface[];
  floors: Surface[];
  objects: RawObject[];
  sections: Array<{ story: number; label: string; center: number[] }>;
}

interface Expected {
  fixture: string;
  frame: { floorY: number };
  totals: {
    floorAreaM2: number;
    outlineCorners: number;
    outlineWithoutWallFraction: number;
    walls: number;
    interiorWalls: number;
    shortInteriorWallEnds: number;
    doors: number;
    openDoors: number;
    windows: number;
    openings: number;
    objects: number;
    sections: number;
  };
  rooms: Array<{
    id: string;
    label: string;
    type: string;
    areaM2: number;
    polygon: P2[];
    section: { index: number; label: string } | null;
    objects: Array<{ index: number; identifier: string; category: string }>;
  }>;
  sections: Array<{ index: number; label: string; roomId: string }>;
  walls: Array<{
    index: number;
    identifier: string;
    kind: "outline" | "interior";
    roomIds: string[];
    shortEnds: Array<{ end: "start" | "end"; junction: P2; shortByM: number }>;
  }>;
  openings: Array<{
    kind: "door" | "window" | "opening";
    index: number;
    identifier: string;
    wallIdentifier: string;
    isOpen?: boolean;
    roomIds: string[];
  }>;
}

const dir = join(generatedDir, "roomplan-only", WALKTHROUGH_NAME);
const raw = readJson<RawRoom>(join(dir, "roomplan.json"));
const expected = readJson<Expected>(join(dir, "expected.json"));

// Every attribute RoomPlan (iOS 17 and later) writes, by object category, with its values.
const ATTRIBUTES: Record<string, Record<string, string[]>> = {
  storage: { StorageType: ["cabinet", "shelf"] },
  sofa: { SofaType: ["rectangular", "lShaped", "lShapedExtension", "singleSeat", "unidentified"] },
  table: {
    TableType: ["coffee", "dining", "unidentified"],
    TableShapeType: ["rectangular", "circularElliptic", "lShaped", "unidentified"],
  },
  chair: {
    ChairType: ["dining", "stool", "swivel", "unidentified"],
    ChairArmType: ["existing", "missing"],
    ChairBackType: ["existing", "missing"],
    ChairLegType: ["four", "star", "unidentified"],
  },
};

const SECTION_TYPE: Record<string, string> = {
  livingRoom: "living_room",
  kitchen: "kitchen",
  bedroom: "bedroom",
  bathroom: "bathroom",
  unidentified: "hallway",
};

function caseName(value: Record<string, unknown>): string {
  const keys = Object.keys(value);
  assert.equal(keys.length, 1, `one enum case in ${JSON.stringify(value)}`);
  return keys[0] as string;
}

// Column `index` of a flat simd_float4x4 (16 numbers, column after column).
function column(transform: readonly number[], index: number): number[] {
  return transform.slice(index * 4, index * 4 + 4);
}

/** Plan position [x, z] of a transform's translation. */
function planAt(transform: readonly number[]): P2 {
  const t = column(transform, 3);
  return [t[0] as number, t[2] as number];
}

/** Start and end [x, z] of a wall centreline (local X along the wall). */
function wallEnds(wall: Surface): [P2, P2] {
  const x = column(wall.transform, 0);
  const [cx, cz] = planAt(wall.transform);
  const half = (wall.dimensions[0] as number) / 2;
  const dx = (x[0] as number) * half;
  const dz = (x[2] as number) * half;
  return [
    [cx - dx, cz - dz],
    [cx + dx, cz + dz],
  ];
}

/** The floor outline [x, z] in the capture frame, in polygonCorners order. */
function floorOutline(): P2[] {
  const floor = raw.floors[0] as Surface;
  const [x, y, t] = [0, 1, 3].map((i) => column(floor.transform, i)) as [
    number[],
    number[],
    number[],
  ];
  return floor.polygonCorners.map(([lx, ly]) => [
    (t[0] as number) + (x[0] as number) * (lx as number) + (y[0] as number) * (ly as number),
    (t[2] as number) + (x[2] as number) * (lx as number) + (y[2] as number) * (ly as number),
  ]);
}

function distance(a: P2, b: P2): number {
  return Math.hypot(b[0] - a[0], b[1] - a[1]);
}

function distanceToSegment(point: P2, a: P2, b: P2): number {
  const dx = b[0] - a[0];
  const dz = b[1] - a[1];
  const lengthSquared = dx * dx + dz * dz;
  const t =
    lengthSquared === 0
      ? 0
      : Math.max(0, Math.min(1, ((point[0] - a[0]) * dx + (point[1] - a[1]) * dz) / lengthSquared));
  return distance(point, [a[0] + dx * t, a[1] + dz * t]);
}

function edges(polygon: readonly P2[]): Array<[P2, P2]> {
  return polygon.map((p, i) => [p, polygon[(i + 1) % polygon.length] as P2]);
}

function distanceToOutline(point: P2, outline: readonly P2[]): number {
  return Math.min(...edges(outline).map(([a, b]) => distanceToSegment(point, a, b)));
}

function allTransforms(): number[][] {
  return [
    raw.referenceOriginTransform,
    ...[...raw.walls, ...raw.doors, ...raw.windows, ...raw.openings, ...raw.floors].map(
      (surface) => surface.transform,
    ),
    ...raw.objects.map((object) => object.transform),
  ];
}

describe(`${WALKTHROUGH_NAME} (RoomPlan-only fixture)`, () => {
  it("is one CapturedRoom like a device export, with no top-level identifier", () => {
    assert.deepEqual(Object.keys(raw).sort(), [
      "doors",
      "floors",
      "objects",
      "openings",
      "referenceOriginTransform",
      "sections",
      "story",
      "version",
      "walls",
      "windows",
    ]);
    assert.equal(raw.version, 2);
    assert.equal(raw.story, 0);
    assert.equal(expected.fixture, WALKTHROUGH_NAME);
  });

  it("writes every transform as a flat simd_float4x4 and every number as a float32", () => {
    const transforms = allTransforms();
    const floorTransform = (raw.floors[0] as Surface).transform;
    for (const transform of transforms) {
      assert.equal(transform.length, 16);
      assert.deepEqual([transform[3], transform[7], transform[11], transform[15]], [0, 0, 0, 1]);
      const axes = [0, 1, 2].map((i) => column(transform, i).slice(0, 3));
      axes.forEach((a, i) =>
        axes.forEach((b, j) => {
          const dot = a.reduce((sum, value, k) => sum + value * (b[k] as number), 0);
          assert.ok(Math.abs(dot - (i === j ? 1 : 0)) < 1e-6, `axes ${i}, ${j}: ${dot}`);
        }),
      );
      // Turned about +Y only: the local up axis (the normal, for the floor) is straight up.
      const up = transform === floorTransform ? 2 : 1;
      assert.deepEqual(column(transform, up), [0, 1, 0, 0]);
    }
    const numbers = [
      ...transforms.flat(),
      ...[...raw.walls, ...raw.doors, ...raw.windows, ...raw.openings, ...raw.floors].flatMap(
        (surface) => [...surface.dimensions, ...surface.polygonCorners.flat()],
      ),
      ...raw.objects.flatMap((object) => object.dimensions),
      ...raw.sections.flatMap((section) => section.center),
    ];
    for (const value of numbers) {
      assert.equal(float32Short(value), value, `${value} is a shortest float32 decimal`);
    }
  });

  it("gives every surface the fields Apple's decoder needs", () => {
    const wallIds = new Set(raw.walls.map((wall) => wall.identifier));
    const surfaces = [...raw.walls, ...raw.doors, ...raw.windows, ...raw.openings, ...raw.floors];
    const ids = [...surfaces, ...raw.objects].map((item) => item.identifier);
    assert.equal(new Set(ids).size, ids.length, "identifiers are unique");
    for (const id of ids) {
      assert.match(id, /^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/);
    }
    for (const surface of surfaces) {
      assert.equal(surface.curve, null);
      assert.deepEqual(surface.completedEdges, []);
      assert.equal(surface.story, 0);
      assert.equal(surface.dimensions.length, 3);
      assert.equal(surface.dimensions[2], 0, "scanned surfaces have no thickness");
    }
    for (const surface of [...raw.walls, ...raw.floors]) {
      assert.equal(surface.parentIdentifier, null);
    }
    for (const surface of [...raw.doors, ...raw.windows, ...raw.openings]) {
      assert.ok(wallIds.has(surface.parentIdentifier ?? ""), "parentIdentifier is a wall");
      assert.deepEqual(surface.polygonCorners, []);
    }
    for (const wall of raw.walls) {
      assert.deepEqual(wall.polygonCorners, []);
      assert.deepEqual(wall.category, { wall: {} });
    }
  });

  it("has one floor whose polygonCorners outline the whole apartment, clockwise from +Y", () => {
    assert.equal(raw.floors.length, 1);
    const outline = floorOutline();
    assert.ok(outline.length >= 20, `${outline.length} corners`);
    assert.equal(outline.length, expected.totals.outlineCorners);
    assert.ok(shoelace(outline) > 0, "clockwise seen from +Y, as a device writes it");
    assert.ok(Math.abs(polygonArea(outline) - expected.totals.floorAreaM2) < 1e-3);
    const roomArea = expected.rooms.reduce((sum, room) => sum + room.areaM2, 0);
    assert.ok(Math.abs(roomArea - expected.totals.floorAreaM2) < 1e-6, "rooms tile the floor");
  });

  it("leaves 12-19% of the outline without a wall", () => {
    const outline = floorOutline();
    const walls = raw.walls.map(wallEnds);
    let total = 0;
    let bare = 0;
    for (const [a, b] of edges(outline)) {
      const length = distance(a, b);
      const steps = Math.max(1, Math.round(length / 0.01));
      for (let i = 0; i < steps; i += 1) {
        const t = (i + 0.5) / steps;
        const p: P2 = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
        const covered = walls.some(([s, e]) => {
          const cross = ((e[0] - s[0]) * (b[1] - a[1]) - (e[1] - s[1]) * (b[0] - a[0])) / length;
          return Math.abs(cross) < 0.01 * distance(s, e) && distanceToSegment(p, s, e) < 0.01;
        });
        bare += covered ? 0 : length / steps;
      }
      total += length;
    }
    const fraction = bare / total;
    assert.ok(fraction >= 0.12 && fraction <= 0.19, `outline without a wall: ${fraction}`);
    assert.ok(Math.abs(fraction - expected.totals.outlineWithoutWallFraction) < 0.005);
  });

  it("has 25-35 walls, and 6-9 interior wall ends stop 0.15-1.0 m short of their junction", () => {
    assert.ok(raw.walls.length >= 25 && raw.walls.length <= 35, `${raw.walls.length} walls`);
    assert.equal(raw.walls.length, expected.totals.walls);
    assert.equal(expected.walls.length, raw.walls.length);
    const outline = floorOutline();
    const ends = raw.walls.map(wallEnds);
    const short: string[] = [];
    raw.walls.forEach((wall, index) => {
      const want = expected.walls[index];
      assert.ok(want !== undefined);
      assert.equal(want.identifier, wall.identifier);
      const [start, end] = ends[index] as [P2, P2];
      const mid: P2 = [(start[0] + end[0]) / 2, (start[1] + end[1]) / 2];
      const onOutline = [start, end, mid].every((p) => distanceToOutline(p, outline) < 1e-3);
      assert.equal(onOutline ? "outline" : "interior", want.kind, `wall ${index} kind`);
      if (want.kind === "outline") {
        assert.deepEqual(want.shortEnds, []);
        return;
      }
      for (const [name, point] of [
        ["start", start],
        ["end", end],
      ] as const) {
        const gap = Math.min(
          ...ends.flatMap(([s, e], other) =>
            other === index ? [] : [distanceToSegment(point, s, e)],
          ),
        );
        const listed: Expected["walls"][number]["shortEnds"][number] | undefined =
          want.shortEnds.find((entry) => entry.end === name);
        if (gap < 1e-3) {
          assert.equal(listed, undefined, `wall ${index} ${name} meets another wall`);
          continue;
        }
        assert.ok(gap >= 0.15 && gap <= 1.0, `wall ${index} ${name} is ${gap} m from any wall`);
        assert.ok(listed !== undefined, `wall ${index} ${name} is listed as short`);
        assert.ok(Math.abs(distance(point, listed.junction) - listed.shortByM) < 1e-4);
        assert.ok(listed.shortByM >= 0.15 && listed.shortByM <= 1.0);
        short.push(`${index} ${name}`);
      }
    });
    assert.ok(short.length >= 6 && short.length <= 9, `${short.length} short interior ends`);
    assert.equal(short.length, expected.totals.shortInteriorWallEnds);
    assert.equal(
      expected.walls.filter((wall) => wall.kind === "interior").length,
      expected.totals.interiorWalls,
    );
  });

  it("has no wall where the kitchen opens to the living room", () => {
    const kitchen = expected.rooms.find((room) => room.type === "kitchen");
    const living = expected.rooms.find((room) => room.type === "living_room");
    assert.ok(kitchen !== undefined && living !== undefined);
    const shared = edges(kitchen.polygon).filter(([a, b]) =>
      [a, b].every((p) => distanceToOutline(p, living.polygon) < 1e-5),
    );
    assert.equal(shared.length, 1);
    const [a, b] = shared[0] as [P2, P2];
    assert.ok(distance(a, b) > 3, "a 3 m wide opening");
    const mid: P2 = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
    for (const [s, e] of raw.walls.map(wallEnds)) {
      assert.ok(distanceToSegment(mid, s, e) > 0.3, "no wall between kitchen and living room");
    }
  });

  it("labels the living room, two bedrooms, bathroom and kitchen, the hall unidentified, no closet", () => {
    assert.equal(raw.sections.length, 6);
    assert.equal(raw.sections.length, expected.totals.sections);
    assert.deepEqual(raw.sections.map((section) => section.label).sort(), [
      "bathroom",
      "bedroom",
      "bedroom",
      "kitchen",
      "livingRoom",
      "unidentified",
    ]);
    raw.sections.forEach((section, index) => {
      assert.equal(section.story, 0);
      assert.equal(section.center.length, 3);
      const at: P2 = [section.center[0] as number, section.center[2] as number];
      const rooms = expected.rooms.filter((room) => pointInPolygon(at, room.polygon));
      assert.equal(rooms.length, 1, `section ${index} is in one room`);
      const room = rooms[0];
      assert.ok(room !== undefined);
      assert.deepEqual(room.section, { index, label: section.label });
      assert.deepEqual(expected.sections[index], { index, label: section.label, roomId: room.id });
      assert.equal(room.type, SECTION_TYPE[section.label], `${section.label} section`);
    });
    const closet = expected.rooms.find((room) => room.type === "closet");
    assert.equal(closet?.section, null, "RoomPlan has no closet label");
  });

  it("has RoomPlan objects with attributes, mixed confidences and a few parents", () => {
    const count = (category: string) =>
      raw.objects.filter((object) => caseName(object.category) === category).length;
    const wanted: Record<string, number> = {
      bed: 2,
      sofa: 1,
      table: 2,
      chair: 3,
      refrigerator: 1,
      stove: 1,
      oven: 1,
      sink: 2,
      toilet: 1,
      bathtub: 1,
      television: 1,
    };
    for (const [category, n] of Object.entries(wanted)) {
      assert.equal(count(category), n, category);
    }
    const storage = raw.objects.filter((object) => caseName(object.category) === "storage");
    const kinds = new Set(storage.map((object) => object.attributes.StorageType));
    assert.deepEqual([...kinds].sort(), ["cabinet", "shelf"]);
    assert.equal(raw.objects.length, expected.totals.objects);

    const objectIds = new Set(raw.objects.map((object) => object.identifier));
    const confidences = new Map<string, number>();
    for (const object of raw.objects) {
      const category = caseName(object.category);
      const allowed = ATTRIBUTES[category] ?? {};
      for (const [key, value] of Object.entries(object.attributes)) {
        assert.ok(allowed[key]?.includes(value), `${category} attribute ${key}: ${value}`);
      }
      if (category === "storage" || category === "sofa" || category === "table") {
        assert.deepEqual(Object.keys(object.attributes).sort(), Object.keys(allowed).sort());
      }
      const confidence = caseName(object.confidence);
      confidences.set(confidence, (confidences.get(confidence) ?? 0) + 1);
      assert.equal(object.story, 0);
      assert.equal(object.dimensions.length, 3);
      if (object.parentIdentifier !== null) {
        assert.ok(objectIds.has(object.parentIdentifier), "parent is another object");
        assert.notEqual(object.parentIdentifier, object.identifier);
      }
    }
    assert.deepEqual([...confidences.keys()].sort(), ["high", "low", "medium"]);
    const low = confidences.get("low") ?? 0;
    assert.ok(low > (confidences.get("medium") ?? 0) && low > (confidences.get("high") ?? 0));
    assert.ok(raw.objects.some((object) => Object.keys(object.attributes).length === 0));
    assert.ok(raw.objects.filter((object) => object.parentIdentifier !== null).length >= 2);
  });

  it("lists every object in exactly the room that holds it", () => {
    const listed = expected.rooms.flatMap((room) => room.objects.map((entry) => ({ room, entry })));
    assert.equal(listed.length, raw.objects.length);
    assert.deepEqual(
      listed.map(({ entry }) => entry.index).sort((a, b) => a - b),
      [...raw.objects.keys()],
    );
    for (const { room, entry } of listed) {
      const object = raw.objects[entry.index];
      assert.ok(object !== undefined);
      assert.equal(object.identifier, entry.identifier);
      assert.equal(caseName(object.category), entry.category);
      assert.ok(
        pointInPolygon(planAt(object.transform), room.polygon),
        `${entry.category} in ${room.id}`,
      );
    }
    const bathroom = expected.rooms.find((room) => room.type === "bathroom");
    assert.ok(bathroom?.objects.some((entry) => entry.category === "toilet"));
  });

  it("has doors seen open and closed, one passage opening and windows, each in its wall", () => {
    const isOpen = raw.doors.map((door) => door.category.door?.isOpen);
    assert.ok(isOpen.includes(true) && isOpen.includes(false));
    assert.equal(raw.doors.length, expected.totals.doors);
    assert.equal(isOpen.filter((value) => value === true).length, expected.totals.openDoors);
    assert.equal(raw.openings.length, 1);
    assert.equal(raw.openings.length, expected.totals.openings);
    assert.ok(raw.windows.length >= 1);
    assert.equal(raw.windows.length, expected.totals.windows);
    const wallById = new Map(raw.walls.map((wall) => [wall.identifier, wall]));
    const lists = { door: raw.doors, window: raw.windows, opening: raw.openings };
    assert.equal(expected.openings.length, raw.doors.length + raw.windows.length + 1);
    for (const want of expected.openings) {
      const surface = lists[want.kind][want.index];
      assert.ok(surface !== undefined);
      assert.equal(surface.identifier, want.identifier);
      assert.equal(surface.parentIdentifier, want.wallIdentifier);
      assert.equal(caseName(surface.category), want.kind);
      assert.equal(surface.category.door?.isOpen, want.isOpen);
      const wall = wallById.get(want.wallIdentifier);
      assert.ok(wall !== undefined);
      const [start, end] = wallEnds(wall);
      const centre = planAt(surface.transform);
      const half = (surface.dimensions[0] as number) / 2;
      const dir: P2 = [
        (end[0] - start[0]) / distance(start, end),
        (end[1] - start[1]) / distance(start, end),
      ];
      const along = (centre[0] - start[0]) * dir[0] + (centre[1] - start[1]) * dir[1];
      assert.ok(distanceToSegment(centre, start, end) < 1e-3, `${want.kind} on its wall`);
      assert.ok(along - half >= -1e-4 && along + half <= distance(start, end) + 1e-4);
      const bottom = (surface.transform[13] as number) - (surface.dimensions[1] as number) / 2;
      const wallBottom = (wall.transform[13] as number) - (wall.dimensions[1] as number) / 2;
      assert.ok(Math.abs(wallBottom - expected.frame.floorY) < 1e-5, "walls stand on the floor");
      if (want.kind !== "window") {
        assert.ok(Math.abs(bottom - wallBottom) < 1e-5, `${want.kind} starts at the floor`);
      }
      assert.ok(want.roomIds.length >= 1);
    }
  });

  it("documents seven rooms of the expected types, counter-clockwise, with their areas", () => {
    assert.deepEqual(expected.rooms.map((room) => room.type).sort(), [
      "bathroom",
      "bedroom",
      "bedroom",
      "closet",
      "hallway",
      "kitchen",
      "living_room",
    ]);
    for (const room of expected.rooms) {
      assert.ok(shoelace(room.polygon) < 0, `${room.id} is counter-clockwise from +Y`);
      assert.ok(Math.abs(polygonArea(room.polygon) - room.areaM2) < 1e-4, `${room.id} area`);
      assert.ok(room.label.length > 0);
    }
  });

  it("is RoomPlan-only: not in index.json and no package", () => {
    const index = readIndex();
    assert.ok(!index.fixtures.some((fixture) => fixture.name === WALKTHROUGH_NAME));
    assert.equal(index.fixtures.length, 4);
    assert.deepEqual(readdirSync(dir).sort(), ["expected.json", "roomplan.json"]);
  });

  it("is deterministic and equal to the committed files", () => {
    const first = buildWalkthrough();
    const second = buildWalkthrough();
    assert.equal(JSON.stringify(first), JSON.stringify(second));
    assert.deepEqual(first.roomPlan, raw);
    assert.deepEqual(first.expected, expected);
  });
});
