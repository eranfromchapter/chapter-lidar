// Pagination (spec 11.1 paginate.test.ts): the 424 page list, the contents page, room item
// continuation, photo pages, checks continuation, the schedule split and the page index.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Finding, Verdict } from "@chapter/capture-contract";
import type { ReportPhoto } from "../../src/report/input.js";
import { PageIndex, type PageSpec } from "../../src/report/pages/index-of-pages.js";
import { checkBlockCounts } from "../../src/report/pages/checks.js";
import {
  captureIdOf,
  input424,
  layoutOf,
  manyObjects,
  namedRooms,
  syntheticInput,
  testCanvas,
  verdict424,
  type SyntheticRoom,
} from "./support.js";

const kinds = (pages: readonly PageSpec[]) =>
  pages.map((page) =>
    page.kind === "room" || (page.kind === "photos" && page.room !== undefined)
      ? `${page.kind}${page.room}`
      : page.kind,
  );

/** Runs of equal kinds collapsed: ["checks", "checks"] -> ["checks*2"]. */
function collapsed(list: readonly string[]): string[] {
  const out: string[] = [];
  for (const item of list) {
    const last = out[out.length - 1];
    const [name, count] = (last ?? "").split("*");
    if (name === item) {
      out[out.length - 1] = `${item}*${Number(count ?? 1) + 1}`;
    } else {
      out.push(item);
    }
  }
  return out;
}

describe("the 424 sample", () => {
  it("has cover, contents, plan, schedule, checks, then each room with its photos, then the record", async () => {
    const { pages } = layoutOf(await input424("limited"));
    const list = collapsed(kinds(pages));
    const rooms = Array.from({ length: 12 }, (_, i) => [`room${i + 1}`, `photos${i + 1}`]).flat();
    assert.deepEqual(list.slice(0, 4), ["cover", "contents", "plan", "schedule"]);
    assert.match(list[4] ?? "", /^checks(\*\d+)?$/);
    assert.deepEqual(list.slice(5, 5 + 24), rooms);
    assert.match(list[29] ?? "", /^record(\*\d+)?$/);
    assert.equal(list.length, 30);
  });

  it("gives the same page list for the three outcomes up to the checks", async () => {
    const lists = await Promise.all(
      (["ready", "limited", "blocked"] as const).map(async (outcome) =>
        collapsed(kinds(layoutOf(await input424(outcome)).pages)).map((k) => k.split("*")[0]),
      ),
    );
    assert.deepEqual(lists[0], lists[1]);
    assert.deepEqual(lists[1], lists[2]);
  });

  it("indexes the page numbers the contents, schedule and cover print", async () => {
    const { model, pages } = layoutOf(await input424("limited"));
    const index = new PageIndex(pages);
    const at = (kind: string) => pages.findIndex((page) => page.kind === kind) + 1;
    assert.equal(index.total, pages.length);
    assert.equal(index.checks, at("checks"));
    assert.equal(index.schedule, at("schedule"));
    assert.equal(index.record, at("record"));
    assert.equal(index.contents, at("contents"));
    assert.equal(index.plan(0), at("plan"));
    for (const room of model.rooms) {
      const first = pages.findIndex((p) => p.kind === "room" && p.room === room.number) + 1;
      const last =
        pages.findLastIndex(
          (p) => (p.kind === "room" || p.kind === "photos") && p.room === room.number,
        ) + 1;
      assert.equal(index.room(room.number), first);
      assert.equal(index.roomRange(room.number), last > first ? `${first}–${last}` : `${first}`);
    }
    assert.equal(index.roomRange(1), "10–11");
  });
});

describe("contents", () => {
  it("stays on the first plan page for a small visit", () => {
    const { pages } = layoutOf(syntheticInput([{ label: "Floor 1", rooms: namedRooms(3) }]));
    assert.deepEqual(kinds(pages).slice(0, 3), ["cover", "plan", "schedule"]);
    const plan = pages[1];
    assert.equal(plan?.kind === "plan" ? plan.contents?.length : undefined, 3 + 3);
  });

  it("gets a page of its own for 13 rooms on 2 floors", () => {
    const { pages } = layoutOf(
      syntheticInput([
        { label: "Floor 1", rooms: namedRooms(7, "Upper") },
        { label: "Floor 2", rooms: namedRooms(6, "Lower") },
      ]),
    );
    assert.deepEqual(kinds(pages).slice(0, 5), ["cover", "contents", "plan", "plan", "schedule"]);
    const contents = pages[1];
    assert.ok(contents?.kind === "contents");
    // schedule, checks, 2 floor rows, 13 rooms, record.
    assert.equal(contents.columns.flat().length, 18);
    const plans = pages.filter((page) => page.kind === "plan");
    assert.ok(plans.every((page) => page.kind === "plan" && page.contents === undefined));
  });
});

describe("room pages", () => {
  const roomWith = (items: number, name = "Living room"): SyntheticRoom => ({
    label: name,
    w: 8,
    d: 6,
    objects: manyObjects(items),
  });
  const roomPages = (room: SyntheticRoom) =>
    layoutOf(syntheticInput([{ label: "Floor 1", rooms: [room] }])).pages.filter(
      (page): page is Extract<PageSpec, { kind: "room" }> => page.kind === "room",
    );
  const itemCount = (page: Extract<PageSpec, { kind: "room" }>) =>
    page.lines.filter((line) => line.kind === "item").length;

  it("fits 12 rows on the room page", () => {
    const pages = roomPages(roomWith(12));
    assert.equal(pages.length, 1);
    assert.equal(itemCount(pages[0] as Extract<PageSpec, { kind: "room" }>), 12);
    assert.equal(pages[0]?.note, undefined);
  });

  it("continues 27 items as 12 + 15 rows with both notes", () => {
    const pages = roomPages(roomWith(27));
    assert.deepEqual(pages.map(itemCount), [12, 15]);
    assert.deepEqual(
      pages.map((page) => page.note),
      [
        "Continued on the next page: rows 13 to 27 of 27.",
        "End of item list. Rows 13 to 27 of 27.",
      ],
    );
    assert.deepEqual(
      pages.map((page) => page.first),
      [true, false],
    );
  });

  it("repeats the group row of a group split over pages", () => {
    const pages = roomPages(roomWith(27));
    const second = pages[1];
    assert.deepEqual(
      second?.lines[0]?.kind === "group" ? second.lines[0].continued : undefined,
      true,
    );
  });

  it("spreads 50 items over 3 pages, continuation pages packed by measured height", () => {
    // One group: a continuation page holds title, header, the repeated group row and 20 rows of
    // 15.75 pt above the notes (the 24-row cap is never reached at these heights).
    const chairs: SyntheticRoom = {
      label: "Dining hall",
      w: 10,
      d: 8,
      objects: Array.from({ length: 50 }, () => ({ category: "chair" as const })),
    };
    const pages = roomPages(chairs);
    assert.deepEqual(pages.map(itemCount), [12, 20, 18]);
    assert.equal(pages[0]?.note, "Continued on the next page: rows 13 to 50 of 50.");
    assert.equal(pages[1]?.note, "Continued on the next page: rows 33 to 50 of 50.");
    assert.equal(pages[2]?.note, "End of item list. Rows 33 to 50 of 50.");
  });

  it("never puts more than 24 item rows on a continuation page", () => {
    const pages = roomPages(roomWith(80));
    assert.ok(pages.slice(1).every((page) => itemCount(page) <= 24));
    assert.equal(
      pages.reduce((n, page) => n + itemCount(page), 0),
      80,
    );
  });

  it("lists every item exactly once", () => {
    const pages = roomPages(roomWith(50));
    const items = pages.flatMap((page) =>
      page.lines.flatMap((line) => (line.kind === "item" ? [line.item] : [])),
    );
    assert.equal(new Set(items).size, 50);
    assert.equal(items.length, 50);
  });

  it("keeps a long two-line title and still continues the list", () => {
    const long =
      "Primary bedroom suite with walk-in closet, dressing area and the reading nook by the bay window";
    const pages = roomPages(roomWith(27, long));
    assert.equal(
      pages.reduce((n, page) => n + itemCount(page), 0),
      27,
    );
    assert.ok(pages.length >= 2);
  });

  it("makes one page for a room without items", () => {
    const pages = roomPages({ label: "Closet", w: 1, d: 1.2 });
    assert.equal(pages.length, 1);
    assert.equal(pages[0]?.lines.length, 0);
  });
});

describe("photo pages", () => {
  const photo = (i: number): ReportPhoto => ({
    path: `Photos/floor-1/photo-${String(i).padStart(2, "0")}.jpg`,
    captureId: captureIdOf(0),
    areaKey: "floor-1",
    room: "Living room",
    direction: "N",
    subject: "general",
    takenAt: `2026-10-17T14:${String(10 + i).padStart(2, "0")}:00Z`,
  });

  it("puts 23 photos on 3 pages numbered 1 to 23", () => {
    const photos = Array.from({ length: 23 }, (_, i) => photo(i + 1));
    const { pages } = layoutOf(
      syntheticInput([{ label: "Floor 1", rooms: [{ label: "Living room", w: 5, d: 4 }] }], {
        photos,
      }),
    );
    const photoPages = pages.filter(
      (page): page is Extract<PageSpec, { kind: "photos" }> => page.kind === "photos",
    );
    assert.deepEqual(
      photoPages.map((page) => [page.photos.length, page.firstNumber, page.continued]),
      [
        [10, 1, false],
        [10, 11, true],
        [3, 21, true],
      ],
    );
    assert.deepEqual(
      photoPages.flatMap((page) => page.photos.map((p) => p.path)),
      photos.map((p) => p.path),
    );
  });

  it("puts photos of no room on 'Other site photos' pages after the floor's rooms", () => {
    const photos = [photo(1), { ...photo(2), room: "Garden" }];
    const { pages } = layoutOf(
      syntheticInput([{ label: "Floor 1", rooms: [{ label: "Living room", w: 5, d: 4 }] }], {
        photos,
      }),
    );
    const list = kinds(pages);
    const other = pages.findIndex((page) => page.kind === "photos" && page.room === undefined);
    assert.ok(other > list.indexOf("photos1"));
    assert.equal(pages[other + 1]?.kind, "record");
  });

  it("leaves photo pages out when the photos were omitted for size", () => {
    const { pages } = layoutOf(
      syntheticInput([{ label: "Floor 1", rooms: [{ label: "Living room", w: 5, d: 4 }] }], {
        photos: [],
        photosOmitted: true,
      }),
    );
    assert.equal(
      pages.some((page) => page.kind === "photos"),
      false,
    );
  });
});

describe("capture checks pages", () => {
  function withFindings(count: number): Verdict {
    const verdict = verdict424("blocked");
    const extra: Finding[] = Array.from({ length: count }, (_, i) => ({
      ruleId: "manifest.fingerprints",
      severity: "blocker",
      message: `File ${i + 1} does not match its manifest fingerprint.`,
      filePath: `Original Exports/floor-1/capture/file-${i + 1}.json`,
      measured: `sha256 ${String(i).padStart(4, "0")}aa… (size 1200 bytes)`,
      expected: "sha256 and size equal the manifest",
      nextAction: "Re-seal the package on the phone and upload it again.",
    }));
    return { ...verdict, findings: [...verdict.findings, ...extra] };
  }

  it("continues 60 findings over 3 or more pages and places every finding block", () => {
    const input = syntheticInput([{ label: "Floor 1", rooms: namedRooms(2) }], {
      verdict: withFindings(60),
    });
    const { model, pages } = layoutOf(input);
    const checks = pages.filter(
      (page): page is Extract<PageSpec, { kind: "checks" }> => page.kind === "checks",
    );
    assert.ok(checks.length >= 3, `${checks.length} checks pages`);
    assert.deepEqual(
      checks.map((page) => page.first),
      [true, ...Array<boolean>(checks.length - 1).fill(false)],
    );
    // Pages are consecutive.
    const first = pages.indexOf(checks[0] as PageSpec);
    assert.ok(checks.every((page, i) => pages[first + i] === page));

    const counts = checkBlockCounts(testCanvas(), model);
    assert.equal(counts.length, model.checkRows.length);
    const placed = counts.map(() => new Set<number>());
    let ends = counts.map(() => 0);
    for (const page of checks) {
      for (const slice of page.table) {
        for (const part of slice.blocks) {
          placed[slice.row]?.add(part.block);
        }
        if (slice.ends) {
          ends = ends.map((n, row) => (row === slice.row ? n + 1 : n));
        }
      }
    }
    counts.forEach((count, row) => {
      assert.equal(placed[row]?.size, count, `row ${row}`);
    });
    assert.deepEqual(
      ends,
      counts.map(() => 1),
    );
    // Rows appear in order; a row split over pages is marked continued on the next.
    const order = checks.flatMap((page) => page.table.map((slice) => slice.row));
    assert.deepEqual(
      order,
      [...order].sort((a, b) => a - b),
    );
    for (let i = 1; i < checks.length; i += 1) {
      const previous = checks[i - 1]?.table.at(-1);
      const next = checks[i]?.table[0];
      if (previous !== undefined && !previous.ends) {
        assert.equal(next?.row, previous.row);
        assert.equal(next?.continued, true);
      }
    }
    // The footnote and the right column end once.
    assert.equal(checks.filter((page) => page.tableEnds).length, 1);
  });
});

describe("room schedule", () => {
  it("splits 30 rooms of 28.75 pt rows by measured height", () => {
    const rooms: SyntheticRoom[] = Array.from({ length: 30 }, (_, i) => ({
      label: `Wing ${i + 1}`,
      w: 0,
      d: 0,
      outline: [
        [0, 0],
        [5 - i * 0.05, 0],
        [5 - i * 0.05, 2],
        [2, 2],
        [2, 4],
        [0, 4],
      ],
    }));
    const { pages } = layoutOf(syntheticInput([{ label: "Floor 1", rooms }]));
    const schedule = pages.filter(
      (page): page is Extract<PageSpec, { kind: "schedule" }> => page.kind === "schedule",
    );
    const roomRows = schedule.map((page) => page.rows.filter((row) => row.kind === "room"));
    assert.ok(roomRows.flat().every((row) => row.kind === "room" && row.height === 28.75));
    // 426 pt less the heading block (55.75 pt) holds 12 rows of 28.75 pt, not the 24-row cap.
    assert.deepEqual(
      roomRows.map((rows) => rows.length),
      [12, 12, 6],
    );
    assert.deepEqual(
      roomRows.flat().map((row) => (row.kind === "room" ? row.room : 0)),
      Array.from({ length: 30 }, (_, i) => i + 1),
    );
    assert.deepEqual(
      schedule.map((page) => [page.first, page.last]),
      [
        [true, false],
        [false, false],
        [false, true],
      ],
    );
  });

  it("packs simple rows of 16.75 pt by height under the 24-room cap", () => {
    const { pages } = layoutOf(syntheticInput([{ label: "Floor 1", rooms: namedRooms(30) }]));
    const schedule = pages.filter(
      (page): page is Extract<PageSpec, { kind: "schedule" }> => page.kind === "schedule",
    );
    // 55.75 + 22 x 16.75 = 424.25 pt of 426.
    assert.deepEqual(
      schedule.map((page) => page.rows.filter((row) => row.kind === "room").length),
      [22, 8],
    );
  });

  it("keeps a floor row with its first room and skipped rooms with the room before", () => {
    const { pages } = layoutOf(
      syntheticInput([
        {
          label: "Floor 1",
          rooms: namedRooms(20, "Upper"),
          capture: { omittedRooms: [{ name: "Attic", reason: "no access" }] },
        },
        { label: "Floor 2", rooms: namedRooms(10, "Lower") },
      ]),
    );
    const schedule = pages.filter(
      (page): page is Extract<PageSpec, { kind: "schedule" }> => page.kind === "schedule",
    );
    for (const page of schedule) {
      const last = page.rows.at(-1);
      assert.notEqual(last?.kind, "floor");
      assert.notEqual(page.rows[0]?.kind, "skipped");
      assert.notEqual(page.rows[0]?.kind, "subtotal");
    }
  });
});
