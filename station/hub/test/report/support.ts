// Test inputs of the spatial report: the generated 424 sample package (fixtures/generated/
// sample-424) with its recorded verdicts (fixtures/report/424-west-end), the two-floor house,
// and synthetic capture models for the layout edge cases (long names, many items, many rooms).

import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  Capture,
  CaptureModel,
  CaptureRecord,
  PackageManifest,
  Verdict,
} from "@chapter/capture-contract";
import PDFDocument from "pdfkit";
import { extractText, getDocumentProxy } from "unpdf";
import {
  loadReportSources,
  planPublication,
  reportFilesOf,
  type PublishPackage,
  type ReportPhoto,
  type SpatialReportInput,
} from "../../src/index.js";
import { registerFonts } from "../../src/report/fonts.js";
import { Canvas } from "../../src/report/layout/canvas.js";
import { buildModel, type Model } from "../../src/report/model.js";
import { paginate } from "../../src/report/paginate.js";
import type { PageSpec } from "../../src/report/pages/index-of-pages.js";
import { REVIEW_BASE_URL } from "../helpers.js";

export const REPO = fileURLToPath(new URL("../../../../", import.meta.url));
export const GENERATED = join(REPO, "fixtures/generated");
export const VERDICTS_424 = join(REPO, "fixtures/report/424-west-end");

export type Outcome = "ready" | "limited" | "blocked";

export function verdict424(outcome: Outcome): Verdict {
  return JSON.parse(readFileSync(join(VERDICTS_424, `verdict-${outcome}.json`), "utf8")) as Verdict;
}

interface FixturePackage {
  readonly root: string;
  readonly manifest: PackageManifest;
  readonly manifestBytes: Buffer;
  readonly record?: CaptureRecord;
  readonly visitId: string;
}

export function fixturePackage(name: string): FixturePackage {
  const root = join(GENERATED, name, "package");
  const visitId = readdirSync(join(root, "Source Register"))[0] as string;
  const manifestBytes = readFileSync(join(root, "Source Register", visitId, "manifest.json"));
  const manifest = JSON.parse(manifestBytes.toString("utf8")) as PackageManifest;
  const recordEntry = manifest.files.find((f) => f.role === "capture_record");
  const record =
    recordEntry === undefined
      ? undefined
      : (JSON.parse(readFileSync(join(root, recordEntry.path), "utf8")) as CaptureRecord);
  return { root, manifest, manifestBytes, ...(record === undefined ? {} : { record }), visitId };
}

/** The publish package of a generated fixture, as the worker builds it. */
export function publishPackage(fixture: FixturePackage): PublishPackage {
  const { manifest } = fixture;
  return {
    packageId: manifest.packageId,
    dealId: fixture.record?.hub.dealId ?? "fixture-deal-0001",
    visitId: manifest.visitId,
    revision: manifest.revision,
    manifestPath: `Source Register/${fixture.visitId}/manifest.json`,
    manifestSha256: createHash("sha256").update(fixture.manifestBytes).digest("hex"),
    manifestBytes: fixture.manifestBytes.length,
    sealedAt: manifest.sealedAt,
    manifestFileCount: manifest.files.length,
    files: manifest.files.map((f) => ({
      path: f.path,
      role: f.role,
      ...(f.captureId === undefined ? {} : { captureId: f.captureId }),
      ...(f.areaKey === undefined ? {} : { areaKey: f.areaKey }),
      sha256: f.sha256,
      bytes: f.bytes,
      mime: f.mime,
      ...(f.photo === undefined
        ? {}
        : {
            photo: {
              room: f.photo.room,
              direction: f.photo.direction,
              subject: f.photo.subject,
              takenAt: f.photo.takenAt,
            },
          }),
    })),
  };
}

/**
 * The full report input of a generated fixture with a verdict, read from disk. `editRecord`
 * changes the capture record the report reads (compass states of the visual scenarios).
 */
export async function fixtureInput(
  name: string,
  verdict: Verdict,
  editRecord?: (record: CaptureRecord) => CaptureRecord,
): Promise<SpatialReportInput> {
  const fixture = fixturePackage(name);
  const pkg = publishPackage(fixture);
  const plan = planPublication(pkg, verdict.verdictId, { reviewBaseUrl: REVIEW_BASE_URL });
  const record =
    fixture.record === undefined || editRecord === undefined
      ? fixture.record
      : editRecord(structuredClone(fixture.record));
  const sources = await loadReportSources({
    files: pkg.files,
    ...(record === undefined ? {} : { captureRecord: record }),
    readFile: async (path) => readFileSync(join(fixture.root, path)),
  });
  return {
    verdict,
    packageId: pkg.packageId,
    dealId: pkg.dealId,
    ...(record === undefined ? {} : { captureRecord: record }),
    reportLocation: plan.report,
    files: reportFilesOf(plan),
    maxUploadBytes: 45 * 1024 * 1024,
    reviewBaseUrl: REVIEW_BASE_URL,
    sealedAt: fixture.manifest.sealedAt,
    manifestFileCount: fixture.manifest.files.length,
    ...sources,
  };
}

export const input424 = (outcome: Outcome) => fixtureInput("sample-424", verdict424(outcome));

// MARK: Synthetic models

export interface SyntheticRoom {
  readonly label: string;
  /** Width (plan x) and depth (plan y = -z), metres, of a rectangular room. */
  readonly w: number;
  readonly d: number;
  /** Outline in plan metres (x, y = -z) relative to the room's origin, counter-clockwise. */
  readonly outline?: ReadonlyArray<readonly [number, number]>;
  readonly heightM?: number;
  readonly type?: CaptureModel["rooms"][number]["type"];
  readonly typeSource?: CaptureModel["rooms"][number]["typeSource"];
  /** Objects inside the room: category and box size [x, y, z]. */
  readonly objects?: ReadonlyArray<{
    category: CaptureModel["objects"][number]["category"];
    size?: [number, number, number];
    low?: boolean;
  }>;
  /** Doors on the room's third wall, windows on its first. */
  readonly doors?: number;
  readonly windows?: number;
}

const ID = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

type Vec3 = [number, number, number];

/**
 * A capture model of rooms side by side along x, each with its own walls (height 2.5 m unless
 * given), objects on a grid inside the room's bounding box, doors on the third wall and windows
 * on the first. `turnDegrees` turns the whole plan counter-clockwise (seen from +Y) about the
 * origin, so its walls no longer run along the axes.
 */
export function syntheticModel(
  rooms: readonly SyntheticRoom[],
  captureId = ID(2),
  options: { schemaVersion?: "1.0.0" | "1.1.0"; turnDegrees?: number } = {},
): CaptureModel {
  const turn = ((options.turnDegrees ?? 0) * Math.PI) / 180;
  // Plan point (x, y) -> model point (x, height, -y), turned.
  const at = (x: number, y: number, height = 0): Vec3 => {
    const tx = x * Math.cos(turn) - y * Math.sin(turn);
    const ty = x * Math.sin(turn) + y * Math.cos(turn);
    return [tx, height, ty === 0 ? 0 : -ty];
  };
  const model: CaptureModel = {
    schemaVersion: options.schemaVersion ?? "1.1.0",
    visitId: ID(1),
    captureId,
    areaKey: "floor-1",
    label: "Floor 1",
    coordinateSystem: { units: "m", handedness: "right", up: "+Y" },
    rooms: [],
    walls: [],
    doors: [],
    windows: [],
    openings: [],
    objects: [],
    refs: [],
  };
  let x0 = 0;
  rooms.forEach((room, r) => {
    const id = `room-${r + 1}`;
    const outline = room.outline ?? [
      [0, 0],
      [room.w, 0],
      [room.w, room.d],
      [0, room.d],
    ];
    const plan = outline.map(([x, y]) => [x0 + x, y] as const);
    const corners = plan.map(([x, y]) => at(x, y));
    const height = room.heightM ?? 2.5;
    model.rooms.push({
      id,
      label: room.label,
      polygon: corners as CaptureModel["rooms"][number]["polygon"],
      heightM: height,
      ...(options.schemaVersion !== "1.0.0" && room.type !== undefined ? { type: room.type } : {}),
      ...(options.schemaVersion !== "1.0.0" && room.typeSource !== undefined
        ? { typeSource: room.typeSource }
        : {}),
    });
    corners.forEach((start, i) => {
      const end = corners[(i + 1) % corners.length] as Vec3;
      model.walls.push({
        id: `${id}-wall-${i + 1}`,
        start,
        end,
        heightM: height,
        thicknessM: 0,
        roomIds: [id],
      });
    });
    for (let k = 0; k < (room.doors ?? 0); k += 1) {
      model.doors.push({
        id: `${id}-door-${k + 1}`,
        wallId: `${id}-wall-3`,
        offsetM: 0.6 + k * 1.0,
        bottomM: 0,
        widthM: 0.8,
        heightM: 2.1,
      });
    }
    for (let k = 0; k < (room.windows ?? 0); k += 1) {
      model.windows.push({
        id: `${id}-window-${k + 1}`,
        wallId: `${id}-wall-1`,
        offsetM: 0.8 + k * 1.2,
        bottomM: 0.9,
        widthM: 1.0,
        heightM: 1.2,
      });
    }
    const xs = plan.map(([x]) => x);
    const ys = plan.map(([, y]) => y);
    const minX = Math.min(...xs);
    const minY = Math.min(...ys);
    const width = Math.max(...xs) - minX;
    const depth = Math.max(...ys) - minY;
    const objects = room.objects ?? [];
    const columns = Math.max(1, Math.ceil(Math.sqrt(objects.length)));
    const rowsOf = Math.max(1, Math.ceil(objects.length / columns));
    objects.forEach((object, k) => {
      const size = object.size ?? [0.5, 0.8, 0.4];
      const cx = minX + ((k % columns) + 0.5) * (width / columns);
      const cy = minY + (Math.floor(k / columns) + 0.5) * (depth / rowsOf);
      model.objects.push({
        id: `${id}-object-${k + 1}`,
        category: object.category,
        roomId: id,
        box: { center: at(cx, cy, size[1] / 2), sizeM: size, rotation: [0, 0, 0, 1] },
        confidence: object.low === true ? "low" : "high",
      });
    });
    x0 = Math.max(...xs) + 0.12;
  });
  return model;
}

/** A verified compass reading (true north, ±8°, heading 212.4°) taken during the scan. */
export const VERIFIED: Partial<Capture> = {
  heading: 212.4,
  headingAccuracy: 8,
  headingSource: "true",
  headingRecordedAt: "2026-10-17T14:02:20Z",
};

/** One capture of a synthetic record: floor mode, scanned 14:02 to 14:20 UTC. */
export function syntheticCapture(
  captureId: string,
  label: string,
  areaKey: string,
  extra: Partial<Capture> = {},
): Capture {
  return {
    captureId,
    areaKey,
    label,
    mode: "floor",
    units: { length: "m", display: "imperial" },
    capturedAt: "2026-10-17T14:02:11Z",
    finishedAt: "2026-10-17T14:20:40Z",
    coverageNotes: "",
    omittedRooms: [],
    inaccessibleRooms: [],
    ...extra,
  };
}

/** A capture record of one or more captures (all floor mode; the first with a verified compass). */
export function syntheticRecord(
  captures: ReadonlyArray<{
    captureId: string;
    label: string;
    areaKey: string;
    extra?: Partial<Capture>;
  }>,
  address = "424 West End Ave, Apt 4K, New York, NY 10024",
): CaptureRecord {
  const list = captures.map((capture, i) =>
    syntheticCapture(
      capture.captureId,
      capture.label,
      capture.areaKey,
      capture.extra ?? (i === 0 ? VERIFIED : { headingIssue: "not_calibrated" }),
    ),
  );
  const [first, ...rest] = list;
  if (first === undefined) {
    throw new Error("a capture record has at least one capture");
  }
  return {
    schemaVersion: "1.1.0",
    visitId: ID(1),
    hub: { dealId: "fixture-deal-0001", projectName: "Synthetic" },
    address: { formatted: address, confirmedOnSite: true, confirmedAt: "2026-10-17T13:58:20Z" },
    operator: { name: "Test Operator" },
    device: {
      model: "iPhone17,1",
      marketingName: "iPhone 16 Pro",
      osName: "iOS",
      osVersion: "26.0.1",
      hasLidar: true,
    },
    app: { version: "2.0.0", build: "test" },
    visitedAt: "2026-10-17T13:55:00Z",
    captures: [first, ...rest],
  };
}

export interface SyntheticFloor {
  readonly label: string;
  readonly rooms: readonly SyntheticRoom[];
  /** Capture-record fields of this floor (compass, skipped rooms, mode). */
  readonly capture?: Partial<Capture>;
  /** The model as the loader found it (default ok). */
  readonly status?: "ok" | "absent" | "unreadable";
  readonly schemaVersion?: "1.0.0" | "1.1.0";
  readonly turnDegrees?: number;
}

export interface SyntheticOptions {
  readonly outcome?: Outcome;
  readonly verdict?: Verdict;
  readonly address?: string;
  /** No capture record in the package. */
  readonly noRecord?: boolean;
  readonly photos?: readonly ReportPhoto[];
  readonly photosOmitted?: boolean;
  readonly timeZone?: string;
}

export const captureIdOf = (floor: number) => ID(100 + floor);

/** A synthetic report input (no package files). */
export function syntheticInput(
  floors: readonly SyntheticFloor[],
  options: SyntheticOptions = {},
): SpatialReportInput {
  const verdict = options.verdict ?? verdict424(options.outcome ?? "limited");
  const record = syntheticRecord(
    floors.map((floor, i) => ({
      captureId: captureIdOf(i),
      label: floor.label,
      areaKey: `floor-${i + 1}`,
      ...(floor.capture === undefined ? {} : { extra: floor.capture }),
    })),
    options.address,
  );
  return {
    verdict,
    packageId: verdict.packageId,
    dealId: "fixture-deal-0001",
    ...(options.noRecord === true ? {} : { captureRecord: record }),
    reportLocation: {
      folder: `Capture/${verdict.visitId}/r1`,
      name: `spatial-report-${verdict.verdictId}.pdf`,
    },
    files: [],
    maxUploadBytes: 45 * 1024 * 1024,
    reviewBaseUrl: REVIEW_BASE_URL,
    sealedAt: "2026-10-17T15:10:00Z",
    ...(options.timeZone === undefined ? {} : { timeZone: options.timeZone }),
    floors: floors.map((floor, i) => ({
      captureId: captureIdOf(i),
      areaKey: `floor-${i + 1}`,
      model:
        floor.status === undefined || floor.status === "ok"
          ? {
              status: "ok" as const,
              model: syntheticModel(floor.rooms, captureIdOf(i), {
                ...(floor.schemaVersion === undefined
                  ? {}
                  : { schemaVersion: floor.schemaVersion }),
                ...(floor.turnDegrees === undefined ? {} : { turnDegrees: floor.turnDegrees }),
              }),
            }
          : { status: floor.status },
    })),
    ...(options.photos === undefined ? {} : { photos: options.photos }),
    ...(options.photosOmitted === undefined ? {} : { photosOmitted: options.photosOmitted }),
  };
}

/** `n` rooms named `Room A1`, `Room A2`, … of decreasing size (so the schedule keeps the order). */
export function namedRooms(n: number, prefix = "Bedroom"): SyntheticRoom[] {
  return Array.from({ length: n }, (_, i) => ({
    label: `${prefix} ${i + 1}`,
    w: 4 - i * 0.05,
    d: 3,
    doors: 1,
  }));
}

/** `n` objects cycling through furniture, fixtures and appliances. */
export function manyObjects(n: number): NonNullable<SyntheticRoom["objects"]> {
  const categories = ["chair", "table", "storage", "sink", "refrigerator", "television"] as const;
  return Array.from({ length: n }, (_, i) => ({
    category: categories[i % categories.length] as (typeof categories)[number],
    size: [0.4, 0.5, 0.4] as [number, number, number],
  }));
}

// MARK: Layout without drawing

/** The report model and its page list, measured with the embedded fonts (nothing drawn). */
export function layoutOf(input: SpatialReportInput): { model: Model; pages: PageSpec[] } {
  const doc = new PDFDocument({
    size: [792, 612],
    margin: 0,
    autoFirstPage: false,
    font: "Times-Roman",
  });
  registerFonts(doc);
  const canvas = new Canvas(doc);
  const model = buildModel(input);
  return { model, pages: paginate(canvas, model) };
}

/** A canvas over a fresh document with the report's fonts (for text measurement tests). */
export function testCanvas(): Canvas {
  const doc = new PDFDocument({
    size: [792, 612],
    margin: 0,
    autoFirstPage: false,
    font: "Times-Roman",
  });
  registerFonts(doc);
  return new Canvas(doc);
}

/** Text of each page of a PDF. */
export async function pageTexts(bytes: Uint8Array): Promise<string[]> {
  const pdf = await getDocumentProxy(new Uint8Array(bytes));
  const { text } = await extractText(pdf, { mergePages: false });
  return text;
}
