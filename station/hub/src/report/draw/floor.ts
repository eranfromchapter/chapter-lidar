// A whole floor on a page (spec 7.4): squared by the floor's dominant angle, fitted uniformly
// into a box (top-left aligned), with fills, objects, walls, openings, room labels and, on the
// floor plan page, the outer dimension strings. Also the key plan of a room page. A room label
// sits on a patch of its room's fill and moves off object boxes to the clearest spot it fits.

import type { Canvas } from "../layout/canvas.js";
import type { ModelFloor, ModelRoom } from "../model.js";
import {
  contains,
  distance,
  distanceToBoundary,
  polygonArea,
  type Point,
} from "../metrics/plan-geometry.js";
import { feetInches } from "../metrics/units.js";
import { COLOR, FONT, type TextStyle } from "../tokens.js";
import {
  FILL_COLOR,
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
  // Room labels: a patch of the room's fill behind each, under the walls and openings (so it
  // knocks out object lines only), and the text over everything.
  const labels = options.labels ? placeRoomLabels(canvas, floor, view) : [];
  for (const label of labels) {
    canvas.fillRect(label.box.x, label.box.y, label.box.width, label.box.height, label.patch);
  }
  drawWalls(canvas, view, bands);
  drawOpenings(
    canvas,
    view,
    geometry.openings.map((opening) => ({ opening, ...openingBand(geometry, opening, minWallM) })),
  );
  for (const label of labels) {
    drawRoomLabel(canvas, label);
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
  return rectCorners(rect).every((corner) => insideConvex(polygon, corner));
}

/** Padding of a room label's patch round its text block, points. */
export const LABEL_PAD = 2;
/**
 * Open floor round a moved label (points) that counts as clear; among clear spots the one
 * nearest the label point wins.
 */
const LABEL_CLEAR = 9;
/** Divisions per side of the grid searched for a clear spot. */
const LABEL_GRID = 48;

/** A room label placed on the page. */
export interface PlacedLabel {
  readonly roomId: string;
  readonly name: string;
  /** Centre of the text block, page x. */
  readonly x: number;
  /** Baseline of the name. */
  readonly baseline: number;
  readonly nameWidth: number;
  /** The area line, when the two-line block fits. */
  readonly area?: string;
  readonly areaWidth: number;
  /** The text block with LABEL_PAD round it: the patch behind the label (page points). */
  readonly box: Rect;
  /** The patch's colour: the room's fill (the page where the room has none). */
  readonly patch: string;
}

/**
 * Room names and areas, where they fit the room's inscribed rectangle: centred on the label
 * point (else the inscribed rectangle's centre) unless an object box lies under or across the
 * block there; then at the clearest spot of the inscribed rectangle (`clearestSpot`).
 */
export function placeRoomLabels(canvas: Canvas, floor: ModelFloor, view: PlanView): PlacedLabel[] {
  const geometry = floor.metrics?.geometry;
  if (geometry === undefined) {
    return [];
  }
  const objects = geometry.objects.map((object) => object.corners.map((p) => view.page(p)));
  const placed: PlacedLabel[] = [];
  for (const room of floor.rooms) {
    const planRoom = geometry.rooms.find((r) => r.id === room.metrics.roomId);
    if (planRoom === undefined) {
      continue;
    }
    const label = placeLabel(canvas, room, view, planRoom.labelPoint, objects);
    if (label !== undefined) {
      placed.push({
        ...label,
        roomId: room.metrics.roomId,
        name: room.name,
        patch: room.fill === "outdoor" ? COLOR.surface : FILL_COLOR[room.fill],
      });
    }
  }
  return placed;
}

/** Draws a placed label's text (the patch is drawn under the walls by `drawFloor`). */
function drawRoomLabel(canvas: Canvas, label: PlacedLabel): void {
  canvas.line(
    label.name,
    NAME,
    label.x - label.nameWidth / 2,
    label.baseline - canvas.baselineOffset(NAME),
  );
  if (label.area !== undefined) {
    const areaBaseline = label.baseline + 11.25;
    canvas.line(
      label.area,
      AREA,
      label.x - label.areaWidth / 2,
      areaBaseline - canvas.baselineOffset(AREA),
    );
  }
}

interface Spot {
  readonly point: Point;
  readonly baseline: number;
  readonly box: Rect;
}

function placeLabel(
  canvas: Canvas,
  room: ModelRoom,
  view: PlanView,
  labelPoint: Point,
  objects: readonly (readonly Point[])[],
): Omit<PlacedLabel, "roomId" | "name" | "patch"> | undefined {
  const inscribed = room.metrics.inscribed.corners.map((corner) => view.page(corner));
  const start = view.page(labelPoint);
  const centre = view.page(room.metrics.inscribed.center);
  const nameWidth = canvas.width(room.name, NAME);
  const area = `${room.words.area} sq ft`;
  const areaWidth = canvas.width(area, AREA);
  const asc = ASC * 7.5;
  const desc = DESC * 7.5;
  // Two lines (name baseline, area baseline 11.25 below), else the name alone; the ink block
  // centred on the point.
  const blocks = [
    { width: Math.max(nameWidth, areaWidth), height: asc + 11.25 + desc, withArea: true },
    { width: nameWidth, height: asc + desc, withArea: false },
  ];
  for (const block of blocks) {
    const at = (point: Point): Spot => {
      const baseline = point.y - block.height / 2 + asc;
      return {
        point,
        baseline,
        box: {
          x: point.x - block.width / 2 - LABEL_PAD,
          y: baseline - asc - LABEL_PAD,
          width: block.width + 2 * LABEL_PAD,
          height: block.height + 2 * LABEL_PAD,
        },
      };
    };
    const first = [start, centre].map(at).find((spot) => fits(inscribed, spot.box));
    if (first === undefined) {
      continue;
    }
    const spot = objects.some((object) => polygonHitsRect(object, first.box))
      ? clearestSpot(first, at, inscribed, objects, start)
      : first;
    return {
      x: spot.point.x,
      baseline: spot.baseline,
      nameWidth,
      areaWidth,
      box: spot.box,
      ...(block.withArea ? { area } : {}),
    };
  }
  return undefined;
}

interface SpotScore {
  /** Object boxes whose outline runs through the block. */
  readonly crossed: number;
  /** Area of object boxes under the block, square points. */
  readonly covered: number;
  /**
   * Open floor round the block, capped at LABEL_CLEAR: to the inscribed rectangle's sides, to
   * object boxes clear of it and to the sides of an object box it lies within; 0 when crossed.
   */
  readonly clearance: number;
  /** Distance from the label point. */
  readonly away: number;
}

/**
 * The spot of the inscribed rectangle for a label block that is crossed by object boxes: the
 * fewest object outlines through the block, then the least object area under it (so clear
 * floor first, then wholly within one object, on its patch, rather than across an edge), then
 * the most open floor round it up to LABEL_CLEAR, then the nearest the label point. Searched on
 * a fixed grid over the rectangle's page box (rows top to bottom, left to right; a later spot
 * wins only when strictly better), so the result is deterministic.
 */
function clearestSpot(
  first: Spot,
  at: (point: Point) => Spot,
  inscribed: readonly Point[],
  objects: readonly (readonly Point[])[],
  start: Point,
): Spot {
  const xs = inscribed.map((p) => p.x);
  const ys = inscribed.map((p) => p.y);
  const area: Rect = {
    x: Math.min(...xs),
    y: Math.min(...ys),
    width: Math.max(...xs) - Math.min(...xs),
    height: Math.max(...ys) - Math.min(...ys),
  };
  const reach: Rect = {
    x: area.x - LABEL_CLEAR,
    y: area.y - LABEL_CLEAR,
    width: area.width + 2 * LABEL_CLEAR,
    height: area.height + 2 * LABEL_CLEAR,
  };
  const near = objects.filter((object) => polygonHitsRect(object, reach));
  const score = (spot: Spot): SpotScore => {
    const corners = rectCorners(spot.box);
    let crossed = 0;
    let covered = 0;
    let clearance = LABEL_CLEAR;
    for (const corner of corners) {
      clearance = Math.min(clearance, distanceToBoundary(inscribed, corner));
    }
    for (const object of near) {
      if (!polygonHitsRect(object, spot.box)) {
        clearance = Math.min(clearance, rectPolygonGap(spot.box, object));
      } else if (corners.every((corner) => contains(object, corner))) {
        covered += spot.box.width * spot.box.height;
        for (const corner of corners) {
          clearance = Math.min(clearance, distanceToBoundary(object, corner));
        }
      } else {
        crossed += 1;
        covered += polygonArea(clipToRect(object, spot.box));
        clearance = 0;
      }
    }
    return {
      crossed,
      covered,
      clearance,
      away: Math.hypot(spot.point.x - start.x, spot.point.y - start.y),
    };
  };
  const better = (a: SpotScore, b: SpotScore): boolean => {
    if (a.crossed !== b.crossed) {
      return a.crossed < b.crossed;
    }
    if (Math.abs(a.covered - b.covered) > 1e-6) {
      return a.covered < b.covered;
    }
    if (Math.abs(a.clearance - b.clearance) > 1e-6) {
      return a.clearance > b.clearance;
    }
    return a.away < b.away - 1e-6;
  };
  let best = first;
  let bestScore = score(first);
  for (let row = 0; row <= LABEL_GRID; row += 1) {
    for (let column = 0; column <= LABEL_GRID; column += 1) {
      const spot = at({
        x: area.x + (area.width * column) / LABEL_GRID,
        y: area.y + (area.height * row) / LABEL_GRID,
      });
      if (!fits(inscribed, spot.box)) {
        continue;
      }
      const candidate = score(spot);
      if (better(candidate, bestScore)) {
        best = spot;
        bestScore = candidate;
      }
    }
  }
  return best;
}

function rectCorners(rect: Rect): Point[] {
  return [
    { x: rect.x, y: rect.y },
    { x: rect.x + rect.width, y: rect.y },
    { x: rect.x + rect.width, y: rect.y + rect.height },
    { x: rect.x, y: rect.y + rect.height },
  ];
}

/** A polygon clipped to a rectangle (Sutherland-Hodgman; exact for convex polygons). */
function clipToRect(polygon: readonly Point[], rect: Rect): Point[] {
  const edges: Array<[(p: Point) => number, number]> = [
    [(p) => p.x, rect.x],
    [(p) => -p.x, -(rect.x + rect.width)],
    [(p) => p.y, rect.y],
    [(p) => -p.y, -(rect.y + rect.height)],
  ];
  let out: Point[] = [...polygon];
  for (const [value, limit] of edges) {
    const input = out;
    out = [];
    for (let i = 0; i < input.length; i += 1) {
      const a = input[i] as Point;
      const b = input[(i + 1) % input.length] as Point;
      const va = value(a) - limit;
      const vb = value(b) - limit;
      if (va >= 0) {
        out.push(a);
      }
      if (va >= 0 !== vb >= 0) {
        const t = va / (va - vb);
        out.push({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
      }
    }
    if (out.length === 0) {
      break;
    }
  }
  return out;
}

/** Distance between a rectangle and a polygon that do not overlap. */
function rectPolygonGap(rect: Rect, polygon: readonly Point[]): number {
  let gap = Infinity;
  for (const p of polygon) {
    const dx = Math.max(rect.x - p.x, 0, p.x - (rect.x + rect.width));
    const dy = Math.max(rect.y - p.y, 0, p.y - (rect.y + rect.height));
    gap = Math.min(gap, Math.hypot(dx, dy));
  }
  for (const corner of rectCorners(rect)) {
    gap = Math.min(gap, distanceToBoundary(polygon, corner));
  }
  return gap;
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
