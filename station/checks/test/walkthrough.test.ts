// Check 14, sketch.measurements, and check 5b on an AR walkthrough capture (spec F15 5, AC5). The
// walkthrough package is the box room rebuilt in memory as a walkthrough capture
// (walkthrough-package.ts): a tape-checked walk is Ready, a walk with neither a tape check nor a
// field-control distance is Limited and names the scale.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  formatErrors,
  validateSketchMeasurements,
  validateVerdict,
  validateWalkthroughLog,
  type Capture,
  type CaptureRecord,
  type FieldControls,
  type SketchMeasurements,
  type Verdict,
} from "@chapter/capture-contract";
import {
  SKETCH_ORIENTATION,
  WALKTHROUGH_ORIENTATION,
  checkCompass,
} from "../src/checks/compass.js";
import { WALKTHROUGH_EXPECTED } from "../src/checks/sketch.js";
import { CheckContext } from "../src/context.js";
import type { LoadedPackage } from "../src/types.js";
import { runChecks } from "../src/verdict.js";
import { HUB_ADDRESS, jsonOf, loadGood, nonInfo, pathOf, readTruth, withJson } from "./helpers.js";
import {
  AREA_KEY,
  CAPTURE_ID,
  COMPLETE,
  MEASUREMENTS_PATH,
  MODEL_PATH,
  RECORD_PATH,
} from "./sketch-package.js";
import {
  AR_SCALE,
  LOG_PATH,
  TAPED,
  VIDEO_PATH,
  walkthroughPackage,
  type WalkthroughScenario,
} from "./walkthrough-package.js";

const RULE = "sketch.measurements";
const COMPASS = "orientation.compass";

const ruleFindings = (verdict: Verdict, ruleId: string) =>
  verdict.findings.filter((item) => item.ruleId === ruleId);
const statusOf = (verdict: Verdict, ruleId: string) =>
  verdict.checks.find((check) => check.ruleId === ruleId)?.status;
const run = (scenario: WalkthroughScenario) => runChecks(walkthroughPackage(scenario), HUB_ADDRESS);

const SCALE_LIMITATION =
  "Scale of Floor 1 comes from the phone's motion tracking only (about 1 to 3 %), not checked with a tape.";
const SCALE_ACTION =
  "Tape one long wall of Floor 1 and record it as a field-control distance, or check the scale in the app on the next visit.";

/** The package without any field-control distance for its floor (the controls file stays). */
function withoutDistances(pkg: LoadedPackage): LoadedPackage {
  return withJson<FieldControls>(pkg, pathOf(pkg, "field_controls"), (controls) => {
    controls.distances = [];
  });
}

describe("the walkthrough package", () => {
  const pkg = walkthroughPackage({ walkthrough: TAPED });

  it("has a valid 1.2.0 capture record with both summaries and no compass field", () => {
    assert.equal(pkg.captureRecord?.schemaVersion, "1.2.0");
    const capture = pkg.captureRecord?.captures[0] as Capture;
    assert.equal(capture.captureSource, "walkthrough");
    assert.deepEqual(capture.sketch, COMPLETE);
    assert.deepEqual(capture.walkthrough, TAPED);
    assert.equal(capture.heading, undefined);
    assert.equal(capture.headingIssue, undefined);
  });

  it("lists the walkthrough originals in manifest 1.2.0, no sketch image and no scan original", () => {
    assert.equal(pkg.manifest.schemaVersion, "1.2.0");
    const roles = pkg.manifest.files.map((file) => file.role);
    for (const role of ["walkthrough_video", "walkthrough_log", "sketch_measurements"] as const) {
      assert.ok(roles.includes(role), role);
    }
    for (const role of ["sketch_image", "raw_roomplan_json", "raw_depth", "point_cloud_las"]) {
      assert.ok(!roles.includes(role as (typeof roles)[number]), role);
    }
    const byPath = (path: string) => pkg.manifest.files.find((file) => file.path === path);
    assert.equal(byPath(VIDEO_PATH)?.role, "walkthrough_video");
    assert.equal(byPath(LOG_PATH)?.role, "walkthrough_log");
    assert.deepEqual(byPath(MEASUREMENTS_PATH)?.derivedFrom, [LOG_PATH]);
    assert.deepEqual(byPath(MODEL_PATH)?.derivedFrom, [MEASUREMENTS_PATH, LOG_PATH]);
  });

  it("carries a valid walkthrough log of the box room's capture", () => {
    const log = jsonOf(pkg, LOG_PATH);
    const result = validateWalkthroughLog(log);
    assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
    if (result.ok) {
      assert.equal(result.value.captureId, CAPTURE_ID);
      assert.equal(result.value.areaKey, AREA_KEY);
      assert.equal(result.value.video?.path, VIDEO_PATH);
      assert.equal(result.value.rooms.length, 1);
    }
  });

  it("carries valid measurements converted from the walk", () => {
    const measurements = jsonOf<SketchMeasurements>(pkg, MEASUREMENTS_PATH);
    const result = validateSketchMeasurements(measurements);
    assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
    assert.deepEqual(measurements.source, { kind: "ar_walkthrough", path: LOG_PATH });
  });

  it("passes fingerprints and parses every file, the video as ISO media", () => {
    const verdict = runChecks(pkg, HUB_ADDRESS);
    assert.equal(statusOf(verdict, "manifest.fingerprints"), "passed");
    assert.equal(statusOf(verdict, "files.parseable"), "passed");
  });

  it("validates a log without the video block when nothing was recorded", () => {
    const unrecorded = walkthroughPackage({
      walkthrough: { ...TAPED, recorded: false },
      withoutVideo: true,
    });
    const result = validateWalkthroughLog(jsonOf(unrecorded, LOG_PATH));
    assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
    assert.equal(result.ok && result.value.video, undefined);
  });
});

describe("AC5: a tape-checked walkthrough with field controls and photos", () => {
  const verdict = run({ walkthrough: TAPED });

  it("is ready", () => {
    assert.deepEqual(nonInfo(verdict), []);
    assert.equal(verdict.outcome, "ready");
    assert.deepEqual(verdict.limitations, []);
    assert.deepEqual(verdict.nextActions, []);
  });

  it("says the geometry comes from an AR walkthrough, with the scale, loop and tracking infos", () => {
    assert.equal(statusOf(verdict, RULE), "passed");
    const findings = ruleFindings(verdict, RULE);
    assert.deepEqual(
      findings.map((item) => [item.severity, item.message]),
      [
        [
          "info",
          "Geometry of Floor 1 comes from an AR walkthrough, not a LiDAR scan: 4 walls and 2 openings measured, ceiling measured.",
        ],
        ["info", "Closure residual of Floor 1 is within the tolerance."],
        ["info", "Scale of Floor 1 checked with a tape (×0.99725)."],
        ["info", "Loop closure of the walk of Floor 1 is within the tolerance."],
        [
          "info",
          "Tracking was limited for 0.5 s of the walk of Floor 1; no tap was taken while it was.",
        ],
      ],
    );
    for (const item of findings) {
      assert.equal(item.filePath, MODEL_PATH);
      assert.equal(item.captureId, CAPTURE_ID);
      assert.equal(item.areaKey, AREA_KEY);
      assert.equal(item.nextAction, "None");
      assert.equal(item.expected, WALKTHROUGH_EXPECTED);
    }
    assert.equal(
      findings[0]?.measured,
      "AR walkthrough, measurements complete: 4 walls measured, 0 estimated, ceiling measured, closure residual 8.0 mm; scale tape ×0.99725, loop closure 38.3 mm, tracking limited 0.5 s, video recorded",
    );
    assert.match(
      findings[3]?.measured ?? "",
      /loop closure 38\.3 mm before distribution; floor extent 4000\.0 mm; tolerance 40\.0 mm/,
    );
  });

  it("is not graded by the compass check", () => {
    assert.equal(statusOf(verdict, COMPASS), "not_applicable");
    assert.deepEqual(
      ruleFindings(verdict, COMPASS).map((item) => [item.severity, item.message, item.measured]),
      [["info", WALKTHROUGH_ORIENTATION, "AR walkthrough (no compass reading)"]],
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

describe("AC5: a walkthrough without any scale reference", () => {
  const verdict = runChecks(
    withoutDistances(walkthroughPackage({ walkthrough: AR_SCALE })),
    HUB_ADDRESS,
  );

  it("is limited and names the scale", () => {
    assert.equal(verdict.outcome, "limited");
    assert.equal(statusOf(verdict, RULE), "failed");
    assert.ok(
      verdict.limitations.includes(`Floor 1: ${SCALE_LIMITATION}`),
      verdict.limitations.join("\n"),
    );
    assert.ok(verdict.nextActions.includes(SCALE_ACTION));
    const item = ruleFindings(verdict, RULE).find((finding) => finding.severity === "limitation");
    assert.equal(item?.message, SCALE_LIMITATION);
    assert.equal(item?.measured, "scale source ar; no field-control distance for this floor");
    assert.equal(item?.filePath, MODEL_PATH);
  });

  it("is limited by the scale alone in rule 14 (no tracking info when tracking was never limited)", () => {
    assert.deepEqual(
      ruleFindings(verdict, RULE).map((item) => [item.severity, item.message]),
      [
        ["limitation", SCALE_LIMITATION],
        ["info", "Geometry of Floor 1 comes from an AR walkthrough, not a LiDAR scan."],
        ["info", "Closure residual of Floor 1 is within the tolerance."],
        ["info", "Loop closure of the walk of Floor 1 is within the tolerance."],
      ],
    );
  });

  it("validates against the verdict schema", () => {
    const result = validateVerdict(verdict);
    assert.ok(result.ok, result.ok ? "" : formatErrors(result.errors));
  });

  it("is an info when the floor has field-control distances (check 4 compares them)", () => {
    const withControls = run({ walkthrough: AR_SCALE });
    assert.equal(withControls.outcome, "ready");
    assert.ok(
      ruleFindings(withControls, RULE).some(
        (item) =>
          item.severity === "info" &&
          item.message ===
            "Scale of Floor 1 comes from the phone's motion tracking and is checked against 2 field-control distances (units.scale).",
      ),
    );
    assert.equal(statusOf(withControls, "units.scale"), "passed");
  });

  it("is an info when the scale was taped, field controls or not", () => {
    const taped = runChecks(
      withoutDistances(walkthroughPackage({ walkthrough: TAPED })),
      HUB_ADDRESS,
    );
    assert.ok(!taped.limitations.some((line) => line.includes("motion tracking only")));
    assert.ok(
      ruleFindings(taped, RULE).some(
        (item) => item.message === "Scale of Floor 1 checked with a tape (×0.99725).",
      ),
    );
    assert.equal(statusOf(taped, RULE), "passed");
  });
});

describe("the loop closure of the walk", () => {
  it("is a limitation over max(1% of the floor's extent, 25.4 mm)", () => {
    const verdict = run({ walkthrough: { ...TAPED, loopClosureMm: 120 } });
    assert.equal(verdict.outcome, "limited");
    assert.deepEqual(verdict.limitations, [
      "Floor 1: The walk of Floor 1 drifted 120.0 mm before the loop was closed; over max(1% of 4000.0 mm, 25.4 mm) = 40.0 mm.",
    ]);
    assert.equal(verdict.nextActions.length, 1);
    assert.match(verdict.nextActions[0] ?? "", /^Walk Floor 1 again on the next visit/);
    const item = nonInfo(verdict)[0];
    assert.equal(item?.ruleId, RULE);
    assert.equal(
      item?.measured,
      "loop closure 120.0 mm before distribution; floor extent 4000.0 mm; tolerance 40.0 mm",
    );
  });

  it("is an info at the tolerance", () => {
    const verdict = run({ walkthrough: { ...TAPED, loopClosureMm: 40 } });
    assert.equal(verdict.outcome, "ready");
  });
});

describe("the originals of a walkthrough capture", () => {
  it("is limited when the walkthrough log is missing (the raw record is gone)", () => {
    const pkg = walkthroughPackage({ walkthrough: TAPED, withoutLog: true });
    const verdict = runChecks(pkg, HUB_ADDRESS);
    assert.equal(verdict.outcome, "limited");
    assert.deepEqual(verdict.limitations, [
      "Floor 1: The walkthrough log of Floor 1 is missing from the package: the raw record of the walk (every tap and camera pose) is gone.",
    ]);
    const item = nonInfo(verdict)[0];
    assert.equal(item?.ruleId, RULE);
    assert.equal(item?.filePath, pkg.manifestPath);
    assert.equal(item?.measured, "missing: walkthrough_log");
    assert.equal(
      item?.nextAction,
      "Re-export the walkthrough capture of Floor 1 so the package carries its walkthrough log (walkthrough-log.json).",
    );
  });

  it("is limited when the video is missing although the record says it was recorded", () => {
    const verdict = run({ walkthrough: TAPED, withoutVideo: true });
    assert.equal(verdict.outcome, "limited");
    assert.deepEqual(verdict.limitations, [
      "Floor 1: The walkthrough video of Floor 1 is missing from the package, although the capture record says it was recorded.",
    ]);
    assert.equal(
      nonInfo(verdict)[0]?.measured,
      "missing: walkthrough_video; walkthrough.recorded: true",
    );
  });

  it("is an info when the walk was not recorded", () => {
    const pkg = walkthroughPackage({
      walkthrough: { ...TAPED, recorded: false },
      withoutVideo: true,
    });
    const verdict = runChecks(pkg, HUB_ADDRESS);
    assert.equal(verdict.outcome, "ready");
    const item = ruleFindings(verdict, RULE).find((finding) =>
      finding.message.startsWith("No walkthrough video"),
    );
    assert.equal(item?.message, "No walkthrough video of Floor 1: the walk was not recorded.");
    assert.equal(item?.severity, "info");
    assert.equal(item?.filePath, pkg.manifestPath);
  });

  it("is limited when the measurements derived from the walk are missing", () => {
    const verdict = run({ walkthrough: TAPED, withoutMeasurements: true });
    assert.equal(verdict.outcome, "limited");
    assert.deepEqual(verdict.limitations, [
      "Floor 1: The measurements of the AR walkthrough of Floor 1 are missing from the package (sketch_measurements).",
    ]);
  });

  it("does not ask a walkthrough for a sketch image", () => {
    const verdict = run({ walkthrough: TAPED });
    assert.ok(!verdict.findings.some((item) => item.message.includes("sketch image")));
  });

  it("blocks a video file that is not ISO media", () => {
    const verdict = run({
      walkthrough: TAPED,
      videoBytes: new TextEncoder().encode("not a video, just text bytes"),
    });
    assert.equal(verdict.outcome, "blocked");
    assert.equal(statusOf(verdict, "files.parseable"), "failed");
    const blockers = verdict.findings.filter((item) => item.severity === "blocker");
    assert.deepEqual(
      blockers.map((item) => [item.ruleId, item.filePath]),
      [["files.parseable", VIDEO_PATH]],
    );
  });
});

describe("a walkthrough capture the check cannot evaluate", () => {
  it("says so without a capture model and still grades the scale", () => {
    const verdict = runChecks(
      withoutDistances(walkthroughPackage({ walkthrough: AR_SCALE, withoutModel: true })),
      HUB_ADDRESS,
    );
    assert.deepEqual(
      ruleFindings(verdict, RULE).map((item) => [item.severity, item.message, item.filePath]),
      [
        ["limitation", SCALE_LIMITATION, RECORD_PATH],
        [
          "info",
          "Geometry of Floor 1 comes from an AR walkthrough, not a LiDAR scan.",
          RECORD_PATH,
        ],
        [
          "info",
          "Walkthrough measurements of Floor 1 not evaluated: the capture has no capture model.",
          RECORD_PATH,
        ],
      ],
    );
  });

  it("is a limitation when the record marks the capture limited and nothing else explains it", () => {
    const verdict = run({ walkthrough: TAPED, sketch: { ...COMPLETE, measurements: "limited" } });
    assert.deepEqual(verdict.limitations, [
      "Floor 1: Walkthrough measurements of Floor 1 are marked limited in the capture record.",
    ]);
  });
});

describe("check 5b on a record with a walkthrough capture, a sketch and a scan", () => {
  const house = loadGood("two-floor-house");
  const housePath = pathOf(house, "capture_record");

  /** The house with Floor 2 walked (record 1.2.0); Floor 1 keeps its reading unless sketched. */
  function withWalkedFloor2(sketchFloor1 = false): LoadedPackage {
    return withJson<CaptureRecord>(house, housePath, (record) => {
      record.schemaVersion = "1.2.0";
      record.captures.forEach((capture, i) => {
        if (i === 1 || sketchFloor1) {
          delete capture.heading;
          delete capture.headingAccuracy;
          delete capture.headingSource;
          delete capture.headingRecordedAt;
          delete capture.headingIssue;
          capture.sketch = { ...COMPLETE };
          if (i === 1) {
            capture.captureSource = "walkthrough";
            capture.walkthrough = { ...TAPED };
          } else {
            capture.captureSource = "sketch";
          }
        } else {
          capture.captureSource = "lidar";
        }
      });
    });
  }

  it("grades the scan and leaves the walkthrough capture with its info", () => {
    const pkg = withWalkedFloor2();
    const output = checkCompass(new CheckContext(pkg, HUB_ADDRESS));
    assert.notEqual(output.notApplicable, true);
    assert.deepEqual(
      output.findings.map((item) => [item.captureId, item.severity, item.message]),
      [
        [pkg.captureRecord?.captures[0]?.captureId, "info", "True north from the compass."],
        [pkg.captureRecord?.captures[1]?.captureId, "info", WALKTHROUGH_ORIENTATION],
      ],
    );
    assert.equal(output.findings[1]?.nextAction, "None");
    const verdict = runChecks(pkg, readTruth("two-floor-house").hub.address);
    assert.equal(statusOf(verdict, COMPASS), "passed");
  });

  it("is not applicable when every capture is a sketch or a walkthrough", () => {
    const output = checkCompass(new CheckContext(withWalkedFloor2(true), HUB_ADDRESS));
    assert.equal(output.notApplicable, true);
    assert.deepEqual(
      output.findings.map((item) => item.message),
      [SKETCH_ORIENTATION, WALKTHROUGH_ORIENTATION],
    );
  });

  it("evaluates sketch.measurements for the walked floor only, asking for its originals", () => {
    const pkg = withWalkedFloor2();
    const verdict = runChecks(pkg, readTruth("two-floor-house").hub.address);
    const findings = ruleFindings(verdict, RULE);
    assert.ok(findings.length > 0);
    for (const item of findings) {
      assert.equal(item.captureId, pkg.captureRecord?.captures[1]?.captureId);
    }
    assert.ok(
      verdict.limitations.includes(
        "Floor 2: The walkthrough log of Floor 2 is missing from the package: the raw record of the walk (every tap and camera pose) is gone.",
      ),
    );
    assert.ok(!verdict.limitations.some((line) => line.includes("sketch image")));
  });
});
