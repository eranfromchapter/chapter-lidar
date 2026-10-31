// The sketch file as sent to POST /v1/sketch-interpretations: strict base64, the media types
// the Claude API accepts (four image types and PDF), and the size reported as `image` in the
// interpretation, read from the file header (no image or PDF library, no decoding of pixels).
//
// - An image's size is the stored pixel size (JPEG SOF, PNG IHDR, GIF screen, WebP
//   VP8/VP8L/VP8X). A JPEG EXIF orientation is not applied: the app sends upright pixels.
// - A PDF's size is its first page in points, best effort (see pdfPageSize).

/** Image media types the Claude API accepts for an image block. HEIC is not one: the app converts it. */
export const SKETCH_IMAGE_MEDIA_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
] as const;
export type SketchImageMediaType = (typeof SKETCH_IMAGE_MEDIA_TYPES)[number];

/** A whole PDF, sent to Claude as a document block. */
export const PDF_MEDIA_TYPE = "application/pdf";

/** Every media type the route accepts; anything else answers 415. */
export const SKETCH_MEDIA_TYPES = [...SKETCH_IMAGE_MEDIA_TYPES, PDF_MEDIA_TYPE] as const;
export type SketchMediaType = (typeof SKETCH_MEDIA_TYPES)[number];

/** Largest decoded image (spec F16 §3: at most 10 MB). */
export const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

/** Base64 length of a MAX_IMAGE_BYTES image. */
export const MAX_IMAGE_BASE64_LENGTH = Math.ceil(MAX_IMAGE_BYTES / 3) * 4;

/**
 * Largest decoded PDF: 24 MB (decimal). In base64 that is 32 000 000 characters (30.5 MiB), so
 * the request to Claude, with the system prompt and the schema, stays under the Messages API's
 * 32 MB request limit.
 */
export const MAX_PDF_BYTES = 24_000_000;

/** Base64 length of a MAX_PDF_BYTES document. */
export const MAX_PDF_BASE64_LENGTH = Math.ceil(MAX_PDF_BYTES / 3) * 4;

/** Largest decoded file of a media type. */
export function maxBytes(mediaType: SketchMediaType): number {
  return mediaType === PDF_MEDIA_TYPE ? MAX_PDF_BYTES : MAX_IMAGE_BYTES;
}

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
export function imageSize(bytes: Buffer, mediaType: SketchImageMediaType): ImageSize | null {
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

/** US Letter in points: the size reported when a PDF's first page size cannot be read. */
export const PDF_FALLBACK_PAGE: ImageSize = { width: 612, height: 792 };

/** True when the bytes start with the PDF header `%PDF-`. */
export function isPdf(bytes: Buffer): boolean {
  return bytes.length >= 5 && bytes.toString("latin1", 0, 5) === "%PDF-";
}

const MEDIA_BOX = Buffer.from("/MediaBox", "latin1");
const NUMBER = String.raw`[+-]?(?:\d+\.?\d*|\.\d+)`;
const MEDIA_BOX_ARRAY = new RegExp(
  String.raw`^\s*\[\s*(${NUMBER})\s+(${NUMBER})\s+(${NUMBER})\s+(${NUMBER})\s*\]`,
);

/**
 * First page size of a PDF in points (rounded), best effort: the first `/MediaBox` written as a
 * direct array of four numbers, in file order. It is not a PDF parser, so the size can be
 * another page's, or an inherited box of the page tree, and `/Rotate`, `/CropBox` and
 * `/UserUnit` are not applied. Page dictionaries inside compressed object streams (common since
 * PDF 1.5) and a `/MediaBox` given as an indirect reference are not read; then, or when no box
 * gives a positive size, the answer is PDF_FALLBACK_PAGE (US Letter, 612 x 792). The size only
 * labels the interpretation: the reading's coordinates do not depend on it.
 */
export function pdfPageSize(bytes: Buffer): ImageSize {
  let at = bytes.indexOf(MEDIA_BOX);
  while (at !== -1) {
    const start = at + MEDIA_BOX.length;
    const match = MEDIA_BOX_ARRAY.exec(bytes.toString("latin1", start, start + 200));
    if (match !== null) {
      const [x0, y0, x1, y1] = match.slice(1, 5).map(Number) as [number, number, number, number];
      const width = Math.round(Math.abs(x1 - x0));
      const height = Math.round(Math.abs(y1 - y0));
      const size =
        Number.isSafeInteger(width) && Number.isSafeInteger(height) ? sized(width, height) : null;
      if (size !== null) {
        return size;
      }
    }
    at = bytes.indexOf(MEDIA_BOX, start);
  }
  return PDF_FALLBACK_PAGE;
}
