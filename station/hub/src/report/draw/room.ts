// One room in its own frame (spec 5.5.1, 7.5): turned so its dominant axis is horizontal, fitted
// top-left into the room page's drawing box with room for the dimension strings it uses. Walls
// are the capture's walls along the room's walled edges (RoomMetrics rule), clipped to them;
// then openings, objects with symbols, the bounding box (dashed), the inscribed rectangle
// (dotted, only when the room is not a rectangle), numbered item markers and dimension strings.

import type { Canvas } from "../layout/canvas.js";
import { ITEM_GROUPS, type ModelFloor, type ModelRoom } from "../model.js";
import {
  add,
  distance,
  dot,
  leftNormal,
  scale,
  sub,
  unit,
  type PlanOpening,
  type PlanWall,
  type Point,
} from "../metrics/plan-geometry.js";
import { WALL_MATCH_ANGLE_DEGREES, WALL_MATCH_DISTANCE_M } from "../metrics/room-metrics.js";
import { feetInches } from "../metrics/units.js";
import { COLOR } from "../tokens.js";
import { drawMarker } from "./glyphs.js";
import { drawDimensions, type DimensionString, type Rect } from "./floor.js";
import {
  PlanView,
  assumedThickness,
  drawObjects,
  drawOpenings,
  drawWalls,
  frameBounds,
  inPlan,
  openingBand,
} from "./plan-view.js";
import { wallBands, type WallBand } from "./walls.js";

/** The room's wall pieces as bands at a minimum thickness (metres). */
function roomBands(floor: ModelFloor, room: ModelRoom, minWallM: number): WallBand[] {
  return wallBands(wallPieces(floor, room), floor.metrics?.geometry.rooms ?? [], (wall) =>
    Math.max(assumedThickness(wall), minWallM),
  );
}

export const ROOM_BOX: Rect = { x: 58, y: 118, width: 271, height: 314 };
const DIM_MARGIN = 24;
const DIM_OFFSET = 9;
const MIN_WALL = 2;

interface WallPiece {
  readonly a: Point;
  readonly b: Point;
  readonly wall: PlanWall;
}

/** The parts of the capture's walls that run along the room's walled edges. */
function wallPieces(floor: ModelFloor, room: ModelRoom): WallPiece[] {
  const geometry = floor.metrics?.geometry;
  if (geometry === undefined) {
    return [];
  }
  const pieces: WallPiece[] = [];
  const maxSine = Math.sin((WALL_MATCH_ANGLE_DEGREES * Math.PI) / 180);
  for (const edge of room.metrics.edges) {
    if (edge.spans.length === 0) {
      continue;
    }
    const length = distance(edge.a, edge.b);
    const u = unit(sub(edge.b, edge.a));
    const n = leftNormal(u);
    for (const wall of geometry.walls) {
      const direction = sub(wall.end, wall.start);
      const wallLength = distance(wall.start, wall.end);
      if (!(wallLength > 1e-9)) {
        continue;
      }
      if (Math.abs(u.x * direction.y - u.y * direction.x) / wallLength > maxSine) {
        continue;
      }
      const t0 = dot(sub(wall.start, edge.a), u);
      const t1 = dot(sub(wall.end, edge.a), u);
      if (!(Math.abs(t1 - t0) > 1e-9)) {
        continue;
      }
      for (const span of edge.spans) {
        const from = Math.max(0, span.from, Math.min(t0, t1));
        const to = Math.min(length, span.to, Math.max(t0, t1));
        if (!(to - from > 1e-6)) {
          continue;
        }
        const point = (t: number) => add(wall.start, scale(direction, (t - t0) / (t1 - t0)));
        const a = point(from);
        const b = point(to);
        if (
          Math.abs(dot(sub(a, edge.a), n)) > WALL_MATCH_DISTANCE_M ||
          Math.abs(dot(sub(b, edge.a), n)) > WALL_MATCH_DISTANCE_M
        ) {
          continue;
        }
        pieces.push({ a, b, wall });
      }
    }
  }
  return pieces;
}

function roomOpenings(floor: ModelFloor, room: ModelRoom): PlanOpening[] {
  const ids = new Set(room.metrics.openings.map((opening) => opening.id));
  return (floor.metrics?.geometry.openings ?? []).filter((opening) => ids.has(opening.id));
}

function roomObjects(floor: ModelFloor, room: ModelRoom) {
  const ids = new Set(room.metrics.objects.map((object) => object.id));
  return (floor.metrics?.geometry.objects ?? []).filter((object) => ids.has(object.id));
}

export interface RoomLayout {
  readonly view: PlanView;
  readonly dims: DimensionString[];
  readonly markers: ReadonlyArray<{
    shape: (typeof ITEM_GROUPS)[number]["shape"];
    x: number;
    y: number;
    label: string;
  }>;
}

/** The room's view and what is drawn around it. */
export function layoutRoom(
  canvas: Canvas,
  floor: ModelFloor,
  room: ModelRoom,
): RoomLayout | undefined {
  const geometry = floor.metrics?.geometry;
  if (geometry === undefined) {
    return undefined;
  }
  const rotation = (room.metrics.frameAngleRadians * 180) / Math.PI;
  const objects = roomObjects(floor, room);
  const inscribed = !room.rectangular;
  const extentAt = (minWallM: number) =>
    frameBounds(
      [
        ...roomBands(floor, room, minWallM).flatMap((band) => band.corners),
        ...room.metrics.boundingBox.corners,
        ...objects.flatMap((object) => object.corners),
      ],
      rotation,
    );
  let extent = extentAt(0);
  if (extent === undefined) {
    return undefined;
  }
  const left = DIM_MARGIN;
  const top = DIM_MARGIN;
  const right = inscribed ? DIM_MARGIN : 0;
  const bottom = inscribed ? DIM_MARGIN : 0;
  const availableWidth = ROOM_BOX.width - left - right;
  const availableHeight = ROOM_BOX.height - top - bottom;
  const fit = (e: NonNullable<typeof extent>) =>
    Math.min(
      availableWidth / Math.max(e.maxX - e.minX, 1e-6),
      availableHeight / Math.max(e.maxY - e.minY, 1e-6),
    );
  // The wall minimum depends on the scale: settle it in a few rounds.
  let s = fit(extent);
  for (let round = 0; round < 4; round += 1) {
    extent = extentAt(MIN_WALL / s) ?? extent;
    s = fit(extent);
  }
  const view = new PlanView(
    rotation,
    s,
    ROOM_BOX.x + left,
    ROOM_BOX.y + top,
    extent.minX,
    extent.maxY,
  );

  // Dimension strings around the bounding box (and the inscribed rectangle).
  const rectOf = (corners: readonly Point[]) => {
    const pts = corners.map((corner) => view.page(corner));
    return {
      minX: Math.min(...pts.map((p) => p.x)),
      maxX: Math.max(...pts.map((p) => p.x)),
      minY: Math.min(...pts.map((p) => p.y)),
      maxY: Math.max(...pts.map((p) => p.y)),
    };
  };
  const b = rectOf(room.metrics.boundingBox.corners);
  const dims: DimensionString[] = [
    {
      side: "top",
      at: b.minY - DIM_OFFSET,
      from: b.minX,
      to: b.maxX,
      text: feetInches(room.metrics.boundingBox.alongM),
    },
    {
      side: "left",
      at: b.minX - DIM_OFFSET,
      from: b.minY,
      to: b.maxY,
      text: feetInches(room.metrics.boundingBox.acrossM),
    },
  ];
  if (inscribed) {
    const i = rectOf(room.metrics.inscribed.corners);
    dims.push(
      {
        side: "bottom",
        at: b.maxY + DIM_OFFSET,
        from: i.minX,
        to: i.maxX,
        text: feetInches(room.metrics.inscribed.alongM),
        muted: true,
      },
      {
        side: "right",
        at: b.maxX + DIM_OFFSET,
        from: i.minY,
        to: i.maxY,
        text: feetInches(room.metrics.inscribed.acrossM),
        muted: true,
      },
    );
  }

  // Markers in table order, nudged off each other.
  const objectById = new Map(objects.map((object) => [object.id, object]));
  const openingById = new Map(roomOpenings(floor, room).map((opening) => [opening.id, opening]));
  const markers: Array<RoomLayout["markers"][number]> = [];
  for (const item of room.items) {
    const shape = ITEM_GROUPS.find((g) => g.group === item.group)?.shape ?? "circle";
    let at: Point | undefined;
    if (item.kind === "object") {
      const object = objectById.get(item.id);
      at = object === undefined ? undefined : view.page(object.center);
    } else {
      const opening = openingById.get(item.id);
      at = opening === undefined ? undefined : view.page(scale(add(opening.from, opening.to), 0.5));
    }
    if (at === undefined) {
      continue;
    }
    const free = (p: Point) => markers.every((m) => Math.hypot(m.x - p.x, m.y - p.y) >= 12.5);
    let placed = at;
    if (!free(at)) {
      for (const [dx, dy] of [
        [0, -13],
        [13, 0],
        [0, 13],
        [-13, 0],
      ] as const) {
        const candidate = { x: at.x + dx, y: at.y + dy };
        if (free(candidate)) {
          placed = candidate;
          break;
        }
      }
    }
    markers.push({ shape, x: placed.x, y: placed.y, label: String(item.number) });
  }
  return { view, dims, markers };
}

/** Draws the room drawing of a layout. */
export function drawRoom(
  canvas: Canvas,
  floor: ModelFloor,
  room: ModelRoom,
  layout: RoomLayout,
): void {
  const geometry = floor.metrics?.geometry;
  if (geometry === undefined) {
    return;
  }
  const { view } = layout;
  const minWallM = view.m(MIN_WALL);
  const walls = geometry.walls.filter((wall) => distance(wall.start, wall.end) > 0);
  drawObjects(canvas, view, roomObjects(floor, room), walls);
  drawWalls(canvas, view, roomBands(floor, room, minWallM));
  drawOpenings(
    canvas,
    view,
    roomOpenings(floor, room).map((opening) => ({
      opening,
      ...openingBand(geometry, opening, minWallM),
    })),
  );
  // Bounding box (dash 3 / 2) and inscribed rectangle (dots 0.6 / 2, round caps).
  inPlan(canvas, view, (doc) => {
    const outline = (corners: readonly Point[], dash: [number, number], round: boolean) => {
      const [first, ...rest] = corners;
      if (first === undefined) {
        return;
      }
      doc.save();
      doc.moveTo(first.x, first.y);
      rest.forEach((p) => doc.lineTo(p.x, p.y));
      doc.closePath();
      doc.lineWidth(view.m(0.75)).dash(view.m(dash[0]), { space: view.m(dash[1]) });
      doc.lineCap(round ? "round" : "butt").lineJoin(round ? "round" : "miter");
      doc.strokeColor(COLOR.muted).stroke();
      doc.restore();
    };
    outline(room.metrics.boundingBox.corners, [3, 2], false);
    if (!room.rectangular) {
      outline(room.metrics.inscribed.corners, [0.6, 2], true);
    }
  });
  for (const marker of layout.markers) {
    drawMarker(canvas, marker.shape, marker.x, marker.y, 12, marker.label);
  }
  drawDimensions(canvas, layout.dims);
}
