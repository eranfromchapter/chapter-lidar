// Room measurement CSV: UTF-8, header row, one row per room, metric and feet-inches columns.

import type { CaptureModel } from "@chapter/capture-contract";
import { polygonArea, polygonPerimeter } from "../geometry.js";
import { fixed, type P2 } from "../util.js";

export const CSV_HEADER = [
  "floor",
  "room_id",
  "room_label",
  "width_mm",
  "length_mm",
  "height_mm",
  "floor_area_m2",
  "perimeter_mm",
  "door_count",
  "window_count",
  "width_ftin",
  "length_ftin",
  "height_ftin",
];

export const CSV_NOTE = "Reported floor area is not a verified construction quantity.";

/** Feet and inches, inches to two decimals, for example 13' 1.48". */
export function feetInches(mm: number): string {
  const totalInches = Math.round((mm / 25.4) * 100) / 100;
  const feet = Math.floor(totalInches / 12);
  const inches = Math.round((totalInches - feet * 12) * 100) / 100;
  return `${feet}' ${fixed(inches, 2)}"`;
}

function cell(value: string): string {
  return /[",\n]/.test(value) ? `"${value.replaceAll('"', '""')}"` : value;
}

export function writeCsv(model: CaptureModel): string {
  const rows: string[] = [CSV_HEADER.join(",")];
  for (const room of model.rooms) {
    const plan: P2[] = room.polygon.map(([x, , z]) => [x, z]);
    const xs = plan.map((p) => p[0]);
    const zs = plan.map((p) => p[1]);
    const widthMm = (Math.max(...xs) - Math.min(...xs)) * 1000;
    const lengthMm = (Math.max(...zs) - Math.min(...zs)) * 1000;
    const heightMm = room.heightM * 1000;
    const wallIds = new Set(
      model.walls.filter((wall) => wall.roomIds?.includes(room.id) === true).map((wall) => wall.id),
    );
    const count = (list: Array<{ wallId: string }>) =>
      list.filter((opening) => wallIds.has(opening.wallId)).length;
    rows.push(
      [
        cell(model.label),
        cell(room.id),
        cell(room.label),
        fixed(widthMm, 1),
        fixed(lengthMm, 1),
        fixed(heightMm, 1),
        fixed(polygonArea(plan), 3),
        fixed(polygonPerimeter(plan) * 1000, 1),
        String(count(model.doors)),
        String(count(model.windows)),
        cell(feetInches(widthMm)),
        cell(feetInches(lengthMm)),
        cell(feetInches(heightMm)),
      ].join(","),
    );
  }
  rows.push(`# ${CSV_NOTE}`);
  return `${rows.join("\n")}\n`;
}
