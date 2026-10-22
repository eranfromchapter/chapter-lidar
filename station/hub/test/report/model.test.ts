// The report model (spec 11.1 model.test.ts): unlabeled rooms, fills, totals, order, skipped
// rooms, rule results, cover sentences, compass states and the north arrow, rectangular rooms,
// models the measurement engine refuses.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { validateCaptureModel, type Capture, type CaptureModel } from "@chapter/capture-contract";
import { coverSentence, outcomeInPlainWords, renderSpatialReport } from "../../src/report/index.js";
import {
  buildModel,
  fillClass,
  floorNorthSymbol,
  isUnlabeled,
  reportFloors,
  skippedEntries,
  typeFromLabel,
} from "../../src/report/model.js";
import { input424, pageTexts, syntheticInput, verdict424, type SyntheticRoom } from "./support.js";

type Room = CaptureModel["rooms"][number];
const room = (label: string, extra: Partial<Room> = {}): Room => ({
  id: "r",
  label,
  polygon: [
    [0, 0, 0],
    [1, 0, 0],
    [1, 0, -1],
  ],
  heightM: 2.5,
  ...extra,
});

describe("unlabeled rooms", () => {
  it("is a RoomPlan number with no type the operator chose", () => {
    assert.equal(isUnlabeled(room("Room 3")), true);
    assert.equal(isUnlabeled(room("Room 3", { type: "other", typeSource: "inferred" })), true);
    assert.equal(isUnlabeled(room("Room 3", { type: "bedroom", typeSource: "operator" })), false);
    assert.equal(isUnlabeled(room("Room 3", { type: "other", typeSource: "operator" })), false);
    assert.equal(isUnlabeled(room("Room 3", { type: "kitchen", typeSource: "inferred" })), false);
    assert.equal(isUnlabeled(room("Room Mexico")), false);
    assert.equal(isUnlabeled(room("Room 3b")), false);
  });

  it("counts unlabeled rooms per floor for the stored figures", async () => {
    const model = buildModel(await input424("limited"));
    assert.deepEqual(
      reportFloors(model).map((floor) => [floor.roomsScanned, floor.roomsUnlabeled]),
      [[12, 5]],
    );
  });
});

describe("fills (plan-sheet 3.4.1)", () => {
  it("reads outdoor and wet words first, then habitable words", () => {
    assert.equal(fillClass("Balcony", undefined, [], "floor"), "outdoor");
    assert.equal(fillClass("Kitchen", undefined, [], "floor"), "wet");
    assert.equal(fillClass("Primary Shower", undefined, [], "floor"), "wet");
    assert.equal(fillClass("Powder room WC", undefined, [], "floor"), "wet");
    assert.equal(fillClass("Guest toilet", undefined, [], "floor"), "wet");
    assert.equal(fillClass("Study", undefined, [], "floor"), "habitable");
    assert.equal(fillClass("Bedroom 2", undefined, [], "floor"), "habitable");
    assert.equal(fillClass("Hall", undefined, [], "floor"), "other");
  });

  it("uses the room type when the label says nothing", () => {
    assert.equal(fillClass("Den", "bedroom", [], "floor"), "habitable");
    assert.equal(fillClass("Room 2", "laundry", [], "floor"), "wet");
    assert.equal(fillClass("Room 2", "closet", ["toilet"], "floor"), "other");
  });

  it("uses objects only for untyped rooms", () => {
    assert.equal(fillClass("Room 2", undefined, ["toilet"], "floor"), "wet");
    assert.equal(fillClass("Room 2", "other", ["stove"], "floor"), "wet");
    assert.equal(fillClass("Room 2", undefined, ["bed"], "floor"), "habitable");
    assert.equal(fillClass("Room 2", undefined, ["chair"], "floor"), "other");
  });

  it("makes every room of an exterior capture outdoor", () => {
    assert.equal(fillClass("Kitchen", "kitchen", ["sink"], "exterior"), "outdoor");
  });

  it("types a 1.0.0 room from its label", () => {
    assert.equal(typeFromLabel("Primary Bedroom"), "bedroom");
    assert.equal(typeFromLabel("Shower room"), "bathroom");
    assert.equal(typeFromLabel("Entry foyer"), "hallway");
    assert.equal(typeFromLabel("Room 4"), undefined);
  });
});

describe("totals", () => {
  it("omits bedrooms and bathrooms for a 1.0.0 model (no room types)", async () => {
    const model = buildModel(await input424("limited"));
    assert.equal(model.totals.bedrooms, undefined);
    assert.equal(model.totals.bathrooms, undefined);
    assert.equal(model.totals.roomsScanned, 12);
    assert.equal(model.totals.items, 29);
    assert.equal(model.totals.volumeIsApproximate, true);
  });

  it("counts bedrooms and bathrooms when rooms are typed", () => {
    const rooms: SyntheticRoom[] = [
      { label: "Primary", w: 4, d: 3.5, type: "bedroom", typeSource: "operator" },
      { label: "Guest", w: 3, d: 3, type: "bedroom", typeSource: "roomplan_section" },
      { label: "Bath", w: 2, d: 2, type: "bathroom", typeSource: "inferred" },
      { label: "Hall", w: 1.2, d: 4, type: "hallway", typeSource: "roomplan_section" },
    ];
    const model = buildModel(syntheticInput([{ label: "Floor 1", rooms }]));
    assert.equal(model.totals.bedrooms, 2);
    assert.equal(model.totals.bathrooms, 1);
  });

  it("stores the floor area rounded to 0.1 sq ft once, not as a sum of rounded rooms", async () => {
    const model = buildModel(await input424("limited"));
    const [floor] = reportFloors(model);
    // The twelve printed room areas add up to 796.3; the unrounded sum is 796.249 sq ft.
    assert.equal(floor?.floorAreaSqFt, 796.2);
  });
});

describe("order and numbers", () => {
  it("sorts rooms by floor area, largest first, ties in model order", () => {
    const rooms: SyntheticRoom[] = [
      { label: "Small", w: 2, d: 2 },
      { label: "Tie A", w: 3, d: 3 },
      { label: "Large", w: 5, d: 4 },
      { label: "Tie B", w: 3, d: 3 },
    ];
    const model = buildModel(syntheticInput([{ label: "Floor 1", rooms }]));
    assert.deepEqual(
      model.rooms.map((r) => [r.number, r.name]),
      [
        [1, "Large"],
        [2, "Tie A"],
        [3, "Tie B"],
        [4, "Small"],
      ],
    );
  });

  it("numbers rooms across floors in floor order", () => {
    const model = buildModel(
      syntheticInput([
        { label: "Floor 1", rooms: [{ label: "A", w: 2, d: 2 }] },
        {
          label: "Floor 2",
          rooms: [
            { label: "B", w: 3, d: 3 },
            { label: "C", w: 4, d: 4 },
          ],
        },
      ]),
    );
    assert.deepEqual(
      model.rooms.map((r) => [r.floorIndex, r.number, r.name]),
      [
        [0, 1, "A"],
        [1, 2, "C"],
        [1, 3, "B"],
      ],
    );
  });

  it("matches photos to rooms by normalized label and keeps the rest per floor", async () => {
    const model = buildModel(await input424("limited"));
    const living = model.rooms.find((r) => r.name === "Living Room");
    assert.equal(living?.photos.length, 7);
    assert.equal(
      model.rooms.every((r) => r.photos.length >= 1),
      true,
    );
    assert.equal(model.floors[0]?.otherPhotos.length, 0);
  });
});

describe("rooms not scanned", () => {
  const capture = (label: string): Partial<Capture> => ({
    omittedRooms: [{ name: `${label} closet`, reason: "locked" }, { name: `${label} attic` }],
    inaccessibleRooms: [
      { name: `${label} storage` },
      { name: `${label} boiler`, reason: "no key" },
    ],
  });
  const model = buildModel(
    syntheticInput([
      { label: "Floor 1", rooms: [{ label: "A", w: 2, d: 2 }], capture: capture("Upper") },
      { label: "Floor 2", rooms: [{ label: "B", w: 2, d: 2 }], capture: capture("Lower") },
    ]),
  );

  it("writes the four kinds of entries", () => {
    assert.deepEqual(skippedEntries(model.floors[0]?.skipped ?? [], false), [
      "Upper closet (locked)",
      "Upper attic (not scanned)",
      "Upper storage (could not enter)",
      "Upper boiler (could not enter: no key)",
    ]);
  });

  it("names the floor on a multi-floor cover", () => {
    assert.deepEqual(skippedEntries(model.floors[1]?.skipped ?? [], true), [
      "Lower closet (Floor 2, locked)",
      "Lower attic (Floor 2, not scanned)",
      "Lower storage (Floor 2, could not enter)",
      "Lower boiler (Floor 2, could not enter: no key)",
    ]);
  });
});

describe("rule results and the cover sentence", () => {
  it("takes every rule result from the shared check rows", async () => {
    const counts = await Promise.all(
      (["ready", "limited", "blocked"] as const).map(async (outcome) => {
        const model = buildModel(await input424(outcome));
        assert.equal(model.checkRows.length, 13);
        return model.counts;
      }),
    );
    assert.deepEqual(counts, [
      { blockers: 0, limitations: 0, passed: 12, notApplicable: 1 },
      { blockers: 0, limitations: 1, passed: 11, notApplicable: 1 },
      { blockers: 2, limitations: 1, passed: 9, notApplicable: 1 },
    ]);
  });

  it("writes the sentence of each outcome", () => {
    assert.equal(
      coverSentence(verdict424("ready"), 5),
      "Ready for preliminary existing-condition plans. All station checks passed (page 5).",
    );
    assert.equal(
      coverSentence(verdict424("limited"), 5),
      "Usable for preliminary existing-condition plans, with the limitations named on page 5.",
    );
    const blocked = verdict424("blocked");
    assert.equal(
      coverSentence(blocked, 5, 1),
      "Not usable yet. One blocker is named on page 5; the package must be re-sealed.",
    );
    assert.equal(
      coverSentence(blocked, 5, 2),
      "Not usable yet. Two blockers are named on page 5; the package must be re-sealed.",
    );
    assert.equal(
      coverSentence(blocked, 7, 12),
      "Not usable yet. 12 blockers are named on page 7; the package must be re-sealed.",
    );
    assert.equal(outcomeInPlainWords(blocked, 5), coverSentence(blocked, 5, 2));
  });
});

describe("compass", () => {
  const floorWith = (capture: Partial<Capture>, turnDegrees?: number) =>
    buildModel(
      syntheticInput([
        {
          label: "Floor 1",
          rooms: [{ label: "Living", w: 5, d: 4 }],
          capture,
          ...(turnDegrees === undefined ? {} : { turnDegrees }),
        },
      ]),
    ).floors[0];
  const reading = (accuracy: number, source: "true" | "magnetic" = "true"): Partial<Capture> => ({
    heading: 90,
    headingAccuracy: accuracy,
    headingSource: source,
    headingRecordedAt: "2026-10-17T14:05:00Z",
  });

  it("is verified to ±10°, approximate to ±30°, not verified beyond", () => {
    const kinds = [0, 10, 11, 30, 31].map((accuracy) => floorWith(reading(accuracy))?.compass.kind);
    assert.deepEqual(kinds, ["verified", "verified", "approximate", "approximate", "not_verified"]);
    assert.equal(floorWith(reading(5, "magnetic"))?.compass.kind, "approximate");
    assert.equal(floorWith(reading(31, "magnetic"))?.compass.kind, "not_verified");
  });

  it("captions a floor without a usable reading", () => {
    const caption = (capture: Partial<Capture>) => {
      const floor = floorWith(capture);
      const symbol = floor === undefined ? undefined : floorNorthSymbol(floor);
      return symbol?.kind === "box" ? `${symbol.box} / ${symbol.caption}` : symbol?.kind;
    };
    assert.equal(caption({}), "Orientation: not verified / No compass reading");
    assert.equal(
      caption({ headingIssue: "rejected" }),
      "Orientation: not verified / Reading rejected",
    );
    assert.equal(
      caption({ headingIssue: "not_calibrated" }),
      "Orientation: not verified / Compass not calibrated",
    );
    assert.equal(
      caption({ headingIssue: "unavailable" }),
      "Orientation: not verified / Compass unavailable",
    );
    assert.equal(caption(reading(31)), "Orientation: not verified / Compass accuracy ±31°");
    // A reading taken long after the scan is rejected.
    assert.equal(
      caption({ ...reading(5), headingRecordedAt: "2026-10-18T14:05:00Z" }),
      "Orientation: not verified / Reading rejected",
    );
  });

  it("captions a floor without a scan model", () => {
    const model = buildModel(
      syntheticInput([{ label: "Floor 1", rooms: [], capture: reading(5), status: "absent" }]),
    );
    const symbol = floorNorthSymbol(model.floors[0] as NonNullable<(typeof model.floors)[0]>);
    assert.deepEqual(symbol, {
      kind: "box",
      box: "Orientation: not verified",
      caption: "No scan model",
    });
  });

  it("turns the arrow by the drawing's rotation (A = H - a)", () => {
    const square = floorWith(reading(5));
    assert.equal(square?.rotationDegrees, 0);
    const straight = square === undefined ? undefined : floorNorthSymbol(square);
    assert.equal(straight?.kind === "arrow" ? straight.angleCcw : undefined, 90);
    assert.deepEqual(straight?.kind === "arrow" ? straight.lines : undefined, [
      "True north · compass",
      "±5° · 90°",
    ]);

    // The plan turned 12° counter-clockwise: the drawing turns it back 12° clockwise.
    const turned = floorWith({ ...reading(5), heading: 0 }, 12);
    assert.ok(turned !== undefined);
    assert.ok(
      Math.abs((turned?.rotationDegrees ?? 0) - 12) < 1e-6,
      String(turned?.rotationDegrees),
    );
    const symbol = floorNorthSymbol(turned);
    assert.equal(symbol.kind, "arrow");
    if (symbol.kind === "arrow") {
      assert.ok(Math.abs(symbol.angleCcw - 348) < 1e-6, String(symbol.angleCcw));
      assert.equal(symbol.lines[1], "±5° · 348°");
    }
  });

  it("draws an approximate arrow with its source", () => {
    const floor = floorWith(reading(20, "magnetic"));
    const symbol = floor === undefined ? undefined : floorNorthSymbol(floor);
    assert.deepEqual(symbol?.kind === "arrow" ? [symbol.approximate, symbol.lines] : undefined, [
      true,
      ["Approx. north · compass", "±20° · magnetic"],
    ]);
  });
});

describe("rectangular rooms", () => {
  it("is rectangular when the bounding box equals the inscribed rectangle", () => {
    const rooms: SyntheticRoom[] = [
      { label: "Box", w: 4, d: 3 },
      {
        label: "L-shaped",
        w: 0,
        d: 0,
        outline: [
          [0, 0],
          [5, 0],
          [5, 2],
          [2, 2],
          [2, 4],
          [0, 4],
        ],
      },
    ];
    const model = buildModel(syntheticInput([{ label: "Floor 1", rooms }]));
    const byName = new Map(model.rooms.map((r) => [r.name, r]));
    assert.equal(byName.get("Box")?.rectangular, true);
    assert.equal(byName.get("L-shaped")?.rectangular, false);
    assert.equal(byName.get("Box")?.words.bbox, `13' 1.5" × 9' 10.1"`);
  });
});

describe("models the measurement engine refuses", () => {
  // A door on a wall id that names no wall passes the contract's schema but not the engine
  // (PlanGeometryError, as PlanExport's unknownWall). Only that floor is "unreadable".
  const input = () => {
    const base = syntheticInput([
      { label: "Floor 1", rooms: [{ label: "Living Room", w: 5, d: 4, doors: 1 }] },
      { label: "Floor 2", rooms: [{ label: "Bedroom", w: 4, d: 3, doors: 1 }] },
    ]);
    const floors = (base.floors ?? []).map((floor, i) => {
      if (i !== 1 || floor.model.status !== "ok") {
        return floor;
      }
      const model = structuredClone(floor.model.model);
      const door = model.doors[0];
      assert.ok(door);
      door.wallId = "wall-that-is-not-there";
      assert.equal(validateCaptureModel(model).ok, true);
      return { ...floor, model: { status: "ok" as const, model } };
    });
    return { ...base, floors };
  };

  it("marks that floor unreadable and keeps the others", () => {
    const model = buildModel(input());
    assert.deepEqual(
      model.floors.map((floor) => [floor.label, floor.source.status, floor.rooms.length]),
      [
        ["Floor 1", "ok", 1],
        ["Floor 2", "unreadable", 0],
      ],
    );
    assert.equal(model.floors[1]?.metrics, undefined);
    assert.equal(model.totals.roomsScanned, 1);
    assert.deepEqual(
      reportFloors(model).map((floor) => floor.areaKey),
      ["floor-1"],
    );
  });

  it("still renders the report, saying that floor's plan could not be read", async () => {
    const rendered = await renderSpatialReport(input());
    const text = (await pageTexts(rendered.bytes)).join("\n");
    assert.ok(text.includes("Plan not available: the scan model of Floor 2 could not be read."));
    assert.deepEqual(
      rendered.floors.map((floor) => floor.areaKey),
      ["floor-1"],
    );
  });

  it("does not hide other errors", () => {
    const broken = input();
    const floor = broken.floors[0];
    assert.ok(floor !== undefined && floor.model.status === "ok");
    // Not geometry the engine refuses: a model without its room list is a programming error.
    const model = { ...floor.model.model, rooms: undefined } as unknown as CaptureModel;
    assert.throws(() =>
      buildModel({
        ...broken,
        floors: [{ ...floor, model: { status: "ok", model } }],
      }),
    );
  });
});
