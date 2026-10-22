// Wall bands of a drawing. RoomPlan measures no wall thickness, so a band has the assumed
// thickness (4.5 in for a wall between rooms, 6 in otherwise; at least 2 pt on the page) and is
// placed like the phone's plan: a wall between two rooms is centred on its centreline; a wall
// of one room lies outside that room (an exterior wall grows outwards, and two rooms scanned
// with their own walls side by side meet in one band instead of two). Ends are squared off so
// corners close: by half the thickness for a centred band; for an outside band, by the whole
// thickness at an outside corner and not at all at an inside corner.

import {
  add,
  contains,
  distance,
  dot,
  leftNormal,
  scale,
  sub,
  unit,
  type PlanRoom,
  type PlanWall,
  type Point,
} from "../metrics/plan-geometry.js";

/** A straight piece of a wall to draw (the whole wall, or the part along a room's edge). */
export interface WallSegment {
  readonly a: Point;
  readonly b: Point;
  readonly wall: PlanWall;
}

/** -1 / +1: the band lies on that side of the centreline (left normal); 0: centred. */
export type BandSide = -1 | 0 | 1;

export interface WallBand {
  readonly segment: WallSegment;
  readonly thickness: number;
  readonly side: BandSide;
  readonly corners: readonly Point[];
}

const PROBE_M = 0.15;
const JOIN_M = 0.05;

/** Which side of the centreline a wall's band lies on. */
export function bandSide(wall: PlanWall, rooms: readonly PlanRoom[]): BandSide {
  if (wall.roomIds.length >= 2) {
    return 0;
  }
  const length = distance(wall.start, wall.end);
  if (!(length > 0)) {
    return 0;
  }
  const n = leftNormal(unit(sub(wall.end, wall.start)));
  const middle = scale(add(wall.start, wall.end), 0.5);
  const own =
    wall.roomIds.length === 1 ? rooms.filter((room) => room.id === wall.roomIds[0]) : rooms;
  const candidates = own.length > 0 ? own : rooms;
  const left = candidates.some((room) => contains(room.polygon, add(middle, scale(n, PROBE_M))));
  const right = candidates.some((room) => contains(room.polygon, sub(middle, scale(n, PROBE_M))));
  if (left === right) {
    return 0;
  }
  // The room is on one side: the band goes to the other.
  return left ? -1 : 1;
}

/** Offsets of the band's two faces along the wall's left normal. */
export function bandFaces(thickness: number, side: BandSide): [number, number] {
  switch (side) {
    case 0:
      return [-thickness / 2, thickness / 2];
    case 1:
      return [0, thickness];
    case -1:
      return [-thickness, 0];
  }
}

/** Unit left normal of a wall (its own start-to-end direction). */
export function wallNormal(wall: PlanWall): Point {
  return leftNormal(unit(sub(wall.end, wall.start)));
}

/** The bands of segments, with their ends closed against neighbouring segments. */
export function wallBands(
  segments: readonly WallSegment[],
  rooms: readonly PlanRoom[],
  thickness: (wall: PlanWall) => number,
): WallBand[] {
  const sides = new Map<PlanWall, BandSide>();
  const sideOf = (wall: PlanWall) => {
    let side = sides.get(wall);
    if (side === undefined) {
      side = bandSide(wall, rooms);
      sides.set(wall, side);
    }
    return side;
  };
  const usable = segments.filter((segment) => distance(segment.a, segment.b) > 1e-9);
  return usable.map((segment) => {
    const t = thickness(segment.wall);
    const side = sideOf(segment.wall);
    const u = unit(sub(segment.b, segment.a));
    // Faces relative to the segment's own left normal (it may run against its wall).
    const flip = dot(leftNormal(u), wallNormal(segment.wall)) < 0 ? -1 : 1;
    const [low, high] = bandFaces(t, side).map((face) => face * flip) as [number, number];
    const n = leftNormal(u);
    const outward = scale(n, side * flip);
    const extension = (end: Point, away: Point): number => {
      if (side === 0) {
        return t / 2;
      }
      let result: number | undefined;
      for (const other of usable) {
        if (other === segment) {
          continue;
        }
        for (const [p, q] of [
          [other.a, other.b],
          [other.b, other.a],
        ] as const) {
          if (distance(p, end) > JOIN_M) {
            continue;
          }
          // Direction of the other segment leaving this end.
          const leaving = unit(sub(q, p));
          const turn = dot(leaving, outward);
          const along = Math.abs(dot(leaving, away));
          if (along > 0.98) {
            result = Math.max(result ?? 0, 0);
          } else if (turn < 0) {
            // It heads to the room side: an outside corner.
            result = Math.max(result ?? 0, t);
          } else {
            result = Math.max(result ?? 0, 0);
          }
        }
      }
      return result ?? t / 2;
    };
    const startExtension = extension(segment.a, scale(u, -1));
    const endExtension = extension(segment.b, u);
    const start = sub(segment.a, scale(u, startExtension));
    const end = add(segment.b, scale(u, endExtension));
    return {
      segment,
      thickness: t,
      side,
      corners: [
        add(start, scale(n, low)),
        add(end, scale(n, low)),
        add(end, scale(n, high)),
        add(start, scale(n, high)),
      ],
    };
  });
}

/**
 * The cleared area of an opening in its wall's band (with `margin` metres more on both faces)
 * and the line along the band's middle, offset by `offset` metres.
 */
export function openingGeometry(
  from: Point,
  to: Point,
  wall: PlanWall | undefined,
  thickness: number,
  side: BandSide,
  margin: number,
): { clear: Point[]; middle: (offset: number) => [Point, Point] } {
  const n = wall === undefined ? leftNormal(unit(sub(to, from))) : wallNormal(wall);
  const [low, high] = bandFaces(thickness, side);
  const clear = [
    add(from, scale(n, low - margin)),
    add(to, scale(n, low - margin)),
    add(to, scale(n, high + margin)),
    add(from, scale(n, high + margin)),
  ];
  const centre = (low + high) / 2;
  return {
    clear,
    middle: (offset) => [add(from, scale(n, centre + offset)), add(to, scale(n, centre + offset))],
  };
}
