// sample-424: the apartment of the design artboards (plan sheet 1b, spatial report 1f-1aa) as an
// intake package, so the plan sheet and the spatial report can be compared with the drawings.
//
// Geometry is the design bundle's trace of the 424 sample (canvas/apartment-424.js): trace units
// of about 19.4 per foot, drawn with y down. Here x = (u - 30) * k and z = (v - 151) * k with
// k = 0.3048 / 19.4 m per unit, rounded to the millimetre, so plan up (-Z) is page up as drawn.
// Walls are the room outlines at thickness 0 (one wall per room edge, partitions once per room,
// as RoomPlan lists them); doors, passages and windows sit on the wall of the room named here.
// Close to the sample, not exact. Text data stays placeholder data (address, deal, operator).

import type {
  CaptureSpec,
  FixtureSpec,
  ObjectSpec,
  OpeningSpec,
  PhotoSpec,
  RoomSpec,
  WallSpec,
} from "./spec.js";
import { round6, type P2 } from "./util.js";

export const SAMPLE_424_NAME = "sample-424";

/** Metres per trace unit (19.4 trace units per foot). */
const METRES_PER_UNIT = 0.3048 / 19.4;
const ORIGIN_U = 30;
const ORIGIN_V = 151;

function mm(value: number): number {
  return round6(Math.round(value * 1000) / 1000);
}

function at(u: number, v: number): P2 {
  return [mm((u - ORIGIN_U) * METRES_PER_UNIT), mm((v - ORIGIN_V) * METRES_PER_UNIT)];
}

function length(units: number): number {
  return mm(units * METRES_PER_UNIT);
}

interface TraceRoom {
  key: string;
  label: string;
  /** Outline in trace units, as drawn (clockwise seen from +Y once z = v). */
  points: Array<[number, number]>;
  /** Ceiling height in metres, from the sample's room table. */
  heightM: number;
}

// Rooms in the trace's order; ceilings from the sample (8' 1.8" = 2.484 m and so on).
const ROOMS: TraceRoom[] = [
  {
    key: "bed1",
    label: "Bedroom 1",
    heightM: 2.504,
    points: [
      [48, 151],
      [232, 151],
      [232, 193],
      [258, 193],
      [258, 465],
      [188, 465],
      [188, 548],
      [125, 548],
      [125, 471],
      [48, 471],
    ],
  },
  {
    key: "closet",
    label: "Closet",
    heightM: 2.487,
    points: [
      [190, 471],
      [258, 471],
      [258, 548],
      [190, 548],
    ],
  },
  {
    key: "living",
    label: "Living Room",
    heightM: 2.484,
    points: [
      [266, 166],
      [488, 166],
      [488, 548],
      [266, 548],
    ],
  },
  {
    key: "room2",
    label: "Room 2",
    heightM: 2.474,
    points: [
      [496, 151],
      [556, 151],
      [556, 495],
      [496, 495],
    ],
  },
  {
    key: "bed2",
    label: "Bedroom 2",
    heightM: 2.474,
    points: [
      [564, 151],
      [698, 151],
      [698, 385],
      [564, 385],
    ],
  },
  {
    key: "room4",
    label: "Room 4",
    heightM: 2.474,
    points: [
      [566, 392],
      [698, 392],
      [698, 432],
      [566, 432],
    ],
  },
  {
    key: "bath2",
    label: "Bathroom 2",
    heightM: 2.449,
    points: [
      [566, 440],
      [700, 440],
      [700, 532],
      [566, 532],
    ],
  },
  {
    key: "bath1",
    label: "Bathroom 1",
    heightM: 2.479,
    points: [
      [30, 556],
      [118, 556],
      [118, 690],
      [30, 690],
    ],
  },
  {
    key: "room5",
    label: "Room 5",
    heightM: 2.464,
    points: [
      [125, 612],
      [170, 612],
      [170, 686],
      [125, 686],
    ],
  },
  {
    key: "room1",
    label: "Room 1",
    heightM: 2.504,
    points: [
      [125, 556],
      [320, 556],
      [320, 683],
      [178, 683],
      [178, 606],
      [125, 606],
    ],
  },
  {
    key: "kitchen",
    label: "Kitchen",
    heightM: 2.525,
    points: [
      [328, 550],
      [455, 550],
      [455, 683],
      [328, 683],
    ],
  },
  {
    key: "room3",
    label: "Room 3",
    heightM: 2.51,
    points: [
      [462, 580],
      [490, 548],
      [496, 495],
      [560, 495],
      [560, 688],
      [462, 688],
    ],
  },
];

/**
 * Room 4's ceiling was partly captured: its long south wall (from (566, 432), counter-clockwise)
 * reads lower than the others, so the room's ceiling height is approximate.
 */
const LOW_WALL = { room: "room4", from: [566, 432] as [number, number], heightM: 2.3 };

const DOOR_H = 2.1;
/**
 * Narrowest door. The trace marks some doors with short thresholds (0.30 to 0.44 m); those are
 * widened about their centre, so the doors are plausible (the station flags doors under 0.6 m).
 */
const MIN_DOOR_W = 0.7;
const WINDOW_SILL = 0.7;
const WINDOW_H = 1.6;

interface TraceOpening {
  id: string;
  kind: OpeningSpec["kind"];
  room: string;
  /** Ends of the threshold or window in trace units. */
  ends: [[number, number], [number, number]];
  label: string;
}

// The trace's two windows and twelve thresholds (door: swing not recorded; pass: open passage).
const OPENINGS: TraceOpening[] = [
  {
    id: "window-1",
    kind: "window",
    room: "bed1",
    ends: [
      [90, 151],
      [215, 151],
    ],
    label: "Bedroom 1 window",
  },
  {
    id: "window-2",
    kind: "window",
    room: "living",
    ends: [
      [292, 166],
      [410, 166],
    ],
    label: "Living Room window",
  },
  {
    id: "door-1",
    kind: "door",
    room: "living",
    ends: [
      [420, 166],
      [466, 166],
    ],
    label: "Entry door",
  },
  {
    id: "opening-1",
    kind: "opening",
    room: "living",
    ends: [
      [488, 431],
      [488, 495],
    ],
    label: "Living Room to Room 2 passage",
  },
  {
    id: "opening-2",
    kind: "opening",
    room: "living",
    ends: [
      [266, 548],
      [320, 548],
    ],
    label: "Living Room to Room 1 passage",
  },
  {
    id: "door-2",
    kind: "door",
    room: "closet",
    ends: [
      [190, 493],
      [190, 512],
    ],
    label: "Closet door",
  },
  {
    id: "door-3",
    kind: "door",
    room: "bed1",
    ends: [
      [48, 358],
      [48, 378],
    ],
    label: "Bedroom 1 door",
  },
  {
    id: "door-4",
    kind: "door",
    room: "bath2",
    ends: [
      [566, 472],
      [566, 500],
    ],
    label: "Bathroom 2 door",
  },
  {
    id: "door-5",
    kind: "door",
    room: "bath1",
    ends: [
      [118, 605],
      [118, 625],
    ],
    label: "Bathroom 1 door",
  },
  {
    id: "opening-3",
    kind: "opening",
    room: "kitchen",
    ends: [
      [328, 595],
      [328, 640],
    ],
    label: "Kitchen passage",
  },
  {
    id: "door-6",
    kind: "door",
    room: "kitchen",
    ends: [
      [455, 600],
      [455, 628],
    ],
    label: "Kitchen door",
  },
  {
    id: "door-7",
    kind: "door",
    room: "bed2",
    ends: [
      [640, 385],
      [685, 385],
    ],
    label: "Bedroom 2 door",
  },
  {
    id: "opening-4",
    kind: "opening",
    room: "room4",
    ends: [
      [566, 392],
      [566, 432],
    ],
    label: "Room 4 passage",
  },
  {
    id: "door-8",
    kind: "door",
    room: "room1",
    ends: [
      [258, 683],
      [312, 683],
    ],
    label: "Room 1 door",
  },
];

interface TraceObject {
  category: ObjectSpec["category"];
  room: string;
  /** Box in trace units: left, top, width, depth. */
  box: [number, number, number, number];
  heightM: number;
}

// The trace's fourteen objects; generic boxes named by where they stand.
const OBJECTS: TraceObject[] = [
  { category: "bed", room: "bed1", box: [112, 208, 145, 125], heightM: 0.6 },
  { category: "sofa", room: "living", box: [290, 178, 125, 62], heightM: 0.85 },
  { category: "sofa", room: "living", box: [435, 285, 52, 125], heightM: 0.85 },
  { category: "table", room: "living", box: [380, 320, 52, 80], heightM: 0.45 },
  { category: "bed", room: "bed2", box: [618, 166, 75, 125], heightM: 0.6 },
  { category: "storage", room: "room2", box: [507, 175, 46, 122], heightM: 2 },
  { category: "bathtub", room: "bath2", box: [668, 442, 30, 85], heightM: 0.55 },
  { category: "bathtub", room: "bath1", box: [35, 662, 80, 25], heightM: 0.55 },
  { category: "stove", room: "kitchen", box: [345, 640, 55, 42], heightM: 0.9 },
  { category: "sink", room: "kitchen", box: [420, 556, 30, 26], heightM: 0.9 },
  { category: "storage", room: "bed1", box: [205, 365, 48, 70], heightM: 1.2 },
  { category: "storage", room: "bed1", box: [55, 215, 22, 110], heightM: 1.8 },
  { category: "table", room: "bed1", box: [55, 372, 45, 40], heightM: 0.6 },
  { category: "toilet", room: "bath2", box: [574, 498, 20, 28], heightM: 0.75 },
];

// Seven living-room photos (the photo page of the report); every other room has one.
const LIVING_PHOTOS: PhotoSpec[] = [
  { direction: "N", subject: "general", directionSource: "compass" },
  { direction: "E", subject: "opening", directionSource: "compass" },
  { direction: "S", subject: "general", directionSource: "manual" },
  { direction: "W", subject: "ceiling", directionSource: "manual" },
  { direction: "N", subject: "opening", directionSource: "compass" },
  { direction: "E", subject: "fixture", directionSource: "compass" },
  { direction: "S", subject: "defect", directionSource: "manual" },
];

function roomId(key: string): string {
  return `room-${ROOMS.findIndex((room) => room.key === key) + 1}`;
}

function sameUnits(a: [number, number], b: [number, number]): boolean {
  return a[0] === b[0] && a[1] === b[1];
}

export function sample424(): FixtureSpec {
  const rooms: RoomSpec[] = [];
  const walls: WallSpec[] = [];
  const wallsOfRoom = new Map<
    string,
    Array<{ wall: WallSpec; a: [number, number]; b: [number, number] }>
  >();
  for (const room of ROOMS) {
    const id = roomId(room.key);
    // The trace is clockwise seen from +Y; the contract wants counter-clockwise.
    const points = [...room.points].reverse();
    rooms.push({
      id,
      label: room.label,
      polygon: points.map(([u, v]) => at(u, v)),
      heightM: room.heightM,
    });
    const own: Array<{ wall: WallSpec; a: [number, number]; b: [number, number] }> = [];
    points.forEach((a, index) => {
      const b = points[(index + 1) % points.length] as [number, number];
      const low = room.key === LOW_WALL.room && sameUnits(a, LOW_WALL.from);
      const wall: WallSpec = {
        id: `wall-${walls.length + 1}`,
        a: at(a[0], a[1]),
        b: at(b[0], b[1]),
        heightM: low ? LOW_WALL.heightM : room.heightM,
        roomIds: [id],
      };
      walls.push(wall);
      own.push({ wall, a, b });
    });
    wallsOfRoom.set(room.key, own);
  }

  const openings: OpeningSpec[] = OPENINGS.map((opening) => {
    const [p, q] = opening.ends;
    // The room's wall the opening lies on: both ends on the wall's line, within its span.
    const host = (wallsOfRoom.get(opening.room) ?? []).find(({ a, b }) => {
      const along = (point: [number, number]) =>
        ((point[0] - a[0]) * (b[0] - a[0]) + (point[1] - a[1]) * (b[1] - a[1])) /
        ((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2);
      const off = (point: [number, number]) =>
        Math.abs((point[0] - a[0]) * (b[1] - a[1]) - (point[1] - a[1]) * (b[0] - a[0]));
      return [p, q].every((point) => off(point) < 1e-9 && along(point) >= 0 && along(point) <= 1);
    });
    if (host === undefined) {
      throw new Error(`${opening.id} lies on no wall of ${opening.room}`);
    }
    const { a } = host;
    const distance = (point: [number, number]) => Math.hypot(point[0] - a[0], point[1] - a[1]);
    const window = opening.kind === "window";
    const traced = length(Math.abs(distance(q) - distance(p)));
    return {
      id: opening.id,
      kind: opening.kind,
      wallId: host.wall.id,
      offsetM: length((distance(p) + distance(q)) / 2),
      bottomM: window ? WINDOW_SILL : 0,
      widthM: opening.kind === "door" ? Math.max(traced, MIN_DOOR_W) : traced,
      heightM: window ? WINDOW_H : DOOR_H,
      label: opening.label,
    };
  });

  const objects: ObjectSpec[] = OBJECTS.map((object, index) => {
    const [u, v, w, d] = object.box;
    const [x, z] = at(u + w / 2, v + d / 2);
    return {
      id: `object-${index + 1}`,
      category: object.category,
      roomId: roomId(object.room),
      center: [x, round6(object.heightM / 2), z],
      sizeM: [length(w), object.heightM, length(d)],
      rotYDeg: 0,
    };
  });

  // Field-control distances A and B: the Living Room's extents, as the model holds them.
  const living = rooms[ROOMS.findIndex((room) => room.key === "living")] as RoomSpec;
  const xs = living.polygon.map(([x]) => x);
  const zs = living.polygon.map(([, z]) => z);
  const capture: CaptureSpec = {
    areaKey: "floor-1",
    label: "Floor 1",
    mode: "floor",
    frame: { rotYDeg: 0, translate: [0, 0, 0] },
    rooms,
    walls,
    openings,
    objects,
    distances: [
      {
        axis: "A",
        from: "Living Room west wall",
        to: "Living Room east wall",
        lengthM: round6(Math.max(...xs) - Math.min(...xs)),
      },
      {
        axis: "B",
        from: "Living Room north wall",
        to: "Living Room south wall",
        lengthM: round6(Math.max(...zs) - Math.min(...zs)),
      },
    ],
    coverageNotes: "Room 4: the ceiling was only partly captured.",
    display: "imperial",
    compass: { heading: 212.4, accuracy: 8, source: "true", offsetSeconds: 9 },
    omittedRooms: [{ name: "Primary closet", reason: "locked" }],
    inaccessibleRooms: [{ name: "Storage room" }],
    photos: { [roomId("living")]: LIVING_PHOTOS },
  };
  return {
    name: SAMPLE_424_NAME,
    description:
      "The 424 sample apartment of the design artboards, traced: one floor, 12 rooms (5 unlabeled Room N), 14 objects, 8 doors, 4 passages, 2 windows; Primary closet not scanned (locked), Storage room could not be entered; 7 photos of the Living Room, one of every other room; compass verified (212.4°, ±8°, true north).",
    captures: [capture],
    landmarks: [],
  };
}
