// Depth sample set: points on the floor, ceiling and wall surfaces of a capture with seeded
// uniform noise of up to 5 mm per axis, written as a small binary file.
//
// File layout "CHDS" version 1, little endian:
//   offset 0   4 bytes  magic "CHDS"
//   offset 4   u32      version (1)
//   offset 8   u32      sample count N
//   offset 12  u32      reserved (0)
//   offset 16  N x 16 bytes: f32 x, f32 y, f32 z (metres, capture frame, +Y up),
//                            u8 red, u8 green, u8 blue, u8 confidence (0 low, 1 medium, 2 high)

import type { CaptureModel } from "@chapter/capture-contract";
import { pointInPolygon, polygonArea } from "./geometry.js";
import { mulberry32, type P2, type V3 } from "./util.js";

export const NOISE_M = 0.005;
export const DEPTH_HEADER_BYTES = 16;
export const DEPTH_SAMPLE_BYTES = 16;
/** Samples per square metre of surface. */
const DENSITY = 14;

export interface DepthSample {
  x: number;
  y: number;
  z: number;
  rgb: [number, number, number];
  confidence: number;
}

function noise(next: () => number): number {
  return (next() * 2 - 1) * NOISE_M;
}

/** Generates the samples of a capture. Surfaces come from the CaptureModel only. */
export function generateDepthSamples(model: CaptureModel, seed: number): DepthSample[] {
  const next = mulberry32(seed);
  const samples: DepthSample[] = [];
  const push = (point: V3, rgb: [number, number, number]) => {
    samples.push({
      x: Math.fround(point[0] + noise(next)),
      y: Math.fround(point[1] + noise(next)),
      z: Math.fround(point[2] + noise(next)),
      rgb,
      confidence: 2,
    });
  };
  const openingsByWall = new Map<
    string,
    Array<{ from: number; to: number; bottom: number; top: number }>
  >();
  for (const opening of [...model.doors, ...model.windows, ...model.openings]) {
    const list = openingsByWall.get(opening.wallId) ?? [];
    list.push({
      from: opening.offsetM - opening.widthM / 2,
      to: opening.offsetM + opening.widthM / 2,
      bottom: opening.bottomM,
      top: opening.bottomM + opening.heightM,
    });
    openingsByWall.set(opening.wallId, list);
  }
  for (const room of model.rooms) {
    const polygon: P2[] = room.polygon.map(([x, , z]) => [x, z]);
    // Corners of the floor and ceiling outlines pin the extents.
    for (const [x, , z] of room.polygon) {
      push([x, 0, z], [170, 170, 170]);
      push([x, room.heightM, z], [235, 235, 235]);
    }
    const xs = polygon.map((p) => p[0]);
    const zs = polygon.map((p) => p[1]);
    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minZ = Math.min(...zs);
    const maxZ = Math.max(...zs);
    const wanted = Math.round(polygonArea(polygon) * DENSITY);
    let made = 0;
    let attempts = 0;
    while (made < wanted && attempts < wanted * 50 + 100) {
      attempts += 1;
      const point: P2 = [minX + next() * (maxX - minX), minZ + next() * (maxZ - minZ)];
      if (!pointInPolygon(point, polygon)) {
        continue;
      }
      push([point[0], 0, point[1]], [170, 170, 170]);
      push([point[0], room.heightM, point[1]], [235, 235, 235]);
      made += 1;
    }
  }
  for (const wall of model.walls) {
    const [sx, , sz] = wall.start;
    const [ex, , ez] = wall.end;
    const length = Math.hypot(ex - sx, ez - sz);
    const holes = openingsByWall.get(wall.id) ?? [];
    for (const [u, v] of [
      [0, 0],
      [length, 0],
      [length, wall.heightM],
      [0, wall.heightM],
    ] as Array<[number, number]>) {
      const t = u / length;
      push([sx + (ex - sx) * t, v, sz + (ez - sz) * t], [215, 210, 200]);
    }
    const wanted = Math.round(length * wall.heightM * DENSITY);
    let made = 0;
    while (made < wanted) {
      const u = next() * length;
      const v = next() * wall.heightM;
      if (holes.some((hole) => u > hole.from && u < hole.to && v > hole.bottom && v < hole.top)) {
        continue;
      }
      const t = u / length;
      push([sx + (ex - sx) * t, v, sz + (ez - sz) * t], [215, 210, 200]);
      made += 1;
    }
  }
  return samples;
}

export function writeDepthSamples(samples: readonly DepthSample[]): Uint8Array {
  const out = new Uint8Array(DEPTH_HEADER_BYTES + samples.length * DEPTH_SAMPLE_BYTES);
  const view = new DataView(out.buffer);
  out.set([0x43, 0x48, 0x44, 0x53], 0);
  view.setUint32(4, 1, true);
  view.setUint32(8, samples.length, true);
  view.setUint32(12, 0, true);
  samples.forEach((sample, index) => {
    const base = DEPTH_HEADER_BYTES + index * DEPTH_SAMPLE_BYTES;
    view.setFloat32(base, sample.x, true);
    view.setFloat32(base + 4, sample.y, true);
    view.setFloat32(base + 8, sample.z, true);
    view.setUint8(base + 12, sample.rgb[0]);
    view.setUint8(base + 13, sample.rgb[1]);
    view.setUint8(base + 14, sample.rgb[2]);
    view.setUint8(base + 15, sample.confidence);
  });
  return out;
}

/** Reads a depth sample file back (used by tests and downstream tools). */
export function readDepthSamples(bytes: Uint8Array): DepthSample[] {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const magic = String.fromCharCode(...bytes.subarray(0, 4));
  if (magic !== "CHDS" || view.getUint32(4, true) !== 1) {
    throw new Error("Not a CHDS version 1 depth sample file");
  }
  const count = view.getUint32(8, true);
  const samples: DepthSample[] = [];
  for (let i = 0; i < count; i += 1) {
    const base = DEPTH_HEADER_BYTES + i * DEPTH_SAMPLE_BYTES;
    samples.push({
      x: view.getFloat32(base, true),
      y: view.getFloat32(base + 4, true),
      z: view.getFloat32(base + 8, true),
      rgb: [view.getUint8(base + 12), view.getUint8(base + 13), view.getUint8(base + 14)],
      confidence: view.getUint8(base + 15),
    });
  }
  return samples;
}
