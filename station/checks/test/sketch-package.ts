// The box room as a sketch capture, built in memory (spec F14 AC6): capture record 1.2.0 with
// `captureSource: sketch`, the scan originals (roomplan.json, depth-samples.bin, points.las)
// replaced by the sketch image and the entered measurements, manifest 1.2.0, the capture model's
// confidences set per scenario, every changed file re-fingerprinted. Shared by sketch.test.ts and
// the single-change variants.

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
function length(valueMm: number, measured = true): SketchMeasurements["ceilingHeight"] {
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

/** The box room as a sketch capture. */
export function sketchPackage(scenario: Scenario): LoadedPackage {
  const lowWalls = new Set(scenario.lowWalls ?? []);
  const lowOpenings = new Set(scenario.lowOpenings ?? []);
  let pkg = withJson<CaptureRecord>(box, RECORD_PATH, (record) => {
    record.schemaVersion = "1.2.0";
    for (const capture of record.captures) {
      delete capture.heading;
      delete capture.headingAccuracy;
      delete capture.headingSource;
      delete capture.headingRecordedAt;
      delete capture.headingIssue;
      capture.captureSource = "sketch";
      capture.sketch = structuredClone(scenario.sketch);
    }
  });
  pkg = withJson<CaptureModel>(pkg, MODEL_PATH, (model) => {
    model.refs = [];
    for (const wall of model.walls) {
      wall.confidence = lowWalls.has(wall.id) ? "low" : "high";
      if (scenario.heightM !== undefined) {
        wall.heightM = scenario.heightM;
      }
    }
    for (const item of [...model.doors, ...model.windows, ...model.openings]) {
      item.confidence = lowOpenings.has(item.id) ? "low" : "high";
    }
    for (const room of model.rooms) {
      if (scenario.heightM !== undefined) {
        room.heightM = scenario.heightM;
      }
    }
  });
  // The originals: the scan files go, the sketch files come, the model derives from them.
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
  const image = box.files.get(pathOf(box, "photo")) as Uint8Array;
  const measurements = encoder.encode(JSON.stringify(boxMeasurements(), null, 2));
  const originals: Array<[string, Uint8Array, PackageManifest["files"][number]["role"], string]> = [
    [IMAGE_PATH, image, "sketch_image", "image/jpeg"],
    [MEASUREMENTS_PATH, measurements, "sketch_measurements", "application/json"],
  ];
  const modelIndex = manifest.files.findIndex((file) => file.role === "capture_model");
  for (const [path, bytes, role, mime] of originals) {
    const skip =
      (role === "sketch_image" && scenario.withoutImage === true) ||
      (role === "sketch_measurements" && scenario.withoutMeasurements === true);
    if (skip) {
      continue;
    }
    files.set(path, bytes);
    manifest.files.splice(modelIndex, 0, {
      path,
      role,
      captureId: CAPTURE_ID,
      areaKey: AREA_KEY,
      sha256: sha256(bytes),
      bytes: bytes.length,
      mime,
      generator: "chapter-capture-ios/SketchCapture",
      generatorVersion: "1.0.0 (42)",
      derivedFrom: [],
    });
  }
  const model = manifest.files.find((file) => file.role === "capture_model");
  if (model !== undefined) {
    model.derivedFrom = [MEASUREMENTS_PATH, IMAGE_PATH];
  }
  files.set(pkg.manifestPath, encoder.encode(JSON.stringify(manifest, null, 2)));
  const built = packageFromFiles(files);
  return scenario.withoutModel === true ? withoutFile(built, MODEL_PATH) : built;
}
