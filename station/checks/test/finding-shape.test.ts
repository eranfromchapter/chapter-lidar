// F8 AC4: every finding names the source file, the rule, the measured value and a next action,
// across the good and broken fixtures and synthetic variants that drive every rule's failing
// paths. Every verdict validates against the contract.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { formatErrors, validateVerdict, type Verdict } from "@chapter/capture-contract";
import { RULES } from "../src/types.js";
import { runChecks } from "../src/verdict.js";
import { HUB_ADDRESS, loadBroken, loadGood, readIndex } from "./helpers.js";
import { variants } from "./variants.js";
import type { LoadedPackage } from "../src/types.js";

const RULE_IDS = new Set<string>(RULES.map((rule) => rule.id));

interface Case {
  name: string;
  pkg: LoadedPackage;
  verdict: Verdict;
}

const index = readIndex();
const cases: Case[] = [
  ...index.fixtures.map((fixture) => ({ name: fixture.name, pkg: loadGood(fixture.name) })),
  ...index.broken.map((broken) => ({ name: broken.defectId, pkg: loadBroken(broken.defectId) })),
].map(({ name, pkg }) => ({ name, pkg, verdict: runChecks(pkg, HUB_ADDRESS) }));
for (const variant of variants()) {
  cases.push({
    name: variant.name,
    pkg: variant.pkg,
    verdict: runChecks(variant.pkg, variant.hubAddress ?? HUB_ADDRESS),
  });
}

describe("finding shape", () => {
  for (const { name, pkg, verdict } of cases) {
    it(`${name}: every finding names file, rule, measured value and next action`, () => {
      const known = new Set([pkg.manifestPath, ...pkg.manifest.files.map((file) => file.path)]);
      assert.ok(verdict.findings.length > 0);
      for (const item of verdict.findings) {
        const label = `${item.ruleId}: ${item.message}`;
        assert.ok(RULE_IDS.has(item.ruleId), label);
        assert.ok(item.message.trim().length > 0, label);
        assert.equal(typeof item.filePath, "string", label);
        assert.ok(known.has(item.filePath as string), `${label} names ${item.filePath}`);
        assert.equal(typeof item.measured, "string", label);
        assert.ok((item.measured as string).trim().length > 0, label);
        assert.ok(item.nextAction.trim().length > 0, label);
        if (item.severity !== "info") {
          assert.notEqual(item.nextAction, "None", label);
          assert.ok(verdict.nextActions.includes(item.nextAction), label);
        }
      }
    });

    it(`${name}: the verdict validates and follows the outcome rule`, () => {
      const result = validateVerdict(verdict);
      assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
      const severities = new Set(verdict.findings.map((item) => item.severity));
      const outcome = severities.has("blocker")
        ? "blocked"
        : severities.has("limitation")
          ? "limited"
          : "ready";
      assert.equal(verdict.outcome, outcome);
      assert.equal(
        verdict.limitations.length > 0,
        severities.has("limitation"),
        "limitations listed exactly when there is a limitation finding",
      );
      for (const check of verdict.checks) {
        const failed = verdict.findings.some(
          (item) => item.ruleId === check.ruleId && item.severity !== "info",
        );
        assert.equal(check.status === "failed", failed, check.ruleId);
      }
    });
  }

  it("every rule produces at least one blocker or limitation somewhere in the cases", () => {
    const seen = new Set(
      cases.flatMap(({ verdict }) =>
        verdict.findings.filter((item) => item.severity !== "info").map((item) => item.ruleId),
      ),
    );
    assert.deepEqual(
      RULES.map((rule) => rule.id).filter((id) => !seen.has(id)),
      [],
    );
  });

  it("findings are ordered blockers, then limitations, then info", () => {
    const rank = { blocker: 0, limitation: 1, info: 2 } as const;
    for (const { name, verdict } of cases) {
      const ranks = verdict.findings.map((item) => rank[item.severity]);
      assert.deepEqual(
        ranks,
        [...ranks].sort((a, b) => a - b),
        name,
      );
    }
  });
});
