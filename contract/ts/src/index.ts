// @chapter/capture-contract: types, validators and layout constants generated
// from contract/schema. Browser-safe; Node-only helpers are in
// "@chapter/capture-contract/node".

import { LAYOUT, ROLES, VISIT_ROLES } from "./generated/constants.js";
import type { Role } from "./generated/manifest.js";

export { LAYOUT, ROLES, VISIT_ROLES };

export type {
  CaptureModel,
  CaptureObject,
  Room,
  SourceRef,
  Wall,
  WallOpening,
} from "./generated/capture-model.js";
export type { Capture, CaptureMode, CaptureRecord, RoomNote } from "./generated/capture-record.js";
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
  validateVerdict,
} from "./validators.js";
export type { ContractError, SchemaName, SchemaTypes, ValidationResult } from "./validators.js";

/** Roles of visit-wide files: they carry no captureId or areaKey. */
export type VisitRole = (typeof VISIT_ROLES)[number];

/** One folder of the package layout. */
export type LayoutFolder = (typeof LAYOUT.folders)[number];

/** Folder ids of the package layout, for example "original_exports". */
export type LayoutFolderId = LayoutFolder["id"];

/** True when files of this role are visit-wide rather than per capture. */
export function isVisitRole(role: Role): role is VisitRole {
  return (VISIT_ROLES as readonly Role[]).includes(role);
}
