// Verdict glyphs (spec 3.6) and item markers (spec 3.8): vector paths, never text glyphs.

import type { RuleResult } from "@chapter/capture-contract";
import type { Canvas } from "../layout/canvas.js";
import type { MarkerShape } from "../model.js";
import { COLOR, FONT } from "../tokens.js";

export type GlyphKind = "ready" | "limited" | "blocked" | "not_applicable";

export const GLYPH_COLOR: Record<GlyphKind, string> = {
  ready: COLOR.ready,
  limited: COLOR.limited,
  blocked: COLOR.blocked,
  not_applicable: COLOR.muted,
};

export const RESULT_TEXT_COLOR: Record<RuleResult, string> = {
  passed: COLOR.ready,
  limited: COLOR.limitedText,
  blocked: COLOR.blocked,
  not_applicable: COLOR.muted,
};

export const RESULT_GLYPH_KIND: Record<RuleResult, GlyphKind> = {
  passed: "ready",
  limited: "limited",
  blocked: "blocked",
  not_applicable: "not_applicable",
};

/**
 * A verdict glyph in a 10-unit box scaled to `size`, top-left at (x, y): ● circle, ▲ triangle,
 * ■ square, — dash (not applicable). `table` uses the slightly smaller table variants.
 */
export function drawGlyph(
  canvas: Canvas,
  kind: GlyphKind,
  x: number,
  y: number,
  size: number,
  table = false,
): void {
  const doc = canvas.doc;
  const k = size / 10;
  doc.save().translate(x, y).scale(k);
  switch (kind) {
    case "ready":
      doc.circle(5, 5, table ? 4.4 : 4.6);
      break;
    case "limited":
      if (table) {
        doc.moveTo(5, 0.6).lineTo(9.6, 9.4).lineTo(0.4, 9.4).closePath();
      } else {
        doc.moveTo(5, 0.5).lineTo(9.6, 9.3).lineTo(0.4, 9.3).closePath();
      }
      break;
    case "blocked":
      if (table) {
        doc.rect(0.8, 0.8, 8.4, 8.4);
      } else {
        doc.rect(0.6, 0.6, 8.8, 8.8);
      }
      break;
    case "not_applicable":
      doc.rect(1, 4.3, 8, 1.4);
      break;
  }
  doc.fill(GLYPH_COLOR[kind]).restore();
}

/** The outline of an item marker of `size` centred at (cx, cy). */
function markerPath(
  canvas: Canvas,
  shape: MarkerShape,
  cx: number,
  cy: number,
  size: number,
): void {
  const doc = canvas.doc;
  const r = size / 2;
  switch (shape) {
    case "circle":
      doc.circle(cx, cy, r);
      break;
    case "square":
      doc.rect(cx - r, cy - r, size, size);
      break;
    case "triangle":
      doc
        .moveTo(cx, cy - r * 1.15)
        .lineTo(cx + r * 1.15, cy + r * 0.85)
        .lineTo(cx - r * 1.15, cy + r * 0.85)
        .closePath();
      break;
    case "pentagon":
      doc
        .moveTo(cx, cy - r * 1.15)
        .lineTo(cx + r * 1.1, cy - r * 0.35)
        .lineTo(cx + r * 0.68, cy + r * 0.95)
        .lineTo(cx - r * 0.68, cy + r * 0.95)
        .lineTo(cx - r * 1.1, cy - r * 0.35)
        .closePath();
      break;
    case "diamond":
      doc
        .moveTo(cx, cy - r * 1.2)
        .lineTo(cx + r * 1.2, cy)
        .lineTo(cx, cy + r * 1.2)
        .lineTo(cx - r * 1.2, cy)
        .closePath();
      break;
  }
}

/**
 * An item marker: shape stroked 0.75 ink, filled surface, with its number (Inter SemiBold 6.5,
 * centred; a triangle's number sits 0.25 r lower). No number for legend glyphs.
 */
export function drawMarker(
  canvas: Canvas,
  shape: MarkerShape,
  cx: number,
  cy: number,
  size: number,
  label?: string,
): void {
  const doc = canvas.doc;
  doc.save();
  markerPath(canvas, shape, cx, cy, size);
  doc.lineWidth(0.75).lineJoin("miter").fillColor(COLOR.surface).strokeColor(COLOR.ink);
  doc.fillAndStroke();
  doc.restore();
  if (label !== undefined && label !== "") {
    const style = { font: FONT.semibold, size: 6.5, line: 6.5, color: COLOR.ink } as const;
    const width = canvas.width(label, style);
    const r = size / 2;
    const middle = cy + (shape === "triangle" ? r * 0.25 : 0);
    // Centre the digits' ink (cap height ~0.73 em of Inter) on the middle.
    const baseline = middle + (0.727 * style.size) / 2;
    doc.font(style.font).fontSize(style.size).fillColor(style.color);
    doc.text(label, cx - width / 2, baseline, { lineBreak: false, baseline: "alphabetic" });
  }
}
