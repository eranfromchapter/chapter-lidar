// The room summary: what a package's scans measured, room by room, in the quantities an estimate
// is priced from (square feet of floor, paintable wall and ceiling, baseboard length, doors,
// windows and fixtures). It is published next to the spatial report so other tools (AI Estimates,
// the PM and design briefs) can read real numbers instead of a PDF.
//
// Every number comes from planMetrics (the report's port of PlanExport's PlanMetrics), so the
// summary agrees with the plan sheet and the spatial report. Values are summed in metres and
// rounded once, at the end. Nothing here is a price: lining quantities up with the Master Pricing
// Sheet is the consumer's job.

import type { CaptureModel, RoomType } from "@chapter/capture-contract";
import type { ReportFloorSource } from "../report/input.js";
import type { ObjectCategory } from "../report/metrics/plan-geometry.js";
import {
  isApproximate,
  planMetrics,
  type CeilingReason,
  type RoomMetrics,
} from "../report/metrics/room-metrics.js";
import { METRES_PER_FOOT, squareFeet } from "../report/metrics/units.js";

export const ROOM_SUMMARY_SCHEMA = "chapter.room-summary";
export const ROOM_SUMMARY_VERSION = "1.0.0";

/** Built-in items an estimate prices (plumbing, appliances, cabinetry, stairs, fireplaces). */
export const FIXTURE_CATEGORIES: readonly ObjectCategory[] = [
  "bathtub",
  "dishwasher",
  "fireplace",
  "oven",
  "refrigerator",
  "sink",
  "stairs",
  "storage",
  "stove",
  "toilet",
];

/** Where a room's type came from, most to least certain. */
export type RoomTypeSource = "scan" | "name" | "fixtures" | "unknown";

/** Quantities summed over rooms (a floor, or the whole package). */
export interface SummaryTotals {
  readonly rooms: number;
  readonly floorAreaSqFt: number;
  /** Walls net of doors, windows and passages. */
  readonly paintableWallAreaSqFt: number;
  /** Flat ceilings: equal to the floor area. */
  readonly ceilingAreaSqFt: number;
  readonly baseboardFt: number;
  readonly doors: number;
  readonly windows: number;
  /** Fixture category to count, categories in alphabetical order. */
  readonly fixtures: Readonly<Record<string, number>>;
  /** Room type to its room count and floor area, types in alphabetical order. */
  readonly byRoomType: Readonly<Record<string, { rooms: number; floorAreaSqFt: number }>>;
}

export interface RoomSummaryRoom {
  readonly roomId: string;
  readonly name: string;
  readonly type: RoomType;
  readonly typeSource: RoomTypeSource;
  readonly floorAreaSqFt: number;
  readonly ceilingHeightFt: number;
  readonly ceilingHeightApproximate: boolean;
  /** Walls including openings. */
  readonly wallAreaSqFt: number;
  /** Walls net of doors, windows and passages: the painting quantity. */
  readonly paintableWallAreaSqFt: number;
  readonly ceilingAreaSqFt: number;
  readonly perimeterFt: number;
  /** Walled length less the widths of doors and passages (windows do not interrupt it). */
  readonly baseboardFt: number;
  readonly doors: number;
  readonly windows: number;
  readonly passages: number;
  readonly fixtures: Readonly<Record<string, number>>;
  readonly furniture: Readonly<Record<string, number>>;
  /** Plain-language reasons to check a number before pricing from it. Empty: nothing to check. */
  readonly uncertain: readonly string[];
}

export interface RoomSummaryFloor {
  readonly captureId: string;
  readonly areaKey: string;
  /** The capture's own label, when the model has one. */
  readonly name?: string;
  /** "absent" or "unreadable": the floor's capture model could not be measured. */
  readonly status: "ok" | "absent" | "unreadable";
  readonly totals: SummaryTotals;
  readonly rooms: readonly RoomSummaryRoom[];
}

export interface RoomSummary {
  readonly schema: typeof ROOM_SUMMARY_SCHEMA;
  readonly version: typeof ROOM_SUMMARY_VERSION;
  readonly packageId: string;
  readonly dealId: string;
  readonly verdictId?: string;
  readonly sealedAt?: string;
  readonly units: { readonly length: "ft"; readonly area: "sq ft" };
  readonly totals: SummaryTotals;
  readonly floors: readonly RoomSummaryFloor[];
  readonly notes: readonly string[];
}

export interface RoomSummaryInput {
  readonly packageId: string;
  readonly dealId: string;
  readonly verdictId?: string;
  readonly sealedAt?: string;
  readonly floors: readonly ReportFloorSource[];
}

/** One room's quantities before rounding, in metres. */
interface RoomQuantities {
  readonly floorAreaM2: number;
  readonly paintableWallAreaM2: number;
  readonly baseboardM: number;
  readonly doors: number;
  readonly windows: number;
  readonly type: RoomType;
  readonly fixtures: ReadonlyMap<string, number>;
}

const NOTES = [
  "Lengths in feet and areas in square feet, rounded to 0.1 after summing.",
  "Paintable wall area is walls less doors, windows and passages; ceiling area assumes flat ceilings.",
  "Baseboard is the walled length less door and passage widths.",
  "typeSource says where a room type came from: scan, the room's name, its fixtures, or unknown.",
  "Quantities are measurements, not prices.",
];

/** The room summary of a package's floors. */
export function buildRoomSummary(input: RoomSummaryInput): RoomSummary {
  const floors: RoomSummaryFloor[] = [];
  const all: RoomQuantities[] = [];
  for (const floor of input.floors) {
    if (floor.model.status !== "ok") {
      floors.push({
        captureId: floor.captureId,
        areaKey: floor.areaKey,
        status: floor.model.status,
        totals: totalsOf([]),
        rooms: [],
      });
      continue;
    }
    const model = floor.model.model;
    const quantities: RoomQuantities[] = [];
    const rooms = planMetrics(model).rooms.map((room) => {
      const [summary, raw] = summarizeRoom(room);
      quantities.push(raw);
      return summary;
    });
    all.push(...quantities);
    floors.push({
      captureId: floor.captureId,
      areaKey: floor.areaKey,
      ...labelOf(model),
      status: "ok",
      totals: totalsOf(quantities),
      rooms,
    });
  }
  return {
    schema: ROOM_SUMMARY_SCHEMA,
    version: ROOM_SUMMARY_VERSION,
    packageId: input.packageId,
    dealId: input.dealId,
    ...(input.verdictId === undefined ? {} : { verdictId: input.verdictId }),
    ...(input.sealedAt === undefined ? {} : { sealedAt: input.sealedAt }),
    units: { length: "ft", area: "sq ft" },
    totals: totalsOf(all),
    floors,
    notes: NOTES,
  };
}

/** The summary as published: two-space JSON with a final newline, keys in a fixed order. */
export function roomSummaryJson(summary: RoomSummary): string {
  return `${JSON.stringify(summary, null, 2)}\n`;
}

/** `room-summary-{verdictId}.json`, or `room-summary.json` without a verdict. */
export function roomSummaryFileName(verdictId?: string): string {
  return verdictId === undefined ? "room-summary.json" : `room-summary-${verdictId}.json`;
}

function labelOf(model: CaptureModel): { name?: string } {
  const label = (model as { label?: unknown }).label;
  return typeof label === "string" && label.trim() !== "" ? { name: label.trim() } : {};
}

function summarizeRoom(room: RoomMetrics): [RoomSummaryRoom, RoomQuantities] {
  const doors = room.openings.filter((opening) => opening.type === "door");
  const passages = room.openings.filter((opening) => opening.type === "opening");
  const windows = room.openings.filter((opening) => opening.type === "window");
  const interrupting = [...doors, ...passages].reduce((sum, opening) => sum + opening.widthM, 0);
  const baseboardM = Math.max(0, room.walledLengthM - interrupting);

  const fixtures = new Map<string, number>();
  const furniture = new Map<string, number>();
  let lowConfidence = 0;
  for (const object of room.objects) {
    const target = FIXTURE_CATEGORIES.includes(object.category) ? fixtures : furniture;
    target.set(object.category, (target.get(object.category) ?? 0) + 1);
    if (target === fixtures && object.confidence === "low") {
      lowConfidence += 1;
    }
  }

  const [type, typeSource] = roomTypeOf(room, fixtures, furniture);
  const uncertain: string[] = [];
  if (isApproximate(room.ceiling)) {
    const reasons = room.ceiling.approximateReasons.map((reason) => CEILING_REASONS[reason]);
    uncertain.push(`ceiling height is approximate (${reasons.join(", ")})`);
  }
  // A type read from the room's name (RoomPlan's section or the PM's own name) is not flagged.
  if (typeSource === "fixtures") {
    uncertain.push("room type inferred from its fixtures");
  } else if (typeSource === "unknown") {
    uncertain.push("room type unknown");
  }
  if (lowConfidence > 0) {
    uncertain.push(
      `${lowConfidence} fixture${lowConfidence === 1 ? "" : "s"} detected with low confidence`,
    );
  }

  const summary: RoomSummaryRoom = {
    roomId: room.roomId,
    name: room.label,
    type,
    typeSource,
    floorAreaSqFt: sqFt(room.floorAreaM2),
    ceilingHeightFt: ft(room.ceiling.heightM),
    ceilingHeightApproximate: isApproximate(room.ceiling),
    wallAreaSqFt: sqFt(room.wallAreaIncludingOpeningsM2),
    paintableWallAreaSqFt: sqFt(room.wallAreaExcludingOpeningsM2),
    ceilingAreaSqFt: sqFt(room.floorAreaM2),
    perimeterFt: ft(room.perimeterM),
    baseboardFt: ft(baseboardM),
    doors: doors.length,
    windows: windows.length,
    passages: passages.length,
    fixtures: sortedRecord(fixtures),
    furniture: sortedRecord(furniture),
    uncertain,
  };
  const raw: RoomQuantities = {
    floorAreaM2: room.floorAreaM2,
    paintableWallAreaM2: room.wallAreaExcludingOpeningsM2,
    baseboardM,
    doors: doors.length,
    windows: windows.length,
    type,
    fixtures,
  };
  return [summary, raw];
}

/** Why a ceiling height is approximate, in words. */
const CEILING_REASONS: Readonly<Record<CeilingReason, string>> = {
  wallHeightsDiffer: "wall heights differ",
  fewWalls: "few walls scanned",
  noWalls: "no walls scanned",
};

/** Room type words in a room's name, checked in this order (a "Bath" before a "Bedroom"). */
const NAME_TYPES: readonly (readonly [RegExp, RoomType])[] = [
  [/\b(bath(room)?|wc|toilet|powder|en-?suite|restroom|shower)\b/i, "bathroom"],
  [/\b(kitchen(ette)?)\b/i, "kitchen"],
  [/\b(bed(room)?|nursery|master)\b/i, "bedroom"],
  [/\b(dining)\b/i, "dining_room"],
  [/\b(living|lounge|family room|great room)\b/i, "living_room"],
  [/\b(closet|wardrobe|walk-?in)\b/i, "closet"],
  [/\b(laundry|mud ?room)\b/i, "laundry"],
  [/\b(office|study|den)\b/i, "office"],
  [/\b(hall(way)?|corridor|foyer|entry|entrance|landing|vestibule)\b/i, "hallway"],
  [/\b(utility|mechanical|boiler)\b/i, "utility"],
];

/** Fixtures (then furniture) that say what a room is, strongest first. */
const OBJECT_TYPES: readonly (readonly [readonly ObjectCategory[], RoomType])[] = [
  [["toilet", "bathtub"], "bathroom"],
  [["stove", "oven", "refrigerator", "dishwasher"], "kitchen"],
  [["bed"], "bedroom"],
  [["sofa", "television"], "living_room"],
];

function roomTypeOf(
  room: RoomMetrics,
  fixtures: ReadonlyMap<string, number>,
  furniture: ReadonlyMap<string, number>,
): [RoomType, RoomTypeSource] {
  if (room.type !== undefined) {
    return [room.type, "scan"];
  }
  for (const [pattern, type] of NAME_TYPES) {
    if (pattern.test(room.label)) {
      return [type, "name"];
    }
  }
  for (const [categories, type] of OBJECT_TYPES) {
    if (categories.some((category) => fixtures.has(category) || furniture.has(category))) {
      return [type, "fixtures"];
    }
  }
  return ["other", "unknown"];
}

function totalsOf(rooms: readonly RoomQuantities[]): SummaryTotals {
  const fixtures = new Map<string, number>();
  const byType = new Map<string, { rooms: number; areaM2: number }>();
  let floorAreaM2 = 0;
  let paintableM2 = 0;
  let baseboardM = 0;
  let doors = 0;
  let windows = 0;
  for (const room of rooms) {
    floorAreaM2 += room.floorAreaM2;
    paintableM2 += room.paintableWallAreaM2;
    baseboardM += room.baseboardM;
    doors += room.doors;
    windows += room.windows;
    for (const [category, count] of room.fixtures) {
      fixtures.set(category, (fixtures.get(category) ?? 0) + count);
    }
    const entry = byType.get(room.type) ?? { rooms: 0, areaM2: 0 };
    byType.set(room.type, { rooms: entry.rooms + 1, areaM2: entry.areaM2 + room.floorAreaM2 });
  }
  const byRoomType: Record<string, { rooms: number; floorAreaSqFt: number }> = {};
  for (const type of [...byType.keys()].sort()) {
    const entry = byType.get(type);
    if (entry !== undefined) {
      byRoomType[type] = { rooms: entry.rooms, floorAreaSqFt: sqFt(entry.areaM2) };
    }
  }
  return {
    rooms: rooms.length,
    floorAreaSqFt: sqFt(floorAreaM2),
    paintableWallAreaSqFt: sqFt(paintableM2),
    ceilingAreaSqFt: sqFt(floorAreaM2),
    baseboardFt: ft(baseboardM),
    doors,
    windows,
    fixtures: sortedRecord(fixtures),
    byRoomType,
  };
}

function sortedRecord(counts: ReadonlyMap<string, number>): Record<string, number> {
  const record: Record<string, number> = {};
  for (const key of [...counts.keys()].sort()) {
    record[key] = counts.get(key) ?? 0;
  }
  return record;
}

/** Rounds to 0.1, with exact halves away from zero. */
function tenth(value: number): number {
  return (Math.sign(value) * Math.round(Math.abs(value) * 10 + 1e-9)) / 10;
}

function sqFt(squareMetres: number): number {
  return tenth(squareFeet(squareMetres));
}

function ft(metres: number): number {
  return tenth(metres / METRES_PER_FOOT);
}
