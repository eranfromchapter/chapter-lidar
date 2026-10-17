// The units-and-scale tolerance rule (check 4). The field control (tape or laser) is the
// reference:
//   diff = |model - control|
//   pass        when diff <= max(1% of control, 25.4 mm)
//   limitation  when diff <= 3% of control
//   blocker     when diff >  3% of control
// Values are compared after rounding to 1e-6 mm, so binary floating point noise (for example
// 4.04 m * 1000 = 4040.0000000000005 mm) never moves a value across a boundary.

export const ONE_INCH_MM = 25.4;
export const PASS_FRACTION = 0.01;
export const LIMIT_FRACTION = 0.03;

export type ScaleGrade = "pass" | "limitation" | "blocker";

export interface DistanceComparison {
  modelMm: number;
  controlMm: number;
  /** model - control, mm. */
  signedDiffMm: number;
  diffMm: number;
  /** signed difference as a percentage of the control. */
  percentOfControl: number;
  passLimitMm: number;
  limitationLimitMm: number;
  grade: ScaleGrade;
}

/** Rounds to 1e-6 (a nanometre when the unit is mm). */
export function round6(value: number): number {
  const rounded = Math.round(value * 1e6) / 1e6;
  return rounded === 0 ? 0 : rounded;
}

/** Grades one model distance against its field control. Both in millimetres; control > 0. */
export function gradeDistance(modelMm: number, controlMm: number): DistanceComparison {
  if (!(controlMm > 0) || !Number.isFinite(controlMm) || !Number.isFinite(modelMm)) {
    throw new RangeError(`Invalid distances: model ${modelMm} mm, control ${controlMm} mm`);
  }
  const model = round6(modelMm);
  const control = round6(controlMm);
  const signedDiffMm = round6(model - control);
  const diffMm = Math.abs(signedDiffMm);
  const passLimitMm = round6(Math.max(control / 100, ONE_INCH_MM));
  const limitationLimitMm = round6((control * 3) / 100);
  const grade: ScaleGrade =
    diffMm <= passLimitMm ? "pass" : diffMm <= limitationLimitMm ? "limitation" : "blocker";
  return {
    modelMm: model,
    controlMm: control,
    signedDiffMm,
    diffMm,
    percentOfControl: (signedDiffMm / control) * 100,
    passLimitMm,
    limitationLimitMm,
    grade,
  };
}

/** True when a measured length agrees with a reference within max(1%, 25.4 mm) of the reference. */
export function withinPassTolerance(measuredMm: number, referenceMm: number): boolean {
  return gradeDistance(measuredMm, referenceMm).grade === "pass";
}

/** Worst grade of a list (blocker > limitation > pass). */
export function worstGrade(grades: readonly ScaleGrade[]): ScaleGrade {
  if (grades.includes("blocker")) {
    return "blocker";
  }
  return grades.includes("limitation") ? "limitation" : "pass";
}
