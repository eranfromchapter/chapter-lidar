// Plane geometry of the measurement engine, ported line for line from PlanExport
// MetricsGeometry.swift: the dominant axis of outlines, rectangles in that frame, the largest
// inscribed rectangle and raster spans.

import { contains, dot, length, sub, type Point } from "./plan-geometry.js";

/** Outlines with at most this many corners get the exact inscribed-rectangle search. */
export const EXACT_SEARCH_VERTEX_LIMIT = 64;
/** Raster cell of the inscribed-rectangle search for large outlines, metres. */
export const RASTER_CELL_M = 0.01;
/** Coordinates closer than this are the same coordinate, metres. */
export const EPSILON = 1e-9;
/** Edges within this angle of the dominant axis (modulo 90 degrees) run along it, radians. */
export const AXIS_TOLERANCE_RADIANS = (3.0 * Math.PI) / 180;
const SLANTED_SEARCH_STEPS = 96;
const SLANTED_SEARCH_ROUNDS = 8;

/** A rectangle in plan coordinates whose sides run along a measurement frame. */
export interface MeasuredRectangle {
  /** Side along the frame's first axis, metres. */
  readonly alongM: number;
  /** Side along the frame's second axis, metres. */
  readonly acrossM: number;
  /** Centre in plan coordinates. */
  readonly center: Point;
  /** Direction of the frame's first axis, radians counter-clockwise from plan +x. */
  readonly angleRadians: number;
  /** Corners in plan coordinates, counter-clockwise from the corner lowest along both axes. */
  readonly corners: readonly Point[];
}

export const longSide = (r: MeasuredRectangle): number => Math.max(r.alongM, r.acrossM);
export const shortSide = (r: MeasuredRectangle): number => Math.min(r.alongM, r.acrossM);

/** Axes turned by `angle` radians counter-clockwise from the plan axes. */
export class Frame {
  readonly u: Point;
  readonly v: Point;

  constructor(readonly angle: number) {
    this.u = { x: Math.cos(angle), y: Math.sin(angle) };
    this.v = { x: -Math.sin(angle), y: Math.cos(angle) };
  }

  /** Plan point to frame coordinates. */
  local(point: Point): Point {
    return { x: dot(point, this.u), y: dot(point, this.v) };
  }

  /** Frame coordinates to plan point. */
  plan(point: Point): Point {
    return {
      x: this.u.x * point.x + this.v.x * point.y,
      y: this.u.y * point.x + this.v.y * point.y,
    };
  }
}

/** An axis-aligned rectangle in frame coordinates. */
export interface Box {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

export const boxWidth = (b: Box): number => b.maxX - b.minX;
export const boxHeight = (b: Box): number => b.maxY - b.minY;
export const boxArea = (b: Box): number => boxWidth(b) * boxHeight(b);
const transposed = (b: Box): Box => ({ minX: b.minY, minY: b.minX, maxX: b.maxY, maxY: b.maxX });

export function measured(box: Box, frame: Frame): MeasuredRectangle {
  const corners = [
    { x: box.minX, y: box.minY },
    { x: box.maxX, y: box.minY },
    { x: box.maxX, y: box.maxY },
    { x: box.minX, y: box.maxY },
  ].map((p) => frame.plan(p));
  return {
    alongM: boxWidth(box),
    acrossM: boxHeight(box),
    center: frame.plan({ x: (box.minX + box.maxX) / 2, y: (box.minY + box.maxY) / 2 }),
    angleRadians: frame.angle,
    corners,
  };
}

/**
 * Whether `a` is the better inscribed rectangle: larger area; on equal area (within 1e-9 m²)
 * the squarer one (longer short side), then the one further down and left.
 */
export function isBetter(a: Box, other: Box): boolean {
  if (Math.abs(boxArea(a) - boxArea(other)) > 1e-9) {
    return boxArea(a) > boxArea(other);
  }
  const short = Math.min(boxWidth(a), boxHeight(a));
  const otherShort = Math.min(boxWidth(other), boxHeight(other));
  if (Math.abs(short - otherShort) > EPSILON) {
    return short > otherShort;
  }
  if (Math.abs(a.minX - other.minX) > EPSILON) {
    return a.minX < other.minX;
  }
  return a.minY < other.minY - EPSILON;
}

/** `angle` modulo 90 degrees, in (-pi/4, pi/4]. */
export function axisAngle(angle: number): number {
  let result = angle % (Math.PI / 2);
  if (result > Math.PI / 4) {
    result -= Math.PI / 2;
  }
  if (result <= -Math.PI / 4) {
    result += Math.PI / 2;
  }
  return result;
}

/**
 * Direction, radians in (-pi/4, pi/4], that the outlines' edges run along (directions modulo
 * 90 degrees): the direction most outline length runs along to within AXIS_TOLERANCE_RADIANS,
 * refined to the length-weighted mean of those edges. Zero when there are no edges.
 */
export function dominantAngle(polygons: ReadonlyArray<readonly Point[]>): number {
  const edges: Array<{ angle: number; length: number }> = [];
  for (const polygon of polygons) {
    for (let index = 0; index < polygon.length; index += 1) {
      const edge = sub(polygon[(index + 1) % polygon.length] as Point, polygon[index] as Point);
      const edgeLength = length(edge);
      if (!(edgeLength > EPSILON)) {
        continue;
      }
      edges.push({ angle: axisAngle(Math.atan2(edge.y, edge.x)), length: edgeLength });
    }
  }
  const apart = (a: number, b: number) => {
    const difference = Math.abs(a - b) % (Math.PI / 2);
    return Math.min(difference, Math.PI / 2 - difference);
  };
  let best: { angle: number; support: number } | undefined;
  for (const candidate of edges) {
    const support = edges
      .filter((edge) => apart(edge.angle, candidate.angle) <= AXIS_TOLERANCE_RADIANS)
      .reduce((sum, edge) => sum + edge.length, 0);
    if (best === undefined || support > best.support + EPSILON) {
      best = { angle: candidate.angle, support };
    }
  }
  if (best === undefined) {
    return 0;
  }
  let sine = 0;
  let cosine = 0;
  for (const edge of edges) {
    if (apart(edge.angle, best.angle) <= AXIS_TOLERANCE_RADIANS) {
      sine += edge.length * Math.sin(4 * edge.angle);
      cosine += edge.length * Math.cos(4 * edge.angle);
    }
  }
  const angle = axisAngle(Math.atan2(sine, cosine) / 4);
  return Math.abs(angle) < EPSILON ? 0 : angle;
}

/** Bounding box of `points` (frame coordinates); undefined when there are none. */
export function bounds(points: readonly Point[]): Box | undefined {
  const first = points[0];
  if (first === undefined) {
    return undefined;
  }
  const box = { minX: first.x, minY: first.y, maxX: first.x, maxY: first.y };
  for (const point of points.slice(1)) {
    box.minX = Math.min(box.minX, point.x);
    box.minY = Math.min(box.minY, point.y);
    box.maxX = Math.max(box.maxX, point.x);
    box.maxY = Math.max(box.maxY, point.y);
  }
  return box;
}

/** The largest axis-aligned rectangle inside `polygon` (frame coordinates). */
export function largestInscribedRectangle(polygon: readonly Point[]): Box | undefined {
  if (polygon.length < 3) {
    return undefined;
  }
  if (polygon.length <= EXACT_SEARCH_VERTEX_LIMIT) {
    const byX = sweepInscribed(polygon);
    const swapped = sweepInscribed(polygon.map((p) => ({ x: p.y, y: p.x })));
    return better(byX, swapped === undefined ? undefined : transposed(swapped));
  }
  return rasterInscribed(polygon, RASTER_CELL_M);
}

function better(a: Box | undefined, b: Box | undefined): Box | undefined {
  if (a === undefined) {
    return b;
  }
  if (b === undefined) {
    return a;
  }
  return isBetter(b, a) ? b : a;
}

function isAlongAxis(a: Point, b: Point): boolean {
  const dx = Math.abs(b.x - a.x);
  const dy = Math.abs(b.y - a.y);
  return Math.min(dx, dy) <= 1e-9 * Math.max(dx, dy, 1);
}

function sweepInscribed(polygon: readonly Point[]): Box | undefined {
  const edges = polygon.map((p, i) => [p, polygon[(i + 1) % polygon.length] as Point] as const);
  const corners = distinctSorted(polygon.map((p) => p.x));
  const low = corners[0];
  const high = corners[corners.length - 1];
  const extent = bounds(polygon);
  if (low === undefined || high === undefined || !(high - low > EPSILON) || extent === undefined) {
    return undefined;
  }
  let best: Box | undefined;
  const consider = (left: number, right: number) => {
    if (!(right - left > EPSILON)) {
      return;
    }
    if (best !== undefined && (right - left) * boxHeight(extent) < boxArea(best) - 1e-9) {
      return;
    }
    best = better(best, slabInscribed(polygon, edges, left, right));
  };
  for (let i = 0; i < corners.length; i += 1) {
    for (let j = i + 1; j < corners.length; j += 1) {
      consider(corners[i] as number, corners[j] as number);
    }
  }
  if (!edges.some(([a, b]) => !isAlongAxis(a, b))) {
    return best;
  }
  // Slanted edges: evenly spaced sides too, then a local search round the best pair.
  let step = (high - low) / SLANTED_SEARCH_STEPS;
  const spaced: number[] = [];
  for (let k = 1; k < SLANTED_SEARCH_STEPS; k += 1) {
    spaced.push(low + step * k);
  }
  const xs = distinctSorted([...corners, ...spaced]);
  for (let i = 0; i < xs.length; i += 1) {
    for (let j = i + 1; j < xs.length; j += 1) {
      consider(xs[i] as number, xs[j] as number);
    }
  }
  for (let round = 0; round < SLANTED_SEARCH_ROUNDS; round += 1) {
    const current: Box | undefined = best;
    if (current === undefined) {
      break;
    }
    const offsets = [-4, -3, -2, -1, 0, 1, 2, 3, 4].map((k) => (step * k) / 4);
    const lefts = offsets.map((o) => Math.min(high, Math.max(low, current.minX + o)));
    const rights = offsets.map((o) => Math.min(high, Math.max(low, current.maxX + o)));
    for (const left of lefts) {
      for (const right of rights) {
        consider(left, right);
      }
    }
    step /= 4;
  }
  return best;
}

function slabInscribed(
  polygon: readonly Point[],
  edges: ReadonlyArray<readonly [Point, Point]>,
  left: number,
  right: number,
): Box | undefined {
  const blocked: Array<[number, number]> = [];
  for (const [a, b] of edges) {
    const range = yRange(a, b, left + EPSILON, right - EPSILON);
    if (range !== undefined) {
      blocked.push(range);
    }
  }
  blocked.sort((p, q) =>
    p[0] < q[0] ? -1 : p[0] > q[0] ? 1 : p[1] < q[1] ? -1 : p[1] > q[1] ? 1 : 0,
  );
  let best: Box | undefined;
  let top = -Infinity;
  for (const range of blocked) {
    if (Number.isFinite(top) && range[0] > top + EPSILON) {
      const candidate = { minX: left, minY: top, maxX: right, maxY: range[0] };
      const middle = { x: (left + right) / 2, y: (top + range[0]) / 2 };
      if ((best === undefined || isBetter(candidate, best)) && contains(polygon, middle)) {
        best = candidate;
      }
    }
    top = Math.max(top, range[1]);
  }
  return best;
}

function yRange(a: Point, b: Point, low: number, high: number): [number, number] | undefined {
  if (!(low <= high)) {
    return undefined;
  }
  const dx = b.x - a.x;
  if (Math.abs(dx) < 1e-12) {
    if (!(a.x >= low && a.x <= high)) {
      return undefined;
    }
    return [Math.min(a.y, b.y), Math.max(a.y, b.y)];
  }
  const t0 = (low - a.x) / dx;
  const t1 = (high - a.x) / dx;
  const from = Math.max(0, Math.min(t0, t1));
  const to = Math.min(1, Math.max(t0, t1));
  if (!(from <= to)) {
    return undefined;
  }
  const y0 = a.y + (b.y - a.y) * from;
  const y1 = a.y + (b.y - a.y) * to;
  return [Math.min(y0, y1), Math.max(y0, y1)];
}

/** Sorted values with those within EPSILON of the previous kept value dropped. */
export function distinctSorted(values: readonly number[]): number[] {
  const result: number[] = [];
  for (const value of [...values].sort((p, q) => p - q)) {
    const last = result[result.length - 1];
    if (last === undefined || value - last > EPSILON) {
      result.push(value);
    }
  }
  return result;
}

function rasterInscribed(polygon: readonly Point[], cell: number): Box | undefined {
  const box = bounds(polygon);
  if (box === undefined || !(boxWidth(box) > 0) || !(boxHeight(box) > 0)) {
    return undefined;
  }
  const columns = Math.ceil(boxWidth(box) / cell);
  const rows = Math.ceil(boxHeight(box) / cell);
  const heights = new Array<number>(columns).fill(0);
  const inside = new Array<boolean>(columns).fill(false);
  let best: Box | undefined;
  for (let row = 0; row < rows; row += 1) {
    inside.fill(false);
    const y = box.minY + (row + 0.5) * cell;
    for (const [from, to] of rowSpans(polygon, y, box.minX, cell, columns)) {
      for (let column = from; column < to; column += 1) {
        inside[column] = true;
      }
    }
    for (let column = 0; column < columns; column += 1) {
      heights[column] = inside[column] ? (heights[column] as number) + 1 : 0;
    }
    const stack: number[] = [];
    for (let column = 0; column <= columns; column += 1) {
      const height = column < columns ? (heights[column] as number) : 0;
      while (stack.length > 0 && (heights[stack[stack.length - 1] as number] as number) >= height) {
        const last = stack.pop() as number;
        const barHeight = heights[last] as number;
        if (!(barHeight > 0)) {
          continue;
        }
        const first = (stack.length > 0 ? (stack[stack.length - 1] as number) : -1) + 1;
        const candidate = {
          minX: box.minX + first * cell,
          minY: box.minY + (row - barHeight + 1) * cell,
          maxX: box.minX + column * cell,
          maxY: box.minY + (row + 1) * cell,
        };
        if (best === undefined || isBetter(candidate, best)) {
          best = candidate;
        }
      }
      if (column < columns) {
        stack.push(column);
      }
    }
  }
  return best;
}

/**
 * Columns of the row at `y` whose cell centres lie inside `polygon` (even-odd rule), as
 * half-open [from, to) column ranges clamped to 0..columns.
 */
export function rowSpans(
  polygon: readonly Point[],
  y: number,
  originX: number,
  cell: number,
  columns: number,
): Array<[number, number]> {
  const crossings: number[] = [];
  for (let index = 0; index < polygon.length; index += 1) {
    let a = polygon[index] as Point;
    let b = polygon[(index + 1) % polygon.length] as Point;
    if (a.y > y === b.y > y) {
      continue;
    }
    if (b.x < a.x || (b.x === a.x && b.y < a.y)) {
      [a, b] = [b, a];
    }
    crossings.push(a.x + ((y - a.y) / (b.y - a.y)) * (b.x - a.x));
  }
  crossings.sort((p, q) => p - q);
  const spans: Array<[number, number]> = [];
  for (let index = 0; index + 1 < crossings.length; index += 2) {
    const start = Math.ceil(((crossings[index] as number) - originX) / cell - 0.5);
    const end = Math.ceil(((crossings[index + 1] as number) - originX) / cell - 0.5);
    const lower = Math.max(0, Math.min(columns, start));
    const upper = Math.max(0, Math.min(columns, end));
    if (lower < upper) {
      spans.push([lower, upper]);
    }
  }
  return spans;
}
