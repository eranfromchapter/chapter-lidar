// Synthetic raw RoomPlan file in the Codable JSON shape of Apple's CapturedRoom (one room) or
// CapturedStructure (several rooms: { version, rooms: [CapturedRoom] }).
//
// Shape notes (what a device export looks like and what this fixture mirrors):
// - simd values encode as arrays: dimensions [x, y, z], transform as one flat array of
//   16 numbers, column after column (Apple's simd_float4x4 Codable shape).
// - enums with associated values encode as { "<case>": { ... } }, for example
//   { "door": { "isOpen": false } } and { "high": {} } for confidence.
// - a surface sits in its own local frame: local X along the wall, local Y up, local Z the
//   normal; transform places the surface centre in the capture frame. dimensions = [width,
//   height, thickness], and RoomPlan reports thickness 0 for scanned surfaces.
// - objects: dimensions are the box size along its local axes; transform holds position and
//   rotation about +Y.
// - walls shared by two rooms are listed in both rooms, as separate surfaces.

import { toLocal, localWalls, localObjects, type LocalWall } from "./geometry.js";
import type { CaptureSpec, OpeningSpec } from "./spec.js";
import { float32Short, uuidFrom, type V3 } from "./util.js";

type Column = [number, number, number, number];
// simd_float4x4 Codable: 16 numbers, column after column (columns[3] is the translation).
export type Transform = number[];

export function f32(value: number): number {
  return float32Short(value);
}

/** simd_float4x4 Codable from three axis columns and a translation, as float32 values. */
export function transformOf(x: V3, y: V3, z: V3, t: V3): Transform {
  const col = (v: V3, w: number): Column => [f32(v[0]), f32(v[1]), f32(v[2]), w];
  return [...col(x, 0), ...col(y, 0), ...col(z, 0), ...col(t, 1)];
}

const CATEGORY_KEY: Record<string, string> = {
  bed: "bed",
  sofa: "sofa",
  stairs: "stairs",
  table: "table",
};

/** RoomPlan section label (CapturedRoom.Section.Label) for a room name. */
function sectionLabel(name: string): string {
  const lower = name.toLowerCase();
  if (lower.includes("kitchen")) return "kitchen";
  if (lower.includes("bath")) return "bathroom";
  if (lower.includes("bed")) return "bedroom";
  if (lower.includes("dining")) return "diningRoom";
  if (lower.includes("living")) return "livingRoom";
  return "unidentified";
}

function wallDirection(wall: LocalWall): { dx: number; dz: number } {
  return {
    dx: (wall.end[0] - wall.start[0]) / wall.lengthM,
    dz: (wall.end[2] - wall.start[2]) / wall.lengthM,
  };
}

function wallSurface(captureId: string, wall: LocalWall): Record<string, unknown> {
  const { dx, dz } = wallDirection(wall);
  const centre: V3 = [
    (wall.start[0] + wall.end[0]) / 2,
    wall.heightM / 2,
    (wall.start[2] + wall.end[2]) / 2,
  ];
  return {
    identifier: uuidFrom(`${captureId}:raw:${wall.id}`).toUpperCase(),
    category: { wall: {} },
    confidence: { high: {} },
    dimensions: [f32(wall.lengthM), f32(wall.heightM), 0],
    transform: transformOf([dx, 0, dz], [0, 1, 0], [-dz, 0, dx], centre),
    completedEdges: [],
    story: 0,
    curve: null,
    parentIdentifier: null,
    polygonCorners: [],
  };
}

function openingSurface(
  captureId: string,
  opening: OpeningSpec,
  wall: LocalWall,
): Record<string, unknown> {
  const { dx, dz } = wallDirection(wall);
  const along = opening.offsetM;
  const centre: V3 = [
    wall.start[0] + dx * along,
    opening.bottomM + opening.heightM / 2,
    wall.start[2] + dz * along,
  ];
  const category =
    opening.kind === "door"
      ? { door: { isOpen: false } }
      : opening.kind === "window"
        ? { window: {} }
        : { opening: {} };
  return {
    identifier: uuidFrom(`${captureId}:raw:${opening.id}`).toUpperCase(),
    parentIdentifier: uuidFrom(`${captureId}:raw:${wall.id}`).toUpperCase(),
    category,
    confidence: { high: {} },
    dimensions: [f32(opening.widthM), f32(opening.heightM), 0],
    transform: transformOf([dx, 0, dz], [0, 1, 0], [-dz, 0, dx], centre),
    completedEdges: [],
    story: 0,
    curve: null,
    polygonCorners: [],
  };
}

/** Builds the raw RoomPlan JSON value of one capture. */
export function buildRoomPlanJson(capture: CaptureSpec, captureId: string): unknown {
  const walls = localWalls(capture);
  const wallById = new Map(walls.map((wall) => [wall.id, wall]));
  const rooms = capture.rooms.map((room) => {
    const roomWalls = walls.filter((wall) => wall.roomIds.includes(room.id));
    const wallIds = new Set(roomWalls.map((wall) => wall.id));
    const openings = capture.openings.filter((opening) => wallIds.has(opening.wallId));
    const surfaces = (kind: string) =>
      openings
        .filter((opening) => opening.kind === kind)
        .map((opening) =>
          openingSurface(captureId, opening, wallById.get(opening.wallId) as LocalWall),
        );
    const polygon = room.polygon.map(([x, z]) => toLocal(capture.frame, [x, 0, z]));
    const xs = polygon.map((p) => p[0]);
    const zs = polygon.map((p) => p[2]);
    const cx = (Math.min(...xs) + Math.max(...xs)) / 2;
    const cz = (Math.min(...zs) + Math.max(...zs)) / 2;
    const floor = {
      identifier: uuidFrom(`${captureId}:raw:${room.id}:floor`).toUpperCase(),
      category: { floor: {} },
      confidence: { high: {} },
      dimensions: [
        f32(Math.max(...xs) - Math.min(...xs)),
        f32(Math.max(...zs) - Math.min(...zs)),
        0,
      ],
      // Local X = world X, local Y = world -Z, local Z (normal) = world +Y.
      transform: transformOf([1, 0, 0], [0, 0, -1], [0, 1, 0], [cx, 0, cz]),
      polygonCorners: polygon.map((p) => [f32(p[0] - cx), f32(-(p[2] - cz)), 0]),
      completedEdges: [],
      story: 0,
      curve: null,
      parentIdentifier: null,
    };
    const objects = localObjects(capture)
      .filter((object) => object.spec.roomId === room.id)
      .map((object) => {
        const radians = (object.rotYDeg * Math.PI) / 180;
        const c = Math.round(Math.cos(radians));
        const s = Math.round(Math.sin(radians));
        return {
          identifier: uuidFrom(`${captureId}:raw:${object.spec.id}`).toUpperCase(),
          category: { [CATEGORY_KEY[object.spec.category] as string]: {} },
          confidence: { high: {} },
          dimensions: object.sizeM.map(f32),
          transform: transformOf([c, 0, -s], [0, 1, 0], [s, 0, c], object.center),
          attributes: {},
          story: 0,
          parentIdentifier: null,
        };
      });
    return {
      // A device export has no top-level identifier on a CapturedRoom; it carries
      // referenceOriginTransform, sections and an opaque coreModel (not generated).
      version: 2,
      story: 0,
      referenceOriginTransform: transformOf([1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 0, 0]),
      walls: roomWalls.map((wall) => wallSurface(captureId, wall)),
      doors: surfaces("door"),
      windows: surfaces("window"),
      openings: surfaces("opening"),
      floors: [floor],
      objects,
      sections: [{ story: 0, label: sectionLabel(room.label), center: [f32(cx), 0, f32(cz)] }],
    };
  });
  if (rooms.length === 1) {
    return rooms[0];
  }
  // A structure also lists every room's elements at the top level.
  const all = (key: string) =>
    rooms.flatMap((room) => (room as unknown as Record<string, unknown[]>)[key] as unknown[]);
  return {
    version: 1,
    identifier: uuidFrom(`${captureId}:raw:structure`).toUpperCase(),
    rooms,
    walls: all("walls"),
    doors: all("doors"),
    windows: all("windows"),
    openings: all("openings"),
    floors: all("floors"),
    objects: all("objects"),
    sections: all("sections"),
  };
}
