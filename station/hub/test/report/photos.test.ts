// Site photo reduction (spec 11.1 photos.test.ts): upright by EXIF orientation, 356 x 444 px,
// no EXIF or GPS in the output, deterministic, undecodable bytes give no image.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import sharp from "sharp";
import { PHOTO_FULL, PHOTO_SMALL, reducePhoto, shrinkPhoto } from "../../src/report/photos.js";

/** A 400 x 300 JPEG, left half red and right half blue, with orientation 6 and GPS EXIF. */
async function sidewaysPhoto(): Promise<Buffer> {
  const half = (r: number, b: number) =>
    sharp({ create: { width: 200, height: 300, channels: 3, background: { r, g: 0, b } } })
      .png()
      .toBuffer();
  const [red, blue] = await Promise.all([half(220, 0), half(0, 220)]);
  return sharp({ create: { width: 400, height: 300, channels: 3, background: "#000" } })
    .composite([
      { input: red, left: 0, top: 0 },
      { input: blue, left: 200, top: 0 },
    ])
    .jpeg({ quality: 90 })
    .toBuffer()
    .then((plain) =>
      sharp(plain)
        .withMetadata({ orientation: 6 })
        .withExifMerge({
          IFD0: { Make: "Apple", Model: "iPhone 16 Pro" },
          IFD3: {
            GPSLatitudeRef: "N",
            GPSLatitude: "40/1 47/1 3000/100",
            GPSLongitudeRef: "W",
            GPSLongitude: "73/1 58/1 4000/100",
          },
        })
        .jpeg({ quality: 90 })
        .toBuffer(),
    );
}

/** True when an EXIF block has a GPS IFD pointer (tag 0x8825, either byte order). */
const hasGpsPointer = (exif: Buffer) =>
  exif.includes(Buffer.from([0x88, 0x25])) || exif.includes(Buffer.from([0x25, 0x88]));

async function pixel(jpeg: Uint8Array, x: number, y: number): Promise<[number, number, number]> {
  const { data, info } = await sharp(jpeg).raw().toBuffer({ resolveWithObject: true });
  const at = (y * info.width + x) * info.channels;
  return [data[at] as number, data[at + 1] as number, data[at + 2] as number];
}

describe("photo reduction", () => {
  it("has the source EXIF this test relies on", async () => {
    const source = await sidewaysPhoto();
    const meta = await sharp(source).metadata();
    assert.equal(meta.orientation, 6);
    assert.deepEqual([meta.width, meta.height], [400, 300]);
    assert.ok(meta.exif !== undefined && hasGpsPointer(meta.exif));
    assert.ok(source.includes(Buffer.from("iPhone 16 Pro", "latin1")));
  });

  it("turns an orientation-6 photo upright and crops it to 356 x 444 px", async () => {
    const reduced = await reducePhoto(await sidewaysPhoto());
    assert.ok(reduced !== undefined);
    const meta = await sharp(reduced).metadata();
    assert.deepEqual([meta.width, meta.height, meta.format], [356, 444, "jpeg"]);
    // Rotated 90° clockwise: the red left half is now on top, the blue right half below.
    const top = await pixel(reduced, 178, 10);
    const bottom = await pixel(reduced, 178, 434);
    assert.ok(top[0] > 150 && top[2] < 80, `top ${top}`);
    assert.ok(bottom[2] > 150 && bottom[0] < 80, `bottom ${bottom}`);
  });

  it("writes no EXIF, GPS, ICC or XMP and no orientation", async () => {
    const reduced = await reducePhoto(await sidewaysPhoto());
    assert.ok(reduced !== undefined);
    const meta = await sharp(reduced).metadata();
    assert.equal(meta.exif, undefined);
    assert.equal(meta.icc, undefined);
    assert.equal(meta.xmp, undefined);
    assert.equal(meta.orientation, undefined);
    const bytes = Buffer.from(reduced);
    assert.equal(bytes.includes(Buffer.from("Exif\0\0", "latin1")), false);
    assert.equal(bytes.includes(Buffer.from("iPhone", "latin1")), false);
    assert.equal(meta.isProgressive, false);
    assert.equal(meta.chromaSubsampling, "4:2:0");
  });

  it("gives the same bytes twice", async () => {
    const source = await sidewaysPhoto();
    const [a, b] = [await reducePhoto(source), await reducePhoto(source)];
    assert.ok(a !== undefined && b !== undefined);
    assert.equal(Buffer.compare(Buffer.from(a), Buffer.from(b)), 0);
  });

  it("reads PNG too", async () => {
    const png = await sharp({
      create: { width: 900, height: 600, channels: 4, background: "#6b6557" },
    })
      .png()
      .toBuffer();
    const reduced = await reducePhoto(png);
    assert.ok(reduced !== undefined);
    const meta = await sharp(reduced).metadata();
    assert.deepEqual([meta.width, meta.height, meta.format], [356, 444, "jpeg"]);
  });

  it("gives no image for bytes that are not a photo (the page shows the placeholder)", async () => {
    assert.equal(await reducePhoto(Buffer.from("not a photo at all")), undefined);
    assert.equal(await reducePhoto(new Uint8Array(0)), undefined);
    // An ISO-BMFF header with a HEIF brand but no image: the HEIC path gives up too.
    const fakeHeic = Buffer.concat([
      Buffer.from([0, 0, 0, 24]),
      Buffer.from("ftypheic", "latin1"),
      Buffer.alloc(64, 7),
    ]);
    assert.equal(await reducePhoto(fakeHeic), undefined);
  });

  it("re-reduces to 267 x 333 px at quality 70 for the size budget", async () => {
    const reduced = await reducePhoto(await sidewaysPhoto(), PHOTO_FULL);
    assert.ok(reduced !== undefined);
    const smaller = await shrinkPhoto(reduced, PHOTO_SMALL);
    assert.ok(smaller !== undefined);
    const meta = await sharp(smaller).metadata();
    assert.deepEqual([meta.width, meta.height], [267, 333]);
    assert.ok(smaller.byteLength < reduced.byteLength);
    assert.equal(await shrinkPhoto(Buffer.from("broken")), undefined);
  });
});
