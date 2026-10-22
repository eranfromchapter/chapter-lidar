// Rounding and unit conversion of the measurement engine, ported line for line from PlanExport
// UnitFormatter.swift so the report prints the numbers the phone's plan sheet prints.
//
// Rounding is to the nearest step, half away from zero; a value within a millionth of a step of
// a half counts as that half. Feet-inches are rounded as a whole before they are split, so
// 11.96 in prints as 1' 0.0", never 0' 12.0".

export const METRES_PER_INCH = 0.0254;
export const METRES_PER_FOOT = 0.3048;
export const SQUARE_METRES_PER_SQUARE_FOOT = 0.092_903_04;
export const CUBIC_METRES_PER_CUBIC_FOOT = 0.028_316_846_592;

/** A millionth of a step: how close to a half a value must be to round as that half. */
const TIE_TOLERANCE = 1e-6;

/** Printed for a value that is not a finite number. */
export const INVALID = "-";

/**
 * `value / step` rounded half away from zero to a whole number of steps; undefined when the
 * value is not finite or too large to count.
 */
export function steps(value: number, step: number): number | undefined {
  const scaled = value / step;
  if (!Number.isFinite(scaled) || Math.abs(scaled) >= 1e15) {
    return undefined;
  }
  // Math.round on a non-negative number rounds halves up, which is away from zero here.
  const count = Math.round(Math.abs(scaled) + TIE_TOLERANCE);
  return scaled < 0 ? -count : count;
}

function sign(count: number): string {
  return count < 0 ? "-" : "";
}

/** `value` with exactly `places` decimals, for example `6.16` or `300.1`. */
export function decimals(value: number, places: number): string | undefined {
  let unit = 1;
  for (let i = 0; i < places; i += 1) {
    unit *= 10;
  }
  const count = steps(value, 1 / unit);
  if (count === undefined) {
    return undefined;
  }
  const magnitude = Math.abs(count);
  const whole = Math.floor(magnitude / unit);
  if (places <= 0) {
    return `${sign(count)}${whole}`;
  }
  const fraction = String(magnitude % unit).padStart(places, "0");
  return `${sign(count)}${whole}.${fraction}`;
}

/** A length in metres as feet and inches to a tenth of an inch: `19' 4.3"` (ASCII marks). */
export function feetInches(metres: number): string {
  const tenths = steps(metres / METRES_PER_INCH, 0.1);
  if (tenths === undefined) {
    return INVALID;
  }
  const magnitude = Math.abs(tenths);
  const feet = Math.floor(magnitude / 120);
  const inchTenths = magnitude % 120;
  return `${sign(tenths)}${feet}' ${Math.floor(inchTenths / 10)}.${inchTenths % 10}"`;
}

export function squareFeet(squareMetres: number): number {
  return squareMetres / SQUARE_METRES_PER_SQUARE_FOOT;
}

export function cubicFeet(cubicMetres: number): number {
  return cubicMetres / CUBIC_METRES_PER_CUBIC_FOOT;
}
