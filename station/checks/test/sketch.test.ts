// Check 14, sketch.measurements (spec F14 1.7, AC6), and check 5b on a sketch capture. The sketch
// package is the box room rebuilt in memory as a sketch capture (sketch-package.ts). The committed
// LiDAR fixtures keep their verdict apart from the evaluator version and the added not-applicable
// row.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  formatErrors,
  validateSketchMeasurements,
  validateVerdict,
  type Capture,
  type CaptureRecord,
  type Verdict,
} from "@chapter/capture-contract";
import { SKETCH_ORIENTATION, checkCompass, compassCheck } from "../src/checks/compass.js";
import { ASSUMED_CEILING_M, gradeClosure } from "../src/checks/sketch.js";
import { CheckContext } from "../src/context.js";
import { RULES, type LoadedPackage } from "../src/types.js";
import { EVALUATOR, runChecks } from "../src/verdict.js";
import {
  GOOD_LIMITATIONS,
  HUB_ADDRESS,
  goodOutcome,
  jsonOf,
  loadGood,
  nonInfo,
  pathOf,
  readIndex,
  readTruth,
  withJson,
  withoutFile,
} from "./helpers.js";
import {
  AREA_KEY,
  CAPTURE_ID,
  COMPLETE,
  IMAGE_PATH,
  MEASUREMENTS_PATH,
  MODEL_PATH,
  RECORD_PATH,
  box,
  sketchPackage,
} from "./sketch-package.js";

const RULE = "sketch.measurements";
const COMPASS = "orientation.compass";

const ruleFindings = (verdict: Verdict, ruleId: string) =>
  verdict.findings.filter((item) => item.ruleId === ruleId);
const statusOf = (verdict: Verdict, ruleId: string) =>
  verdict.checks.find((check) => check.ruleId === ruleId)?.status;

describe("the sketch package", () => {
  const pkg = sketchPackage({ sketch: COMPLETE });

  it("has a valid 1.2.0 capture record with one sketch capture and no compass field", () => {
    assert.equal(pkg.captureRecord?.schemaVersion, "1.2.0");
    const capture = pkg.captureRecord?.captures[0] as Capture;
    assert.equal(capture.captureSource, "sketch");
    assert.deepEqual(capture.sketch, COMPLETE);
    assert.equal(capture.heading, undefined);
    assert.equal(capture.headingIssue, undefined);
  });

  it("lists the sketch originals in manifest 1.2.0 and no scan original", () => {
    assert.equal(pkg.manifest.schemaVersion, "1.2.0");
    const roles = pkg.manifest.files.map((file) => file.role);
    assert.ok(roles.includes("sketch_image"));
    assert.ok(roles.includes("sketch_measurements"));
    for (const role of ["raw_roomplan_json", "raw_depth", "point_cloud_las"]) {
      assert.ok(!roles.includes(role as (typeof roles)[number]), role);
    }
    const model = pkg.manifest.files.find((file) => file.role === "capture_model");
    assert.deepEqual(model?.derivedFrom, [MEASUREMENTS_PATH, IMAGE_PATH]);
  });

  it("carries valid entered measurements", () => {
    const result = validateSketchMeasurements(jsonOf(pkg, MEASUREMENTS_PATH));
    assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
  });

  it("passes fingerprints and parses every file", () => {
    const verdict = runChecks(pkg, HUB_ADDRESS);
    assert.equal(statusOf(verdict, "manifest.fingerprints"), "passed");
    assert.equal(statusOf(verdict, "files.parseable"), "passed");
  });
});

describe("AC6 (a): a complete sketch with field controls and photos", () => {
  const verdict = runChecks(sketchPackage({ sketch: COMPLETE }), HUB_ADDRESS);

  it("is ready", () => {
    assert.deepEqual(nonInfo(verdict), []);
    assert.equal(verdict.outcome, "ready");
    assert.deepEqual(verdict.limitations, []);
    assert.deepEqual(verdict.nextActions, []);
  });

  it("passes sketch.measurements with the source and closure infos", () => {
    assert.equal(statusOf(verdict, RULE), "passed");
    const findings = ruleFindings(verdict, RULE);
    assert.deepEqual(
      findings.map((item) => [item.severity, item.message]),
      [
        [
          "info",
          "Geometry of Floor 1 comes from a measured sketch, not a scan: 4 walls and 2 openings measured, ceiling measured.",
        ],
        ["info", "Closure residual of Floor 1 is within the tolerance."],
      ],
    );
    for (const item of findings) {
      assert.equal(item.filePath, MODEL_PATH);
      assert.equal(item.captureId, CAPTURE_ID);
      assert.equal(item.areaKey, AREA_KEY);
      assert.equal(item.nextAction, "None");
      assert.ok(item.expected !== undefined);
    }
    assert.match(
      findings[1]?.measured ?? "",
      /closure residual 8\.0 mm; floor extent 4000\.0 mm; tolerance 40\.0 mm/,
    );
  });

  it("is not graded by the compass check", () => {
    assert.equal(statusOf(verdict, COMPASS), "not_applicable");
    assert.deepEqual(
      ruleFindings(verdict, COMPASS).map((item) => [item.severity, item.message, item.measured]),
      [["info", SKETCH_ORIENTATION, "sketch capture (no scan frame)"]],
    );
  });

  it("keeps scale, coverage and plausibility as a scan gets them", () => {
    assert.equal(statusOf(verdict, "units.scale"), "passed");
    assert.equal(statusOf(verdict, "coverage.rooms"), "passed");
    assert.equal(statusOf(verdict, "geometry.plausibility"), "passed");
    assert.equal(statusOf(verdict, "las.header"), "not_applicable");
  });

  it("validates against the verdict schema", () => {
    const result = validateVerdict(verdict);
    assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
  });
});

describe("AC6 (b): a limited sketch", () => {
  const verdict = runChecks(
    sketchPackage({
      sketch: {
        measurements: "limited",
        wallsMeasured: 2,
        wallsEstimated: 2,
        ceilingHeightSource: "assumed",
      },
      lowWalls: ["wall-2", "wall-3"],
      lowOpenings: ["door-1"],
      heightM: ASSUMED_CEILING_M,
    }),
    HUB_ADDRESS,
  );

  it("is limited by the estimated walls, the assumed ceiling and the estimated door", () => {
    assert.equal(verdict.outcome, "limited");
    assert.equal(statusOf(verdict, RULE), "failed");
    assert.deepEqual(
      nonInfo(verdict).map((item) => [item.ruleId, item.severity]),
      [
        [RULE, "limitation"],
        [RULE, "limitation"],
        [RULE, "limitation"],
      ],
    );
    assert.deepEqual(verdict.limitations, [
      "Floor 1: 2 of 4 walls of Floor 1 are estimated, not measured (wall-2, wall-3).",
      "Floor 1: Ceiling height of Floor 1 is assumed (2.440 m), not measured.",
      "Floor 1: 1 opening of Floor 1 is estimated, not measured (door-1).",
    ]);
  });

  it("asks for the measurements on the next visit", () => {
    assert.deepEqual(verdict.nextActions, [
      "Measure the estimated walls of Floor 1 (wall-2, wall-3) with tape or laser on the next visit.",
      "Measure the ceiling height of Floor 1 with tape or laser on the next visit.",
      "Measure the width and position of door door-1 on Floor 1 with tape on the next visit.",
    ]);
  });

  it("still says where the geometry comes from, without the complete counts", () => {
    const info = ruleFindings(verdict, RULE).filter((item) => item.severity === "info");
    assert.deepEqual(
      info.map((item) => item.message),
      ["Geometry of Floor 1 comes from a measured sketch, not a scan."],
    );
    assert.equal(
      info[0]?.measured,
      "sketch capture, measurements limited: 2 walls measured, 2 estimated, ceiling assumed",
    );
  });

  it("names the model and the capture on every finding", () => {
    for (const item of ruleFindings(verdict, RULE)) {
      assert.equal(item.filePath, MODEL_PATH);
      assert.equal(item.captureId, CAPTURE_ID);
      assert.equal(item.areaKey, AREA_KEY);
      assert.ok(item.measured.length > 0);
    }
  });

  it("validates against the verdict schema", () => {
    const result = validateVerdict(verdict);
    assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
  });
});

describe("AC6 (c): a closure residual over the tolerance", () => {
  const verdict = runChecks(
    sketchPackage({ sketch: { ...COMPLETE, measurements: "limited", closureResidualMm: 120 } }),
    HUB_ADDRESS,
  );

  it("is a limitation graded against max(1% of the floor's extent, 25.4 mm)", () => {
    assert.equal(verdict.outcome, "limited");
    assert.deepEqual(verdict.limitations, [
      "Floor 1: Closure residual of Floor 1 is over the tolerance: 120.0 mm against max(1% of 4000.0 mm, 25.4 mm) = 40.0 mm.",
    ]);
    assert.equal(verdict.nextActions.length, 1);
    assert.match(verdict.nextActions[0] ?? "", /^Re-measure the walls of Floor 1/);
  });

  it("grades the residual like a scale difference of check 4", () => {
    assert.equal(gradeClosure(40, 4000).grade, "pass");
    assert.equal(gradeClosure(40.1, 4000).grade, "limitation");
    assert.equal(gradeClosure(25, 1000).grade, "pass");
    assert.equal(gradeClosure(26, 1000).grade, "limitation");
    assert.equal(gradeClosure(10, 0).passLimitMm, 25.4);
  });

  it("is an info when the residual is within the tolerance", () => {
    const within = runChecks(
      sketchPackage({ sketch: { ...COMPLETE, closureResidualMm: 40 } }),
      HUB_ADDRESS,
    );
    assert.equal(within.outcome, "ready");
    assert.ok(
      ruleFindings(within, RULE).some(
        (item) => item.message === "Closure residual of Floor 1 is within the tolerance.",
      ),
    );
  });

  it("writes no closure finding when the record has no residual", () => {
    const { closureResidualMm: _unused, ...rest } = COMPLETE;
    const none = runChecks(sketchPackage({ sketch: rest }), HUB_ADDRESS);
    assert.equal(none.outcome, "ready");
    assert.equal(ruleFindings(none, RULE).length, 1);
  });
});

describe("AC6 (d): a sketch capture without its originals", () => {
  it("is limited when the entered measurements are missing", () => {
    const pkg = sketchPackage({ sketch: COMPLETE, withoutMeasurements: true });
    const verdict = runChecks(pkg, HUB_ADDRESS);
    assert.equal(verdict.outcome, "limited");
    assert.deepEqual(verdict.limitations, [
      "Floor 1: The originals of the sketch capture of Floor 1 are missing from the package: entered measurements (sketch_measurements).",
    ]);
    const item = nonInfo(verdict)[0];
    assert.equal(item?.ruleId, RULE);
    assert.equal(item?.filePath, pkg.manifestPath);
    assert.equal(item?.measured, "missing: sketch_measurements");
    assert.match(item?.nextAction ?? "", /^Re-export the sketch capture of Floor 1/);
  });

  it("names both originals when both are missing", () => {
    const verdict = runChecks(
      sketchPackage({ sketch: COMPLETE, withoutMeasurements: true, withoutImage: true }),
      HUB_ADDRESS,
    );
    assert.deepEqual(verdict.limitations, [
      "Floor 1: The originals of the sketch capture of Floor 1 are missing from the package: entered measurements (sketch_measurements) and sketch image (sketch_image).",
    ]);
  });
});

describe("a sketch capture the check cannot evaluate", () => {
  it("says so when the capture has no capture model", () => {
    const verdict = runChecks(sketchPackage({ sketch: COMPLETE, withoutModel: true }), HUB_ADDRESS);
    const findings = ruleFindings(verdict, RULE);
    assert.deepEqual(
      findings.map((item) => [item.severity, item.message, item.filePath]),
      [
        ["info", "Geometry of Floor 1 comes from a measured sketch, not a scan.", RECORD_PATH],
        [
          "info",
          "Sketch measurements of Floor 1 not evaluated: the capture has no capture model.",
          RECORD_PATH,
        ],
      ],
    );
    assert.equal(statusOf(verdict, RULE), "passed");
    // Check 4 reports the missing model as it does for a scan.
    assert.ok(verdict.limitations.some((line) => line.includes("no capture model to compare")));
  });

  it("says so when the capture model cannot be read, and keeps the assumed ceiling", () => {
    const pkg = sketchPackage({
      sketch: { ...COMPLETE, measurements: "limited", ceilingHeightSource: "assumed" },
    });
    const broken = withJson<Record<string, unknown>>(pkg, MODEL_PATH, (model) => {
      delete model.rooms;
    });
    const verdict = runChecks(broken, HUB_ADDRESS);
    const findings = ruleFindings(verdict, RULE);
    // The verdict lists limitations before infos.
    assert.deepEqual(
      findings.map((item) => [item.severity, item.message]),
      [
        ["limitation", "Ceiling height of Floor 1 is assumed (2.440 m), not measured."],
        ["info", "Geometry of Floor 1 comes from a measured sketch, not a scan."],
        [
          "info",
          "Sketch measurements of Floor 1 not evaluated: the capture model cannot be read (see files.parseable).",
        ],
      ],
    );
    assert.equal(statusOf(verdict, "files.parseable"), "failed");
  });

  it("is a limitation when the record marks the capture limited and the model shows nothing", () => {
    const verdict = runChecks(
      sketchPackage({ sketch: { ...COMPLETE, measurements: "limited" } }),
      HUB_ADDRESS,
    );
    assert.equal(verdict.outcome, "limited");
    assert.deepEqual(verdict.limitations, [
      "Floor 1: Sketch measurements of Floor 1 are marked limited in the capture record.",
    ]);
    assert.equal(nonInfo(verdict)[0]?.filePath, RECORD_PATH);
  });
});

describe("AC6 (e): the committed LiDAR fixtures", () => {
  it("adds sketch.measurements last, not applicable", () => {
    assert.deepEqual(RULES[RULES.length - 1], { id: RULE, title: "Sketch measurements" });
  });

  for (const fixture of readIndex().fixtures) {
    it(`${fixture.name}: same outcome and findings, plus the not-applicable row`, () => {
      const pkg = loadGood(fixture.name);
      const verdict = runChecks(pkg, readTruth(fixture.name).hub.address);
      assert.deepEqual(verdict.evaluator, { ...EVALUATOR, version: "1.2.0" });
      assert.equal(verdict.outcome, goodOutcome(fixture.name));
      assert.deepEqual(
        verdict.limitations,
        (GOOD_LIMITATIONS[fixture.name] ?? []).map((item) => item.limitation),
      );
      // The 13 rules of 1.1.0 in their order, then the new row.
      assert.deepEqual(
        verdict.checks.map((check) => check.ruleId),
        RULES.map((rule) => rule.id),
      );
      assert.deepEqual(verdict.checks[verdict.checks.length - 1], {
        ruleId: RULE,
        title: "Sketch measurements",
        status: "not_applicable",
      });
      assert.deepEqual(ruleFindings(verdict, RULE), []);
      // No sketch capture: the compass check is as before.
      for (const item of ruleFindings(verdict, COMPASS)) {
        assert.notEqual(item.message, SKETCH_ORIENTATION);
      }
    });
  }

  it("is not applicable without a capture record", () => {
    const pkg = withoutFile(box, RECORD_PATH);
    const verdict = runChecks(pkg, HUB_ADDRESS);
    assert.equal(statusOf(verdict, RULE), "not_applicable");
    assert.deepEqual(ruleFindings(verdict, RULE), []);
  });
});

describe("check 5b on a record with a sketch capture and a scan", () => {
  const house = loadGood("two-floor-house");
  const housePath = pathOf(house, "capture_record");

  /** The house with Floor 2 as a sketch capture (record 1.2.0); Floor 1 keeps its reading. */
  function withSketchFloor2(sketchFloor1 = false): LoadedPackage {
    return withJson<CaptureRecord>(house, housePath, (record) => {
      record.schemaVersion = "1.2.0";
      record.captures.forEach((capture, i) => {
        if (i === 1 || sketchFloor1) {
          delete capture.heading;
          delete capture.headingAccuracy;
          delete capture.headingSource;
          delete capture.headingRecordedAt;
          delete capture.headingIssue;
          capture.captureSource = "sketch";
          capture.sketch = { ...COMPLETE };
        } else {
          capture.captureSource = "lidar";
        }
      });
    });
  }

  it("grades the scan and leaves the sketch capture with its info", () => {
    const pkg = withSketchFloor2();
    assert.equal(pkg.captureRecord?.schemaVersion, "1.2.0");
    const output = checkCompass(new CheckContext(pkg, HUB_ADDRESS));
    assert.notEqual(output.notApplicable, true);
    assert.deepEqual(
      output.findings.map((item) => [item.captureId, item.severity, item.message]),
      [
        [pkg.captureRecord?.captures[0]?.captureId, "info", "True north from the compass."],
        [pkg.captureRecord?.captures[1]?.captureId, "info", SKETCH_ORIENTATION],
      ],
    );
    assert.equal(output.findings[1]?.measured, "sketch capture (no scan frame)");
    assert.equal(output.findings[1]?.nextAction, "None");
    assert.equal(output.findings[1]?.filePath, housePath);
    const verdict = runChecks(pkg, readTruth("two-floor-house").hub.address);
    assert.equal(statusOf(verdict, COMPASS), "passed");
  });

  it("is not applicable when every capture is a sketch", () => {
    const output = checkCompass(new CheckContext(withSketchFloor2(true), HUB_ADDRESS));
    assert.equal(output.notApplicable, true);
    assert.deepEqual(
      output.findings.map((item) => item.message),
      [SKETCH_ORIENTATION, SKETCH_ORIENTATION],
    );
  });

  it("gives the sketch capture the same info under the strict Q-B policy", () => {
    const strict = compassCheck({ limitationForLegacyRecords: true });
    const mixed = strict(new CheckContext(withSketchFloor2(), HUB_ADDRESS));
    assert.notEqual(mixed.notApplicable, true);
    assert.deepEqual(
      mixed.findings.map((item) => [item.severity, item.message]),
      [
        ["info", "True north from the compass."],
        ["info", SKETCH_ORIENTATION],
      ],
    );
    const all = strict(new CheckContext(withSketchFloor2(true), HUB_ADDRESS));
    assert.equal(all.notApplicable, true);
  });

  it("evaluates sketch.measurements for the sketch floor only", () => {
    const pkg = withSketchFloor2();
    const verdict = runChecks(pkg, readTruth("two-floor-house").hub.address);
    const findings = ruleFindings(verdict, RULE);
    assert.ok(findings.length > 0);
    for (const item of findings) {
      assert.equal(item.captureId, pkg.captureRecord?.captures[1]?.captureId);
    }
    // The LiDAR floor's originals are not asked of a scan; the sketch floor's are missing.
    assert.ok(
      verdict.limitations.some((line) =>
        line.startsWith("Floor 2: The originals of the sketch capture of Floor 2 are missing"),
      ),
    );
  });
});
