// @chapter/station-checks: the station's acceptance checks. Pure library: runChecks takes a
// package already in memory and returns the verdict. Reading a folder is in
// "@chapter/station-checks/node"; loading from storage and storing verdicts are in F9.

export { addressesMatch, normalizeAddress } from "./address.js";
export {
  COMPASS_EXPECTED,
  COMPASS_LIMITATION_FOR_LEGACY_RECORDS,
  ORIENTATION_NOT_VERIFIED,
  scannedBeforeCompass,
} from "./checks/compass.js";
export { CheckContext, resolveRelative, type CaptureInfo } from "./context.js";
export { clip, finding, outcomeOf, NO_ACTION } from "./finding.js";
export { PackageLoadError, packageFromFiles } from "./package.js";
export {
  LIMIT_FRACTION,
  ONE_INCH_MM,
  PASS_FRACTION,
  gradeDistance,
  withinPassTolerance,
  type DistanceComparison,
  type ScaleGrade,
} from "./tolerance.js";
export {
  RULES,
  type CheckOutput,
  type LoadedPackage,
  type RuleId,
  type StationFinding,
} from "./types.js";
export {
  CHECKS,
  DEFAULT_TASK,
  EVALUATOR,
  STATEMENT,
  deterministicUuid,
  runChecks,
  type Check,
  type RunOptions,
} from "./verdict.js";
