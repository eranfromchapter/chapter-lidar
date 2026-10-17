// Triangle mesh of a capture, built only from its CaptureModel (floor, ceiling and wall quads).
// Walls have no cut-outs: this is a simplified plan model, like a Polycam floor-plan mesh.

import type { CaptureModel } from "@chapter/capture-contract";
import { shoelace } from "./geometry.js";
import type { P2, V3 } from "./util.js";

export interface Mesh {
  /** Flat x, y, z per vertex, metres, +Y up. */
  positions: number[];
  /** Flat unit normals per vertex. */
  normals: number[];
  /** Flat uv per vertex. */
  uvs: number[];
  /** Triangle vertex indices. */
  indices: number[];
}

function sub(a: V3, b: V3): V3 {
  return [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
}

function cross(a: V3, b: V3): V3 {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}

function dot(a: V3, b: V3): number {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

/** Ear-clipping triangulation of a simple plan polygon. Returns index triples. */
export function triangulate(polygon: readonly P2[]): Array<[number, number, number]> {
  const count = polygon.length;
  const order = Array.from({ length: count }, (_, i) => i);
  // Work counter-clockwise in (x, z) with a positive area, regardless of input order.
  if (shoelace(polygon) < 0) {
    order.reverse();
  }
  const cross2 = (o: P2, a: P2, b: P2) =>
    (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const inTriangle = (p: P2, a: P2, b: P2, c: P2) =>
    cross2(a, b, p) >= 0 && cross2(b, c, p) >= 0 && cross2(c, a, p) >= 0;
  const triangles: Array<[number, number, number]> = [];
  let guard = 0;
  while (order.length > 3 && guard < 10000) {
    guard += 1;
    let clipped = false;
    for (let i = 0; i < order.length; i += 1) {
      const prev = order[(i + order.length - 1) % order.length] as number;
      const cur = order[i] as number;
      const next = order[(i + 1) % order.length] as number;
      const a = polygon[prev] as P2;
      const b = polygon[cur] as P2;
      const c = polygon[next] as P2;
      if (cross2(a, b, c) <= 0) {
        continue;
      }
      const blocked = order.some(
        (other) =>
          other !== prev &&
          other !== cur &&
          other !== next &&
          inTriangle(polygon[other] as P2, a, b, c),
      );
      if (blocked) {
        continue;
      }
      triangles.push([prev, cur, next]);
      order.splice(i, 1);
      clipped = true;
      break;
    }
    if (!clipped) {
      throw new Error("Polygon cannot be triangulated");
    }
  }
  triangles.push([order[0] as number, order[1] as number, order[2] as number]);
  return triangles;
}

class MeshBuilder {
  readonly mesh: Mesh = { positions: [], normals: [], uvs: [], indices: [] };

  /** Adds a flat-shaded triangle whose front face looks along `normal`. */
  triangle(a: V3, b: V3, c: V3, normal: V3, uv: [P2, P2, P2]): void {
    let second = b;
    let third = c;
    let uvs = uv;
    if (dot(cross(sub(b, a), sub(c, a)), normal) < 0) {
      second = c;
      third = b;
      uvs = [uv[0], uv[2], uv[1]];
    }
    const base = this.mesh.positions.length / 3;
    [a, second, third].forEach((point, i) => {
      this.mesh.positions.push(point[0], point[1], point[2]);
      this.mesh.normals.push(normal[0], normal[1], normal[2]);
      const [u, v] = uvs[i] as P2;
      this.mesh.uvs.push(u, v);
    });
    this.mesh.indices.push(base, base + 1, base + 2);
  }
}

/** Builds the reference mesh of a capture from its CaptureModel. */
export function meshFromModel(model: CaptureModel): Mesh {
  const builder = new MeshBuilder();
  for (const room of model.rooms) {
    const plan2: P2[] = room.polygon.map(([x, , z]) => [x, z]);
    for (const [i, j, k] of triangulate(plan2)) {
      const at = (index: number, y: number): V3 => {
        const [x, , z] = room.polygon[index] as V3;
        return [x, y, z];
      };
      const uv = (index: number): P2 => [(plan2[index] as P2)[0], (plan2[index] as P2)[1]];
      builder.triangle(at(i, 0), at(j, 0), at(k, 0), [0, 1, 0], [uv(i), uv(j), uv(k)]);
      builder.triangle(
        at(i, room.heightM),
        at(j, room.heightM),
        at(k, room.heightM),
        [0, -1, 0],
        [uv(i), uv(j), uv(k)],
      );
    }
  }
  const roomById = new Map(model.rooms.map((room) => [room.id, room]));
  for (const wall of model.walls) {
    const [sx, , sz] = wall.start;
    const [ex, , ez] = wall.end;
    const dx = ex - sx;
    const dz = ez - sz;
    const length = Math.hypot(dx, dz);
    let normal: V3 = [-dz / length, 0, dx / length];
    const room = roomById.get(wall.roomIds?.[0] ?? "");
    if (room !== undefined) {
      const cx = room.polygon.reduce((sum, p) => sum + p[0], 0) / room.polygon.length;
      const cz = room.polygon.reduce((sum, p) => sum + p[2], 0) / room.polygon.length;
      const mx = (sx + ex) / 2;
      const mz = (sz + ez) / 2;
      if (normal[0] * (cx - mx) + normal[2] * (cz - mz) < 0) {
        normal = [-normal[0], 0, -normal[2]];
      }
    }
    const h = wall.heightM;
    const p00: V3 = [sx, 0, sz];
    const p10: V3 = [ex, 0, ez];
    const p11: V3 = [ex, h, ez];
    const p01: V3 = [sx, h, sz];
    builder.triangle(p00, p10, p11, normal, [
      [0, 0],
      [length, 0],
      [length, h],
    ]);
    builder.triangle(p00, p11, p01, normal, [
      [0, 0],
      [length, h],
      [0, h],
    ]);
  }
  return builder.mesh;
}

export interface Bounds {
  min: V3;
  max: V3;
}

export function positionBounds(positions: readonly number[]): Bounds {
  const min: V3 = [Infinity, Infinity, Infinity];
  const max: V3 = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < positions.length; i += 3) {
    for (let axis = 0; axis < 3; axis += 1) {
      const value = positions[i + axis] as number;
      if (value < (min[axis] as number)) {
        min[axis] = value;
      }
      if (value > (max[axis] as number)) {
        max[axis] = value;
      }
    }
  }
  return { min, max };
}
