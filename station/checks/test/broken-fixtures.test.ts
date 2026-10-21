// F8 AC2: each broken fixture (box-room with exactly one change) produces exactly its defect's
// finding at the expected severity, no other blocker or limitation, and the expected outcome.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  formatErrors,
  validateVerdict,
  type Outcome,
  type Severity,
} from "@chapter/capture-contract";
import type { RuleId } from "../src/types.js";
import { runChecks } from "../src/verdict.js";
import { loadBroken, nonInfo, readDefect, readIndex, readTruth } from "./helpers.js";

interface Expectation {
  ruleId: RuleId;
  severity: Exclude<Severity, "info">;
  outcome: Outcome;
  /** Package file the finding names; defaults to defect.json affectedFile. */
  filePath?: (defect: ReturnType<typeof readDefect>) => string;
  /** Text the measured value must contain. */
  measured?: RegExp;
}

/** Orchestrator decisions for the seven defects. */
const EXPECTED: Record<string, Expectation> = {
  "empty-file": {
    ruleId: "files.parseable",
    severity: "blocker",
    outcome: "blocked",
    measured: /^0 bytes$/,
  },
  "wrong-address": {
    ruleId: "property.address",
    severity: "blocker",
    outcome: "blocked",
    measured: /200 Sample Avenue/,
  },
  "inches-as-metres": {
    ruleId: "units.scale",
    severity: "blocker",
    outcome: "blocked",
    measured: /model 157480\.3 mm vs control 4000\.0 mm/,
  },
  "dimensions-3pct-off": {
    ruleId: "units.scale",
    severity: "blocker",
    outcome: "blocked",
    // The finding names the capture model the controls were compared with.
    filePath: () =>
      "Original Exports/floor-1/22bfb513-226d-4eca-bde1-0b6cb0c84aad/capture-model.json",
    measured:
      /control 3880\.0 mm, \+120\.0 mm \(\+3\.09%\).*control 2910\.0 mm, \+90\.0 mm \(\+3\.09%\)/,
  },
  "z-up-mesh": {
    ruleId: "orientation.up",
    severity: "limitation",
    outcome: "limited",
    measured: /Y 3\.000 m.*looks Z-up/,
  },
  "missing-gltf-bin": {
    ruleId: "companions.resolve",
    severity: "blocker",
    outcome: "blocked",
    measured: /mesh\.bin.*not in the package/,
  },
  "las-bad-header": {
    ruleId: "las.header",
    severity: "limitation",
    outcome: "limited",
    measured: /header point count 1888, data holds 888 points/,
  },
};

/**
 * Broken fixtures whose rule the station does not run yet (contract v1.1 ships the fixture
 * first), with that rule. Until then the defect goes unnoticed: the package is otherwise the
 * good box room. Each moves to EXPECTED with its rule.
 */
const AWAITING_RULE: Record<string, string> = {
  "compass-time-outside-scan": "orientation.compass",
};

const index = readIndex();

describe("broken fixtures", () => {
  it("every broken fixture has an expectation and every expectation a fixture", () => {
    assert.deepEqual(
      index.broken.map((item) => item.defectId).sort(),
      [...Object.keys(EXPECTED), ...Object.keys(AWAITING_RULE)].sort(),
    );
  });

  for (const broken of index.broken.filter((item) => item.defectId in AWAITING_RULE)) {
    it(`${broken.defectId}: ready until ${AWAITING_RULE[broken.defectId]} runs`, () => {
      const hubAddress = readTruth(broken.baseFixture).hub.address;
      const verdict = runChecks(loadBroken(broken.defectId), hubAddress);
      assert.ok(!verdict.checks.some((check) => check.ruleId === AWAITING_RULE[broken.defectId]));
      assert.deepEqual(nonInfo(verdict), []);
      assert.equal(verdict.outcome, "ready");
      const result = validateVerdict(verdict);
      assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
    });
  }

  for (const broken of index.broken.filter((item) => !(item.defectId in AWAITING_RULE))) {
    const expected = EXPECTED[broken.defectId] as Expectation;
    describe(broken.defectId, () => {
      const defect = readDefect(broken.defectId);
      // The HUB address of every broken fixture is the box-room truth address; for
      // wrong-address it is also defect.json details.hubAddress.
      const hubAddress = readTruth(broken.baseFixture).hub.address;
      const verdict = runChecks(loadBroken(broken.defectId), hubAddress);
      const actionable = nonInfo(verdict);

      it(`produces exactly one ${expected.severity} ${expected.ruleId} finding and nothing else`, () => {
        assert.deepEqual(
          actionable.map((item) => [item.ruleId, item.severity]),
          [[expected.ruleId, expected.severity]],
          JSON.stringify(actionable, null, 2),
        );
      });

      it(`names the affected file and the measured value`, () => {
        const item = actionable[0];
        assert.ok(item !== undefined);
        const filePath = expected.filePath?.(defect) ?? defect.affectedFile;
        assert.equal(item.filePath, filePath);
        if (expected.measured !== undefined) {
          assert.match(item.measured ?? "", expected.measured);
        }
        assert.notEqual(item.nextAction, "None");
      });

      it(`is ${expected.outcome}`, () => {
        assert.equal(verdict.outcome, expected.outcome);
        if (expected.outcome === "limited") {
          assert.equal(verdict.limitations.length, 1);
        }
      });

      it("fails only the defect's rule", () => {
        const failed = verdict.checks.filter((check) => check.status === "failed");
        assert.deepEqual(
          failed.map((check) => check.ruleId),
          [expected.ruleId],
        );
      });

      it("validates against the verdict schema", () => {
        const result = validateVerdict(verdict);
        assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
      });
    });
  }

  it("the wrong-address HUB address is the box-room truth address", () => {
    assert.equal(readDefect("wrong-address").details.hubAddress, readTruth("box-room").hub.address);
  });

  it("the 3%-off controls are beyond 3% of the control (3.09%), not at the boundary", () => {
    const defect = readDefect("dimensions-3pct-off");
    const distances = defect.details.distances as Array<{
      scanMinusControlPercentOfControl: number;
    }>;
    for (const item of distances) {
      assert.ok(item.scanMinusControlPercentOfControl > 3);
    }
  });

  it("a wrong address with the recorded address as HUB address is not a mismatch", () => {
    const defect = readDefect("wrong-address");
    const verdict = runChecks(
      loadBroken("wrong-address"),
      defect.details.recordedAddress as string,
    );
    assert.equal(nonInfo(verdict).filter((item) => item.ruleId === "property.address").length, 0);
  });
});
