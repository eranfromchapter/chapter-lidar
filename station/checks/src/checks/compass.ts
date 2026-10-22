// Check 5b: orientation (compass), compass spec 8.2. A capture record 1.1.0 carries, per capture,
// the phone's compass reading of the scan start (heading, accuracy, source and time) or why there
// is none. The contract's evaluator `compassState` (the one the plan sheet, the spatial report and
// the web use) grades each capture:
// - verified or approximate: info; the plans carry a north arrow.
// - not verified: a limitation, "Plan orientation is not verified; north is not shown.", with the
//   reason. Its next action is None: a reading cannot be added to a finished scan.
// A capture scanned before the app read the compass has none of the compass fields (owner question
// Q-B): every capture of a capture record 1.0.0, and in a 1.1.0 record a capture carried over from
// a revision written before the compass or scanned by a build that does not read it (the app
// writes a reading or `headingIssue` for every capture it scans with the compass). With
// COMPASS_LIMITATION_FOR_LEGACY_RECORDS false such a capture is not graded:
// it gets the info finding of a 1.0.0 record, and the check is not applicable when no capture is
// graded, so older packages and their revisions keep their verdict; true grades it as above (no
// compass reading). Without a capture record the check is not applicable and says nothing (checks
// 2 and 3 report it).

import {
  COMPASS_VERIFIED_MAX,
  compassDetail,
  compassState,
  type Capture,
  type CaptureRecord,
} from "@chapter/capture-contract";
import type { CheckContext } from "../context.js";
import { NO_ACTION, finding, scopeOf } from "../finding.js";
import type { CheckOutput, StationFinding } from "../types.js";

/**
 * Owner question Q-B. false (the default): a capture scanned before the app read the compass is
 * not graded (one info finding; the check is not applicable when no capture is graded). true:
 * every such capture is a limitation (no compass reading), which makes every package from an app
 * before the compass, and every revision carrying such a capture over, Limited.
 */
export const COMPASS_LIMITATION_FOR_LEGACY_RECORDS = false;

/** The limitation of a not-verified orientation, as the verdict lists it (compass spec 1.4). */
export const ORIENTATION_NOT_VERIFIED = "Plan orientation is not verified; north is not shown.";

/** What the rule expects of every capture. */
export const COMPASS_EXPECTED = `a compass reading at scan start, true north, accuracy ±${COMPASS_VERIFIED_MAX}° or better`;

/** The capture record version written before the app read the compass. */
const LEGACY_RECORD_VERSION: CaptureRecord["schemaVersion"] = "1.0.0";

/** The capture fields capture record 1.1.0 added for the compass. */
const COMPASS_FIELDS = [
  "heading",
  "headingAccuracy",
  "headingSource",
  "headingRecordedAt",
  "headingIssue",
] as const satisfies ReadonlyArray<keyof Capture>;

/**
 * The info finding of a capture scanned before the app read the compass (Q-B, compass G4): the
 * contract's no-reading phrase, which is the drawn sample's wording. No full stop, unlike the other
 * messages: the checks table and the web row show it as drawn.
 */
const LEGACY_MESSAGE = compassDetail({ kind: "not_verified", reason: "no_reading" });

export interface CompassPolicy {
  /** Grade the captures scanned before the app read the compass too (Q-B); otherwise not graded. */
  limitationForLegacyRecords: boolean;
}

/**
 * True for a capture scanned before the app read the compass: it has none of the compass fields.
 * Every capture of a 1.0.0 record is one. In a 1.1.0 record it is a capture carried over from a
 * revision written before the compass (or scanned by such an app, or by a build without the
 * compass service, and sealed by a later one): the app writes the reading, or `headingIssue` when
 * there is none, for every capture it scans with the compass.
 */
export function scannedBeforeCompass(
  capture: Pick<Capture, (typeof COMPASS_FIELDS)[number]>,
): boolean {
  return COMPASS_FIELDS.every((field) => capture[field] === undefined);
}

/**
 * Why a reading was rejected by the time rule (compass spec 1.2 rule 5): its time and the scan's.
 * Undefined for any other state (a rejected reading without a heading is the phone's verdict).
 */
function timeNote(capture: Capture): string | undefined {
  if (capture.heading === undefined || capture.headingRecordedAt === undefined) {
    return undefined;
  }
  const scan =
    capture.finishedAt === undefined
      ? `scan from ${capture.capturedAt} with no finish time`
      : `scan ${capture.capturedAt} to ${capture.finishedAt}`;
  return `reading at ${capture.headingRecordedAt}, ${scan}`;
}

function captureFinding(capture: Capture, filePath: string): StationFinding {
  const state = compassState(capture);
  const base = {
    ruleId: "orientation.compass" as const,
    filePath,
    nextAction: NO_ACTION,
    ...scopeOf(capture),
    expected: COMPASS_EXPECTED,
  };
  switch (state.kind) {
    case "verified":
      return finding({
        ...base,
        severity: "info",
        message: "True north from the compass.",
        measured: compassDetail(state),
      });
    case "approximate":
      return finding({
        ...base,
        severity: "info",
        message: "North is approximate.",
        measured: compassDetail(state),
      });
    case "not_verified": {
      const note = state.reason === "rejected" ? timeNote(capture) : undefined;
      return finding({
        ...base,
        severity: "limitation",
        message: ORIENTATION_NOT_VERIFIED,
        measured: `${compassDetail(state)}${note === undefined ? "" : ` (${note})`}`,
      });
    }
  }
}

/**
 * The info finding of a capture of a 1.1.0 record scanned before the app read the compass: the
 * 1.0.0 record's finding, for that capture. Nothing is expected of it.
 */
function legacyCaptureFinding(
  capture: Capture,
  record: CaptureRecord,
  filePath: string,
): StationFinding {
  return finding({
    ruleId: "orientation.compass",
    severity: "info",
    message: LEGACY_MESSAGE,
    filePath,
    measured: `scanned before the app read the compass (no compass fields in capture record ${record.schemaVersion})`,
    nextAction: NO_ACTION,
    ...scopeOf(capture),
  });
}

/** The compass check under a Q-B policy. The station runs `checkCompass` (the constant). */
export function compassCheck(policy: CompassPolicy): (ctx: CheckContext) => CheckOutput {
  return (ctx) => {
    const record = ctx.pkg.captureRecord;
    if (record === undefined) {
      return { findings: [], notApplicable: true };
    }
    const filePath = ctx.recordPath();
    if (policy.limitationForLegacyRecords) {
      return { findings: record.captures.map((capture) => captureFinding(capture, filePath)) };
    }
    if (record.schemaVersion === LEGACY_RECORD_VERSION) {
      const labels = record.captures.map((capture) => capture.label).join(", ");
      return {
        findings: [
          finding({
            ruleId: "orientation.compass",
            severity: "info",
            message: LEGACY_MESSAGE,
            filePath,
            measured: `capture record ${record.schemaVersion}, written before the app read the compass (${labels})`,
            nextAction: NO_ACTION,
          }),
        ],
        notApplicable: true,
      };
    }
    const findings = record.captures.map((capture) =>
      scannedBeforeCompass(capture)
        ? legacyCaptureFinding(capture, record, filePath)
        : captureFinding(capture, filePath),
    );
    return record.captures.every(scannedBeforeCompass)
      ? { findings, notApplicable: true }
      : { findings };
  };
}

/** Check 5b as the station runs it. */
export const checkCompass = compassCheck({
  limitationForLegacyRecords: COMPASS_LIMITATION_FOR_LEGACY_RECORDS,
});
