// Declarative description of a synthetic fixture. Everything is written in one "house frame"
// (metres, +Y up, plan coordinates x and z). Each capture has its own frame: a rotation about Y
// and a translation, so floors of one visit are deliberately not aligned with each other.

import type { P2, V3 } from "./util.js";

export type OpeningKind = "door" | "window" | "opening";
export type CaptureModeName = "room" | "floor" | "exterior";
export type ObjectCategory = "bed" | "sofa" | "stairs" | "table";

export interface RoomSpec {
  id: string;
  label: string;
  /** Floor outline, counter-clockwise seen from +Y (negative shoelace sum in x, z). */
  polygon: P2[];
  heightM: number;
}

export interface WallSpec {
  id: string;
  a: P2;
  b: P2;
  heightM: number;
  roomIds: string[];
}

export interface OpeningSpec {
  id: string;
  kind: OpeningKind;
  wallId: string;
  /** Distance along the wall from its start to the centre of the opening. */
  offsetM: number;
  bottomM: number;
  widthM: number;
  heightM: number;
  /** Label used for the field-control opening entry, for example "Entry door". */
  label: string;
}

export interface ObjectSpec {
  id: string;
  category: ObjectCategory;
  roomId: string;
  center: V3;
  sizeM: V3;
  /** Rotation about +Y, degrees (multiples of 90 only). */
  rotYDeg: number;
}

export interface DistanceSpec {
  axis: "A" | "B";
  from: string;
  to: string;
  /** True length in metres, along the capture's long perpendicular axes. */
  lengthM: number;
}

export interface FrameSpec {
  /** Rotation about +Y in degrees, multiple of 90. Maps house frame to capture frame. */
  rotYDeg: 0 | 90 | 180 | 270;
  translate: V3;
}

export interface CaptureSpec {
  areaKey: string;
  label: string;
  mode: CaptureModeName;
  frame: FrameSpec;
  rooms: RoomSpec[];
  walls: WallSpec[];
  openings: OpeningSpec[];
  objects: ObjectSpec[];
  distances: DistanceSpec[];
  coverageNotes: string;
}

export interface LandmarkSpec {
  id: string;
  label: string;
  description: string;
  /** Position in the house frame, metres. */
  position: V3;
  /** areaKeys of the captures it is visible in. */
  areaKeys: string[];
}

export interface FixtureSpec {
  /** Folder name under fixtures/generated. */
  name: string;
  description: string;
  captures: CaptureSpec[];
  /** Floor-to-floor level between two captures. */
  floorToFloor?: { lowerAreaKey: string; upperAreaKey: string; location: string; valueM: number };
  landmarks: LandmarkSpec[];
  /** Stair void rectangle in the house frame, when the fixture has one. */
  stairVoid?: { floorAreaKey: string; minX: number; maxX: number; minZ: number; maxZ: number };
}

/** Placeholder address, the same for every fixture. Not a real address. */
export const PLACEHOLDER_ADDRESS = "100 Example Street, Testville, NY 00000";
/** A second placeholder, used only by the wrong-address broken fixture. */
export const OTHER_PLACEHOLDER_ADDRESS = "200 Sample Avenue, Testville, NY 00000";
export const DEAL_ID = "fixture-deal-0001";
export const OPERATOR_NAME = "Test Operator";
