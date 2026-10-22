// F9 AC5: the spatial report contains the outcome, every finding and the not-certification
// statement as extractable text.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { Finding, Verdict } from "@chapter/capture-contract";
import { validateVerdict } from "@chapter/capture-contract";
import {
  REPORT_NOT_CERTIFICATION,
  outcomeInPlainWords,
  pdfSafeText,
  renderSpatialReport,
  type ReportFile,
} from "../src/index.js";
import { MIB, REVIEW_BASE_URL, makeTestPackage, pdfText, squash } from "./helpers.js";

const RECORD = makeTestPackage().captureRecord;

async function render(
  verdict: Verdict,
  files: ReportFile[] = [],
  captureRecord = RECORD,
): Promise<{ text: string; bytes: Buffer; checksPage: number }> {
  const rendered = await renderSpatialReport({
    verdict,
    packageId: verdict.packageId,
    dealId: "fixture-deal-0001",
    captureRecord,
    reportLocation: {
      folder: `Capture/${verdict.visitId}/r1`,
      name: `spatial-report-${verdict.verdictId}.pdf`,
    },
    files,
    maxUploadBytes: 45 * MIB,
    reviewBaseUrl: REVIEW_BASE_URL,
  });
  return {
    text: await pdfText(rendered.bytes),
    bytes: rendered.bytes,
    checksPage: rendered.checksPage,
  };
}

function assertHasFinding(text: string, finding: Finding): void {
  const squashed = squash(text);
  for (const part of [
    finding.message,
    finding.ruleId,
    finding.nextAction,
    finding.measured,
    finding.expected,
    finding.filePath,
  ]) {
    if (part !== undefined) {
      assert.ok(squashed.includes(squash(pdfSafeText(part))), `report misses "${part}"`);
    }
  }
}

describe("spatial report (F9 AC5)", () => {
  it("holds the outcome, every finding and the statements (limited)", async () => {
    const { verdict } = makeTestPackage();
    assert.ok(validateVerdict(verdict).ok);
    const { text, bytes, checksPage } = await render(verdict);
    assert.equal(bytes.subarray(0, 5).toString("latin1"), "%PDF-");
    const squashed = squash(text);
    assert.ok(squashed.includes(squash("Limited: usable with named limitations")));
    assert.ok(squashed.includes("STATIONVERDICT"));
    assert.ok(squashed.includes(squash(outcomeInPlainWords(verdict, checksPage))));
    assert.ok(squashed.includes(squash(verdict.summary)));
    for (const finding of verdict.findings) {
      assertHasFinding(text, finding);
    }
    for (const limitation of verdict.limitations) {
      assert.ok(squashed.includes(squash(limitation)));
    }
    for (const action of verdict.nextActions) {
      assert.ok(squashed.includes(squash(action)));
    }
    assert.ok(squashed.includes(squash(verdict.statement)));
    assert.ok(squashed.includes(squash(REPORT_NOT_CERTIFICATION)));
    assert.ok(text.includes("not a certification of any property model or measurement"));
  });

  it("holds every finding of a long blocked verdict across pages, symbols spelled out", async () => {
    const base = makeTestPackage().verdict;
    const findings: Finding[] = Array.from({ length: 60 }, (_, index) => ({
      ruleId: index % 2 === 0 ? "units.scale" : "property.address",
      severity: index < 5 ? "blocker" : "limitation",
      message: `Finding ${index}: distance differs by ${index}.5 mm − tolerance ≤ 25.4 mm … check wall ${index}`,
      filePath: `Original Exports/floor-1/3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35/capture-model.json`,
      measured: `${index}.0 mm × 2`,
      expected: "within 1% or 25.4 mm",
      nextAction: `Re-measure wall ${index} with a tape → re-upload`,
    }));
    const verdict: Verdict = {
      ...base,
      outcome: "blocked",
      summary:
        "Blocked: 5 blockers prevent preliminary existing-condition plans; 55 limitations also listed. Resolve the blockers and re-upload.",
      findings,
      limitations: findings.slice(5).map((f) => f.message),
      nextActions: findings.map((f) => f.nextAction),
    };
    assert.ok(validateVerdict(verdict).ok);
    const { text } = await render(verdict);
    assert.ok(squash(text).includes(squash("Blocked: missing information prevents the task")));
    for (const finding of findings) {
      assertHasFinding(text, finding);
    }
    assert.ok(text.includes("<="));
    assert.ok(squash(text).includes(squash(REPORT_NOT_CERTIFICATION)));
  });

  it("says so when there are no findings (ready)", async () => {
    const base = makeTestPackage().verdict;
    const verdict: Verdict = {
      ...base,
      outcome: "ready",
      summary:
        "Ready for preliminary existing-condition plans. No blockers and no limitations; this is not acceptance of all measurements.",
      checks: base.checks.map((check) => ({ ...check, status: "passed" as const })),
      findings: [],
      limitations: [],
      nextActions: [],
    };
    assert.ok(validateVerdict(verdict).ok);
    const { text, checksPage } = await render(verdict);
    const squashed = squash(text);
    assert.ok(squashed.includes(squash("Ready for preliminary existing-condition plans")));
    assert.ok(squashed.includes(squash(outcomeInPlainWords(verdict, checksPage))));
    assert.ok(squashed.includes("Nofindings."));
    assert.ok(squashed.includes(squash(REPORT_NOT_CERTIFICATION)));
  });

  it("lists the capture record and every file with its SHA-256", async () => {
    const test = makeTestPackage();
    const files: ReportFile[] = test.pkg.files.map((file, index) => ({
      path: file.path,
      role: file.role,
      bytes: file.bytes,
      sha256: file.sha256,
      location:
        index % 2 === 0
          ? { kind: "hub", folder: `Capture/x/r1`, name: file.path.split("/").pop() ?? "" }
          : {
              kind: "link",
              url: `https://review.test/packages/p?file=${encodeURIComponent(file.path)}`,
              reason: "not_published",
            },
    }));
    const { text } = await render(test.verdict, files, test.captureRecord);
    const squashed = squash(text);
    assert.ok(squashed.includes(squash("100 Example Street, Testville, NY 00000")));
    assert.ok(squashed.includes("TestOperator"));
    for (const capture of test.captureRecord.captures) {
      assert.ok(squashed.includes(capture.captureId));
    }
    for (const file of files) {
      assert.ok(squashed.includes(file.sha256), file.path);
      assert.ok(squashed.includes(squash(file.path)), file.path);
    }
  });

  it("is deterministic for the same input", async () => {
    const { verdict } = makeTestPackage();
    const first = await render(verdict);
    const second = await render(verdict);
    assert.equal(squash(first.text), squash(second.text));
    assert.ok(first.bytes.equals(second.bytes), "byte-identical");
  });
});
