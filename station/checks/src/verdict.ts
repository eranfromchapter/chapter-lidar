// Entry point: runs every check on a loaded package and builds the contract Verdict.

import { createHash } from "node:crypto";
import type { CheckResult, Verdict } from "@chapter/capture-contract";
import { checkCompanions } from "./checks/companions.js";
import { checkCompass } from "./checks/compass.js";
import { checkCoverage } from "./checks/coverage.js";
import { checkDxfContent, checkLasHeader } from "./checks/formats.js";
import { checkIndependence } from "./checks/independence.js";
import { checkFingerprints, checkParseable } from "./checks/integrity.js";
import { checkOrientation } from "./checks/orientation.js";
import { checkPlausibility } from "./checks/plausibility.js";
import { checkProperty } from "./checks/property.js";
import { checkRegistration } from "./checks/registration.js";
import { checkScale } from "./checks/scale.js";
import { checkSketchMeasurements } from "./checks/sketch.js";
import { CheckContext } from "./context.js";
import { NO_ACTION, clip, count, isActionable, outcomeOf } from "./finding.js";
import {
  RULES,
  type CheckOutput,
  type LoadedPackage,
  type RuleId,
  type StationFinding,
} from "./types.js";

/**
 * Station component and rule set version written into every verdict. 1.1.0 added
 * `orientation.compass` (13 rules); 1.2.0 adds `sketch.measurements` (14 rules, spec F14) and
 * leaves a sketch capture ungraded by `orientation.compass`. People read it as
 * "station-checks v1.2.0" (contract `ruleSetLabel`).
 */
export const EVALUATOR = { name: "chapter-capture-station/checks", version: "1.2.0" } as const;

/** The preliminary task outcomes apply to, unless the caller names another. */
export const DEFAULT_TASK = "Preliminary existing-condition plans";

/** Fixed statement required by the verdict schema. */
export const STATEMENT =
  "This verdict is an automated check of the intake package. It does not certify any property model or measurement." as const;

/** Each check: (context) -> findings. The context holds the package and shared analyses. */
export type Check = (ctx: CheckContext) => CheckOutput;

/** The check function of every rule. */
const RUNNERS: Readonly<Record<RuleId, Check>> = {
  "manifest.fingerprints": checkFingerprints,
  "files.parseable": checkParseable,
  "property.address": checkProperty,
  "units.scale": checkScale,
  "orientation.up": checkOrientation,
  "orientation.compass": checkCompass,
  "companions.resolve": checkCompanions,
  "dxf.content": checkDxfContent,
  "las.header": checkLasHeader,
  "coverage.rooms": checkCoverage,
  "geometry.plausibility": checkPlausibility,
  "floors.registration": checkRegistration,
  "evidence.independence": checkIndependence,
  "sketch.measurements": checkSketchMeasurements,
};

/** The fourteen checks in checklist order. */
export const CHECKS: ReadonlyArray<{ ruleId: RuleId; title: string; run: Check }> = RULES.map(
  (rule) => ({ ruleId: rule.id, title: rule.title, run: RUNNERS[rule.id] }),
);

export interface RunOptions {
  /** Evaluation time, UTC whole seconds (RFC 3339 with Z). Defaults to the manifest sealedAt. */
  evaluatedAt?: string;
  /** Verdict id. Defaults to a UUID derived from package, HUB address, time and rule set. */
  verdictId?: string;
  /** The preliminary task the outcome applies to. */
  task?: string;
}

/** Deterministic UUID (version 8, RFC 9562 variant) from a SHA-256 of the input. */
export function deterministicUuid(input: string): string {
  const hex = createHash("sha256").update(input).digest("hex").slice(0, 32).split("");
  hex[12] = "8";
  hex[16] = ((parseInt(hex[16] as string, 16) & 0x3) | 0x8).toString(16);
  const s = hex.join("");
  return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20, 32)}`;
}

const SEVERITY_ORDER = { blocker: 0, limitation: 1, info: 2 } as const;

function statusOf(output: CheckOutput): CheckResult["status"] {
  if (output.findings.some(isActionable)) {
    return "failed";
  }
  return output.notApplicable === true ? "not_applicable" : "passed";
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}

function summaryOf(
  outcome: Verdict["outcome"],
  task: string,
  findings: StationFinding[],
  nextActions: string[],
): string {
  const blockers = findings.filter((item) => item.severity === "blocker").length;
  const limitations = findings.filter((item) => item.severity === "limitation").length;
  const lower = task.charAt(0).toLowerCase() + task.slice(1);
  switch (outcome) {
    case "ready":
      return `Ready for ${lower}. No blockers and no limitations; this is not acceptance of all measurements.`;
    case "limited":
      // A limitation may ask for nothing (a compass reading cannot be added after the scan).
      return `Usable for ${lower} with ${count(limitations, "named limitation")}. Continue the work the evidence supports${nextActions.length > 0 ? " and request the listed items" : ""}.`;
    case "blocked":
      return `Blocked: ${count(blockers, "blocker")} prevent${blockers === 1 ? "s" : ""} ${lower}${limitations > 0 ? `; ${count(limitations, "limitation")} also listed` : ""}. Resolve the blockers and re-upload.`;
  }
}

/**
 * Runs every check on the package and returns the verdict. Pure: no I/O and no clock; pass
 * `options.evaluatedAt` with the real evaluation time.
 */
export function runChecks(
  pkg: LoadedPackage,
  hubAddress: string,
  options: RunOptions = {},
): Verdict {
  const ctx = new CheckContext(pkg, hubAddress);
  const checks: CheckResult[] = [];
  const collected: StationFinding[] = [];
  for (const check of CHECKS) {
    const output = check.run(ctx);
    checks.push({ ruleId: check.ruleId, title: check.title, status: statusOf(output) });
    collected.push(...output.findings);
  }
  const findings = collected
    .map((item, index) => ({ item, index }))
    .sort(
      (a, b) =>
        SEVERITY_ORDER[a.item.severity] - SEVERITY_ORDER[b.item.severity] || a.index - b.index,
    )
    .map(({ item }) => item);
  const outcome = outcomeOf(findings);
  const task = options.task ?? DEFAULT_TASK;
  const evaluatedAt = options.evaluatedAt ?? pkg.manifest.sealedAt;
  const verdictId =
    options.verdictId ??
    deterministicUuid(
      [pkg.manifest.packageId, hubAddress, evaluatedAt, EVALUATOR.name, EVALUATOR.version].join(
        "\n",
      ),
    );
  const limitations = unique(
    findings
      .filter((item) => item.severity === "limitation")
      .map((item) =>
        clip(
          item.captureId === undefined
            ? item.message
            : `${ctx.label(item.captureId)}: ${item.message}`,
          500,
        ),
      ),
  );
  const nextActions = unique(
    findings
      .filter(isActionable)
      .map((item) => item.nextAction)
      .filter((action) => action !== NO_ACTION),
  );
  return {
    schemaVersion: "1.0.0",
    verdictId,
    packageId: pkg.manifest.packageId,
    visitId: pkg.manifest.visitId,
    revision: pkg.manifest.revision,
    outcome,
    task,
    summary: summaryOf(outcome, task, findings, nextActions),
    evaluatedAt,
    evaluator: { ...EVALUATOR },
    checks,
    findings,
    limitations,
    nextActions,
    statement: STATEMENT,
  };
}
