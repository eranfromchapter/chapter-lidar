// LAS 1.4 writer: point data record format 7, scale 0.001 m, offsets at the bounding-box minimum.
// LAS is Z-up: the model's +Y (height) becomes LAS Z, and model z becomes LAS -y, so the
// right-handed frame is kept.

import { concatBytes } from "../util.js";
import type { DepthSample } from "../depth.js";

export const LAS_HEADER_SIZE = 375;
export const LAS_RECORD_LENGTH = 36;
export const LAS_SCALE = 0.001;

export interface LasInfo {
  count: number;
  min: [number, number, number];
  max: [number, number, number];
}

function ascii(text: string, length: number): Uint8Array {
  const out = new Uint8Array(length);
  for (let i = 0; i < Math.min(text.length, length); i += 1) {
    out[i] = text.charCodeAt(i);
  }
  return out;
}

export function writeLas(samples: readonly DepthSample[]): Uint8Array {
  const points = samples.map((sample) => ({
    x: sample.x,
    y: -sample.z,
    z: sample.y,
    rgb: sample.rgb,
  }));
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  for (const point of points) {
    [point.x, point.y, point.z].forEach((value, axis) => {
      min[axis] = Math.min(min[axis] as number, value);
      max[axis] = Math.max(max[axis] as number, value);
    });
  }
  // Offsets and scaled integers first, then extents from the integers, so the header equals
  // the data exactly.
  const offset = [...min];
  const records = new Uint8Array(points.length * LAS_RECORD_LENGTH);
  const view = new DataView(records.buffer);
  const ints = points.map((point) =>
    [point.x, point.y, point.z].map((value, axis) =>
      Math.round((value - (offset[axis] as number)) / LAS_SCALE),
    ),
  );
  const imin = [Infinity, Infinity, Infinity];
  const imax = [-Infinity, -Infinity, -Infinity];
  ints.forEach((triple, index) => {
    const base = index * LAS_RECORD_LENGTH;
    triple.forEach((value, axis) => {
      view.setInt32(base + axis * 4, value, true);
      imin[axis] = Math.min(imin[axis] as number, value);
      imax[axis] = Math.max(imax[axis] as number, value);
    });
    view.setUint16(base + 12, 0, true); // intensity 0
    view.setUint8(base + 14, 0x11); // return 1 of 1
    view.setUint8(base + 15, 0); // flags
    view.setUint8(base + 16, 0); // classification
    view.setUint8(base + 17, 0); // user data
    view.setInt16(base + 18, 0, true); // scan angle
    view.setUint16(base + 20, 0, true); // point source id
    view.setFloat64(base + 22, index * 0.001, true); // GPS time
    const rgb = (points[index] as { rgb: [number, number, number] }).rgb;
    view.setUint16(base + 30, rgb[0] * 257, true);
    view.setUint16(base + 32, rgb[1] * 257, true);
    view.setUint16(base + 34, rgb[2] * 257, true);
  });

  const header = new Uint8Array(LAS_HEADER_SIZE);
  const h = new DataView(header.buffer);
  header.set(ascii("LASF", 4), 0);
  h.setUint16(4, 0, true); // file source id
  h.setUint16(6, 0, true); // global encoding: GPS week time, no WKT (local coordinates)
  header.set(ascii("Chapter Capture", 32), 26);
  header.set(ascii("chapter-fixtures 1.0.0", 32), 58);
  header[24] = 1;
  header[25] = 4;
  h.setUint16(90, 290, true); // creation day of year (2026-10-17)
  h.setUint16(92, 2026, true);
  h.setUint16(94, LAS_HEADER_SIZE, true);
  h.setUint32(96, LAS_HEADER_SIZE, true); // offset to point data
  h.setUint32(100, 0, true); // number of VLRs
  header[104] = 7; // point data record format
  h.setUint16(105, LAS_RECORD_LENGTH, true);
  h.setUint32(107, 0, true); // legacy point count: zero for formats 6 to 10
  for (let i = 0; i < 5; i += 1) {
    h.setUint32(111 + i * 4, 0, true);
  }
  for (let axis = 0; axis < 3; axis += 1) {
    h.setFloat64(131 + axis * 8, LAS_SCALE, true);
    h.setFloat64(155 + axis * 8, offset[axis] as number, true);
  }
  // Max X, Min X, Max Y, Min Y, Max Z, Min Z, from the stored integers.
  for (let axis = 0; axis < 3; axis += 1) {
    h.setFloat64(
      179 + axis * 16,
      (offset[axis] as number) + (imax[axis] as number) * LAS_SCALE,
      true,
    );
    h.setFloat64(
      187 + axis * 16,
      (offset[axis] as number) + (imin[axis] as number) * LAS_SCALE,
      true,
    );
  }
  h.setBigUint64(227, 0n, true); // start of waveform data packet record
  h.setBigUint64(235, 0n, true); // start of first EVLR
  h.setUint32(243, 0, true); // number of EVLRs
  h.setBigUint64(247, BigInt(points.length), true); // number of point records
  h.setBigUint64(255, BigInt(points.length), true); // points by return 1
  return concatBytes([header, records]);
}

/** Reads the header fields the tests and the defect mutation need. */
export function readLasHeader(bytes: Uint8Array): LasInfo & { signature: string } {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return {
    signature: String.fromCharCode(...bytes.subarray(0, 4)),
    count: Number(view.getBigUint64(247, true)),
    max: [view.getFloat64(179, true), view.getFloat64(195, true), view.getFloat64(211, true)],
    min: [view.getFloat64(187, true), view.getFloat64(203, true), view.getFloat64(219, true)],
  };
}
