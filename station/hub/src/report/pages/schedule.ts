// Room schedule (spec 5.3; artboard 1n): every scanned room largest first per floor with its
// measurements and page, the rooms not scanned, subtotals per floor and the total.

import { notScannedRoomText } from "@chapter/capture-contract";
import { cuFt, fixed, ftIn, plural, sqFt } from "../format.js";
import type { Canvas, Run } from "../layout/canvas.js";
import type { Model, ModelRoom } from "../model.js";
import { COLOR, TYPE, type TextStyle } from "../tokens.js";
import { WORDS } from "../words.js";
import { drawFrame, type PageContext } from "./context.js";
import type { PageSpec, ScheduleRow } from "./index-of-pages.js";

const X = 36;
const WIDTH = 720;
const COLUMNS = [118, 60, 62, 160, 62, 62, 62, 40, 40];
const GAP = 6;
const COLUMN_X = COLUMNS.reduce<number[]>((xs, _w, i) => {
  xs.push(i === 0 ? X : (xs[i - 1] as number) + (COLUMNS[i - 1] as number) + GAP);
  return xs;
}, []);
const MAX_ROOM_ROWS = 24;
const HEADER_HEIGHT = 20 + 4 + 0.75;
const TOP_BLOCK = 19 + 6 + HEADER_HEIGHT + 6;
const TOTAL_HEIGHT = 5 + 11 + 5 + 0.75;
const FLOOR_ROW_HEIGHT = 7 + 9 + 2;
const SKIPPED_HEIGHT = 2 + 11 + 2 + 0.75;
const SIMPLE_HEIGHT = 2.5 + 11 + 2.5 + 0.75;

const NAME: TextStyle = TYPE.tableBold;
const TAG: TextStyle = TYPE.caption;
const MUTED: TextStyle = { ...TYPE.table, color: COLOR.muted };

function nameLines(canvas: Canvas, room: ModelRoom): string[] {
  return canvas.wrap(room.name, NAME, COLUMNS[0] as number, 2);
}

/** Whether the ceiling and volume cells put " approx." on a line of its own (too wide). */
function approxOnOwnLine(canvas: Canvas, room: ModelRoom): { ceiling: boolean; volume: boolean } {
  if (!room.approximate) {
    return { ceiling: false, volume: false };
  }
  const approx = canvas.width(" approx.", MUTED);
  return {
    ceiling: canvas.width(room.words.ceiling, TYPE.tableMono) + approx > (COLUMNS[5] as number),
    volume: canvas.width(room.words.volume, TYPE.table) + approx > (COLUMNS[6] as number),
  };
}

/** Height of a room row (padding, content, rule). */
export function roomRowHeight(canvas: Canvas, room: ModelRoom): number {
  const name = nameLines(canvas, room).length * NAME.line + (room.unlabeled ? 1 + TAG.line : 0);
  const split = approxOnOwnLine(canvas, room);
  const dims = room.rectangular && !split.ceiling && !split.volume ? 11 : 11 + 1 + 11;
  return 2.5 + Math.max(name, dims, 11) + 2.5 + 0.75;
}

/** Every row of the schedule in order (floor rows, rooms, not scanned, subtotals). */
export function scheduleRows(canvas: Canvas, model: Model): ScheduleRow[] {
  if (!model.totals.readable) {
    return [{ kind: "empty" }];
  }
  const multi = model.floors.length > 1;
  const rows: ScheduleRow[] = [];
  for (const floor of model.floors) {
    if (multi) {
      rows.push({ kind: "floor", floor: floor.index });
    }
    if (floor.metrics === undefined) {
      rows.push({ kind: "unavailable", floor: floor.index });
    }
    for (const room of floor.rooms) {
      rows.push({ kind: "room", room: room.number, height: roomRowHeight(canvas, room) });
    }
    floor.skipped.forEach((_room, i) =>
      rows.push({ kind: "skipped", floor: floor.index, skipped: i }),
    );
    if (multi && floor.metrics !== undefined) {
      rows.push({ kind: "subtotal", floor: floor.index });
    }
  }
  return rows;
}

function rowHeight(row: ScheduleRow): number {
  switch (row.kind) {
    case "floor":
      return FLOOR_ROW_HEIGHT;
    case "room":
      return row.height;
    case "skipped":
      return SKIPPED_HEIGHT;
    case "unavailable":
    case "empty":
      return SIMPLE_HEIGHT;
    case "subtotal":
      return TOTAL_HEIGHT;
  }
}

/** Splits the schedule into pages (spec 5.3.4). */
export function paginateSchedule(canvas: Canvas, model: Model): PageSpec[] {
  const rows = scheduleRows(canvas, model);
  const footnote = 6 + canvas.blockHeight(WORDS.scheduleFootnote, TYPE.footnote, WIDTH);
  const tail = (model.totals.readable ? TOTAL_HEIGHT : 0) + footnote;
  // Groups that never split: a floor row with the row after it; not-scanned and subtotal rows
  // with the row before them.
  const groups: ScheduleRow[][] = [];
  let pendingFloor: ScheduleRow | undefined;
  for (const row of rows) {
    if (row.kind === "floor") {
      pendingFloor = row;
      continue;
    }
    const last = groups[groups.length - 1];
    if (
      (row.kind === "skipped" || row.kind === "subtotal") &&
      pendingFloor === undefined &&
      last !== undefined
    ) {
      last.push(row);
      continue;
    }
    groups.push(pendingFloor === undefined ? [row] : [pendingFloor, row]);
    pendingFloor = undefined;
  }
  if (pendingFloor !== undefined) {
    groups.push([pendingFloor]);
  }
  const pages: ScheduleRow[][] = [[]];
  let used = TOP_BLOCK;
  let roomRows = 0;
  groups.forEach((group, i) => {
    const height = group.reduce((sum, r) => sum + rowHeight(r), 0);
    const rooms = group.filter((r) => r.kind === "room").length;
    const limit = 426 - (i === groups.length - 1 ? tail : 0);
    const page = pages[pages.length - 1] as ScheduleRow[];
    if (page.length > 0 && (used + height > limit || roomRows + rooms > MAX_ROOM_ROWS)) {
      pages.push([...group]);
      used = TOP_BLOCK + height;
      roomRows = rooms;
      return;
    }
    page.push(...group);
    used += height;
    roomRows += rooms;
  });
  // The total and footnote need room on the last page; a page of their own otherwise.
  const lastPage = pages[pages.length - 1] ?? [];
  const lastUsed = TOP_BLOCK + lastPage.reduce((sum, r) => sum + rowHeight(r), 0);
  if (lastUsed + tail > 426 && lastPage.length > 0) {
    pages.push([]);
  }
  return pages.map((rows, i) => ({
    kind: "schedule",
    rows,
    first: i === 0,
    last: i === pages.length - 1,
  }));
}

function headingRight(model: Model): string {
  const rooms = model.totals.roomsScanned;
  const skipped = model.floors.reduce((n, floor) => n + floor.skipped.length, 0);
  const notScanned = skipped > 0 ? ` · ${skipped} not scanned` : "";
  if (model.floors.length <= 1) {
    const label = model.floors[0]?.label ?? "";
    return `${label} · ${plural(rooms, "room")} scanned${notScanned} · largest first`;
  }
  return `${plural(rooms, "room")} scanned on ${model.floors.length} floors${notScanned} · largest first per floor`;
}

function cell(
  canvas: Canvas,
  column: number,
  text: string,
  style: TextStyle,
  top: number,
  align: "left" | "right" = "left",
): void {
  const x = COLUMN_X[column] as number;
  const width = COLUMNS[column] as number;
  if (align === "right") {
    const w = canvas.width(text, style);
    canvas.line(text, style, x + width - w, top);
  } else {
    canvas.line(text, style, x, top);
  }
}

function runsCell(canvas: Canvas, column: number, runs: readonly Run[], top: number): void {
  const x = COLUMN_X[column] as number;
  const width = COLUMNS[column] as number;
  canvas.runs(runs, x, top, { width, align: "right" });
}

export function drawSchedulePage(
  ctx: PageContext,
  rows: readonly ScheduleRow[],
  first: boolean,
  last: boolean,
): void {
  const { canvas, model, index } = ctx;
  drawFrame(ctx, { kicker: [WORDS.roomSchedule], statement: "short" });
  let y = 102;
  const right = headingRight(model);
  const rightWidth = canvas.width(right, MUTED);
  canvas.line(first ? WORDS.roomSchedule : `${WORDS.roomSchedule} (continued)`, TYPE.section, X, y);
  canvas.line(right, MUTED, X + WIDTH - rightWidth, y + 19 - 11);
  y += 19 + 6;

  // Header (two-line cells aligned to the bottom).
  const headers: Array<[string, string | undefined, "left" | "right"]> = [
    ["Room", undefined, "left"],
    ["Floor area", "sq ft", "right"],
    ["Wall area", "sq ft", "right"],
    ["Dimensions", "(B) bounding box · (I) inscribed", "left"],
    ["Perimeter", undefined, "right"],
    ["Ceiling", "height", "right"],
    ["Volume", "cu ft", "right"],
    ["Items", undefined, "right"],
    ["Page", undefined, "right"],
  ];
  headers.forEach(([line1, line2, align], column) => {
    if (line2 === undefined) {
      cell(canvas, column, line1, TYPE.header, y + 10, align);
    } else {
      cell(canvas, column, line1, TYPE.header, y, align);
      cell(canvas, column, line2, TYPE.header, y + 10, align);
    }
  });
  y += 20 + 4;
  canvas.rule(X, y, WIDTH, COLOR.ink);
  y += 0.75 + 6;

  for (const row of rows) {
    y = drawRow(ctx, row, y);
  }
  if (last) {
    if (model.totals.readable) {
      y = drawTotal(canvas, model, y);
    }
    y += 6;
    canvas.block(WORDS.scheduleFootnote, TYPE.footnote, X, y, WIDTH);
  }
  void index;
}

function drawRow(ctx: PageContext, row: ScheduleRow, top: number): number {
  const { canvas, model, index } = ctx;
  switch (row.kind) {
    case "empty":
      canvas.line(WORDS.noRoomsMeasured, MUTED, X, top + 2.5);
      canvas.rule(X, top + 2.5 + 11 + 2.5, WIDTH, COLOR.line);
      return top + SIMPLE_HEIGHT;
    case "floor":
      canvas.line(model.floors[row.floor]?.label ?? "", TYPE.kickerInner, X, top + 7);
      return top + FLOOR_ROW_HEIGHT;
    case "unavailable":
      canvas.line(
        `Plan not available for ${model.floors[row.floor]?.label ?? ""}`,
        MUTED,
        X,
        top + 2.5,
      );
      canvas.rule(X, top + 2.5 + 11 + 2.5, WIDTH, COLOR.line);
      return top + SIMPLE_HEIGHT;
    case "skipped": {
      const floor = model.floors[row.floor];
      const room = floor?.skipped[row.skipped];
      if (room === undefined) {
        return top;
      }
      const status = room.kind === "omitted" ? "Not scanned" : "Could not enter";
      const text = `${status}${room.reason === undefined ? "" : ` · ${room.reason}`} · no measurements, not on the plan`;
      const mutedBold: TextStyle = { ...NAME, color: COLOR.muted };
      canvas.line(room.name, mutedBold, X, top + 2, { maxWidth: COLUMNS[0] });
      const middleX = X + (COLUMNS[0] as number) + GAP;
      const middleWidth = WIDTH - (COLUMNS[0] as number) - 40 - 2 * GAP;
      canvas.line(text, MUTED, middleX, top + 2, { maxWidth: middleWidth });
      const dash = "—";
      canvas.line(dash, MUTED, X + WIDTH - canvas.width(dash, MUTED), top + 2);
      canvas.rule(X, top + 2 + 11 + 2, WIDTH, COLOR.line);
      void notScannedRoomText;
      return top + SKIPPED_HEIGHT;
    }
    case "subtotal": {
      const floor = model.floors[row.floor];
      if (floor === undefined || floor.metrics === undefined) {
        return top;
      }
      const t = floor.metrics.totals;
      return drawTotalRow(
        canvas,
        `${floor.label}, scanned rooms`,
        {
          area: t.livableAreaM2,
          wall: t.wallAreaM2,
          perimeter: t.perimeterM,
          volume: t.volumeM3,
          volumeApproximate: t.volumeIsApproximate,
          items: floor.rooms.reduce((n, room) => n + room.items.length, 0),
        },
        top,
        COLOR.line,
      );
    }
    case "room": {
      const room = model.rooms[row.room - 1];
      if (room === undefined) {
        return top;
      }
      const content = row.height - 2.5 - 2.5 - 0.75;
      const middle = (lineCount: number, extra = 0) =>
        top + 2.5 + (content - lineCount * 11 - extra) / 2;
      // Name (and tag).
      const names = nameLines(canvas, room);
      const nameHeight = names.length * NAME.line + (room.unlabeled ? 1 + TAG.line : 0);
      const nameTop = top + 2.5 + (content - nameHeight) / 2;
      canvas.lines(names, NAME, X, nameTop, COLUMNS[0] as number);
      if (room.unlabeled) {
        canvas.line(WORDS.unlabeledTag, TAG, X, nameTop + names.length * NAME.line + 1);
      }
      const single = middle(1);
      cell(canvas, 1, room.words.area, TYPE.table, single, "right");
      cell(canvas, 2, room.words.wall, TYPE.table, single, "right");
      if (room.rectangular) {
        cell(canvas, 3, `(B) ${room.words.bbox}`, TYPE.tableMono, single);
      } else {
        const dimsTop = middle(2, 1);
        cell(canvas, 3, `(B) ${room.words.bbox}`, TYPE.tableMono, dimsTop);
        cell(
          canvas,
          3,
          `(I) ${room.words.inscribed}`,
          { ...TYPE.tableMono, color: COLOR.muted },
          dimsTop + 12,
        );
      }
      cell(canvas, 4, room.words.perimeter, TYPE.tableMono, single, "right");
      const approx: Run[] = room.approximate ? [{ text: " approx.", style: MUTED }] : [];
      const split = approxOnOwnLine(canvas, room);
      const twoTop = middle(2, 1);
      if (split.ceiling) {
        cell(canvas, 5, room.words.ceiling, TYPE.tableMono, twoTop, "right");
        cell(canvas, 5, "approx.", MUTED, twoTop + 12, "right");
      } else {
        runsCell(
          canvas,
          5,
          [{ text: room.words.ceiling, style: TYPE.tableMono }, ...approx],
          single,
        );
      }
      if (split.volume) {
        cell(canvas, 6, room.words.volume, TYPE.table, twoTop, "right");
        cell(canvas, 6, "approx.", MUTED, twoTop + 12, "right");
      } else {
        runsCell(canvas, 6, [{ text: room.words.volume, style: TYPE.table }, ...approx], single);
      }
      cell(canvas, 7, String(room.items.length), TYPE.table, single, "right");
      cell(canvas, 8, String(index.room(room.number)), MUTED, single, "right");
      canvas.rule(X, top + row.height - 0.75, WIDTH, COLOR.line);
      return top + row.height;
    }
  }
}

interface TotalValues {
  readonly area: number;
  readonly wall: number;
  readonly perimeter: number;
  readonly volume: number;
  /** A room's ceiling height is approximate (the cover's "cu ft approx." rule). */
  readonly volumeApproximate: boolean;
  readonly items: number;
}

function drawTotalRow(
  canvas: Canvas,
  label: string,
  values: TotalValues,
  top: number,
  rule: string,
): number {
  const y = top + 5;
  cell(canvas, 0, label, TYPE.tableBold, y);
  cell(canvas, 1, sqFt(values.area), TYPE.tableBold, y, "right");
  cell(canvas, 2, sqFt(values.wall), TYPE.tableBold, y, "right");
  cell(canvas, 3, `${fixed(values.area, 1)} m² · ${fixed(values.wall, 1)} m²`, MUTED, y);
  cell(canvas, 4, ftIn(values.perimeter), TYPE.tableMono, y, "right");
  if (values.volumeApproximate) {
    // " approx." as on the room rows, on the same line: it may run into the ceiling column,
    // which is empty on total rows.
    canvas.runs(
      [
        { text: cuFt(values.volume), style: TYPE.tableBold },
        { text: " approx.", style: MUTED },
      ],
      COLUMN_X[5] as number,
      y,
      { width: (COLUMNS[5] as number) + GAP + (COLUMNS[6] as number), align: "right" },
    );
  } else {
    cell(canvas, 6, cuFt(values.volume), TYPE.tableBold, y, "right");
  }
  cell(canvas, 7, String(values.items), TYPE.tableBold, y, "right");
  canvas.rule(X, top + 5 + 11 + 5, WIDTH, rule);
  return top + TOTAL_HEIGHT;
}

function drawTotal(canvas: Canvas, model: Model, top: number): number {
  const t = model.totals;
  return drawTotalRow(
    canvas,
    "Total, scanned rooms",
    {
      area: t.livableAreaM2,
      wall: t.wallAreaM2,
      perimeter: t.perimeterM,
      volume: t.volumeM3,
      volumeApproximate: t.volumeIsApproximate,
      items: t.items,
    },
    top,
    COLOR.ink,
  );
}
