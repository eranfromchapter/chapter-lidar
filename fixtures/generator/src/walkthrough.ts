// RoomPlan-only fixture "apartment-walkthrough": one CapturedRoom of a whole two-bedroom
// apartment, scanned by walking through every doorway. It is shaped like the real iPhone exports
// the floorplan report plan was checked against (docs/floorplan-report-plan.md) and is the test
// input for room naming and room splitting. It is not an intake package and is not listed in
// index.json.
//
// What a device walk-through export looks like, and what this fixture mirrors:
// - one CapturedRoom, version 2, no top-level identifier, with referenceOriginTransform and
//   sections. coreModel (Apple's opaque base64 blob) is not generated.
// - one floor surface whose polygonCorners outline the whole apartment, wound clockwise seen
//   from +Y. The floor is below the capture origin (the phone's height when the scan started)
//   and the plan is turned about +Y against the capture axes.
// - walls along most of the outline but not all of it: none behind tall furniture and none
//   across short jogs. Interior walls meet at junctions, except a few that stop short of the
//   wall they should reach. No wall where the kitchen opens to the living room.
// - sections ({ story, label, center }) for most rooms. RoomPlan has no closet label; the hall
//   gets "unidentified".
// - objects with attributes ({ "StorageType": "cabinet" }), mostly low or medium confidence; a
//   few name the object they sit on (parentIdentifier). Doors are seen open and closed.
//
// The apartment is written below in a layout frame with exact decimals (metres, plan x and z,
// +Y up, polygons counter-clockwise seen from +Y). expected.json holds the ground truth in the
// capture frame: each room's label, type, outline, area, section and objects.

import { pointInPolygon, polygonArea, polygonPerimeter, shoelace } from "./geometry.js";
import { f32, transformOf } from "./roomplan.js";
import { dist2, mulberry32, round6, seedFrom, uuidFrom, type P2, type V3 } from "./util.js";

export const WALKTHROUGH_NAME = "apartment-walkthrough";

type Confidence = "high" | "medium" | "low";
export type RoomType = "living_room" | "kitchen" | "bedroom" | "bathroom" | "closet" | "hallway";
type SectionLabel = "livingRoom" | "bedroom" | "bathroom" | "kitchen" | "unidentified";

interface LayoutRoom {
  id: string;
  label: string;
  type: RoomType;
  polygon: P2[];
}

interface LayoutWall {
  id: string;
  a: P2;
  b: P2;
  heightM: number;
  /** An interior wall end that stops short: which end, and the junction it should have met. */
  short?: { end: "start" | "end"; junction: P2 };
}

interface LayoutOpening {
  id: string;
  kind: "door" | "window" | "opening";
  wallId: string;
  /** Distance along the wall from `a` to the centre of the opening. */
  offsetM: number;
  bottomM: number;
  widthM: number;
  heightM: number;
  confidence: Confidence;
  isOpen?: boolean;
}

interface LayoutObject {
  id: string;
  /** RoomPlan object category (CapturedRoom.Object.Category case name). */
  category: string;
  /** Plan position of the box centre. */
  at: P2;
  /** Height of the box centre above the floor. */
  centreY: number;
  /** Box size [width, height, depth] along its local axes. */
  sizeM: V3;
  /** Rotation about +Y in the layout frame, degrees. */
  yawDeg: number;
  confidence: Confidence;
  attributes: Record<string, string>;
  /** The object this one sits on or belongs to. */
  parentId?: string;
}

interface LayoutSection {
  label: SectionLabel;
  at: P2;
}

const WALL_H = 2.49;
/** The bay in the living room has a lower ceiling. */
const BAY_H = 2.31;
/** Floor level in the capture frame: the phone started the scan 1.31 m above the floor. */
const FLOOR_Y = -1.31;
/** Section centres sit about half a wall height above the floor, as on a device. */
const SECTION_Y = 1.25;
/** The layout frame is turned this much about +Y into the capture frame. */
const YAW_DEG = -14.2;
/** Layout point under the capture origin (where the scan started, in the living room). */
const ORIGIN: P2 = [2.6, 6.2];
/** referenceOriginTransform: a turn about +Y and a small offset, like a device export. */
const REFERENCE_YAW_DEG = 37;
const REFERENCE_OFFSET: V3 = [-0.18, 0.05, 0.27];

// Floor outline of the whole apartment, counter-clockwise seen from +Y. Bedroom 1 sits 0.1 m in
// from the living room's west wall; the entry recess has one slightly skewed side; the living
// room has a bay; the kitchen has a refrigerator recess; the bedroom, bathroom and closet north
// walls are not in line.
const OUTLINE: P2[] = [
  [0.1, 0],
  [0.1, 3.6],
  [0, 3.6],
  [0, 5.2],
  [-0.9, 5.25],
  [-0.9, 6.4],
  [0, 6.4],
  [0, 8.0],
  [2.0, 8.0],
  [2.0, 8.45],
  [4.4, 8.45],
  [4.4, 8.0],
  [6.0, 8.0],
  [6.0, 7.2],
  [9.85, 7.2],
  [9.85, 5.8],
  [10.15, 5.8],
  [10.15, 5.0],
  [9.85, 5.0],
  [9.85, 3.6],
  [10.0, 3.6],
  [10.0, -0.1],
  [6.7, -0.1],
  [6.7, 0.15],
  [3.5, 0.15],
  [3.5, 0],
];

// The intended rooms. They tile the outline exactly. The kitchen and the living room meet along
// x = 6.0 with no wall between them.
const ROOMS: LayoutRoom[] = [
  {
    id: "living-room",
    label: "Living Room",
    type: "living_room",
    polygon: [
      [0, 3.6],
      [0, 5.2],
      [-0.9, 5.25],
      [-0.9, 6.4],
      [0, 6.4],
      [0, 8.0],
      [2.0, 8.0],
      [2.0, 8.45],
      [4.4, 8.45],
      [4.4, 8.0],
      [6.0, 8.0],
      [6.0, 3.6],
    ],
  },
  {
    id: "kitchen",
    label: "Kitchen",
    type: "kitchen",
    polygon: [
      [6.0, 3.6],
      [6.0, 7.2],
      [9.85, 7.2],
      [9.85, 5.8],
      [10.15, 5.8],
      [10.15, 5.0],
      [9.85, 5.0],
      [9.85, 3.6],
    ],
  },
  { id: "hall", label: "Hall", type: "hallway", polygon: rect(3.5, 2.2, 6.7, 3.6) },
  { id: "bedroom-1", label: "Bedroom 1", type: "bedroom", polygon: rect(0.1, 0, 3.5, 3.6) },
  { id: "bathroom", label: "Bathroom", type: "bathroom", polygon: rect(3.5, 0.15, 5.7, 2.2) },
  { id: "closet", label: "Closet", type: "closet", polygon: rect(5.7, 0.15, 6.7, 2.2) },
  { id: "bedroom-2", label: "Bedroom 2", type: "bedroom", polygon: rect(6.7, -0.1, 10.0, 3.6) },
];

function wall(id: string, a: P2, b: P2, heightM = WALL_H): LayoutWall {
  return { id, a, b, heightM };
}

function shortWall(id: string, a: P2, b: P2, end: "start" | "end", junction: P2): LayoutWall {
  return { id, a, b, heightM: WALL_H, short: { end, junction } };
}

// Outline walls (wall-1 to wall-21), then interior walls (wall-22 to wall-31). Outline without a
// wall: bedroom 1 west behind the wardrobe (1.0 m), the living room south behind the shelf
// (0.7 m), the kitchen south behind the pantry (1.65 m), the refrigerator recess (1.4 m), bedroom
// 2 east behind the wardrobe (0.7 m) and three short jogs (0.1, 0.15, 0.15 m).
const WALLS: LayoutWall[] = [
  wall("wall-1", [0.1, 0], [0.1, 2.6]),
  wall("wall-2", [0, 3.6], [0, 5.2]),
  wall("wall-3", [0, 5.2], [-0.9, 5.25]),
  wall("wall-4", [-0.9, 5.25], [-0.9, 6.4]),
  wall("wall-5", [-0.9, 6.4], [0, 6.4]),
  wall("wall-6", [0, 6.4], [0, 8.0]),
  wall("wall-7", [0, 8.0], [2.0, 8.0]),
  wall("wall-8", [2.0, 8.0], [2.0, 8.45], BAY_H),
  wall("wall-9", [2.0, 8.45], [4.4, 8.45], BAY_H),
  wall("wall-10", [4.4, 8.45], [4.4, 8.0], BAY_H),
  wall("wall-11", [4.4, 8.0], [5.3, 8.0]),
  wall("wall-12", [6.0, 8.0], [6.0, 7.2]),
  wall("wall-13", [6.0, 7.2], [8.2, 7.2]),
  wall("wall-14", [9.85, 7.2], [9.85, 5.8]),
  wall("wall-15", [9.85, 5.0], [9.85, 3.6]),
  wall("wall-16", [10.0, 3.6], [10.0, 0.6]),
  wall("wall-17", [10.0, -0.1], [6.7, -0.1]),
  wall("wall-18", [6.7, -0.1], [6.7, 0.15]),
  wall("wall-19", [6.7, 0.15], [5.7, 0.15]),
  wall("wall-20", [5.7, 0.15], [3.5, 0.15]),
  wall("wall-21", [3.5, 0], [0.1, 0]),
  shortWall("wall-22", [3.5, 0.45], [3.5, 2.2], "start", [3.5, 0.15]),
  wall("wall-23", [3.5, 2.2], [3.5, 3.6]),
  shortWall("wall-24", [0.6, 3.6], [3.5, 3.6], "start", [0.1, 3.6]),
  shortWall("wall-25", [3.75, 2.2], [5.7, 2.2], "start", [3.5, 2.2]),
  wall("wall-26", [5.7, 2.2], [6.7, 2.2]),
  shortWall("wall-27", [5.7, 0.55], [5.7, 2.2], "start", [5.7, 0.15]),
  shortWall("wall-28", [6.7, 0.35], [6.7, 2.2], "start", [6.7, 0.15]),
  shortWall("wall-29", [6.7, 2.2], [6.7, 3.4], "end", [6.7, 3.6]),
  wall("wall-30", [3.5, 3.6], [6.7, 3.6]),
  shortWall("wall-31", [6.7, 3.6], [9.4, 3.6], "end", [9.85, 3.6]),
];

const OPENINGS: LayoutOpening[] = [
  door("door-entry", "wall-4", 0.58, 0.92, 2.13, "high", false),
  door("door-bedroom-1", "wall-23", 0.62, 0.78, 2.05, "high", true),
  door("door-bathroom", "wall-25", 1.2, 0.72, 2.02, "medium", true),
  door("door-closet", "wall-26", 0.5, 0.62, 1.98, "medium", false),
  door("door-bedroom-2", "wall-29", 0.6, 0.8, 2.03, "high", false),
  windowAt("window-living-room", "wall-9", 1.2, 2.0, 1.6, 0.62, "high"),
  windowAt("window-bedroom-1", "wall-21", 1.7, 1.6, 1.5, 0.8, "high"),
  windowAt("window-bedroom-2", "wall-17", 1.6, 1.8, 1.5, 0.75, "medium"),
  windowAt("window-kitchen", "wall-13", 1.0, 1.2, 1.1, 1.05, "high"),
  {
    id: "opening-hall",
    kind: "opening",
    wallId: "wall-30",
    offsetM: 1.1,
    bottomM: 0,
    widthM: 0.92,
    heightM: 1.98,
    confidence: "high",
  },
];

const CABINET = { StorageType: "cabinet" };
const SHELF = { StorageType: "shelf" };
const DINING_CHAIR = {
  ChairArmType: "missing",
  ChairType: "unidentified",
  ChairLegType: "four",
  ChairBackType: "existing",
};

const OBJECTS: LayoutObject[] = [
  // Living room.
  item("sofa", "sofa", [2.1, 4.15], 0.426, [2.14, 0.852, 1.04], 180, "medium", {
    SofaType: "rectangular",
  }),
  item("coffee-table", "table", [2.1, 5.35], 0.215, [1.27, 0.43, 0.84], 0, "high", {
    TableType: "coffee",
    TableShapeType: "rectangular",
  }),
  item("television", "television", [1.0, 7.93], 1.45, [1.2, 0.69, 0.1], 0, "medium", {}),
  item("living-shelf", "storage", [5.62, 7.8], 0.67, [0.7, 1.34, 0.36], 0, "low", SHELF),
  // Kitchen.
  item("refrigerator", "refrigerator", [9.775, 5.4], 0.92, [0.8, 1.84, 0.75], 90, "low", {}),
  item("base-cabinet", "storage", [7.3, 6.9], 0.45, [2.4, 0.9, 0.6], 0, "medium", CABINET),
  item("pantry", "storage", [9.2, 6.9], 1.05, [1.3, 2.1, 0.6], 0, "low", CABINET),
  item("wall-cabinet", "storage", [8.05, 7.03], 1.95, [0.9, 0.7, 0.33], 0, "low", CABINET),
  item("oven", "oven", [8.0, 6.85], 0.47, [0.75, 0.94, 0.72], 0, "low", {}),
  {
    ...item("stove", "stove", [8.0, 6.85], 0.97, [0.75, 0.1, 0.72], 0, "low", {}),
    parentId: "base-cabinet",
  },
  {
    ...item("kitchen-sink", "sink", [7.0, 6.95], 0.83, [0.52, 0.16, 0.41], 0, "low", {}),
    parentId: "base-cabinet",
  },
  item("dining-table", "table", [7.7, 4.9], 0.38, [1.2, 0.76, 0.8], 0, "high", {
    TableType: "unidentified",
    TableShapeType: "rectangular",
  }),
  {
    ...item("chair-1", "chair", [6.95, 4.9], 0.46, [0.46, 0.92, 0.5], 90, "low", DINING_CHAIR),
    parentId: "dining-table",
  },
  item("chair-2", "chair", [7.7, 5.55], 0.46, [0.46, 0.92, 0.5], 192, "low", {}),
  item("chair-3", "chair", [8.45, 4.85], 0.46, [0.46, 0.92, 0.5], 250, "medium", {
    ...DINING_CHAIR,
    ChairLegType: "unidentified",
  }),
  // Bedroom 1.
  item("bed-1", "bed", [1.25, 1.5], 0.374, [1.92, 0.75, 2.23], 90, "low", {}),
  item("wardrobe-1", "storage", [0.4, 3.1], 1.05, [1.0, 2.1, 0.6], 90, "low", CABINET),
  // Bedroom 2.
  item("bed-2", "bed", [8.95, 1.6], 0.271, [1.35, 0.54, 2.07], 90, "medium", {}),
  item("wardrobe-2", "storage", [9.7, 0.4], 1.1, [1.0, 2.2, 0.6], 90, "low", CABINET),
  // Bathroom.
  item("bathtub", "bathtub", [4.3, 0.5], 0.205, [1.5, 0.41, 0.68], 0, "low", {}),
  item("toilet", "toilet", [5.37, 1.3], 0.405, [0.44, 0.81, 0.66], 270, "medium", {}),
  item("vanity", "storage", [3.8, 1.55], 0.42, [0.8, 0.84, 0.5], 90, "low", CABINET),
  {
    ...item("bathroom-sink", "sink", [3.8, 1.55], 0.78, [0.53, 0.14, 0.41], 90, "low", {}),
    parentId: "vanity",
  },
  // Closet.
  item("closet-shelf", "storage", [6.2, 0.45], 0.9, [0.9, 1.8, 0.4], 0, "high", SHELF),
];

// In the order a scan reports them. No section for the closet.
const SECTIONS: LayoutSection[] = [
  { label: "bedroom", at: [8.3, 1.9] },
  { label: "kitchen", at: [7.9, 5.3] },
  { label: "livingRoom", at: [2.7, 6.0] },
  { label: "unidentified", at: [5.0, 2.95] },
  { label: "bathroom", at: [4.5, 1.25] },
  { label: "bedroom", at: [1.9, 1.85] },
];

function rect(x0: number, z0: number, x1: number, z1: number): P2[] {
  return [
    [x0, z0],
    [x0, z1],
    [x1, z1],
    [x1, z0],
  ];
}

function door(
  id: string,
  wallId: string,
  offsetM: number,
  widthM: number,
  heightM: number,
  confidence: Confidence,
  isOpen: boolean,
): LayoutOpening {
  return { id, kind: "door", wallId, offsetM, bottomM: 0, widthM, heightM, confidence, isOpen };
}

function windowAt(
  id: string,
  wallId: string,
  offsetM: number,
  widthM: number,
  heightM: number,
  bottomM: number,
  confidence: Confidence,
): LayoutOpening {
  return { id, kind: "window", wallId, offsetM, bottomM, widthM, heightM, confidence };
}

function item(
  id: string,
  category: string,
  at: P2,
  centreY: number,
  sizeM: V3,
  yawDeg: number,
  confidence: Confidence,
  attributes: Record<string, string>,
): LayoutObject {
  return { id, category, at, centreY, sizeM, yawDeg, confidence, attributes };
}

const COS = Math.cos((YAW_DEG * Math.PI) / 180);
const SIN = Math.sin((YAW_DEG * Math.PI) / 180);

/** Layout direction (dx, 0, dz) turned into the capture frame. */
function turn(dx: number, dz: number): V3 {
  return [dx * COS + dz * SIN, 0, -dx * SIN + dz * COS];
}

/** Layout plan point into the capture frame. */
function toCapture(point: P2): P2 {
  const [x, , z] = turn(point[0] - ORIGIN[0], point[1] - ORIGIN[1]);
  return [x, z];
}

function rawId(id: string): string {
  return uuidFrom(`${WALKTHROUGH_NAME}:raw:${id}`).toUpperCase();
}

function confidence(value: Confidence): Record<string, unknown> {
  return { [value]: {} };
}

/** Unit direction of a wall in the layout frame. */
function along(wall: LayoutWall): P2 {
  const length = dist2(wall.a, wall.b);
  return [(wall.b[0] - wall.a[0]) / length, (wall.b[1] - wall.a[1]) / length];
}

function wallSurface(wall: LayoutWall): Record<string, unknown> {
  const [ux, uz] = along(wall);
  const [dx, , dz] = turn(ux, uz);
  const mid = toCapture([(wall.a[0] + wall.b[0]) / 2, (wall.a[1] + wall.b[1]) / 2]);
  return {
    identifier: rawId(wall.id),
    category: { wall: {} },
    confidence: confidence("high"),
    dimensions: [f32(dist2(wall.a, wall.b)), f32(wall.heightM), 0],
    transform: transformOf(
      [dx, 0, dz],
      [0, 1, 0],
      [-dz, 0, dx],
      [mid[0], FLOOR_Y + wall.heightM / 2, mid[1]],
    ),
    completedEdges: [],
    story: 0,
    curve: null,
    parentIdentifier: null,
    polygonCorners: [],
  };
}

function openingSurface(opening: LayoutOpening, wall: LayoutWall): Record<string, unknown> {
  const [ux, uz] = along(wall);
  const [dx, , dz] = turn(ux, uz);
  const centre = toCapture([wall.a[0] + ux * opening.offsetM, wall.a[1] + uz * opening.offsetM]);
  const category =
    opening.kind === "door"
      ? { door: { isOpen: opening.isOpen ?? false } }
      : opening.kind === "window"
        ? { window: {} }
        : { opening: {} };
  return {
    identifier: rawId(opening.id),
    parentIdentifier: rawId(wall.id),
    category,
    confidence: confidence(opening.confidence),
    dimensions: [f32(opening.widthM), f32(opening.heightM), 0],
    transform: transformOf(
      [dx, 0, dz],
      [0, 1, 0],
      [-dz, 0, dx],
      [centre[0], FLOOR_Y + opening.bottomM + opening.heightM / 2, centre[1]],
    ),
    completedEdges: [],
    story: 0,
    curve: null,
    polygonCorners: [],
  };
}

function floorSurface(): Record<string, unknown> {
  const xs = OUTLINE.map((p) => p[0]);
  const zs = OUTLINE.map((p) => p[1]);
  const cx = (Math.min(...xs) + Math.max(...xs)) / 2;
  const cz = (Math.min(...zs) + Math.max(...zs)) / 2;
  const centre = toCapture([cx, cz]);
  return {
    identifier: rawId("floor"),
    category: { floor: {} },
    confidence: confidence("high"),
    dimensions: [f32(Math.max(...xs) - Math.min(...xs)), f32(Math.max(...zs) - Math.min(...zs)), 0],
    // Local X = layout +X, local Y = layout -Z, local Z (the normal) = +Y, turned like the plan.
    transform: transformOf(turn(1, 0), turn(0, -1), [0, 1, 0], [centre[0], FLOOR_Y, centre[1]]),
    // Clockwise seen from +Y, as a device writes it (OUTLINE is counter-clockwise).
    polygonCorners: [...OUTLINE].reverse().map(([x, z]) => [f32(x - cx), f32(-(z - cz)), 0]),
    completedEdges: [],
    story: 0,
    curve: null,
    parentIdentifier: null,
  };
}

function objectJson(object: LayoutObject): Record<string, unknown> {
  const radians = ((object.yawDeg + YAW_DEG) * Math.PI) / 180;
  const c = Math.cos(radians);
  const s = Math.sin(radians);
  const at = toCapture(object.at);
  return {
    identifier: rawId(object.id),
    category: { [object.category]: {} },
    confidence: confidence(object.confidence),
    dimensions: object.sizeM.map(f32),
    transform: transformOf(
      [c, 0, -s],
      [0, 1, 0],
      [s, 0, c],
      [at[0], FLOOR_Y + object.centreY, at[1]],
    ),
    attributes: object.attributes,
    story: 0,
    parentIdentifier: object.parentId === undefined ? null : rawId(object.parentId),
  };
}

/** Same items in a fixed scrambled order: a device does not list walls or objects room by room. */
function scrambled<T>(items: readonly T[], seed: string): T[] {
  const random = mulberry32(seedFrom(`${WALKTHROUGH_NAME}:${seed}`));
  const out = [...items];
  for (let i = out.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1));
    [out[i], out[j]] = [out[j] as T, out[i] as T];
  }
  return out;
}

/** The rooms whose outline contains a layout point (never a point on a room boundary). */
function roomsAt(point: P2): LayoutRoom[] {
  return ROOMS.filter((room) => pointInPolygon(point, room.polygon));
}

function oneRoomAt(point: P2, what: string): LayoutRoom {
  const rooms = roomsAt(point);
  if (rooms.length !== 1) {
    throw new Error(`${what} is in ${rooms.length} rooms`);
  }
  return rooms[0] as LayoutRoom;
}

/** Ids of the rooms on either side of a stretch of wall, sampled 5 cm off the wall line. */
function roomsBeside(wall: LayoutWall, fractions: readonly number[]): string[] {
  const [ux, uz] = along(wall);
  const ids = new Set<string>();
  for (const t of fractions) {
    const x = wall.a[0] + (wall.b[0] - wall.a[0]) * t;
    const z = wall.a[1] + (wall.b[1] - wall.a[1]) * t;
    for (const side of [-0.05, 0.05]) {
      roomsAt([x - uz * side, z + ux * side]).forEach((room) => ids.add(room.id));
    }
  }
  return ROOMS.filter((room) => ids.has(room.id)).map((room) => room.id);
}

function distanceToSegment(point: P2, a: P2, b: P2): number {
  const dx = b[0] - a[0];
  const dz = b[1] - a[1];
  const t = Math.max(
    0,
    Math.min(1, ((point[0] - a[0]) * dx + (point[1] - a[1]) * dz) / (dx * dx + dz * dz)),
  );
  return dist2(point, [a[0] + dx * t, a[1] + dz * t]);
}

function onOutline(point: P2): boolean {
  return OUTLINE.some(
    (corner, i) => distanceToSegment(point, corner, OUTLINE[(i + 1) % OUTLINE.length] as P2) < 1e-9,
  );
}

function isOutlineWall(wall: LayoutWall): boolean {
  const mid: P2 = [(wall.a[0] + wall.b[0]) / 2, (wall.a[1] + wall.b[1]) / 2];
  return onOutline(wall.a) && onOutline(wall.b) && onOutline(mid);
}

/** Checks that the layout is what expected.json says it is; a typo here fails generation. */
function checkLayout(): void {
  if (shoelace(OUTLINE) >= 0 || ROOMS.some((room) => shoelace(room.polygon) >= 0)) {
    throw new Error("outlines must be counter-clockwise seen from +Y");
  }
  const roomArea = ROOMS.reduce((sum, room) => sum + polygonArea(room.polygon), 0);
  if (Math.abs(roomArea - polygonArea(OUTLINE)) > 1e-9) {
    throw new Error(`rooms cover ${roomArea} m2 of a ${polygonArea(OUTLINE)} m2 outline`);
  }
  const wallById = new Map(WALLS.map((w) => [w.id, w]));
  for (const opening of OPENINGS) {
    const host = wallById.get(opening.wallId);
    const half = opening.widthM / 2;
    if (
      host === undefined ||
      opening.offsetM - half < 0 ||
      opening.offsetM + half > dist2(host.a, host.b) ||
      opening.bottomM + opening.heightM > host.heightM
    ) {
      throw new Error(`${opening.id} does not fit its wall`);
    }
  }
}

/** The raw RoomPlan JSON and the expected.json value of the walk-through fixture. */
export function buildWalkthrough(): { roomPlan: unknown; expected: unknown } {
  checkLayout();
  const wallById = new Map(WALLS.map((w) => [w.id, w]));
  const walls = scrambled(WALLS, "walls");
  const objects = scrambled(OBJECTS, "objects");
  const kinds = ["door", "window", "opening"] as const;
  const openingsOf = (kind: (typeof kinds)[number]) =>
    OPENINGS.filter((opening) => opening.kind === kind);
  const surfacesOf = (kind: (typeof kinds)[number]) =>
    openingsOf(kind).map((opening) =>
      openingSurface(opening, wallById.get(opening.wallId) as LayoutWall),
    );
  const sectionAt = (section: LayoutSection): number[] => {
    const at = toCapture(section.at);
    return [f32(at[0]), f32(FLOOR_Y + SECTION_Y), f32(at[1])];
  };
  const referenceYaw = (REFERENCE_YAW_DEG * Math.PI) / 180;
  const rc = Math.cos(referenceYaw);
  const rs = Math.sin(referenceYaw);

  const roomPlan = {
    // A device export has no top-level identifier on a CapturedRoom.
    version: 2,
    story: 0,
    referenceOriginTransform: transformOf([rc, 0, -rs], [0, 1, 0], [rs, 0, rc], REFERENCE_OFFSET),
    walls: walls.map(wallSurface),
    doors: surfacesOf("door"),
    windows: surfacesOf("window"),
    openings: surfacesOf("opening"),
    floors: [floorSurface()],
    objects: objects.map(objectJson),
    sections: SECTIONS.map((section) => ({
      story: 0,
      label: section.label,
      center: sectionAt(section),
    })),
  };

  const capturePlan = (point: P2): number[] => toCapture(point).map(round6);
  const sectionRooms = SECTIONS.map((section, index) => ({
    index,
    label: section.label,
    roomId: oneRoomAt(section.at, `section ${index} (${section.label})`).id,
  }));
  const objectRooms = objects.map((object) => oneRoomAt(object.at, object.id).id);
  const outlineWalls = WALLS.filter(isOutlineWall);
  const perimeter = polygonPerimeter(OUTLINE);
  const withoutWall = perimeter - outlineWalls.reduce((sum, w) => sum + dist2(w.a, w.b), 0);
  const shortEnds = WALLS.filter((w) => w.short !== undefined).length;

  const expected = {
    fixture: WALKTHROUGH_NAME,
    description:
      "Synthetic whole-apartment walk-through scan as one CapturedRoom: a living room with an open kitchen, two bedrooms, a bathroom, a closet and a short hall.",
    roomPlan: "roomplan.json",
    frame: {
      note: "Plan points are [x, z] in metres in the capture frame of roomplan.json, at floor level y = floorY. The layout frame turned by yawDeg about +Y, with layoutOrigin under the capture origin, gives the capture frame.",
      floorY: FLOOR_Y,
      yawDeg: YAW_DEG,
      layoutOrigin: ORIGIN,
    },
    totals: {
      floorAreaM2: round6(polygonArea(OUTLINE)),
      outlineCorners: OUTLINE.length,
      outlinePerimeterM: round6(perimeter),
      outlineWithoutWallM: round6(withoutWall),
      outlineWithoutWallFraction: round6(withoutWall / perimeter),
      walls: WALLS.length,
      outlineWalls: outlineWalls.length,
      interiorWalls: WALLS.length - outlineWalls.length,
      shortInteriorWallEnds: shortEnds,
      doors: openingsOf("door").length,
      openDoors: openingsOf("door").filter((opening) => opening.isOpen === true).length,
      windows: openingsOf("window").length,
      openings: openingsOf("opening").length,
      objects: OBJECTS.length,
      sections: SECTIONS.length,
    },
    rooms: ROOMS.map((room) => {
      const section = sectionRooms.find((entry) => entry.roomId === room.id);
      return {
        id: room.id,
        label: room.label,
        type: room.type,
        areaM2: round6(polygonArea(room.polygon)),
        polygon: room.polygon.map(capturePlan),
        section: section === undefined ? null : { index: section.index, label: section.label },
        objects: objects.flatMap((object, index) =>
          objectRooms[index] === room.id
            ? [{ index, identifier: rawId(object.id), category: object.category }]
            : [],
        ),
      };
    }),
    sections: sectionRooms,
    walls: walls.map((w, index) => ({
      index,
      identifier: rawId(w.id),
      kind: isOutlineWall(w) ? "outline" : "interior",
      roomIds: roomsBeside(w, [0.1, 0.3, 0.5, 0.7, 0.9]),
      shortEnds:
        w.short === undefined
          ? []
          : [
              {
                end: w.short.end,
                junction: capturePlan(w.short.junction),
                shortByM: round6(dist2(w.short.end === "start" ? w.a : w.b, w.short.junction)),
              },
            ],
    })),
    openings: kinds.flatMap((kind) =>
      openingsOf(kind).map((opening, index) => {
        const host = wallById.get(opening.wallId) as LayoutWall;
        const fraction = opening.offsetM / dist2(host.a, host.b);
        return {
          kind,
          index,
          identifier: rawId(opening.id),
          wallIdentifier: rawId(host.id),
          ...(opening.isOpen === undefined ? {} : { isOpen: opening.isOpen }),
          roomIds: roomsBeside(host, [fraction]),
        };
      }),
    ),
  };
  return { roomPlan, expected };
}
