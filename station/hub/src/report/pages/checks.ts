// Capture checks (spec 5.4; artboards 1p Limited, 1q Ready, 1r Blocked): the verdict band, one
// table row per rule with every finding (message, measured, expected, file, next action), and
// the right column (limitations, next actions, field controls, package). Rows and the right
// column continue on "Capture checks (continued)" pages.

import {
  countsLine,
  ruleSetLabel,
  verdictHeadline,
  type CheckRow,
  type FieldControls,
} from "@chapter/capture-contract";
import { feetInches } from "../metrics/units.js";
import { shortDate, shortDateTime } from "../format.js";
import type { Canvas, Run } from "../layout/canvas.js";
import type { Model } from "../model.js";
import { taskWords } from "../model.js";
import { RESULT_GLYPH_KIND, RESULT_TEXT_COLOR, drawGlyph, type GlyphKind } from "../draw/glyphs.js";
import { COLOR, FONT, TYPE, type TextStyle } from "../tokens.js";
import { WORDS } from "../words.js";
import { drawFrame, type PageContext } from "./context.js";
import type { CheckSlice, PageIndex, PageSpec, RightSlice } from "./index-of-pages.js";

const X = 36;
const TABLE_WIDTH = 476;
const COLS = [100, 82, 160, 116];
const COL_X = [X, X + 106, X + 194, X + 360];
const RIGHT_X = 524;
const RIGHT_WIDTH = 232;
const BOTTOM = 528;

const TITLE: TextStyle = TYPE.table;
const RULE_ID: TextStyle = TYPE.ids;
const MESSAGE: TextStyle = TYPE.dense;
const DETAIL: TextStyle = TYPE.caption;
const FILE: TextStyle = TYPE.ids;
const ACTION: TextStyle = TYPE.dense;
const ACTION_NONE: TextStyle = { ...TYPE.dense, color: COLOR.muted };
const RIGHT_TEXT: TextStyle = { ...TYPE.table, color: COLOR.muted };

interface Piece {
  readonly text: string;
  readonly style: TextStyle;
  /** Space above this line. */
  readonly gap: number;
}

interface BlockLayout {
  readonly left: readonly Piece[];
  readonly right: readonly Piece[];
}

interface RowLayout {
  readonly row: CheckRow;
  readonly title: readonly string[];
  readonly titleContinued: readonly string[];
  readonly ruleId: readonly string[];
  readonly blocks: readonly BlockLayout[];
}

const piecesHeight = (pieces: readonly Piece[]) =>
  pieces.reduce((sum, p) => sum + p.gap + p.style.line, 0);

function lines(
  canvas: Canvas,
  text: string,
  style: TextStyle,
  width: number,
  firstGap: number,
): Piece[] {
  return canvas
    .wrap(text, style, width)
    .map((line, i) => ({ text: line, style, gap: i === 0 ? firstGap : 0 }));
}

function rowLayout(canvas: Canvas, row: CheckRow): RowLayout {
  const blocks: BlockLayout[] = [];
  if (row.found.length === 0) {
    const text =
      row.result === "passed"
        ? WORDS.noFindingsPassed
        : row.result === "not_applicable"
          ? WORDS.noFindingsNotApplicable
          : WORDS.noFindingsFailed;
    blocks.push({
      left: lines(canvas, text, MESSAGE, COLS[2] as number, 0),
      right: lines(canvas, WORDS.none, ACTION_NONE, COLS[3] as number, 0),
    });
  }
  for (const found of row.found) {
    const left: Piece[] = [...lines(canvas, found.message, MESSAGE, COLS[2] as number, 0)];
    const finding = found.finding;
    if (finding.measured !== undefined) {
      left.push(...lines(canvas, `Measured: ${finding.measured}`, DETAIL, COLS[2] as number, 1));
    }
    if (finding.expected !== undefined) {
      left.push(...lines(canvas, `Expected: ${finding.expected}`, DETAIL, COLS[2] as number, 1));
    }
    if (finding.filePath !== undefined) {
      left.push(
        ...canvas
          .wrapPath(finding.filePath, FILE, COLS[2] as number)
          .map((line, i) => ({ text: line, style: FILE, gap: i === 0 ? 1 : 0 })),
      );
    }
    const none = finding.nextAction === WORDS.none;
    blocks.push({
      left,
      right: lines(canvas, finding.nextAction, none ? ACTION_NONE : ACTION, COLS[3] as number, 0),
    });
  }
  return {
    row,
    title: canvas.wrap(row.title, TITLE, COLS[0] as number),
    titleContinued: canvas.wrap(`${row.title} (continued)`, TITLE, COLS[0] as number),
    ruleId: canvas.wrap(row.ruleId, RULE_ID, COLS[0] as number),
    blocks,
  };
}

function col1Height(layout: RowLayout, continued: boolean): number {
  const title = (continued ? layout.titleContinued : layout.title).length * TITLE.line;
  return title + 1 + layout.ruleId.length * RULE_ID.line;
}

/** Height of a slice's content (without padding). */
function sliceHeight(layout: RowLayout, slice: CheckSlice): number {
  let blocks = 0;
  slice.blocks.forEach((part, i) => {
    const block = layout.blocks[part.block] as BlockLayout;
    const left = piecesHeight(
      block.left.slice(part.fromLine, part.toLine).map((p, j) => (j === 0 ? { ...p, gap: 0 } : p)),
    );
    const right = piecesHeight(
      block.right
        .slice(part.fromAction, part.toAction)
        .map((p, j) => (j === 0 ? { ...p, gap: 0 } : p)),
    );
    blocks += (i === 0 ? 0 : 3) + Math.max(left, right);
  });
  return Math.max(col1Height(layout, slice.continued), 11, blocks);
}

const ROW_CHROME = 3 + 3 + 0.75;

/** The part of a row from (block, line, action) that fits `available` content height. */
function fitRow(
  layout: RowLayout,
  start: { block: number; line: number; action: number },
  available: number,
  continued: boolean,
): { slice: CheckSlice; next?: { block: number; line: number; action: number } } | undefined {
  const parts: Array<CheckSlice["blocks"][number]> = [];
  let used = 0;
  const base = Math.max(col1Height(layout, continued), 11);
  for (let b = start.block; b < layout.blocks.length; b += 1) {
    const block = layout.blocks[b] as BlockLayout;
    const fromLine = b === start.block ? start.line : 0;
    const fromAction = b === start.block ? start.action : 0;
    const left = block.left.slice(fromLine).map((p, j) => (j === 0 ? { ...p, gap: 0 } : p));
    const right = block.right.slice(fromAction).map((p, j) => (j === 0 ? { ...p, gap: 0 } : p));
    const gap = parts.length === 0 ? 0 : 3;
    const height = Math.max(piecesHeight(left), piecesHeight(right));
    if (Math.max(base, used + gap + height) <= available) {
      parts.push({
        block: b,
        fromLine,
        toLine: block.left.length,
        fromAction,
        toAction: block.right.length,
      });
      used += gap + height;
      continue;
    }
    // Split inside this block, between lines.
    const room = available - used - gap;
    let leftCount = 0;
    let leftUsed = 0;
    while (
      leftCount < left.length &&
      leftUsed + (left[leftCount] as Piece).gap + (left[leftCount] as Piece).style.line <= room
    ) {
      leftUsed += (left[leftCount] as Piece).gap + (left[leftCount] as Piece).style.line;
      leftCount += 1;
    }
    let rightCount = 0;
    let rightUsed = 0;
    while (
      rightCount < right.length &&
      rightUsed + (right[rightCount] as Piece).gap + (right[rightCount] as Piece).style.line <= room
    ) {
      rightUsed += (right[rightCount] as Piece).gap + (right[rightCount] as Piece).style.line;
      rightCount += 1;
    }
    if (leftCount + rightCount > 0 && base <= available) {
      parts.push({
        block: b,
        fromLine,
        toLine: fromLine + leftCount,
        fromAction,
        toAction: fromAction + rightCount,
      });
      const next = { block: b, line: fromLine + leftCount, action: fromAction + rightCount };
      if (next.line >= block.left.length && next.action >= block.right.length) {
        return b + 1 < layout.blocks.length
          ? {
              slice: { row: 0, continued, blocks: parts, ends: false },
              next: { block: b + 1, line: 0, action: 0 },
            }
          : { slice: { row: 0, continued, blocks: parts, ends: true } };
      }
      return { slice: { row: 0, continued, blocks: parts, ends: false }, next };
    }
    if (parts.length === 0) {
      return undefined;
    }
    return {
      slice: { row: 0, continued, blocks: parts, ends: false },
      next: { block: b, line: fromLine, action: fromAction },
    };
  }
  return { slice: { row: 0, continued, blocks: parts, ends: true } };
}

// MARK: Right column

type RightItem =
  | { readonly kind: "text"; readonly lines: readonly string[]; readonly style: TextStyle }
  | {
      readonly kind: "row";
      readonly label: string;
      readonly value: readonly Run[];
      readonly stacked?: boolean;
    }
  | { readonly kind: "note"; readonly lines: readonly string[] };

interface RightSection {
  readonly title: string;
  readonly items: readonly RightItem[];
}

const ROW_LABEL: TextStyle = { ...TYPE.dense, color: COLOR.muted };
const LIST: TextStyle = { ...TYPE.dense, line: 10.5 };

function itemHeight(item: RightItem): number {
  switch (item.kind) {
    case "text":
      return item.lines.length * item.style.line;
    case "row":
      return 3 + (item.stacked === true ? 10 + 9 : 10) + 3 + 0.75;
    case "note":
      return item.lines.length * TYPE.footnote.line;
  }
}

function methodsOf(controls: FieldControls, captureId?: string): string {
  const methods = new Set(
    controls.distances
      .filter((d) => captureId === undefined || d.capture.captureId === captureId)
      .map((d) => d.measurement.method),
  );
  if (methods.has("tape") && methods.has("laser")) {
    return "tape, laser";
  }
  return methods.has("laser") ? "laser" : "tape";
}

function rightSections(canvas: Canvas, model: Model, index: PageIndex | undefined): RightSection[] {
  const verdict = model.verdict;
  const texts = (list: readonly string[]): RightItem[] =>
    (list.length === 0 ? [WORDS.noneDot] : list).map((text) => ({
      kind: "text" as const,
      lines: canvas.wrap(text, LIST, RIGHT_WIDTH),
      style: LIST,
    }));
  const value: TextStyle = TYPE.dense;
  const mono: TextStyle = TYPE.denseMono;
  const controls = model.fieldControls;
  const valid = controls !== undefined && controls !== "invalid" ? controls : undefined;
  const notRecorded: Run[] = [{ text: WORDS.notRecorded, style: value }];
  const fieldRows: RightItem[] = [];
  const floors = model.floors;
  const distanceValue = (captureId: string): Run[] => {
    if (valid === undefined) {
      return notRecorded;
    }
    const of = (axis: "A" | "B") =>
      valid.distances.find((d) => d.capture.captureId === captureId && d.axis === axis);
    const a = of("A");
    const b = of("B");
    if (a === undefined && b === undefined) {
      return notRecorded;
    }
    const text = (d: typeof a) =>
      d === undefined ? "none" : feetInches(d.measurement.valueMm / 1000);
    return [{ text: `${text(a)} · ${text(b)}`, style: mono }];
  };
  if (floors.length <= 1) {
    const methods = valid === undefined ? "tape" : methodsOf(valid);
    fieldRows.push({
      kind: "row",
      label: `Long distances A, B (${methods})`,
      value: distanceValue(floors[0]?.captureId ?? ""),
    });
  } else {
    for (const floor of floors) {
      const methods = valid === undefined ? "tape" : methodsOf(valid, floor.captureId);
      fieldRows.push({
        kind: "row",
        label: `A, B, ${floor.label} (${methods})`,
        value: distanceValue(floor.captureId),
      });
    }
  }
  const count = (n: number, one: string, many: string) => (n === 0 ? "none" : n === 1 ? one : many);
  fieldRows.push(
    {
      kind: "row",
      label: "Ceiling heights",
      value:
        valid === undefined
          ? notRecorded
          : [
              {
                text: count(
                  valid.ceilingHeights.length,
                  "1 room",
                  `${valid.ceilingHeights.length} rooms`,
                ),
                style: value,
              },
            ],
    },
    {
      kind: "row",
      label: "Openings",
      value:
        valid === undefined
          ? notRecorded
          : [
              {
                text: count(valid.openings.length, "1", String(valid.openings.length)),
                style: value,
              },
            ],
    },
    {
      kind: "row",
      label: "Floor to floor · landmarks",
      value:
        valid === undefined
          ? notRecorded
          : [
              {
                text:
                  floors.length <= 1
                    ? "none · one floor"
                    : `${count(valid.floorToFloor.length, "1", String(valid.floorToFloor.length))} · ${count(valid.landmarks.length, "1", String(valid.landmarks.length))}`,
                style: value,
              },
            ],
    },
    { kind: "note", lines: canvas.wrap(WORDS.tolerance, TYPE.footnote, RIGHT_WIDTH) },
  );
  const packageRows: RightItem[] = [];
  if (floors.length <= 1) {
    packageRows.push({
      kind: "row",
      label: "Capture id",
      value: [{ text: floors[0]?.captureId ?? "", style: mono }],
    });
  } else {
    for (const floor of floors) {
      packageRows.push({
        kind: "row",
        label: `Capture id, ${floor.label}`,
        value: [{ text: floor.captureId, style: { ...TYPE.ids, color: COLOR.ink } }],
        stacked: true,
      });
    }
  }
  const sealed =
    model.input.sealedAt === undefined
      ? ""
      : ` · sealed ${shortDate(model.input.sealedAt, model.timeZone)}`;
  packageRows.push(
    {
      kind: "row",
      label: "Package",
      value: [{ text: `revision ${verdict.revision}${sealed}`, style: value }],
    },
    {
      kind: "row",
      label: "Files",
      value: [
        {
          text: `${model.fileCount} files · SHA-256 fingerprints · page ${index?.record ?? 0}`,
          style: value,
        },
      ],
    },
  );
  return [
    { title: "Limitations", items: texts(verdict.limitations) },
    { title: "Next actions", items: texts(verdict.nextActions) },
    { title: "Field controls recorded on site", items: fieldRows },
    { title: "Package", items: packageRows },
  ];
}

// MARK: Page geometry

function headingHeight(canvas: Canvas, model: Model): { right: string[]; height: number } {
  const text = `Checked by the Chapter station before this report was issued · rules ${ruleSetLabel(model.verdict.evaluator)} · evaluated ${shortDateTime(model.verdict.evaluatedAt, model.timeZone)}`;
  const right = canvas.wrap(text, RIGHT_TEXT, 590, 2);
  return { right, height: Math.max(19, right.length * 11) };
}

interface BandLayout {
  readonly headline: string;
  readonly summary: readonly string[];
  readonly task: string;
  readonly counts: string;
  readonly statement: readonly string[];
  readonly rightWidth: number;
  readonly height: number;
}

function bandLayout(canvas: Canvas, model: Model): BandLayout {
  const verdict = model.verdict;
  const task = `Task: ${taskWords(verdict)}`;
  const counts = countsLine(model.counts);
  const rightWidth = Math.max(canvas.width(task, TYPE.table), canvas.width(counts, RIGHT_TEXT));
  const inner = 720 - 24 - 3;
  const leftWidth = inner - 16 - rightWidth;
  const summaryStyle: TextStyle = { ...TYPE.table, line: 11.5 };
  const summary = canvas.wrap(verdict.summary, summaryStyle, leftWidth);
  const statement = canvas.wrap(verdict.statement, TYPE.caption, inner);
  const left = 14 + 3 + summary.length * 11.5;
  const right = 11 + 2 + 11;
  const height = 1.5 + 9 + Math.max(left, right) + 5 + statement.length * 9 + 9 + 1.5;
  return {
    headline: verdictHeadline(verdict),
    summary,
    task,
    counts,
    statement,
    rightWidth,
    height,
  };
}

/** Splits the checks into pages (spec 5.4.5). */
export function paginateChecks(canvas: Canvas, model: Model): PageSpec[] {
  const layouts = model.checkRows.map((row) => rowLayout(canvas, row));
  const sections = rightSections(canvas, model, undefined);
  const heading = headingHeight(canvas, model);
  const band = bandLayout(canvas, model);
  const footnote = 5 + canvas.blockHeight(WORDS.checksFootnote, TYPE.footnote, TABLE_WIDTH);
  const pages: PageSpec[] = [];
  let rowIndex = 0;
  let rowStart = { block: 0, line: 0, action: 0 };
  let rowContinued = false;
  let footnoteDone = false;
  let section = 0;
  let item = 0;
  let sectionContinued = false;
  for (let page = 0; page < 1000; page += 1) {
    const first = page === 0;
    const top = 102 + heading.height + 8 + (first ? band.height + 8 : 0);
    // Table.
    const slices: CheckSlice[] = [];
    const tableHeader = rowIndex < layouts.length;
    let y = top + (tableHeader ? 10 + 4 + 0.75 : 0);
    while (rowIndex < layouts.length) {
      const layout = layouts[rowIndex] as RowLayout;
      const available = BOTTOM - y - ROW_CHROME;
      const fit = fitRow(layout, rowStart, available, rowContinued);
      const whole =
        rowStart.block === 0 && rowStart.line === 0 && rowStart.action === 0 && !rowContinued;
      if (
        fit === undefined ||
        (fit.next !== undefined && whole && slices.length > 0 && fit.slice.blocks.length === 0)
      ) {
        break;
      }
      const slice: CheckSlice = { ...fit.slice, row: rowIndex };
      slices.push(slice);
      y += ROW_CHROME + sliceHeight(layout, slice);
      if (fit.next === undefined) {
        rowIndex += 1;
        rowStart = { block: 0, line: 0, action: 0 };
        rowContinued = false;
      } else {
        rowStart = fit.next;
        rowContinued = true;
        break;
      }
    }
    let tableEnds = false;
    if (rowIndex >= layouts.length && !footnoteDone) {
      if (y + footnote <= BOTTOM || !tableHeader) {
        tableEnds = true;
        footnoteDone = true;
      }
    }
    // Right column.
    const right: RightSlice[] = [];
    let ry = top;
    while (section < sections.length) {
      const current = sections[section] as RightSection;
      const head = (right.length > 0 ? 10 : 0) + 9;
      const from = item;
      let used = head;
      let to = from;
      while (to < current.items.length) {
        const h = 3 + itemHeight(current.items[to] as RightItem);
        if (ry + used + h > BOTTOM) {
          break;
        }
        used += h;
        to += 1;
      }
      if (to === from && current.items.length > 0) {
        // Nothing of this section fits here.
        if (right.length === 0 && slices.length === 0 && !tableEnds) {
          // An item taller than a page: place it anyway.
          to = from + 1;
        } else {
          break;
        }
      }
      right.push({ section, continued: sectionContinued, fromItem: from, toItem: to });
      ry += used;
      if (to >= current.items.length) {
        section += 1;
        item = 0;
        sectionContinued = false;
      } else {
        item = to;
        sectionContinued = true;
        break;
      }
    }
    pages.push({
      kind: "checks",
      first,
      table: slices,
      tableHeader: tableHeader && slices.length > 0,
      tableEnds,
      right,
    });
    if (rowIndex >= layouts.length && footnoteDone && section >= sections.length) {
      break;
    }
  }
  return pages;
}

// MARK: Drawing

const VERDICT_LOOK: Record<string, { border: string; text: string; glyph: GlyphKind }> = {
  ready: { border: COLOR.ready, text: COLOR.ready, glyph: "ready" },
  limited: { border: COLOR.limited, text: COLOR.limitedText, glyph: "limited" },
  blocked: { border: COLOR.blocked, text: COLOR.blocked, glyph: "blocked" },
};

export function drawChecksPage(
  ctx: PageContext,
  page: Extract<PageSpec, { kind: "checks" }>,
): void {
  const { canvas, model, index } = ctx;
  drawFrame(ctx, { kicker: [WORDS.captureChecks], statement: "checks" });
  const heading = headingHeight(canvas, model);
  canvas.line(
    page.first ? WORDS.captureChecks : `${WORDS.captureChecks} (continued)`,
    TYPE.section,
    X,
    102 + heading.height - 19,
  );
  heading.right.forEach((line, i) => {
    const w = canvas.measure(line, RIGHT_TEXT);
    canvas.lines(
      [line],
      RIGHT_TEXT,
      X + 720 - w,
      102 + heading.height - heading.right.length * 11 + i * 11,
      w,
    );
  });
  let top = 102 + heading.height + 8;
  if (page.first) {
    top = drawBand(canvas, model, top) + 8;
  }
  // Table.
  let y = top;
  if (page.tableHeader) {
    ["Check", "Result", "What was found", "Next action"].forEach((text, i) =>
      canvas.line(text, TYPE.header, COL_X[i] as number, y),
    );
    y += 10 + 4;
    canvas.rule(X, y, TABLE_WIDTH, COLOR.ink);
    y += 0.75;
  }
  const layouts = new Map<number, RowLayout>();
  for (const slice of page.table) {
    let layout = layouts.get(slice.row);
    if (layout === undefined) {
      layout = rowLayout(canvas, model.checkRows[slice.row] as CheckRow);
      layouts.set(slice.row, layout);
    }
    y = drawSlice(canvas, layout, slice, y);
  }
  if (page.tableEnds) {
    canvas.block(WORDS.checksFootnote, TYPE.footnote, X, y + 5, TABLE_WIDTH);
  }
  // Right column.
  const sections = rightSections(canvas, model, index);
  let ry = top;
  page.right.forEach((part, i) => {
    const section = sections[part.section] as RightSection;
    if (i > 0) {
      ry += 10;
    }
    canvas.line(
      part.continued ? `${section.title} (continued)` : section.title,
      TYPE.kickerInner,
      RIGHT_X,
      ry,
      { maxWidth: RIGHT_WIDTH },
    );
    ry += 9;
    for (const item of section.items.slice(part.fromItem, part.toItem)) {
      ry += 3;
      ry = drawRightItem(canvas, item, ry);
    }
  });
}

function drawRightItem(canvas: Canvas, item: RightItem, top: number): number {
  switch (item.kind) {
    case "text":
      return top + canvas.lines(item.lines, item.style, RIGHT_X, top, RIGHT_WIDTH);
    case "note":
      return top + canvas.lines(item.lines, TYPE.footnote, RIGHT_X, top, RIGHT_WIDTH);
    case "row": {
      let y = top + 3;
      if (item.stacked === true) {
        canvas.line(item.label, ROW_LABEL, RIGHT_X, y, { maxWidth: RIGHT_WIDTH });
        y += 10;
        canvas.runs(item.value, RIGHT_X, y, { width: RIGHT_WIDTH, align: "right" });
        y += 9;
      } else {
        const labelWidth = canvas.width(item.label, ROW_LABEL);
        canvas.line(item.label, ROW_LABEL, RIGHT_X, y, { maxWidth: RIGHT_WIDTH });
        const valueWidth = canvas.runsWidth(item.value);
        if (labelWidth + 6 + valueWidth > RIGHT_WIDTH) {
          const first = item.value[0];
          if (first !== undefined) {
            canvas.line(first.text, first.style, RIGHT_X + labelWidth + 6, y, {
              width: RIGHT_WIDTH - labelWidth - 6,
              align: "right",
            });
          }
        } else {
          canvas.runs(item.value, RIGHT_X, y, { width: RIGHT_WIDTH, align: "right" });
        }
        y += 10;
      }
      y += 3;
      canvas.rule(RIGHT_X, y, RIGHT_WIDTH, COLOR.line);
      return y + 0.75;
    }
  }
}

function drawBand(canvas: Canvas, model: Model, top: number): number {
  const band = bandLayout(canvas, model);
  const look = VERDICT_LOOK[model.verdict.outcome] as (typeof VERDICT_LOOK)[string];
  canvas.roundedBorder(X, top, 720, band.height, 6, 1.5, look.border);
  const innerX = X + 1.5 + 12;
  let y = top + 1.5 + 9;
  drawGlyph(canvas, look.glyph, innerX, y + 1.5, 11);
  canvas.line(band.headline, { ...TYPE.verdictWord, color: look.text }, innerX + 11 + 7, y);
  const summaryStyle: TextStyle = { ...TYPE.table, line: 11.5 };
  canvas.lines(band.summary, summaryStyle, innerX, y + 14 + 3, 720 - 27 - 16 - band.rightWidth);
  const rightX = X + 720 - 1.5 - 12 - band.rightWidth;
  canvas.line(band.task, TYPE.table, rightX, y, { width: band.rightWidth, align: "right" });
  canvas.line(band.counts, RIGHT_TEXT, rightX, y + 11 + 2, {
    width: band.rightWidth,
    align: "right",
  });
  const left = 14 + 3 + band.summary.length * 11.5;
  y += Math.max(left, 24) + 5;
  canvas.lines(band.statement, TYPE.caption, innerX, y, 720 - 27);
  return top + band.height;
}

function drawSlice(canvas: Canvas, layout: RowLayout, slice: CheckSlice, top: number): number {
  const y = top + 3;
  // Column 1: title (" (continued)" muted) and rule id.
  const titleLines = slice.continued ? layout.titleContinued : layout.title;
  if (slice.continued) {
    const plain = canvas.wrap(layout.row.title, TITLE, COLS[0] as number);
    // Draw the continued title with its suffix in muted when it stays on one line.
    if (titleLines.length === 1 && plain.length === 1) {
      canvas.runs(
        [
          { text: layout.row.title, style: TITLE },
          { text: " (continued)", style: { ...TITLE, color: COLOR.muted } },
        ],
        COL_X[0] as number,
        y,
      );
    } else {
      canvas.lines(titleLines, TITLE, COL_X[0] as number, y, COLS[0] as number);
    }
  } else {
    canvas.lines(titleLines, TITLE, COL_X[0] as number, y, COLS[0] as number);
  }
  canvas.lines(
    layout.ruleId,
    RULE_ID,
    COL_X[0] as number,
    y + titleLines.length * TITLE.line + 1,
    COLS[0] as number,
  );
  // Column 2: glyph and result word (first part of a row only).
  if (!slice.continued) {
    drawGlyph(canvas, RESULT_GLYPH_KIND[layout.row.result], COL_X[1] as number, y + 1.5, 8, true);
    canvas.line(
      layout.row.word,
      { font: FONT.semibold, size: 9, line: 11, color: RESULT_TEXT_COLOR[layout.row.result] },
      (COL_X[1] as number) + 12,
      y,
    );
  }
  // Columns 3 and 4: finding blocks.
  let by = y;
  slice.blocks.forEach((part, i) => {
    if (i > 0) {
      by += 3;
    }
    const block = layout.blocks[part.block] as BlockLayout;
    const draw = (pieces: readonly Piece[], x: number, width: number) => {
      let py = by;
      pieces.forEach((piece, j) => {
        py += j === 0 ? 0 : piece.gap;
        canvas.lines([piece.text], piece.style, x, py, width);
        py += piece.style.line;
      });
      return py - by;
    };
    const left = draw(
      block.left.slice(part.fromLine, part.toLine),
      COL_X[2] as number,
      COLS[2] as number,
    );
    const right = draw(
      block.right.slice(part.fromAction, part.toAction),
      COL_X[3] as number,
      COLS[3] as number,
    );
    by += Math.max(left, right);
  });
  const height = sliceHeight(layout, slice);
  canvas.rule(X, top + 3 + height + 3, TABLE_WIDTH, COLOR.line);
  return top + ROW_CHROME + height;
}

/** Number of finding lines the table holds (tests). */
export function checksLayoutForTests(canvas: Canvas, model: Model): number {
  return model.checkRows
    .map((row) => rowLayout(canvas, row))
    .reduce((n, l) => n + l.blocks.length, 0);
}
