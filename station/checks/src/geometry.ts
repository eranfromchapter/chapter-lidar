// Plan geometry helpers for the scale check: principal wall direction and extents along it.

import type { CaptureModel } from "@chapter/capture-contract";

export type P2 = [number, number];

/** Plan points (x, z) and edges of the rooms in a model (walls when it has no rooms). */
export function planOutline(
  model: CaptureModel,
  roomIds?: ReadonlySet<string>,
): {
  points: P2[];
  edges: Array<[P2, P2]>;
} {
  const points: P2[] = [];
  const edges: Array<[P2, P2]> = [];
  const rooms = model.rooms.filter((room) => roomIds === undefined || roomIds.has(room.id));
  for (const room of rooms) {
    const loop = room.polygon.map(([x, , z]) => [x, z] as P2);
    loop.forEach((point, index) => {
      points.push(point);
      edges.push([point, loop[(index + 1) % loop.length] as P2]);
    });
  }
  if (points.length === 0 && roomIds === undefined) {
    for (const wall of model.walls) {
      const a: P2 = [wall.start[0], wall.start[2]];
      const b: P2 = [wall.end[0], wall.end[2]];
      points.push(a, b);
      edges.push([a, b]);
    }
  }
  return { points, edges };
}

/**
 * Principal plan direction in radians, in [-pi/4, pi/4): the length-weighted mean of edge
 * directions modulo 90 degrees (rectilinear buildings give their wall direction).
 */
export function principalAngle(edges: ReadonlyArray<[P2, P2]>): number {
  let c = 0;
  let s = 0;
  for (const [a, b] of edges) {
    const dx = b[0] - a[0];
    const dz = b[1] - a[1];
    const length = Math.hypot(dx, dz);
    if (length === 0) {
      continue;
    }
    const theta = Math.atan2(dz, dx);
    c += length * Math.cos(4 * theta);
    s += length * Math.sin(4 * theta);
  }
  if (c === 0 && s === 0) {
    return 0;
  }
  const angle = Math.atan2(s, c) / 4;
  return Math.abs(angle) < 1e-9 ? 0 : angle;
}

/** Extents (metres) of points along the principal direction u and its perpendicular v. */
export function extentsAlong(points: readonly P2[], angle: number): { u: number; v: number } {
  const cos = Math.cos(angle);
  const sin = Math.sin(angle);
  let minU = Infinity;
  let maxU = -Infinity;
  let minV = Infinity;
  let maxV = -Infinity;
  for (const [x, z] of points) {
    const u = x * cos + z * sin;
    const v = -x * sin + z * cos;
    minU = Math.min(minU, u);
    maxU = Math.max(maxU, u);
    minV = Math.min(minV, v);
    maxV = Math.max(maxV, v);
  }
  return points.length === 0 ? { u: 0, v: 0 } : { u: maxU - minU, v: maxV - minV };
}
