// fixtures/report/424-west-end (critique R-19): one station verdict per outcome for the
// sample-424 package, valid, about that package, with the 13 rules of the v2 rule set, and
// exactly what `npm run record-report` records from the station checks.

import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import {
  checkCounts,
  checkRows,
  compassDetail,
  compassState,
  countsLine,
  formatErrors,
  ruleSetLabel,
  validateVerdict,
  type Capture,
  type CaptureRecord,
  type Verdict,
} from "@chapter/capture-contract";
import {
  recordReportVerdicts,
  reportDir,
  reportVerdictFileName,
  reportVerdictText,
  withCompassRule,
} from "../src/report.js";
import { SAMPLE_424_NAME } from "../src/sample424.js";
import { fixturesDir, loadSample, readJson } from "./helpers.js";

const dir = join(fixturesDir, "report", "424-west-end");
const sample = loadSample(SAMPLE_424_NAME);
const OUTCOMES = ["blocked", "limited", "ready"] as const;

/** The station's rules in checklist order, with the v2 compass rule after orientation.up. */
const RULE_IDS = [
  "manifest.fingerprints",
  "files.parseable",
  "property.address",
  "units.scale",
  "orientation.up",
  "orientation.compass",
  "companions.resolve",
  "dxf.content",
  "las.header",
  "coverage.rooms",
  "geometry.plausibility",
  "floors.registration",
  "evidence.independence",
];

function verdict(outcome: (typeof OUTCOMES)[number]): Verdict {
  return readJson<Verdict>(join(dir, `verdict-${outcome}.json`));
}

describe("report fixtures for sample-424", () => {
  it("holds exactly the three verdicts", () => {
    assert.deepEqual(readdirSync(dir).sort(), OUTCOMES.map((o) => `verdict-${o}.json`).sort());
  });

  for (const outcome of OUTCOMES) {
    describe(outcome, () => {
      const value = verdict(outcome);

      it("validates against the verdict schema and has its outcome", () => {
        const result = validateVerdict(value);
        assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
        assert.equal(value.outcome, outcome);
      });

      it("is about the sample-424 package, its files and its captures", () => {
        assert.equal(value.packageId, sample.manifest.packageId);
        assert.equal(value.visitId, sample.manifest.visitId);
        assert.equal(value.revision, sample.manifest.revision);
        const paths = new Set([
          ...sample.manifest.files.map((file) => file.path),
          sample.manifestPath.replace(/^.*?\/package\//, ""),
        ]);
        const captures = new Set(sample.record.captures.map((capture) => capture.captureId));
        for (const finding of value.findings) {
          if (finding.filePath !== undefined) {
            assert.ok(paths.has(finding.filePath), finding.filePath);
          }
          if (finding.captureId !== undefined) {
            assert.ok(captures.has(finding.captureId), finding.captureId);
          }
        }
      });

      it("lists the 13 rules of evaluator 1.1.0, compass passed with its verified reading", () => {
        assert.deepEqual(
          value.checks.map((check) => check.ruleId),
          RULE_IDS,
        );
        assert.deepEqual(value.evaluator, {
          name: "chapter-capture-station/checks",
          version: "1.1.0",
        });
        assert.equal(ruleSetLabel(value.evaluator), "station-checks v1.1.0");
        const compass = value.checks.find((check) => check.ruleId === "orientation.compass");
        assert.deepEqual(compass, {
          ruleId: "orientation.compass",
          title: "Orientation (compass)",
          status: "passed",
        });
        const [capture] = sample.record.captures;
        assert.ok(capture !== undefined);
        const findings = value.findings.filter((item) => item.ruleId === "orientation.compass");
        assert.deepEqual(
          findings.map((item) => [item.severity, item.message, item.measured, item.captureId]),
          [
            [
              "info",
              "True north from the compass.",
              compassDetail(compassState(capture)),
              capture.captureId,
            ],
          ],
        );
      });
    });
  }

  it("reads in the shared words as the design draws them", () => {
    const counts = (outcome: (typeof OUTCOMES)[number]) =>
      countsLine(checkCounts(checkRows(verdict(outcome), sample.record)));
    assert.equal(counts("ready"), "0 blockers · 0 limitations · 12 passed · 1 not applicable");
    assert.equal(counts("limited"), "0 blockers · 1 limitation · 11 passed · 1 not applicable");
    assert.equal(counts("blocked"), "2 blockers · 1 limitation · 9 passed · 1 not applicable");
    assert.deepEqual(verdict("limited").limitations, [
      "Floor 1: Primary closet not captured (omitted by the operator: locked).",
      "Floor 1: Storage room not captured (inaccessible).",
    ]);
  });

  it("is what the station checks record for the three package states, byte for byte", async () => {
    assert.equal(reportDir, dir);
    const recorded = recordReportVerdicts();
    for (const outcome of OUTCOMES) {
      assert.equal(
        await reportVerdictText(recorded[outcome]),
        readFileSync(join(dir, reportVerdictFileName(outcome)), "utf8"),
        `${outcome}: re-record with npm run record-report --workspace @chapter/fixtures`,
      );
    }
  });
});

describe("withCompassRule (the v2 compass rule until the station runs it)", () => {
  const limited = verdict("limited");
  const recordPath = sample.fileOfRole("capture_record");
  /** The limited verdict as a station without the compass rule gives it. */
  const withoutRule: Verdict = {
    ...limited,
    evaluator: { ...limited.evaluator, version: "1.0.0" },
    checks: limited.checks.filter((check) => check.ruleId !== "orientation.compass"),
    findings: limited.findings.filter((item) => item.ruleId !== "orientation.compass"),
  };
  function withReading(change: Partial<Capture>): { record: CaptureRecord; capture: Capture } {
    const [first, ...rest] = sample.record.captures;
    const capture = { ...first, ...change };
    return { record: { ...sample.record, captures: [capture, ...rest] }, capture };
  }

  it("adds the row after orientation.up, the finding in check order and evaluator 1.1.0", () => {
    assert.deepEqual(withCompassRule(withoutRule, sample.record, recordPath), limited);
  });

  it("leaves a verdict that has the rule as it is", () => {
    assert.equal(withCompassRule(limited, sample.record, recordPath), limited);
  });

  it("writes an approximate reading as an info finding", () => {
    const { record, capture } = withReading({ headingSource: "magnetic", headingAccuracy: 12 });
    const out = withCompassRule(withoutRule, record, recordPath);
    const added = out.findings.filter((item) => item.ruleId === "orientation.compass");
    assert.deepEqual(
      added.map((item) => [item.severity, item.message, item.measured]),
      [["info", "North is approximate.", compassDetail(compassState(capture))]],
    );
    assert.equal(out.outcome, "limited");
    assert.deepEqual(out.limitations, limited.limitations);
  });

  it("refuses a reading that is not verified (it would change the outcome)", () => {
    const { record } = withReading({ headingAccuracy: 40 });
    assert.throws(() => withCompassRule(withoutRule, record, recordPath), /not verified/);
  });
});
