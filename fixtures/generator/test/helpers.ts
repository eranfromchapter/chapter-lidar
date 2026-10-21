// Shared test helpers: locate and load the committed fixtures.

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  CaptureModel,
  CaptureRecord,
  FieldControls,
  PackageManifest,
} from "@chapter/capture-contract";
import type { TruthJson } from "../src/truth.js";

const here = dirname(fileURLToPath(import.meta.url));
export const generatorDir = resolve(here, "..");
export const fixturesDir = resolve(generatorDir, "..");
export const generatedDir = join(fixturesDir, "generated");

export function readJson<T>(path: string): T {
  return JSON.parse(readFileSync(path, "utf8")) as T;
}

/** Relative paths (forward slashes) of every file under a folder, sorted. */
export function listFiles(dir: string): string[] {
  const out: string[] = [];
  const walk = (current: string) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const full = join(current, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else {
        out.push(relative(dir, full).split("\\").join("/"));
      }
    }
  };
  walk(dir);
  return out.sort();
}

export function readTree(dir: string): Map<string, Buffer> {
  return new Map(listFiles(dir).map((path) => [path, readFileSync(join(dir, path))]));
}

export interface IndexFixture {
  name: string;
  description: string;
  legacy?: boolean;
  truth: string;
  packageRoot: string;
  manifest: string;
  visitId: string;
}

export interface GeneratedIndex {
  generatedFormatVersion: string;
  fixtures: IndexFixture[];
  legacy: IndexFixture[];
  samples: IndexFixture[];
  broken: Array<{
    defectId: string;
    baseFixture: string;
    defect: string;
    packageRoot: string;
    manifest: string;
  }>;
}

export function readIndex(): GeneratedIndex {
  return readJson<GeneratedIndex>(join(generatedDir, "index.json"));
}

export interface LoadedFixture {
  name: string;
  /** Absolute path of the package root. */
  root: string;
  manifest: PackageManifest;
  manifestPath: string;
  record: CaptureRecord;
  controls: FieldControls;
  /** Capture models by captureId. */
  models: Map<string, CaptureModel>;
  truth?: TruthJson;
  path(relativePath: string): string;
  bytes(relativePath: string): Buffer;
  fileOfRole(role: string, captureId?: string): string;
}

export function loadPackage(
  name: string,
  packageRoot: string,
  manifestPath: string,
): LoadedFixture {
  const root = join(generatedDir, packageRoot);
  const manifest = readJson<PackageManifest>(join(generatedDir, manifestPath));
  const find = (role: string, captureId?: string): string => {
    const entry = manifest.files.find(
      (file) => file.role === role && (captureId === undefined || file.captureId === captureId),
    );
    if (entry === undefined) {
      throw new Error(`No ${role} file in ${name}`);
    }
    return entry.path;
  };
  const record = readJson<CaptureRecord>(join(root, find("capture_record")));
  const controls = readJson<FieldControls>(join(root, find("field_controls")));
  const models = new Map<string, CaptureModel>();
  for (const capture of record.captures) {
    const path = manifest.files.find(
      (file) => file.role === "capture_model" && file.captureId === capture.captureId,
    )?.path;
    if (path !== undefined && existsSync(join(root, path))) {
      models.set(capture.captureId, readJson<CaptureModel>(join(root, path)));
    }
  }
  return {
    name,
    root,
    manifest,
    manifestPath,
    record,
    controls,
    models,
    path: (relativePath) => join(root, relativePath),
    bytes: (relativePath) => readFileSync(join(root, relativePath)),
    fileOfRole: find,
  };
}

function loadListed(list: "fixtures" | "legacy" | "samples", name: string): LoadedFixture {
  const entry = readIndex()[list].find((fixture) => fixture.name === name);
  if (entry === undefined) {
    throw new Error(`Unknown fixture ${name} in index ${list}`);
  }
  const loaded = loadPackage(name, entry.packageRoot, entry.manifest);
  loaded.truth = readJson<TruthJson>(join(generatedDir, entry.truth));
  return loaded;
}

export function loadGood(name: string): LoadedFixture {
  return loadListed("fixtures", name);
}

/** A package sealed by an app before v2 (index.json `legacy`). */
export function loadLegacy(name: string): LoadedFixture {
  return loadListed("legacy", name);
}

/** A design sample (index.json `samples`). */
export function loadSample(name: string): LoadedFixture {
  return loadListed("samples", name);
}

export function loadBroken(defectId: string): LoadedFixture {
  const entry = readIndex().broken.find((fixture) => fixture.defectId === defectId);
  if (entry === undefined) {
    throw new Error(`Unknown broken fixture ${defectId}`);
  }
  return loadPackage(defectId, entry.packageRoot, entry.manifest);
}

export function isDirectory(path: string): boolean {
  return existsSync(path) && statSync(path).isDirectory();
}

/** Minimal GLB reader: JSON chunk and (optional) BIN chunk. */
export function readGlb(bytes: Uint8Array): { json: Record<string, unknown>; bin?: Uint8Array } {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.getUint32(0, true) !== 0x46546c67 || view.getUint32(4, true) !== 2) {
    throw new Error("Not a GLB 2.0 file");
  }
  if (view.getUint32(8, true) !== bytes.length) {
    throw new Error("GLB length field does not match the file size");
  }
  let offset = 12;
  let json: Record<string, unknown> | undefined;
  let bin: Uint8Array | undefined;
  while (offset < bytes.length) {
    const length = view.getUint32(offset, true);
    const type = view.getUint32(offset + 4, true);
    const body = bytes.subarray(offset + 8, offset + 8 + length);
    if (type === 0x4e4f534a) {
      json = JSON.parse(Buffer.from(body).toString("utf8")) as Record<string, unknown>;
    } else if (type === 0x004e4942) {
      bin = body;
    }
    offset += 8 + length;
  }
  if (json === undefined) {
    throw new Error("GLB has no JSON chunk");
  }
  return bin === undefined ? { json } : { json, bin };
}

/** Float32 positions of the first primitive of a GLB. */
export function glbPositions(bytes: Uint8Array): {
  positions: number[];
  min: number[];
  max: number[];
} {
  const { json, bin } = readGlb(bytes);
  if (bin === undefined) {
    throw new Error("GLB has no BIN chunk");
  }
  const accessors = json.accessors as Array<{
    bufferView: number;
    count: number;
    min?: number[];
    max?: number[];
  }>;
  const views = json.bufferViews as Array<{ byteOffset: number }>;
  const meshes = json.meshes as Array<{ primitives: Array<{ attributes: { POSITION: number } }> }>;
  const accessor = accessors[meshes[0]?.primitives[0]?.attributes.POSITION ?? 0];
  if (accessor === undefined) {
    throw new Error("No POSITION accessor");
  }
  const view = new DataView(bin.buffer, bin.byteOffset, bin.byteLength);
  const base = views[accessor.bufferView]?.byteOffset ?? 0;
  const positions: number[] = [];
  for (let i = 0; i < accessor.count * 3; i += 1) {
    positions.push(view.getFloat32(base + i * 4, true));
  }
  return { positions, min: accessor.min ?? [], max: accessor.max ?? [] };
}

/** Parses DXF group code / value pairs into entities. */
export interface DxfEntity {
  type: string;
  layer: string;
  groups: Array<[number, string]>;
}

export function parseDxf(text: string): {
  header: Map<string, string[]>;
  entities: DxfEntity[];
  layers: string[];
} {
  const lines = text.split(/\r?\n/);
  const pairs: Array<[number, string]> = [];
  for (let i = 0; i + 1 < lines.length; i += 2) {
    pairs.push([Number((lines[i] as string).trim()), (lines[i + 1] as string).trim()]);
  }
  const header = new Map<string, string[]>();
  const entities: DxfEntity[] = [];
  const layers: string[] = [];
  let section = "";
  let variable = "";
  let current: DxfEntity | undefined;
  let table = "";
  let inLayerRecord = false;
  for (const [code, value] of pairs) {
    if (code === 0 && value === "SECTION") {
      section = "";
      continue;
    }
    if (code === 2 && section === "") {
      section = value;
      continue;
    }
    if (code === 0 && value === "ENDSEC") {
      section = "";
      current = undefined;
      continue;
    }
    if (section === "HEADER") {
      if (code === 9) {
        variable = value;
        header.set(variable, []);
      } else {
        header.get(variable)?.push(value);
      }
    } else if (section === "TABLES") {
      if (code === 0 && value === "TABLE") {
        table = "";
      } else if (code === 2 && table === "" && !inLayerRecord) {
        table = value;
      } else if (code === 0) {
        inLayerRecord = table === "LAYER" && value === "LAYER";
      } else if (inLayerRecord && code === 2) {
        layers.push(value);
        inLayerRecord = false;
      }
    } else if (section === "ENTITIES") {
      if (code === 0) {
        current = { type: value, layer: "", groups: [] };
        entities.push(current);
      } else if (current !== undefined) {
        current.groups.push([code, value]);
        if (code === 8) {
          current.layer = value;
        }
      }
    }
  }
  return { header, entities, layers };
}

export function dxfNumbers(entity: DxfEntity, code: number): number[] {
  return entity.groups.filter(([c]) => c === code).map(([, value]) => Number(value));
}
