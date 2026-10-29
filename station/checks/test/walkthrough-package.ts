// The box room as an AR walkthrough capture, built in memory (spec F15 AC5): capture record 1.2.0
// with `captureSource: walkthrough`, the `sketch` and `walkthrough` summaries and no compass field;
// the scan originals replaced by the walkthrough video, the walkthrough log (the contract's
// two-rooms example adapted to the box room's ids) and the sketch measurements derived from it
// (source kind ar_walkthrough); manifest 1.2.0; every changed file re-fingerprinted.

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { Capture, WalkthroughLog } from "@chapter/capture-contract";
import type { LoadedPackage } from "../src/types.js";
import {
  AREA_KEY,
  CAPTURE_ID,
  COMPLETE,
  MEASUREMENTS_PATH,
  boxMeasurements,
  boxRecord,
  measuredPlanPackage,
  type Original,
  type Scenario,
  type Sketch,
} from "./sketch-package.js";

export type Walkthrough = NonNullable<Capture["walkthrough"]>;

const here = dirname(fileURLToPath(import.meta.url));
const EXAMPLE = resolve(
  here,
  "..",
  "..",
  "..",
  "contract",
  "examples",
  "walkthrough-log",
  "valid",
  "two-rooms.json",
);

const ORIGINALS = `Original Exports/${AREA_KEY}/${CAPTURE_ID}`;
export const VIDEO_PATH = `${ORIGINALS}/walkthrough.mp4`;
export const LOG_PATH = `${ORIGINALS}/walkthrough-log.json`;

const encoder = new TextEncoder();

/** A tape-checked walk with a small loop gap and half a second of limited tracking. */
export const TAPED: Walkthrough = {
  scaleSource: "tape",
  scaleFactor: 0.99725,
  loopClosureMm: 38.3,
  trackingLimitedSeconds: 0.5,
  recorded: true,
};

/** A walk whose scale is the phone's own (no tape check). */
export const AR_SCALE: Walkthrough = {
  scaleSource: "ar",
  loopClosureMm: 22,
  trackingLimitedSeconds: 0,
  recorded: true,
};

/**
 * The smallest ISO base media file the station reads as one: a 24-byte ftyp box (major brand
 * isom, minor version 0x200, compatible brands isom and iso2) and an empty free box.
 */
export function isoMediaBytes(): Uint8Array {
  const bytes = new Uint8Array(32);
  const view = new DataView(bytes.buffer);
  const ascii = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i += 1) {
      bytes[offset + i] = text.charCodeAt(i);
    }
  };
  view.setUint32(0, 24);
  ascii(4, "ftyp");
  ascii(8, "isom");
  view.setUint32(12, 0x200);
  ascii(16, "isom");
  ascii(20, "iso2");
  view.setUint32(24, 8);
  ascii(28, "free");
  return bytes;
}

/**
 * The walkthrough log of the box room: the contract's two-rooms example with the box room's visit,
 * capture and area, its first room (a 4 x 3 m rectangle with a door, a window and a tape check of
 * wall 0) renamed Test Room, the closet left out. Without the video block when nothing was recorded.
 */
export function boxWalkthroughLog(recorded = true): WalkthroughLog {
  const log = JSON.parse(readFileSync(EXAMPLE, "utf8")) as WalkthroughLog;
  log.visitId = boxRecord.visitId;
  log.captureId = CAPTURE_ID;
  log.areaKey = AREA_KEY;
  if (recorded && log.video !== undefined) {
    log.video.path = VIDEO_PATH;
  } else {
    delete log.video;
  }
  const room = log.rooms[0] as WalkthroughLog["rooms"][number];
  room.label = "Test Room";
  log.rooms = [room];
  return log;
}

export interface WalkthroughScenario extends Omit<
  Scenario,
  "sketch" | "withoutImage" | "withoutMeasurements"
> {
  walkthrough: Walkthrough;
  /** The record's sketch summary; COMPLETE when omitted. */
  sketch?: Sketch;
  /** Leave the walkthrough log out of the package. */
  withoutLog?: boolean;
  /** Leave the video out of the package. */
  withoutVideo?: boolean;
  /** Leave the sketch measurements out of the package. */
  withoutMeasurements?: boolean;
  /** Bytes of the video file; a minimal ISO media file when omitted. */
  videoBytes?: Uint8Array;
}

/** The box room as an AR walkthrough capture. */
export function walkthroughPackage(scenario: WalkthroughScenario): LoadedPackage {
  const sketch = scenario.sketch ?? COMPLETE;
  const measurements = boxMeasurements();
  measurements.source = { kind: "ar_walkthrough", path: LOG_PATH };
  const log = boxWalkthroughLog(scenario.walkthrough.recorded);
  const originals: Original[] = [];
  if (scenario.withoutVideo !== true) {
    originals.push({
      path: VIDEO_PATH,
      bytes: scenario.videoBytes ?? isoMediaBytes(),
      role: "walkthrough_video",
      mime: "video/mp4",
    });
  }
  if (scenario.withoutLog !== true) {
    originals.push({
      path: LOG_PATH,
      bytes: encoder.encode(JSON.stringify(log, null, 2)),
      role: "walkthrough_log",
      mime: "application/json",
    });
  }
  if (scenario.withoutMeasurements !== true) {
    originals.push({
      path: MEASUREMENTS_PATH,
      bytes: encoder.encode(JSON.stringify(measurements, null, 2)),
      role: "sketch_measurements",
      mime: "application/json",
      derivedFrom: [LOG_PATH],
    });
  }
  return measuredPlanPackage({
    ...scenario,
    source: {
      captureSource: "walkthrough",
      sketch: structuredClone(sketch),
      walkthrough: structuredClone(scenario.walkthrough),
    },
    originals,
    modelDerivedFrom: [MEASUREMENTS_PATH, LOG_PATH],
  });
}
