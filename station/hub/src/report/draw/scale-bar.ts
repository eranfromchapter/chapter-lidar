// Scale bar (spec 3.9, plan-parts scaleBar): F = the smallest of 5, 10, 20, 50, 100 ft whose bar
// is at least 60 pt; two halves 5 pt tall (ink, then surface) under a 0.6 pt ink outline; label
// "0    {F/2}    {F} ft" in Courier 7.5, 3 pt below. No ratio: the drawing is fitted.

import type { Canvas } from "../layout/canvas.js";
import { METRES_PER_FOOT } from "../metrics/units.js";
import { COLOR, FONT, type TextStyle } from "../tokens.js";

const LABEL: TextStyle = { font: FONT.mono, size: 7.5, line: 9, color: COLOR.ink };
const STEPS = [5, 10, 20, 50, 100];

export interface ScaleBar {
  readonly feet: number;
  readonly barWidth: number;
  readonly label: string;
  readonly width: number;
  readonly height: number;
}

/** The bar for a drawing at `ptPerMetre`. */
export function scaleBar(canvas: Canvas, ptPerMetre: number): ScaleBar {
  const ptPerFt = ptPerMetre * METRES_PER_FOOT;
  const feet = STEPS.find((f) => f * ptPerFt >= 60) ?? STEPS[STEPS.length - 1] ?? 100;
  const half = feet / 2;
  const label = `0    ${Number.isInteger(half) ? half : half.toFixed(1)}    ${feet} ft`;
  const barWidth = feet * ptPerFt;
  return {
    feet,
    barWidth,
    label,
    width: Math.max(barWidth + 1, canvas.width(label, LABEL)),
    height: 6 + 3 + LABEL.line,
  };
}

/** Draws the bar with its top-left at (x, y). */
export function drawScaleBar(canvas: Canvas, bar: ScaleBar, x: number, y: number): void {
  const doc = canvas.doc;
  const w = bar.barWidth;
  doc.save();
  doc.rect(x + 0.5, y + 0.5, w / 2, 5).fill(COLOR.ink);
  doc.rect(x + 0.5 + w / 2, y + 0.5, w / 2, 5).fill(COLOR.surface);
  doc
    .rect(x + 0.5, y + 0.5, w, 5)
    .lineWidth(0.6)
    .strokeColor(COLOR.ink)
    .stroke();
  doc.restore();
  canvas.line(bar.label, LABEL, x, y + 6 + 3);
}
