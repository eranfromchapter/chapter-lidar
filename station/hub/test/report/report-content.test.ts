// What the rendered report contains (spec 11.1 report-content.test.ts; SR-AC3, SR-AC7): page
// numbers and the statement on every page, the fixed strings of each page, no placeholders,
// exactly Inter (2 subsets), Times-Roman and Courier, the logo on every page, token colours only,
// and WinAnsi letters without .notdef glyphs.

import assert from "node:assert/strict";
import { before, describe, it } from "node:test";
import { LOGO_PATHS } from "../../src/report/brand-assets.generated.js";
import {
  REPORT_STATEMENT_CHECKS,
  REPORT_STATEMENT_FULL,
  REPORT_STATEMENT_SHORT,
  renderSpatialReport,
} from "../../src/report/index.js";
import { PageIndex, type PageSpec } from "../../src/report/pages/index-of-pages.js";
import { COLOR } from "../../src/report/tokens.js";
import { PLAN_LEGEND, WORDS } from "../../src/report/words.js";
import { squash } from "../helpers.js";
import { coloursOf, pdfStructure, textShows } from "./pdf-inspect.js";
import { input424, layoutOf, pageTexts, syntheticInput, type Outcome } from "./support.js";

interface Rendered {
  readonly bytes: Buffer;
  readonly texts: readonly string[];
  readonly pages: readonly PageSpec[];
  readonly checksPage: number;
}

const rendered = new Map<Outcome, Rendered>();

async function render424(outcome: Outcome): Promise<Rendered> {
  const input = await input424(outcome);
  const report = await renderSpatialReport(input);
  return {
    bytes: report.bytes,
    texts: await pageTexts(report.bytes),
    pages: layoutOf(input).pages,
    checksPage: report.checksPage,
  };
}

const get = (outcome: Outcome) => rendered.get(outcome) as Rendered;
const has = (text: string, part: string) => squash(text).includes(squash(part));

before(async () => {
  for (const outcome of ["ready", "limited", "blocked"] as const) {
    rendered.set(outcome, await render424(outcome));
  }
});

describe("every page", () => {
  it("has its number, n / N", () => {
    for (const outcome of ["ready", "limited", "blocked"] as const) {
      const { texts } = get(outcome);
      texts.forEach((text, i) => {
        assert.ok(text.includes(`${i + 1} / ${texts.length}`), `${outcome} page ${i + 1}`);
      });
    }
  });

  it("has the full statement on the cover, statement B on the checks, the short one elsewhere", () => {
    const { texts, pages } = get("limited");
    texts.forEach((text, i) => {
      const kind = pages[i]?.kind;
      const expected =
        i === 0
          ? REPORT_STATEMENT_FULL
          : kind === "checks"
            ? REPORT_STATEMENT_CHECKS
            : REPORT_STATEMENT_SHORT;
      assert.ok(has(text, expected), `page ${i + 1} (${kind})`);
      if (i > 0) {
        assert.equal(has(text, REPORT_STATEMENT_FULL), false, `page ${i + 1}`);
      }
    });
  });

  it("has the review link line with the capture id", () => {
    const { texts } = get("limited");
    for (const text of texts) {
      assert.ok(has(text, "Review link · capture 33ede7f4-cfcb-4cd6-9af5-7daffee829a9"));
      assert.ok(has(text, "report generated October 17, 2026"));
    }
  });

  it("has no bracketed placeholder or template field", () => {
    const placeholder = /\[(PLACEHOLDER|N\]|DATE|OPERATOR|CAPTURE ID|DEAL ID|ACC|HDG|PHOTO)/;
    for (const outcome of ["ready", "limited", "blocked"] as const) {
      for (const text of get(outcome).texts) {
        assert.equal(placeholder.test(text), false, text.slice(0, 200));
        assert.equal(/\{\{|\{[A-Za-z]+\}/.test(text), false);
        assert.equal(/undefined|NaN|\[object/.test(text), false);
      }
    }
  });
});

describe("fixed strings of each page", () => {
  const pagesOf = (outcome: Outcome, kind: PageSpec["kind"]) => {
    const { texts, pages } = get(outcome);
    return texts.filter((_, i) => pages[i]?.kind === kind);
  };

  it("cover (1f Limited, 1g Ready, 1h Blocked)", () => {
    const cover = (outcome: Outcome) => get(outcome).texts[0] as string;
    for (const outcome of ["ready", "limited", "blocked"] as const) {
      const text = cover(outcome);
      for (const part of [
        "STATION VERDICT",
        WORDS.overview,
        WORDS.capture,
        WORDS.coverPlanNote,
        WORDS.overviewNote,
        "100 Example Street",
        "Testville, NY 00000 · address confirmed on site",
        "True north · compass",
        "±8° · 212°",
      ]) {
        assert.ok(has(text, part), `${outcome}: ${part}`);
      }
    }
    assert.ok(has(cover("ready"), "Ready for preliminary existing-condition plans"));
    assert.ok(
      has(
        cover("limited"),
        `Usable for preliminary existing-condition plans, with the limitations named on page ${get("limited").checksPage}.`,
      ),
    );
    assert.ok(
      has(
        cover("blocked"),
        `Not usable yet. Two blockers are named on page ${get("blocked").checksPage}; the package must be re-sealed.`,
      ),
    );
    assert.ok(
      has(
        cover("limited"),
        "Not scanned: Primary closet (locked) · Storage room (could not enter)",
      ),
    );
  });

  it("contents and plan (1k)", () => {
    const [contents] = pagesOf("limited", "contents");
    assert.ok(contents !== undefined);
    for (const part of [
      WORDS.contents,
      WORDS.roomSchedule,
      WORDS.captureChecks,
      WORDS.packageRecord,
    ]) {
      assert.ok(has(contents, part), part);
    }
    assert.ok(has(contents, "Room 1 (unlabeled)"));
    assert.ok(has(contents, WORDS.contentsNotePhotos));
    const [plan] = pagesOf("limited", "plan");
    assert.ok(plan !== undefined);
    assert.ok(has(plan, WORDS.planNote));
    assert.ok(has(plan, WORDS.legend.toUpperCase()));
    assert.ok(has(plan, "True north · compass"));
    assert.ok(has(plan, "Living Room 225.3 sq ft"));
    for (const [, text] of PLAN_LEGEND) {
      assert.ok(has(plan, text), text);
    }
  });

  it("schedule (1n)", () => {
    const [schedule] = pagesOf("limited", "schedule");
    assert.ok(schedule !== undefined);
    for (const part of [
      WORDS.roomSchedule,
      WORDS.scheduleFootnote,
      "Floor 1 · 12 rooms scanned · 2 not scanned · largest first",
      "Primary closet",
      "Storage room",
      "approx.",
    ]) {
      assert.ok(has(schedule, part), part);
    }
  });

  it("capture checks (1p, 1q, 1r)", () => {
    for (const outcome of ["ready", "limited", "blocked"] as const) {
      const checks = pagesOf(outcome, "checks");
      const all = checks.join("\n");
      assert.ok(has(checks[0] as string, WORDS.captureChecks));
      assert.ok(has(checks[1] as string, `${WORDS.captureChecks} (continued)`));
      assert.ok(has(all, WORDS.checksFootnote));
      assert.ok(has(all, WORDS.tolerance));
      assert.ok(has(all, "rules station-checks v1.2.0"));
      assert.ok(has(all, "FIELD CONTROLS RECORDED ON SITE"));
    }
    assert.ok(
      has(
        pagesOf("ready", "checks").join(""),
        "0 blockers · 0 limitations · 12 passed · 2 not applicable",
      ),
    );
    assert.ok(
      has(pagesOf("blocked", "checks").join(""), "Blocked: missing information prevents the task"),
    );
    assert.ok(
      has(
        pagesOf("blocked", "checks").join(""),
        "2 blockers · 1 limitation · 9 passed · 2 not applicable",
      ),
    );
  });

  it("room pages (1t living, 1x closet-like, 1y Room 4)", () => {
    const rooms = pagesOf("limited", "room");
    assert.equal(rooms.length, 12);
    const living = rooms[0] as string;
    for (const part of [
      "SPATIAL REPORT · ROOM 1 OF 12",
      "Living Room",
      "FLOOR AREA 225.3 sq ft 20.9 m²",
      "Bounding box 19' 8.3\" × 11' 5.3\" · rectangular room",
      "FURNITURE · 3",
      "OPENINGS · 4 Area",
      WORDS.itemsFootnote,
      WORDS.keyPlan,
      WORDS.roomLegendNote,
    ]) {
      assert.ok(has(living, part), part);
    }
    const room4 = rooms.find((text) => has(text, "ROOM 10 OF 12")) as string;
    assert.ok(has(room4, WORDS.unlabeledRoomTag));
    assert.ok(has(room4, WORDS.approxCeilingNote));
    const empty = rooms.find((text) => has(text, "ROOM 12 OF 12")) as string;
    assert.ok(has(empty, WORDS.noItemsNote));
    assert.ok(has(empty, WORDS.noItemsFootnote));
  });

  it("photo pages (1u) and the package record", () => {
    const photos = pagesOf("limited", "photos");
    assert.ok(photos.every((text) => has(text, WORDS.photosFootnote)));
    assert.ok(has(photos[0] as string, "Living Room · site photos"));
    const record = pagesOf("limited", "record");
    assert.ok(has(record[0] as string, WORDS.packageRecord));
    assert.ok(has(record.join(""), WORDS.recordRight));
    assert.ok(has(record[1] as string, `${WORDS.packageRecord} (continued)`));
  });
});

describe("fonts, logo and colours", () => {
  it("embeds exactly two Inter subsets and uses Times-Roman and Courier, never Helvetica", () => {
    const { bytes } = get("limited");
    const { baseFonts } = pdfStructure(bytes);
    const distinct = [...new Set(baseFonts)].sort();
    assert.equal(distinct.length, 4, distinct.join(", "));
    assert.deepEqual(
      distinct.filter((name) => !name.includes("+")),
      ["Courier", "Times-Roman"],
    );
    assert.deepEqual(
      distinct.filter((name) => name.includes("+")).map((name) => name.split("+")[1]),
      ["Inter-Regular", "Inter-SemiBold"],
    );
    assert.equal(bytes.includes(Buffer.from("Helvetica", "latin1")), false);
    assert.equal(bytes.includes(Buffer.from("/FontFile2", "latin1")), true);
  });

  it("draws the logo's paths on every page", () => {
    const { bytes } = get("limited");
    const { pages } = pdfStructure(bytes);
    const scale = (34 / 635).toFixed(6).slice(0, 6);
    for (const [i, content] of pages.entries()) {
      const at = content.indexOf(`${scale}`);
      assert.ok(at >= 0, `page ${i + 1}: no logo transform`);
      const end = content.indexOf("\nQ", at);
      const fills = content.slice(at, end).match(/\nf\n|\nf$/g)?.length ?? 0;
      assert.equal(fills, LOGO_PATHS.length, `page ${i + 1}`);
    }
  });

  it("uses only token colours", () => {
    const tokens = new Set<string>(Object.values(COLOR).map((c) => c.toUpperCase()));
    for (const outcome of ["ready", "limited", "blocked"] as const) {
      const { pages } = pdfStructure(get(outcome).bytes);
      const used = new Set(pages.flatMap(coloursOf));
      const foreign = [...used].filter((colour) => !tokens.has(colour));
      assert.deepEqual(foreign, [], outcome);
    }
    // The verdict colours appear where the outcome uses them.
    const blocked = new Set(pdfStructure(get("blocked").bytes).pages.flatMap(coloursOf));
    assert.ok(blocked.has(COLOR.blocked));
  });

  it("never shows a .notdef glyph", () => {
    const { bytes } = get("limited");
    const { pages, fontResources } = pdfStructure(bytes);
    const shows = pages.flatMap((content) => textShows(content, fontResources));
    assert.ok(shows.length > 100);
    const notdef = shows.filter((show) => show.font.includes("+") && show.codes.includes("0000"));
    assert.deepEqual(notdef, []);
  });

  it("prints the WinAnsi letters Š š Ž ž of an address with the embedded fonts", async () => {
    const input = syntheticInput(
      [{ label: "Floor 1", rooms: [{ label: "Dnevni boravak", w: 5, d: 4 }] }],
      {
        address: "Ulica Žrtava 3, Šibenik, HR 22000",
      },
    );
    const report = await renderSpatialReport(input);
    const texts = await pageTexts(report.bytes);
    assert.ok(texts[0]?.includes("Ulica Žrtava 3"));
    assert.ok(texts[0]?.includes("Šibenik, HR 22000"));
    const { pages, fontResources } = pdfStructure(report.bytes);
    const shows = pages.flatMap((content) => textShows(content, fontResources));
    assert.deepEqual(
      shows.filter((show) => show.font.includes("+") && show.codes.includes("0000")),
      [],
    );
  });
});

describe("page numbers printed on other pages", () => {
  it("match the page list", () => {
    const { texts, pages, checksPage } = get("limited");
    const index = new PageIndex(pages);
    assert.equal(checksPage, index.checks);
    const contents = texts[index.contents - 1] as string;
    // Contents rows: name then page; rooms with their page range.
    assert.ok(has(contents, `${WORDS.roomSchedule} ${index.schedule}`));
    assert.ok(has(contents, `${WORDS.captureChecks} ${index.checks}`));
    assert.ok(has(contents, `${WORDS.packageRecord} ${index.record}`));
    assert.ok(has(contents, `Living Room ${index.roomRange(1)}`));
    const checks = texts[index.checks - 1] as string;
    assert.ok(has(checks, `SHA-256 fingerprints · page ${index.record}`));
  });
});

describe("cover with four or more floors", () => {
  const floor = (label: string, w: number) => ({
    label,
    rooms: [{ label: `${label} room`, w, d: 3 }],
  });

  it("draws the three largest and names the other floor and its page, singular", async () => {
    const input = syntheticInput([
      floor("Floor 1", 6),
      floor("Floor 2", 5),
      floor("Basement", 2),
      floor("Attic", 4),
    ]);
    const report = await renderSpatialReport(input);
    const [cover] = await pageTexts(report.bytes);
    const index = new PageIndex(layoutOf(input).pages);
    assert.ok(has(cover as string, `+1 floor on page ${index.plan(2)}`), cover);
    assert.ok(!(cover as string).includes("floors on pages"));
  });

  it("lists the pages of two floors that are not next to each other", async () => {
    const input = syntheticInput([
      floor("Floor 1", 6),
      floor("Floor 2", 2),
      floor("Floor 3", 5),
      floor("Basement", 1.5),
      floor("Attic", 4),
    ]);
    const report = await renderSpatialReport(input);
    const [cover] = await pageTexts(report.bytes);
    const index = new PageIndex(layoutOf(input).pages);
    assert.equal(index.plan(3), index.plan(1) + 2);
    assert.ok(has(cover as string, `+2 floors on pages ${index.plan(1)} and ${index.plan(3)}`));
  });
});

describe("approx. on the schedule's totals", () => {
  /** The schedule's line that starts with `label`. */
  const lineOf = (texts: readonly string[], pages: readonly PageSpec[], label: string) =>
    texts
      .filter((_, i) => pages[i]?.kind === "schedule")
      .flatMap((text) => text.split("\n"))
      .find((line) => line.startsWith(label));

  it("says approx. after the total volume when the cover does (424)", () => {
    const { texts, pages } = get("limited");
    assert.ok(has(texts[0] as string, "6,505.5 cu ft approx."));
    assert.equal(
      lineOf(texts, pages, "Total, scanned rooms"),
      `Total, scanned rooms 796.2 2,852.0 74.0 m² · 265.0 m² 384' 4.2" 6,505.5 approx. 29`,
    );
  });

  it("marks only the floor subtotals with an approximate room, and the total", async () => {
    const input = syntheticInput([
      { label: "Floor 1", rooms: [{ label: "Living room", w: 5, d: 4 }] },
      {
        label: "Floor 2",
        rooms: [
          { label: "Bedroom", w: 4, d: 3.5 },
          { label: "Loft", w: 3, d: 2.5 },
        ],
      },
    ]);
    // The loft's walls were not captured: its ceiling height is approximate.
    const floor2 = input.floors?.[1]?.model;
    assert.ok(floor2?.status === "ok");
    floor2.model.walls = floor2.model.walls.filter((wall) => !wall.roomIds?.includes("room-2"));
    const report = await renderSpatialReport(input);
    const texts = await pageTexts(report.bytes);
    const { pages } = layoutOf(input);
    assert.ok(has(texts[0] as string, "cu ft approx."));
    assert.doesNotMatch(lineOf(texts, pages, "Floor 1, scanned rooms") ?? "", /approx\./);
    assert.match(lineOf(texts, pages, "Floor 2, scanned rooms") ?? "", / approx\. 0$/);
    assert.match(lineOf(texts, pages, "Total, scanned rooms") ?? "", / approx\. 0$/);
  });

  it("has no approx. when every ceiling height was measured", async () => {
    const input = syntheticInput([
      { label: "Floor 1", rooms: [{ label: "Living room", w: 5, d: 4 }] },
    ]);
    const report = await renderSpatialReport(input);
    const texts = await pageTexts(report.bytes);
    assert.ok(!(texts[0] as string).includes("approx."));
    const total = lineOf(texts, layoutOf(input).pages, "Total, scanned rooms");
    assert.ok(total !== undefined);
    assert.doesNotMatch(total, /approx\./);
  });
});
