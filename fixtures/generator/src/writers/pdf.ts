// Minimal PDF 1.7 writer: one Letter page, Helvetica text and vector lines, uncompressed.

import type { CaptureModel } from "@chapter/capture-contract";
import { polygonArea } from "../geometry.js";
import { fixed, latin1, concatBytes, type P2 } from "../util.js";
import { planBounds } from "./svg.js";

const PAGE_W = 612;
const PAGE_H = 792;
/** 1:50 scale: 1 m is 20 mm on paper. */
const PT_PER_M_AT_1_50 = (20 / 25.4) * 72;

export interface PageContent {
  title: string;
  /** Content stream operators. */
  stream: string;
}

function escapePdf(text: string): string {
  return text.replaceAll("\\", "\\\\").replaceAll("(", "\\(").replaceAll(")", "\\)");
}

function textOp(x: number, y: number, size: number, text: string): string {
  return `BT /F1 ${size} Tf ${fixed(x, 2)} ${fixed(y, 2)} Td (${escapePdf(text)}) Tj ET\n`;
}

function lineOp(a: P2, b: P2, width = 1): string {
  return `${width} w ${fixed(a[0], 3)} ${fixed(a[1], 3)} m ${fixed(b[0], 3)} ${fixed(b[1], 3)} l S\n`;
}

/** Assembles a PDF 1.7 file with a correct cross-reference table. */
export function assemblePdf(page: PageContent): Uint8Array {
  const objects: string[] = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PAGE_W} ${PAGE_H}] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    `<< /Length ${page.stream.length} >>\nstream\n${page.stream}endstream`,
    `<< /Title (${escapePdf(page.title)}) /Producer (chapter-fixtures 1.0.0) >>`,
  ];
  const parts: Uint8Array[] = [latin1("%PDF-1.7\n%âãÏÓ\n")];
  const offsets: number[] = [];
  let length = parts[0]?.length ?? 0;
  objects.forEach((body, index) => {
    offsets.push(length);
    const bytes = latin1(`${index + 1} 0 obj\n${body}\nendobj\n`);
    parts.push(bytes);
    length += bytes.length;
  });
  const xrefStart = length;
  const xref = [
    "xref",
    `0 ${objects.length + 1}`,
    "0000000000 65535 f ",
    ...offsets.map((offset) => `${String(offset).padStart(10, "0")} 00000 n `),
    "trailer",
    `<< /Size ${objects.length + 1} /Root 1 0 R /Info 6 0 R >>`,
    "startxref",
    String(xrefStart),
    "%%EOF",
    "",
  ].join("\n");
  parts.push(latin1(xref));
  return concatBytes(parts);
}

export interface PdfMeta {
  address: string;
  captureId: string;
  projectName: string;
  operator: string;
  date: string;
}

/** Scaled plan with walls, openings, room labels and a title block. */
export function writePlanPdf(model: CaptureModel, meta: PdfMeta): Uint8Array {
  const bounds = planBounds(model);
  const originX = 72;
  const originY = 250;
  const px = (x: number): number => originX + (x - bounds.minX) * PT_PER_M_AT_1_50;
  const py = (z: number): number => originY + (bounds.maxZ - z) * PT_PER_M_AT_1_50;
  const point = (p: readonly number[]): P2 => [px(p[0] as number), py(p[2] as number)];
  let stream = "";
  stream += textOp(72, 740, 16, `Floor plan - ${model.label}`);
  stream += textOp(72, 720, 10, `Scale 1:50 (Letter). 20 mm on paper is 1.000 m.`);
  const wallsById = new Map(model.walls.map((wall) => [wall.id, wall]));
  for (const wall of model.walls) {
    stream += lineOp(point(wall.start), point(wall.end), 1.5);
  }
  const marks: Array<[number, typeof model.doors]> = [
    [3, model.doors],
    [3, model.windows],
    [0.5, model.openings],
  ];
  for (const [width, list] of marks) {
    for (const opening of list) {
      const wall = wallsById.get(opening.wallId);
      if (wall === undefined) {
        continue;
      }
      const dx = wall.end[0] - wall.start[0];
      const dz = wall.end[2] - wall.start[2];
      const length = Math.hypot(dx, dz);
      const at = (distance: number): P2 =>
        point([
          wall.start[0] + (dx * distance) / length,
          0,
          wall.start[2] + (dz * distance) / length,
        ]);
      stream += lineOp(
        at(opening.offsetM - opening.widthM / 2),
        at(opening.offsetM + opening.widthM / 2),
        width,
      );
    }
  }
  for (const wall of model.walls) {
    const length = Math.hypot(wall.end[0] - wall.start[0], wall.end[2] - wall.start[2]);
    const mid = point([(wall.start[0] + wall.end[0]) / 2, 0, (wall.start[2] + wall.end[2]) / 2]);
    stream += textOp(mid[0] + 3, mid[1] + 3, 7, `${fixed(length * 1000, 0)} mm`);
  }
  for (const room of model.rooms) {
    const cx = room.polygon.reduce((s, p) => s + p[0], 0) / room.polygon.length;
    const cz = room.polygon.reduce((s, p) => s + p[2], 0) / room.polygon.length;
    stream += textOp(px(cx) - 30, py(cz), 10, room.label);
  }
  // Scale bar: 2 m.
  const barY = 215;
  stream += lineOp([72, barY], [72 + 2 * PT_PER_M_AT_1_50, barY], 2);
  stream += textOp(72, barY - 12, 8, "0        2 m");
  stream += textOp(
    72,
    190,
    8,
    "North: plan top is model -Z (local capture frame, not true north).",
  );
  // Title block.
  stream += textOp(72, 150, 9, `Address: ${meta.address}`);
  stream += textOp(72, 138, 9, `Project: ${meta.projectName}`);
  stream += textOp(72, 126, 9, `Floor: ${model.label} (${model.areaKey})`);
  stream += textOp(72, 114, 9, `Capture ID: ${meta.captureId}`);
  stream += textOp(72, 102, 9, `Date: ${meta.date}`);
  stream += textOp(72, 90, 9, `Operator: ${meta.operator}`);
  return assemblePdf({ title: `Plan ${model.label}`, stream });
}

/** Per-room table and capture metadata. */
export function writeReportPdf(model: CaptureModel, meta: PdfMeta): Uint8Array {
  let stream = "";
  stream += textOp(72, 740, 16, `Spatial Report - ${model.label}`);
  stream += textOp(72, 722, 9, `Address: ${meta.address}`);
  stream += textOp(72, 710, 9, `Capture ID: ${meta.captureId}`);
  stream += textOp(
    72,
    698,
    9,
    `Project: ${meta.projectName}   Operator: ${meta.operator}   Date: ${meta.date}`,
  );
  stream += textOp(
    72,
    680,
    10,
    "Room | Width mm | Length mm | Area m2 | Height mm | Doors | Windows | Objects",
  );
  let y = 664;
  for (const room of model.rooms) {
    const plan: P2[] = room.polygon.map(([x, , z]) => [x, z]);
    const xs = plan.map((p) => p[0]);
    const zs = plan.map((p) => p[1]);
    const wallIds = new Set(
      model.walls.filter((wall) => wall.roomIds?.includes(room.id) === true).map((wall) => wall.id),
    );
    const count = (list: Array<{ wallId: string }>) =>
      list.filter((opening) => wallIds.has(opening.wallId)).length;
    const objects = model.objects.filter((object) => object.roomId === room.id);
    stream += textOp(
      72,
      y,
      10,
      `${room.label} | ${fixed((Math.max(...xs) - Math.min(...xs)) * 1000, 0)} | ${fixed((Math.max(...zs) - Math.min(...zs)) * 1000, 0)} | ${fixed(polygonArea(plan), 2)} | ${fixed(room.heightM * 1000, 0)} | ${count(model.doors)} | ${count(model.windows)} | ${objects.map((o) => o.category).join(", ") || "none"}`,
    );
    y -= 14;
  }
  stream += textOp(
    72,
    y - 20,
    9,
    "This report is not a photo survey. Reported areas are not verified construction quantities.",
  );
  return assemblePdf({ title: `Spatial Report ${model.label}`, stream });
}
