// Text layout (spec 11.1 text.test.ts): CSS half-leading line placement, word wrap, path
// breaking at "/", maxLines with "...", tracking.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { INTER_REGULAR_TTF_BASE64 } from "../../src/report/brand-assets.generated.js";
import { ELLIPSIS } from "../../src/report/layout/canvas.js";
import { TYPE, type TextStyle } from "../../src/report/tokens.js";
import { testCanvas } from "./support.js";

const canvas = testCanvas();

/** hhea ascender/descender and head unitsPerEm read straight from the TrueType tables. */
function fontMetrics(ttf: Buffer): { ascent: number; descent: number; unitsPerEm: number } {
  const tables = new Map<string, number>();
  const count = ttf.readUInt16BE(4);
  for (let i = 0; i < count; i += 1) {
    const record = 12 + i * 16;
    tables.set(ttf.toString("latin1", record, record + 4), ttf.readUInt32BE(record + 8));
  }
  const hhea = tables.get("hhea") as number;
  const head = tables.get("head") as number;
  return {
    ascent: ttf.readInt16BE(hhea + 4),
    descent: ttf.readInt16BE(hhea + 6),
    unitsPerEm: ttf.readUInt16BE(head + 18),
  };
}
const near = (actual: number, expected: number, tolerance = 0.005) =>
  assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} vs ${expected}`);

describe("line placement", () => {
  it("puts an Inter 9/11 baseline where a CSS line box does", () => {
    const font = fontMetrics(Buffer.from(INTER_REGULAR_TTF_BASE64.join(""), "base64"));
    const asc = (font.ascent / font.unitsPerEm) * 9;
    const desc = (font.descent / font.unitsPerEm) * 9;
    // Half-leading: (L - (asc - desc)) / 2 above the ascender.
    near(canvas.baselineOffset(TYPE.table), (11 - (asc - desc)) / 2 + asc);
    near(canvas.baselineOffset(TYPE.table), 8.774, 0.01);
  });

  it("puts a Times 21/24 title baseline with the browser's Times metrics", () => {
    // Times New Roman: ascender 891.1, descender -216.3 per 1000.
    near(canvas.baselineOffset(TYPE.title), (24 - 1.1074 * 21) / 2 + 0.8911 * 21);
    near(canvas.baselineOffset(TYPE.title), 19.085, 0.001);
  });

  it("gives the ink box of a line inside its line box", () => {
    const [top, bottom] = canvas.inkBox(TYPE.table);
    assert.ok(top >= 0 && bottom <= 11 + 0.2, `${top} ${bottom}`);
  });
});

describe("wrapping", () => {
  const style: TextStyle = TYPE.dense;
  const text =
    "Plan geometry of Floor 1 agrees with the field-control distances measured on site with a laser.";

  it("wraps greedily at spaces within the width", () => {
    const lines = canvas.wrap(text, style, 160);
    assert.ok(lines.length > 1);
    assert.equal(lines.join(" "), text);
    for (const line of lines) {
      assert.ok(canvas.width(line, style) <= 160 + 1e-6, line);
    }
    // Greedy: the next word never fits on the line before.
    for (let i = 1; i < lines.length; i += 1) {
      const next = (lines[i] as string).split(" ")[0] as string;
      assert.ok(canvas.width(`${lines[i - 1]} ${next}`, style) > 160);
    }
  });

  it("keeps paragraphs", () => {
    assert.deepEqual(canvas.wrap("one\ntwo", style, 300), ["one", "two"]);
  });

  it("breaks a package path after '/' and never inside a folder name with spaces", () => {
    const path = "Source Register/b8dbc48a-f67f-4fd1-9859-7cfc2edaad7e/capture-record.json";
    const lines = canvas.wrapPath(path, TYPE.ids, 160);
    assert.equal(lines.join(""), path);
    assert.equal(lines[0], "Source Register/");
    for (const line of lines) {
      assert.ok(canvas.width(line, TYPE.ids) <= 160 + 1e-6, line);
    }
  });

  it("breaks a path segment longer than the width anywhere", () => {
    const path = `Photos/${"x".repeat(60)}.jpg`;
    const lines = canvas.wrapPath(path, TYPE.ids, 100);
    assert.equal(lines.join(""), path);
    assert.equal(lines[0], "Photos/");
    assert.ok(lines.length >= 3);
  });

  it("breaks a long word after '/' first", () => {
    const word = "Original/Exports/floor-1/33ede7f4-cfcb-4cd6-9af5-7daffee829a9/model.json";
    const lines = canvas.wrap(word, style, 120);
    assert.equal(lines.join(""), word);
    // The first piece ends at the last "/" that fits; the id (wider than the column) breaks
    // anywhere.
    assert.equal(lines[0], "Original/Exports/floor-1/");
    assert.ok(lines.every((line) => canvas.width(line, style) <= 120 + 1e-6));
  });

  it("cuts to maxLines with '...' that still fits", () => {
    const lines = canvas.wrap(text, style, 100, 2);
    assert.equal(lines.length, 2);
    assert.ok(lines[1]?.endsWith(ELLIPSIS));
    assert.ok(canvas.width(lines[1] as string, style) <= 100 + 1e-6);
    assert.deepEqual(canvas.wrap("Short.", style, 100, 2), ["Short."]);
  });

  it("truncates a single line with '...'", () => {
    const cut = canvas.truncate(canvas.prepare(text, style), style, 80);
    assert.ok(cut.endsWith(ELLIPSIS));
    assert.ok(canvas.width(cut, style) <= 80 + 1e-6);
    assert.ok(text.startsWith(cut.slice(0, -ELLIPSIS.length)));
  });

  it("measures a wrapped block", () => {
    assert.equal(
      canvas.blockHeight(text, style, 160),
      canvas.wrap(text, style, 160).length * style.line,
    );
  });
});

describe("tracking and case", () => {
  it("adds the tracking between characters", () => {
    const plain = canvas.width("CAPTURE", { ...TYPE.kicker, tracking: 0 });
    const tracked = canvas.width("CAPTURE", TYPE.kicker);
    near(tracked - plain, 1.5 * 6, 1e-6);
  });

  it("upper-cases kickers before measuring", () => {
    assert.equal(
      canvas.prepare("Spatial report · Room 1 of 12", TYPE.kicker),
      "SPATIAL REPORT · ROOM 1 OF 12",
    );
    assert.equal(
      canvas.width("Spatial report", TYPE.kicker),
      canvas.width("SPATIAL REPORT", TYPE.kicker),
    );
  });

  it("measures WinAnsi-safe text (≤ is drawn as <=)", () => {
    assert.equal(canvas.width("a ≤ b", TYPE.body), canvas.width("a <= b", TYPE.body));
  });
});
