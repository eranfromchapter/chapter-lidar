// The four synthetic shapes. All dimensions are exact decimals in metres.

import type {
  CaptureSpec,
  FixtureSpec,
  FrameSpec,
  OpeningSpec,
  RoomSpec,
  WallSpec,
} from "./spec.js";

const IDENTITY: FrameSpec = { rotYDeg: 0, translate: [0, 0, 0] };

const DOOR_W = 0.9;
const DOOR_H = 2.1;
const WIN_W = 1.2;
const WIN_H = 1.2;
const WIN_SILL = 0.9;

function door(id: string, wallId: string, offsetM: number, label: string): OpeningSpec {
  return { id, kind: "door", wallId, offsetM, bottomM: 0, widthM: DOOR_W, heightM: DOOR_H, label };
}

function windowAt(
  id: string,
  wallId: string,
  offsetM: number,
  label: string,
  widthM = WIN_W,
): OpeningSpec {
  return {
    id,
    kind: "window",
    wallId,
    offsetM,
    bottomM: WIN_SILL,
    widthM,
    heightM: WIN_H,
    label,
  };
}

function walls(
  heightM: number,
  roomIds: string[],
  edges: ReadonlyArray<readonly [string, [number, number], [number, number]]>,
): WallSpec[] {
  return edges.map(([id, a, b]) => ({ id, a, b, heightM, roomIds }));
}

function boxRoom(): FixtureSpec {
  const room: RoomSpec = {
    id: "room-1",
    label: "Test Room",
    polygon: [
      [0, 0],
      [0, 3],
      [4, 3],
      [4, 0],
    ],
    heightM: 2.7,
  };
  const capture: CaptureSpec = {
    areaKey: "floor-1",
    label: "Floor 1",
    mode: "room",
    frame: IDENTITY,
    rooms: [room],
    walls: walls(
      2.7,
      ["room-1"],
      [
        ["wall-1", [0, 0], [0, 3]],
        ["wall-2", [0, 3], [4, 3]],
        ["wall-3", [4, 3], [4, 0]],
        ["wall-4", [4, 0], [0, 0]],
      ],
    ),
    openings: [
      door("door-1", "wall-4", 3.0, "Entry door"),
      windowAt("window-1", "wall-2", 2.0, "South window"),
    ],
    objects: [
      {
        id: "object-1",
        category: "table",
        roomId: "room-1",
        center: [2, 0.375, 1.5],
        sizeM: [1.2, 0.75, 0.8],
        rotYDeg: 0,
      },
    ],
    distances: [
      { axis: "A", from: "Test Room west wall", to: "Test Room east wall", lengthM: 4 },
      { axis: "B", from: "Test Room north wall", to: "Test Room south wall", lengthM: 3 },
    ],
    coverageNotes: "",
  };
  return {
    name: "box-room",
    description: "Box room 4.000 x 3.000 m, ceiling 2.700 m, one door and one window.",
    captures: [capture],
    landmarks: [],
  };
}

function lShapedRoom(): FixtureSpec {
  const room: RoomSpec = {
    id: "room-1",
    label: "L Room",
    polygon: [
      [0, 0],
      [0, 4],
      [3, 4],
      [3, 2],
      [6, 2],
      [6, 0],
    ],
    heightM: 2.7,
  };
  const capture: CaptureSpec = {
    areaKey: "floor-1",
    label: "Floor 1",
    mode: "room",
    frame: IDENTITY,
    rooms: [room],
    walls: walls(
      2.7,
      ["room-1"],
      [
        ["wall-1", [0, 0], [0, 4]],
        ["wall-2", [0, 4], [3, 4]],
        ["wall-3", [3, 4], [3, 2]],
        ["wall-4", [3, 2], [6, 2]],
        ["wall-5", [6, 2], [6, 0]],
        ["wall-6", [6, 0], [0, 0]],
      ],
    ),
    openings: [
      door("door-1", "wall-6", 1.0, "Entry door"),
      windowAt("window-1", "wall-1", 2.0, "West window"),
      windowAt("window-2", "wall-4", 1.5, "South window"),
      {
        id: "opening-1",
        kind: "opening",
        wallId: "wall-5",
        offsetM: 1.0,
        bottomM: 0,
        widthM: 1.0,
        heightM: 2.1,
        label: "East passage",
      },
    ],
    objects: [],
    distances: [
      { axis: "A", from: "L Room west wall", to: "L Room east wall", lengthM: 6 },
      { axis: "B", from: "L Room north wall", to: "L Room south wall", lengthM: 4 },
    ],
    coverageNotes: "",
  };
  return {
    name: "l-shaped-room",
    description:
      "L-shaped room, 6.000 x 4.000 m outline with a 3.000 x 2.000 m corner removed, ceiling 2.700 m.",
    captures: [capture],
    landmarks: [],
  };
}

function twoRoomApartment(): FixtureSpec {
  const living: RoomSpec = {
    id: "room-1",
    label: "Living Room",
    polygon: [
      [0, 0],
      [0, 4],
      [5, 4],
      [5, 0],
    ],
    heightM: 2.7,
  };
  const bedroom: RoomSpec = {
    id: "room-2",
    label: "Bedroom",
    polygon: [
      [5, 0],
      [5, 4],
      [8, 4],
      [8, 0],
    ],
    heightM: 2.7,
  };
  // Like a RoomPlan structure, each room has its own wall surfaces; the partition between the
  // rooms is listed once per room (wall-3 and wall-5), at the same place.
  const capture: CaptureSpec = {
    areaKey: "floor-1",
    label: "Floor 1",
    mode: "floor",
    frame: IDENTITY,
    rooms: [living, bedroom],
    walls: [
      ...walls(
        2.7,
        ["room-1"],
        [
          ["wall-1", [0, 0], [0, 4]],
          ["wall-2", [0, 4], [5, 4]],
          ["wall-3", [5, 4], [5, 0]],
          ["wall-4", [5, 0], [0, 0]],
        ],
      ),
      ...walls(
        2.7,
        ["room-2"],
        [
          ["wall-5", [5, 0], [5, 4]],
          ["wall-6", [5, 4], [8, 4]],
          ["wall-7", [8, 4], [8, 0]],
          ["wall-8", [8, 0], [5, 0]],
        ],
      ),
    ],
    openings: [
      door("door-1", "wall-3", 1.0, "Bedroom door"),
      windowAt("window-1", "wall-1", 2.0, "Living window", 1.5),
      windowAt("window-2", "wall-7", 2.0, "Bedroom window"),
      // A passage without a door, so the plan has content on every plan layer.
      {
        id: "opening-1",
        kind: "opening",
        wallId: "wall-4",
        offsetM: 1.5,
        bottomM: 0,
        widthM: 1.0,
        heightM: 2.1,
        label: "Hall passage",
      },
    ],
    objects: [
      {
        id: "object-1",
        category: "sofa",
        roomId: "room-1",
        center: [2.5, 0.4, 3.2],
        sizeM: [2.0, 0.8, 0.9],
        rotYDeg: 0,
      },
      {
        id: "object-2",
        category: "bed",
        roomId: "room-2",
        center: [6.8, 0.25, 2.0],
        sizeM: [1.6, 0.5, 2.0],
        rotYDeg: 90,
      },
    ],
    distances: [
      { axis: "A", from: "Living Room west wall", to: "Bedroom east wall", lengthM: 8 },
      { axis: "B", from: "Living Room north wall", to: "Living Room south wall", lengthM: 4 },
    ],
    coverageNotes: "",
  };
  return {
    name: "two-room-apartment",
    description:
      "Two-room apartment: Living Room 5.000 x 4.000 m and Bedroom 3.000 x 4.000 m, ceiling 2.700 m, one door between the rooms, two windows and one passage opening.",
    captures: [capture],
    landmarks: [],
  };
}

function twoFloorHouse(): FixtureSpec {
  const floor1Room: RoomSpec = {
    id: "room-1",
    label: "Living Room",
    polygon: [
      [0, 0],
      [0, 5],
      [6, 5],
      [6, 0],
    ],
    heightM: 2.7,
  };
  // Floor 2 has the same 6 x 5 m envelope. The stair void is a 1.000 x 3.000 m corner notch
  // (x 0..1, z 0..3 in the house frame) cut out of the floor, so the room is L-shaped.
  const floor2Room: RoomSpec = {
    id: "room-1",
    label: "Upper Hall",
    polygon: [
      [0, 3],
      [0, 5],
      [6, 5],
      [6, 0],
      [1, 0],
      [1, 3],
    ],
    heightM: 2.5,
  };
  const floor1: CaptureSpec = {
    areaKey: "floor-1",
    label: "Floor 1",
    mode: "floor",
    frame: IDENTITY,
    rooms: [floor1Room],
    walls: walls(
      2.7,
      ["room-1"],
      [
        ["wall-1", [0, 0], [0, 5]],
        ["wall-2", [0, 5], [6, 5]],
        ["wall-3", [6, 5], [6, 0]],
        ["wall-4", [6, 0], [0, 0]],
      ],
    ),
    openings: [
      door("door-1", "wall-2", 4.5, "Entry door"),
      windowAt("window-1", "wall-3", 2.5, "East window"),
    ],
    objects: [
      {
        id: "object-1",
        category: "stairs",
        roomId: "room-1",
        center: [0.5, 1.35, 1.5],
        sizeM: [1.0, 2.7, 3.0],
        rotYDeg: 0,
      },
    ],
    distances: [
      { axis: "A", from: "Living Room west wall", to: "Living Room east wall", lengthM: 6 },
      { axis: "B", from: "Living Room north wall", to: "Living Room south wall", lengthM: 5 },
    ],
    coverageNotes: "",
  };
  // Floor 2 is captured in its own frame: turned 90 degrees about Y and moved. Nothing in the
  // capture model relates it to floor 1; only the landmarks and the floor-to-floor level do.
  const floor2: CaptureSpec = {
    areaKey: "floor-2",
    label: "Floor 2",
    mode: "floor",
    frame: { rotYDeg: 90, translate: [0.35, 0, 6.25] },
    rooms: [floor2Room],
    walls: walls(
      2.5,
      ["room-1"],
      [
        ["wall-1", [0, 0], [0, 5]],
        ["wall-2", [0, 5], [6, 5]],
        ["wall-3", [6, 5], [6, 0]],
        ["wall-4", [6, 0], [0, 0]],
      ],
    ),
    openings: [
      windowAt("window-1", "wall-3", 2.5, "East window"),
      windowAt("window-2", "wall-2", 3.0, "South window"),
    ],
    objects: [],
    distances: [
      { axis: "A", from: "Upper Hall north wall", to: "Upper Hall south wall", lengthM: 6 },
      { axis: "B", from: "Upper Hall west wall", to: "Upper Hall east wall", lengthM: 5 },
    ],
    coverageNotes: "The stair void is open: no wall or rail was captured along its edge.",
  };
  return {
    name: "two-floor-house",
    description:
      "Two-floor house, one visit and two captures. Floor 1 Living Room 6.000 x 5.000 m, ceiling 2.700 m. Floor 2 Upper Hall with a 1.000 x 3.000 m stair void, ceiling 2.500 m. Floor-to-floor 2.950 m. Floor 2 is captured in a rotated and moved frame; two shared landmarks.",
    captures: [floor1, floor2],
    floorToFloor: {
      lowerAreaKey: "floor-1",
      upperAreaKey: "floor-2",
      location: "At stair",
      valueM: 2.95,
    },
    landmarks: [
      {
        id: "landmark-newel",
        label: "Stair newel post",
        description: "Top of the newel post at the foot of the stair.",
        position: [1.05, 1.1, 3.05],
        areaKeys: ["floor-1", "floor-2"],
      },
      {
        id: "landmark-column",
        label: "North-east column",
        description: "Square structural column in the north-east corner.",
        position: [5.8, 1.2, 0.2],
        areaKeys: ["floor-1", "floor-2"],
      },
    ],
    stairVoid: { floorAreaKey: "floor-2", minX: 0, maxX: 1, minZ: 0, maxZ: 3 },
  };
}

/** The four good fixtures in a fixed order. */
export function fixtureSpecs(): FixtureSpec[] {
  return [boxRoom(), lShapedRoom(), twoRoomApartment(), twoFloorHouse()];
}
