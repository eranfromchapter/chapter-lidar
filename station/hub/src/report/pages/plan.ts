// Floor plan pages (spec 5.2; artboards 1k Floor 1, 1l Floor 2+) and the contents list (5.2.1,
// 5.2.3): the contents (or the floor's note) and the legend on the left, the floor with its
// outer dimension strings, north and scale on the right.

import { captureSourceOf } from "@chapter/capture-contract";
import type { Canvas } from "../layout/canvas.js";
import type { Model, ModelFloor } from "../model.js";
import { floorNorthSymbol, NO_SCAN_MODEL_SYMBOL, skippedEntries } from "../model.js";
import {
  dimensionRects,
  drawDimensions,
  drawFloor,
  fitFloor,
  inkPolygons,
  intersects,
  outerDimensions,
  polygonHitsRect,
  type DimensionString,
  type Rect,
} from "../draw/floor.js";
import { drawNorthBlock, northBlockSize } from "../draw/north-arrow.js";
import { drawScaleBar, scaleBar } from "../draw/scale-bar.js";
import { COLOR, TYPE, type TextStyle } from "../tokens.js";
import { PLAN_LEGEND, WORDS, type PlanLegendKind } from "../words.js";
import { drawFrame, floorKicker, type PageContext } from "./context.js";
import type { ContentsRow, PageIndex } from "./index-of-pages.js";

const LEFT_X = 36;
const LEFT_WIDTH = 171;
const REGION: Rect = { x: 219, y: 102, width: 537, height: 426 };
const ROW_HEIGHT = 17.75;

const ROW_NAME: TextStyle = TYPE.table;
const ROW_PAGE: TextStyle = { ...TYPE.table, color: COLOR.muted };

/** Height the legend takes at the bottom of the left column. */
export const LEGEND_HEIGHT = 9 + PLAN_LEGEND.length * (5 + 10);

/** The contents note under the rows. */
export function contentsNote(model: Model): string {
  if (model.photosOmitted) {
    return WORDS.contentsNoteNoPhotos;
  }
  return model.rooms.every((room) => room.photos.length > 0)
    ? WORDS.contentsNotePhotos
    : WORDS.contentsNoteSomePhotos;
}

/** How many contents rows fit the first plan page's left column. */
export function contentsCapacity(canvas: Canvas, model: Model): number {
  const note = canvas.blockHeight(contentsNote(model), TYPE.footnote, LEFT_WIDTH);
  const available = 426 - TYPE.section.line - 4 - 4 - note - 9 - LEGEND_HEIGHT;
  return Math.floor(available / ROW_HEIGHT + 1e-9);
}

/** Every contents row in report order. */
export function contentsRows(model: Model): ContentsRow[] {
  const rows: ContentsRow[] = [{ kind: "schedule" }, { kind: "checks" }];
  const multi = model.floors.length > 1;
  for (const floor of model.floors) {
    if (multi) {
      rows.push({ kind: "floor", floor: floor.index });
    }
    for (const room of floor.rooms) {
      rows.push({ kind: "room", room: room.number });
    }
  }
  rows.push({ kind: "record" });
  return rows;
}

function rowWords(
  model: Model,
  index: PageIndex,
  row: ContentsRow,
): { name: string; page: string; floor: boolean } {
  switch (row.kind) {
    case "schedule":
      return { name: WORDS.roomSchedule, page: String(index.schedule), floor: false };
    case "checks":
      return { name: WORDS.captureChecks, page: String(index.checks), floor: false };
    case "record":
      return { name: WORDS.packageRecord, page: String(index.record), floor: false };
    case "floor":
      return { name: model.floors[row.floor]?.label ?? "", page: "", floor: true };
    case "room": {
      const room = model.rooms[row.room - 1];
      const name =
        room === undefined ? "" : room.unlabeled ? `${room.name} (unlabeled)` : room.name;
      return { name, page: index.roomRange(row.room), floor: false };
    }
  }
}

/** Draws contents rows from `top` in a column; returns the y under the last row. */
export function drawContentsRows(
  canvas: Canvas,
  model: Model,
  index: PageIndex,
  rows: readonly ContentsRow[],
  x: number,
  top: number,
  width: number,
): number {
  let y = top;
  for (const row of rows) {
    const words = rowWords(model, index, row);
    if (words.floor) {
      canvas.line(words.name, TYPE.kickerInner, x, y + 3, { maxWidth: width });
      y += 3 + 9 + 3;
    } else {
      const pageWidth = canvas.width(words.page, ROW_PAGE);
      canvas.line(words.name, ROW_NAME, x, y + 3, { maxWidth: width - pageWidth - 8 });
      canvas.line(words.page, ROW_PAGE, x + width - pageWidth, y + 3);
      y += 3 + 11 + 3;
    }
    canvas.rule(x, y, width, COLOR.line);
    y += 0.75;
  }
  return y;
}

function drawLegend(canvas: Canvas): void {
  const doc = canvas.doc;
  let y = 528 - LEGEND_HEIGHT;
  canvas.line(WORDS.legend, TYPE.kickerInner, LEFT_X, y);
  y += 9;
  for (const [kind, text] of PLAN_LEGEND) {
    y += 5;
    const sx = LEFT_X;
    const sy = y + 1;
    drawLegendSample(doc, kind, sx, sy);
    canvas.line(text, TYPE.dense, LEFT_X + 24 + 8, y, { maxWidth: LEFT_WIDTH - 32 });
    y += 10;
  }
}

function drawLegendSample(
  doc: PDFKit.PDFDocument,
  kind: PlanLegendKind,
  x: number,
  y: number,
): void {
  doc.save().translate(x, y);
  switch (kind) {
    case "wall":
      doc.rect(0, 1.5, 24, 5).fill(COLOR.ink);
      break;
    case "window":
      doc
        .moveTo(0, 3)
        .lineTo(24, 3)
        .moveTo(0, 5)
        .lineTo(24, 5)
        .lineWidth(0.6)
        .strokeColor(COLOR.ink)
        .stroke();
      break;
    case "door":
    case "passage":
      doc.rect(0, 1.5, 5, 5).rect(19, 1.5, 5, 5).fill(COLOR.ink);
      doc.moveTo(5, 4).lineTo(19, 4).lineWidth(0.5).strokeColor(COLOR.muted);
      if (kind === "passage") {
        doc.dash(2, { space: 2 });
      }
      doc.stroke();
      break;
    case "object":
    case "lowObject":
      doc.rect(4, 0.5, 16, 7).lineWidth(0.6).fillColor(COLOR.surface).strokeColor(COLOR.muted);
      if (kind === "lowObject") {
        doc.dash(1.8, { space: 1.2 });
      }
      doc.fillAndStroke();
      break;
    case "fills":
      doc.rect(0, 0, 8, 8).fill(COLOR.nude);
      doc.rect(8, 0, 8, 8).fill(COLOR.wet);
      doc.rect(16, 0, 8, 8).fill(COLOR.ground);
      doc.rect(16.2, 0.2, 7.6, 7.6).lineWidth(0.4).strokeColor(COLOR.line).stroke();
      break;
  }
  doc.restore();
}

export function drawPlanPage(
  ctx: PageContext,
  floorIndex: number,
  contents: readonly ContentsRow[] | undefined,
): void {
  const { canvas, model, index } = ctx;
  const floor = model.floors[floorIndex] as ModelFloor;
  /**
   * A sketch capture (spec F14 1.7) or an AR walkthrough (spec F15 5): the page says so under the
   * floor title and in the notes. A LiDAR scan's page says nothing of the kind.
   */
  const source = floor.capture === undefined ? "lidar" : captureSourceOf(floor.capture);
  const sourceNote =
    source === "sketch"
      ? { title: WORDS.sketchCapture, note: WORDS.sketchPlanNote }
      : source === "walkthrough"
        ? { title: WORDS.walkthroughCapture, note: WORDS.walkthroughPlanNote }
        : undefined;
  drawFrame(ctx, {
    kicker: ["Floor plan", floorKicker(model, floorIndex)],
    statement: "short",
    captureId: floor.captureId,
  });

  // Left column.
  if (contents !== undefined) {
    canvas.line(WORDS.contents, TYPE.section, LEFT_X, 102);
    const bottom = drawContentsRows(
      canvas,
      model,
      index,
      contents,
      LEFT_X,
      102 + 19 + 4,
      LEFT_WIDTH,
    );
    canvas.block(contentsNote(model), TYPE.footnote, LEFT_X, bottom + 4, LEFT_WIDTH);
  } else {
    canvas.line(floor.label, TYPE.section, LEFT_X, 102, { maxWidth: LEFT_WIDTH });
    let noteTop = 102 + 19 + 6;
    if (sourceNote !== undefined) {
      canvas.line(sourceNote.title, { ...TYPE.table, color: COLOR.muted }, LEFT_X, noteTop);
      noteTop += TYPE.table.line + 2;
    }
    const text =
      index.contents > 0 && floorIndex === 0
        ? WORDS.otherFloorNote.replace(
            "The contents list is on the first plan page only.",
            `The contents list is on page ${index.contents}.`,
          )
        : WORDS.otherFloorNote;
    canvas.block(
      text,
      { ...TYPE.table, line: 12, color: COLOR.muted },
      LEFT_X,
      noteTop,
      LEFT_WIDTH,
    );
  }
  drawLegend(canvas);

  // Plan region: notes at the bottom, the drawing above them.
  const notes: string[] = [];
  const drawable =
    floor.metrics !== undefined &&
    !(floor.rooms.length === 0 && floor.metrics.geometry.walls.length === 0);
  if (sourceNote !== undefined) {
    notes.push(sourceNote.note);
  }
  if (drawable) {
    notes.push(WORDS.planNote);
  }
  if (floor.skipped.length > 0) {
    notes.push(`Not scanned: ${skippedEntries(floor.skipped, false).join(" · ")}`);
  }
  const lines = notes.map((note) => canvas.wrap(note, TYPE.caption, NOTES_WIDTH));
  const height =
    lines.reduce((sum, l) => sum + l.length * TYPE.caption.line, 0) +
    2 * Math.max(0, lines.length - 1);
  const notesTop = 528 - height;
  if (floor.metrics === undefined) {
    drawUnavailable(canvas, floor);
  } else if (!drawable) {
    const style = { ...TYPE.body, color: COLOR.muted };
    const width = canvas.width(WORDS.noRooms, style);
    canvas.line(WORDS.noRooms, style, REGION.x + (REGION.width - width) / 2, REGION.y + 200);
  } else {
    drawFloorRegion(ctx, floor, notesTop);
  }
  let y = notesTop;
  for (const l of lines) {
    y += canvas.lines(l, TYPE.caption, REGION.x, y, NOTES_WIDTH) + 2;
  }
}

const NOTES_WIDTH = 400;

function drawUnavailable(canvas: Canvas, floor: ModelFloor): void {
  const text =
    floor.source.status === "unreadable"
      ? WORDS.scanModelUnreadable(floor.label)
      : WORDS.scanModelMissing(floor.label);
  const style: TextStyle = { ...TYPE.dense, line: 10.5 };
  const lines = canvas.wrap(text, style, 300 - 18);
  const height = Math.max(80, lines.length * style.line + 12);
  const x = REGION.x + (REGION.width - 300) / 2;
  const y = REGION.y + (REGION.height - height) / 2 - 30;
  canvas.roundedBorder(x, y, 300, height, 4, 0.75, COLOR.line);
  canvas.lines(lines, style, x + 9, y + (height - lines.length * style.line) / 2, 282);
  const size = northBlockSize(canvas, NO_SCAN_MODEL_SYMBOL, 32);
  drawNorthBlock(canvas, NO_SCAN_MODEL_SYMBOL, 756 - size.width / 2, 502 - size.height, 32);
}

/**
 * The floor fitted with its outer wall box in x 245-732 from y 118 (24 pt left on every side for
 * the dimension strings) above the notes; north and scale right-aligned at x 756 with their
 * bottom at y 502. When the drawing's ink or dimension strings would cover them, the drawing is
 * made smaller (to 85 % of the fitted scale); past that, they go to the top right of the region.
 */
function drawFloorRegion(ctx: PageContext, floor: ModelFloor, notesTop: number): void {
  const { canvas } = ctx;
  const bottom = Math.min(494, notesTop - 24 - 2);
  const box = { x: 245, y: 118, width: 732 - 245, height: bottom - 118 };
  const fitted = fitFloor(floor, { box, minWall: 2, wallsOnly: true });
  if (fitted === undefined) {
    return;
  }
  const symbol = floorNorthSymbol(floor);
  const north = northBlockSize(canvas, symbol, 32);
  const blockAt = (scale: number, top?: number): Rect => {
    const bar = scaleBar(canvas, scale);
    const width = Math.max(north.width, bar.width);
    const height = north.height + 8 + bar.height;
    return { x: 756 - width, y: top ?? 502 - height, width, height };
  };
  const covered = (view: NonNullable<typeof fitted>, dims: DimensionString[], block: Rect) =>
    inkPolygons(floor, view, 2).some((polygon) => polygonHitsRect(polygon, block)) ||
    dimensionRects(canvas, dims).some((rect) => intersects(rect, block));
  let view = fitted;
  let dims = outerDimensions(canvas, floor, view, 2);
  let block = blockAt(view.scale);
  if (covered(view, dims, block)) {
    let resolved = false;
    for (let factor = 0.99; factor >= 0.85 - 1e-9; factor -= 0.01) {
      const candidate = fitFloor(floor, {
        box,
        minWall: 2,
        wallsOnly: true,
        scale: fitted.scale * factor,
      });
      if (candidate === undefined) {
        break;
      }
      const candidateDims = outerDimensions(canvas, floor, candidate, 2);
      const candidateBlock = blockAt(candidate.scale);
      if (!covered(candidate, candidateDims, candidateBlock)) {
        view = candidate;
        dims = candidateDims;
        block = candidateBlock;
        resolved = true;
        break;
      }
    }
    if (!resolved) {
      block = blockAt(view.scale, 102);
    }
  }
  drawFloor(canvas, floor, view, { minWall: 2, labels: true });
  drawDimensions(canvas, dims);
  const bar = scaleBar(canvas, view.scale);
  drawNorthBlock(canvas, symbol, 756 - north.width / 2, block.y, 32);
  drawScaleBar(canvas, bar, 756 - bar.width, block.y + north.height + 8);
}

/** A contents page (when the list does not fit the first plan page): 3 columns of 232 pt. */
export function drawContentsPage(
  ctx: PageContext,
  columns: ReadonlyArray<readonly ContentsRow[]>,
  note: boolean,
): void {
  const { canvas, model, index } = ctx;
  drawFrame(ctx, { kicker: [WORDS.contents], statement: "short" });
  canvas.line(WORDS.contents, TYPE.section, 36, 102);
  const xs = [36, 280, 524];
  columns.forEach((rows, i) => {
    const bottom = drawContentsRows(canvas, model, index, rows, xs[i] ?? 36, 125, 232);
    if (note && i === columns.length - 1) {
      canvas.block(contentsNote(model), TYPE.footnote, xs[i] ?? 36, bottom + 4, 232);
    }
  });
}

/** Contents rows per column of a contents page. */
export const CONTENTS_PAGE_ROWS = Math.floor((528 - 125) / ROW_HEIGHT);
