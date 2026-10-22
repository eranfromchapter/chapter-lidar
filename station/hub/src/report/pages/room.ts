// Room pages (spec 5.5; artboards 1t living, 1w kitchen, 1x closet, 1y Room 4, 1z/1aa long name
// and continuation): the room drawing with key plan and legend on the left; title, tiles,
// dimension line, note, items table and footnote on the right.

import { cuFt, fixed, sqFt } from "../format.js";
import type { Canvas, Run } from "../layout/canvas.js";
import { ITEM_GROUPS, type Model, type ModelFloor, type ModelRoom } from "../model.js";
import { drawFloor, fitFloor } from "../draw/floor.js";
import { drawMarker } from "../draw/glyphs.js";
import { drawRoom, layoutRoom } from "../draw/room.js";
import { COLOR, FONT, TYPE, type TextStyle } from "../tokens.js";
import { WORDS } from "../words.js";
import { drawFrame, type PageContext } from "./context.js";
import type { ItemLine, PageSpec } from "./index-of-pages.js";

const RX = 341;
const RW = 415;
const TABLE_COLS = [14, RW - 14 - 62 - 62 - 70 - 32, 62, 62, 70];
const TABLE_X = TABLE_COLS.reduce<number[]>((xs, _w, i) => {
  xs.push(i === 0 ? RX : (xs[i - 1] as number) + (TABLE_COLS[i - 1] as number) + 8);
  return xs;
}, []);
const HEADER_H = 10 + 3 + 0.75;
const GROUP_H = 7 + 9 + 2;
const ITEM_H = 2 + 11 + 2 + 0.75;
const TILES_H = 6 + 9 + 1 + 13 + 1 + 9 + 6;
const FIRST_PAGE_ROWS = 12;
const NEXT_PAGE_ROWS = 24;

const DIM_LINE: TextStyle = { ...TYPE.dense, line: 10.5, color: COLOR.muted };
const NOTE: TextStyle = { ...TYPE.dense, line: 10.5 };
const CONT_NOTE: TextStyle = { ...TYPE.dense, color: COLOR.muted };
const TAG: TextStyle = { ...TYPE.table, color: COLOR.muted };

function titleStyle(room: ModelRoom): TextStyle {
  return room.name.length > 40 ? TYPE.roomTitleLong : TYPE.roomTitle;
}

function titleLines(canvas: Canvas, room: ModelRoom, continued: boolean): string[] {
  return canvas.wrap(continued ? `${room.name} (continued)` : room.name, titleStyle(room), RW, 2);
}

function titleHeight(canvas: Canvas, room: ModelRoom, continued: boolean): number {
  return (
    titleLines(canvas, room, continued).length * titleStyle(room).line +
    (room.unlabeled ? 3 + 11 : 0)
  );
}

export function dimensionLine(room: ModelRoom): string {
  const inscribed = room.rectangular
    ? " · rectangular room"
    : ` · inscribed rectangle ${room.words.inscribed}`;
  const walls =
    room.words.wallIncl !== room.words.wall
      ? ` · walls ${room.words.wallIncl} sq ft incl. openings, ${room.words.wall} excl.`
      : ` · walls ${room.words.wall} sq ft excl. openings`;
  return `Bounding box ${room.words.bbox}${inscribed}${walls}`;
}

export function noteText(room: ModelRoom): string | undefined {
  const sentences: string[] = [];
  if (room.items.length === 0) {
    sentences.push(WORDS.noItemsNote);
  }
  if (room.approximate) {
    sentences.push(WORDS.approxCeilingNote);
  }
  return sentences.length === 0 ? undefined : sentences.join(" ");
}

function footnoteText(model: Model, room: ModelRoom): string {
  const base = room.items.length > 0 ? WORDS.itemsFootnote : WORDS.noItemsFootnote;
  return model.photosOmitted ? `${base}${WORDS.photosOmittedFootnote}` : base;
}

/** Item lines of the whole table: group rows and item rows in table order. */
function tableLines(room: ModelRoom): ItemLine[] {
  const lines: ItemLine[] = [];
  ITEM_GROUPS.forEach((group, g) => {
    const items = room.items
      .map((item, i) => ({ item, i }))
      .filter(({ item }) => item.group === group.group);
    if (items.length === 0) {
      return;
    }
    lines.push({ kind: "group", group: g, continued: false });
    for (const { i } of items) {
      lines.push({ kind: "item", item: i });
    }
  });
  return lines;
}

/** Splits a room into its room page and continuation pages (spec 5.5.6). */
export function paginateRoom(canvas: Canvas, model: Model, room: ModelRoom): PageSpec[] {
  const all = tableLines(room);
  const footnote = canvas.blockHeight(footnoteText(model, room), TYPE.footnote, RW);
  const pages: Array<{ lines: ItemLine[] }> = [];
  let index = 0;
  const total = room.items.length;
  while (pages.length === 0 || index < all.length) {
    const first = pages.length === 0;
    let used = titleHeight(canvas, room, !first) + 8;
    if (first) {
      used += TILES_H + 8 + canvas.blockHeight(dimensionLine(room), DIM_LINE, RW) + 8;
      const note = noteText(room);
      if (note !== undefined) {
        used += 1.5 + 6 + canvas.blockHeight(note, NOTE, RW - 19.5) + 6 + 8;
      }
    }
    const lines: ItemLine[] = [];
    if (all.length > 0) {
      used += HEADER_H;
      // A group split over pages repeats its group row first.
      const previous = all[index - 1];
      const current = all[index];
      if (!first && current?.kind === "item" && previous !== undefined) {
        const group = ITEM_GROUPS.findIndex((g) => g.group === room.items[current.item]?.group);
        lines.push({ kind: "group", group, continued: true });
        used += GROUP_H;
      }
      const cap = first ? FIRST_PAGE_ROWS : NEXT_PAGE_ROWS;
      let rows = 0;
      // Room for the continuation note and the footnote.
      const reserve = 8 + 10 + 8 + footnote;
      while (index < all.length) {
        const line = all[index] as ItemLine;
        const h = line.kind === "group" ? GROUP_H : ITEM_H;
        // A group row never ends a page.
        const next = all[index + 1];
        const extra = line.kind === "group" && next !== undefined ? ITEM_H : 0;
        if (line.kind === "item" && rows >= cap) {
          break;
        }
        if (used + h + extra + reserve > 426 && rows > 0) {
          break;
        }
        lines.push(line);
        used += h;
        if (line.kind === "item") {
          rows += 1;
        }
        index += 1;
      }
    }
    pages.push({ lines });
    if (all.length === 0) {
      break;
    }
  }
  const firstRowOf = (lines: readonly ItemLine[]) => {
    const item = lines.find((l) => l.kind === "item");
    return item === undefined ? 0 : rowNumber(room, (item as { item: number }).item);
  };
  return pages.map((page, i) => {
    let note: string | undefined;
    if (pages.length > 1) {
      if (i < pages.length - 1) {
        note = `Continued on the next page: rows ${firstRowOf((pages[i + 1] as { lines: ItemLine[] }).lines)} to ${total} of ${total}.`;
      } else {
        note = `End of item list. Rows ${firstRowOf(page.lines)} to ${total} of ${total}.`;
      }
    }
    return {
      kind: "room" as const,
      room: room.number,
      first: i === 0,
      lines: page.lines,
      ...(note === undefined ? {} : { note }),
    };
  });
}

/** 1-based row number of an item in table order. */
function rowNumber(room: ModelRoom, item: number): number {
  const order = tableLines(room)
    .filter((l) => l.kind === "item")
    .map((l) => (l as { item: number }).item);
  return order.indexOf(item) + 1;
}

export function roomKicker(
  model: Model,
  room: ModelRoom,
  continued: boolean,
  suffix?: string,
): string[] {
  const floor = model.floors[room.floorIndex] as ModelFloor;
  const parts = model.floors.length > 1 ? [floor.label] : [];
  parts.push(`Room ${room.number} of ${model.rooms.length}`);
  if (suffix !== undefined) {
    parts.push(suffix);
  }
  if (continued) {
    parts.push("continued");
  }
  return parts;
}

export function drawRoomPage(ctx: PageContext, page: Extract<PageSpec, { kind: "room" }>): void {
  const { canvas, model } = ctx;
  const room = model.rooms[page.room - 1] as ModelRoom;
  const floor = model.floors[room.floorIndex] as ModelFloor;
  drawFrame(ctx, {
    kicker: roomKicker(model, room, !page.first),
    statement: "short",
    captureId: floor.captureId,
  });
  drawLeftColumn(canvas, floor, room);

  // Right column.
  let y = 102;
  const style = titleStyle(room);
  y += canvas.lines(titleLines(canvas, room, !page.first), style, RX, y, RW);
  if (room.unlabeled) {
    y += 3;
    canvas.line(WORDS.unlabeledRoomTag, TAG, RX, y);
    y += 11;
  }
  y += 8;
  if (page.first) {
    drawTiles(canvas, room, y);
    y += TILES_H + 8;
    y += canvas.block(dimensionLine(room), DIM_LINE, RX, y, RW);
    y += 8;
    const note = noteText(room);
    if (note !== undefined) {
      const lines = canvas.wrap(note, NOTE, RW - 19.5);
      const height = 0.75 + 6 + lines.length * NOTE.line + 6 + 0.75;
      canvas.roundedBorder(RX, y, RW, height, 4, 0.75, COLOR.line);
      canvas.lines(lines, NOTE, RX + 0.75 + 9, y + 0.75 + 6, RW - 19.5);
      y += height + 8;
    }
  }
  if (page.lines.length > 0) {
    y = drawTable(canvas, room, page.lines, y);
    if (page.note !== undefined) {
      y += 8;
      canvas.line(page.note, CONT_NOTE, RX, y, { maxWidth: RW });
    }
  }
  const footnote = footnoteText(model, room);
  const lines = canvas.wrap(footnote, TYPE.footnote, RW);
  canvas.lines(lines, TYPE.footnote, RX, 528 - lines.length * TYPE.footnote.line, RW);
}

const TILE_KICKER: TextStyle = { ...TYPE.caption, tracking: 1, upper: true };
const TILE_METRIC: TextStyle = TYPE.caption;

function drawTiles(canvas: Canvas, room: ModelRoom, top: number): void {
  const m = room.metrics;
  const approx = room.approximate ? " · approx." : "";
  const tiles: Array<[string, string, string]> = [
    ["Floor area", `${room.words.area} sq ft`, `${fixed(m.floorAreaM2, 1)} m²`],
    ["Ceiling", room.words.ceiling, `${fixed(m.ceiling.heightM, 2)} m${approx}`],
    ["Volume", `${cuFt(m.volumeM3)} cu ft`, `${fixed(m.volumeM3, 1)} m³${approx}`],
    ["Perimeter", room.words.perimeter, `${fixed(m.perimeterM, 1)} m`],
  ];
  const width = (RW - 18) / 4;
  tiles.forEach(([kicker, value, metric], i) => {
    const x = RX + i * (width + 6);
    canvas.roundedFill(x, top, width, TILES_H, 4, COLOR.ground);
    canvas.line(kicker, TILE_KICKER, x + 8, top + 6, { maxWidth: width - 16 });
    let valueStyle: TextStyle = TYPE.tileValue;
    while (canvas.width(value, valueStyle) > width - 16 && valueStyle.size > 9) {
      valueStyle = { ...valueStyle, size: Math.max(9, valueStyle.size - 0.75) };
    }
    canvas.line(value, valueStyle, x + 8, top + 6 + 9 + 1, { maxWidth: width - 16 });
    canvas.line(metric, TILE_METRIC, x + 8, top + 6 + 9 + 1 + 13 + 1, { maxWidth: width - 16 });
  });
  void sqFt;
}

function drawTable(
  canvas: Canvas,
  room: ModelRoom,
  lines: readonly ItemLine[],
  top: number,
): number {
  let y = top;
  const header = ["", "Item", "W", "H", "D"];
  header.forEach((text, i) => {
    if (text !== "") {
      canvas.line(text, TYPE.header, TABLE_X[i] as number, y);
    }
  });
  y += 10 + 3;
  canvas.rule(RX, y, RW, COLOR.ink);
  y += 0.75;
  const counts = new Map<string, number>();
  room.items.forEach((item) => counts.set(item.group, (counts.get(item.group) ?? 0) + 1));
  for (const line of lines) {
    if (line.kind === "group") {
      const group = ITEM_GROUPS[line.group];
      if (group === undefined) {
        continue;
      }
      const label = `${group.label} · ${counts.get(group.group) ?? 0}${line.continued ? " · continued" : ""}`;
      canvas.line(label, TYPE.kickerInner, TABLE_X[1] as number, y + 7, {
        maxWidth: TABLE_COLS[1],
      });
      if (group.group === "openings") {
        canvas.line("Area", TYPE.caption, TABLE_X[4] as number, y + 7);
      }
      y += GROUP_H;
      continue;
    }
    const item = room.items[line.item];
    if (item === undefined) {
      continue;
    }
    const shape = ITEM_GROUPS.find((g) => g.group === item.group)?.shape ?? "circle";
    drawMarker(canvas, shape, (TABLE_X[0] as number) + 5.5, y + 2 + 5.5, 11, String(item.number));
    const name: Run[] = [{ text: item.name, style: TYPE.table }];
    if (item.low) {
      name.push({ text: " approx.", style: { ...TYPE.table, color: COLOR.muted } });
    }
    canvas.runs(name, TABLE_X[1] as number, y + 2);
    const mono: TextStyle = { font: FONT.mono, size: 9, line: 11, color: COLOR.ink };
    canvas.line(item.w, mono, TABLE_X[2] as number, y + 2);
    canvas.line(item.h, mono, TABLE_X[3] as number, y + 2);
    canvas.line(item.d, mono, TABLE_X[4] as number, y + 2);
    y += 2 + 11 + 2;
    canvas.rule(RX, y, RW, COLOR.line);
    y += 0.75;
  }
  return y;
}

// MARK: Left column

const LEGEND_TEXT: TextStyle = { ...TYPE.caption, color: COLOR.ink };
const LEGEND_MUTED: TextStyle = TYPE.caption;

function drawLeftColumn(canvas: Canvas, floor: ModelFloor, room: ModelRoom): void {
  const layout = layoutRoom(canvas, floor, room);
  if (layout !== undefined) {
    drawRoom(canvas, floor, room, layout);
  }
  // Bottom row: key plan, then the legend.
  const keyTop = 528 - 48 - 3 - 9;
  const keyView = fitFloor(floor, {
    box: { x: 36, y: keyTop, width: 60, height: 48 },
    minWall: 0.5,
  });
  if (keyView === undefined) {
    const doc = canvas.doc;
    doc.save();
    doc
      .roundedRect(36.375, keyTop + 0.375, 59.25, 47.25, 3)
      .lineWidth(0.75)
      .dash(3, { space: 2 })
      .strokeColor(COLOR.muted)
      .stroke();
    doc.restore();
  } else {
    drawFloor(canvas, floor, keyView, {
      minWall: 0.5,
      labels: false,
      keyRoomId: room.metrics.roomId,
    });
  }
  canvas.line(WORDS.keyPlan, TYPE.caption, 36, keyTop + 48 + 3);

  const legendX = 36 + 60 + 12;
  const legendWidth = 329 - legendX;
  const note = canvas.wrap(WORDS.roomLegendNote, TYPE.caption, legendWidth);
  // Marker legend (wraps).
  const entries: Array<[string, (typeof ITEM_GROUPS)[number]["shape"]]> = [
    ["Furniture", "circle"],
    ["Fixture", "triangle"],
    ["Appliance", "diamond"],
    ["Opening", "square"],
    ["Other", "pentagon"],
  ];
  const markerRows: Array<Array<[string, (typeof ITEM_GROUPS)[number]["shape"], number]>> = [[]];
  let rowWidth = 0;
  for (const [text, shape] of entries) {
    const w = 11 + 5 + canvas.width(text, LEGEND_MUTED) + 4 + 5;
    if (rowWidth + w > legendWidth && rowWidth > 0) {
      markerRows.push([]);
      rowWidth = 0;
    }
    (
      markerRows[markerRows.length - 1] as Array<
        [string, (typeof ITEM_GROUPS)[number]["shape"], number]
      >
    ).push([text, shape, rowWidth]);
    rowWidth += w;
  }
  const height = 9 + 3 + markerRows.length * 11 + (markerRows.length - 1) * 5 + 3 + note.length * 9;
  let y = 528 - height;
  // Row 1: bounding box and inscribed rectangle samples.
  const doc = canvas.doc;
  const sample = (x: number, dash: [number, number], round: boolean) => {
    doc.save();
    doc
      .moveTo(x, y + 4.5)
      .lineTo(x + 22, y + 4.5)
      .lineWidth(0.75)
      .dash(dash[0], { space: dash[1] })
      .lineCap(round ? "round" : "butt")
      .strokeColor(COLOR.muted)
      .stroke();
    doc.restore();
  };
  sample(legendX, [3, 2], false);
  let x = legendX + 22 + 6;
  x += canvas.line(WORDS.boundingBox, LEGEND_TEXT, x, y) + 6 + 6;
  sample(x, [0.6, 2], true);
  canvas.line(WORDS.inscribedRectangle, LEGEND_TEXT, x + 22 + 6, y);
  y += 9 + 3;
  for (const row of markerRows) {
    for (const [text, shape, offset] of row) {
      drawMarker(canvas, shape, legendX + offset + 5.5, y + 5.5, 11);
      canvas.line(text, LEGEND_MUTED, legendX + offset + 11 + 5, y + 1);
    }
    y += 11 + 5;
  }
  y -= 5;
  y += 3;
  canvas.lines(note, TYPE.caption, legendX, y, legendWidth);
}
