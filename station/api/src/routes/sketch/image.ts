// The sketch photo as sent to POST /v1/sketch-interpretations: strict base64, the media types
// the Claude API accepts, and the pixel size read from the image header (no image library, no
// decoding of the pixels).
//
// The size is the stored pixel size (JPEG SOF, PNG IHDR, GIF screen, WebP VP8/VP8L/VP8X). A
// JPEG EXIF orientation is not applied: the app sends upright pixels.

/** Media types the Claude API accepts for an image block. HEIC is not one: the app converts it. */
export const SKETCH_MEDIA_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif"] as const;
export type SketchMediaType = (typeof SKETCH_MEDIA_TYPES)[number];

/** Largest decoded image (spec F16 §3: at most 10 MB). */
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

/** Base64 length of a MAX_IMAGE_BYTES image. */
export const MAX_IMAGE_BASE64_LENGTH = Math.ceil(MAX_IMAGE_BYTES / 3) * 4;

export function isSketchMediaType(value: string): value is SketchMediaType {
  return (SKETCH_MEDIA_TYPES as readonly string[]).includes(value);
}

const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/;

/** Decoded size of canonical base64 text, or null when it is not canonical base64. */
export function base64DecodedLength(data: string): number | null {
  if (data.length === 0 || data.length % 4 !== 0 || !BASE64.test(data)) {
    return null;
  }
  const padding = data.endsWith("==") ? 2 : data.endsWith("=") ? 1 : 0;
  return (data.length / 4) * 3 - padding;
}

export interface ImageSize {
  readonly width: number;
  readonly height: number;
}

function sized(width: number, height: number): ImageSize | null {
  return width >= 1 && height >= 1 ? { width, height } : null;
}

function pngSize(bytes: Buffer): ImageSize | null {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 24 || signature.some((byte, index) => bytes[index] !== byte)) {
    return null;
  }
  if (bytes.toString("latin1", 12, 16) !== "IHDR") {
    return null;
  }
  return sized(bytes.readUInt32BE(16), bytes.readUInt32BE(20));
}

function gifSize(bytes: Buffer): ImageSize | null {
  const header = bytes.toString("latin1", 0, 6);
  if (bytes.length < 10 || (header !== "GIF87a" && header !== "GIF89a")) {
    return null;
  }
  return sized(bytes.readUInt16LE(6), bytes.readUInt16LE(8));
}

/** Start-of-frame markers (baseline, progressive, lossless, arithmetic); not DHT C4, JPG C8, DAC CC. */
const JPEG_SOF = new Set([
  0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf,
]);

function jpegSize(bytes: Buffer): ImageSize | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
    return null;
  }
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] !== 0xff) {
      return null;
    }
    // Fill bytes: any number of 0xFF before the marker code.
    while (offset < bytes.length && bytes[offset] === 0xff) {
      offset += 1;
    }
    const marker = bytes[offset];
    offset += 1;
    if (marker === undefined) {
      return null;
    }
    // Standalone markers carry no length.
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) {
      continue;
    }
    if (marker === 0xd9 || marker === 0xda || offset + 2 > bytes.length) {
      // End of image or start of scan before any frame header.
      return null;
    }
    const length = bytes.readUInt16BE(offset);
    if (length < 2) {
      return null;
    }
    if (JPEG_SOF.has(marker)) {
      if (offset + 7 > bytes.length) {
        return null;
      }
      return sized(bytes.readUInt16BE(offset + 5), bytes.readUInt16BE(offset + 3));
    }
    offset += length;
  }
  return null;
}

function webpSize(bytes: Buffer): ImageSize | null {
  if (
    bytes.length < 30 ||
    bytes.toString("latin1", 0, 4) !== "RIFF" ||
    bytes.toString("latin1", 8, 12) !== "WEBP"
  ) {
    return null;
  }
  const chunk = bytes.toString("latin1", 12, 16);
  if (chunk === "VP8 ") {
    // Frame tag (3 bytes), start code 9d 01 2a, then 14-bit width and height.
    if (bytes[23] !== 0x9d || bytes[24] !== 0x01 || bytes[25] !== 0x2a) {
      return null;
    }
    return sized(bytes.readUInt16LE(26) & 0x3fff, bytes.readUInt16LE(28) & 0x3fff);
  }
  if (chunk === "VP8L") {
    if (bytes[20] !== 0x2f) {
      return null;
    }
    const bits = bytes.readUInt32LE(21);
    return sized((bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1);
  }
  if (chunk === "VP8X") {
    return sized(bytes.readUIntLE(24, 3) + 1, bytes.readUIntLE(27, 3) + 1);
  }
  return null;
}

/** Pixel size from the image header, or null when the bytes are not an image of that type. */
export function imageSize(bytes: Buffer, mediaType: SketchMediaType): ImageSize | null {
  switch (mediaType) {
    case "image/jpeg":
      return jpegSize(bytes);
    case "image/png":
      return pngSize(bytes);
    case "image/gif":
      return gifSize(bytes);
    case "image/webp":
      return webpSize(bytes);
  }
}
