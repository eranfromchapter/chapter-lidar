// @chapter/capture-contract: types, validators and layout constants generated
// from contract/schema. Browser-safe; Node-only helpers are in
// "@chapter/capture-contract/node".

import { LAYOUT, RETIRED_ROLES, ROLES, VISIT_ROLES } from "./generated/constants.js";
import type { Capture } from "./generated/capture-record.js";
import type { Photo, Role } from "./generated/manifest.js";

export { LAYOUT, RETIRED_ROLES, ROLES, VISIT_ROLES };

export type {
  CaptureModel,
  CaptureObject,
  Room,
  RoomType,
  RoomTypeSource,
  SourceRef,
  Wall,
  WallOpening,
} from "./generated/capture-model.js";
export type { Capture, CaptureMode, CaptureRecord, RoomNote } from "./generated/capture-record.js";
export type {
  SketchDiagonal,
  SketchLength,
  SketchMeasurements,
  SketchOpening,
  SketchRoom,
  SketchWall,
} from "./generated/sketch-measurements.js";
export type {
  WalkthroughFrame,
  WalkthroughLength,
  WalkthroughLog,
  WalkthroughOpening,
  WalkthroughRoom,
  WalkthroughTap,
} from "./generated/walkthrough-log.js";
export type {
  CaptureRef,
  CeilingHeight,
  Distance,
  EnteredUnit,
  FieldControls,
  FloorToFloor,
  Landmark,
  Measurement,
  OpeningControl,
} from "./generated/field-controls.js";
export type {
  FileEntry,
  PackageManifest,
  Photo,
  PhotoDirection,
  PhotoSubject,
  Role,
} from "./generated/manifest.js";
export type { CheckResult, Finding, Outcome, Severity, Verdict } from "./generated/verdict.js";

/** Every generated type of one schema, including shared aliases such as Uuid and DateTime. */
export type * as CaptureModelTypes from "./generated/capture-model.js";
export type * as CaptureRecordTypes from "./generated/capture-record.js";
export type * as FieldControlsTypes from "./generated/field-controls.js";
export type * as ManifestTypes from "./generated/manifest.js";
export type * as SketchMeasurementsTypes from "./generated/sketch-measurements.js";
export type * as WalkthroughLogTypes from "./generated/walkthrough-log.js";
export type * as VerdictTypes from "./generated/verdict.js";

export {
  SCHEMA_NAMES,
  SCHEMAS,
  formatErrors,
  getValidator,
  validate,
  validateCaptureModel,
  validateCaptureRecord,
  validateFieldControls,
  validateManifest,
  validateSketchMeasurements,
  validateVerdict,
  validateWalkthroughLog,
} from "./validators.js";
export type { ContractError, SchemaName, SchemaTypes, ValidationResult } from "./validators.js";

export {
  COMPASS_APPROXIMATE_MAX,
  COMPASS_VERIFIED_MAX,
  NOT_VERIFIED_BOX,
  compassDetail,
  compassState,
  compassWord,
  formatAccuracy,
  formatHeading,
  isUsable,
  northSymbol,
  reasonCaption,
} from "./compass.js";
export type {
  CompassFields,
  CompassReason,
  CompassState,
  CompassWord,
  HeadingIssue,
  HeadingSource,
  NorthSymbol,
} from "./compass.js";

export {
  NO_NEXT_ACTION,
  OUTCOME_WORD,
  RESULT_GLYPH,
  RESULT_TONE,
  RESULT_WORD,
  checkCounts,
  checkRows,
  countsLine,
  lowerFirst,
  notScannedRoomText,
  notScannedRooms,
  notScannedText,
  ruleResult,
  ruleSetLabel,
  sortCheckRows,
  verdictHeadline,
} from "./review-text.js";
export type {
  CheckCounts,
  CheckRow,
  FoundBlock,
  NotScannedRoom,
  RuleResult,
} from "./review-text.js";

/** How a photo's direction was set (manifest 1.1.0 `photo.directionSource`). */
export type PhotoDirectionSource = NonNullable<Photo["directionSource"]>;

/** Roles of visit-wide files: they carry no captureId or areaKey. */
export type VisitRole = (typeof VISIT_ROLES)[number];

/** Retired roles: listed only by manifest 1.0.0 packages from app builds before v2. */
export type RetiredRole = (typeof RETIRED_ROLES)[number];

/** True for a retired role (a 1.1.0 or later manifest never lists one). */
export function isRetiredRole(role: Role): role is RetiredRole {
  return (RETIRED_ROLES as readonly Role[]).includes(role);
}

/** Roles added in manifest 1.2.0 (spec F14): the originals of a sketch capture. */
export const SKETCH_ROLES = [
  "sketch_image",
  "sketch_measurements",
] as const satisfies readonly Role[];

export type SketchRole = (typeof SKETCH_ROLES)[number];

/** True for a sketch role (manifest 1.2.0 only). */
export function isSketchRole(role: Role): role is SketchRole {
  return (SKETCH_ROLES as readonly Role[]).includes(role);
}

/** Roles added in manifest 1.2.0 (spec F15): the originals of an AR walkthrough. */
export const WALKTHROUGH_ROLES = [
  "walkthrough_video",
  "walkthrough_log",
] as const satisfies readonly Role[];

export type WalkthroughRole = (typeof WALKTHROUGH_ROLES)[number];

/** True for a walkthrough role (manifest 1.2.0 only). */
export function isWalkthroughRole(role: Role): role is WalkthroughRole {
  return (WALKTHROUGH_ROLES as readonly Role[]).includes(role);
}

/** True for the sources whose model the sketch solver builds (sketch and walkthrough). */
export function isMeasuredPlanSource(source: CaptureSource): boolean {
  return source !== "lidar";
}

/** How a capture was made: `captureSource`, with lidar for a record written before 1.2.0. */
export type CaptureSource = NonNullable<Capture["captureSource"]>;

export function captureSourceOf(capture: Pick<Capture, "captureSource">): CaptureSource {
  return capture.captureSource ?? "lidar";
}

/** One folder of the package layout. */
export type LayoutFolder = (typeof LAYOUT.folders)[number];

/** Folder ids of the package layout, for example "original_exports". */
export type LayoutFolderId = LayoutFolder["id"];

/** True when files of this role are visit-wide rather than per capture. */
export function isVisitRole(role: Role): role is VisitRole {
  return (VISIT_ROLES as readonly Role[]).includes(role);
}
