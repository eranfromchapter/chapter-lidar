// Orientation words of the review screen (compass spec §9, web-review addendum D1). The state of
// each capture comes from the contract's evaluator (`compassState`, the one the station and the
// spatial report use); this file only holds the web's sentence templates.

import {
  compassState,
  compassWord,
  formatAccuracy,
  formatHeading,
  type CompassReason,
  type CompassState,
} from "@chapter/capture-contract";
import type { CaptureRecord } from "./station-types";

type Capture = CaptureRecord["captures"][number];

/** The phrase of a not-verified reason in the plan card sentence. */
function reasonPhrase(reason: CompassReason, accuracy: number | undefined): string {
  switch (reason) {
    case "no_reading":
      return "no compass reading";
    case "rejected":
      return "the compass reading was rejected";
    case "inaccurate":
      return `compass accuracy ±${formatAccuracy(accuracy ?? 0)}°`;
    case "not_calibrated":
      return "the compass was not calibrated";
    case "unavailable":
      return "no compass on the phone";
  }
}

/** Plan card "Orientation" value of one state. */
export function orientationSentence(state: CompassState): string {
  switch (state.kind) {
    case "verified":
      return `Verified · true north from the compass, ±${formatAccuracy(state.accuracy)}°. The plan sheet shows the north arrow.`;
    case "approximate":
      return `Approximate · compass ±${formatAccuracy(state.accuracy)}°, ${
        state.source === "true" ? "true north" : "magnetic north"
      }. The plan sheet shows an approximate north arrow.`;
    case "not_verified":
      return `Not verified · ${reasonPhrase(state.reason, state.accuracy)}. North is not shown.`;
  }
}

/** Plan card "Orientation" value of one capture. */
export function orientationText(capture: Capture): string {
  return orientationSentence(compassState(capture));
}

/** Capture record "Compass" value of a visit with one capture. */
export function compassRecordSentence(state: CompassState): string {
  switch (state.kind) {
    case "verified":
      return `Verified · ${formatHeading(state.heading)}° true, ±${formatAccuracy(state.accuracy)}°`;
    case "approximate":
      return `Approximate · ${formatHeading(state.heading)}° ${state.source}, ±${formatAccuracy(state.accuracy)}°`;
    case "not_verified":
      switch (state.reason) {
        case "rejected":
          return "Rejected · orientation not verified";
        case "inaccurate":
          return `±${formatAccuracy(state.accuracy ?? 0)}° · orientation not verified`;
        case "no_reading":
        case "not_calibrated":
        case "unavailable":
          return "Not read · orientation not verified";
      }
  }
}

/**
 * Capture record "Compass" value of a visit: the one capture's sentence, or with several
 * captures each capture's word ("Floor 1 verified · Floor 2 not read").
 */
export function compassRecordText(record: CaptureRecord): string {
  const [only] = record.captures;
  if (record.captures.length === 1 && only !== undefined) {
    return compassRecordSentence(compassState(only));
  }
  return record.captures
    .map((capture) => `${capture.label} ${compassWord(compassState(capture))}`)
    .join(" · ");
}
