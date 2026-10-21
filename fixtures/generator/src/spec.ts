// Declarative description of a synthetic fixture. Everything is written in one "house frame"
// (metres, +Y up, plan coordinates x and z). Each capture has its own frame: a rotation about Y
// and a translation, so floors of one visit are deliberately not aligned with each other.

import type { P2, V3 } from "./util.js";

export type OpeningKind = "door" | "window" | "opening";
export type CaptureModeName = "room" | "floor" | "exterior";
export type ObjectCategory =
  "bathtub" | "bed" | "sink" | "sofa" | "stairs" | "storage" | "stove" | "table" | "toilet";

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

/**
 * The compass reading recorded at the start of the capture's scan (capture record 1.1.0):
 * a reading taken `offsetSeconds` after capturedAt, or the issue that left none.
 */
export type CompassSpec =
  | { heading: number; accuracy: number; source: "true" | "magnetic"; offsetSeconds: number }
  | { issue: "rejected" | "not_calibrated" | "unavailable" };

/** Labels of one site photo; the room and the file come from the capture. */
export interface PhotoSpec {
  direction: "N" | "E" | "S" | "W";
  subject: "opening" | "cabinetry" | "ceiling" | "fixture" | "equipment" | "defect" | "general";
  /** How the direction was set (manifest 1.1.0); omitted when absent. */
  directionSource?: "compass" | "manual";
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
  /** Units shown to the operator; metric when absent. */
  display?: "metric" | "imperial";
  /** Compass reading of the scan; a capture without one records no compass fields. */
  compass?: CompassSpec;
  /** Rooms the operator chose not to scan. */
  omittedRooms?: Array<{ name: string; reason?: string }>;
  /** Rooms that could not be entered. */
  inaccessibleRooms?: Array<{ name: string; reason?: string }>;
  /**
   * Site photos per room id, in order. A room not listed gets one photo looking north, subject
   * general.
   */
  photos?: Record<string, PhotoSpec[]>;
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
  /**
   * A package as an app build before v2 sealed it: manifest 1.0.0, the plan PDF named plan.pdf
   * and the phone's spatial report (role spatial_report_pdf, retired in manifest 1.1.0).
   */
  legacy?: boolean;
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
