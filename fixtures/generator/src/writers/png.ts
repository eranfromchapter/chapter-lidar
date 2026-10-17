// PNG encoder with stored (uncompressed) deflate blocks, so output bytes never depend on the
// zlib version. Plus a tiny 1-bit plan raster and a small texture.

import { crc32 } from "node:zlib";
import type { CaptureModel } from "@chapter/capture-contract";
import { concatBytes } from "../util.js";
import { planBounds } from "./svg.js";

function chunk(type: string, data: Uint8Array): Uint8Array {
  const out = new Uint8Array(12 + data.length);
  const view = new DataView(out.buffer);
  view.setUint32(0, data.length);
  for (let i = 0; i < 4; i += 1) {
    out[4 + i] = type.charCodeAt(i);
  }
  out.set(data, 8);
  view.setUint32(8 + data.length, crc32(out.subarray(4, 8 + data.length)));
  return out;
}

function adler32(data: Uint8Array): number {
  let a = 1;
  let b = 0;
  for (const byte of data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return ((b << 16) | a) >>> 0;
}

function zlibStored(data: Uint8Array): Uint8Array {
  const blocks: Uint8Array[] = [Uint8Array.of(0x78, 0x01)];
  let offset = 0;
  do {
    const size = Math.min(65535, data.length - offset);
    const last = offset + size >= data.length ? 1 : 0;
    const header = new Uint8Array(5);
    header[0] = last;
    header[1] = size & 0xff;
    header[2] = size >> 8;
    header[3] = ~size & 0xff;
    header[4] = (~size >> 8) & 0xff;
    blocks.push(header, data.subarray(offset, offset + size));
    offset += size;
  } while (offset < data.length);
  const tail = new Uint8Array(4);
  new DataView(tail.buffer).setUint32(0, adler32(data));
  blocks.push(tail);
  return concatBytes(blocks);
}

export interface PngImage {
  width: number;
  height: number;
  /** 0 grayscale, 2 RGB. */
  colorType: 0 | 2;
  bitDepth: 1 | 8;
  /** Raw scanlines without filter bytes. */
  rows: Uint8Array[];
}

export function encodePng(image: PngImage): Uint8Array {
  const ihdr = new Uint8Array(13);
  const view = new DataView(ihdr.buffer);
  view.setUint32(0, image.width);
  view.setUint32(4, image.height);
  ihdr[8] = image.bitDepth;
  ihdr[9] = image.colorType;
  const raw = concatBytes(image.rows.map((row) => concatBytes([Uint8Array.of(0), row])));
  return concatBytes([
    Uint8Array.of(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlibStored(raw)),
    chunk("IEND", new Uint8Array(0)),
  ]);
}

const PLAN_W = 256;
const PLAN_H = 192;

/** 256 x 192, 1-bit plan preview: black walls on white. */
export function writePlanPng(model: CaptureModel): Uint8Array {
  const pixels = new Uint8Array(PLAN_W * PLAN_H).fill(1); // 1 = white
  const bounds = planBounds(model);
  const margin = 16;
  const scale = Math.min(
    (PLAN_W - margin * 2) / (bounds.maxX - bounds.minX),
    (PLAN_H - margin * 2) / (bounds.maxZ - bounds.minZ),
  );
  const px = (x: number) => Math.round(margin + (x - bounds.minX) * scale);
  const py = (z: number) => Math.round(margin + (bounds.maxZ - z) * scale);
  const set = (x: number, y: number, value: number) => {
    if (x >= 0 && x < PLAN_W && y >= 0 && y < PLAN_H) {
      pixels[y * PLAN_W + x] = value;
    }
  };
  const draw = (x0: number, y0: number, x1: number, y1: number, value: number) => {
    const dx = Math.abs(x1 - x0);
    const dy = -Math.abs(y1 - y0);
    const sx = x0 < x1 ? 1 : -1;
    const sy = y0 < y1 ? 1 : -1;
    let error = dx + dy;
    let x = x0;
    let y = y0;
    for (;;) {
      set(x, y, value);
      set(x + 1, y, value);
      set(x, y + 1, value);
      if (x === x1 && y === y1) {
        break;
      }
      const doubled = 2 * error;
      if (doubled >= dy) {
        error += dy;
        x += sx;
      }
      if (doubled <= dx) {
        error += dx;
        y += sy;
      }
    }
  };
  for (const wall of model.walls) {
    draw(px(wall.start[0]), py(wall.start[2]), px(wall.end[0]), py(wall.end[2]), 0);
  }
  // Open doors and passages: white gaps in the wall line.
  const wallsById = new Map(model.walls.map((wall) => [wall.id, wall]));
  for (const opening of [...model.doors, ...model.openings]) {
    const wall = wallsById.get(opening.wallId);
    if (wall === undefined) {
      continue;
    }
    const dx = wall.end[0] - wall.start[0];
    const dz = wall.end[2] - wall.start[2];
    const length = Math.hypot(dx, dz);
    const at = (distance: number): [number, number] => [
      wall.start[0] + (dx * distance) / length,
      wall.start[2] + (dz * distance) / length,
    ];
    const from = at(opening.offsetM - opening.widthM / 2);
    const to = at(opening.offsetM + opening.widthM / 2);
    draw(px(from[0]), py(from[1]), px(to[0]), py(to[1]), 1);
  }
  const rows: Uint8Array[] = [];
  for (let y = 0; y < PLAN_H; y += 1) {
    const row = new Uint8Array(PLAN_W / 8);
    for (let x = 0; x < PLAN_W; x += 1) {
      if (pixels[y * PLAN_W + x] === 1) {
        const index = x >> 3;
        row[index] = (row[index] ?? 0) | (0x80 >> (x & 7));
      }
    }
    rows.push(row);
  }
  return encodePng({ width: PLAN_W, height: PLAN_H, colorType: 0, bitDepth: 1, rows });
}

/** 4 x 4 RGB material texture (a plain checker, generated pixels). */
export function writeTexturePng(): Uint8Array {
  const rows: Uint8Array[] = [];
  for (let y = 0; y < 4; y += 1) {
    const row = new Uint8Array(12);
    for (let x = 0; x < 4; x += 1) {
      const light = (x + y) % 2 === 0;
      row.set(light ? [214, 208, 196] : [188, 182, 170], x * 3);
    }
    rows.push(row);
  }
  return encodePng({ width: 4, height: 4, colorType: 2, bitDepth: 8, rows });
}
