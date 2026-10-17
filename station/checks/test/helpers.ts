// Test helpers: load the committed fixtures and make single, re-fingerprinted changes to them.

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { PackageManifest, Verdict } from "@chapter/capture-contract";
import { packageFromFiles } from "../src/package.js";
import { loadPackageFromDirectory } from "../src/node.js";
import type { LoadedPackage } from "../src/types.js";

const here = dirname(fileURLToPath(import.meta.url));
export const generatedDir = resolve(here, "..", "..", "..", "fixtures", "generated");

export interface GeneratedIndex {
  fixtures: Array<{ name: string; truth: string; packageRoot: string; visitId: string }>;
  broken: Array<{ defectId: string; baseFixture: string; defect: string; packageRoot: string }>;
}

export interface DefectJson {
  defectId: string;
  affectedFile: string;
  role: string;
  details: Record<string, unknown>;
}

export interface TruthJson {
  hub: { dealId: string; address: string };
  captures: Array<{ captureId: string; areaKey: string; label: string }>;
}

export function readJson<T>(path: string): T {
  return JSON.parse(readFileSync(path, "utf8")) as T;
}

export function readIndex(): GeneratedIndex {
  return readJson<GeneratedIndex>(join(generatedDir, "index.json"));
}

export function readTruth(name: string): TruthJson {
  return readJson<TruthJson>(join(generatedDir, name, "truth.json"));
}

export function readDefect(id: string): DefectJson {
  return readJson<DefectJson>(join(generatedDir, "broken", id, "defect.json"));
}

export function loadGood(name: string): LoadedPackage {
  return loadPackageFromDirectory(join(generatedDir, name, "package"));
}

export function loadBroken(id: string): LoadedPackage {
  return loadPackageFromDirectory(join(generatedDir, "broken", id, "package"));
}

/** HUB address of the good fixtures (truth.json hub.address). */
export const HUB_ADDRESS = readTruth("box-room").hub.address;

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export function textOf(pkg: LoadedPackage, path: string): string {
  const bytes = pkg.files.get(path);
  if (bytes === undefined) {
    throw new Error(`No file ${path}`);
  }
  return decoder.decode(bytes);
}

export function jsonOf<T>(pkg: LoadedPackage, path: string): T {
  return JSON.parse(textOf(pkg, path)) as T;
}

/** Rebuilds the package from a file map and a manifest (written back as manifest.json). */
function rebuild(
  pkg: LoadedPackage,
  files: Map<string, Uint8Array>,
  manifest: PackageManifest,
): LoadedPackage {
  files.set(pkg.manifestPath, encoder.encode(JSON.stringify(manifest, null, 2)));
  return packageFromFiles(files);
}

export interface ChangeOptions {
  /** Keep the manifest fingerprint unchanged (to test fingerprint mismatches). */
  keepFingerprint?: boolean;
}

/** Replaces one file (adding a manifest entry is not done here) and refreshes its fingerprint. */
export function withFile(
  pkg: LoadedPackage,
  path: string,
  bytes: Uint8Array,
  options: ChangeOptions = {},
): LoadedPackage {
  const files = new Map(pkg.files);
  files.set(path, bytes);
  const manifest = structuredClone(pkg.manifest);
  if (options.keepFingerprint !== true) {
    const entry = manifest.files.find((file) => file.path === path);
    if (entry !== undefined) {
      entry.sha256 = sha256(bytes);
      entry.bytes = bytes.length;
    }
  }
  return rebuild(pkg, files, manifest);
}

export function withText(pkg: LoadedPackage, path: string, text: string): LoadedPackage {
  return withFile(pkg, path, encoder.encode(text));
}

export function withJson<T>(
  pkg: LoadedPackage,
  path: string,
  change: (value: T) => void,
): LoadedPackage {
  const value = jsonOf<T>(pkg, path);
  change(value);
  return withText(pkg, path, JSON.stringify(value, null, 2));
}

/** Removes a file from the package and, unless told otherwise, from the manifest. */
export function withoutFile(
  pkg: LoadedPackage,
  path: string,
  options: { keepManifestEntry?: boolean } = {},
): LoadedPackage {
  const files = new Map(pkg.files);
  files.delete(path);
  const manifest = structuredClone(pkg.manifest);
  if (options.keepManifestEntry !== true) {
    manifest.files = manifest.files.filter(
      (file) => file.path !== path,
    ) as PackageManifest["files"];
  }
  return rebuild(pkg, files, manifest);
}

/** Changes the manifest itself (entries, derivedFrom ...). */
export function withManifest(
  pkg: LoadedPackage,
  change: (manifest: PackageManifest) => void,
): LoadedPackage {
  const manifest = structuredClone(pkg.manifest);
  change(manifest);
  return rebuild(pkg, new Map(pkg.files), manifest);
}

/** Adds a file that the manifest does not list. */
export function withUnlistedFile(
  pkg: LoadedPackage,
  path: string,
  bytes: Uint8Array,
): LoadedPackage {
  const files = new Map(pkg.files);
  files.set(path, bytes);
  return packageFromFiles(files);
}

/** Path of the first manifest entry with a role (and optional captureId). */
export function pathOf(pkg: LoadedPackage, role: string, captureId?: string): string {
  const entry = pkg.manifest.files.find(
    (file) => file.role === role && (captureId === undefined || file.captureId === captureId),
  );
  if (entry === undefined) {
    throw new Error(`No ${role} file`);
  }
  return entry.path;
}

export function nonInfo(verdict: Verdict): Verdict["findings"] {
  return verdict.findings.filter((item) => item.severity !== "info");
}

/** Rewrites the JSON chunk of a GLB (keeps the BIN chunk). */
export function rewriteGlbJson(
  glb: Uint8Array,
  change: (json: Record<string, unknown>) => void,
): Uint8Array {
  const view = new DataView(glb.buffer, glb.byteOffset, glb.byteLength);
  const jsonLength = view.getUint32(12, true);
  const json = JSON.parse(decoder.decode(glb.subarray(20, 20 + jsonLength))) as Record<
    string,
    unknown
  >;
  change(json);
  const raw = encoder.encode(JSON.stringify(json));
  const jsonBytes = new Uint8Array(Math.ceil(raw.length / 4) * 4).fill(0x20);
  jsonBytes.set(raw);
  const rest = glb.subarray(20 + jsonLength);
  const out = new Uint8Array(20 + jsonBytes.length + rest.length);
  const outView = new DataView(out.buffer);
  out.set(glb.subarray(0, 12), 0);
  outView.setUint32(8, out.length, true);
  outView.setUint32(12, jsonBytes.length, true);
  outView.setUint32(16, 0x4e4f534a, true);
  out.set(jsonBytes, 20);
  out.set(rest, 20 + jsonBytes.length);
  return out;
}
