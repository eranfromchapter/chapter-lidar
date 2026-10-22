// Site photo reduction for the report (spec 5.6.6): decoded (JPEG, PNG, HEIC/HEIF), turned
// upright by its EXIF orientation, converted to sRGB, cropped to 4:5 from the centre, encoded as
// a baseline JPEG with no metadata at all (EXIF and GPS are never copied: sharp writes none
// unless asked). One photo at a time; only the reduced bytes are kept.
//
// sharp's prebuilt libvips cannot decode HEVC, which iPhones write as HEIC; those photos are
// decoded with heic-decode (libheif in WebAssembly), which applies the HEIF rotation, and then
// reduced by sharp from the raw pixels.

import decodeHeic from "heic-decode";
import sharp from "sharp";

sharp.concurrency(1);

export interface PhotoSize {
  readonly width: number;
  readonly height: number;
  readonly quality: number;
}

/** 128 x 160 pt at 200 dpi, quality 80. */
export const PHOTO_FULL: PhotoSize = { width: 356, height: 444, quality: 80 };
/** 150 dpi, quality 70: the first step of the size budget. */
export const PHOTO_SMALL: PhotoSize = { width: 267, height: 333, quality: 70 };

function pipeline(image: ReturnType<typeof sharp>, size: PhotoSize): Promise<Buffer> {
  return image
    .resize(size.width, size.height, { fit: "cover", position: "centre" })
    .toColourspace("srgb")
    .jpeg({ quality: size.quality, chromaSubsampling: "4:2:0", progressive: false, mozjpeg: false })
    .toBuffer();
}

function isHeif(bytes: Uint8Array): boolean {
  // ISO base media file: "ftyp" at offset 4 with a HEIF brand.
  if (bytes.length < 12) {
    return false;
  }
  const box = Buffer.from(bytes.subarray(4, 12)).toString("latin1");
  return (
    box.startsWith("ftyp") && /^(heic|heix|hevc|hevx|heim|heis|mif1|msf1)$/.test(box.slice(4, 8))
  );
}

/** The reduced JPEG of a photo, or undefined when it cannot be decoded. */
export async function reducePhoto(
  bytes: Uint8Array,
  size: PhotoSize = PHOTO_FULL,
): Promise<Uint8Array | undefined> {
  try {
    return await pipeline(sharp(bytes, { failOn: "error" }).rotate(), size);
  } catch {
    // Fall through: HEIC with HEVC, or not a photo.
  }
  if (!isHeif(bytes)) {
    return undefined;
  }
  try {
    const image = await decodeHeic({ buffer: bytes });
    const raw = Buffer.from(image.data.buffer, image.data.byteOffset, image.data.byteLength);
    return await pipeline(
      sharp(raw, { raw: { width: image.width, height: image.height, channels: 4 } }),
      size,
    );
  } catch {
    return undefined;
  }
}

/** Re-reduces an already reduced photo to a smaller size. */
export async function shrinkPhoto(
  reduced: Uint8Array,
  size: PhotoSize = PHOTO_SMALL,
): Promise<Uint8Array | undefined> {
  try {
    return await pipeline(sharp(reduced), size);
  } catch {
    return undefined;
  }
}
