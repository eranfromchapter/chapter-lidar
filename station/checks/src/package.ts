// Builds a LoadedPackage from an in-memory file map. Pure: no file system access.

import {
  LAYOUT,
  formatErrors,
  validateCaptureRecord,
  validateFieldControls,
  validateManifest,
  type CaptureRecord,
  type FieldControls,
} from "@chapter/capture-contract";
import type { LoadedPackage } from "./types.js";

/** Thrown when the files do not hold one valid Chapter manifest; no verdict can be made. */
export class PackageLoadError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PackageLoadError";
  }
}

const MANIFEST_NAME = LAYOUT.fileNames.manifest;
const MANIFEST_PREFIX = LAYOUT.manifestPath.slice(0, LAYOUT.manifestPath.indexOf("{visitId}"));

/** Decodes UTF-8 strictly. Returns undefined when the bytes are not valid UTF-8. */
export function decodeUtf8(bytes: Uint8Array): string | undefined {
  try {
    const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return text.startsWith("﻿") ? text.slice(1) : text;
  } catch {
    return undefined;
  }
}

/** Parses JSON bytes. Returns undefined when they are not UTF-8 JSON. */
export function parseJsonBytes(bytes: Uint8Array): unknown {
  const text = decodeUtf8(bytes);
  if (text === undefined) {
    return undefined;
  }
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return undefined;
  }
}

function isManifestPath(path: string): boolean {
  if (!path.startsWith(MANIFEST_PREFIX) || !path.endsWith(`/${MANIFEST_NAME}`)) {
    return false;
  }
  const middle = path.slice(MANIFEST_PREFIX.length, path.length - MANIFEST_NAME.length - 1);
  return middle.length > 0 && !middle.includes("/");
}

/**
 * Finds Source Register/{visitId}/manifest.json, validates it and parses the capture record and
 * field controls it lists. Throws PackageLoadError when there is not exactly one valid manifest
 * at its layout path (packages without a Chapter manifest are out of scope).
 */
export function packageFromFiles(files: ReadonlyMap<string, Uint8Array>): LoadedPackage {
  const candidates = [...files.keys()].filter(isManifestPath);
  if (candidates.length !== 1) {
    throw new PackageLoadError(
      candidates.length === 0
        ? `No ${LAYOUT.manifestPath} in the package.`
        : `More than one manifest in the package: ${candidates.join(", ")}.`,
    );
  }
  const manifestPath = candidates[0] as string;
  const parsed = parseJsonBytes(files.get(manifestPath) as Uint8Array);
  if (parsed === undefined) {
    throw new PackageLoadError(`${manifestPath} is not UTF-8 JSON.`);
  }
  const result = validateManifest(parsed);
  if (!result.ok) {
    throw new PackageLoadError(
      `${manifestPath} does not match the manifest schema:\n${formatErrors(result.errors)}`,
    );
  }
  const manifest = result.value;
  const expectedPath = LAYOUT.manifestPath.replace("{visitId}", manifest.visitId);
  if (manifestPath !== expectedPath) {
    throw new PackageLoadError(
      `Manifest is at ${manifestPath} but its visitId says ${expectedPath}.`,
    );
  }

  const firstOf = (role: string): Uint8Array | undefined => {
    const entry = manifest.files.find((file) => file.role === role);
    return entry === undefined ? undefined : files.get(entry.path);
  };
  const loaded: LoadedPackage = { manifestPath, manifest, files };
  const recordBytes = firstOf("capture_record");
  if (recordBytes !== undefined) {
    const record = validateCaptureRecord(parseJsonBytes(recordBytes));
    if (record.ok) {
      loaded.captureRecord = record.value as CaptureRecord;
    }
  }
  const controlBytes = firstOf("field_controls");
  if (controlBytes !== undefined) {
    const controls = validateFieldControls(parseJsonBytes(controlBytes));
    if (controls.ok) {
      loaded.fieldControls = controls.value as FieldControls;
    }
  }
  return loaded;
}
