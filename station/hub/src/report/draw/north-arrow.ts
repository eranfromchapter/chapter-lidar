// The north symbol of a floor (compass spec 6.1 and 8.3; artboard 1d north-arrow-v2), in pdfkit.
//
// Geometry in a 32 x 32 box scaled by size / 32, y down: ring centre (16, 18) r 10.5; arrow
// (16, 6.5) (20.5, 25.5) (16, 22) (11.5, 25.5); "N" Inter SemiBold 6 with its baseline at y 4.6.
// Ring, arrow and "N" turn counter-clockwise by the symbol's angle about (16, 16) (pdfkit's y
// axis points down, so that is a negative pdfkit rotation); the caption does not turn.
// Approximate: dashed ring (1.6 / 1.6) and a hollow arrow (page colour). Not verified: no arrow,
// a bordered box "Orientation: not verified" with the reason under it.

import type { NorthSymbol } from "@chapter/capture-contract";
import type { Canvas } from "../layout/canvas.js";
import { COLOR, FONT, TYPE, type TextStyle } from "../tokens.js";

const CAPTION: TextStyle = TYPE.caption;
const BOX_TEXT: TextStyle = { ...TYPE.caption, color: COLOR.ink };
const BOX_HEIGHT = 15;
const GAP = 2;

export interface BlockSize {
  readonly width: number;
  readonly height: number;
}

/** Size of the whole block (symbol and caption). */
export function northBlockSize(canvas: Canvas, symbol: NorthSymbol, size: number): BlockSize {
  if (symbol.kind === "box") {
    const boxWidth = canvas.width(symbol.box, BOX_TEXT) + 12;
    const caption = canvas.width(symbol.caption, CAPTION);
    return { width: Math.max(boxWidth, caption), height: BOX_HEIGHT + GAP + CAPTION.line };
  }
  const caption = Math.max(...symbol.lines.map((line) => canvas.width(line, CAPTION)));
  return { width: Math.max(size, caption), height: size + GAP + 2 * CAPTION.line };
}

/** Draws the block with its top centre at (centerX, top). */
export function drawNorthBlock(
  canvas: Canvas,
  symbol: NorthSymbol,
  centerX: number,
  top: number,
  size: number,
): void {
  const doc = canvas.doc;
  if (symbol.kind === "box") {
    const textWidth = canvas.width(symbol.box, BOX_TEXT);
    const boxWidth = textWidth + 12;
    const left = centerX - boxWidth / 2;
    canvas.roundedBorder(left, top, boxWidth, BOX_HEIGHT, 3, 0.75, COLOR.muted);
    canvas.line(symbol.box, BOX_TEXT, left + 6, top + 3);
    const captionWidth = canvas.width(symbol.caption, CAPTION);
    canvas.line(symbol.caption, CAPTION, centerX - captionWidth / 2, top + BOX_HEIGHT + GAP);
    return;
  }
  const s = size / 32;
  const left = centerX - size / 2;
  doc.save();
  doc.translate(left, top).scale(s);
  doc.rotate(-symbol.angleCcw, { origin: [16, 16] });
  // Ring.
  doc.save();
  doc.circle(16, 18, 10.5).lineWidth(0.75);
  if (symbol.approximate) {
    doc.dash(1.6, { space: 1.6 });
    doc.lineCap("butt");
  }
  doc.strokeColor(COLOR.ink).stroke();
  doc.restore();
  // Arrow.
  doc.save();
  doc.polygon([16, 6.5], [20.5, 25.5], [16, 22], [11.5, 25.5]);
  doc.lineWidth(0.75).lineJoin("round");
  doc.fillColor(symbol.approximate ? COLOR.surface : COLOR.ink).strokeColor(COLOR.ink);
  doc.fillAndStroke();
  doc.restore();
  // "N", centred on x 16, baseline at y 4.6 (in box units).
  doc.font(FONT.semibold).fontSize(6);
  const nWidth = doc.widthOfString("N");
  doc.fillColor(COLOR.ink).text("N", 16 - nWidth / 2, 4.6, {
    lineBreak: false,
    baseline: "alphabetic",
  });
  doc.restore();
  symbol.lines.forEach((line, index) => {
    const width = canvas.width(line, CAPTION);
    canvas.line(line, CAPTION, centerX - width / 2, top + size + GAP + index * CAPTION.line);
  });
}
