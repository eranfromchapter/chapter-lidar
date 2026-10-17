// Tiny baseline JPEG encoder for generated site photos. Grayscale, 8x8 blocks that carry only a
// DC coefficient (flat blocks), so the file is a few hundred bytes. JFIF header, no EXIF and no
// location data. Quantisation step 8 makes the DC value equal to (pixel - 128).

import { mulberry32, concatBytes } from "../util.js";

const DC_BITS = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0];
const DC_VALS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
// Only the end-of-block symbol is ever written, so the AC table holds that single symbol.
const AC_BITS = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
const AC_VALS = [0x00];

function buildCodes(bits: number[], vals: number[]): Map<number, { code: number; length: number }> {
  const codes = new Map<number, { code: number; length: number }>();
  let code = 0;
  let index = 0;
  for (let length = 1; length <= 16; length += 1) {
    for (let i = 0; i < (bits[length - 1] as number); i += 1) {
      codes.set(vals[index] as number, { code, length });
      code += 1;
      index += 1;
    }
    code <<= 1;
  }
  return codes;
}

class BitWriter {
  private readonly bytes: number[] = [];
  private buffer = 0;
  private count = 0;

  write(value: number, length: number): void {
    for (let i = length - 1; i >= 0; i -= 1) {
      this.buffer = (this.buffer << 1) | ((value >> i) & 1);
      this.count += 1;
      if (this.count === 8) {
        this.bytes.push(this.buffer);
        if (this.buffer === 0xff) {
          this.bytes.push(0x00);
        }
        this.buffer = 0;
        this.count = 0;
      }
    }
  }

  finish(): number[] {
    while (this.count !== 0) {
      this.write(1, 1);
    }
    return this.bytes;
  }
}

function segment(marker: number, payload: number[]): Uint8Array {
  const length = payload.length + 2;
  return Uint8Array.from([0xff, marker, length >> 8, length & 0xff, ...payload]);
}

/**
 * Encodes a width x height grayscale image from flat 8x8 blocks.
 * `blocks` has (width / 8) * (height / 8) pixel values in 0..255.
 */
export function encodeFlatJpeg(
  width: number,
  height: number,
  blocks: readonly number[],
): Uint8Array {
  const dcCodes = buildCodes(DC_BITS, DC_VALS);
  const acCodes = buildCodes(AC_BITS, AC_VALS);
  const eob = acCodes.get(0) as { code: number; length: number };
  const writer = new BitWriter();
  let previous = 0;
  for (const pixel of blocks) {
    const dc = pixel - 128;
    const diff = dc - previous;
    previous = dc;
    const magnitude = Math.abs(diff);
    const size = magnitude === 0 ? 0 : Math.floor(Math.log2(magnitude)) + 1;
    const entry = dcCodes.get(size) as { code: number; length: number };
    writer.write(entry.code, entry.length);
    if (size > 0) {
      writer.write(diff >= 0 ? diff : diff + (1 << size) - 1, size);
    }
    writer.write(eob.code, eob.length);
  }
  const scan = Uint8Array.from(writer.finish());
  return concatBytes([
    Uint8Array.of(0xff, 0xd8),
    segment(0xe0, [0x4a, 0x46, 0x49, 0x46, 0x00, 1, 1, 0, 0, 1, 0, 1, 0, 0]),
    segment(0xdb, [0x00, ...new Array<number>(64).fill(8)]),
    segment(0xc0, [8, height >> 8, height & 0xff, width >> 8, width & 0xff, 1, 1, 0x11, 0]),
    segment(0xc4, [0x00, ...DC_BITS, ...DC_VALS]),
    segment(0xc4, [0x10, ...AC_BITS, ...AC_VALS]),
    segment(0xda, [1, 1, 0x00, 0, 63, 0]),
    scan,
    Uint8Array.of(0xff, 0xd9),
  ]);
}

/** A 64 x 48 photo-like image (soft gradient and a few seeded blocks) from a seed. */
export function generatePhoto(seed: number): Uint8Array {
  const next = mulberry32(seed);
  const cols = 8;
  const rows = 6;
  const blocks: number[] = [];
  for (let r = 0; r < rows; r += 1) {
    for (let c = 0; c < cols; c += 1) {
      const base = 90 + c * 12 + r * 6;
      blocks.push(Math.min(235, Math.max(20, Math.round(base + (next() - 0.5) * 24))));
    }
  }
  return encodeFlatJpeg(cols * 8, rows * 8, blocks);
}
