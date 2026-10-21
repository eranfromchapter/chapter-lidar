// fixtures/report/424-west-end (critique R-19): the station verdicts of the sample-424 package,
// one per outcome, recorded by running the station checks (station/checks, from its sources) on
// three states of the generated package. `npm run record-report` writes them and
// test/report.test.ts checks that the committed files are exactly what this gives.

import { join } from "node:path";
import {
  compassDetail,
  compassState,
  type CaptureRecord,
  type Finding,
  type Verdict,
} from "@chapter/capture-contract";
import { loadPackageFromDirectory } from "../../../station/checks/src/node.js";
import { packageFromFiles } from "../../../station/checks/src/package.js";
import type { LoadedPackage } from "../../../station/checks/src/types.js";
import { runChecks } from "../../../station/checks/src/verdict.js";
import { expandedJsonText, repoRoot } from "./json.js";
import { SAMPLE_424_NAME } from "./sample424.js";
import { sha256Hex, utf8 } from "./util.js";

export const REPORT_OUTCOMES = ["ready", "limited", "blocked"] as const;
export type ReportOutcome = (typeof REPORT_OUTCOMES)[number];

export const reportDir = join(repoRoot, "fixtures", "report", "424-west-end");
export const sample424PackageDir = join(
  repoRoot,
  "fixtures",
  "generated",
  SAMPLE_424_NAME,
  "package",
);

/** HUB address the checks compare the capture record with (the fixtures' placeholder). */
export const REPORT_HUB_ADDRESS = "100 Example Street, Testville, NY 00000";
/** Evaluation time of the three verdicts. */
export const REPORT_EVALUATED_AT = "2026-10-17T15:20:44Z";
/**
 * Verdict ids, pinned. The station derives an id from package, HUB address, time and rule set,
 * which are the same for the three states, so each fixture names its own. They do not change
 * with the rule set, so baselines built on these files keep them when the files are re-recorded.
 */
export const REPORT_VERDICT_IDS: Readonly<Record<ReportOutcome, string>> = {
  ready: "6a1f3c2e-9b4d-4e7a-8c5f-0d2e4b6a8c10",
  limited: "6a1f3c2e-9b4d-4e7a-8c5f-0d2e4b6a8c11",
  blocked: "6a1f3c2e-9b4d-4e7a-8c5f-0d2e4b6a8c12",
};
/** The second placeholder address, recorded in the blocked state's capture record. */
const OTHER_ADDRESS = "200 Sample Avenue, Testville, NY 00000";

const decoder = new TextDecoder();

function pathOfRole(pkg: LoadedPackage, role: string): string {
  const entry = pkg.manifest.files.find((file) => file.role === role);
  if (entry === undefined) {
    throw new Error(`sample-424 has no ${role} file`);
  }
  return entry.path;
}

/**
 * The package with one file replaced. `refingerprint`: the manifest entry takes the new SHA-256
 * and size (an edit before sealing); otherwise it keeps the old ones (a change after sealing).
 */
function withFile(
  pkg: LoadedPackage,
  path: string,
  bytes: Uint8Array,
  refingerprint: boolean,
): LoadedPackage {
  const files = new Map(pkg.files);
  files.set(path, bytes);
  if (refingerprint) {
    const manifest = structuredClone(pkg.manifest);
    const entry = manifest.files.find((file) => file.path === path);
    if (entry === undefined) {
      throw new Error(`no manifest entry for ${path}`);
    }
    entry.sha256 = sha256Hex(bytes);
    entry.bytes = bytes.length;
    files.set(pkg.manifestPath, utf8(JSON.stringify(manifest, null, 2)));
  }
  return packageFromFiles(files);
}

/** The package with its capture record changed before sealing. */
function withRecord(pkg: LoadedPackage, change: (record: CaptureRecord) => void): LoadedPackage {
  const path = pathOfRole(pkg, "capture_record");
  const record = JSON.parse(decoder.decode(pkg.files.get(path))) as CaptureRecord;
  change(record);
  return withFile(pkg, path, utf8(JSON.stringify(record, null, 2)), true);
}

/**
 * The package with one digit of rooms.csv changed after sealing (the file still reads as CSV,
 * with the same size): the first digit 0 to 8 in the second half of the file, plus one.
 */
function withRoomsCsvChangedAfterSealing(pkg: LoadedPackage): LoadedPackage {
  const path = pathOfRole(pkg, "rooms_csv");
  const bytes = new Uint8Array(pkg.files.get(path) ?? []);
  const at = bytes.findIndex(
    (byte, index) => index > bytes.length / 2 && byte >= 0x30 && byte <= 0x38,
  );
  if (at < 0) {
    throw new Error("rooms.csv has no digit to change in its second half");
  }
  bytes[at] = (bytes[at] as number) + 1;
  return withFile(pkg, path, bytes, false);
}

/**
 * The three package states. limited: the package as generated (Primary closet not scanned,
 * locked; Storage room not entered). ready: no skipped rooms in the capture record. blocked: the
 * capture-record address changed to the second placeholder, and rooms.csv changed after sealing.
 */
export function reportPackageStates(base: LoadedPackage): Record<ReportOutcome, LoadedPackage> {
  return {
    ready: withRecord(base, (record) => {
      for (const capture of record.captures) {
        capture.omittedRooms = [];
        capture.inaccessibleRooms = [];
      }
    }),
    limited: base,
    blocked: withRoomsCsvChangedAfterSealing(
      withRecord(base, (record) => {
        record.address.formatted = OTHER_ADDRESS;
      }),
    ),
  };
}

const COMPASS_RULE = { ruleId: "orientation.compass", title: "Orientation (compass)" } as const;
const COMPASS_EXPECTED = "a compass reading at scan start, true north, accuracy ±10° or better";
const SEVERITY_ORDER = { blocker: 0, limitation: 1, info: 2 } as const;

/**
 * Adds the v2 rule `orientation.compass` (compass spec 8.2, built in station/checks by track T3)
 * to a verdict of a station that does not run it yet, as that station will report it: the row
 * right after `orientation.up`, one finding per capture in the station's field order, findings
 * by severity then check order, evaluator version 1.1.0 (13 rules). A verdict that has the rule
 * already is returned unchanged. Only the info states (verified, approximate) are written: a
 * reading that is not verified adds a limitation and changes the outcome, so it throws.
 */
export function withCompassRule(
  verdict: Verdict,
  record: CaptureRecord,
  recordPath: string,
): Verdict {
  if (verdict.checks.some((check) => check.ruleId === COMPASS_RULE.ruleId)) {
    return verdict;
  }
  const out = structuredClone(verdict);
  out.evaluator = { ...out.evaluator, version: "1.1.0" };
  const up = out.checks.findIndex((check) => check.ruleId === "orientation.up");
  if (up < 0) {
    throw new Error("the verdict has no orientation.up row");
  }
  out.checks.splice(up + 1, 0, { ...COMPASS_RULE, status: "passed" });
  const compass = record.captures.map((capture): Finding => {
    const state = compassState(capture);
    if (state.kind === "not_verified") {
      throw new Error(`${capture.label}: the compass reading is not verified (${state.reason})`);
    }
    return {
      ruleId: COMPASS_RULE.ruleId,
      severity: "info",
      message: state.kind === "verified" ? "True north from the compass." : "North is approximate.",
      filePath: recordPath,
      measured: compassDetail(state),
      nextAction: "None",
      captureId: capture.captureId,
      areaKey: capture.areaKey,
      expected: COMPASS_EXPECTED,
    };
  });
  const order = new Map(out.checks.map((check, index) => [check.ruleId, index]));
  const rank = (item: Finding) => order.get(item.ruleId) ?? out.checks.length;
  // Stable: findings of one check keep their order.
  out.findings = [...out.findings, ...compass].sort(
    (a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity] || rank(a) - rank(b),
  );
  return out;
}

/** The three verdicts of the package in `packageDir` (the generated sample-424 by default). */
export function recordReportVerdicts(
  packageDir: string = sample424PackageDir,
): Record<ReportOutcome, Verdict> {
  const states = reportPackageStates(loadPackageFromDirectory(packageDir));
  const out = {} as Record<ReportOutcome, Verdict>;
  for (const outcome of REPORT_OUTCOMES) {
    const pkg = states[outcome];
    if (pkg.captureRecord === undefined) {
      throw new Error(`${outcome}: the capture record does not load`);
    }
    const verdict = runChecks(pkg, REPORT_HUB_ADDRESS, {
      evaluatedAt: REPORT_EVALUATED_AT,
      verdictId: REPORT_VERDICT_IDS[outcome],
    });
    if (verdict.outcome !== outcome) {
      throw new Error(`the ${outcome} state gives a ${verdict.outcome} verdict`);
    }
    out[outcome] = withCompassRule(verdict, pkg.captureRecord, pathOfRole(pkg, "capture_record"));
  }
  return out;
}

/** File name of the verdict of one outcome, in `reportDir`. */
export function reportVerdictFileName(outcome: ReportOutcome): string {
  return `verdict-${outcome}.json`;
}

/** The text a verdict file holds: objects expanded, two-space indentation, through Prettier. */
export function reportVerdictText(verdict: Verdict): Promise<string> {
  return expandedJsonText(verdict);
}
