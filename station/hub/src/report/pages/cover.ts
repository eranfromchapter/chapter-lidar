// Cover (spec 5.1; artboards 1f Limited, 1g Ready, 1h Blocked, 1i 2 floors): the plan of the
// floor (or the floors side by side) with north and scale, and the data column: station verdict,
// overview and capture.

import { northSymbol, type NorthSymbol, type Verdict } from "@chapter/capture-contract";
import { dateSpan, numberWord, shortDate, sqFt as sqFtText, fixed, ftIn, cuFt } from "../format.js";
import type { Canvas, Run } from "../layout/canvas.js";
import type { Model, ModelFloor } from "../model.js";
import { skippedEntries, taskWords } from "../model.js";
import { drawGlyph, type GlyphKind } from "../draw/glyphs.js";
import {
  drawFloor,
  fitFloor,
  inkPolygons,
  inkRect,
  polygonHitsRect,
  type Rect,
} from "../draw/floor.js";
import { drawNorthBlock, northBlockSize } from "../draw/north-arrow.js";
import { drawScaleBar, scaleBar } from "../draw/scale-bar.js";
import type { PlanView } from "../draw/plan-view.js";
import { COLOR, FONT, TYPE, type TextStyle } from "../tokens.js";
import { WORDS } from "../words.js";
import { drawFrame, type PageContext } from "./context.js";

const PLAN: Rect = { x: 36, y: 102, width: 476, height: 426 };
const DATA_X = 524;
const DATA_WIDTH = 232;

const VERDICT_STYLE: Record<
  Verdict["outcome"],
  { border: string; text: string; glyph: GlyphKind; word: string }
> = {
  ready: { border: COLOR.ready, text: COLOR.ready, glyph: "ready", word: "Ready" },
  limited: { border: COLOR.limited, text: COLOR.limitedText, glyph: "limited", word: "Limited" },
  blocked: { border: COLOR.blocked, text: COLOR.blocked, glyph: "blocked", word: "Blocked" },
};

/** The cover sentence of a verdict (spec 5.1.2); `checksPage` is the first capture checks page. */
export function coverSentence(verdict: Verdict, checksPage: number, blockers?: number): string {
  const task = taskWords(verdict);
  switch (verdict.outcome) {
    case "ready":
      return `Ready for ${task}. All station checks passed (page ${checksPage}).`;
    case "limited":
      return `Usable for ${task}, with the limitations named on page ${checksPage}.`;
    case "blocked": {
      const count = blockers ?? 0;
      return `Not usable yet. ${numberWord(count)} ${count === 1 ? "blocker is" : "blockers are"} named on page ${checksPage}; the package must be re-sealed.`;
    }
  }
}

/** Rotation the drawing applies to the plan, counter-clockwise degrees (compass 2.5: rho). */
function symbolOf(floor: ModelFloor, available: boolean): NorthSymbol {
  if (!available) {
    return { kind: "box", box: "Orientation: not verified", caption: WORDS.noScanModel };
  }
  return northSymbol(floor.compass, -floor.rotationDegrees);
}

const LABEL: TextStyle = {
  font: FONT.semibold,
  size: 7.5,
  line: 9,
  color: COLOR.ink,
  tracking: 1.2,
  upper: true,
};
const LABEL_MIN_SCALE = 31.8;

export function drawCover(ctx: PageContext): void {
  const { canvas, model } = ctx;
  drawFrame(ctx, { kicker: [], cover: true, statement: "full" });
  drawPlanArea(ctx);
  drawDataColumn(canvas, model, ctx.index.checks);
}

// MARK: Plan area

function drawPlanArea(ctx: PageContext): void {
  const { canvas, model } = ctx;
  const readable = model.floors.filter((floor) => floor.metrics !== undefined);
  if (model.floors.length <= 1) {
    const floor = model.floors[0];
    if (floor === undefined || floor.metrics === undefined) {
      drawNotAvailable(canvas, floor);
      return;
    }
    if (floor.rooms.length === 0 && floor.metrics.geometry.walls.length === 0) {
      centredText(canvas, WORDS.noRooms);
      return;
    }
    drawOneFloor(ctx, floor);
    return;
  }
  if (readable.length === 0 && model.floors.every((floor) => floor.source.status !== "ok")) {
    // Every model missing: still one block per floor with its placeholder.
  }
  drawFloors(ctx);
}

function centredText(canvas: Canvas, text: string): void {
  const style = { ...TYPE.body, color: COLOR.muted };
  const width = canvas.width(text, style);
  canvas.line(text, style, PLAN.x + (PLAN.width - width) / 2, 102 + 392 / 2 - style.line / 2);
}

function drawNotAvailable(canvas: Canvas, floor: ModelFloor | undefined): void {
  const text =
    floor?.source.status === "unreadable"
      ? WORDS.scanModelUnreadable(floor.label)
      : WORDS.scanModelMissing(floor?.label ?? "the floor");
  const style: TextStyle = { ...TYPE.dense, line: 10.5 };
  const lines = canvas.wrap(text, style, 300 - 18);
  const height = lines.length * style.line + 12;
  const x = PLAN.x + (PLAN.width - 300) / 2;
  const y = 102 + (392 - height) / 2;
  canvas.roundedBorder(x, y, 300, height, 4, 0.75, COLOR.line);
  canvas.lines(lines, style, x + 9, y + 6, 282);
  const symbol: NorthSymbol = {
    kind: "box",
    box: "Orientation: not verified",
    caption: WORDS.noScanModel,
  };
  const size = northBlockSize(canvas, symbol, 32);
  drawNorthBlock(canvas, symbol, 470, 506 - size.height, 32);
}

/** The bottom-left block: scale bar + note, then the not-scanned line. Returns its top. */
function bottomBlock(
  canvas: Canvas,
  model: Model,
  view: PlanView | undefined,
  withFloorNames: boolean,
  draw: boolean,
  extra?: string,
): number {
  const width = 380;
  const note = { ...TYPE.caption };
  const bar = view === undefined ? undefined : scaleBar(canvas, view.scale);
  const noteWidth = width - (bar === undefined ? 0 : bar.width + 14);
  const noteLines = canvas.wrap(WORDS.coverPlanNote, note, noteWidth);
  const row1 = Math.max(bar?.height ?? 0, noteLines.length * note.line);
  const skipped = model.floors.flatMap((floor) => floor.skipped);
  const rows: Array<{ lines: string[] }> = [];
  if (skipped.length > 0) {
    rows.push({ lines: notScannedLines(canvas, skippedEntries(skipped, withFloorNames), width) });
  }
  if (extra !== undefined) {
    rows.push({ lines: canvas.wrap(extra, note, width) });
  }
  const rest = rows.reduce((sum, row) => sum + 5 + row.lines.length * note.line, 0);
  const top = 528 - row1 - rest;
  if (draw) {
    if (bar !== undefined) {
      drawScaleBar(canvas, bar, PLAN.x, top + row1 - bar.height);
    }
    const noteX = PLAN.x + (bar === undefined ? 0 : bar.width + 14);
    canvas.lines(noteLines, note, noteX, top + row1 - noteLines.length * note.line, noteWidth);
    let y = top + row1;
    for (const row of rows) {
      y += 5;
      canvas.lines(row.lines, note, PLAN.x, y, width);
      y += row.lines.length * note.line;
    }
  }
  return top;
}

/** "Not scanned: a · b" in at most 2 lines; more entries end with "and {k} more". */
function notScannedLines(canvas: Canvas, entries: readonly string[], width: number): string[] {
  const style = TYPE.caption;
  const all = `Not scanned: ${entries.join(" · ")}`;
  const lines = canvas.wrap(all, style, width);
  if (lines.length <= 2) {
    return lines;
  }
  for (let kept = entries.length - 1; kept >= 0; kept -= 1) {
    const text = `Not scanned: ${entries.slice(0, kept).join(" · ")}${kept > 0 ? " · " : ""}and ${entries.length - kept} more (see the room schedule)`;
    const wrapped = canvas.wrap(text, style, width);
    if (wrapped.length <= 2) {
      return wrapped;
    }
  }
  return canvas.wrap(all, style, width, 2);
}

function drawOneFloor(ctx: PageContext, floor: ModelFloor): void {
  const { canvas, model } = ctx;
  const symbol = symbolOf(floor, true);
  const northSize = northBlockSize(canvas, symbol, 32);
  const northRect: Rect = {
    x: 428,
    y: 506 - northSize.height,
    width: 84,
    height: northSize.height,
  };
  let view = fitFloor(floor, {
    box: { x: PLAN.x, y: PLAN.y, width: 476, height: 392 },
    minWall: 2,
  });
  if (view === undefined) {
    return;
  }
  // Shrink until the drawing's ink clears the north and bottom blocks (the drawing may reach
  // into their corners where it draws nothing, as artboard 1f does).
  for (let round = 0; round < 60; round += 1) {
    const blockTop = bottomBlock(canvas, model, view, false, false);
    const bottomRect: Rect = { x: PLAN.x, y: blockTop, width: 380, height: 528 - blockTop };
    const polygons = inkPolygons(floor, view, 2);
    if (
      !polygons.some(
        (polygon) => polygonHitsRect(polygon, northRect) || polygonHitsRect(polygon, bottomRect),
      )
    ) {
      break;
    }
    view =
      fitFloor(floor, {
        box: { x: PLAN.x, y: PLAN.y, width: 476, height: 392 },
        minWall: 2,
        scale: view.scale * 0.97,
      }) ?? view;
  }
  drawFloor(canvas, floor, view, { minWall: 2, labels: true });
  drawNorthBlock(canvas, symbol, 470, northRect.y, 32);
  bottomBlock(canvas, model, view, false, true);
}

/** Two or three floors side by side at one scale (the three largest when there are more). */
function drawFloors(ctx: PageContext): void {
  const { canvas, model, index } = ctx;
  let shown = model.floors;
  let extra: string | undefined;
  if (model.floors.length > 3) {
    const area = (floor: ModelFloor) => floor.metrics?.totals.livableAreaM2 ?? -1;
    const largest = [...model.floors]
      .sort((a, b) => area(b) - area(a) || a.index - b.index)
      .slice(0, 3);
    shown = model.floors.filter((floor) => largest.includes(floor));
    const omitted = model.floors.filter((floor) => !largest.includes(floor));
    const pages = omitted.map((floor) => index.plan(floor.index));
    extra = `+${omitted.length} floors on pages ${Math.min(...pages)}–${Math.max(...pages)}`;
  }
  const arrowSize = 26;
  const symbols = shown.map((floor) => symbolOf(floor, floor.metrics !== undefined));
  const blockHeights = symbols.map((symbol) => northBlockSize(canvas, symbol, arrowSize).height);
  // Unit extents (metres) of each drawing at scale 1, then the common scale.
  const unitViews = shown.map((floor) =>
    fitFloor(floor, { box: { x: 0, y: 0, width: 1, height: 1 }, minWall: 0, scale: 1 }),
  );
  const extentAt = (s: number) =>
    shown.map((floor) => {
      if (floor.metrics === undefined) {
        return { width: 120, height: 90 };
      }
      const view = fitFloor(floor, {
        box: { x: 0, y: 0, width: 1, height: 1 },
        minWall: 2,
        scale: s,
      });
      const ink = view === undefined ? undefined : inkRect(floor, view, 2);
      return { width: ink?.width ?? 0, height: ink?.height ?? 0 };
    });
  const fitsAt = (s: number, blockTop: number) => {
    const sizes = extentAt(s);
    const widths = sizes.reduce((sum, size) => sum + size.width, 0) + 20 * (shown.length - 1);
    const tallest = Math.max(
      ...sizes.map((size, i) => 9 + 6 + size.height + 4 + (blockHeights[i] ?? 0)),
    );
    return widths <= 476 && tallest <= Math.min(392, blockTop - 102 - 6);
  };
  let s = 200;
  if (unitViews.some((view) => view !== undefined)) {
    // Largest scale that fits, by bisection.
    let low = 0.5;
    let high = 400;
    const blockTop = (scale: number) =>
      bottomBlock(
        canvas,
        model,
        fitFloor(shown.find((f) => f.metrics !== undefined) as ModelFloor, {
          box: { x: 0, y: 0, width: 1, height: 1 },
          minWall: 2,
          scale,
        }),
        true,
        false,
        extra,
      );
    for (let i = 0; i < 40; i += 1) {
      const mid = (low + high) / 2;
      if (fitsAt(mid, blockTop(mid))) {
        low = mid;
      } else {
        high = mid;
      }
    }
    s = low;
  }
  const sizes = extentAt(s);
  let x = PLAN.x;
  let scaleView: PlanView | undefined;
  shown.forEach((floor, i) => {
    const size = sizes[i] as { width: number; height: number };
    canvas.line(floor.label, LABEL, x, PLAN.y);
    const drawingTop = PLAN.y + 9 + 6;
    if (floor.metrics === undefined) {
      const doc = canvas.doc;
      doc.save();
      doc.rect(x + 0.375, drawingTop + 0.375, 120 - 0.75, 90 - 0.75).fill(COLOR.ground);
      doc
        .rect(x + 0.375, drawingTop + 0.375, 120 - 0.75, 90 - 0.75)
        .lineWidth(0.75)
        .dash(4, { space: 3 })
        .strokeColor(COLOR.muted)
        .stroke();
      doc.restore();
      const style = { ...TYPE.caption };
      const w = canvas.width(WORDS.planNotAvailable, style);
      canvas.line(
        WORDS.planNotAvailable,
        style,
        x + (120 - w) / 2,
        drawingTop + 45 - style.line / 2,
      );
    } else {
      const view = fitFloor(floor, {
        box: { x, y: drawingTop, width: size.width, height: size.height },
        minWall: 2,
        scale: s,
      });
      if (view !== undefined) {
        drawFloor(canvas, floor, view, { minWall: 2, labels: s >= LABEL_MIN_SCALE });
        scaleView ??= view;
      }
    }
    const symbol = symbols[i] as NorthSymbol;
    drawNorthBlock(canvas, symbol, x + size.width / 2, drawingTop + size.height + 4, arrowSize);
    x += size.width + 20;
  });
  bottomBlock(canvas, model, scaleView, true, true, extra);
}

// MARK: Data column

interface DataRow {
  readonly label: string;
  readonly value: readonly Run[];
}

function drawDataColumn(canvas: Canvas, model: Model, checksPage: number): void {
  let y = 102;
  y = drawVerdictBlock(canvas, model, checksPage, y);
  y += 10;
  const value: TextStyle = TYPE.table;
  const muted: TextStyle = { ...TYPE.table, color: COLOR.muted };
  const mono: TextStyle = TYPE.tableMono;
  const totals = model.totals;
  const overview: DataRow[] = [];
  if (totals.bedrooms !== undefined) {
    overview.push({ label: "Bedrooms", value: [{ text: String(totals.bedrooms), style: value }] });
    overview.push({
      label: "Bathrooms",
      value: [{ text: String(totals.bathrooms ?? 0), style: value }],
    });
  }
  const notAvailable = (label: string): DataRow => ({
    label,
    value: [{ text: WORDS.notAvailable, style: value }],
  });
  overview.push({ label: "Rooms scanned", value: [{ text: roomsLine(model), style: value }] });
  if (totals.readable) {
    overview.push(
      {
        label: "Floor area, sum of rooms",
        value: [
          { text: `${sqFtText(totals.livableAreaM2)} sq ft`, style: value },
          { text: ` · ${fixed(totals.livableAreaM2, 1)} m²`, style: muted },
        ],
      },
      {
        label: "Wall area, excl. openings",
        value: [{ text: `${sqFtText(totals.wallAreaM2)} sq ft`, style: value }],
      },
      {
        label: "Window area",
        value: [{ text: `${sqFtText(totals.windowAreaM2)} sq ft`, style: value }],
      },
      {
        label: "Volume, flat ceilings",
        value: [
          { text: `${cuFt(totals.volumeM3)} cu ft`, style: value },
          ...(totals.volumeIsApproximate ? [{ text: " approx.", style: muted }] : []),
        ],
      },
      { label: "Perimeter, all rooms", value: [{ text: ftIn(totals.perimeterM), style: mono }] },
    );
  } else {
    overview.push(
      notAvailable("Floor area, sum of rooms"),
      notAvailable("Wall area, excl. openings"),
      notAvailable("Window area"),
      notAvailable("Volume, flat ceilings"),
      notAvailable("Perimeter, all rooms"),
    );
  }
  y = drawSection(canvas, WORDS.overview, overview, y);
  y += 4;
  y += canvas.block(WORDS.overviewNote, TYPE.footnote, DATA_X, y, DATA_WIDTH);
  y += 10;
  drawSection(canvas, WORDS.capture, captureRows(model), y);
}

function roomsLine(model: Model): string {
  const readable = model.floors.filter((floor) => floor.metrics !== undefined);
  const counts = readable.map((floor) => floor.rooms.length);
  const missing = model.floors
    .filter((floor) => floor.metrics === undefined)
    .map((floor) => ` · ${floor.label}: plan not available`)
    .join("");
  const n = readable.length;
  if (n === 0) {
    return model.floors.length === 0 ? "0" : `0${missing}`;
  }
  return `${counts.join(" + ")} on ${n} ${n === 1 ? "floor" : "floors"}${missing}`;
}

const MODE_LABEL: Record<string, string> = {
  room: "One room",
  floor: "Whole floor",
  exterior: "Exterior",
};

function captureRows(model: Model): DataRow[] {
  const value: TextStyle = TYPE.table;
  const record = model.input.captureRecord;
  const tz = model.timeZone;
  const text = (t: string): Run[] => [{ text: t, style: value }];
  const k = model.floors.length;
  const captures = `${k} ${k === 1 ? "capture" : "captures"}`;
  const rows: DataRow[] = [];
  if (record === undefined) {
    rows.push(
      { label: "Captured", value: text(WORDS.notRecorded) },
      { label: "Device", value: text(WORDS.notRecorded) },
    );
    rows.push({ label: "Mode", value: text(captures) });
  } else {
    const starts = record.captures.map((capture) => capture.capturedAt).sort();
    const first = starts[0] ?? record.visitedAt;
    const last = starts[starts.length - 1] ?? record.visitedAt;
    const sameDay = shortDate(first, tz) === shortDate(last, tz);
    const when = sameDay
      ? shortDate(record.visitedAt, tz)
      : dateSpan(first, last, tz, "short", "–");
    rows.push({ label: "Captured", value: text(`${when} · ${record.operator.name}`) });
    const device = record.device.marketingName ?? record.device.model;
    rows.push({
      label: "Device",
      value: text(`${device} · ${record.device.hasLidar ? "LiDAR" : "no LiDAR"}`),
    });
    const modes = [
      ...new Set(record.captures.map((capture) => MODE_LABEL[capture.mode] ?? capture.mode)),
    ];
    rows.push({ label: "Mode", value: text(`${modes.join(", ")} · ${captures}`) });
  }
  const sealed =
    model.input.sealedAt === undefined ? "" : ` · sealed ${shortDate(model.input.sealedAt, tz)}`;
  rows.push({ label: "Package", value: text(`revision ${model.verdict.revision}${sealed}`) });
  rows.push({ label: "HUB deal", value: [{ text: model.input.dealId, style: TYPE.tableMono }] });
  return rows;
}

/** Heading + label/value rows; returns the y under the last row. */
function drawSection(
  canvas: Canvas,
  heading: string,
  rows: readonly DataRow[],
  top: number,
): number {
  canvas.line(heading, TYPE.section, DATA_X, top);
  let y = top + TYPE.section.line + 4;
  const label: TextStyle = { ...TYPE.table, color: COLOR.muted };
  for (const row of rows) {
    const labelWidth = canvas.width(row.label, label);
    canvas.line(row.label, label, DATA_X, y + 3.75);
    const available = DATA_WIDTH - labelWidth - 8;
    const runs = truncateRuns(canvas, row.value, available);
    canvas.runs(runs, DATA_X, y + 3.75, { width: DATA_WIDTH, align: "right" });
    y += 3.75 + 11 + 3.75;
    canvas.rule(DATA_X, y, DATA_WIDTH, COLOR.line);
    y += 0.75;
  }
  return y;
}

function truncateRuns(canvas: Canvas, runs: readonly Run[], width: number): Run[] {
  if (canvas.runsWidth(runs) <= width) {
    return [...runs];
  }
  const first = runs[0];
  if (first === undefined) {
    return [];
  }
  return [
    {
      text: canvas.truncate(canvas.prepare(first.text, first.style), first.style, width),
      style: first.style,
    },
  ];
}

function drawVerdictBlock(canvas: Canvas, model: Model, checksPage: number, top: number): number {
  const verdict = model.verdict;
  const look = VERDICT_STYLE[verdict.outcome];
  const innerX = DATA_X + 11;
  const innerWidth = DATA_WIDTH - 22;
  const sentenceStyle: TextStyle = { ...TYPE.dense, line: 11 };
  const sentence = coverSentence(verdict, checksPage, model.counts.blockers);
  const sentenceLines = canvas.wrap(sentence, sentenceStyle, innerWidth);
  const height = 8 + 9 + 4 + 14 + 4 + sentenceLines.length * sentenceStyle.line + 9;
  canvas.roundedBorder(DATA_X, top, DATA_WIDTH, height, 6, 1.5, look.border);
  let y = top + 8;
  canvas.line(
    `Station verdict · ${shortDate(verdict.evaluatedAt, model.timeZone)}`,
    TYPE.kickerInner,
    innerX,
    y,
    { maxWidth: innerWidth },
  );
  y += 9 + 4;
  drawGlyph(canvas, look.glyph, innerX, y + 2, 10);
  canvas.line(look.word, { ...TYPE.verdictWord, color: look.text }, innerX + 16, y);
  y += 14 + 4;
  canvas.lines(sentenceLines, sentenceStyle, innerX, y, innerWidth);
  return top + height;
}
