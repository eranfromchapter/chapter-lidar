// Assembles a complete intake package (layout.json folders, manifest with sha256) for a fixture.

import {
  LAYOUT,
  type CaptureModel,
  type CaptureRecord,
  type FieldControls,
  type FileEntry,
  type PackageManifest,
  type Role,
} from "@chapter/capture-contract";
import { buildCaptureRecord, buildFieldControls, type CaptureIds } from "./controls.js";
import { generateDepthSamples, writeDepthSamples, type DepthSample } from "./depth.js";
import { buildCaptureModel } from "./geometry.js";
import { jsonBytes } from "./json.js";
import { meshFromModel } from "./mesh.js";
import { buildRoomPlanJson } from "./roomplan.js";
import type { CaptureSpec, FixtureSpec } from "./spec.js";
import { OPERATOR_NAME, PLACEHOLDER_ADDRESS } from "./spec.js";
import { buildTruth, type TruthJson } from "./truth.js";
import { atLeast, seedFrom, sha256Hex, utf8, uuidFrom } from "./util.js";
import { writeCsv } from "./writers/csv.js";
import { writeDxf } from "./writers/dxf.js";
import { writeGlb } from "./writers/glb.js";
import { generatePhoto } from "./writers/jpeg.js";
import { writeLas } from "./writers/las.js";
import { MTL_NAME, TEXTURE_NAME, writeMtl, writeObj } from "./writers/obj.js";
import { writePlanPdf, writeReportPdf } from "./writers/pdf.js";
import { writePlanPng, writeTexturePng } from "./writers/png.js";
import { writeSvg } from "./writers/svg.js";

export const GENERATOR_VERSION = "1.0.0";
export const SEALED_AT = "2026-10-17T15:10:00Z";

export interface PackageFile {
  path: string;
  role: Role;
  captureId?: string;
  areaKey?: string;
  bytes: Uint8Array;
  mime: string;
  generator: string;
  generatorVersion: string;
  derivedFrom: string[];
  photo?: NonNullable<FileEntry["photo"]>;
}

export interface GeneratedPackage {
  fixture: FixtureSpec;
  visitId: string;
  packageId: string;
  truth: TruthJson;
  /** Every file except manifest.json. */
  files: PackageFile[];
  manifest: PackageManifest;
  /** Package-relative path of manifest.json. */
  manifestPath: string;
  /** Per capture: the generated source objects (kept for tests and mutations). */
  captures: Array<{
    spec: CaptureSpec;
    captureId: string;
    model: CaptureModel;
    samples: DepthSample[];
  }>;
  record: CaptureRecord;
  controls: FieldControls;
}

/** Folder path of a role, from layout.json. */
export function folderPath(
  role: Role,
  values: { visitId: string; areaKey?: string; captureId?: string },
): string {
  const folder = LAYOUT.folders.find((candidate) =>
    (candidate.roles as readonly string[]).includes(role),
  );
  if (folder === undefined) {
    throw new Error(`No layout folder for role ${role}`);
  }
  return folder.pathTemplate
    .replace("{visitId}", values.visitId)
    .replace("{areaKey}", values.areaKey ?? "")
    .replace("{captureId}", values.captureId ?? "");
}

export function manifestPathOf(visitId: string): string {
  return LAYOUT.manifestPath.replace("{visitId}", visitId);
}

/** Manifest entry of a file. */
export function entryOf(file: PackageFile): FileEntry {
  const entry: FileEntry = {
    path: file.path,
    role: file.role,
    ...(file.captureId === undefined ? {} : { captureId: file.captureId }),
    ...(file.areaKey === undefined ? {} : { areaKey: file.areaKey }),
    sha256: sha256Hex(file.bytes),
    bytes: file.bytes.length,
    mime: file.mime,
    generator: file.generator,
    generatorVersion: file.generatorVersion,
    derivedFrom: file.derivedFrom,
    ...(file.photo === undefined ? {} : { photo: file.photo }),
  };
  return entry;
}

export function buildManifest(
  visitId: string,
  packageId: string,
  files: readonly PackageFile[],
): PackageManifest {
  return {
    schemaVersion: "1.0.0",
    layoutVersion: "1.0.0",
    packageId,
    visitId,
    revision: 1,
    sealedAt: SEALED_AT,
    files: atLeast(files.map(entryOf), 1),
  };
}

function minutesAfter(timestamp: string, minutes: number): string {
  const date = new Date(timestamp);
  date.setUTCMinutes(date.getUTCMinutes() + minutes);
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

export async function buildPackage(fixture: FixtureSpec): Promise<GeneratedPackage> {
  const visitId = uuidFrom(`${fixture.name}:visit`);
  const packageId = uuidFrom(`${fixture.name}:package:1`);
  const ids = new Map<string, CaptureIds>(
    fixture.captures.map((capture) => [
      capture.areaKey,
      {
        captureId: uuidFrom(`${fixture.name}:capture:${capture.areaKey}`),
        areaKey: capture.areaKey,
      },
    ]),
  );
  const record = buildCaptureRecord(fixture, visitId, ids);
  const photoPaths = new Map<string, string>();
  const files: PackageFile[] = [];
  const captures: GeneratedPackage["captures"] = [];

  const per = fixture.captures.map((spec) => {
    const captureId = (ids.get(spec.areaKey) as CaptureIds).captureId;
    const dir = folderPath("capture_model", { visitId, areaKey: spec.areaKey, captureId });
    const photoDir = folderPath("photo", { visitId, areaKey: spec.areaKey, captureId });
    return { spec, captureId, dir, photoDir };
  });
  for (const { spec, photoDir } of per) {
    photoPaths.set(spec.areaKey, `${photoDir}photo-0001.jpg`);
  }
  const controls = buildFieldControls(fixture, visitId, ids, photoPaths);

  files.push(
    {
      path: `${folderPath("capture_record", { visitId })}${LAYOUT.fileNames.capture_record}`,
      role: "capture_record",
      bytes: await jsonBytes(record),
      mime: "application/json",
      generator: "chapter-fixtures/CaptureRecord",
      generatorVersion: GENERATOR_VERSION,
      derivedFrom: [],
    },
    {
      path: `${folderPath("field_controls", { visitId })}${LAYOUT.fileNames.field_controls}`,
      role: "field_controls",
      bytes: await jsonBytes(controls),
      mime: "application/json",
      generator: "chapter-fixtures/FieldControls",
      generatorVersion: GENERATOR_VERSION,
      derivedFrom: [],
    },
  );

  for (const { spec, captureId, dir, photoDir } of per) {
    const areaKey = spec.areaKey;
    const path = (name: string) => `${dir}${name}`;
    const refs: CaptureModel["refs"] = [
      { role: "raw_roomplan_json", path: path("roomplan.json") },
      { role: "raw_depth", path: path("depth-samples.bin") },
      { role: "mesh_glb", path: path("mesh.glb") },
      { role: "mesh_obj", path: path("mesh.obj") },
      { role: "point_cloud_las", path: path("points.las") },
    ];
    const model = buildCaptureModel(spec, { visitId, captureId, refs });
    const samples = generateDepthSamples(model, seedFrom(`${fixture.name}:${areaKey}:depth`));
    const mesh = meshFromModel(model);
    const captureRecord = record.captures.find((c) => c.captureId === captureId);
    const meta = {
      address: PLACEHOLDER_ADDRESS,
      captureId,
      projectName: `Fixture ${fixture.name}`,
      operator: OPERATOR_NAME,
      date: (captureRecord?.capturedAt ?? "").slice(0, 10),
    };
    const pdfs = { plan: writePlanPdf(model, meta), report: writeReportPdf(model, meta) };
    const own = { captureId, areaKey };
    const make = (
      name: string,
      role: Role,
      bytes: Uint8Array,
      mime: string,
      generator: string,
      derivedFrom: string[],
    ): PackageFile => ({
      path: path(name),
      role,
      ...own,
      bytes,
      mime,
      generator: `chapter-fixtures/${generator}`,
      generatorVersion: GENERATOR_VERSION,
      derivedFrom,
    });
    const modelPath = path("capture-model.json");
    files.push(
      make(
        "roomplan.json",
        "raw_roomplan_json",
        await jsonBytes(buildRoomPlanJson(spec, captureId)),
        "application/json",
        "CaptureCore",
        [],
      ),
      make(
        "depth-samples.bin",
        "raw_depth",
        writeDepthSamples(samples),
        "application/octet-stream",
        "CaptureCore",
        [],
      ),
      make(
        "capture-model.json",
        "capture_model",
        await jsonBytes(model),
        "application/json",
        "CaptureCore",
        [path("roomplan.json")],
      ),
      make("plan.dxf", "plan_dxf", utf8(writeDxf(model)), "image/vnd.dxf", "PlanExport", [
        modelPath,
      ]),
      make("rooms.csv", "rooms_csv", utf8(writeCsv(model)), "text/csv", "PlanExport", [modelPath]),
      make("plan.pdf", "plan_pdf", pdfs.plan, "application/pdf", "PlanExport", [modelPath]),
      make(
        "spatial-report.pdf",
        "spatial_report_pdf",
        pdfs.report,
        "application/pdf",
        "PlanExport",
        [modelPath],
      ),
      make("plan.png", "plan_png", writePlanPng(model), "image/png", "PlanExport", [modelPath]),
      make("plan.svg", "plan_svg", utf8(writeSvg(model)), "image/svg+xml", "PlanExport", [
        modelPath,
      ]),
      make(
        "mesh.glb",
        "mesh_glb",
        writeGlb(mesh, { name: spec.label }),
        "model/gltf-binary",
        "MeshExport",
        [modelPath],
      ),
      make("mesh.obj", "mesh_obj", utf8(writeObj(mesh, spec.label)), "model/obj", "MeshExport", [
        modelPath,
      ]),
      make(MTL_NAME, "mesh_mtl", utf8(writeMtl()), "model/mtl", "MeshExport", [modelPath]),
      make(TEXTURE_NAME, "texture", writeTexturePng(), "image/png", "MeshExport", []),
      make(
        "points.las",
        "point_cloud_las",
        writeLas(samples),
        "application/vnd.las",
        "MeshExport",
        [path("depth-samples.bin")],
      ),
    );
    spec.rooms.forEach((room, index) => {
      const photoName = `photo-${String(index + 1).padStart(4, "0")}.jpg`;
      files.push({
        path: `${photoDir}${photoName}`,
        role: "photo",
        ...own,
        bytes: generatePhoto(seedFrom(`${fixture.name}:${areaKey}:photo:${room.id}`)),
        mime: "image/jpeg",
        generator: "chapter-fixtures/FieldKit",
        generatorVersion: GENERATOR_VERSION,
        derivedFrom: [],
        photo: {
          room: room.label,
          direction: "N",
          subject: "general",
          takenAt: minutesAfter(captureRecord?.capturedAt ?? "2026-10-17T14:02:11Z", 5 + index),
        },
      });
    });
    captures.push({ spec, captureId, model, samples });
  }

  const truth = buildTruth(
    fixture,
    visitId,
    new Map(per.map((entry) => [entry.spec.areaKey, entry.captureId])),
  );
  return {
    fixture,
    visitId,
    packageId,
    truth,
    files,
    manifest: buildManifest(visitId, packageId, files),
    manifestPath: manifestPathOf(visitId),
    captures,
    record,
    controls,
  };
}
