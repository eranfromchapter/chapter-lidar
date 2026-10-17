// Small deterministic helpers shared by every generator module.

import { createHash } from "node:crypto";

export type V3 = [number, number, number];
export type P2 = [number, number];

/** Rounds to 1e-6 (one micrometre) so computed coordinates print as short decimals. */
export function round6(value: number): number {
  const rounded = Math.round(value * 1e6) / 1e6;
  return rounded === 0 ? 0 : rounded;
}

/** Rounds to 1e-4 (0.1 mm in metres). */
export function round4(value: number): number {
  const rounded = Math.round(value * 1e4) / 1e4;
  return rounded === 0 ? 0 : rounded;
}

/**
 * Shortest decimal that reads back as the same IEEE float32, as a double. Swift's JSONEncoder
 * writes Float values this way, so raw RoomPlan fixtures look like device output.
 */
export function float32Short(value: number): number {
  const target = Math.fround(value);
  if (target === 0) {
    return 0;
  }
  for (let digits = 1; digits <= 9; digits += 1) {
    const candidate = Number(target.toPrecision(digits));
    if (Math.fround(candidate) === target) {
      return candidate;
    }
  }
  return target;
}

export function sha256Hex(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Lowercase RFC 9562 version 4 UUID derived from a seed string. Same seed, same UUID. */
export function uuidFrom(seed: string): string {
  const digest = createHash("sha256").update(`chapter-fixtures:${seed}`).digest();
  const bytes = Uint8Array.from(digest.subarray(0, 16));
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x40;
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80;
  const hex = Buffer.from(bytes).toString("hex");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join("-");
}

/** Seeded 32-bit generator (mulberry32). Returns numbers in [0, 1). */
export function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** 32-bit seed from a string. */
export function seedFrom(text: string): number {
  return createHash("sha256").update(text).digest().readUInt32LE(0);
}

export function utf8(text: string): Uint8Array {
  return new Uint8Array(Buffer.from(text, "utf8"));
}

export function latin1(text: string): Uint8Array {
  return new Uint8Array(Buffer.from(text, "latin1"));
}

export function concatBytes(parts: readonly Uint8Array[]): Uint8Array {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

/** Fixed-decimal text, never "-0.000". */
export function fixed(value: number, decimals: number): string {
  const text = value.toFixed(decimals);
  return /^-0(\.0+)?$/.test(text) ? text.slice(1) : text;
}

/** Plan point (x, z) of a 3D point. */
export function plan(point: V3): P2 {
  return [point[0], point[2]];
}

export function dist2(a: P2, b: P2): number {
  return Math.hypot(b[0] - a[0], b[1] - a[1]);
}

/** Narrows an array to the tuple types generated for schema minItems constraints. */
export function atLeast<T>(items: T[], min: 1): [T, ...T[]];
export function atLeast<T>(items: T[], min: 2): [T, T, ...T[]];
export function atLeast<T>(items: T[], min: 3): [T, T, T, ...T[]];
export function atLeast<T>(items: T[], min: number): T[] {
  if (items.length < min) {
    throw new Error(`Expected at least ${min} items, got ${items.length}`);
  }
  return items;
}
