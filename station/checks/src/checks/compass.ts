// Check 5b: orientation (compass), compass spec 8.2. A capture record 1.1.0 carries, per capture,
// the phone's compass reading of the scan start (heading, accuracy, source and time) or why there
// is none. The contract's evaluator `compassState` (the one the plan sheet, the spatial report and
// the web use) grades each capture:
// - verified or approximate: info; the plans carry a north arrow.
// - not verified: a limitation, "Plan orientation is not verified; north is not shown.", with the
//   reason. Its next action is None: a reading cannot be added to a finished scan.
// A capture record 1.0.0 comes from an app that never read the compass (owner question Q-B): with
// COMPASS_LIMITATION_FOR_LEGACY_RECORDS false the check is not applicable with one info finding,
// so older packages keep their verdict; true grades its captures as above (no compass reading).
// Without a capture record the check is not applicable and says nothing (checks 2 and 3 report it).

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
 * Owner question Q-B. false (the default): a capture record 1.0.0 makes the check not applicable
 * with one info finding. true: every capture of a 1.0.0 record is a limitation (no compass
 * reading), which makes every package from an app before the compass Limited.
 */
export const COMPASS_LIMITATION_FOR_LEGACY_RECORDS = false;

/** The limitation of a not-verified orientation, as the verdict lists it (compass spec 1.4). */
export const ORIENTATION_NOT_VERIFIED = "Plan orientation is not verified; north is not shown.";

/** What the rule expects of every capture. */
export const COMPASS_EXPECTED = `a compass reading at scan start, true north, accuracy ±${COMPASS_VERIFIED_MAX}° or better`;

/** The capture record version written before the app read the compass. */
const LEGACY_RECORD_VERSION: CaptureRecord["schemaVersion"] = "1.0.0";

export interface CompassPolicy {
  /** Grade the captures of a capture record 1.0.0 too (Q-B); otherwise not applicable. */
  limitationForLegacyRecords: boolean;
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

/** The compass check under a Q-B policy. The station runs `checkCompass` (the constant). */
export function compassCheck(policy: CompassPolicy): (ctx: CheckContext) => CheckOutput {
  return (ctx) => {
    const record = ctx.pkg.captureRecord;
    if (record === undefined) {
      return { findings: [], notApplicable: true };
    }
    const filePath = ctx.recordPath();
    if (record.schemaVersion === LEGACY_RECORD_VERSION && !policy.limitationForLegacyRecords) {
      const labels = record.captures.map((capture) => capture.label).join(", ");
      return {
        findings: [
          finding({
            ruleId: "orientation.compass",
            severity: "info",
            message: "No compass reading recorded; orientation not verified.",
            filePath,
            measured: `capture record ${record.schemaVersion}, written before the app read the compass (${labels})`,
            nextAction: NO_ACTION,
          }),
        ],
        notApplicable: true,
      };
    }
    return { findings: record.captures.map((capture) => captureFinding(capture, filePath)) };
  };
}

/** Check 5b as the station runs it. */
export const checkCompass = compassCheck({
  limitationForLegacyRecords: COMPASS_LIMITATION_FOR_LEGACY_RECORDS,
});
