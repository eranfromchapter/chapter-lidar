// F8 AC3: the "1% or 25.4 mm, whichever is larger" rule is applied exactly at its boundaries.
// The field control is the reference: diff = |model - control|; pass when diff <= max(1% of
// control, 25.4 mm); limitation when diff <= 3% of control; blocker above 3%.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { CaptureModel, FieldControls } from "@chapter/capture-contract";
import { gradeDistance, type ScaleGrade } from "../src/tolerance.js";
import { runChecks } from "../src/verdict.js";
import { HUB_ADDRESS, loadGood, pathOf, withJson } from "./helpers.js";

function grade(modelMm: number, controlMm: number): ScaleGrade {
  return gradeDistance(modelMm, controlMm).grade;
}

describe("gradeDistance", () => {
  it("1% governs above 2540 mm: control 4000 mm passes at 40 mm, not beyond", () => {
    assert.equal(grade(4040, 4000), "pass");
    assert.equal(grade(4040.000001, 4000), "limitation");
    assert.equal(grade(3960, 4000), "pass");
    assert.equal(grade(3959.999999, 4000), "limitation");
  });

  it("25.4 mm governs below 2540 mm: control 2000 mm passes at 25.4 mm, not beyond", () => {
    assert.equal(grade(2025.4, 2000), "pass");
    assert.equal(grade(2025.400001, 2000), "limitation");
    assert.equal(grade(1974.6, 2000), "pass");
    assert.equal(grade(1974.599999, 2000), "limitation");
    // 1% of 2000 mm is 20 mm, which alone would fail 20.1 mm; the inch keeps it passing.
    assert.equal(grade(2020.1, 2000), "pass");
  });

  it("at 2540 mm the two limits meet at 25.4 mm", () => {
    assert.equal(grade(2565.4, 2540), "pass");
    assert.equal(grade(2565.400001, 2540), "limitation");
    assert.equal(grade(2514.6, 2540), "pass");
  });

  it("3% of the control is still a limitation; beyond it is a blocker", () => {
    assert.equal(grade(4120, 4000), "limitation");
    assert.equal(grade(4120.000001, 4000), "blocker");
    assert.equal(grade(3880, 4000), "limitation");
    assert.equal(grade(3879.999999, 4000), "blocker");
    assert.equal(grade(2060, 2000), "limitation");
    assert.equal(grade(2060.000001, 2000), "blocker");
  });

  it("below 846.7 mm 3% is under an inch: there is no limitation band", () => {
    assert.equal(grade(525.4, 500), "pass");
    assert.equal(grade(525.400001, 500), "blocker");
  });

  it("the denominator is the control, not the model (3%-short controls are 3.09% off)", () => {
    const result = gradeDistance(4000, 3880);
    assert.equal(result.diffMm, 120);
    assert.equal(result.limitationLimitMm, 116.4);
    assert.equal(result.grade, "blocker");
    assert.ok(Math.abs(result.percentOfControl - 3.0927835) < 1e-6);
  });

  it("binary floating point noise does not cross a boundary", () => {
    // 1025.4 - 1000 is 25.40000000000009 in binary floating point: one hair over the inch.
    assert.ok(1025.4 - 1000 > 25.4);
    assert.equal(grade(1025.4, 1000), "pass");
    // Exactly 1% longer than 2630 mm: 2656.3 - 2630 is 26.300000000000182, over 26.3 mm.
    assert.ok(2656.3 - 2630 > 2630 / 100);
    assert.equal(grade(2656.3, 2630), "pass");
  });

  it("reports the signed difference and both limits", () => {
    const result = gradeDistance(1974.6, 2000);
    assert.equal(result.signedDiffMm, -25.4);
    assert.equal(result.passLimitMm, 25.4);
    assert.equal(result.limitationLimitMm, 60);
  });

  it("rejects a control that is not positive", () => {
    assert.throws(() => gradeDistance(1000, 0), RangeError);
    assert.throws(() => gradeDistance(1000, -5), RangeError);
    assert.throws(() => gradeDistance(Number.NaN, 1000), RangeError);
  });
});

describe("units.scale applies the boundaries to a package", () => {
  const base = loadGood("box-room");
  const controlsPath = pathOf(base, "field_controls");
  const modelPath = pathOf(base, "capture_model");

  /** Box room with distance A (model 4000 mm) and/or B set to the given control values. */
  function verdictWith(
    controls: { a?: number; b?: number },
    change?: (model: CaptureModel) => void,
  ) {
    let pkg = withJson<FieldControls>(base, controlsPath, (value) => {
      for (const distance of value.distances) {
        const mmValue = distance.axis === "A" ? controls.a : controls.b;
        if (mmValue !== undefined) {
          distance.measurement.valueMm = mmValue;
          distance.measurement.enteredUnit = "mm";
          distance.measurement.enteredText = String(mmValue);
        }
      }
    });
    if (change !== undefined) {
      pkg = withJson<CaptureModel>(pkg, modelPath, change);
    }
    const verdict = runChecks(pkg, HUB_ADDRESS);
    const scale = verdict.findings.filter((item) => item.ruleId === "units.scale");
    assert.equal(scale.length, 1);
    return { verdict, finding: scale[0] as (typeof scale)[number] };
  }

  const cases: Array<[string, { a?: number; b?: number }, "info" | "limitation" | "blocker"]> = [
    // 1% of the control: 4000 / 1.01 = 3960.39604 mm is the boundary (model longer).
    ["model 1% longer, just inside", { a: 3960.39604 }, "info"],
    ["model 1% longer, just outside", { a: 3960.396 }, "limitation"],
    // 4000 / 0.99 = 4040.40404 mm is the boundary (model shorter).
    ["model 1% shorter, just inside", { a: 4040.404 }, "info"],
    ["model 1% shorter, just outside", { a: 4040.405 }, "limitation"],
    // 3% of the control: 4000 / 1.03 = 3883.49515 mm.
    ["model 3% longer, just inside", { a: 3883.4952 }, "limitation"],
    ["model 3% longer, just outside", { a: 3883.4951 }, "blocker"],
  ];
  for (const [name, controls, severity] of cases) {
    it(`${name}: ${severity}`, () => {
      const { verdict, finding } = verdictWith(controls);
      assert.equal(finding.severity, severity, finding.measured);
      assert.equal(
        verdict.outcome,
        severity === "info" ? "ready" : severity === "limitation" ? "limited" : "blocked",
      );
    });
  }

  // Shrink the room to 4.000 x 2.000 m so axis B (2000 mm) sits where 25.4 mm governs.
  const shortB = (model: CaptureModel) => {
    for (const room of model.rooms) {
      room.polygon = room.polygon.map(([x, y, z]) => [
        x,
        y,
        z === 3 ? 2 : z,
      ]) as typeof room.polygon;
    }
  };
  const inchCases: Array<[string, number, "info" | "limitation"]> = [
    ["control 25.4 mm longer than the model", 2025.4, "info"],
    ["control 25.401 mm longer than the model", 2025.401, "limitation"],
    ["control 25.4 mm shorter than the model", 1974.6, "info"],
    ["control 25.401 mm shorter than the model", 1974.599, "limitation"],
  ];
  for (const [name, b, severity] of inchCases) {
    it(`2000 mm room, ${name}: ${severity}`, () => {
      const { finding } = verdictWith({ b }, shortB);
      assert.equal(finding.severity, severity, finding.measured);
      assert.match(finding.measured ?? "", /model 2000\.0 mm/);
    });
  }
});
