// The room summary of fixture packages: quantities agree with planMetrics, room types follow
// scan > name > fixtures > unknown, unmeasured floors are kept, the JSON is stable, and the brief
// section says what the summary says.

import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import type { CaptureModel } from "@chapter/capture-contract";
import type { ReportFloorSource } from "../../src/report/input.js";
import { planMetrics } from "../../src/report/metrics/room-metrics.js";
import { squareFeet } from "../../src/report/metrics/units.js";
import {
  ROOM_SUMMARY_SCHEMA,
  ROOM_SUMMARY_VERSION,
  buildRoomSummary,
  roomSummaryFileName,
  roomSummaryJson,
  type RoomSummary,
} from "../../src/summary/room-summary.js";
import { spatialObservations } from "../../src/summary/spatial-observations.js";
import { GENERATED } from "../report/support.js";

/** The floors of a generated fixture package, in area order. */
function floorsOf(fixture: string): ReportFloorSource[] {
  const exportsDir = join(GENERATED, fixture, "package", "Original Exports");
  return readdirSync(exportsDir)
    .sort()
    .flatMap((areaKey) =>
      readdirSync(join(exportsDir, areaKey)).map((captureId) => {
        const file = join(exportsDir, areaKey, captureId, "capture-model.json");
        return {
          captureId,
          areaKey,
          model: existsSync(file)
            ? {
                status: "ok" as const,
                model: JSON.parse(readFileSync(file, "utf8")) as CaptureModel,
              }
            : { status: "absent" as const },
        };
      }),
    );
}

function summaryOf(floors: readonly ReportFloorSource[]): RoomSummary {
  return buildRoomSummary({ packageId: "pkg-1", dealId: "deal-1", verdictId: "verdict-1", floors });
}

function modelOf(floor: ReportFloorSource | undefined): CaptureModel {
  assert.ok(floor !== undefined && floor.model.status === "ok");
  return floor.model.model;
}

const tenth = (value: number): number => Math.round(value * 10) / 10;

describe("room summary of sample-424", () => {
  const floors = floorsOf("sample-424");
  const summary = summaryOf(floors);
  const rooms = summary.floors.flatMap((floor) => floor.rooms);

  it("names the package and the format", () => {
    assert.equal(summary.schema, ROOM_SUMMARY_SCHEMA);
    assert.equal(summary.version, ROOM_SUMMARY_VERSION);
    assert.deepEqual(
      [summary.packageId, summary.dealId, summary.verdictId],
      ["pkg-1", "deal-1", "verdict-1"],
    );
    assert.deepEqual(summary.units, { length: "ft", area: "sq ft" });
  });

  it("measures every room the report measures, with the same floor area", () => {
    const metrics = floors.flatMap((floor) => planMetrics(modelOf(floor)).rooms);
    assert.equal(summary.totals.rooms, 12);
    assert.equal(rooms.length, metrics.length);
    const areaM2 = metrics.reduce((sum, room) => sum + room.floorAreaM2, 0);
    assert.equal(summary.totals.floorAreaSqFt, tenth(squareFeet(areaM2)));
    for (const [index, room] of rooms.entries()) {
      assert.equal(room.floorAreaSqFt, tenth(squareFeet(metrics[index]?.floorAreaM2 ?? NaN)));
    }
  });

  it("keeps each room's quantities consistent", () => {
    for (const room of rooms) {
      assert.ok(room.paintableWallAreaSqFt <= room.wallAreaSqFt, room.name);
      assert.ok(room.baseboardFt <= room.perimeterFt, room.name);
      assert.equal(room.ceilingAreaSqFt, room.floorAreaSqFt, room.name);
      assert.ok(room.ceilingHeightFt > 6 && room.ceilingHeightFt < 12, room.name);
    }
  });

  it("counts fixtures and furniture apart", () => {
    assert.deepEqual(summary.totals.fixtures, {
      bathtub: 2,
      sink: 1,
      storage: 3,
      stove: 1,
      toilet: 1,
    });
    const furniture = new Map<string, number>();
    for (const room of rooms) {
      for (const [category, count] of Object.entries(room.furniture)) {
        furniture.set(category, (furniture.get(category) ?? 0) + count);
      }
    }
    assert.deepEqual(Object.fromEntries(furniture), { bed: 2, sofa: 2, table: 2 });
  });

  it("types rooms from their names, and says when it cannot", () => {
    const byName = new Map(rooms.map((room) => [room.name, room]));
    assert.deepEqual(
      ["Bedroom 1", "Closet", "Living Room", "Bathroom 2", "Kitchen"].map((name) => {
        const room = byName.get(name);
        return [room?.type, room?.typeSource];
      }),
      [
        ["bedroom", "name"],
        ["closet", "name"],
        ["living_room", "name"],
        ["bathroom", "name"],
        ["kitchen", "name"],
      ],
    );
    const unknown = byName.get("Room 2");
    assert.deepEqual([unknown?.type, unknown?.typeSource], ["other", "unknown"]);
    assert.ok(unknown?.uncertain.includes("room type unknown"));
    assert.deepEqual(byName.get("Kitchen")?.uncertain, []);
  });

  it("flags an approximate ceiling", () => {
    const room = rooms.find((candidate) => candidate.ceilingHeightApproximate);
    assert.ok(room !== undefined);
    assert.match(room.uncertain.join("; "), /ceiling height is approximate/);
  });

  it("totals rooms by type", () => {
    const byType = summary.totals.byRoomType;
    assert.deepEqual(byType["bathroom"]?.rooms, 2);
    assert.deepEqual(byType["bedroom"]?.rooms, 2);
    assert.equal(
      Object.values(byType).reduce((sum, entry) => sum + entry.rooms, 0),
      summary.totals.rooms,
    );
  });
});

describe("room types", () => {
  const floor = floorsOf("sample-424")[0];
  const base = modelOf(floor);

  function withRoom(index: number, change: (room: Record<string, unknown>) => void): RoomSummary {
    const model = structuredClone(base) as unknown as { rooms: Record<string, unknown>[] };
    const room = model.rooms[index];
    assert.ok(room !== undefined);
    change(room);
    return summaryOf([
      { captureId: "c", areaKey: "floor-1", model: { status: "ok", model: model as never } },
    ]);
  }

  const bathroom = base.rooms.findIndex((room) => room.label === "Bathroom 2");

  it("takes the scan's type over the name", () => {
    const summary = withRoom(bathroom, (room) => {
      room["type"] = "laundry";
    });
    const room = summary.floors[0]?.rooms[bathroom];
    assert.deepEqual([room?.type, room?.typeSource], ["laundry", "scan"]);
  });

  it("falls back to the fixtures when the name says nothing, and flags it", () => {
    const summary = withRoom(bathroom, (room) => {
      room["label"] = "Room 9";
    });
    const room = summary.floors[0]?.rooms[bathroom];
    assert.deepEqual([room?.type, room?.typeSource], ["bathroom", "fixtures"]);
    assert.ok(room?.uncertain.includes("room type inferred from its fixtures"));
  });
});

describe("floors", () => {
  it("keeps floors whose model is absent or unreadable, with nothing measured", () => {
    const summary = summaryOf([
      { captureId: "a", areaKey: "floor-1", model: { status: "absent" } },
      { captureId: "b", areaKey: "floor-2", model: { status: "unreadable" } },
    ]);
    assert.deepEqual(
      summary.floors.map((floor) => [floor.status, floor.rooms.length, floor.totals.rooms]),
      [
        ["absent", 0, 0],
        ["unreadable", 0, 0],
      ],
    );
    assert.equal(summary.totals.floorAreaSqFt, 0);
    assert.deepEqual(summary.totals.fixtures, {});
  });

  it("totals a two-floor house over both floors", () => {
    const summary = summaryOf(floorsOf("two-floor-house"));
    assert.equal(summary.floors.length, 2);
    assert.equal(
      summary.totals.rooms,
      summary.floors.reduce((sum, floor) => sum + floor.totals.rooms, 0),
    );
    const floorSum = summary.floors.reduce((sum, floor) => sum + floor.totals.floorAreaSqFt, 0);
    assert.ok(Math.abs(summary.totals.floorAreaSqFt - floorSum) <= 0.1 * summary.floors.length);
  });
});

describe("published file", () => {
  it("is stable two-space JSON with a final newline", () => {
    const floors = floorsOf("sample-424");
    const first = roomSummaryJson(summaryOf(floors));
    assert.equal(first, roomSummaryJson(summaryOf(floors)));
    assert.ok(first.endsWith("}\n"));
    assert.deepEqual(JSON.parse(first), summaryOf(floors));
  });

  it("is named after the verdict", () => {
    assert.equal(roomSummaryFileName("abc"), "room-summary-abc.json");
    assert.equal(roomSummaryFileName(), "room-summary.json");
  });
});

describe("spatial observations", () => {
  const summary = summaryOf(floorsOf("sample-424"));
  const text = spatialObservations(summary);

  it("lists the rooms with their sizes and fixtures", () => {
    assert.ok(text.startsWith("Spatial Observations (from Chapter Capture)\n"));
    assert.match(text, /^12 rooms, 796\.2 sq ft over 1 floor\.$/m);
    assert.match(
      text,
      /^- Bathroom 2: [\d.]+ sq ft, ceiling [\d.]+ ft, 1 door; bathtub, toilet\.$/m,
    );
    assert.match(text, /^- Room 2 \(other\): /m);
  });

  it("gives the estimate's quantities and what to check", () => {
    assert.match(text, /^Quantities for the estimate$/m);
    assert.match(text, /^- Fixtures: bathtub x2, sink, cabinets\/storage x3, stove, toilet$/m);
    assert.match(text, /^Check before pricing$/m);
    assert.match(text, /^- Room 4: ceiling height is approximate/m);
    assert.ok(text.endsWith("\n"));
  });

  it("says when a floor could not be measured", () => {
    const withAbsent = buildRoomSummary({
      packageId: "p",
      dealId: "d",
      floors: [
        ...floorsOf("sample-424"),
        { captureId: "x", areaKey: "floor-2", model: { status: "absent" } },
      ],
    });
    assert.match(spatialObservations(withAbsent), /^1 floor could not be measured/m);
  });
});
