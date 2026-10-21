// The compass reading of one capture (capture record 1.1.0): its state, the north symbol drawn on
// plans and the station and web phrases. One evaluator for the station, the spatial report and
// the web; the Swift CaptureContract (Compass.swift) implements the same rules, and both run
// contract/test-vectors/compass-states.json.
//
// Rules, in order (compass spec 1.2):
//   1-4. no heading: headingIssue rejected / not_calibrated / unavailable, else no_reading
//   5.   headingRecordedAt outside [capturedAt - 60 s, (finishedAt ?? capturedAt + 24 h) + 60 s]: rejected
//   6.   headingAccuracy > 30: inaccurate
//   7.   true and headingAccuracy <= 10: verified
//   8.   otherwise (true 11-30, magnetic <= 30): approximate
// A heading without its accuracy, source or time (not a valid 1.1.0 record) is rejected.

import type { Capture } from "./generated/capture-record.js";

/** Highest accuracy, in whole degrees, of a verified reading (true north only). */
export const COMPASS_VERIFIED_MAX = 10;
/** Highest accuracy, in whole degrees, of a usable (verified or approximate) reading. */
export const COMPASS_APPROXIMATE_MAX = 30;

/** How far the reading time may lie outside the scan, in seconds (rule 5). */
const READING_SLACK_S = 60;
/** End of the scan when the capture has no finishedAt, in seconds after capturedAt (rule 5). */
const OPEN_SCAN_S = 24 * 60 * 60;

/** `true`: corrected to true north with the phone's location; `magnetic`: magnetic north only. */
export type HeadingSource = NonNullable<Capture["headingSource"]>;
/** Why a capture has no heading although the app tried. */
export type HeadingIssue = NonNullable<Capture["headingIssue"]>;

/** Why an orientation is not verified. */
export type CompassReason =
  "no_reading" | "rejected" | "inaccurate" | "not_calibrated" | "unavailable";

export type CompassState =
  | { kind: "verified"; heading: number; accuracy: number; source: "true" }
  | { kind: "approximate"; heading: number; accuracy: number; source: HeadingSource }
  /** `accuracy` is present for the reason `inaccurate` only. */
  | { kind: "not_verified"; reason: CompassReason; accuracy?: number };

/** The capture fields the evaluator reads. A whole `Capture` qualifies. */
export type CompassFields = Pick<
  Capture,
  | "capturedAt"
  | "finishedAt"
  | "heading"
  | "headingAccuracy"
  | "headingSource"
  | "headingRecordedAt"
  | "headingIssue"
>;

/** The symbol drawn on a plan: an arrow for a usable reading, the text box otherwise. */
export type NorthSymbol =
  | {
      kind: "arrow";
      /** Counter-clockwise from "up" on the page, degrees in [0, 360). */
      angleCcw: number;
      /** Dashed ring and hollow arrow. */
      approximate: boolean;
      lines: [string, string];
    }
  | { kind: "box"; box: "Orientation: not verified"; caption: string };

/** Words of a capture's state in summaries ("Floor 1 verified · Floor 2 not read"). */
export type CompassWord = "verified" | "approximate" | "not verified" | "not read";

export const NOT_VERIFIED_BOX = "Orientation: not verified";

function seconds(timestamp: string): number {
  return Date.parse(timestamp) / 1000;
}

/** The state of one capture's orientation (compass spec 1.2). */
export function compassState(capture: CompassFields): CompassState {
  const { heading, headingAccuracy: accuracy, headingSource: source } = capture;
  const recordedAt = capture.headingRecordedAt;
  if (heading === undefined) {
    switch (capture.headingIssue) {
      case "rejected":
        return { kind: "not_verified", reason: "rejected" };
      case "not_calibrated":
        return { kind: "not_verified", reason: "not_calibrated" };
      case "unavailable":
        return { kind: "not_verified", reason: "unavailable" };
      default:
        return { kind: "not_verified", reason: "no_reading" };
    }
  }
  if (accuracy === undefined || source === undefined || recordedAt === undefined) {
    return { kind: "not_verified", reason: "rejected" };
  }
  const start = seconds(capture.capturedAt);
  const end = capture.finishedAt === undefined ? start + OPEN_SCAN_S : seconds(capture.finishedAt);
  const read = seconds(recordedAt);
  if (!(read >= start - READING_SLACK_S && read <= end + READING_SLACK_S)) {
    return { kind: "not_verified", reason: "rejected" };
  }
  if (accuracy > COMPASS_APPROXIMATE_MAX) {
    return { kind: "not_verified", reason: "inaccurate", accuracy };
  }
  if (source === "true" && accuracy <= COMPASS_VERIFIED_MAX) {
    return { kind: "verified", heading, accuracy, source };
  }
  return { kind: "approximate", heading, accuracy, source };
}

/** True for a verified or approximate state: the plans carry an arrow. */
export function isUsable(state: CompassState): boolean {
  return state.kind !== "not_verified";
}

function normalized(degrees: number): number {
  const turned = degrees % 360;
  return turned < 0 ? turned + 360 : turned;
}

/**
 * `{HDG}`: a bearing rounded half up to a whole degree, then mod 360, as digits without the
 * degree sign. 212.4 -> "212", 359.6 -> "0", never "360".
 */
export function formatHeading(degrees: number): string {
  return String(normalized(Math.floor(normalized(degrees) + 0.5)));
}

/** `{ACC}`: the stored accuracy (whole degrees) as digits without the sign. */
export function formatAccuracy(accuracy: number): string {
  return String(accuracy);
}

/** Caption under the "Orientation: not verified" box (compass spec 1.4). */
export function reasonCaption(reason: CompassReason, accuracy?: number): string {
  switch (reason) {
    case "no_reading":
      return "No compass reading";
    case "rejected":
      return "Reading rejected";
    case "inaccurate":
      return `Compass accuracy ±${formatAccuracy(accuracy ?? 0)}°`;
    case "not_calibrated":
      return "Compass not calibrated";
    case "unavailable":
      return "Compass unavailable";
  }
}

/**
 * The north symbol of a drawing that shows the plan turned counter-clockwise by
 * `drawingRotationCcw` degrees. The arrow angle and the caption's `{HDG}` are both
 * A = (heading + rotation) mod 360, the bearing of "up" on that drawing (compass spec 2.5).
 */
export function northSymbol(state: CompassState, drawingRotationCcw = 0): NorthSymbol {
  if (state.kind === "not_verified") {
    return {
      kind: "box",
      box: NOT_VERIFIED_BOX,
      caption: reasonCaption(state.reason, state.accuracy),
    };
  }
  const angleCcw = normalized(state.heading + drawingRotationCcw);
  const accuracy = `±${formatAccuracy(state.accuracy)}°`;
  if (state.kind === "verified") {
    return {
      kind: "arrow",
      angleCcw,
      approximate: false,
      lines: ["True north · compass", `${accuracy} · ${formatHeading(angleCcw)}°`],
    };
  }
  return {
    kind: "arrow",
    angleCcw,
    approximate: true,
    lines: ["Approx. north · compass", `${accuracy} · ${state.source}`],
  };
}

/** Station detail and web phrase of a state (compass spec 1.4); `{HDG}` is the stored heading. */
export function compassDetail(state: CompassState): string {
  switch (state.kind) {
    case "verified":
      return `True heading ${formatHeading(state.heading)}°, accuracy ±${formatAccuracy(state.accuracy)}°`;
    case "approximate":
      return `Approximate north: ${state.source} heading ${formatHeading(state.heading)}°, accuracy ±${formatAccuracy(state.accuracy)}°`;
    case "not_verified":
      switch (state.reason) {
        case "no_reading":
          return "No compass reading recorded; orientation not verified";
        case "rejected":
          return "Compass reading rejected; orientation not verified";
        case "inaccurate":
          return `Compass accuracy ±${formatAccuracy(state.accuracy ?? 0)}°; orientation not verified`;
        case "not_calibrated":
          return "Compass not calibrated; orientation not verified";
        case "unavailable":
          return "No compass on the device; orientation not verified";
      }
  }
}

/**
 * The summary word of a state: `not verified` when a reading was taken but is not usable
 * (inaccurate, rejected), `not read` when there was none (compass spec 5.3).
 */
export function compassWord(state: CompassState): CompassWord {
  switch (state.kind) {
    case "verified":
      return "verified";
    case "approximate":
      return "approximate";
    case "not_verified":
      return state.reason === "inaccurate" || state.reason === "rejected"
        ? "not verified"
        : "not read";
  }
}
