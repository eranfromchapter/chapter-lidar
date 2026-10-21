// fixtures/report/424-west-end (critique R-19): one station verdict per outcome for the
// sample-424 package, valid, about that package, with the 13 rules of the v2 rule set.

import assert from "node:assert/strict";
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import {
  checkCounts,
  checkRows,
  compassDetail,
  compassState,
  countsLine,
  formatErrors,
  validateVerdict,
  type Verdict,
} from "@chapter/capture-contract";
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
});
