// Check 5b, orientation.compass (compass spec 8.2): the rule set (14 rules, evaluator 1.2.0),
// the compass findings of every generated fixture, every compass test vector of the contract run
// through the station, and owner question Q-B (captures scanned before the app read the compass:
// capture records 1.0.0, and captures without compass fields in a 1.1.0 record, carried over from
// an older revision) under both settings of COMPASS_LIMITATION_FOR_LEGACY_RECORDS.

import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { describe, it } from "node:test";
import {
  formatErrors,
  ruleSetLabel,
  validateVerdict,
  type Capture,
  type CaptureRecord,
  type Verdict,
} from "@chapter/capture-contract";
import {
  COMPASS_EXPECTED,
  COMPASS_LIMITATION_FOR_LEGACY_RECORDS,
  ORIENTATION_NOT_VERIFIED,
  checkCompass,
  compassCheck,
  scannedBeforeCompass,
} from "../src/checks/compass.js";
import { CheckContext } from "../src/context.js";
import { outcomeOf } from "../src/finding.js";
import { loadPackageFromDirectory } from "../src/node.js";
import { RULES, type LoadedPackage } from "../src/types.js";
import { CHECKS, EVALUATOR, runChecks } from "../src/verdict.js";
import {
  HUB_ADDRESS,
  generatedDir,
  loadBroken,
  loadGood,
  pathOf,
  readIndex,
  readJson,
  withJson,
  withText,
  withoutFile,
} from "./helpers.js";

const RULE = "orientation.compass";
const index = readIndex();

/** The info finding of a 1.0.0 record: the drawn sample's wording (compass G4), no full stop. */
const LEGACY_MESSAGE = "No compass reading recorded; orientation not verified";

/** Measured value of a 1.1.0 record's capture that has no compass fields. */
const BEFORE_COMPASS =
  "scanned before the app read the compass (no compass fields in capture record 1.1.0)";

function compassFindings(verdict: Verdict): Verdict["findings"] {
  return verdict.findings.filter((item) => item.ruleId === RULE);
}

function compassStatus(verdict: Verdict): string | undefined {
  return verdict.checks.find((check) => check.ruleId === RULE)?.status;
}

function loadGenerated(name: string): LoadedPackage {
  return loadPackageFromDirectory(join(generatedDir, name, "package"));
}

const COMPASS_FIELDS = [
  "heading",
  "headingAccuracy",
  "headingSource",
  "headingRecordedAt",
  "headingIssue",
] as const;

/** The two-floor house's Floor 1 reading: verified, true north 212.4°, ±8°. */
const FLOOR_1_VERIFIED: Partial<Capture> = {
  heading: 212.4,
  headingAccuracy: 8,
  headingSource: "true",
  headingRecordedAt: "2026-10-17T14:02:20Z",
};

/**
 * The package with the capture record at `schemaVersion` and each capture's compass fields
 * replaced by `readings[i]` (which may also set the scan times; an undefined value removes one).
 */
function withReadings(
  pkg: LoadedPackage,
  schemaVersion: CaptureRecord["schemaVersion"],
  readings: Array<Partial<Capture>>,
): LoadedPackage {
  return withJson<CaptureRecord>(pkg, pathOf(pkg, "capture_record"), (record) => {
    record.schemaVersion = schemaVersion;
    record.captures.forEach((capture, i) => {
      for (const key of COMPASS_FIELDS) {
        delete capture[key];
      }
      Object.assign(capture, readings[i] ?? {});
    });
  });
}

describe("the rule set", () => {
  it("has 14 rules, orientation.compass right after orientation.up", () => {
    assert.equal(RULES.length, 14);
    const ids = RULES.map((rule) => rule.id);
    assert.equal(ids.indexOf(RULE), ids.indexOf("orientation.up") + 1);
    assert.deepEqual(RULES[ids.indexOf(RULE)], { id: RULE, title: "Orientation (compass)" });
    assert.equal(CHECKS.find((check) => check.ruleId === RULE)?.run, checkCompass);
  });

  it("is evaluator 1.2.0, read as station-checks v1.2.0", () => {
    assert.deepEqual(EVALUATOR, { name: "chapter-capture-station/checks", version: "1.2.0" });
    assert.equal(ruleSetLabel(EVALUATOR), "station-checks v1.2.0");
    const verdict = runChecks(loadGood("box-room"), HUB_ADDRESS);
    assert.deepEqual(verdict.evaluator, EVALUATOR);
    assert.equal(verdict.checks.length, 14);
  });
});

describe("compass findings of the generated fixtures", () => {
  /** Expected compass check of a capture record 1.0.0 with these capture labels (Q-B default). */
  const legacy = (labels: string) => ({
    status: "not_applicable",
    findings: [
      {
        severity: "info",
        message: LEGACY_MESSAGE,
        measured: `capture record 1.0.0, written before the app read the compass (${labels})`,
      },
    ],
  });
  const verified = {
    severity: "info",
    message: "True north from the compass.",
    measured: "True heading 212°, accuracy ±8°",
  };
  const EXPECTED: Record<
    string,
    { status: string; findings: Array<{ severity: string; message: string; measured: string }> }
  > = {
    "box-room": legacy("Floor 1"),
    "l-shaped-room": legacy("Floor 1"),
    "two-room-apartment": {
      status: "passed",
      findings: [
        {
          severity: "info",
          message: "North is approximate.",
          measured: "Approximate north: magnetic heading 88°, accuracy ±12°",
        },
      ],
    },
    // Floor 1 verified; Floor 2 scanned with the compass but not calibrated: a limitation. The
    // limitation comes first (verdict order).
    "two-floor-house": {
      status: "failed",
      findings: [
        {
          severity: "limitation",
          message: ORIENTATION_NOT_VERIFIED,
          measured: "Compass not calibrated; orientation not verified",
        },
        verified,
      ],
    },
    "legacy-1.0.0": legacy("Floor 1"),
    "sample-424": { status: "passed", findings: [verified] },
  };
  const { legacy: legacyFixtures, samples } = readJson<{
    legacy: Array<{ name: string }>;
    samples: Array<{ name: string }>;
  }>(join(generatedDir, "index.json"));
  const names = [...index.fixtures, ...legacyFixtures, ...samples].map((item) => item.name);

  it("covers every good, legacy and sample fixture", () => {
    assert.deepEqual([...names].sort(), Object.keys(EXPECTED).sort());
  });

  for (const name of names) {
    it(name, () => {
      const pkg = loadGenerated(name);
      const record = pkg.captureRecord;
      assert.ok(record !== undefined);
      const verdict = runChecks(pkg, record.address.formatted);
      const expected = EXPECTED[name];
      assert.ok(expected !== undefined);
      assert.equal(compassStatus(verdict), expected.status);
      const found = compassFindings(verdict);
      assert.deepEqual(
        found.map((item) => ({
          severity: item.severity,
          message: item.message,
          measured: item.measured,
        })),
        expected.findings,
      );
      for (const item of found) {
        assert.equal(item.filePath, pathOf(pkg, "capture_record"));
        assert.equal(item.nextAction, "None");
        if (record.schemaVersion === "1.0.0") {
          // One finding for the record, not per capture, with nothing expected of it.
          assert.equal(item.captureId, undefined);
          assert.equal(item.expected, undefined);
        } else {
          const capture: Capture | undefined = record.captures.find(
            (c) => c.captureId === item.captureId,
          );
          assert.ok(capture !== undefined);
          assert.equal(item.areaKey, capture.areaKey);
          // Nothing is expected of a capture scanned before the app read the compass.
          assert.equal(item.expected, scannedBeforeCompass(capture) ? undefined : COMPASS_EXPECTED);
        }
      }
    });
  }

  it("the two-floor house is limited by Floor 2 alone and asks for nothing", () => {
    // Floor 2 as the app writes a floor scanned with the compass and no reading: why (compass
    // spec 1.5). The drawn "Floor 1 verified · Floor 2 not read" sample.
    const pkg = loadGood("two-floor-house");
    assert.equal(pkg.captureRecord?.schemaVersion, "1.1.0");
    assert.deepEqual(
      pkg.captureRecord.captures.map((capture) => [
        capture.label,
        capture.headingIssue,
        scannedBeforeCompass(capture),
      ]),
      [
        ["Floor 1", undefined, false],
        ["Floor 2", "not_calibrated", false],
      ],
    );
    const verdict = runChecks(pkg, HUB_ADDRESS);
    assert.equal(compassStatus(verdict), "failed");
    assert.equal(verdict.outcome, "limited");
    assert.deepEqual(verdict.limitations, [`Floor 2: ${ORIENTATION_NOT_VERIFIED}`]);
    assert.deepEqual(verdict.nextActions, []);
    assert.equal(
      verdict.summary,
      "Usable for preliminary existing-condition plans with 1 named limitation. Continue the work the evidence supports.",
    );
    assert.deepEqual(
      compassFindings(verdict).map((item) => [item.areaKey, item.severity, item.message]),
      [
        ["floor-2", "limitation", ORIENTATION_NOT_VERIFIED],
        ["floor-1", "info", "True north from the compass."],
      ],
    );
  });

  it("the same house with Floor 2 carried over from before the compass is ready", () => {
    const pkg = withReadings(loadGood("two-floor-house"), "1.1.0", [FLOOR_1_VERIFIED, {}]);
    const verdict = runChecks(pkg, HUB_ADDRESS);
    assert.equal(compassStatus(verdict), "passed");
    assert.equal(verdict.outcome, "ready");
    assert.deepEqual(verdict.limitations, []);
    assert.deepEqual(
      compassFindings(verdict).map((item) => [item.areaKey, item.severity, item.message]),
      [
        ["floor-1", "info", "True north from the compass."],
        ["floor-2", "info", LEGACY_MESSAGE],
      ],
    );
  });

  it("a limited verdict with next actions still asks for the listed items", () => {
    const pkg = loadGenerated("sample-424");
    const verdict = runChecks(pkg, pkg.captureRecord?.address.formatted ?? "");
    assert.equal(verdict.outcome, "limited");
    assert.match(
      verdict.summary,
      /Continue the work the evidence supports and request the listed items\.$/,
    );
  });

  it("the sample-424 finding is the one fixtures/report/424-west-end records", () => {
    const pkg = loadGenerated("sample-424");
    const verdict = runChecks(pkg, pkg.captureRecord?.address.formatted ?? "");
    const reportDir = resolve(generatedDir, "..", "report", "424-west-end");
    for (const outcome of ["ready", "limited", "blocked"]) {
      const recorded = readJson<Verdict>(join(reportDir, `verdict-${outcome}.json`));
      assert.deepEqual(recorded.evaluator, verdict.evaluator, outcome);
      assert.deepEqual(
        verdict.checks.map((check) => check.ruleId),
        recorded.checks.map((check) => check.ruleId),
        outcome,
      );
      // Same fields in the same order: the recorded files are the station's output.
      assert.equal(
        JSON.stringify(compassFindings(recorded)),
        JSON.stringify(compassFindings(verdict)),
        outcome,
      );
    }
  });

  it("every broken fixture on the 1.0.0 box room keeps the legacy finding", () => {
    for (const broken of index.broken) {
      const pkg = loadBroken(broken.defectId);
      const verdict = runChecks(pkg, HUB_ADDRESS);
      if (pkg.captureRecord?.schemaVersion !== "1.0.0") {
        assert.equal(broken.defectId, "compass-time-outside-scan");
        continue;
      }
      assert.equal(compassStatus(verdict), "not_applicable", broken.defectId);
      assert.deepEqual(
        compassFindings(verdict).map((item) => [item.severity, item.message]),
        [["info", LEGACY_MESSAGE]],
        broken.defectId,
      );
    }
  });
});

describe("compass test vectors through the station", () => {
  interface Vector {
    name: string;
    capture: Partial<Capture>;
    expected: {
      kind: "verified" | "approximate" | "not_verified";
      reason?: string;
      detail: string;
    };
  }
  const contractDir = resolve(generatedDir, "..", "..", "contract");
  const vectors = readJson<Vector[]>(join(contractDir, "test-vectors", "compass-states.json"));
  const box = loadGood("box-room");

  it("reads the shared vectors", () => {
    assert.ok(vectors.length >= 30);
  });

  for (const vector of vectors) {
    it(vector.name, () => {
      // The vector's own scan times: no finishedAt when the vector has none.
      const pkg = withReadings(box, "1.1.0", [{ finishedAt: undefined, ...vector.capture }]);
      assert.ok(pkg.captureRecord !== undefined, "every vector is valid in a 1.1.0 record");
      const verdict = runChecks(pkg, HUB_ADDRESS);
      const result = validateVerdict(verdict);
      assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
      const [item, ...rest] = compassFindings(verdict);
      assert.ok(item !== undefined);
      assert.deepEqual(rest, []);
      assert.equal(item.captureId, pkg.captureRecord.captures[0]?.captureId);
      assert.equal(item.nextAction, "None");
      if (scannedBeforeCompass(vector.capture)) {
        // No compass field at all: scanned before the app read the compass, not graded (Q-B).
        // The evaluator still calls it no reading; graded under the other setting.
        assert.equal(vector.expected.reason, "no_reading");
        assert.deepEqual(
          [item.severity, item.message, item.measured, item.expected],
          ["info", LEGACY_MESSAGE, BEFORE_COMPASS, undefined],
        );
        assert.equal(compassStatus(verdict), "not_applicable");
        assert.equal(verdict.outcome, "ready");
        const [graded] = compassCheck({ limitationForLegacyRecords: true })(
          new CheckContext(pkg, HUB_ADDRESS),
        ).findings;
        assert.deepEqual(
          [graded?.severity, graded?.message, graded?.measured],
          ["limitation", ORIENTATION_NOT_VERIFIED, vector.expected.detail],
        );
        return;
      }
      const usable = vector.expected.kind !== "not_verified";
      assert.equal(item.severity, usable ? "info" : "limitation");
      assert.equal(
        item.message,
        vector.expected.kind === "verified"
          ? "True north from the compass."
          : vector.expected.kind === "approximate"
            ? "North is approximate."
            : ORIENTATION_NOT_VERIFIED,
      );
      // Rule 5 (a reading outside the scan) names the reading time and the scan.
      const outsideScan =
        vector.expected.reason === "rejected" && vector.capture.heading !== undefined;
      if (outsideScan) {
        const { capturedAt, finishedAt, headingRecordedAt } = vector.capture;
        const scan =
          finishedAt === undefined
            ? `scan from ${capturedAt} with no finish time`
            : `scan ${capturedAt} to ${finishedAt}`;
        assert.equal(
          item.measured,
          `${vector.expected.detail} (reading at ${headingRecordedAt}, ${scan})`,
        );
      } else {
        assert.equal(item.measured, vector.expected.detail);
      }
      assert.equal(compassStatus(verdict), usable ? "passed" : "failed");
      assert.equal(verdict.outcome, usable ? "ready" : "limited");
      assert.deepEqual(verdict.limitations, usable ? [] : [`Floor 1: ${ORIENTATION_NOT_VERIFIED}`]);
      assert.deepEqual(verdict.nextActions, []);
    });
  }

  it("covers every reason and rule 5 with and without finishedAt", () => {
    const reasons = new Set(
      vectors.map((vector) => vector.expected.reason ?? vector.expected.kind),
    );
    for (const reason of [
      "verified",
      "approximate",
      "no_reading",
      "rejected",
      "inaccurate",
      "not_calibrated",
      "unavailable",
    ]) {
      assert.ok(reasons.has(reason), reason);
    }
    const outside = vectors.filter(
      (vector) => vector.expected.reason === "rejected" && vector.capture.heading !== undefined,
    );
    assert.ok(outside.some((vector) => vector.capture.finishedAt === undefined));
    assert.ok(outside.some((vector) => vector.capture.finishedAt !== undefined));
    // Both kinds of capture without a heading: with headingIssue (graded) and with no field.
    assert.ok(vectors.some((vector) => scannedBeforeCompass(vector.capture)));
    assert.ok(
      vectors.some(
        (vector) =>
          vector.capture.heading === undefined && vector.capture.headingIssue !== undefined,
      ),
    );
  });
});

describe("no capture record", () => {
  const box = loadGood("box-room");
  const recordPath = pathOf(box, "capture_record");

  for (const [name, pkg] of [
    ["missing", withoutFile(box, recordPath)],
    ["unreadable", withText(box, recordPath, "{")],
  ] as const) {
    it(`${name}: not applicable with no finding (checks 2 and 3 report the record)`, () => {
      assert.equal(pkg.captureRecord, undefined);
      const verdict = runChecks(pkg, HUB_ADDRESS);
      assert.equal(compassStatus(verdict), "not_applicable");
      assert.deepEqual(compassFindings(verdict), []);
      assert.deepEqual(checkCompass(new CheckContext(pkg, HUB_ADDRESS)), {
        findings: [],
        notApplicable: true,
      });
    });
  }
});

describe("Q-B: capture records 1.0.0", () => {
  const box = loadGood("box-room");
  const house = loadGood("two-floor-house");
  /** The two-floor house as an app before the compass wrote it: record 1.0.0, no readings. */
  const legacyHouse = withReadings(house, "1.0.0", [{}, {}]);
  const run = (limitationForLegacyRecords: boolean, pkg: LoadedPackage) =>
    compassCheck({ limitationForLegacyRecords })(new CheckContext(pkg, HUB_ADDRESS));

  it("the station's setting is the critique default: no limitation for 1.0.0 records", () => {
    assert.equal(COMPASS_LIMITATION_FOR_LEGACY_RECORDS, false);
    assert.deepEqual(checkCompass(new CheckContext(box, HUB_ADDRESS)), run(false, box));
    assert.deepEqual(
      checkCompass(new CheckContext(legacyHouse, HUB_ADDRESS)),
      run(false, legacyHouse),
    );
  });

  describe("false (default): not applicable with one info finding, outcome unchanged", () => {
    it("one capture", () => {
      const output = run(false, box);
      assert.equal(output.notApplicable, true);
      assert.deepEqual(output.findings, [
        {
          ruleId: RULE,
          severity: "info",
          message: LEGACY_MESSAGE,
          filePath: pathOf(box, "capture_record"),
          measured: "capture record 1.0.0, written before the app read the compass (Floor 1)",
          nextAction: "None",
        },
      ]);
      assert.equal(outcomeOf(output.findings), "ready");
    });

    it("two captures: still one finding, naming both", () => {
      assert.equal(legacyHouse.captureRecord?.schemaVersion, "1.0.0");
      const output = run(false, legacyHouse);
      assert.equal(output.notApplicable, true);
      assert.deepEqual(
        output.findings.map((item) => [item.severity, item.measured, item.captureId]),
        [
          [
            "info",
            "capture record 1.0.0, written before the app read the compass (Floor 1, Floor 2)",
            undefined,
          ],
        ],
      );
      const verdict = runChecks(legacyHouse, HUB_ADDRESS);
      assert.equal(compassStatus(verdict), "not_applicable");
      assert.equal(verdict.outcome, "ready");
    });
  });

  describe("true: every capture of a 1.0.0 record is a limitation", () => {
    it("one capture", () => {
      const output = run(true, box);
      assert.equal(output.notApplicable, undefined);
      const capture = box.captureRecord?.captures[0];
      assert.deepEqual(output.findings, [
        {
          ruleId: RULE,
          severity: "limitation",
          message: ORIENTATION_NOT_VERIFIED,
          filePath: pathOf(box, "capture_record"),
          measured: "No compass reading recorded; orientation not verified",
          nextAction: "None",
          captureId: capture?.captureId,
          areaKey: capture?.areaKey,
          expected: COMPASS_EXPECTED,
        },
      ]);
      assert.equal(outcomeOf(output.findings), "limited");
    });

    it("two captures: one limitation per floor", () => {
      const output = run(true, legacyHouse);
      assert.deepEqual(
        output.findings.map((item) => [item.severity, item.areaKey, item.measured]),
        [
          ["limitation", "floor-1", "No compass reading recorded; orientation not verified"],
          ["limitation", "floor-2", "No compass reading recorded; orientation not verified"],
        ],
      );
    });
  });

  it("1.1.0 records whose captures all carry compass fields are graded the same under both settings", () => {
    for (const pkg of [
      loadGood("two-room-apartment"),
      house,
      loadBroken("compass-time-outside-scan"),
      withReadings(house, "1.1.0", [{ headingIssue: "unavailable" }, { headingIssue: "rejected" }]),
    ]) {
      assert.equal(pkg.captureRecord?.schemaVersion, "1.1.0");
      assert.ok(pkg.captureRecord.captures.every((capture) => !scannedBeforeCompass(capture)));
      assert.deepEqual(run(true, pkg), run(false, pkg));
      assert.equal(run(false, pkg).notApplicable, undefined);
    }
  });
});

describe("Q-B: captures of a 1.1.0 record scanned before the app read the compass", () => {
  const box = loadGood("box-room");
  const house = loadGood("two-floor-house");
  const run = (limitationForLegacyRecords: boolean, pkg: LoadedPackage) =>
    compassCheck({ limitationForLegacyRecords })(new CheckContext(pkg, HUB_ADDRESS));
  /** The box room re-sealed by an app that reads the compass: record 1.1.0, Floor 1 carried over. */
  const carriedBox = withReadings(box, "1.1.0", [{}]);
  /** The house re-sealed: record 1.1.0, both floors carried over from a 1.0.0 revision. */
  const carriedHouse = withReadings(house, "1.1.0", [{}, {}]);
  /** Floor 1 scanned again without a reading (not calibrated), Floor 2 carried over. */
  const rescanned = withReadings(house, "1.1.0", [{ headingIssue: "not_calibrated" }, {}]);
  /** Floor 1 scanned again with a verified reading, Floor 2 carried over. */
  const newFloorVerified = withReadings(house, "1.1.0", [FLOOR_1_VERIFIED, {}]);

  it("a capture is scanned before the compass when it has none of the five compass fields", () => {
    assert.equal(scannedBeforeCompass({}), true);
    const one: Array<Partial<Capture>> = [
      { heading: 212.4 },
      { headingAccuracy: 8 },
      { headingSource: "true" },
      { headingRecordedAt: "2026-10-17T14:02:20Z" },
      { headingIssue: "rejected" },
      { headingIssue: "not_calibrated" },
      { headingIssue: "unavailable" },
    ];
    for (const fields of one) {
      assert.equal(scannedBeforeCompass(fields), false, JSON.stringify(fields));
    }
  });

  it("the station's setting is the critique default: such captures are not graded", () => {
    assert.equal(COMPASS_LIMITATION_FOR_LEGACY_RECORDS, false);
    for (const pkg of [carriedBox, carriedHouse, rescanned, newFloorVerified, house]) {
      assert.deepEqual(checkCompass(new CheckContext(pkg, HUB_ADDRESS)), run(false, pkg));
    }
  });

  describe("false (default): the 1.0.0 treatment for each such capture", () => {
    it("one capture: not applicable with its info finding, outcome unchanged", () => {
      const output = run(false, carriedBox);
      assert.equal(output.notApplicable, true);
      const capture = carriedBox.captureRecord?.captures[0];
      assert.deepEqual(output.findings, [
        {
          ruleId: RULE,
          severity: "info",
          message: LEGACY_MESSAGE,
          filePath: pathOf(carriedBox, "capture_record"),
          measured: BEFORE_COMPASS,
          nextAction: "None",
          captureId: capture?.captureId,
          areaKey: capture?.areaKey,
        },
      ]);
      const verdict = runChecks(carriedBox, HUB_ADDRESS);
      assert.equal(compassStatus(verdict), "not_applicable");
      assert.equal(verdict.outcome, "ready");
      assert.deepEqual(verdict, runChecks(carriedBox, HUB_ADDRESS), "deterministic");
    });

    it("every capture carried over: not applicable, one info finding per floor", () => {
      const output = run(false, carriedHouse);
      assert.equal(output.notApplicable, true);
      assert.deepEqual(
        output.findings.map((item) => [item.severity, item.areaKey, item.message, item.measured]),
        [
          ["info", "floor-1", LEGACY_MESSAGE, BEFORE_COMPASS],
          ["info", "floor-2", LEGACY_MESSAGE, BEFORE_COMPASS],
        ],
      );
      const verdict = runChecks(carriedHouse, HUB_ADDRESS);
      assert.equal(compassStatus(verdict), "not_applicable");
      assert.equal(verdict.outcome, "ready");
      const result = validateVerdict(verdict);
      assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
    });

    it("a new floor with a reading next to one carried over: passed", () => {
      const output = run(false, newFloorVerified);
      assert.equal(output.notApplicable, undefined);
      assert.deepEqual(
        output.findings.map((item) => [item.severity, item.areaKey, item.expected]),
        [
          ["info", "floor-1", COMPASS_EXPECTED],
          ["info", "floor-2", undefined],
        ],
      );
      assert.equal(compassStatus(runChecks(newFloorVerified, HUB_ADDRESS)), "passed");
    });

    it("a new floor without a reading next to one carried over: only the new floor limits", () => {
      const output = run(false, rescanned);
      assert.equal(output.notApplicable, undefined);
      assert.deepEqual(
        output.findings.map((item) => [item.severity, item.areaKey, item.measured]),
        [
          ["limitation", "floor-1", "Compass not calibrated; orientation not verified"],
          ["info", "floor-2", BEFORE_COMPASS],
        ],
      );
      const verdict = runChecks(rescanned, HUB_ADDRESS);
      assert.equal(compassStatus(verdict), "failed");
      assert.equal(verdict.outcome, "limited");
      assert.deepEqual(verdict.limitations, [`Floor 1: ${ORIENTATION_NOT_VERIFIED}`]);
      assert.deepEqual(verdict.nextActions, []);
    });
  });

  describe("true: every such capture is a limitation (no compass reading)", () => {
    it("one capture", () => {
      const output = run(true, carriedBox);
      assert.equal(output.notApplicable, undefined);
      const capture = carriedBox.captureRecord?.captures[0];
      assert.deepEqual(output.findings, [
        {
          ruleId: RULE,
          severity: "limitation",
          message: ORIENTATION_NOT_VERIFIED,
          filePath: pathOf(carriedBox, "capture_record"),
          measured: "No compass reading recorded; orientation not verified",
          nextAction: "None",
          captureId: capture?.captureId,
          areaKey: capture?.areaKey,
          expected: COMPASS_EXPECTED,
        },
      ]);
      assert.equal(outcomeOf(output.findings), "limited");
    });

    it("a new floor verified next to one carried over: the carried floor limits", () => {
      const output = run(true, newFloorVerified);
      assert.deepEqual(
        output.findings.map((item) => [item.severity, item.areaKey, item.measured]),
        [
          ["info", "floor-1", "True heading 212°, accuracy ±8°"],
          ["limitation", "floor-2", "No compass reading recorded; orientation not verified"],
        ],
      );
      assert.equal(outcomeOf(output.findings), "limited");
    });

    it("every capture carried over: one limitation per floor", () => {
      const output = run(true, carriedHouse);
      assert.deepEqual(
        output.findings.map((item) => [item.severity, item.areaKey]),
        [
          ["limitation", "floor-1"],
          ["limitation", "floor-2"],
        ],
      );
    });
  });
});
