// The box room as a sketch capture, built in memory (spec F14 AC6): capture record 1.2.0 with
// `captureSource: sketch`, the scan originals (roomplan.json, depth-samples.bin, points.las)
// replaced by the sketch image and the entered measurements, manifest 1.2.0, the capture model's
// confidences set per scenario, every changed file re-fingerprinted. Shared by sketch.test.ts and
// the single-change variants; the builder (measuredPlanPackage) also makes the AR walkthrough
// package of walkthrough-package.ts.

import { createHash } from "node:crypto";
import type {
  Capture,
  CaptureModel,
  CaptureRecord,
  PackageManifest,
  SketchMeasurements,
} from "@chapter/capture-contract";
import { packageFromFiles } from "../src/package.js";
import type { LoadedPackage } from "../src/types.js";
import { jsonOf, loadGood, pathOf, withJson, withoutFile } from "./helpers.js";

export const box = loadGood("box-room");
export const boxRecord = jsonOf<CaptureRecord>(box, pathOf(box, "capture_record"));
const boxCapture = boxRecord.captures[0] as Capture;
export const CAPTURE_ID = boxCapture.captureId;
export const AREA_KEY = boxCapture.areaKey;
const ORIGINALS = `Original Exports/${AREA_KEY}/${CAPTURE_ID}`;
export const IMAGE_PATH = `${ORIGINALS}/sketch.jpg`;
export const MEASUREMENTS_PATH = `${ORIGINALS}/sketch-measurements.json`;
export const MODEL_PATH = pathOf(box, "capture_model");
export const RECORD_PATH = pathOf(box, "capture_record");

const encoder = new TextEncoder();
const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

export type Sketch = NonNullable<Capture["sketch"]>;

export const COMPLETE: Sketch = {
  measurements: "complete",
  wallsMeasured: 4,
  wallsEstimated: 0,
  ceilingHeightSource: "measured",
  closureResidualMm: 8,
};

/** A length as the operator entered it, in millimetres. */
function length(
  valueMm: number,
  measured = true,
): NonNullable<SketchMeasurements["ceilingHeight"]> {
  return { valueMm, enteredUnit: "mm", enteredText: String(valueMm), measured };
}

/** The entered measurements of the box room (4.000 x 3.000 m, one door, one window). */
export function boxMeasurements(): SketchMeasurements {
  return {
    schemaVersion: "1.0.0",
    visitId: boxRecord.visitId,
    captureId: CAPTURE_ID,
    areaKey: AREA_KEY,
    displayUnits: "metric",
    source: { kind: "hand_sketch", path: IMAGE_PATH },
    ceilingHeight: length(2700),
    rooms: [
      {
        id: "room-1",
        label: "Test Room",
        walls: [
          { id: "wall-1", length: length(3000), exterior: true },
          { id: "wall-2", length: length(4000), exterior: true },
          { id: "wall-3", length: length(3000) },
          { id: "wall-4", length: length(4000) },
        ],
        diagonals: [{ from: 0, to: 2, length: length(5000) }],
        openings: [
          {
            id: "door-1",
            kind: "door",
            wallId: "wall-4",
            width: length(900),
            fromCorner: "start",
            fromCornerDistance: length(2550),
          },
          {
            id: "window-1",
            kind: "window",
            wallId: "wall-2",
            width: length(1200),
            sill: length(900),
            height: length(1200),
            fromCorner: "start",
            fromCornerDistance: length(1400),
          },
        ],
      },
    ],
  };
}

export interface Scenario {
  sketch: Sketch;
  /** Walls of the model marked low confidence (estimated). */
  lowWalls?: readonly string[];
  /** Doors, windows or openings of the model marked low confidence. */
  lowOpenings?: readonly string[];
  /** Ceiling height of every room and wall (the solver's default when assumed). */
  heightM?: number;
  /** Leave the entered measurements out of the package. */
  withoutMeasurements?: boolean;
  /** Leave the sketch image out of the package. */
  withoutImage?: boolean;
  /** Leave the capture model out of the package. */
  withoutModel?: boolean;
}

/** One original file of a sketch or walkthrough capture, added before the capture model. */
export interface Original {
  path: string;
  bytes: Uint8Array;
  role: PackageManifest["files"][number]["role"];
  mime: string;
  derivedFrom?: string[];
}

/** How the box room is rebuilt as a capture measured without LiDAR. */
export interface MeasuredPlanBuild extends Pick<
  Scenario,
  "lowWalls" | "lowOpenings" | "heightM" | "withoutModel"
> {
  /** The capture record's fields for the source: captureSource, sketch, walkthrough. */
  source: Pick<Capture, "captureSource" | "sketch" | "walkthrough">;
  /** The originals that replace the scan files, in manifest order. */
  originals: readonly Original[];
  /** derivedFrom of the capture model. */
  modelDerivedFrom: string[];
}

/** The box room with the scan originals replaced, record and manifest 1.2.0, re-fingerprinted. */
export function measuredPlanPackage(build: MeasuredPlanBuild): LoadedPackage {
  const lowWalls = new Set(build.lowWalls ?? []);
  const lowOpenings = new Set(build.lowOpenings ?? []);
  let pkg = withJson<CaptureRecord>(box, RECORD_PATH, (record) => {
    record.schemaVersion = "1.2.0";
    for (const capture of record.captures) {
      delete capture.heading;
      delete capture.headingAccuracy;
      delete capture.headingSource;
      delete capture.headingRecordedAt;
      delete capture.headingIssue;
      Object.assign(capture, structuredClone(build.source));
    }
  });
  pkg = withJson<CaptureModel>(pkg, MODEL_PATH, (model) => {
    model.refs = [];
    for (const wall of model.walls) {
      wall.confidence = lowWalls.has(wall.id) ? "low" : "high";
      if (build.heightM !== undefined) {
        wall.heightM = build.heightM;
      }
    }
    for (const item of [...model.doors, ...model.windows, ...model.openings]) {
      item.confidence = lowOpenings.has(item.id) ? "low" : "high";
    }
    for (const room of model.rooms) {
      if (build.heightM !== undefined) {
        room.heightM = build.heightM;
      }
    }
  });
  // The originals: the scan files go, the new originals come, the model derives from them.
  const files = new Map(pkg.files);
  const manifest = structuredClone(pkg.manifest);
  const dropped = new Set(["raw_roomplan_json", "raw_depth", "point_cloud_las"]);
  for (const entry of manifest.files.filter((file) => dropped.has(file.role))) {
    files.delete(entry.path);
  }
  manifest.files = manifest.files.filter(
    (file) => !dropped.has(file.role),
  ) as PackageManifest["files"];
  manifest.schemaVersion = "1.2.0";
  // Each original goes in just before the model, so the last one listed comes first.
  const modelIndex = manifest.files.findIndex((file) => file.role === "capture_model");
  for (const original of build.originals) {
    files.set(original.path, original.bytes);
    manifest.files.splice(modelIndex, 0, {
      path: original.path,
      role: original.role,
      captureId: CAPTURE_ID,
      areaKey: AREA_KEY,
      sha256: sha256(original.bytes),
      bytes: original.bytes.length,
      mime: original.mime,
      generator: "chapter-capture-ios/SketchCapture",
      generatorVersion: "1.0.0 (42)",
      derivedFrom: original.derivedFrom ?? [],
    });
  }
  const model = manifest.files.find((file) => file.role === "capture_model");
  if (model !== undefined) {
    model.derivedFrom = build.modelDerivedFrom;
  }
  files.set(pkg.manifestPath, encoder.encode(JSON.stringify(manifest, null, 2)));
  const built = packageFromFiles(files);
  return build.withoutModel === true ? withoutFile(built, MODEL_PATH) : built;
}

/** The box room as a sketch capture. */
export function sketchPackage(scenario: Scenario): LoadedPackage {
  const image = box.files.get(pathOf(box, "photo")) as Uint8Array;
  const measurements = encoder.encode(JSON.stringify(boxMeasurements(), null, 2));
  const originals: Original[] = [];
  if (scenario.withoutImage !== true) {
    originals.push({ path: IMAGE_PATH, bytes: image, role: "sketch_image", mime: "image/jpeg" });
  }
  if (scenario.withoutMeasurements !== true) {
    originals.push({
      path: MEASUREMENTS_PATH,
      bytes: measurements,
      role: "sketch_measurements",
      mime: "application/json",
    });
  }
  return measuredPlanPackage({
    ...scenario,
    source: { captureSource: "sketch", sketch: structuredClone(scenario.sketch) },
    originals,
    modelDerivedFrom: [MEASUREMENTS_PATH, IMAGE_PATH],
  });
}
