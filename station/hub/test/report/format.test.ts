// Spatial report text formatting (spec 11.1 format.test.ts): engine rounding, unit conversion,
// dates in the report's time zone, plurals, number words, page lists and WinAnsi-safe text.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  cuFt,
  dateSpan,
  dimensionPair,
  fixed,
  formatBytes,
  ftIn,
  grouped,
  isTimeZone,
  longDate,
  numberWord,
  pdfSafeText,
  plural,
  shortDate,
  shortDateTime,
  sqFt,
  time,
} from "../../src/report/format.js";
import { decimals, METRES_PER_INCH } from "../../src/report/metrics/units.js";
import { omittedFloorsText, pagesText } from "../../src/report/words.js";

const NY = "America/New_York";

describe("lengths, areas and volumes", () => {
  it("rounds feet-inches as a whole before splitting", () => {
    assert.equal(ftIn(11.96 * METRES_PER_INCH), `1' 0.0"`);
    assert.equal(ftIn(0), `0' 0.0"`);
    assert.equal(ftIn(5.8928), `19' 4.0"`);
    assert.equal(ftIn(-0.3048), `-1' 0.0"`);
  });

  it("rounds a tie half away from zero (within a millionth of a step)", () => {
    assert.equal(ftIn(0.05 * METRES_PER_INCH), `0' 0.1"`);
    assert.equal(decimals(2.345, 2), "2.35");
    assert.equal(decimals(-0.5, 0), "-1");
    assert.equal(fixed(2196.25, 1), "2,196.3");
  });

  it("groups thousands", () => {
    assert.equal(grouped("2196.3"), "2,196.3");
    assert.equal(grouped("-1234567.25"), "-1,234,567.25");
    assert.equal(grouped("999"), "999");
    assert.equal(fixed(Number.NaN, 1), "-");
  });

  it("converts square and cubic metres to feet with one decimal", () => {
    assert.equal(sqFt(0.092_903_04), "1.0");
    assert.equal(sqFt(10), "107.6");
    assert.equal(sqFt(204.04), "2,196.3");
    assert.equal(cuFt(1), "35.3");
    assert.equal(cuFt(186.84), "6,598.2");
  });

  it("prints metric values with the engine's decimals", () => {
    assert.equal(decimals(12.345678, 2), "12.35");
    assert.equal(decimals(2.7, 2), "2.70");
    assert.equal(decimals(186.8354, 1), "186.8");
  });

  it("writes a dimension pair larger side first", () => {
    assert.equal(dimensionPair(3, 4), `13' 1.5" × 9' 10.1"`);
    assert.equal(dimensionPair(4, 3), `13' 1.5" × 9' 10.1"`);
  });
});

describe("dates and times", () => {
  // 23:30 EDT on October 16 is 03:30 UTC on October 17.
  const lateVisit = "2026-10-17T03:30:00Z";

  it("prints the local date of a late visit in America/New_York", () => {
    assert.equal(longDate(lateVisit, NY), "October 16, 2026");
    assert.equal(shortDate(lateVisit, NY), "Oct 16, 2026");
    assert.equal(shortDateTime(lateVisit, NY), "Oct 16, 2026 23:30");
    assert.equal(time(lateVisit, NY), "23:30");
  });

  it("prints the same instant in UTC", () => {
    assert.equal(longDate(lateVisit, "UTC"), "October 17, 2026");
    assert.equal(shortDateTime(lateVisit, "UTC"), "Oct 17, 2026 03:30");
  });

  it("uses a 24-hour clock that starts at 00", () => {
    assert.equal(time("2026-10-17T04:05:00Z", NY), "00:05");
    assert.equal(time("2026-01-15T17:45:00Z", NY), "12:45");
  });

  it("follows daylight saving time", () => {
    assert.equal(time("2026-01-15T14:00:00Z", NY), "09:00");
    assert.equal(time("2026-07-15T14:00:00Z", NY), "10:00");
  });

  it("writes spans of one day, days of one year and days across years", () => {
    assert.equal(
      dateSpan("2026-10-17T13:00:00Z", "2026-10-17T15:00:00Z", NY, "long", " to "),
      "October 17, 2026",
    );
    assert.equal(
      dateSpan("2026-10-16T13:00:00Z", "2026-10-17T15:00:00Z", NY, "long", " to "),
      "October 16 to October 17, 2026",
    );
    assert.equal(
      dateSpan("2026-10-16T13:00:00Z", "2026-10-17T15:00:00Z", NY, "short", "–"),
      "Oct 16–Oct 17, 2026",
    );
    assert.equal(
      dateSpan("2025-12-31T15:00:00Z", "2026-01-01T15:00:00Z", NY, "long", " to "),
      "December 31, 2025 to January 1, 2026",
    );
  });

  it("rejects a malformed date and knows IANA zones", () => {
    assert.throws(() => longDate("not a date", NY), RangeError);
    assert.equal(isTimeZone(NY), true);
    assert.equal(isTimeZone("UTC"), true);
    assert.equal(isTimeZone("Mars/Olympus_Mons"), false);
  });
});

describe("words", () => {
  it("writes plurals", () => {
    assert.equal(plural(0, "room"), "0 rooms");
    assert.equal(plural(1, "room"), "1 room");
    assert.equal(plural(2, "room"), "2 rooms");
    assert.equal(plural(2, "entry", "entries"), "2 entries");
  });

  it("spells 1 to 9 and writes digits from 10", () => {
    const words = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"];
    words.forEach((word, i) => assert.equal(numberWord(i + 1), word));
    assert.equal(numberWord(0), "Zero");
    assert.equal(numberWord(10), "10");
    assert.equal(numberWord(12), "12");
  });

  it("writes sizes in bytes and binary units", () => {
    assert.equal(formatBytes(512), "512 B");
    assert.equal(formatBytes(1024), "1.0 KiB (1024 bytes)");
    assert.equal(formatBytes(1_258_291), "1.2 MiB (1258291 bytes)");
    assert.equal(formatBytes(47_185_920), "45.0 MiB (47185920 bytes)");
  });

  it("prints one page, a range of consecutive pages, or a list", () => {
    assert.equal(pagesText([4]), "page 4");
    assert.equal(pagesText([5, 4]), "pages 4–5");
    assert.equal(pagesText([4, 5, 6]), "pages 4–6");
    assert.equal(pagesText([3, 5]), "pages 3 and 5");
    assert.equal(pagesText([6, 3, 5]), "pages 3, 5 and 6");
  });

  it("names the floors a four-floor cover leaves out, singular for one", () => {
    assert.equal(omittedFloorsText([4]), "+1 floor on page 4");
    assert.equal(omittedFloorsText([4, 5]), "+2 floors on pages 4–5");
    assert.equal(omittedFloorsText([3, 5]), "+2 floors on pages 3 and 5");
  });
});

describe("pdfSafeText", () => {
  const table: Array<[string, string]> = [
    ["−3", "-3"],
    ["a‐b‑c", "a-b-c"],
    ["≤ 1% ≥ 2", "<= 1% >= 2"],
    ["≈ 4", "~ 4"],
    ["A → B ← C", "A -> B <- C"],
    ["wait…", "wait..."],
    ["● ▲ ■", "* ^ #"],
    ["6′ 2″", `6' 2"`],
    ["a b\tc", "a b c"],
    ["Café × 2 · 3° ±8", "Café × 2 · 3° ±8"],
    ["“quoted” – ‘single’ — €5 ™", "“quoted” – ‘single’ — €5 ™"],
    ["Šibenik Ž ž š Ÿ ƒ", "Šibenik Ž ž š Ÿ ƒ"],
    ["日本 🏠", "?? ?"],
    ["line 1\nline 2", "line 1\nline 2"],
  ];
  for (const [input, expected] of table) {
    it(`maps ${JSON.stringify(input)}`, () => {
      assert.equal(pdfSafeText(input), expected);
    });
  }
});
