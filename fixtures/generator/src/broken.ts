// Broken fixtures for negative checks. Each is the box-room good fixture with exactly ONE
// mutation of one file; the manifest is rebuilt so it stays consistent with the mutated bytes
// (these are not fingerprint-mismatch defects).

import type { CaptureModel, FieldControls } from "@chapter/capture-contract";
import { secondsAfter } from "./controls.js";
import { jsonBytes } from "./json.js";
import { meshFromModel } from "./mesh.js";
import { buildManifest, type GeneratedPackage, type PackageFile } from "./package.js";
import { OTHER_PLACEHOLDER_ADDRESS, PLACEHOLDER_ADDRESS } from "./spec.js";
import { atLeast, round6, uuidFrom } from "./util.js";
import { writeGlb } from "./writers/glb.js";
import { readLasHeader } from "./writers/las.js";

export const DEFECT_IDS = [
  "empty-file",
  "wrong-address",
  "inches-as-metres",
  "z-up-mesh",
  "missing-gltf-bin",
  "las-bad-header",
  "dimensions-3pct-off",
  "compass-time-outside-scan",
] as const;

/** The compass-time-outside-scan reading was taken this long before the scan started. */
export const COMPASS_EARLY_SECONDS = 2 * 60 * 60;

export type DefectId = (typeof DEFECT_IDS)[number];

/** Contents of defect.json. */
export interface DefectJson {
  defectId: DefectId;
  title: string;
  baseFixture: string;
  /** Package-relative path of the one file that was changed. */
  affectedFile: string;
  role: string;
  mutation: string;
  details: Record<string, unknown>;
}

export interface BrokenFixture {
  defectId: DefectId;
  defect: DefectJson;
  packageId: string;
  visitId: string;
  files: PackageFile[];
  manifestPath: string;
  manifest: ReturnType<typeof buildManifest>;
}

/** Metres to the number a person would write if the value were inches, at 1e-6 precision. */
export const INCHES_PER_METRE = 1 / 0.0254;
/** Field controls in the dimensions-3pct-off fixture read this fraction of the true distance. */
export const CONTROL_FACTOR = 0.97;

function find(files: readonly PackageFile[], role: string): PackageFile {
  const file = files.find((candidate) => candidate.role === role);
  if (file === undefined) {
    throw new Error(`Base fixture has no ${role} file`);
  }
  return file;
}

function scaleVec(v: number[], factor: number): number[] {
  return v.map((value) => round6(value * factor));
}

/** Writes metre fields as if the numbers were inches: every length is multiplied by 39.37. */
export function scaleModelLengths(model: CaptureModel, factor: number): CaptureModel {
  const scale = (value: number) => round6(value * factor);
  return {
    ...model,
    rooms: model.rooms.map((room) => ({
      ...room,
      polygon: atLeast(
        room.polygon.map((point) => scaleVec(point, factor) as [number, number, number]),
        3,
      ),
      heightM: scale(room.heightM),
    })),
    walls: model.walls.map((wall) => ({
      ...wall,
      start: scaleVec(wall.start, factor) as [number, number, number],
      end: scaleVec(wall.end, factor) as [number, number, number],
      heightM: scale(wall.heightM),
      thicknessM: scale(wall.thicknessM),
    })),
    doors: model.doors.map((o) => scaleOpening(o, scale)),
    windows: model.windows.map((o) => scaleOpening(o, scale)),
    openings: model.openings.map((o) => scaleOpening(o, scale)),
    objects: model.objects.map((object) => ({
      ...object,
      box: {
        ...object.box,
        center: scaleVec(object.box.center, factor) as [number, number, number],
        sizeM: scaleVec(object.box.sizeM, factor) as [number, number, number],
      },
    })),
  };
}

function scaleOpening<
  T extends { offsetM: number; bottomM: number; widthM: number; heightM: number },
>(opening: T, scale: (value: number) => number): T {
  return {
    ...opening,
    offsetM: scale(opening.offsetM),
    bottomM: scale(opening.bottomM),
    widthM: scale(opening.widthM),
    heightM: scale(opening.heightM),
  };
}

/** Distances of the field controls read as a fraction of the truth, entered in millimetres. */
export function scaleControlDistances(controls: FieldControls, factor: number): FieldControls {
  return {
    ...controls,
    distances: controls.distances.map((distance) => {
      const valueMm = round6(distance.measurement.valueMm * factor);
      return {
        ...distance,
        measurement: {
          ...distance.measurement,
          valueMm,
          enteredUnit: "mm" as const,
          enteredText: String(valueMm),
        },
      };
    }),
  };
}

export async function buildBrokenFixtures(base: GeneratedPackage): Promise<BrokenFixture[]> {
  const capture = base.captures[0];
  if (capture === undefined || base.captures.length !== 1) {
    throw new Error("Broken fixtures derive from the one-capture box-room fixture");
  }
  const out: BrokenFixture[] = [];

  const derive = (
    defectId: DefectId,
    title: string,
    role: string,
    mutation: string,
    details: Record<string, unknown> | ((file: PackageFile) => Record<string, unknown>),
    mutate: (file: PackageFile) => Promise<Uint8Array> | Uint8Array,
  ) => {
    return (async () => {
      const original = find(base.files, role);
      const bytes = await mutate(original);
      const files = base.files.map((file) => (file === original ? { ...file, bytes } : file));
      const packageId = uuidFrom(`${base.fixture.name}:package:broken:${defectId}`);
      out.push({
        defectId,
        defect: {
          defectId,
          title,
          baseFixture: base.fixture.name,
          affectedFile: original.path,
          role,
          mutation,
          details: typeof details === "function" ? details(original) : details,
        },
        packageId,
        visitId: base.visitId,
        files,
        manifestPath: base.manifestPath,
        manifest: buildManifest(base.visitId, packageId, files),
      });
    })();
  };

  await derive(
    "empty-file",
    "A package file is empty",
    "plan_dxf",
    "plan.dxf replaced by a zero-byte file; the manifest records 0 bytes and the SHA-256 of nothing.",
    {},
    () => new Uint8Array(0),
  );

  await derive(
    "wrong-address",
    "Capture record address differs from the HUB address",
    "capture_record",
    "address.formatted in capture-record.json changed to a different placeholder address.",
    { hubAddress: PLACEHOLDER_ADDRESS, recordedAddress: OTHER_PLACEHOLDER_ADDRESS },
    () =>
      jsonBytes({
        ...base.record,
        address: { ...base.record.address, formatted: OTHER_PLACEHOLDER_ADDRESS },
      }),
  );

  await derive(
    "inches-as-metres",
    "Inch values written into metre fields",
    "capture_model",
    "Every length in capture-model.json (polygons, wall ends, heights, thickness, openings, object boxes) multiplied by 39.37007874, as if inches were written into metre fields.",
    {
      factor: round6(INCHES_PER_METRE),
      example: { truthRoomWidthM: 4, writtenRoomWidth: round6(4 * INCHES_PER_METRE) },
      note: "Only capture-model.json is changed; derived plan and mesh files keep the true geometry.",
    },
    () => jsonBytes(scaleModelLengths(capture.model, INCHES_PER_METRE)),
  );

  await derive(
    "z-up-mesh",
    "GLB mesh is Z-up",
    "mesh_glb",
    "mesh.glb rewritten with the vertical axis as +Z: (x, y, z) -> (x, -z, y) for positions and normals.",
    { vertical: "+Z", expected: "+Y" },
    () => writeGlb(meshFromModel(capture.model), { name: capture.spec.label, zUp: true }),
  );

  await derive(
    "missing-gltf-bin",
    "glTF binary companion is missing",
    "mesh_glb",
    "mesh.glb rewritten so its only buffer is the external file mesh.bin (no BIN chunk); mesh.bin is not in the package.",
    { bufferUri: "mesh.bin", missingCompanion: "mesh.bin next to mesh.glb" },
    () =>
      writeGlb(meshFromModel(capture.model), {
        name: capture.spec.label,
        externalBufferUri: "mesh.bin",
      }),
  );

  await derive(
    "las-bad-header",
    "LAS header point count does not match the data",
    "point_cloud_las",
    "Number of point records (64-bit, offset 247) in points.las raised by 1000; the file holds fewer points than its header says.",
    (file) => ({
      headerPointCount: readLasHeader(file.bytes).count + 1000,
      actualPointCount: readLasHeader(file.bytes).count,
    }),
    (file) => {
      const bytes = new Uint8Array(file.bytes);
      const view = new DataView(bytes.buffer);
      const wrong = BigInt(readLasHeader(file.bytes).count + 1000);
      view.setBigUint64(247, wrong, true);
      view.setBigUint64(255, wrong, true);
      return bytes;
    },
  );

  const truthDistances = base.controls.distances;
  await derive(
    "dimensions-3pct-off",
    "Field controls are 3% short of the true dimensions",
    "field_controls",
    "Every long distance in field-controls.json multiplied by 0.97 and entered in millimetres.",
    {
      factor: CONTROL_FACTOR,
      distances: truthDistances.map((distance) => {
        const controlMm = round6(distance.measurement.valueMm * CONTROL_FACTOR);
        return {
          id: distance.id,
          truthMm: distance.measurement.valueMm,
          controlMm,
          scanMinusControlPercentOfControl: round6(
            ((distance.measurement.valueMm - controlMm) / controlMm) * 100,
          ),
          scanMinusControlPercentOfScan: round6(
            ((distance.measurement.valueMm - controlMm) / distance.measurement.valueMm) * 100,
          ),
        };
      }),
    },
    () => jsonBytes(scaleControlDistances(base.controls, CONTROL_FACTOR)),
  );

  const scan = base.record.captures[0];
  if (scan === undefined) {
    throw new Error("Base fixture has no capture in its record");
  }
  const reading = {
    heading: 212.4,
    headingAccuracy: 8,
    headingSource: "true" as const,
    headingRecordedAt: secondsAfter(scan.capturedAt, -COMPASS_EARLY_SECONDS),
  };
  await derive(
    "compass-time-outside-scan",
    "Compass reading taken outside the scan",
    "capture_record",
    "capture-record.json written as 1.1.0 with a true-north compass reading (212.4°, ±8°) whose headingRecordedAt is 2 h before the capture's capturedAt, so it cannot belong to the scan.",
    {
      capturedAt: scan.capturedAt,
      finishedAt: scan.finishedAt,
      ...reading,
    },
    () =>
      jsonBytes({
        ...base.record,
        schemaVersion: "1.1.0",
        captures: atLeast(
          base.record.captures.map((capture, index) =>
            index === 0 ? { ...capture, ...reading } : capture,
          ),
          1,
        ),
      }),
  );

  // Keep the declared order.
  return DEFECT_IDS.map((id) => out.find((entry) => entry.defectId === id) as BrokenFixture);
}
