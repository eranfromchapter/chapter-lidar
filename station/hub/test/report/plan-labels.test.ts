// Room labels on the plan drawings (cover and floor plan pages): each sits on a patch of its
// room's fill, inside the room's inscribed rectangle; a label whose block an object box lies
// under or across at the label point moves to the clearest spot of the room (clear floor, else
// wholly within one object, never across an edge where it can be helped), deterministically.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  LABEL_PAD,
  fitFloor,
  placeRoomLabels,
  polygonHitsRect,
  type PlacedLabel,
  type Rect,
} from "../../src/report/draw/floor.js";
import { FILL_COLOR, type PlanView } from "../../src/report/draw/plan-view.js";
import { contains, type Point } from "../../src/report/metrics/plan-geometry.js";
import { buildModel, type Model, type ModelFloor } from "../../src/report/model.js";
import { input424, syntheticInput, testCanvas } from "./support.js";

/** The floor plan page's drawing region. */
const PLAN_BOX: Rect = { x: 245, y: 118, width: 487, height: 376 };
/** The cover's drawing region (one floor). */
const COVER_BOX: Rect = { x: 36, y: 102, width: 476, height: 392 };

function labelsOf(model: Model, box: Rect, wallsOnly: boolean) {
  const floor = model.floors[0] as ModelFloor;
  const view = fitFloor(floor, { box, minWall: 2, wallsOnly }) as PlanView;
  assert.ok(view !== undefined);
  const objects = (floor.metrics?.geometry.objects ?? []).map((object) =>
    object.corners.map((p) => view.page(p)),
  );
  return { floor, view, objects, labels: placeRoomLabels(testCanvas(), floor, view) };
}

const corners = (r: Rect): Point[] => [
  { x: r.x, y: r.y },
  { x: r.x + r.width, y: r.y },
  { x: r.x + r.width, y: r.y + r.height },
  { x: r.x, y: r.y + r.height },
];

function insideInscribed(floor: ModelFloor, view: PlanView, label: PlacedLabel): boolean {
  const room = floor.rooms.find((r) => r.metrics.roomId === label.roomId);
  assert.ok(room !== undefined);
  const inscribed = room.metrics.inscribed.corners.map((p) => view.page(p));
  // The inscribed rectangle is convex: a corner within 1e-6 of it counts.
  return corners(label.box).every(
    (c) =>
      contains(inscribed, c) ||
      inscribed.some((p, i) => {
        const q = inscribed[(i + 1) % inscribed.length] as Point;
        const cross = (q.x - p.x) * (c.y - p.y) - (q.y - p.y) * (c.x - p.x);
        return Math.abs(cross) < 1e-6;
      }),
  );
}

describe("room labels on the plan drawings", () => {
  it("moves the 424 labels off the object boxes and keeps them inside their rooms", async () => {
    const model = buildModel(await input424("limited"));
    for (const [box, wallsOnly] of [
      [PLAN_BOX, true],
      [COVER_BOX, false],
    ] as const) {
      const { floor, view, objects, labels } = labelsOf(model, box, wallsOnly);
      // Every room but Room 5 (8.9 sq ft), whose name does not fit it.
      assert.deepEqual(
        floor.rooms
          .filter((r) => !labels.some((l) => l.roomId === r.metrics.roomId))
          .map((r) => r.name),
        ["Room 5"],
      );
      for (const label of labels) {
        assert.ok(insideInscribed(floor, view, label), `${label.name} leaves its room`);
        const crossed = objects.filter((object) => polygonHitsRect(object, label.box));
        assert.deepEqual(crossed, [], `${label.name} over an object box`);
        const room = floor.rooms.find((r) => r.metrics.roomId === label.roomId);
        assert.equal(label.patch, FILL_COLOR[room?.fill as keyof typeof FILL_COLOR]);
      }
      // The labels the drawings used to put across the bed, the table and the bed.
      for (const name of ["Bedroom 1", "Living Room", "Bedroom 2"]) {
        const label = labels.find((l) => l.name === name);
        assert.ok(label?.area !== undefined, `${name} keeps its area line`);
        const planRoom = floor.metrics?.geometry.rooms.find((r) => r.id === label.roomId);
        const start = view.page(planRoom?.labelPoint as Point);
        assert.ok(Math.hypot(label.x - start.x, label.box.y + label.box.height / 2 - start.y) > 1);
      }
    }
  });

  it("is deterministic", async () => {
    const model = buildModel(await input424("limited"));
    assert.deepEqual(
      labelsOf(model, COVER_BOX, false).labels,
      labelsOf(model, COVER_BOX, false).labels,
    );
  });

  it("keeps a label at the label point where nothing lies under it", () => {
    const model = buildModel(
      syntheticInput([{ label: "Floor 1", rooms: [{ label: "Living room", w: 5, d: 4 }] }]),
    );
    const { floor, view, labels } = labelsOf(model, PLAN_BOX, true);
    const [label] = labels;
    assert.ok(label !== undefined);
    const start = view.page(floor.metrics?.geometry.rooms[0]?.labelPoint as Point);
    assert.ok(Math.abs(label.x - start.x) < 1e-9);
    assert.ok(Math.abs(label.box.y + label.box.height / 2 - start.y) < 1e-9);
    assert.equal(label.box.width, Math.max(label.nameWidth, label.areaWidth) + 2 * LABEL_PAD);
  });

  it("sits wholly within an object that leaves no clear floor, not across its edge", () => {
    const model = buildModel(
      syntheticInput([
        {
          label: "Floor 1",
          rooms: [
            { label: "Den", w: 3, d: 3, objects: [{ category: "table", size: [2.8, 0.7, 2.8] }] },
            { label: "Study", w: 3.5, d: 3, objects: [{ category: "bed", size: [3.2, 0.5, 2.7] }] },
          ],
        },
      ]),
    );
    const { floor, view, objects, labels } = labelsOf(model, COVER_BOX, false);
    assert.equal(labels.length, 2);
    for (const label of labels) {
      assert.ok(insideInscribed(floor, view, label), label.name);
      const under = objects.filter((object) => polygonHitsRect(object, label.box));
      assert.equal(under.length, 1, label.name);
      assert.ok(
        corners(label.box).every((c) => contains(under[0] as Point[], c)),
        `${label.name} across an object's edge`,
      );
    }
  });
});
