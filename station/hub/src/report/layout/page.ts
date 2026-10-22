// The frame of every page (spec 3.3, 3.5): page colour, header (kicker, title, address line,
// logo, rule) and footer (rule, QR code of the review link, review line, statement, n / N).

import QRCode from "qrcode";
import { LOGO_HEIGHT, LOGO_PATHS } from "../brand-assets.generated.js";
import { COLOR, PAGE, TYPE, type TextStyle } from "../tokens.js";
import type { Canvas, Run } from "./canvas.js";

const LOGO_X = 662;
const LOGO_Y = 36;
const LOGO_DRAWN_HEIGHT = 34;
const HEADER_WIDTH = 610;

export function drawBackground(canvas: Canvas): void {
  canvas.fillRect(0, 0, PAGE.width, PAGE.height, COLOR.surface);
}

/** The real Chapter logo, 34 pt tall at top right, brand black, nonzero fill per path. */
export function drawLogo(canvas: Canvas): void {
  const doc = canvas.doc;
  const k = LOGO_DRAWN_HEIGHT / LOGO_HEIGHT;
  doc.save();
  doc.translate(LOGO_X, LOGO_Y).scale(k);
  for (const d of LOGO_PATHS) {
    doc.path(d).fill(COLOR.logo, "nonzero");
  }
  doc.restore();
}

export interface Header {
  /** Kicker parts after "Spatial report" (joined " · "). */
  readonly kicker: string;
  readonly title: string;
  /** Address line (and on the cover its suffix). Empty: no line. */
  readonly subline: string;
}

export function drawHeader(canvas: Canvas, header: Header): void {
  canvas.line(header.kicker, TYPE.kicker, PAGE.left, 36, { maxWidth: HEADER_WIDTH });
  canvas.line(header.title, TYPE.title, PAGE.left, 48, { maxWidth: HEADER_WIDTH });
  if (header.subline !== "") {
    canvas.line(header.subline, TYPE.subline, PAGE.left, 75, { maxWidth: HEADER_WIDTH });
  }
  drawLogo(canvas);
  canvas.rule(PAGE.left, 90, PAGE.contentWidth, COLOR.line);
}

export interface Footer {
  /** Line 1 as runs (the capture or package id in Courier). */
  readonly line1: readonly Run[];
  /** Line 2: the statement (wraps to at most 2 lines). */
  readonly statement: string;
  readonly pageLabel: string;
  readonly reviewUrl: string;
}

const QR_SIZE = 30;

/** QR modules of the review URL (error correction L), cached per URL. */
const qrCache = new Map<string, { size: number; dark: (row: number, col: number) => boolean }>();

export function qrModules(url: string): {
  size: number;
  dark: (row: number, col: number) => boolean;
} {
  let found = qrCache.get(url);
  if (found === undefined) {
    const code = QRCode.create(url, { errorCorrectionLevel: "L" });
    const size = code.modules.size;
    const data = code.modules.data;
    found = { size, dark: (row, col) => data[row * size + col] === 1 };
    qrCache.set(url, found);
  }
  return found;
}

/** The QR code at (x, y), 30 x 30 pt: surface square, ink modules (horizontal runs merged). */
export function drawQr(canvas: Canvas, url: string, x: number, y: number): void {
  const doc = canvas.doc;
  const { size, dark } = qrModules(url);
  const m = QR_SIZE / size;
  doc.save();
  doc.rect(x, y, QR_SIZE, QR_SIZE).fill(COLOR.surface);
  let any = false;
  for (let row = 0; row < size; row += 1) {
    let col = 0;
    while (col < size) {
      if (!dark(row, col)) {
        col += 1;
        continue;
      }
      const start = col;
      while (col < size && dark(row, col)) {
        col += 1;
      }
      doc.rect(x + start * m, y + row * m, (col - start) * m, m);
      any = true;
    }
  }
  if (any) {
    doc.fill(COLOR.ink);
  }
  doc.restore();
  doc.link(x, y, QR_SIZE, QR_SIZE, url);
}

export function drawFooter(canvas: Canvas, footer: Footer): void {
  canvas.rule(PAGE.left, 536, PAGE.contentWidth, COLOR.line);
  drawQr(canvas, footer.reviewUrl, PAGE.left, 544);
  const pageStyle: TextStyle = TYPE.caption;
  const pageWidth = canvas.width(footer.pageLabel, pageStyle);
  const textLeft = 76;
  const textWidth = PAGE.right - pageWidth - 10 - textLeft;
  const line1Style: TextStyle = { ...TYPE.caption, color: COLOR.ink };
  const statementLines = canvas.wrap(footer.statement, TYPE.caption, textWidth, 2);
  const columnHeight = line1Style.line + 1.5 + statementLines.length * TYPE.caption.line;
  const top = 542 + (34 - columnHeight) / 2;
  // Line 1 is cut to the column only when it would overflow it.
  const runs = fitRuns(canvas, footer.line1, textWidth);
  const reviewWidth = canvas.width("Review link", line1Style);
  canvas.runs(runs, textLeft, top);
  canvas.doc.link(textLeft, top, reviewWidth, line1Style.line, footer.reviewUrl);
  canvas.lines(statementLines, TYPE.caption, textLeft, top + line1Style.line + 1.5, textWidth);
  canvas.line(footer.pageLabel, pageStyle, PAGE.right - pageWidth, 542 + (34 - pageStyle.line) / 2);
}

/** Runs cut from the end so the line fits `width`. */
function fitRuns(canvas: Canvas, runs: readonly Run[], width: number): Run[] {
  if (canvas.runsWidth(runs) <= width) {
    return [...runs];
  }
  const out: Run[] = [];
  let used = 0;
  for (const run of runs) {
    const runWidth = canvas.width(run.text, run.style);
    if (used + runWidth <= width) {
      out.push(run);
      used += runWidth;
      continue;
    }
    const prepared = canvas.prepare(run.text, run.style);
    out.push({ text: canvas.truncate(prepared, run.style, width - used), style: run.style });
    break;
  }
  return out;
}
