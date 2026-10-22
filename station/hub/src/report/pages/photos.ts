// Site photo pages (spec 5.6; artboard 1u): up to 10 reduced photos per page in a 5 x 2 grid,
// with the operator's labels; photos whose room label matches no room get "Other site photos"
// pages per floor.

import { dateSpan, plural, time } from "../format.js";
import type { ReportPhoto } from "../input.js";
import type { Model, ModelFloor, ModelRoom } from "../model.js";
import { COLOR, FONT, TYPE, type TextStyle } from "../tokens.js";
import { WORDS } from "../words.js";
import { drawFrame, type PageContext } from "./context.js";
import type { PageSpec } from "./index-of-pages.js";
import { roomKicker } from "./room.js";

export const PHOTOS_PER_PAGE = 10;
const COLUMN_X = [36, 182.5, 329, 475.5, 622];
const IMAGE_W = 128;
const IMAGE_H = 160;
const ROW_PITCH = 184;

const SUBJECT: Record<string, string> = {
  opening: "Opening",
  cabinetry: "Cabinetry",
  ceiling: "Ceiling",
  fixture: "Fixture",
  equipment: "Equipment",
  defect: "Defect",
  general: "General",
};

const RIGHT: TextStyle = { ...TYPE.table, color: COLOR.muted };
const TITLE_MUTED: TextStyle = { ...TYPE.roomTitle, color: COLOR.muted };

/** Pages of photos (10 each) for one room or the floor's other photos. */
export function photoPages(
  floor: ModelFloor,
  photos: readonly ReportPhoto[],
  room?: ModelRoom,
): PageSpec[] {
  const pages: PageSpec[] = [];
  for (let i = 0; i < photos.length; i += PHOTOS_PER_PAGE) {
    pages.push({
      kind: "photos",
      floor: floor.index,
      ...(room === undefined ? {} : { room: room.number }),
      photos: photos.slice(i, i + PHOTOS_PER_PAGE),
      firstNumber: i + 1,
      continued: i > 0,
    });
  }
  return pages;
}

function rightText(model: Model, photos: readonly ReportPhoto[]): string {
  const times = photos.map((photo) => photo.takenAt).sort();
  const first = times[0] ?? model.verdict.evaluatedAt;
  const last = times[times.length - 1] ?? first;
  const operator = model.input.captureRecord?.operator.name;
  const taken = `taken ${dateSpan(first, last, model.timeZone, "long", " to ")}`;
  return `${plural(photos.length, "photo")} · ${taken}${operator === undefined ? "" : ` by ${operator}`} · reduced here, originals in the package`;
}

export function drawPhotosPage(
  ctx: PageContext,
  page: Extract<PageSpec, { kind: "photos" }>,
): void {
  const { canvas, model } = ctx;
  const floor = model.floors[page.floor] as ModelFloor;
  const room = page.room === undefined ? undefined : model.rooms[page.room - 1];
  const all = room === undefined ? floor.otherPhotos : room.photos;
  const kicker =
    room === undefined
      ? [floor.label, "Other site photos", ...(page.continued ? ["continued"] : [])]
      : roomKicker(model, room, page.continued, "Site photos");
  drawFrame(ctx, { kicker, statement: "short", captureId: floor.captureId });

  // Heading row.
  const right = rightText(model, all);
  const rightLines = canvas.wrap(right, RIGHT, 720 - 300 - 12, 2);
  const rightWidth = Math.max(...rightLines.map((line) => canvas.measure(line, RIGHT)));
  const headingHeight = Math.max(26, rightLines.length * 11);
  const titleWidth = 720 - rightWidth - 12;
  const name = room === undefined ? floor.label : room.name;
  const suffix = room === undefined ? " · other site photos" : " · site photos";
  const tail = `${suffix}${page.continued ? " (continued)" : ""}`;
  const tailWidth = canvas.width(tail, TITLE_MUTED);
  const nameText = canvas.truncate(
    canvas.prepare(name, TYPE.roomTitle),
    TYPE.roomTitle,
    Math.max(10, titleWidth - tailWidth),
  );
  const titleTop = 102 + headingHeight - 26;
  canvas.runs(
    [
      { text: nameText, style: TYPE.roomTitle },
      { text: tail, style: TITLE_MUTED },
    ],
    36,
    titleTop,
  );
  rightLines.forEach((line, i) => {
    const w = canvas.measure(line, RIGHT);
    canvas.lines([line], RIGHT, 756 - w, 102 + headingHeight - rightLines.length * 11 + i * 11, w);
  });

  // Grid.
  const gridTop = 102 + headingHeight + 10;
  const doc = canvas.doc;
  page.photos.forEach((photo, i) => {
    const column = i % 5;
    const row = Math.floor(i / 5);
    const x = (COLUMN_X[column] as number) + 3;
    const y = gridTop + row * ROW_PITCH;
    if (photo.image === undefined) {
      doc.save().rect(x, y, IMAGE_W, IMAGE_H).fill(COLOR.nude).restore();
      const style: TextStyle = { ...TYPE.table, color: COLOR.muted };
      const w = canvas.width(WORDS.photoUnreadable, style);
      canvas.line(
        WORDS.photoUnreadable,
        style,
        x + (IMAGE_W - w) / 2,
        y + IMAGE_H / 2 - style.line / 2,
      );
    } else {
      doc.image(Buffer.from(photo.image), x, y, { width: IMAGE_W, height: IMAGE_H });
    }
    const n = page.firstNumber + i;
    const subject = SUBJECT[photo.subject] ?? photo.subject;
    const head = room === undefined ? `${n} · ${photo.room} · ${subject}` : `${n} · ${subject}`;
    canvas.runs(
      [
        { text: head, style: TYPE.dense },
        { text: ` · looking ${photo.direction}`, style: { ...TYPE.dense, color: COLOR.muted } },
      ],
      x,
      y + IMAGE_H + 4,
    );
    const file = photo.path.slice(photo.path.lastIndexOf("/") + 1);
    canvas.line(
      `${time(photo.takenAt, model.timeZone)} · ${file}`,
      { font: FONT.mono, size: 7.5, line: 9, color: COLOR.muted },
      x,
      y + IMAGE_H + 4 + 10,
      { maxWidth: 134 },
    );
  });
  const lines = canvas.wrap(WORDS.photosFootnote, TYPE.footnote, 720);
  canvas.lines(lines, TYPE.footnote, 36, 528 - lines.length * TYPE.footnote.line, 720);
}
