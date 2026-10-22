// Drawing a capture's plan on a page: the view (plan metres -> page points: turned clockwise by
// the squaring rotation, uniform scale, y down) and the elements of system 1ab section 5: room
// fills, objects and fixture symbols, wall bands, windows, doors and passages.
//
// Shapes are drawn in plan metres under the view's transform (a similarity), so line widths and
// dashes given in points are divided by the scale. Text is always drawn in page space.

import type { Canvas } from "../layout/canvas.js";
import type { FillClass } from "../model.js";
import {
  add,
  distance,
  dot,
  scale,
  sub,
  unit,
  type PlanGeometry,
  type PlanObject,
  type PlanOpening,
  type PlanWall,
  type Point,
} from "../metrics/plan-geometry.js";
import { METRES_PER_INCH } from "../metrics/units.js";
import { COLOR } from "../tokens.js";
import { bandSide, openingGeometry, wallBands, type BandSide, type WallBand } from "./walls.js";

/** Assumed wall thickness when the scan reports none: 4.5 in between rooms, 6 in otherwise. */
export const INTERIOR_WALL_M = 4.5 * METRES_PER_INCH;
export const EXTERIOR_WALL_M = 6 * METRES_PER_INCH;

export function assumedThickness(wall: PlanWall): number {
  if (wall.thickness > 0) {
    return wall.thickness;
  }
  return wall.roomIds.length >= 2 ? INTERIOR_WALL_M : EXTERIOR_WALL_M;
}

export const FILL_COLOR: Record<Exclude<FillClass, "outdoor">, string> = {
  habitable: COLOR.nude,
  wet: COLOR.wet,
  other: COLOR.ground,
};

/** Plan metres turned clockwise by `rotationDegrees`, then scaled onto the page. */
export class PlanView {
  readonly cos: number;
  readonly sin: number;

  constructor(
    readonly rotationDegrees: number,
    /** Points per metre. */
    readonly scale: number,
    /** Page point of frame coordinate (minX, maxY), i.e. the top-left of the drawing. */
    readonly originX: number,
    readonly originY: number,
    readonly minX: number,
    readonly maxY: number,
  ) {
    const radians = (rotationDegrees * Math.PI) / 180;
    this.cos = Math.cos(radians);
    this.sin = Math.sin(radians);
  }

  /** Plan point turned into the drawing frame (metres, y up). */
  frame(p: Point): Point {
    return { x: p.x * this.cos + p.y * this.sin, y: -p.x * this.sin + p.y * this.cos };
  }

  /** Plan point to page point. */
  page(p: Point): Point {
    const f = this.frame(p);
    return {
      x: this.originX + this.scale * (f.x - this.minX),
      y: this.originY + this.scale * (this.maxY - f.y),
    };
  }

  /** Points per metre to metres for a length in points. */
  m(points: number): number {
    return points / this.scale;
  }

  /** Applies plan metres -> page points to the current graphics state. */
  apply(doc: PDFKit.PDFDocument): void {
    const s = this.scale;
    doc.transform(
      s * this.cos,
      s * this.sin,
      s * this.sin,
      -s * this.cos,
      this.originX - s * this.minX,
      this.originY + s * this.maxY,
    );
  }
}

/** Frame-coordinate bounds of plan points under a rotation (no scale). */
export function frameBounds(
  points: readonly Point[],
  rotationDegrees: number,
): { minX: number; minY: number; maxX: number; maxY: number } | undefined {
  if (points.length === 0) {
    return undefined;
  }
  const probe = new PlanView(rotationDegrees, 1, 0, 0, 0, 0);
  let box: { minX: number; minY: number; maxX: number; maxY: number } | undefined;
  for (const point of points) {
    const f = probe.frame(point);
    if (box === undefined) {
      box = { minX: f.x, minY: f.y, maxX: f.x, maxY: f.y };
    } else {
      box.minX = Math.min(box.minX, f.x);
      box.minY = Math.min(box.minY, f.y);
      box.maxX = Math.max(box.maxX, f.x);
      box.maxY = Math.max(box.maxY, f.y);
    }
  }
  return box;
}

/** The bands of every wall of a plan, `minWallM` metres thick at least. */
export function planBands(geometry: PlanGeometry, minWallM: number): WallBand[] {
  return wallBands(
    geometry.walls.map((wall) => ({ a: wall.start, b: wall.end, wall })),
    geometry.rooms,
    (wall) => Math.max(assumedThickness(wall), minWallM),
  );
}

/** Where an opening's wall band is and how thick it is drawn. */
export function openingBand(
  geometry: PlanGeometry,
  opening: PlanOpening,
  minWallM: number,
): { wall: PlanWall | undefined; thickness: number; side: BandSide } {
  const wall = geometry.wallById.get(opening.wallId);
  const thickness = Math.max(
    wall === undefined ? opening.wallThickness : assumedThickness(wall),
    minWallM,
  );
  return { wall, thickness, side: wall === undefined ? 0 : bandSide(wall, geometry.rooms) };
}

function polygonPath(doc: PDFKit.PDFDocument, points: readonly Point[]): void {
  const [first, ...rest] = points;
  if (first === undefined) {
    return;
  }
  doc.moveTo(first.x, first.y);
  for (const p of rest) {
    doc.lineTo(p.x, p.y);
  }
  doc.closePath();
}

/** Runs `draw` with the plan transform applied. */
export function inPlan(
  canvas: Canvas,
  view: PlanView,
  draw: (doc: PDFKit.PDFDocument) => void,
): void {
  const doc = canvas.doc;
  doc.save();
  view.apply(doc);
  draw(doc);
  doc.restore();
}

/** Room fills; outdoor rooms get a dashed outline instead. */
export function drawFills(
  canvas: Canvas,
  view: PlanView,
  rooms: ReadonlyArray<{ readonly polygon: readonly Point[]; readonly fill: FillClass }>,
): void {
  inPlan(canvas, view, (doc) => {
    for (const room of rooms) {
      if (room.fill === "outdoor") {
        doc.save();
        polygonPath(doc, room.polygon);
        doc
          .lineWidth(view.m(0.6))
          .dash(view.m(4), { space: view.m(3) })
          .strokeColor(COLOR.muted)
          .stroke();
        doc.restore();
        continue;
      }
      polygonPath(doc, room.polygon);
      doc.fill(FILL_COLOR[room.fill]);
    }
  });
}

/** Key-plan fills: the highlighted room in ink, the others unfilled. */
export function drawKeyFill(canvas: Canvas, view: PlanView, polygon: readonly Point[]): void {
  inPlan(canvas, view, (doc) => {
    polygonPath(doc, polygon);
    doc.fill(COLOR.ink);
  });
}

/** The box of an object in its local frame: centre, unit axes, half sizes (metres). */
interface LocalBox {
  readonly center: Point;
  /** Unit vector along the box's local x (width). */
  readonly ex: Point;
  /** Unit vector along the box's local z (depth). */
  readonly ez: Point;
  readonly w: number;
  readonly d: number;
}

function localBox(object: PlanObject): LocalBox {
  const [c0, c1, , c3] = object.corners as [Point, Point, Point, Point];
  const along = sub(c3, c0);
  const across = sub(c1, c0);
  return {
    center: object.center,
    ex: unit(along),
    ez: unit(across),
    w: distance(c3, c0),
    d: distance(c1, c0),
  };
}

/** Plan point of local box coordinates (u across width from -w/2, v across depth from -d/2). */
function at(box: LocalBox, u: number, v: number): Point {
  return add(box.center, add(scale(box.ex, u), scale(box.ez, v)));
}

const KAPPA = 0.5522847498;

function ellipsePath(
  doc: PDFKit.PDFDocument,
  box: LocalBox,
  cu: number,
  cv: number,
  ru: number,
  rv: number,
): void {
  const p = (u: number, v: number) => at(box, cu + u, cv + v);
  const start = p(ru, 0);
  doc.moveTo(start.x, start.y);
  const quarter = (u0: number, v0: number, u1: number, v1: number, u2: number, v2: number) => {
    const a = p(u0, v0);
    const b = p(u1, v1);
    const c = p(u2, v2);
    doc.bezierCurveTo(a.x, a.y, b.x, b.y, c.x, c.y);
  };
  quarter(ru, rv * KAPPA, ru * KAPPA, rv, 0, rv);
  quarter(-ru * KAPPA, rv, -ru, rv * KAPPA, -ru, 0);
  quarter(-ru, -rv * KAPPA, -ru * KAPPA, -rv, 0, -rv);
  quarter(ru * KAPPA, -rv, ru, -rv * KAPPA, ru, 0);
  doc.closePath();
}

function roundedRectPath(
  doc: PDFKit.PDFDocument,
  box: LocalBox,
  u0: number,
  v0: number,
  u1: number,
  v1: number,
  r: number,
): void {
  const radius = Math.max(0, Math.min(r, (u1 - u0) / 2, (v1 - v0) / 2));
  const k = radius * (1 - KAPPA);
  const p = (u: number, v: number) => at(box, u, v);
  const move = (u: number, v: number) => {
    const q = p(u, v);
    doc.moveTo(q.x, q.y);
  };
  const line = (u: number, v: number) => {
    const q = p(u, v);
    doc.lineTo(q.x, q.y);
  };
  const curve = (a: [number, number], b: [number, number], c: [number, number]) => {
    const qa = p(...a);
    const qb = p(...b);
    const qc = p(...c);
    doc.bezierCurveTo(qa.x, qa.y, qb.x, qb.y, qc.x, qc.y);
  };
  move(u0 + radius, v0);
  line(u1 - radius, v0);
  curve([u1 - k, v0], [u1, v0 + k], [u1, v0 + radius]);
  line(u1, v1 - radius);
  curve([u1, v1 - k], [u1 - k, v1], [u1 - radius, v1]);
  line(u0 + radius, v1);
  curve([u0 + k, v1], [u0, v1 - k], [u0, v1 - radius]);
  line(u0, v0 + radius);
  curve([u0, v0 + k], [u0 + k, v0], [u0 + radius, v0]);
  doc.closePath();
}

/** Distance from a point to the nearest wall centreline. */
function nearestWall(point: Point, walls: readonly PlanWall[]): number {
  let best = Infinity;
  for (const wall of walls) {
    const ab = sub(wall.end, wall.start);
    const lengthSquared = dot(ab, ab);
    const t =
      lengthSquared > 0
        ? Math.max(0, Math.min(1, dot(sub(point, wall.start), ab) / lengthSquared))
        : 0;
    best = Math.min(best, distance(point, add(wall.start, scale(ab, t))));
  }
  return best;
}

/** Objects with their symbols, parents before children. */
export function drawObjects(
  canvas: Canvas,
  view: PlanView,
  objects: readonly PlanObject[],
  walls: readonly PlanWall[],
): void {
  const ordered = [
    ...objects.filter((o) => o.parentId === undefined),
    ...objects.filter((o) => o.parentId !== undefined),
  ];
  inPlan(canvas, view, (doc) => {
    const stroke = view.m(0.6);
    for (const object of ordered) {
      const box = localBox(object);
      const low = object.confidence === "low";
      const outline = (path: () => void, dashed: boolean, fill: boolean) => {
        doc.save();
        path();
        doc.lineWidth(stroke).lineJoin("miter").lineCap("butt").strokeColor(COLOR.muted);
        if (dashed) {
          doc.dash(view.m(1.8), { space: view.m(1.2) });
        }
        if (fill) {
          doc.fillColor(COLOR.surface).fillAndStroke();
        } else {
          doc.stroke();
        }
        doc.restore();
      };
      const { w, d } = box;
      if (object.category === "toilet") {
        // Tank on the side nearest a wall, bowl in front of it.
        const back =
          nearestWall(at(box, 0, -d / 2), walls) <= nearestWall(at(box, 0, d / 2), walls) ? -1 : 1;
        const tankFar = back * (d / 2 - 0.3 * d);
        const tank: [number, number] = back < 0 ? [-d / 2, tankFar] : [tankFar, d / 2];
        outline(
          () =>
            polygonPath(doc, [
              at(box, -w / 2, tank[0]),
              at(box, w / 2, tank[0]),
              at(box, w / 2, tank[1]),
              at(box, -w / 2, tank[1]),
            ]),
          low,
          true,
        );
        const bowlCentre = back * (d / 2 - 0.64 * d);
        outline(() => ellipsePath(doc, box, 0, bowlCentre, 0.46 * w, 0.34 * d), low, true);
        continue;
      }
      outline(() => polygonPath(doc, object.corners), low, true);
      const inner = (path: () => void) => outline(path, false, false);
      switch (object.category) {
        case "bathtub": {
          const i = Math.min(w, d) * 0.18;
          inner(() => roundedRectPath(doc, box, -w / 2 + i, -d / 2 + i, w / 2 - i, d / 2 - i, i));
          break;
        }
        case "sink":
          inner(() => ellipsePath(doc, box, 0, 0, w * 0.34, d * 0.32));
          break;
        case "stove": {
          const r = Math.min(w, d) * 0.17;
          for (const [fu, fv] of [
            [0.27, 0.3],
            [0.73, 0.3],
            [0.27, 0.7],
            [0.73, 0.7],
          ] as const) {
            inner(() => ellipsePath(doc, box, -w / 2 + fu * w, -d / 2 + fv * d, r, r));
          }
          break;
        }
        default:
          break;
      }
    }
  });
}

/** Wall bands (filled ink, nonzero). */
export function drawWalls(canvas: Canvas, view: PlanView, bands: readonly WallBand[]): void {
  if (bands.length === 0) {
    return;
  }
  inPlan(canvas, view, (doc) => {
    for (const band of bands) {
      polygonPath(doc, band.corners);
    }
    doc.fill(COLOR.ink, "nonzero");
  });
}

/** An opening with where its wall band is. */
export interface OpeningInBand {
  readonly opening: PlanOpening;
  readonly wall: PlanWall | undefined;
  readonly thickness: number;
  readonly side: BandSide;
}

/**
 * Windows, doors and passages: the wall band cleared to the page colour over the opening, then
 * two 0.6 pt ink lines 2 pt apart (window) or a 0.4 pt muted threshold (door solid, passage
 * dashed 2 / 2) along the band's middle.
 */
export function drawOpenings(
  canvas: Canvas,
  view: PlanView,
  openings: readonly OpeningInBand[],
): void {
  const usable = openings.filter((o) => distance(o.opening.from, o.opening.to) > 0);
  const shapes = usable.map((o) =>
    openingGeometry(o.opening.from, o.opening.to, o.wall, o.thickness, o.side, view.m(0.1)),
  );
  inPlan(canvas, view, (doc) => {
    for (const shape of shapes) {
      polygonPath(doc, shape.clear);
      doc.fill(COLOR.surface);
    }
    usable.forEach((o, i) => {
      const shape = shapes[i] as (typeof shapes)[number];
      doc.save();
      if (o.opening.kind === "window") {
        for (const offset of [view.m(1), -view.m(1)]) {
          const [a, b] = shape.middle(offset);
          doc.moveTo(a.x, a.y).lineTo(b.x, b.y);
        }
        doc.lineWidth(view.m(0.6)).lineCap("butt").strokeColor(COLOR.ink).stroke();
      } else {
        const [a, b] = shape.middle(0);
        doc.moveTo(a.x, a.y).lineTo(b.x, b.y);
        doc.lineWidth(view.m(0.4)).lineCap("butt").strokeColor(COLOR.muted);
        if (o.opening.kind === "opening") {
          doc.dash(view.m(2), { space: view.m(2) });
        }
        doc.stroke();
      }
      doc.restore();
    });
  });
}

/** Page polygons of what a drawing inks (for overlap tests). */
export function pagePolygons(view: PlanView, polygons: ReadonlyArray<readonly Point[]>): Point[][] {
  return polygons.map((polygon) => polygon.map((p) => view.page(p)));
}
