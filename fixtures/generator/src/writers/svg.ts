// SVG plan preview: walls, openings, room outlines and labels. Plan y is the model's -z.

import type { CaptureModel } from "@chapter/capture-contract";
import { fixed } from "../util.js";

function escapeXml(text: string): string {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

export function planBounds(model: CaptureModel): {
  minX: number;
  maxX: number;
  minZ: number;
  maxZ: number;
} {
  const points = [
    ...model.rooms.flatMap((room) => room.polygon),
    ...model.walls.flatMap((w) => [w.start, w.end]),
  ];
  return {
    minX: Math.min(...points.map((p) => p[0])),
    maxX: Math.max(...points.map((p) => p[0])),
    minZ: Math.min(...points.map((p) => p[2])),
    maxZ: Math.max(...points.map((p) => p[2])),
  };
}

export function writeSvg(model: CaptureModel): string {
  const bounds = planBounds(model);
  const margin = 0.5;
  const width = bounds.maxX - bounds.minX + margin * 2;
  const height = bounds.maxZ - bounds.minZ + margin * 2;
  const sx = (x: number) => fixed(x - bounds.minX + margin, 3);
  const sy = (z: number) => fixed(bounds.maxZ - z + margin, 3);
  const wallsById = new Map(model.walls.map((wall) => [wall.id, wall]));
  const out: string[] = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${fixed(width, 3)} ${fixed(height, 3)}" width="${fixed(width * 100, 0)}" height="${fixed(height * 100, 0)}">`,
    `  <title>${escapeXml(model.label)} plan (metres)</title>`,
  ];
  for (const room of model.rooms) {
    const points = room.polygon.map((p) => `${sx(p[0])},${sy(p[2])}`).join(" ");
    out.push(`  <polygon points="${points}" fill="#f4f1ea" stroke="none"/>`);
  }
  for (const wall of model.walls) {
    out.push(
      `  <line x1="${sx(wall.start[0])}" y1="${sy(wall.start[2])}" x2="${sx(wall.end[0])}" y2="${sy(wall.end[2])}" stroke="#222222" stroke-width="0.08"/>`,
    );
  }
  const spans: Array<[string, string, (typeof model.doors)[number]]> = [
    ...model.doors.map((o) => ["door", "#a0522d", o] as [string, string, typeof o]),
    ...model.windows.map((o) => ["window", "#1e90ff", o] as [string, string, typeof o]),
    ...model.openings.map((o) => ["opening", "#888888", o] as [string, string, typeof o]),
  ];
  for (const [kind, colour, opening] of spans) {
    const wall = wallsById.get(opening.wallId);
    if (wall === undefined) {
      continue;
    }
    const dx = wall.end[0] - wall.start[0];
    const dz = wall.end[2] - wall.start[2];
    const length = Math.hypot(dx, dz);
    const at = (distance: number): [number, number] => [
      wall.start[0] + (dx * distance) / length,
      wall.start[2] + (dz * distance) / length,
    ];
    const from = at(opening.offsetM - opening.widthM / 2);
    const to = at(opening.offsetM + opening.widthM / 2);
    out.push(
      `  <line class="${kind}" x1="${sx(from[0])}" y1="${sy(from[1])}" x2="${sx(to[0])}" y2="${sy(to[1])}" stroke="${colour}" stroke-width="0.12"/>`,
    );
  }
  for (const room of model.rooms) {
    const cx = room.polygon.reduce((sum, p) => sum + p[0], 0) / room.polygon.length;
    const cz = room.polygon.reduce((sum, p) => sum + p[2], 0) / room.polygon.length;
    out.push(
      `  <text x="${sx(cx)}" y="${sy(cz)}" font-family="Helvetica, Arial, sans-serif" font-size="0.3" text-anchor="middle">${escapeXml(room.label)}</text>`,
    );
  }
  out.push("</svg>");
  return `${out.join("\n")}\n`;
}
