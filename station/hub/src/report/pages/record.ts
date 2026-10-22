// Package record pages (spec 5.7, not drawn; owner default Q-E): the capture record, the
// captures, and every file of the package with its SHA-256 and where it is (the HUB folder, or
// the station link that needs Entra sign-in).

import { formatBytes, shortDateTime, time } from "../format.js";
import type { Canvas } from "../layout/canvas.js";
import type { ReportFile } from "../input.js";
import type { Model } from "../model.js";
import { COLOR, TYPE, type TextStyle } from "../tokens.js";
import { WORDS } from "../words.js";
import { drawFrame, type PageContext } from "./context.js";
import type { PageSpec, RecordBlock } from "./index-of-pages.js";

const X = 36;
const WIDTH = 720;
const BOTTOM = 528;
const KEY_WIDTH = 120;
const CAPTURE_COLS = [100, 60, 190, 120, 226];
const FILE_COLS = [260, 170, 278];
const GAP = 6;

const KEY: TextStyle = { ...TYPE.dense, color: COLOR.muted };
const VALUE: TextStyle = TYPE.dense;
const MONO: TextStyle = { ...TYPE.ids, color: COLOR.ink, size: 8.25, line: 10 };
const MUTED_SMALL: TextStyle = TYPE.caption;
const IDS: TextStyle = TYPE.ids;
const PARAGRAPH: TextStyle = TYPE.footnote;
const RIGHT: TextStyle = { ...TYPE.table, color: COLOR.muted };

const xs = (cols: readonly number[]) =>
  cols.reduce<number[]>((acc, _w, i) => {
    acc.push(i === 0 ? X : (acc[i - 1] as number) + (cols[i - 1] as number) + GAP);
    return acc;
  }, []);
const CAPTURE_X = xs(CAPTURE_COLS);
const FILE_X = xs(FILE_COLS);

interface Cell {
  readonly lines: ReadonlyArray<{ text: string; style: TextStyle; link?: string }>;
}

const cellHeight = (cell: Cell) => cell.lines.reduce((sum, line) => sum + line.style.line, 0);

function wrapCell(
  canvas: Canvas,
  text: string,
  style: TextStyle,
  width: number,
  link?: string,
): Cell["lines"] {
  return canvas
    .wrap(text, style, width)
    .map((line) => ({ text: line, style, ...(link === undefined ? {} : { link }) }));
}

const MODE_LABEL: Record<string, string> = {
  room: "One room",
  floor: "Whole floor",
  exterior: "Exterior",
};

function recordRows(model: Model): Array<{ key: string; value: string; mono?: boolean }> {
  const record = model.input.captureRecord;
  const tz = model.timeZone;
  if (record === undefined) {
    return [{ key: "Capture record", value: WORDS.noCaptureRecord }];
  }
  const device = record.device;
  const deviceText = `${device.marketingName === undefined ? device.model : `${device.marketingName} (${device.model})`} · ${device.osName} ${device.osVersion} · LiDAR ${device.hasLidar ? "yes" : "no"}`;
  const project = record.hub.projectName;
  return [
    { key: "Address", value: record.address.formatted },
    {
      key: "Address confirmed on site",
      value: record.address.confirmedOnSite
        ? record.address.confirmedAt === undefined
          ? "Yes"
          : `Yes, ${shortDateTime(record.address.confirmedAt, tz)}`
        : "No",
    },
    {
      key: "HUB project",
      value:
        project === undefined || project.trim() === ""
          ? `deal ${record.hub.dealId}`
          : `${project} · deal ${record.hub.dealId}`,
    },
    { key: "Operator", value: record.operator.name },
    { key: "Device", value: deviceText },
    { key: "App", value: `Chapter Capture ${record.app.version} (build ${record.app.build})` },
    { key: "Visited", value: shortDateTime(record.visitedAt, tz) },
    { key: "Visit id", value: record.visitId, mono: true },
    { key: "Package id", value: model.input.packageId, mono: true },
    { key: "Verdict id", value: model.verdict.verdictId, mono: true },
  ];
}

function recordRowCells(
  canvas: Canvas,
  row: { key: string; value: string; mono?: boolean },
): [Cell, Cell] {
  return [
    { lines: wrapCell(canvas, row.key, KEY, KEY_WIDTH - 8) },
    { lines: wrapCell(canvas, row.value, row.mono === true ? MONO : VALUE, WIDTH - KEY_WIDTH) },
  ];
}

function captureCells(canvas: Canvas, model: Model, index: number): Cell[] {
  const record = model.input.captureRecord;
  const capture = record?.captures[index];
  if (capture === undefined) {
    return [];
  }
  const tz = model.timeZone;
  const notes: string[] = [];
  if (capture.coverageNotes.trim() !== "") {
    notes.push(`Coverage: ${capture.coverageNotes}`);
  }
  if (capture.omittedRooms.length > 0) {
    notes.push(
      `Omitted: ${capture.omittedRooms.map((room) => (room.reason ? `${room.name} (${room.reason})` : room.name)).join("; ")}`,
    );
  }
  if (capture.inaccessibleRooms.length > 0) {
    notes.push(
      `Inaccessible: ${capture.inaccessibleRooms.map((room) => (room.reason ? `${room.name} (${room.reason})` : room.name)).join("; ")}`,
    );
  }
  const captured = [
    { text: shortDateTime(capture.capturedAt, tz), style: VALUE },
    ...(capture.finishedAt === undefined
      ? []
      : [{ text: `to ${time(capture.finishedAt, tz)}`, style: VALUE }]),
  ];
  return [
    {
      lines: [
        ...wrapCell(canvas, capture.label, VALUE, CAPTURE_COLS[0] as number),
        ...wrapCell(canvas, capture.areaKey, IDS, CAPTURE_COLS[0] as number),
      ],
    },
    {
      lines: wrapCell(
        canvas,
        MODE_LABEL[capture.mode] ?? capture.mode,
        VALUE,
        CAPTURE_COLS[1] as number,
      ),
    },
    {
      lines: wrapCell(
        canvas,
        capture.captureId,
        { ...IDS, color: COLOR.ink },
        CAPTURE_COLS[2] as number,
      ),
    },
    { lines: captured },
    {
      lines: (notes.length === 0 ? [WORDS.none] : notes).flatMap((note) =>
        wrapCell(canvas, note, VALUE, CAPTURE_COLS[4] as number),
      ),
    },
  ];
}

function where(model: Model, file: ReportFile): { text: string; link?: string } {
  switch (file.location.kind) {
    case "hub":
      return { text: `In the HUB: ${file.location.folder}/${file.location.name}` };
    case "link":
      return file.location.reason === "too_large"
        ? {
            text: `Not uploaded (over ${formatBytes(model.input.maxUploadBytes)}). Station link, Entra sign-in required: ${file.location.url}`,
            link: file.location.url,
          }
        : {
            text: `Kept in the station. Station link, Entra sign-in required: ${file.location.url}`,
            link: file.location.url,
          };
  }
}

function fileCells(canvas: Canvas, model: Model, file: ReportFile): Cell[] {
  const place = where(model, file);
  return [
    {
      lines: [
        ...canvas
          .wrapPath(file.path, VALUE, FILE_COLS[0] as number)
          .map((text) => ({ text, style: VALUE })),
        ...wrapCell(
          canvas,
          `${file.role}, ${formatBytes(file.bytes)}`,
          MUTED_SMALL,
          FILE_COLS[0] as number,
        ),
      ],
    },
    {
      lines: [
        { text: file.sha256.slice(0, 32), style: { ...IDS, color: COLOR.ink } },
        { text: file.sha256.slice(32), style: { ...IDS, color: COLOR.ink } },
      ],
    },
    { lines: wrapCell(canvas, place.text, VALUE, FILE_COLS[2] as number, place.link) },
  ];
}

const REPORT_LINE: TextStyle = { ...PARAGRAPH, color: COLOR.ink };

function filesIntro(canvas: Canvas, model: Model): { paragraph: string[]; report: string[] } {
  const paragraph = `Files up to ${formatBytes(model.input.maxUploadBytes)} of the roles the HUB receives are in the HUB folders below. Every other file stays in the station's immutable storage and opens through its station link after Entra sign-in. There are no public links.`;
  return {
    paragraph: canvas.wrap(paragraph, PARAGRAPH, WIDTH),
    report: canvas.wrap(
      `This report: ${model.input.reportLocation.folder}/${model.input.reportLocation.name}`,
      REPORT_LINE,
      WIDTH,
    ),
  };
}

function blockHeight(canvas: Canvas, model: Model, block: RecordBlock): number {
  switch (block.kind) {
    case "kicker":
      return 9 + 3;
    case "recordRow": {
      const row = recordRows(model)[block.row];
      if (row === undefined) {
        return 0;
      }
      const [key, value] = recordRowCells(canvas, row);
      return 3 + Math.max(cellHeight(key), cellHeight(value)) + 3 + 0.75;
    }
    case "capturesHeader":
    case "filesHeader":
      return 10 + 4 + 0.75;
    case "captureRow":
      return 3 + Math.max(...captureCells(canvas, model, block.capture).map(cellHeight)) + 3 + 0.75;
    case "filesIntro": {
      const intro = filesIntro(canvas, model);
      return (intro.paragraph.length + intro.report.length) * PARAGRAPH.line + 6;
    }
    case "fileRow": {
      const file = model.input.files[block.file];
      return file === undefined
        ? 0
        : 3 + Math.max(...fileCells(canvas, model, file).map(cellHeight)) + 3 + 0.75;
    }
  }
}

/** Splits the package record into pages; table headers repeat on continuation pages. */
export function paginateRecord(canvas: Canvas, model: Model): PageSpec[] {
  const blocks: RecordBlock[] = [{ kind: "kicker", text: "Capture record" }];
  recordRows(model).forEach((_row, i) => blocks.push({ kind: "recordRow", row: i }));
  const captures = model.input.captureRecord?.captures ?? [];
  if (captures.length > 0) {
    blocks.push({ kind: "kicker", text: "Captures" }, { kind: "capturesHeader" });
    captures.forEach((_c, i) => blocks.push({ kind: "captureRow", capture: i }));
  }
  blocks.push({ kind: "kicker", text: "Files" }, { kind: "filesIntro" }, { kind: "filesHeader" });
  model.input.files.forEach((_f, i) => blocks.push({ kind: "fileRow", file: i }));

  const top = 102 + 19 + 8;
  const pages: RecordBlock[][] = [[]];
  let y = top;
  let lastHeader: RecordBlock | undefined;
  blocks.forEach((block, i) => {
    const sectionGap = block.kind === "kicker" && i > 0 ? 8 : 0;
    let height = sectionGap + blockHeight(canvas, model, block);
    // Keep a kicker with what follows it, and a header with its first row.
    const next = blocks[i + 1];
    const keep =
      block.kind === "kicker" ||
      block.kind === "capturesHeader" ||
      block.kind === "filesHeader" ||
      block.kind === "filesIntro"
        ? blockHeight(canvas, model, next ?? block)
        : 0;
    const page = pages[pages.length - 1] as RecordBlock[];
    if (y + height + keep > BOTTOM && page.length > 0) {
      const fresh: RecordBlock[] = [];
      y = top;
      if ((block.kind === "captureRow" || block.kind === "fileRow") && lastHeader !== undefined) {
        fresh.push(lastHeader);
        y += blockHeight(canvas, model, lastHeader);
      }
      pages.push(fresh);
      height -= sectionGap;
    }
    (pages[pages.length - 1] as RecordBlock[]).push(block);
    y += height;
    if (block.kind === "capturesHeader" || block.kind === "filesHeader") {
      lastHeader = block;
    } else if (block.kind === "kicker") {
      lastHeader = undefined;
    }
  });
  return pages.map((page, i) => ({ kind: "record", first: i === 0, blocks: page }));
}

export function drawRecordPage(
  ctx: PageContext,
  page: Extract<PageSpec, { kind: "record" }>,
): void {
  const { canvas, model } = ctx;
  drawFrame(ctx, { kicker: [WORDS.packageRecord], statement: "short" });
  canvas.line(
    page.first ? WORDS.packageRecord : `${WORDS.packageRecord} (continued)`,
    TYPE.section,
    X,
    102,
  );
  const rightWidth = canvas.width(WORDS.recordRight, RIGHT);
  canvas.line(WORDS.recordRight, RIGHT, X + WIDTH - rightWidth, 102 + 19 - 11);
  let y = 102 + 19 + 8;
  page.blocks.forEach((block, i) => {
    if (block.kind === "kicker" && i > 0) {
      y += 8;
    }
    y = drawBlock(canvas, model, block, y);
  });
}

function drawCells(
  canvas: Canvas,
  cells: readonly Cell[],
  columnX: readonly number[],
  columnWidth: readonly number[],
  top: number,
): number {
  let height = 0;
  cells.forEach((cell, c) => {
    let y = top + 3;
    for (const line of cell.lines) {
      canvas.line(line.text, line.style, columnX[c] as number, y, {
        ...(line.link === undefined ? {} : { link: line.link }),
      });
      y += line.style.line;
    }
    height = Math.max(height, cellHeight(cell));
    void columnWidth;
  });
  const bottom = top + 3 + height + 3;
  canvas.rule(X, bottom, WIDTH, COLOR.line);
  return bottom + 0.75;
}

function drawBlock(canvas: Canvas, model: Model, block: RecordBlock, top: number): number {
  switch (block.kind) {
    case "kicker":
      canvas.line(block.text, TYPE.kickerInner, X, top);
      return top + 9 + 3;
    case "recordRow": {
      const row = recordRows(model)[block.row];
      if (row === undefined) {
        return top;
      }
      return drawCells(
        canvas,
        recordRowCells(canvas, row),
        [X, X + KEY_WIDTH],
        [KEY_WIDTH - 8, WIDTH - KEY_WIDTH],
        top,
      );
    }
    case "capturesHeader":
      ["Floor or area", "Mode", "Capture id", "Captured", "Notes"].forEach((text, i) =>
        canvas.line(text, TYPE.header, CAPTURE_X[i] as number, top),
      );
      canvas.rule(X, top + 10 + 4, WIDTH, COLOR.ink);
      return top + 10 + 4 + 0.75;
    case "captureRow":
      return drawCells(
        canvas,
        captureCells(canvas, model, block.capture),
        CAPTURE_X,
        CAPTURE_COLS,
        top,
      );
    case "filesIntro": {
      const intro = filesIntro(canvas, model);
      let y = top + canvas.lines(intro.paragraph, PARAGRAPH, X, top, WIDTH);
      y += canvas.lines(intro.report, REPORT_LINE, X, y, WIDTH);
      return y + 6;
    }
    case "filesHeader":
      ["File", "SHA-256", "Where"].forEach((text, i) =>
        canvas.line(text, TYPE.header, FILE_X[i] as number, top),
      );
      canvas.rule(X, top + 10 + 4, WIDTH, COLOR.ink);
      return top + 10 + 4 + 0.75;
    case "fileRow": {
      const file = model.input.files[block.file];
      if (file === undefined) {
        return top;
      }
      return drawCells(canvas, fileCells(canvas, model, file), FILE_X, FILE_COLS, top);
    }
  }
}
