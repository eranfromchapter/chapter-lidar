// Shared parser result type and byte helpers.

export type ParseResult<T> = { ok: true; value: T } | { ok: false; reason: string };

export function fail<T>(reason: string): ParseResult<T> {
  return { ok: false, reason };
}

export function ok<T>(value: T): ParseResult<T> {
  return { ok: true, value };
}

/** ASCII text of a byte range (non-ASCII bytes map to their Latin-1 characters). */
export function ascii(bytes: Uint8Array, start: number, length: number): string {
  let out = "";
  const end = Math.min(bytes.length, start + length);
  for (let i = start; i < end; i += 1) {
    out += String.fromCharCode(bytes[i] as number);
  }
  return out;
}

/** True when `needle` occurs in bytes[from, to). */
export function containsAscii(
  bytes: Uint8Array,
  needle: string,
  from = 0,
  to = bytes.length,
): boolean {
  const n = needle.length;
  outer: for (let i = Math.max(0, from); i + n <= Math.min(to, bytes.length); i += 1) {
    for (let k = 0; k < n; k += 1) {
      if (bytes[i + k] !== needle.charCodeAt(k)) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}

export function view(bytes: Uint8Array): DataView {
  return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
}
