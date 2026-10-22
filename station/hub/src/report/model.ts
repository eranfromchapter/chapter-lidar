// The report model (pure): floors, rooms in schedule order with their numbers and words, items,
// photos, skipped rooms, compass states, check rows and totals. Pagination and drawing read only
// this model.

import {
  checkCounts,
  checkRows,
  compassState,
  northSymbol,
  notScannedRooms,
  notScannedRoomText,
  NOT_VERIFIED_BOX,
  type Capture,
  type CaptureMode,
  type CaptureModel,
  type CheckCounts,
  type CheckRow,
  type CompassState,
  type FieldControls,
  type NorthSymbol,
  type NotScannedRoom,
  type RoomType,
  type Verdict,
} from "@chapter/capture-contract";
import { cuFt, dimensionPair, ftIn, sqFt } from "./format.js";
import type { ReportFloor, ReportModel, ReportPhoto, SpatialReportInput } from "./input.js";
import { dominantAngle, longSide, shortSide } from "./metrics/metrics-geometry.js";
import { PlanGeometryError, type Point } from "./metrics/plan-geometry.js";
import {
  isApproximate,
  planMetrics,
  type PlanMetrics,
  type PlanTotals,
  type RoomMetrics,
} from "./metrics/room-metrics.js";
import { decimals, feetInches, squareFeet } from "./metrics/units.js";
import { WORDS } from "./words.js";

export type FillClass = "habitable" | "wet" | "other" | "outdoor";
export type ItemGroup = "furniture" | "fixtures" | "appliances" | "other" | "openings";

/** Groups of the items table, in table order, with their marker shapes. */
export const ITEM_GROUPS: ReadonlyArray<{
  readonly group: ItemGroup;
  readonly label: string;
  readonly shape: MarkerShape;
}> = [
  { group: "furniture", label: "Furniture", shape: "circle" },
  { group: "fixtures", label: "Fixtures", shape: "triangle" },
  { group: "appliances", label: "Appliances", shape: "diamond" },
  { group: "other", label: "Other", shape: "pentagon" },
  { group: "openings", label: "Openings", shape: "square" },
];

export type MarkerShape = "circle" | "triangle" | "diamond" | "square" | "pentagon";

const CATEGORY: Record<string, { group: ItemGroup; name: string }> = {
  bed: { group: "furniture", name: "Bed" },
  chair: { group: "furniture", name: "Chair" },
  sofa: { group: "furniture", name: "Sofa" },
  table: { group: "furniture", name: "Table" },
  bathtub: { group: "fixtures", name: "Bathtub" },
  sink: { group: "fixtures", name: "Sink" },
  toilet: { group: "fixtures", name: "Toilet" },
  storage: { group: "fixtures", name: "Storage" },
  fireplace: { group: "fixtures", name: "Fireplace" },
  stairs: { group: "fixtures", name: "Stairs" },
  dishwasher: { group: "appliances", name: "Dishwasher" },
  oven: { group: "appliances", name: "Oven" },
  refrigerator: { group: "appliances", name: "Refrigerator" },
  stove: { group: "appliances", name: "Stove" },
  television: { group: "appliances", name: "TV" },
  washer_dryer: { group: "appliances", name: "Washer/dryer" },
  other: { group: "other", name: "Other" },
};

const OPENING_NAME = { door: "Door", window: "Window", opening: "Passage" } as const;

/** One row of a room's items table. */
export interface ItemRow {
  readonly group: ItemGroup;
  /** Number in its group (1-based, table order). */
  readonly number: number;
  readonly name: string;
  readonly low: boolean;
  readonly w: string;
  readonly h: string;
  readonly d: string;
  /** Object or opening id. */
  readonly id: string;
  readonly kind: "object" | "opening";
}

export interface ModelRoom {
  readonly floorIndex: number;
  /** Position in report order across the visit (1-based). */
  readonly number: number;
  readonly metrics: RoomMetrics;
  readonly name: string;
  readonly unlabeled: boolean;
  readonly fill: FillClass;
  readonly rectangular: boolean;
  readonly approximate: boolean;
  readonly items: readonly ItemRow[];
  readonly photos: readonly ReportPhoto[];
  readonly words: {
    readonly area: string;
    readonly wall: string;
    readonly wallIncl: string;
    readonly bbox: string;
    readonly inscribed: string;
    readonly perimeter: string;
    readonly ceiling: string;
    readonly volume: string;
  };
}

export interface ModelFloor {
  readonly index: number;
  readonly captureId: string;
  readonly areaKey: string;
  readonly label: string;
  readonly mode?: CaptureMode;
  readonly capture?: Capture;
  readonly source: ReportModel;
  readonly metrics?: PlanMetrics;
  /** Rooms in schedule order (floor area, largest first; ties in model order). */
  readonly rooms: readonly ModelRoom[];
  readonly skipped: readonly NotScannedRoom[];
  /** Photos of this capture whose room label matches no room. */
  readonly otherPhotos: readonly ReportPhoto[];
  readonly compass: CompassState;
  /** Clockwise rotation that squares the floor's walls with the page, degrees. */
  readonly rotationDegrees: number;
}

export interface VisitTotals {
  readonly roomsScanned: number;
  readonly bedrooms?: number;
  readonly bathrooms?: number;
  readonly livableAreaM2: number;
  readonly wallAreaM2: number;
  readonly windowAreaM2: number;
  readonly volumeM3: number;
  readonly volumeIsApproximate: boolean;
  readonly perimeterM: number;
  readonly items: number;
  /** True when at least one floor has a readable model. */
  readonly readable: boolean;
}

export interface Model {
  readonly input: SpatialReportInput;
  readonly verdict: Verdict;
  readonly timeZone: string;
  readonly title: string;
  readonly addressLine: string;
  readonly floors: readonly ModelFloor[];
  /** Rooms of every floor in report order. */
  readonly rooms: readonly ModelRoom[];
  readonly totals: VisitTotals;
  readonly checkRows: readonly CheckRow[];
  readonly counts: CheckCounts;
  readonly reviewUrl: string;
  readonly fieldControls?: FieldControls | "invalid";
  readonly photosOmitted: boolean;
  /** Number of manifest entries. */
  readonly fileCount: number;
}

// MARK: Rules

/** Title line and address line of a one-line address (spec 6.1). */
export function addressLines(formatted: string | undefined): { title: string; address: string } {
  if (formatted === undefined) {
    return { title: "Address not recorded", address: "" };
  }
  const parts = formatted.split(", ");
  if (parts.length >= 3) {
    return { title: parts.slice(0, -2).join(", "), address: parts.slice(-2).join(", ") };
  }
  return { title: formatted, address: "" };
}

/** Unlabeled: "Room N" with no type (or other) that the operator did not type. */
export function isUnlabeled(room: CaptureModel["rooms"][number]): boolean {
  return (
    /^Room \d+$/.test(room.label) &&
    (room.type === undefined || room.type === "other") &&
    room.typeSource !== "operator"
  );
}

const LABEL_TYPES: ReadonlyArray<readonly [RoomType, readonly string[]]> = [
  ["bedroom", ["bed"]],
  ["bathroom", ["bath", "toilet", "shower", "wc"]],
  ["kitchen", ["kitchen"]],
  ["living_room", ["living", "lounge", "family"]],
  ["dining_room", ["dining"]],
  ["closet", ["closet", "wardrobe", "pantry"]],
  ["hallway", ["hall", "corridor", "entry", "foyer"]],
  ["laundry", ["laundry"]],
  ["office", ["office", "study"]],
];

/**
 * The room type a label implies (PlanExport FloorPlanStyle.type(fromLabel:)), for a room the
 * model gives no type: every room of a 1.0.0 model, and an untyped room of a 1.1.0 one.
 */
export function typeFromLabel(label: string): RoomType | undefined {
  const text = label.toLowerCase();
  for (const [type, words] of LABEL_TYPES) {
    if (words.some((word) => text.includes(word))) {
      return type;
    }
  }
  return undefined;
}

const has = (text: string, words: readonly string[]) => words.some((word) => text.includes(word));

/**
 * Fill class of a room (plan-sheet 3.4.1, the plan sheet's `RoomFillClass.of`, critique R-35):
 * outdoor labels, then wet and habitable by type or label, then by objects for rooms with no
 * type (or `other`), else other. Every room of an exterior capture is outdoor. `modelType` is
 * the capture model's type; a room without one takes the type its label implies
 * (`typeFromLabel`), as on the sheet, so an untyped "Pantry" is a closet whatever it holds.
 */
export function fillClass(
  label: string,
  modelType: RoomType | undefined,
  categories: readonly string[],
  mode: CaptureMode | undefined,
): FillClass {
  const text = label.toLowerCase();
  if (mode === "exterior" || has(text, ["balcony", "terrace", "patio", "deck", "porch"])) {
    return "outdoor";
  }
  const type = modelType ?? typeFromLabel(label);
  if (
    (type !== undefined && ["bathroom", "kitchen", "laundry"].includes(type)) ||
    has(text, ["bath", "kitchen", "laundry", "wc", "toilet", "shower"])
  ) {
    return "wet";
  }
  if (
    (type !== undefined && ["bedroom", "living_room", "dining_room", "office"].includes(type)) ||
    has(text, ["bed", "living", "dining", "office", "study"])
  ) {
    return "habitable";
  }
  if (type === undefined || type === "other") {
    if (
      categories.some((c) => ["toilet", "bathtub", "sink", "stove", "washer_dryer"].includes(c))
    ) {
      return "wet";
    }
    if (categories.includes("bed")) {
      return "habitable";
    }
  }
  return "other";
}

/** Photo room labels match room labels this way (the station coverage check's rule). */
export function normalizeLabel(text: string): string {
  return text.normalize("NFKC").toLowerCase().replace(/\s+/g, " ").trim();
}

function itemsOf(metrics: RoomMetrics): ItemRow[] {
  const rows: ItemRow[] = [];
  const counter = new Map<ItemGroup, number>();
  const next = (group: ItemGroup) => {
    const n = (counter.get(group) ?? 0) + 1;
    counter.set(group, n);
    return n;
  };
  const objectRows = metrics.objects.map((object) => {
    const entry = CATEGORY[object.category] ?? { group: "other" as const, name: "Other" };
    return { object, entry };
  });
  for (const { group } of ITEM_GROUPS) {
    if (group === "openings") {
      for (const opening of metrics.openings) {
        rows.push({
          group,
          number: next(group),
          name: OPENING_NAME[opening.type],
          low: opening.confidence === "low",
          w: feetInches(opening.widthM),
          h: feetInches(opening.heightM),
          d: `${sqFt(opening.areaM2)} sq ft`,
          id: opening.id,
          kind: "opening",
        });
      }
      continue;
    }
    for (const { object, entry } of objectRows) {
      if (entry.group !== group) {
        continue;
      }
      rows.push({
        group,
        number: next(group),
        name: entry.name,
        low: object.confidence === "low",
        w: feetInches(object.widthM),
        h: feetInches(object.heightM),
        d: feetInches(object.depthM),
        id: object.id,
        kind: "object",
      });
    }
  }
  return rows;
}

// MARK: Build

/**
 * The measurements of one floor's model. A model the contract accepts can still describe
 * geometry the measurement engine refuses (PlanGeometryError, e.g. a door on a wall id that
 * names no wall; the phone's PlanExport refuses it the same way): that floor is "unreadable"
 * (spec 6.2: "Plan not available ... could not be read") and the rest of the report is made.
 */
function measured(source: ReportModel): { status: ReportModel; metrics?: PlanMetrics } {
  if (source.status !== "ok") {
    return { status: source };
  }
  try {
    return { status: source, metrics: planMetrics(source.model) };
  } catch (error) {
    if (error instanceof PlanGeometryError) {
      return { status: { status: "unreadable" } };
    }
    throw error;
  }
}

function floorSources(input: SpatialReportInput): SpatialReportInput["floors"] {
  if (input.floors !== undefined) {
    return input.floors;
  }
  const captures = input.captureRecord?.captures ?? [];
  return captures.map((capture) => ({
    captureId: capture.captureId,
    areaKey: capture.areaKey,
    model: { status: "absent" as const },
  }));
}

export function buildModel(input: SpatialReportInput): Model {
  const timeZone = input.timeZone ?? "America/New_York";
  const record = input.captureRecord;
  const { title, address } = addressLines(record?.address.formatted);
  const sources = floorSources(input) ?? [];
  const skippedAll = record === undefined ? [] : notScannedRooms(record);
  const photos = [...(input.photos ?? [])].sort((a, b) =>
    a.takenAt < b.takenAt
      ? -1
      : a.takenAt > b.takenAt
        ? 1
        : a.path < b.path
          ? -1
          : a.path > b.path
            ? 1
            : 0,
  );
  let number = 0;
  const floors: ModelFloor[] = sources.map((source, index) => {
    const capture = record?.captures.find((c) => c.captureId === source.captureId);
    const label = capture?.label ?? source.areaKey;
    const mode = capture?.mode;
    const { status, metrics } = measured(source.model);
    const model = status.status === "ok" ? status.model : undefined;
    const ownPhotos = photos.filter((photo) => photo.captureId === source.captureId);
    const roomsInOrder = (metrics?.rooms ?? [])
      .map((room, modelIndex) => ({ room, modelIndex }))
      .sort((a, b) => b.room.floorAreaM2 - a.room.floorAreaM2 || a.modelIndex - b.modelIndex);
    const claimed = new Set<ReportPhoto>();
    const rooms: ModelRoom[] = roomsInOrder.map(({ room, modelIndex }) => {
      const sourceRoom = model?.rooms[modelIndex];
      const type = sourceRoom?.type;
      const categories = room.objects.map((object) => object.category);
      const key = normalizeLabel(room.label);
      const roomPhotos = ownPhotos.filter(
        (photo) => !claimed.has(photo) && normalizeLabel(photo.room) === key,
      );
      roomPhotos.forEach((photo) => claimed.add(photo));
      const bbox = dimensionPair(room.boundingBox.alongM, room.boundingBox.acrossM);
      const inscribed = dimensionPair(room.inscribed.alongM, room.inscribed.acrossM);
      number += 1;
      return {
        floorIndex: index,
        number,
        metrics: room,
        name: room.label,
        unlabeled: sourceRoom === undefined ? false : isUnlabeled(sourceRoom),
        fill: fillClass(room.label, type, categories, mode),
        rectangular:
          feetInches(longSide(room.boundingBox)) === feetInches(longSide(room.inscribed)) &&
          feetInches(shortSide(room.boundingBox)) === feetInches(shortSide(room.inscribed)),
        approximate: isApproximate(room.ceiling),
        items: itemsOf(room),
        photos: roomPhotos,
        words: {
          area: sqFt(room.floorAreaM2),
          wall: sqFt(room.wallAreaExcludingOpeningsM2),
          wallIncl: sqFt(room.wallAreaIncludingOpeningsM2),
          bbox,
          inscribed,
          perimeter: ftIn(room.perimeterM),
          ceiling: ftIn(room.ceiling.heightM),
          volume: cuFt(room.volumeM3),
        },
      };
    });
    const rotation =
      metrics === undefined
        ? 0
        : (dominantAngle(metrics.geometry.rooms.map((room) => room.polygon)) * 180) / Math.PI;
    return {
      index,
      captureId: source.captureId,
      areaKey: source.areaKey,
      label,
      ...(mode === undefined ? {} : { mode }),
      ...(capture === undefined ? {} : { capture }),
      source: status,
      ...(metrics === undefined ? {} : { metrics }),
      rooms,
      skipped: skippedAll.filter((room) => room.captureId === source.captureId),
      otherPhotos: ownPhotos.filter((photo) => !claimed.has(photo)),
      compass:
        capture === undefined
          ? { kind: "not_verified" as const, reason: "no_reading" as const }
          : compassState(capture),
      rotationDegrees: rotation,
    };
  });
  // Photos of captures the report has no floor for go to no page (they stay in the package).

  const readable = floors.filter((floor) => floor.metrics !== undefined);
  const allTotals = readable.map((floor) => floor.metrics?.totals as PlanTotals);
  const typed = readable.some((floor) =>
    floor.source.status === "ok"
      ? floor.source.model.rooms.some((r) => r.type !== undefined)
      : false,
  );
  const sum = (pick: (t: PlanTotals) => number) => allTotals.reduce((s, t) => s + pick(t), 0);
  const rooms = floors.flatMap((floor) => floor.rooms);
  const totals: VisitTotals = {
    roomsScanned: rooms.length,
    ...(typed ? { bedrooms: sum((t) => t.bedrooms), bathrooms: sum((t) => t.bathrooms) } : {}),
    livableAreaM2: sum((t) => t.livableAreaM2),
    wallAreaM2: sum((t) => t.wallAreaM2),
    windowAreaM2: sum((t) => t.windowAreaM2),
    volumeM3: sum((t) => t.volumeM3),
    volumeIsApproximate: allTotals.some((t) => t.volumeIsApproximate),
    perimeterM: sum((t) => t.perimeterM),
    items: rooms.reduce((n, room) => n + room.items.length, 0),
    readable: readable.length > 0,
  };
  const rows = checkRows(input.verdict, record);
  return {
    input,
    verdict: input.verdict,
    timeZone,
    title,
    addressLine: address,
    floors,
    rooms,
    totals,
    checkRows: rows,
    counts: checkCounts(rows),
    reviewUrl: `${input.reviewBaseUrl.replace(/\/+$/, "")}/packages/${input.packageId}`,
    ...(input.fieldControls === undefined ? {} : { fieldControls: input.fieldControls }),
    photosOmitted: input.photosOmitted === true,
    fileCount:
      input.manifestFileCount ?? input.files.filter((file) => file.role !== "manifest").length,
  };
}

/** Per-floor figures stored with the report (one per floor with a readable model). */
export function reportFloors(model: Model): ReportFloor[] {
  return model.floors
    .filter((floor) => floor.metrics !== undefined)
    .map((floor) => ({
      captureId: floor.captureId,
      areaKey: floor.areaKey,
      roomsScanned: floor.rooms.length,
      roomsUnlabeled: floor.rooms.filter((room) => room.unlabeled).length,
      floorAreaSqFt: Number(
        decimals(squareFeet(floor.metrics?.totals.livableAreaM2 ?? 0), 1) ?? "0",
      ),
    }));
}

// MARK: Words used by several pages

/** "{name} ({reason})" entries of skipped rooms; on a multi-floor cover with the floor label. */
export function skippedEntries(rooms: readonly NotScannedRoom[], withFloor: boolean): string[] {
  return rooms.map((room) => notScannedRoomText(room, withFloor));
}

/** The task with its first letter lower-cased ("preliminary existing-condition plans"). */
export function taskWords(verdict: Verdict): string {
  const task = verdict.task;
  return task.charAt(0).toLowerCase() + task.slice(1);
}

export function blockerCount(model: Model): number {
  return model.counts.blockers;
}

/** The north block of a floor without a readable scan model. */
export const NO_SCAN_MODEL_SYMBOL: NorthSymbol = {
  kind: "box",
  box: NOT_VERIFIED_BOX,
  caption: WORDS.noScanModel,
};

/**
 * The north symbol of a floor's drawing: the drawing turns the plan clockwise by the floor's
 * squaring rotation a, so the contract's drawing rotation is -a (compass 2.5). A floor without a
 * readable model has no drawing: the box with "No scan model".
 */
export function floorNorthSymbol(floor: ModelFloor): NorthSymbol {
  if (floor.metrics === undefined) {
    return NO_SCAN_MODEL_SYMBOL;
  }
  return northSymbol(floor.compass, -floor.rotationDegrees);
}

/** The label point of a room in plan coordinates (for labels and markers). */
export type { Point };
