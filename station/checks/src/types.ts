// In-memory package and finding model shared by every check.

import type {
  CaptureRecord,
  FieldControls,
  Finding,
  PackageManifest,
  Severity,
} from "@chapter/capture-contract";

/**
 * One intake package held in memory. Built by `packageFromFiles` (pure) or
 * `loadPackageFromDirectory` (Node, reads a folder). Checks never touch the file system.
 */
export interface LoadedPackage {
  /** Package-relative path of manifest.json, for example Source Register/{visitId}/manifest.json. */
  manifestPath: string;
  /** The validated manifest. */
  manifest: PackageManifest;
  /** The capture record, when its file is present and valid against the contract schema. */
  captureRecord?: CaptureRecord;
  /** The field controls, when their file is present and valid against the contract schema. */
  fieldControls?: FieldControls;
  /** Every file of the package by package-relative path (forward slashes), manifest included. */
  files: ReadonlyMap<string, Uint8Array>;
}

/**
 * A finding as the station writes it. The contract makes filePath and measured optional; the
 * station always fills them so every finding names the file, the rule, the measured value and
 * the next action.
 */
export type StationFinding = Finding & {
  filePath: string;
  measured: string;
  nextAction: string;
};

export type { Severity };

/** What one check returns. */
export interface CheckOutput {
  findings: StationFinding[];
  /** True when the check had nothing to evaluate in this package (for example one floor only). */
  notApplicable?: boolean;
}

/** Stable rule ids, one per check, in checklist order. */
export const RULES = [
  { id: "manifest.fingerprints", title: "Fingerprints" },
  { id: "files.parseable", title: "Files nonempty and readable" },
  { id: "property.address", title: "Property match" },
  { id: "units.scale", title: "Units and scale" },
  { id: "orientation.up", title: "Up direction and orientation" },
  { id: "orientation.compass", title: "Orientation (compass)" },
  { id: "companions.resolve", title: "Mesh companions" },
  { id: "dxf.content", title: "DXF content type" },
  { id: "las.header", title: "LAS header" },
  { id: "coverage.rooms", title: "Coverage" },
  { id: "geometry.plausibility", title: "Plausibility" },
  { id: "floors.registration", title: "Floor registration" },
  { id: "evidence.independence", title: "Independence of evidence" },
] as const;

export type RuleId = (typeof RULES)[number]["id"];
