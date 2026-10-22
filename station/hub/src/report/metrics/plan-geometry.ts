// Plan view of a capture model, ported line for line from PlanExport PlanGeometry.swift:
// deduplicated walls, opening spans along their walls, room outlines and object footprints, in
// plan coordinates (metres). Plan x is the model's x and plan y is the model's -z, so the plan
// reads the right way round seen from above with plan y pointing up the sheet.

import type { CaptureModel, CaptureObject, WallOpening } from "@chapter/capture-contract";

export interface Point {
  readonly x: number;
  readonly y: number;
}

export const add = (a: Point, b: Point): Point => ({ x: a.x + b.x, y: a.y + b.y });
export const sub = (a: Point, b: Point): Point => ({ x: a.x - b.x, y: a.y - b.y });
export const scale = (a: Point, k: number): Point => ({ x: a.x * k, y: a.y * k });
export const dot = (a: Point, b: Point): number => a.x * b.x + a.y * b.y;
export const length = (a: Point): number => Math.sqrt(a.x * a.x + a.y * a.y);
export const distance = (a: Point, b: Point): number => length(sub(a, b));
export const unit = (a: Point): Point => {
  const l = length(a);
  return l > 0 ? { x: a.x / l, y: a.y / l } : { x: 1, y: 0 };
};
/** Left-hand normal (90 degrees counter-clockwise). */
export const leftNormal = (a: Point): Point => ({ x: -a.y, y: a.x });

/** Model point [x, y, z] to plan point (x, -z). */
export function planPoint(v: readonly [number, number, number]): Point {
  return { x: v[0], y: -v[2] };
}

export type OpeningKind = "door" | "window" | "opening";
export type ObjectCategory = CaptureObject["category"];
export type Confidence = NonNullable<CaptureObject["confidence"]>;

export interface PlanWall {
  readonly id: string;
  start: Point;
  end: Point;
  thickness: number;
  /** Rooms this wall bounds, merged over coincident walls. */
  roomIds: string[];
}

export interface PlanOpening {
  readonly id: string;
  readonly kind: OpeningKind;
  readonly wallId: string;
  /** Ends of the opening along its wall. */
  readonly from: Point;
  readonly to: Point;
  readonly widthM: number;
  readonly heightM: number;
  readonly bottomM: number;
  readonly roomIds: readonly string[];
  readonly wallThickness: number;
  readonly confidence?: Confidence;
}

export interface PlanRoom {
  readonly id: string;
  readonly label: string;
  readonly polygon: readonly Point[];
  readonly heightM: number;
  readonly areaM2: number;
  readonly perimeterM: number;
  /** A point inside the room for its label. */
  readonly labelPoint: Point;
}

export interface PlanObject {
  readonly id: string;
  readonly category: ObjectCategory;
  readonly roomId?: string;
  /** Footprint corners in order. */
  readonly corners: readonly Point[];
  readonly center: Point;
  /** Box size along its local axes, metres [x, y = height, z]. */
  readonly sizeM: readonly [number, number, number];
  readonly confidence?: Confidence;
  readonly parentId?: string;
  /** Model y of the box's underside and top (for overhead objects). */
  readonly bottomY: number;
  readonly topY: number;
}

export interface PlanBounds {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

export interface PlanGeometry {
  readonly walls: readonly PlanWall[];
  readonly openings: readonly PlanOpening[];
  readonly rooms: readonly PlanRoom[];
  readonly objects: readonly PlanObject[];
  /** Undefined when there is nothing to draw. */
  readonly bounds?: PlanBounds;
  /** The (merged) wall of each model wall id. */
  readonly wallById: ReadonlyMap<string, PlanWall>;
}

/** Walls closer than this at both ends are the same wall (a partition listed once per room). */
export const COINCIDENCE_TOLERANCE = 0.002;
/** An opening with no room ids on its wall belongs to a room whose outline is this close. */
export const ROOM_ATTACH_DISTANCE = 0.15;

export class PlanGeometryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PlanGeometryError";
  }
}

function check(value: number, what: string): void {
  if (!Number.isFinite(value)) {
    throw new PlanGeometryError(`${what} is not a finite number`);
  }
}

function check3(v: readonly number[], what: string): void {
  for (const value of v) {
    check(value, what);
  }
}

/** Builds the plan view of `model`. Throws PlanGeometryError on invalid geometry. */
export function planGeometry(model: CaptureModel): PlanGeometry {
  // Walls, with coincident walls merged.
  const walls: PlanWall[] = [];
  const wallIndexById = new Map<string, number>();
  for (const wall of model.walls) {
    check3(wall.start, `wall ${wall.id} start`);
    check3(wall.end, `wall ${wall.id} end`);
    check(wall.thicknessM, `wall ${wall.id} thickness`);
    const start = planPoint(wall.start);
    const end = planPoint(wall.end);
    const tolerance = COINCIDENCE_TOLERANCE;
    const match = walls.findIndex(
      (other) =>
        (distance(other.start, start) <= tolerance && distance(other.end, end) <= tolerance) ||
        (distance(other.start, end) <= tolerance && distance(other.end, start) <= tolerance),
    );
    if (match !== -1) {
      const found = walls[match] as PlanWall;
      for (const id of wall.roomIds ?? []) {
        if (!found.roomIds.includes(id)) {
          found.roomIds.push(id);
        }
      }
      found.thickness = Math.max(found.thickness, wall.thicknessM);
      wallIndexById.set(wall.id, match);
    } else {
      walls.push({
        id: wall.id,
        start,
        end,
        thickness: Math.max(0, wall.thicknessM),
        roomIds: [...(wall.roomIds ?? [])],
      });
      wallIndexById.set(wall.id, walls.length - 1);
    }
  }

  // Rooms.
  const rooms: PlanRoom[] = [];
  for (const room of model.rooms) {
    if (room.polygon.length < 3) {
      throw new PlanGeometryError(`room ${room.id} has fewer than 3 outline points`);
    }
    for (const point of room.polygon) {
      check3(point, `room ${room.id} outline`);
    }
    check(room.heightM, `room ${room.id} height`);
    const polygon = room.polygon.map(planPoint);
    rooms.push({
      id: room.id,
      label: room.label,
      polygon,
      heightM: room.heightM,
      areaM2: polygonArea(polygon),
      perimeterM: polygonPerimeter(polygon),
      labelPoint: labelPoint(polygon),
    });
  }

  // Openings.
  const openings: PlanOpening[] = [];
  const place = (list: readonly WallOpening[], kind: OpeningKind) => {
    for (const item of list) {
      check(item.offsetM, `${item.id} offset`);
      check(item.widthM, `${item.id} width`);
      check(item.heightM, `${item.id} height`);
      check(item.bottomM, `${item.id} bottom`);
      const index = wallIndexById.get(item.wallId);
      if (index === undefined) {
        throw new PlanGeometryError(`opening ${item.id} names an unknown wall ${item.wallId}`);
      }
      const wall = walls[index] as PlanWall;
      if (!(distance(wall.start, wall.end) > 0)) {
        continue;
      }
      // Use the wall as written for this opening so its offset runs from the right end.
      const source = model.walls.find((w) => w.id === item.wallId);
      const wallStart = source === undefined ? wall.start : planPoint(source.start);
      const wallEnd = source === undefined ? wall.end : planPoint(source.end);
      const direction = unit(sub(wallEnd, wallStart));
      const from = add(wallStart, scale(direction, item.offsetM - item.widthM / 2));
      const to = add(wallStart, scale(direction, item.offsetM + item.widthM / 2));
      const tolerance = COINCIDENCE_TOLERANCE;
      const duplicate = openings.some(
        (other) =>
          other.kind === kind &&
          ((distance(other.from, from) <= tolerance && distance(other.to, to) <= tolerance) ||
            (distance(other.from, to) <= tolerance && distance(other.to, from) <= tolerance)),
      );
      if (duplicate) {
        continue;
      }
      let roomIds: string[] = [...wall.roomIds];
      if (roomIds.length === 0) {
        const middle = scale(add(from, to), 0.5);
        roomIds = rooms
          .filter((room) => distanceToBoundary(room.polygon, middle) <= ROOM_ATTACH_DISTANCE)
          .map((room) => room.id);
      }
      openings.push({
        id: item.id,
        kind,
        wallId: item.wallId,
        from,
        to,
        widthM: item.widthM,
        heightM: item.heightM,
        bottomM: item.bottomM,
        roomIds,
        wallThickness: wall.thickness,
        ...(item.confidence === undefined ? {} : { confidence: item.confidence }),
      });
    }
  };
  place(model.doors, "door");
  place(model.windows, "window");
  place(model.openings, "opening");

  // Objects.
  const objects: PlanObject[] = [];
  for (const object of model.objects) {
    check3(object.box.center, `object ${object.id} centre`);
    check3(object.box.sizeM, `object ${object.id} size`);
    const box = object.box;
    const [qx, qy, qz, qw] = box.rotation;
    const norm = Math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw);
    const r =
      norm > 1e-9
        ? { x: qx / norm, y: qy / norm, z: qz / norm, w: qw / norm }
        : { x: 0, y: 0, z: 0, w: 1 };
    const rotate = (v: { x: number; y: number; z: number }) => {
      // v' = v + 2 * cross(u, cross(u, v) + w * v), u = (x, y, z)
      const cx = r.y * v.z - r.z * v.y + r.w * v.x;
      const cy = r.z * v.x - r.x * v.z + r.w * v.y;
      const cz = r.x * v.y - r.y * v.x + r.w * v.z;
      return {
        x: v.x + 2 * (r.y * cz - r.z * cy),
        y: v.y + 2 * (r.z * cx - r.x * cz),
        z: v.z + 2 * (r.x * cy - r.y * cx),
      };
    };
    const hx = box.sizeM[0] / 2;
    const hz = box.sizeM[2] / 2;
    const corners = (
      [
        [-1, -1],
        [-1, 1],
        [1, 1],
        [1, -1],
      ] as const
    ).map(([sx, sz]) => {
      const local = rotate({ x: sx * hx, y: 0, z: sz * hz });
      return planPoint([box.center[0] + local.x, 0, box.center[2] + local.z]);
    });
    const center = planPoint(box.center);
    const roomId = object.roomId ?? rooms.find((room) => contains(room.polygon, center))?.id;
    objects.push({
      id: object.id,
      category: object.category,
      ...(roomId === undefined ? {} : { roomId }),
      corners,
      center,
      sizeM: [box.sizeM[0], box.sizeM[1], box.sizeM[2]],
      ...(object.confidence === undefined ? {} : { confidence: object.confidence }),
      ...(object.parentId === undefined ? {} : { parentId: object.parentId }),
      bottomY: box.center[1] - Math.abs(box.sizeM[1]) / 2,
      topY: box.center[1] + Math.abs(box.sizeM[1]) / 2,
    });
  }

  let bounds: PlanBounds | undefined;
  const grow = (point: Point) => {
    if (bounds === undefined) {
      bounds = { minX: point.x, minY: point.y, maxX: point.x, maxY: point.y };
    } else {
      bounds.minX = Math.min(bounds.minX, point.x);
      bounds.minY = Math.min(bounds.minY, point.y);
      bounds.maxX = Math.max(bounds.maxX, point.x);
      bounds.maxY = Math.max(bounds.maxY, point.y);
    }
  };
  for (const wall of walls) {
    grow(wall.start);
    grow(wall.end);
  }
  for (const room of rooms) {
    room.polygon.forEach(grow);
  }
  for (const object of objects) {
    object.corners.forEach(grow);
  }
  const wallById = new Map<string, PlanWall>();
  for (const [id, index] of wallIndexById) {
    wallById.set(id, walls[index] as PlanWall);
  }
  return {
    walls,
    openings,
    rooms,
    objects,
    ...(bounds === undefined ? {} : { bounds }),
    wallById,
  };
}

// MARK: Polygon maths

/** Absolute shoelace area. */
export function polygonArea(polygon: readonly Point[]): number {
  let sum = 0;
  for (let index = 0; index < polygon.length; index += 1) {
    const a = polygon[index] as Point;
    const b = polygon[(index + 1) % polygon.length] as Point;
    sum += a.x * b.y - b.x * a.y;
  }
  return Math.abs(sum) / 2;
}

export function polygonPerimeter(polygon: readonly Point[]): number {
  let sum = 0;
  for (let index = 0; index < polygon.length; index += 1) {
    sum += distance(polygon[index] as Point, polygon[(index + 1) % polygon.length] as Point);
  }
  return sum;
}

/** Ray casting, even-odd. */
export function contains(polygon: readonly Point[], point: Point): boolean {
  let inside = false;
  let previous = polygon.length - 1;
  for (let index = 0; index < polygon.length; index += 1) {
    const a = polygon[index] as Point;
    const b = polygon[previous] as Point;
    if (
      a.y > point.y !== b.y > point.y &&
      point.x < ((b.x - a.x) * (point.y - a.y)) / (b.y - a.y) + a.x
    ) {
      inside = !inside;
    }
    previous = index;
  }
  return inside;
}

export function distanceToBoundary(polygon: readonly Point[], point: Point): number {
  let best = Infinity;
  for (let index = 0; index < polygon.length; index += 1) {
    const a = polygon[index] as Point;
    const b = polygon[(index + 1) % polygon.length] as Point;
    const ab = sub(b, a);
    const lengthSquared = dot(ab, ab);
    const t =
      lengthSquared > 0 ? Math.max(0, Math.min(1, dot(sub(point, a), ab) / lengthSquared)) : 0;
    best = Math.min(best, distance(point, add(a, scale(ab, t))));
  }
  return best;
}

/**
 * Area centroid when it lies inside the outline, otherwise the middle of the longest inside
 * stretch of the horizontal line through the centroid.
 */
export function labelPoint(polygon: readonly Point[]): Point {
  let twiceArea = 0;
  let cx = 0;
  let cy = 0;
  for (let index = 0; index < polygon.length; index += 1) {
    const a = polygon[index] as Point;
    const b = polygon[(index + 1) % polygon.length] as Point;
    const cross = a.x * b.y - b.x * a.y;
    twiceArea += cross;
    cx += (a.x + b.x) * cross;
    cy += (a.y + b.y) * cross;
  }
  const mean = {
    x: polygon.reduce((sum, p) => sum + p.x, 0) / polygon.length,
    y: polygon.reduce((sum, p) => sum + p.y, 0) / polygon.length,
  };
  if (!(Math.abs(twiceArea) > 1e-12)) {
    return mean;
  }
  const centroid = { x: cx / (3 * twiceArea), y: cy / (3 * twiceArea) };
  if (contains(polygon, centroid)) {
    return centroid;
  }
  const crossings: number[] = [];
  for (let index = 0; index < polygon.length; index += 1) {
    const a = polygon[index] as Point;
    const b = polygon[(index + 1) % polygon.length] as Point;
    if (a.y > centroid.y !== b.y > centroid.y) {
      crossings.push(a.x + ((centroid.y - a.y) / (b.y - a.y)) * (b.x - a.x));
    }
  }
  crossings.sort((p, q) => p - q);
  let best: [number, number] | undefined;
  for (let index = 0; index + 1 < crossings.length; index += 2) {
    const span: [number, number] = [crossings[index] as number, crossings[index + 1] as number];
    if (best === undefined || span[1] - span[0] > best[1] - best[0]) {
      best = span;
    }
  }
  if (best !== undefined) {
    return { x: (best[0] + best[1]) / 2, y: centroid.y };
  }
  return mean;
}
