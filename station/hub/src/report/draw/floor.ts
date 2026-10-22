// A whole floor on a page (spec 7.4): squared by the floor's dominant angle, fitted uniformly
// into a box (top-left aligned), with fills, objects, walls, openings, room labels and, on the
// floor plan page, the outer dimension strings. Also the key plan of a room page.

import type { Canvas } from "../layout/canvas.js";
import type { ModelFloor, ModelRoom } from "../model.js";
import { distance, type Point } from "../metrics/plan-geometry.js";
import { feetInches } from "../metrics/units.js";
import { COLOR, FONT, type TextStyle } from "../tokens.js";
import {
  PlanView,
  drawFills,
  drawKeyFill,
  drawObjects,
  drawOpenings,
  drawWalls,
  frameBounds,
  openingBand,
  planBands,
} from "./plan-view.js";

export interface Rect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export const intersects = (a: Rect, b: Rect): boolean =>
  a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

const NAME: TextStyle = { font: FONT.semibold, size: 7.5, line: 9, color: COLOR.ink };
const AREA: TextStyle = { font: FONT.sans, size: 7.5, line: 9, color: COLOR.muted };
const DIM: TextStyle = { font: FONT.mono, size: 7.5, line: 9, color: COLOR.ink };
/** Inter's ascender and descender, em. */
const ASC = 0.96875;
const DESC = 0.2415;

/** Frame-coordinate extent (metres) of what a floor draws, for a wall minimum in metres. */
function inkExtent(floor: ModelFloor, minWallM: number, rotation: number) {
  const geometry = floor.metrics?.geometry;
  if (geometry === undefined) {
    return undefined;
  }
  const points: Point[] = [
    ...planBands(geometry, minWallM).flatMap((band) => band.corners),
    ...geometry.rooms.flatMap((room) => room.polygon),
    ...geometry.objects.flatMap((object) => object.corners),
  ];
  return frameBounds(points, rotation);
}

/** Outer wall bounding box in the frame (metres) at drawn thickness. */
function wallExtent(floor: ModelFloor, minWallM: number, rotation: number) {
  const geometry = floor.metrics?.geometry;
  if (geometry === undefined) {
    return undefined;
  }
  const points = planBands(geometry, minWallM).flatMap((band) => band.corners);
  return frameBounds(
    points.length > 0 ? points : geometry.rooms.flatMap((r) => r.polygon),
    rotation,
  );
}

export interface FitOptions {
  /** Box the drawing's ink (or with `wallsOnly` the outer wall box) is fitted into. */
  readonly box: Rect;
  /** Minimum wall band on the page, points. */
  readonly minWall: number;
  /** Fit the outer wall box instead of all ink (plan page). */
  readonly wallsOnly?: boolean;
  /** Fixed scale (points per metre) instead of fitting. */
  readonly scale?: number;
}

/** The view of a floor fitted top-left into a box (undefined without a readable model). */
export function fitFloor(floor: ModelFloor, options: FitOptions): PlanView | undefined {
  const rotation = floor.rotationDegrees;
  const extentOf = options.wallsOnly === true ? wallExtent : inkExtent;
  let extent = extentOf(floor, 0, rotation);
  if (extent === undefined) {
    return undefined;
  }
  let s = options.scale ?? 0;
  if (options.scale === undefined) {
    // The wall minimum depends on the scale: settle it in a few rounds.
    for (let round = 0; round < 4; round += 1) {
      const width = Math.max(extent.maxX - extent.minX, 1e-6);
      const height = Math.max(extent.maxY - extent.minY, 1e-6);
      s = Math.min(options.box.width / width, options.box.height / height);
      extent = extentOf(floor, options.minWall / s, rotation) ?? extent;
    }
    const width = Math.max(extent.maxX - extent.minX, 1e-6);
    const height = Math.max(extent.maxY - extent.minY, 1e-6);
    s = Math.min(options.box.width / width, options.box.height / height);
  } else {
    extent = extentOf(floor, options.minWall / s, rotation) ?? extent;
  }
  return new PlanView(rotation, s, options.box.x, options.box.y, extent.minX, extent.maxY);
}

function rectOf(
  view: PlanView,
  extent: { minX: number; minY: number; maxX: number; maxY: number },
): Rect {
  return {
    x: view.originX + view.scale * (extent.minX - view.minX),
    y: view.originY + view.scale * (view.maxY - extent.maxY),
    width: view.scale * (extent.maxX - extent.minX),
    height: view.scale * (extent.maxY - extent.minY),
  };
}

/** Page rectangle of a floor's ink under a view. */
export function inkRect(floor: ModelFloor, view: PlanView, minWall: number): Rect | undefined {
  const extent = inkExtent(floor, view.m(minWall), view.rotationDegrees);
  return extent === undefined ? undefined : rectOf(view, extent);
}

/** Page rectangle of the outer wall faces. */
export function wallRect(floor: ModelFloor, view: PlanView, minWall: number): Rect | undefined {
  const extent = wallExtent(floor, view.m(minWall), view.rotationDegrees);
  return extent === undefined ? undefined : rectOf(view, extent);
}

/** Page polygons of a floor's ink: room fills, wall bands and objects. */
export function inkPolygons(floor: ModelFloor, view: PlanView, minWall: number): Point[][] {
  const geometry = floor.metrics?.geometry;
  if (geometry === undefined) {
    return [];
  }
  return [
    ...geometry.rooms.map((room) => room.polygon),
    ...planBands(geometry, view.m(minWall)).map((band) => band.corners),
    ...geometry.objects.map((object) => object.corners),
  ].map((polygon) => polygon.map((p) => view.page(p)));
}

function segmentsCross(a: Point, b: Point, c: Point, d: Point): boolean {
  const orient = (p: Point, q: Point, r: Point) =>
    (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
  const o1 = orient(a, b, c);
  const o2 = orient(a, b, d);
  const o3 = orient(c, d, a);
  const o4 = orient(c, d, b);
  return o1 * o2 < 0 && o3 * o4 < 0;
}

function pointInPolygon(polygon: readonly Point[], p: Point): boolean {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i, i += 1) {
    const a = polygon[i] as Point;
    const b = polygon[j] as Point;
    if (a.y > p.y !== b.y > p.y && p.x < ((b.x - a.x) * (p.y - a.y)) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

/** Whether a polygon and a rectangle overlap (page coordinates). */
export function polygonHitsRect(polygon: readonly Point[], rect: Rect): boolean {
  const inRect = (p: Point) =>
    p.x > rect.x && p.x < rect.x + rect.width && p.y > rect.y && p.y < rect.y + rect.height;
  if (polygon.some(inRect)) {
    return true;
  }
  const corners = [
    { x: rect.x, y: rect.y },
    { x: rect.x + rect.width, y: rect.y },
    { x: rect.x + rect.width, y: rect.y + rect.height },
    { x: rect.x, y: rect.y + rect.height },
  ];
  if (corners.some((corner) => pointInPolygon(polygon, corner))) {
    return true;
  }
  for (let i = 0; i < polygon.length; i += 1) {
    const a = polygon[i] as Point;
    const b = polygon[(i + 1) % polygon.length] as Point;
    for (let k = 0; k < 4; k += 1) {
      if (segmentsCross(a, b, corners[k] as Point, corners[(k + 1) % 4] as Point)) {
        return true;
      }
    }
  }
  return false;
}

export interface FloorDrawOptions {
  readonly minWall: number;
  readonly labels: boolean;
  /** Key plan: walls and this room in ink only. */
  readonly keyRoomId?: string;
}

/** Draws fills, objects, walls, openings and (optionally) room labels. */
export function drawFloor(
  canvas: Canvas,
  floor: ModelFloor,
  view: PlanView,
  options: FloorDrawOptions,
): void {
  const geometry = floor.metrics?.geometry;
  if (geometry === undefined) {
    return;
  }
  const minWallM = view.m(options.minWall);
  const bands = planBands(geometry, minWallM);
  if (options.keyRoomId !== undefined) {
    const room = geometry.rooms.find((r) => r.id === options.keyRoomId);
    if (room !== undefined) {
      drawKeyFill(canvas, view, room.polygon);
    }
    drawWalls(canvas, view, bands);
    return;
  }
  const byId = new Map(floor.rooms.map((room) => [room.metrics.roomId, room]));
  drawFills(
    canvas,
    view,
    geometry.rooms.map((room) => ({
      polygon: room.polygon,
      fill: byId.get(room.id)?.fill ?? "other",
    })),
  );
  const walls = geometry.walls.filter((wall) => distance(wall.start, wall.end) > 0);
  drawObjects(canvas, view, geometry.objects, walls);
  drawWalls(canvas, view, bands);
  drawOpenings(
    canvas,
    view,
    geometry.openings.map((opening) => ({ opening, ...openingBand(geometry, opening, minWallM) })),
  );
  if (options.labels) {
    drawRoomLabels(canvas, floor, view);
  }
}

// MARK: Room labels

function insideConvex(polygon: readonly Point[], p: Point): boolean {
  let sign = 0;
  for (let i = 0; i < polygon.length; i += 1) {
    const a = polygon[i] as Point;
    const b = polygon[(i + 1) % polygon.length] as Point;
    const cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
    if (Math.abs(cross) < 1e-6) {
      continue;
    }
    const s = cross > 0 ? 1 : -1;
    if (sign === 0) {
      sign = s;
    } else if (s !== sign) {
      return false;
    }
  }
  return true;
}

function fits(polygon: readonly Point[], rect: Rect): boolean {
  return [
    { x: rect.x, y: rect.y },
    { x: rect.x + rect.width, y: rect.y },
    { x: rect.x + rect.width, y: rect.y + rect.height },
    { x: rect.x, y: rect.y + rect.height },
  ].every((corner) => insideConvex(polygon, corner));
}

/** Room names and areas centred on the label point, where they fit the inscribed rectangle. */
export function drawRoomLabels(canvas: Canvas, floor: ModelFloor, view: PlanView): void {
  const geometry = floor.metrics?.geometry;
  if (geometry === undefined) {
    return;
  }
  for (const room of floor.rooms) {
    const planRoom = geometry.rooms.find((r) => r.id === room.metrics.roomId);
    if (planRoom === undefined) {
      continue;
    }
    const placed = placeLabel(canvas, room, view, planRoom.labelPoint);
    if (placed === undefined) {
      continue;
    }
    canvas.line(
      room.name,
      NAME,
      placed.x - placed.nameWidth / 2,
      placed.baseline - canvas.baselineOffset(NAME),
    );
    if (placed.area !== undefined) {
      const areaBaseline = placed.baseline + 11.25;
      canvas.line(
        placed.area,
        AREA,
        placed.x - placed.areaWidth / 2,
        areaBaseline - canvas.baselineOffset(AREA),
      );
    }
  }
}

interface PlacedLabel {
  readonly x: number;
  readonly baseline: number;
  readonly nameWidth: number;
  readonly area?: string;
  readonly areaWidth: number;
}

function placeLabel(
  canvas: Canvas,
  room: ModelRoom,
  view: PlanView,
  labelPoint: Point,
): PlacedLabel | undefined {
  const inscribed = room.metrics.inscribed.corners.map((corner) => view.page(corner));
  const centre = view.page(room.metrics.inscribed.center);
  const nameWidth = canvas.width(room.name, NAME);
  const area = `${room.words.area} sq ft`;
  const areaWidth = canvas.width(area, AREA);
  const asc = ASC * 7.5;
  const desc = DESC * 7.5;
  for (const point of [view.page(labelPoint), centre]) {
    // Two lines: name baseline, area baseline 11.25 below; the ink block centred on the point.
    const twoHeight = asc + 11.25 + desc;
    const twoWidth = Math.max(nameWidth, areaWidth);
    const twoBaseline = point.y - twoHeight / 2 + asc;
    const two = {
      x: point.x - twoWidth / 2 - 2,
      y: twoBaseline - asc - 2,
      width: twoWidth + 4,
      height: twoHeight + 4,
    };
    if (fits(inscribed, two)) {
      return { x: point.x, baseline: twoBaseline, nameWidth, area, areaWidth };
    }
  }
  for (const point of [view.page(labelPoint), centre]) {
    const oneBaseline = point.y + (asc - desc) / 2;
    const one = {
      x: point.x - nameWidth / 2 - 2,
      y: oneBaseline - asc - 2,
      width: nameWidth + 4,
      height: asc + desc + 4,
    };
    if (fits(inscribed, one)) {
      return { x: point.x, baseline: oneBaseline, nameWidth, areaWidth };
    }
  }
  return undefined;
}

// MARK: Outer dimension strings

export interface DimensionString {
  readonly side: "top" | "bottom" | "left" | "right";
  /** Line position: y for top/bottom, x for left/right. */
  readonly at: number;
  readonly from: number;
  readonly to: number;
  readonly text: string;
  readonly muted?: boolean;
}

/**
 * The outer dimension strings of a floor (spec 7.4.5): per side of the outer wall box, the rooms
 * whose own box edge lies within (thickest band + 0.30 m) of it and whose frame is within 3
 * degrees of the floor's, 12 pt outside the outer wall face, left to right / top to bottom; a
 * string is dropped when its text does not fit its line or it overlaps the previous one.
 */
export function outerDimensions(
  canvas: Canvas,
  floor: ModelFloor,
  view: PlanView,
  minWall: number,
): DimensionString[] {
  const geometry = floor.metrics?.geometry;
  const outer = wallRect(floor, view, minWall);
  if (geometry === undefined || outer === undefined) {
    return [];
  }
  const thickest = Math.max(
    0,
    ...planBands(geometry, view.m(minWall)).map((band) => band.thickness),
  );
  const reach = (thickest + 0.3) * view.scale;
  const floorAngle = view.rotationDegrees;
  const candidates: DimensionString[] = [];
  for (const room of floor.rooms) {
    const planRoom = geometry.rooms.find((r) => r.id === room.metrics.roomId);
    if (planRoom === undefined) {
      continue;
    }
    const roomAngle = (room.metrics.frameAngleRadians * 180) / Math.PI;
    let difference = Math.abs(roomAngle - floorAngle) % 90;
    difference = Math.min(difference, 90 - difference);
    if (difference > 3) {
      continue;
    }
    const pts = planRoom.polygon.map((p) => view.page(p));
    const box = {
      minX: Math.min(...pts.map((p) => p.x)),
      maxX: Math.max(...pts.map((p) => p.x)),
      minY: Math.min(...pts.map((p) => p.y)),
      maxY: Math.max(...pts.map((p) => p.y)),
    };
    // The room's first axis runs along the page x unless its frame is a quarter turn off.
    const swapped = Math.abs(roomAngle - floorAngle) > 45;
    const bbox = room.metrics.boundingBox;
    const along = feetInches(swapped ? bbox.acrossM : bbox.alongM);
    const across = feetInches(swapped ? bbox.alongM : bbox.acrossM);
    if (Math.abs(box.minY - outer.y) <= reach) {
      candidates.push({ side: "top", at: outer.y - 12, from: box.minX, to: box.maxX, text: along });
    }
    if (Math.abs(outer.y + outer.height - box.maxY) <= reach) {
      candidates.push({
        side: "bottom",
        at: outer.y + outer.height + 12,
        from: box.minX,
        to: box.maxX,
        text: along,
      });
    }
    if (Math.abs(box.minX - outer.x) <= reach) {
      candidates.push({
        side: "left",
        at: outer.x - 12,
        from: box.minY,
        to: box.maxY,
        text: across,
      });
    }
    if (Math.abs(outer.x + outer.width - box.maxX) <= reach) {
      candidates.push({
        side: "right",
        at: outer.x + outer.width + 12,
        from: box.minY,
        to: box.maxY,
        text: across,
      });
    }
  }
  const kept: DimensionString[] = [];
  for (const side of ["top", "bottom", "left", "right"] as const) {
    const own = candidates
      .filter((c) => c.side === side)
      .sort((a, b) => a.from - b.from || a.to - b.to);
    let previousEnd = -Infinity;
    for (const dim of own) {
      const textWidth = canvas.width(dim.text, DIM);
      if (textWidth + 4 > dim.to - dim.from) {
        continue;
      }
      if (dim.from < previousEnd - 2) {
        continue;
      }
      kept.push(dim);
      previousEnd = dim.to;
    }
  }
  return kept;
}

/** Draws dimension strings: 0.4 pt line, 5 pt end ticks at 0.6 pt, Courier 7.5 text outside. */
export function drawDimensions(canvas: Canvas, dims: readonly DimensionString[]): void {
  const doc = canvas.doc;
  for (const dim of dims) {
    const color = dim.muted === true ? COLOR.muted : COLOR.ink;
    const style: TextStyle = { ...DIM, color };
    const horizontal = dim.side === "top" || dim.side === "bottom";
    doc.save();
    if (horizontal) {
      doc.moveTo(dim.from, dim.at).lineTo(dim.to, dim.at);
    } else {
      doc.moveTo(dim.at, dim.from).lineTo(dim.at, dim.to);
    }
    doc.lineWidth(0.4).lineCap("butt").strokeColor(color).stroke();
    for (const end of [dim.from, dim.to]) {
      if (horizontal) {
        doc.moveTo(end, dim.at - 2.5).lineTo(end, dim.at + 2.5);
      } else {
        doc.moveTo(dim.at - 2.5, end).lineTo(dim.at + 2.5, end);
      }
    }
    doc.lineWidth(0.6).strokeColor(color).stroke();
    doc.restore();
    const width = canvas.width(dim.text, style);
    const middle = (dim.from + dim.to) / 2;
    const prepared = canvas.prepare(dim.text, style);
    doc.font(style.font).fontSize(style.size).fillColor(color);
    switch (dim.side) {
      case "top":
        doc.text(prepared, middle - width / 2, dim.at - 2.5, {
          lineBreak: false,
          baseline: "alphabetic",
        });
        break;
      case "bottom":
        doc.text(prepared, middle - width / 2, dim.at + 2.5 + style.size, {
          lineBreak: false,
          baseline: "alphabetic",
        });
        break;
      case "left":
      case "right": {
        const tx = dim.side === "left" ? dim.at - 2.5 : dim.at + 2.5 + style.size;
        doc.save();
        doc.rotate(-90, { origin: [tx, middle] });
        doc.text(prepared, tx - width / 2, middle, { lineBreak: false, baseline: "alphabetic" });
        doc.restore();
        break;
      }
    }
  }
}

/** Page extent of dimension strings (lines and text), for overlap tests. */
export function dimensionRects(canvas: Canvas, dims: readonly DimensionString[]): Rect[] {
  return dims.map((dim) => {
    const width = canvas.width(dim.text, DIM);
    const middle = (dim.from + dim.to) / 2;
    switch (dim.side) {
      case "top":
        return {
          x: Math.min(dim.from, middle - width / 2),
          y: dim.at - 2.5 - 7.5,
          width: Math.max(dim.to - dim.from, width),
          height: 10 + 2.5,
        };
      case "bottom":
        return {
          x: Math.min(dim.from, middle - width / 2),
          y: dim.at - 2.5,
          width: Math.max(dim.to - dim.from, width),
          height: 10 + 2.5 + 2,
        };
      case "left":
        return {
          x: dim.at - 2.5 - 7.5,
          y: Math.min(dim.from, middle - width / 2),
          width: 10 + 2.5,
          height: Math.max(dim.to - dim.from, width),
        };
      case "right":
        return {
          x: dim.at - 2.5,
          y: Math.min(dim.from, middle - width / 2),
          width: 10 + 2.5 + 2,
          height: Math.max(dim.to - dim.from, width),
        };
    }
  });
}
