// Frames, polygons and the CaptureModel builder.

import type { CaptureModel } from "@chapter/capture-contract";
import type { CaptureSpec, FrameSpec, ObjectSpec } from "./spec.js";
import { atLeast, round6, type P2, type V3 } from "./util.js";

const COS: Record<number, number> = { 0: 1, 90: 0, 180: -1, 270: 0 };
const SIN: Record<number, number> = { 0: 0, 90: 1, 180: 0, 270: -1 };

/** Maps a house-frame point into a capture's own frame: rotate about +Y, then translate. */
export function toLocal(frame: FrameSpec, point: V3): V3 {
  const cos = COS[frame.rotYDeg] ?? 1;
  const sin = SIN[frame.rotYDeg] ?? 0;
  const [x, y, z] = point;
  return [
    round6(x * cos + z * sin + frame.translate[0]),
    round6(y + frame.translate[1]),
    round6(-x * sin + z * cos + frame.translate[2]),
  ];
}

/** Maps a capture-frame point back into the house frame. */
export function toHouse(frame: FrameSpec, point: V3): V3 {
  const cos = COS[frame.rotYDeg] ?? 1;
  const sin = SIN[frame.rotYDeg] ?? 0;
  const x = point[0] - frame.translate[0];
  const y = point[1] - frame.translate[1];
  const z = point[2] - frame.translate[2];
  return [round6(x * cos - z * sin), round6(y), round6(x * sin + z * cos)];
}

export function rotationQuaternionY(deg: number): [number, number, number, number] {
  const half = (deg * Math.PI) / 360;
  return [0, round6(Math.sin(half)), 0, round6(Math.cos(half))];
}

/** Signed shoelace sum of a plan polygon in (x, z). Negative means counter-clockwise from +Y. */
export function shoelace(polygon: readonly P2[]): number {
  let sum = 0;
  for (let i = 0; i < polygon.length; i += 1) {
    const [x1, z1] = polygon[i] as P2;
    const [x2, z2] = polygon[(i + 1) % polygon.length] as P2;
    sum += x1 * z2 - x2 * z1;
  }
  return sum / 2;
}

export function polygonArea(polygon: readonly P2[]): number {
  return Math.abs(shoelace(polygon));
}

export function polygonPerimeter(polygon: readonly P2[]): number {
  let sum = 0;
  for (let i = 0; i < polygon.length; i += 1) {
    const [x1, z1] = polygon[i] as P2;
    const [x2, z2] = polygon[(i + 1) % polygon.length] as P2;
    sum += Math.hypot(x2 - x1, z2 - z1);
  }
  return sum;
}

export function pointInPolygon(point: P2, polygon: readonly P2[]): boolean {
  let inside = false;
  const [px, pz] = point;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i, i += 1) {
    const [xi, zi] = polygon[i] as P2;
    const [xj, zj] = polygon[j] as P2;
    if (zi > pz !== zj > pz && px < ((xj - xi) * (pz - zi)) / (zj - zi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

/** Local-frame polygon of a room, as 3D points at floor level (y = 0). */
export function localPolygon3(capture: CaptureSpec, polygon: readonly P2[]): V3[] {
  return polygon.map(([x, z]) => toLocal(capture.frame, [x, 0, z]));
}

export function localPolygon2(capture: CaptureSpec, polygon: readonly P2[]): P2[] {
  return localPolygon3(capture, polygon).map(([x, , z]) => [x, z] as P2);
}

export interface LocalWall {
  id: string;
  start: V3;
  end: V3;
  heightM: number;
  roomIds: string[];
  lengthM: number;
}

export function localWalls(capture: CaptureSpec): LocalWall[] {
  return capture.walls.map((wall) => {
    const start = toLocal(capture.frame, [wall.a[0], 0, wall.a[1]]);
    const end = toLocal(capture.frame, [wall.b[0], 0, wall.b[1]]);
    return {
      id: wall.id,
      start,
      end,
      heightM: wall.heightM,
      roomIds: wall.roomIds,
      lengthM: Math.hypot(end[0] - start[0], end[2] - start[2]),
    };
  });
}

export interface LocalObject {
  spec: ObjectSpec;
  center: V3;
  /** Size along the box's local axes. */
  sizeM: V3;
  rotYDeg: number;
}

export function localObjects(capture: CaptureSpec): LocalObject[] {
  return capture.objects.map((spec) => ({
    spec,
    center: toLocal(capture.frame, spec.center),
    sizeM: spec.sizeM,
    // Object rotation in the house frame plus the capture frame rotation.
    rotYDeg: (spec.rotYDeg + capture.frame.rotYDeg) % 360,
  }));
}

export interface ModelContext {
  visitId: string;
  captureId: string;
  /** Package-relative paths of the capture's source and accompanying files. */
  refs: CaptureModel["refs"];
}

/** Builds the CaptureModel of one capture in the capture's own frame. */
export function buildCaptureModel(capture: CaptureSpec, context: ModelContext): CaptureModel {
  const walls = localWalls(capture);
  const wallById = new Map(capture.walls.map((wall) => [wall.id, wall]));
  for (const opening of capture.openings) {
    const wall = wallById.get(opening.wallId);
    if (wall === undefined) {
      throw new Error(`Opening ${opening.id} names unknown wall ${opening.wallId}`);
    }
    const length = Math.hypot(wall.b[0] - wall.a[0], wall.b[1] - wall.a[1]);
    if (
      opening.offsetM - opening.widthM / 2 < 0 ||
      opening.offsetM + opening.widthM / 2 > length ||
      opening.bottomM + opening.heightM > wall.heightM
    ) {
      throw new Error(`Opening ${opening.id} does not fit in wall ${wall.id}`);
    }
  }
  const byKind = (kind: string) =>
    capture.openings
      .filter((opening) => opening.kind === kind)
      .map((opening) => ({
        id: opening.id,
        wallId: opening.wallId,
        offsetM: opening.offsetM,
        bottomM: opening.bottomM,
        widthM: opening.widthM,
        heightM: opening.heightM,
      }));
  return {
    schemaVersion: "1.0.0",
    visitId: context.visitId,
    captureId: context.captureId,
    areaKey: capture.areaKey,
    label: capture.label,
    coordinateSystem: { units: "m", handedness: "right", up: "+Y" },
    rooms: capture.rooms.map((room) => ({
      id: room.id,
      label: room.label,
      polygon: atLeast(localPolygon3(capture, room.polygon), 3),
      heightM: room.heightM,
    })),
    walls: walls.map((wall) => ({
      id: wall.id,
      start: wall.start,
      end: wall.end,
      heightM: wall.heightM,
      // Scanned surfaces have no thickness; centreline and room boundary coincide.
      thicknessM: 0,
      roomIds: wall.roomIds,
      confidence: "high" as const,
    })),
    doors: byKind("door"),
    windows: byKind("window"),
    openings: byKind("opening"),
    objects: localObjects(capture).map((object) => ({
      id: object.spec.id,
      category: object.spec.category,
      roomId: object.spec.roomId,
      box: {
        center: object.center,
        sizeM: object.sizeM,
        rotation: rotationQuaternionY(object.rotYDeg),
      },
      confidence: "high" as const,
    })),
    refs: context.refs,
  };
}
