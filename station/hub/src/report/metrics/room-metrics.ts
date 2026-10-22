// Measurements of each room of a capture, ported line for line from PlanExport RoomMetrics.swift
// and PlanTotals.swift (casing lengths and the exterior area estimate are not ported: the report
// shows neither). Definitions are those of RoomMetrics.swift:
//
// - Floor area: shoelace area of the floor outline. Perimeter: length of the outline.
// - Frame: the room's dominant axis (dominantAngle). Bounding box B: smallest rectangle along the
//   frame containing the outline. Inscribed I: largest rectangle along the frame inside it.
// - Walled edges: outline parts a wall runs along (within 0.10 m and 5 degrees); ceiling height =
//   length-weighted median wall height there; approximate when off-height walls cover more than
//   10 % of the walled length, walls cover less than half the perimeter, or no wall runs along it.
// - Volume = floor area x ceiling. Wall area incl. openings = sum of walled length x height;
//   excluding openings subtracts every door, window and opening on a walled edge.

import type { CaptureModel, RoomType } from "@chapter/capture-contract";
import {
  Frame,
  bounds,
  distinctSorted,
  dominantAngle,
  largestInscribedRectangle,
  measured,
  EPSILON,
  type Box,
  type MeasuredRectangle,
} from "./metrics-geometry.js";
import {
  distance,
  dot,
  leftNormal,
  planGeometry,
  planPoint,
  scale,
  add,
  sub,
  unit,
  type Confidence,
  type ObjectCategory,
  type OpeningKind,
  type PlanGeometry,
  type PlanOpening,
  type Point,
} from "./plan-geometry.js";

export const WALL_MATCH_DISTANCE_M = 0.1;
export const WALL_MATCH_ANGLE_DEGREES = 5.0;
export const WALL_HEIGHT_SPREAD_M = 0.05;
export const MAXIMUM_OFF_HEIGHT_FRACTION = 0.1;
export const MINIMUM_WALLED_FRACTION = 0.5;

export type CeilingReason = "wallHeightsDiffer" | "fewWalls" | "noWalls";

export interface CeilingHeight {
  readonly heightM: number;
  readonly basis: "roomWalls" | "captureWalls" | "roomRecord";
  /** Empty when the height is not approximate. */
  readonly approximateReasons: readonly CeilingReason[];
}

export interface OpeningMetrics {
  readonly id: string;
  readonly type: OpeningKind;
  readonly widthM: number;
  readonly heightM: number;
  readonly areaM2: number;
  readonly confidence?: Confidence;
}

export interface ObjectMetrics {
  readonly id: string;
  readonly category: ObjectCategory;
  /** Box size along its own axes: width (x), height (y), depth (z), metres. */
  readonly widthM: number;
  readonly heightM: number;
  readonly depthM: number;
  readonly confidence?: Confidence;
  readonly parentId?: string;
}

/** A stretch of an outline edge with a wall, `from`/`to` in metres from the edge start. */
export interface WalledSpan {
  from: number;
  to: number;
  heightM: number;
}

export interface WalledEdge {
  readonly a: Point;
  readonly b: Point;
  readonly spans: readonly WalledSpan[];
}

export interface RoomMetrics {
  readonly roomId: string;
  readonly label: string;
  readonly type?: RoomType;
  readonly floorAreaM2: number;
  readonly perimeterM: number;
  /** Radians counter-clockwise from plan +x, in (-pi/4, pi/4]. */
  readonly frameAngleRadians: number;
  readonly boundingBox: MeasuredRectangle;
  readonly inscribed: MeasuredRectangle;
  readonly ceiling: CeilingHeight;
  readonly volumeM3: number;
  readonly wallAreaIncludingOpeningsM2: number;
  readonly wallAreaExcludingOpeningsM2: number;
  readonly walledLengthM: number;
  readonly openings: readonly OpeningMetrics[];
  readonly objects: readonly ObjectMetrics[];
  /** The outline edges with their walled spans (for drawing the room's walls). */
  readonly edges: readonly WalledEdge[];
}

export const isApproximate = (ceiling: CeilingHeight): boolean =>
  ceiling.approximateReasons.length > 0;

interface WallLine {
  readonly start: Point;
  readonly end: Point;
  readonly heightM: number;
}

/** Measurements of every room of `model`, in model order. */
export function measureRooms(
  model: CaptureModel,
  geometry: PlanGeometry = planGeometry(model),
): RoomMetrics[] {
  const walls: WallLine[] = model.walls.map((wall) => ({
    start: planPoint(wall.start),
    end: planPoint(wall.end),
    heightM: Math.max(0, wall.heightM),
  }));
  const captureMedian = weightedMedian(
    walls.map((wall) => [wall.heightM, distance(wall.start, wall.end)] as const),
  );
  const sourceObjects = new Map<string, (typeof model.objects)[number]>();
  for (const object of model.objects) {
    if (!sourceObjects.has(object.id)) {
      sourceObjects.set(object.id, object);
    }
  }

  return geometry.rooms.map((room, index) => {
    const source = index < model.rooms.length ? model.rooms[index] : undefined;
    const polygon = room.polygon;
    const frame = new Frame(dominantAngle([polygon]));
    const local = polygon.map((p) => frame.local(p));
    const box = bounds(local) as Box;
    const middle = { x: (box.minX + box.maxX) / 2, y: (box.minY + box.maxY) / 2 };
    const inscribed: Box = largestInscribedRectangle(local) ?? {
      minX: middle.x,
      minY: middle.y,
      maxX: middle.x,
      maxY: middle.y,
    };

    // Walled edges.
    const spans: WalledSpan[] = [];
    const edges: WalledEdge[] = [];
    for (let edgeIndex = 0; edgeIndex < polygon.length; edgeIndex += 1) {
      const a = polygon[edgeIndex] as Point;
      const b = polygon[(edgeIndex + 1) % polygon.length] as Point;
      const here = walledSpans(a, b, walls);
      spans.push(...here);
      edges.push({ a, b, spans: here });
    }
    const walledLength = spans.reduce((sum, span) => sum + (span.to - span.from), 0);
    const wallArea = spans.reduce((sum, span) => sum + (span.to - span.from) * span.heightM, 0);

    // Ceiling height.
    let ceiling: CeilingHeight;
    if (walledLength <= EPSILON) {
      const height = captureMedian ?? Math.max(0, source?.heightM ?? 0);
      ceiling = {
        heightM: height,
        basis: captureMedian === undefined ? "roomRecord" : "captureWalls",
        approximateReasons: ["noWalls"],
      };
    } else {
      const median =
        weightedMedian(spans.map((span) => [span.heightM, span.to - span.from] as const)) ?? 0;
      const reasons: CeilingReason[] = [];
      const offHeight = spans
        .filter((span) => Math.abs(span.heightM - median) > WALL_HEIGHT_SPREAD_M + EPSILON)
        .reduce((sum, span) => sum + (span.to - span.from), 0);
      if (offHeight > MAXIMUM_OFF_HEIGHT_FRACTION * walledLength) {
        reasons.push("wallHeightsDiffer");
      }
      if (walledLength < MINIMUM_WALLED_FRACTION * room.perimeterM - EPSILON) {
        reasons.push("fewWalls");
      }
      ceiling = { heightM: median, basis: "roomWalls", approximateReasons: reasons };
    }

    // Openings on walled edges.
    const openings: OpeningMetrics[] = [];
    for (const opening of geometry.openings) {
      if (edges.some((edge) => isOpeningOnEdge(opening, edge.a, edge.b, edge.spans))) {
        openings.push({
          id: opening.id,
          type: opening.kind,
          widthM: opening.widthM,
          heightM: opening.heightM,
          areaM2: opening.widthM * opening.heightM,
          ...(opening.confidence === undefined ? {} : { confidence: opening.confidence }),
        });
      }
    }
    const openingArea = openings.reduce((sum, opening) => sum + opening.areaM2, 0);

    // Objects.
    const objects: ObjectMetrics[] = geometry.objects
      .filter((object) => object.roomId === room.id)
      .map((object) => {
        const parentId = sourceObjects.get(object.id)?.parentId;
        return {
          id: object.id,
          category: object.category,
          widthM: object.sizeM[0],
          heightM: object.sizeM[1],
          depthM: object.sizeM[2],
          ...(object.confidence === undefined ? {} : { confidence: object.confidence }),
          ...(parentId === undefined ? {} : { parentId }),
        };
      });

    return {
      roomId: room.id,
      label: room.label,
      ...(source?.type === undefined ? {} : { type: source.type }),
      floorAreaM2: room.areaM2,
      perimeterM: room.perimeterM,
      frameAngleRadians: frame.angle,
      boundingBox: measured(box, frame),
      inscribed: measured(inscribed, frame),
      ceiling,
      volumeM3: room.areaM2 * ceiling.heightM,
      wallAreaIncludingOpeningsM2: wallArea,
      wallAreaExcludingOpeningsM2: Math.max(0, wallArea - openingArea),
      walledLengthM: walledLength,
      openings,
      objects,
      edges,
    };
  });
}

/** The stretches of the edge a-b that walls run along, each with the tallest wall's height. */
export function walledSpans(a: Point, b: Point, walls: readonly WallLine[]): WalledSpan[] {
  const edgeLength = distance(a, b);
  if (!(edgeLength > EPSILON)) {
    return [];
  }
  const u = unit(sub(b, a));
  const n = leftNormal(u);
  const maxSine = Math.sin((WALL_MATCH_ANGLE_DEGREES * Math.PI) / 180);
  const intervals: WalledSpan[] = [];
  for (const wall of walls) {
    const direction = sub(wall.end, wall.start);
    const wallLength = Math.sqrt(direction.x * direction.x + direction.y * direction.y);
    if (!(wallLength > EPSILON)) {
      continue;
    }
    if (!(Math.abs(u.x * direction.y - u.y * direction.x) / wallLength <= maxSine)) {
      continue;
    }
    const t0 = dot(sub(wall.start, a), u);
    const t1 = dot(sub(wall.end, a), u);
    if (!(Math.abs(t1 - t0) > EPSILON)) {
      continue;
    }
    const from = Math.max(0, Math.min(t0, t1));
    const to = Math.min(edgeLength, Math.max(t0, t1));
    if (!(to - from > 1e-6)) {
      continue;
    }
    const close = [from, to].every((t) => {
      const point = add(wall.start, scale(direction, (t - t0) / (t1 - t0)));
      return Math.abs(dot(sub(point, a), n)) <= WALL_MATCH_DISTANCE_M;
    });
    if (close) {
      intervals.push({ from, to, heightM: wall.heightM });
    }
  }
  if (intervals.length === 0) {
    return [];
  }
  const cuts = distinctSorted(intervals.flatMap((span) => [span.from, span.to]));
  const result: WalledSpan[] = [];
  for (let index = 0; index + 1 < cuts.length; index += 1) {
    const from = cuts[index] as number;
    const to = cuts[index + 1] as number;
    const middle = (from + to) / 2;
    const covering = intervals.filter((span) => span.from <= middle && middle <= span.to);
    if (covering.length === 0) {
      continue;
    }
    const height = Math.max(...covering.map((span) => span.heightM));
    const last = result[result.length - 1];
    if (last !== undefined && last.heightM === height && Math.abs(last.to - from) <= 1e-12) {
      last.to = to;
    } else {
      result.push({ from, to, heightM: height });
    }
  }
  return result;
}

/** Whether the middle of `opening` lies on a walled stretch of the edge a-b, running along it. */
export function isOpeningOnEdge(
  opening: PlanOpening,
  a: Point,
  b: Point,
  spans: readonly WalledSpan[],
): boolean {
  const edgeLength = distance(a, b);
  if (!(edgeLength > EPSILON) || spans.length === 0) {
    return false;
  }
  const u = unit(sub(b, a));
  const along = sub(opening.to, opening.from);
  const alongLength = Math.sqrt(along.x * along.x + along.y * along.y);
  if (alongLength > EPSILON) {
    const sine = Math.abs(u.x * along.y - u.y * along.x) / alongLength;
    if (!(sine <= Math.sin((WALL_MATCH_ANGLE_DEGREES * Math.PI) / 180))) {
      return false;
    }
  }
  const middle = scale(add(opening.from, opening.to), 0.5);
  if (!(Math.abs(dot(sub(middle, a), leftNormal(u))) <= WALL_MATCH_DISTANCE_M)) {
    return false;
  }
  const t = dot(sub(middle, a), u);
  const slack = 0.01;
  return spans.some((span) => t >= span.from - slack && t <= span.to + slack);
}

/**
 * Weighted median of (value, weight) pairs: the smallest value at which the running weight, in
 * ascending value order, reaches half the total; the mean of that value and the next when it
 * lands exactly on half. Undefined when the total weight is zero.
 */
export function weightedMedian(
  values: ReadonlyArray<readonly [number, number]>,
): number | undefined {
  const sorted = values
    .filter((item) => item[1] > 0)
    .sort((p, q) => (p[0] < q[0] ? -1 : p[0] > q[0] ? 1 : p[1] < q[1] ? -1 : p[1] > q[1] ? 1 : 0));
  const total = sorted.reduce((sum, item) => sum + item[1], 0);
  if (!(total > 0)) {
    return undefined;
  }
  const half = total / 2;
  let running = 0;
  for (let index = 0; index < sorted.length; index += 1) {
    const item = sorted[index] as readonly [number, number];
    running += item[1];
    if (Math.abs(running - half) <= 1e-9 * total && index + 1 < sorted.length) {
      return (item[0] + (sorted[index + 1] as readonly [number, number])[0]) / 2;
    }
    if (running >= half) {
      return item[0];
    }
  }
  return sorted[sorted.length - 1]?.[0];
}

/** Totals over every room of a capture (PlanTotals.swift without the exterior estimate). */
export interface PlanTotals {
  readonly roomCount: number;
  readonly bedrooms: number;
  readonly bathrooms: number;
  readonly livableAreaM2: number;
  readonly wallAreaM2: number;
  readonly windowAreaM2: number;
  readonly volumeM3: number;
  readonly volumeIsApproximate: boolean;
  readonly perimeterM: number;
}

export function planTotals(rooms: readonly RoomMetrics[], geometry: PlanGeometry): PlanTotals {
  const windows = geometry.openings.filter((opening) => opening.kind === "window");
  return {
    roomCount: rooms.length,
    bedrooms: rooms.filter((room) => room.type === "bedroom").length,
    bathrooms: rooms.filter((room) => room.type === "bathroom").length,
    livableAreaM2: rooms.reduce((sum, room) => sum + room.floorAreaM2, 0),
    wallAreaM2: rooms.reduce((sum, room) => sum + room.wallAreaExcludingOpeningsM2, 0),
    windowAreaM2: windows.reduce((sum, opening) => sum + opening.widthM * opening.heightM, 0),
    volumeM3: rooms.reduce((sum, room) => sum + room.volumeM3, 0),
    volumeIsApproximate: rooms.some((room) => isApproximate(room.ceiling)),
    perimeterM: rooms.reduce((sum, room) => sum + room.perimeterM, 0),
  };
}

/** Room measurements and totals of one capture model. */
export interface PlanMetrics {
  readonly geometry: PlanGeometry;
  readonly rooms: readonly RoomMetrics[];
  readonly totals: PlanTotals;
}

export function planMetrics(model: CaptureModel): PlanMetrics {
  const geometry = planGeometry(model);
  const rooms = measureRooms(model, geometry);
  return { geometry, rooms, totals: planTotals(rooms, geometry) };
}
