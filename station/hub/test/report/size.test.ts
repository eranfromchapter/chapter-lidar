// Report size (spec 11.1 size.test.ts, SR-AC9): 40 rooms with 10 full-size photos each stay
// under the HUB's 45 MiB within 60 s; over the photo budget the photos are reduced again, and
// past that the photo pages are left out with the footnote.

import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import sharp from "sharp";
import { loadReportSources, type SourceFile } from "../../src/report/sources.js";
import { renderSpatialReport } from "../../src/report/index.js";
import { WORDS } from "../../src/report/words.js";
import { squash } from "../helpers.js";
import { captureIdOf, namedRooms, pageTexts, syntheticInput, syntheticRecord } from "./support.js";

const MIB = 1024 * 1024;
let photo: Buffer;

/** A 4032 x 3024 phone-sized JPEG with texture (it does not shrink to nothing). */
async function phonePhoto(): Promise<Buffer> {
  return sharp({
    create: {
      width: 4032,
      height: 3024,
      channels: 3,
      background: "#8a7f70",
      noise: { type: "gaussian", mean: 128, sigma: 40 },
    },
  })
    .jpeg({ quality: 85 })
    .toBuffer();
}

function photoFiles(rooms: number, perRoom: number): SourceFile[] {
  return Array.from({ length: rooms * perRoom }, (_, i) => {
    const room = Math.floor(i / perRoom);
    return {
      path: `Photos/floor-1/room-${room + 1}-${(i % perRoom) + 1}.jpg`,
      role: "photo",
      captureId: captureIdOf(0),
      areaKey: "floor-1",
      photo: {
        room: `Bedroom ${room + 1}`,
        direction: "N" as const,
        subject: "general" as const,
        takenAt: `2026-10-17T14:${String(Math.floor(i / 60) % 60).padStart(2, "0")}:${String(i % 60).padStart(2, "0")}Z`,
      },
    };
  });
}

async function sources(rooms: number, perRoom: number, photoBudgetBytes?: number) {
  return loadReportSources(
    {
      files: photoFiles(rooms, perRoom),
      captureRecord: syntheticRecord([
        { captureId: captureIdOf(0), label: "Floor 1", areaKey: "floor-1" },
      ]),
      readFile: async () => photo,
    },
    photoBudgetBytes === undefined ? {} : { photoBudgetBytes },
  );
}

before(async () => {
  photo = await phonePhoto();
  assert.ok(photo.byteLength > 2 * MIB, `${photo.byteLength} bytes`);
});

describe("report size", () => {
  it("keeps 40 rooms x 10 photos under 45 MiB, rendered within 60 s", async (t) => {
    const started = Date.now();
    const loaded = await sources(40, 10);
    assert.equal(loaded.photosOmitted, false);
    assert.equal(loaded.photos.length, 400);
    const input = syntheticInput([{ label: "Floor 1", rooms: namedRooms(40) }], {
      photos: loaded.photos,
    });
    const report = await renderSpatialReport(input);
    const seconds = (Date.now() - started) / 1000;
    t.diagnostic(
      `${report.pages} pages, ${(report.bytes.byteLength / MIB).toFixed(1)} MiB, ${seconds.toFixed(1)} s`,
    );
    assert.ok(report.bytes.byteLength < 45 * MIB, `${report.bytes.byteLength} bytes`);
    assert.ok(seconds < 60, `${seconds} s`);
    // Each room: a room page and its 10 photos on one photo page.
    assert.ok(report.pages >= 1 + 40 * 2, String(report.pages));
  });

  it("reduces every photo again (267 x 333, quality 70) over the photo budget", async () => {
    const full = await sources(2, 10);
    const fullBytes = full.photos.reduce((n, p) => n + (p.image?.byteLength ?? 0), 0);
    // A budget the full-size photos exceed by one byte.
    const loaded = await sources(2, 10, fullBytes + 2 * MIB - 1);
    assert.equal(loaded.photosOmitted, false);
    assert.equal(loaded.photos.length, 20);
    for (const reduced of loaded.photos) {
      const meta = await sharp(reduced.image).metadata();
      assert.deepEqual([meta.width, meta.height], [267, 333]);
    }
  });

  it("leaves the photo pages out with the footnote when even the small photos are too large", async () => {
    const loaded = await sources(2, 10, 2 * MIB + 1000);
    assert.equal(loaded.photosOmitted, true);
    assert.equal(loaded.photos.length, 0);
    const input = syntheticInput([{ label: "Floor 1", rooms: namedRooms(2) }], {
      photos: loaded.photos,
      photosOmitted: true,
    });
    const report = await renderSpatialReport(input);
    const texts = await pageTexts(report.bytes);
    const rooms = texts.filter(
      (text) => squash(text).includes("ROOM1OF2") || squash(text).includes("ROOM2OF2"),
    );
    assert.equal(rooms.length, 2);
    for (const text of rooms) {
      assert.ok(squash(text).includes(squash(WORDS.photosOmittedFootnote)));
    }
    // No photo page ("{room} · site photos"), and the contents say where the photos are.
    assert.equal(
      texts.some((text) => squash(text).includes("·sitephotos")),
      false,
    );
    assert.ok(squash(texts[1] ?? "").includes(squash(WORDS.contentsNoteNoPhotos)));
  });
});
