// F8 AC1: every synthetic good fixture gets outcome ready, with no blocker or limitation
// finding, and a verdict that validates against the contract. The one exception is by design:
// the two-floor house's Floor 2 has no compass reading, so it is limited by orientation.compass
// alone (GOOD_LIMITATIONS).

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { formatErrors, validateVerdict } from "@chapter/capture-contract";
import { RULES } from "../src/types.js";
import { runChecks } from "../src/verdict.js";
import {
  GOOD_LIMITATIONS,
  goodOutcome,
  loadGood,
  nonInfo,
  readIndex,
  readTruth,
} from "./helpers.js";

const index = readIndex();

describe("good fixtures", () => {
  it("covers the four good fixtures", () => {
    assert.deepEqual(
      index.fixtures.map((fixture) => fixture.name),
      ["box-room", "l-shaped-room", "two-room-apartment", "two-floor-house"],
    );
  });

  for (const fixture of index.fixtures) {
    describe(fixture.name, () => {
      const pkg = loadGood(fixture.name);
      const verdict = runChecks(pkg, readTruth(fixture.name).hub.address);
      const expected = GOOD_LIMITATIONS[fixture.name] ?? [];

      it(`is ${goodOutcome(fixture.name)} with no blocker and only its expected limitations`, () => {
        const labels = new Map(
          readTruth(fixture.name).captures.map((capture) => [capture.captureId, capture.label]),
        );
        assert.deepEqual(
          nonInfo(verdict).map((item) => [
            item.ruleId,
            item.severity,
            labels.get(item.captureId ?? ""),
          ]),
          expected.map((item) => [item.ruleId, "limitation", item.label]),
        );
        assert.equal(verdict.outcome, goodOutcome(fixture.name));
        assert.deepEqual(
          verdict.limitations,
          expected.map((item) => item.limitation),
        );
        assert.deepEqual(verdict.nextActions, []);
      });

      it("validates against the verdict schema", () => {
        const result = validateVerdict(verdict);
        assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
      });

      it("reports every rule once, none failed but its expected limitations' rules", () => {
        assert.deepEqual(
          verdict.checks.map((check) => check.ruleId),
          RULES.map((rule) => rule.id),
        );
        const limited = new Set(expected.map((item) => item.ruleId));
        for (const check of verdict.checks) {
          assert.equal(check.status === "failed", limited.has(check.ruleId), check.ruleId);
        }
      });

      it("evaluates scale against every floor's field controls", () => {
        const scale = verdict.findings.filter((item) => item.ruleId === "units.scale");
        assert.equal(scale.length, readTruth(fixture.name).captures.length);
        for (const item of scale) {
          assert.match(item.message, /agrees with the field-control distances/);
        }
      });

      it("carries the package identity and is deterministic", () => {
        assert.equal(verdict.packageId, pkg.manifest.packageId);
        assert.equal(verdict.visitId, pkg.manifest.visitId);
        assert.equal(verdict.revision, pkg.manifest.revision);
        assert.deepEqual(runChecks(pkg, readTruth(fixture.name).hub.address), verdict);
      });
    });
  }

  it("the two-floor house is registered by its two shared landmarks", () => {
    const verdict = runChecks(
      loadGood("two-floor-house"),
      readTruth("two-floor-house").hub.address,
    );
    const check = verdict.checks.find((item) => item.ruleId === "floors.registration");
    assert.equal(check?.status, "passed");
  });

  it("uses the evaluation time and verdict id the caller passes", () => {
    const pkg = loadGood("box-room");
    const verdict = runChecks(pkg, readTruth("box-room").hub.address, {
      evaluatedAt: "2026-10-17T16:00:00Z",
      verdictId: "5d1a7c3e-2b4f-4e9a-8c6d-0f3b9a2e7d14",
      task: "Client design options",
    });
    assert.equal(verdict.evaluatedAt, "2026-10-17T16:00:00Z");
    assert.equal(verdict.verdictId, "5d1a7c3e-2b4f-4e9a-8c6d-0f3b9a2e7d14");
    assert.equal(verdict.task, "Client design options");
    assert.ok(validateVerdict(verdict).ok);
  });
});
