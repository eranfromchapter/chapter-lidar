// Shared words of a verdict, for every place that shows one: the web review and the station's
// spatial report print the same check rows, counts, headlines and not-scanned room lists.
// Formatting that only one consumer needs (dates, sizes) stays with that consumer.

import type { CaptureRecord } from "./generated/capture-record.js";
import type { CheckResult, Finding, Outcome, Severity, Verdict } from "./generated/verdict.js";

/** Result of one rule as people read it. */
export type RuleResult = "passed" | "limited" | "blocked" | "not_applicable";

export const RESULT_WORD = {
  passed: "Passed",
  limited: "Limited",
  blocked: "Blocked",
  not_applicable: "Not applicable",
} as const satisfies Record<RuleResult, string>;

export const OUTCOME_WORD = {
  ready: "Ready",
  limited: "Limited",
  blocked: "Blocked",
} as const satisfies Record<Outcome, string>;

/** Shape drawn next to a result word (never colour alone). */
export const RESULT_GLYPH = {
  passed: "circle",
  limited: "triangle",
  blocked: "square",
  not_applicable: "dash",
} as const satisfies Record<RuleResult, string>;

/** Tone of a result (success, warning, danger, neutral). */
export const RESULT_TONE = {
  passed: "success",
  limited: "warning",
  blocked: "danger",
  not_applicable: "neutral",
} as const satisfies Record<RuleResult, string>;

/** The `nextAction` of a finding that asks for nothing. */
export const NO_NEXT_ACTION = "None";

const SEVERITY_ORDER: readonly Severity[] = ["blocker", "limitation", "info"];
const RESULT_ORDER: readonly RuleResult[] = ["blocked", "limited", "passed", "not_applicable"];

/**
 * Lower-cases the first character only when the second one is lower case, so a sentence start
 * joins a phrase ("Preliminary plans" -> "preliminary plans") and an acronym stays ("PDF").
 */
export function lowerFirst(text: string): string {
  const [first, second] = [...text];
  if (first === undefined || second === undefined || second.toLowerCase() !== second) {
    return text;
  }
  if (second.toUpperCase() === second) {
    // Not a letter (digit, space, punctuation): nothing tells the case, keep it.
    return text;
  }
  return first.toLowerCase() + text.slice(first.length);
}

/**
 * Result of one check: not applicable as the station says; else blocked with any blocker
 * finding of that rule; else limited when the check failed or has a limitation finding; else
 * passed. `findings` may hold every finding of the verdict; only the check's rule counts.
 */
export function ruleResult(check: CheckResult, findings: readonly Finding[]): RuleResult {
  if (check.status === "not_applicable") {
    return "not_applicable";
  }
  const own = findings.filter((finding) => finding.ruleId === check.ruleId);
  if (own.some((finding) => finding.severity === "blocker")) {
    return "blocked";
  }
  if (check.status === "failed" || own.some((finding) => finding.severity === "limitation")) {
    return "limited";
  }
  return "passed";
}

/** One finding as a check row shows it. */
export interface FoundBlock {
  finding: Finding;
  /**
   * The finding's message, prefixed "{capture label}: " when the package has more than one
   * capture and the finding names one (label from the capture record, else its areaKey).
   */
  message: string;
  /** "Measured: {measured} · Expected: {expected}" (either half alone); absent when neither is. */
  values?: string;
}

/** One rule of a verdict, ready to print. */
export interface CheckRow {
  ruleId: string;
  title: string;
  result: RuleResult;
  word: (typeof RESULT_WORD)[RuleResult];
  glyph: (typeof RESULT_GLYPH)[RuleResult];
  tone: (typeof RESULT_TONE)[RuleResult];
  /** The rule's findings: blocker, limitation, info, station order inside each severity. */
  found: FoundBlock[];
  /** Distinct next actions of the rule's findings, without "None", in finding order. */
  nextActions: string[];
}

function bySeverity(findings: readonly Finding[]): Finding[] {
  return SEVERITY_ORDER.flatMap((severity) =>
    findings.filter((finding) => finding.severity === severity),
  );
}

function captureLabels(record: CaptureRecord | undefined): Map<string, string> | undefined {
  if (record === undefined || record.captures.length < 2) {
    return undefined;
  }
  return new Map(record.captures.map((capture) => [capture.captureId, capture.label]));
}

function foundBlock(finding: Finding, labels: Map<string, string> | undefined): FoundBlock {
  const label =
    labels !== undefined && finding.captureId !== undefined
      ? (labels.get(finding.captureId) ?? finding.areaKey)
      : undefined;
  const values = [
    finding.measured === undefined ? undefined : `Measured: ${finding.measured}`,
    finding.expected === undefined ? undefined : `Expected: ${finding.expected}`,
  ].filter((part): part is string => part !== undefined);
  return {
    finding,
    message: label === undefined ? finding.message : `${label}: ${finding.message}`,
    ...(values.length === 0 ? {} : { values: values.join(" · ") }),
  };
}

function rowOf(
  ruleId: string,
  title: string,
  result: RuleResult,
  findings: readonly Finding[],
  labels: Map<string, string> | undefined,
): CheckRow {
  const ordered = bySeverity(findings);
  const nextActions: string[] = [];
  for (const finding of ordered) {
    if (finding.nextAction !== NO_NEXT_ACTION && !nextActions.includes(finding.nextAction)) {
      nextActions.push(finding.nextAction);
    }
  }
  return {
    ruleId,
    title,
    result,
    word: RESULT_WORD[result],
    glyph: RESULT_GLYPH[result],
    tone: RESULT_TONE[result],
    found: ordered.map((finding) => foundBlock(finding, labels)),
    nextActions,
  };
}

/**
 * One row per check in verdict order, then one row per rule that has findings but no check
 * (title = ruleId, result from its worst severity). Pass the package's capture record to
 * prefix findings with their capture label when there are several captures.
 */
export function checkRows(verdict: Verdict, record?: CaptureRecord): CheckRow[] {
  const labels = captureLabels(record);
  const rows = verdict.checks.map((check) =>
    rowOf(
      check.ruleId,
      check.title,
      ruleResult(check, verdict.findings),
      verdict.findings.filter((finding) => finding.ruleId === check.ruleId),
      labels,
    ),
  );
  const checked = new Set(verdict.checks.map((check) => check.ruleId));
  const orphans: string[] = [];
  for (const finding of verdict.findings) {
    if (!checked.has(finding.ruleId) && !orphans.includes(finding.ruleId)) {
      orphans.push(finding.ruleId);
    }
  }
  for (const ruleId of orphans) {
    const findings = verdict.findings.filter((finding) => finding.ruleId === ruleId);
    const result: RuleResult = findings.some((finding) => finding.severity === "blocker")
      ? "blocked"
      : findings.some((finding) => finding.severity === "limitation")
        ? "limited"
        : "passed";
    rows.push(rowOf(ruleId, ruleId, result, findings, labels));
  }
  return rows;
}

/** Stable sort: blocked, limited, passed, not applicable. */
export function sortCheckRows(rows: readonly CheckRow[]): CheckRow[] {
  return RESULT_ORDER.flatMap((result) => rows.filter((row) => row.result === result));
}

/** Number of check rows per result (rules, not findings). */
export interface CheckCounts {
  blockers: number;
  limitations: number;
  passed: number;
  notApplicable: number;
}

export function checkCounts(rows: readonly CheckRow[]): CheckCounts {
  const count = (result: RuleResult) => rows.filter((row) => row.result === result).length;
  return {
    blockers: count("blocked"),
    limitations: count("limited"),
    passed: count("passed"),
    notApplicable: count("not_applicable"),
  };
}

/** "0 blockers · 2 limitations · 5 passed · 2 not applicable". */
export function countsLine(counts: CheckCounts): string {
  const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;
  return [
    plural(counts.blockers, "blocker"),
    plural(counts.limitations, "limitation"),
    `${counts.passed} passed`,
    `${counts.notApplicable} not applicable`,
  ].join(" · ");
}

/** "Ready for preliminary existing-condition plans", "Limited: …", "Blocked: …". */
export function verdictHeadline(verdict: Pick<Verdict, "outcome" | "task">): string {
  switch (verdict.outcome) {
    case "ready":
      return `Ready for ${lowerFirst(verdict.task)}`;
    case "limited":
      return "Limited: usable with named limitations";
    case "blocked":
      return "Blocked: missing information prevents the task";
  }
}

/** "station-checks v1.1.0": the rule set a verdict was evaluated with. */
export function ruleSetLabel(evaluator: Verdict["evaluator"]): string {
  return `${evaluator.name} v${evaluator.version}`;
}

/** A room the operator did not scan, from the capture record. */
export interface NotScannedRoom {
  captureId: string;
  areaKey: string;
  /** Label of the capture (floor or area) the room belongs to. */
  floorLabel: string;
  name: string;
  /** omitted: the operator chose not to scan it; inaccessible: it could not be entered. */
  kind: "omitted" | "inaccessible";
  reason?: string;
}

/** Every omitted, then every inaccessible room of each capture, in record order. */
export function notScannedRooms(record: CaptureRecord): NotScannedRoom[] {
  return record.captures.flatMap((capture) => {
    const of = (kind: NotScannedRoom["kind"]) => (room: { name: string; reason?: string }) => ({
      captureId: capture.captureId,
      areaKey: capture.areaKey,
      floorLabel: capture.label,
      name: room.name,
      kind,
      ...(room.reason === undefined ? {} : { reason: room.reason }),
    });
    return [
      ...capture.omittedRooms.map(of("omitted")),
      ...capture.inaccessibleRooms.map(of("inaccessible")),
    ];
  });
}

/**
 * One room as notes print it: omitted "{name} ({reason})" or "{name} (not scanned)";
 * inaccessible "{name} (could not enter)" or "{name} (could not enter: {reason})". With
 * `withFloor` (a cover of several floors) the floor label leads inside the brackets:
 * "{name} ({floor label}, {reason})".
 */
export function notScannedRoomText(room: NotScannedRoom, withFloor = false): string {
  const why =
    room.kind === "omitted"
      ? (room.reason ?? "not scanned")
      : room.reason === undefined
        ? "could not enter"
        : `could not enter: ${room.reason}`;
  return `${room.name} (${withFloor ? `${room.floorLabel}, ` : ""}${why})`;
}

/**
 * The not-scanned rooms of a visit as one text: rooms joined " · "; with more than one capture
 * each capture's rooms are prefixed "{label}: " and captures are separated by a line break;
 * "None" when every room was scanned.
 */
export function notScannedText(record: CaptureRecord): string {
  const rooms = notScannedRooms(record);
  if (rooms.length === 0) {
    return "None";
  }
  if (record.captures.length < 2) {
    return rooms.map((room) => notScannedRoomText(room)).join(" · ");
  }
  return record.captures
    .map((capture) => rooms.filter((room) => room.captureId === capture.captureId))
    .filter((own) => own.length > 0)
    .map(
      (own) =>
        `${own[0]?.floorLabel ?? ""}: ${own.map((room) => notScannedRoomText(room)).join(" · ")}`,
    )
    .join("\n");
}
