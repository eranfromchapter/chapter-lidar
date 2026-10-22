// Reads what the spatial report is made from, through the publisher's verified reader: the
// capture model of every floor, the field controls and the site photos (reduced one at a time).
// A capture model that does not match the contract is "unreadable" (the report says so); a file
// the storage cannot give back fails like any other read (the job retries or fails).
//
// Size budget (spec 5.6.6), decided before drawing: estimate = sum of the reduced photos + 2 MiB.
// Over 40 MiB, every photo is reduced again to 267 x 333 px at quality 70; still over, the photo
// pages are left out (each room page's footnote says so).

import {
  validateCaptureModel,
  validateFieldControls,
  type CaptureModel,
  type CaptureRecord,
  type FieldControls,
  type PhotoDirection,
  type PhotoSubject,
} from "@chapter/capture-contract";
import type { ReportFloorSource, ReportPhoto } from "./input.js";
import { reducePhoto, shrinkPhoto } from "./photos.js";

export const PHOTO_BUDGET_BYTES = 40 * 1024 * 1024;
const PDF_OVERHEAD_BYTES = 2 * 1024 * 1024;

/** A package file as the publication plan knows it. */
export interface SourceFile {
  readonly path: string;
  readonly role: string;
  readonly captureId?: string;
  readonly areaKey?: string;
  /** Manifest photo labels (role photo). */
  readonly photo?: {
    readonly room: string;
    readonly direction: PhotoDirection;
    readonly subject: PhotoSubject;
    readonly takenAt: string;
  };
}

export interface SourceRequest {
  readonly files: readonly SourceFile[];
  readonly captureRecord?: CaptureRecord;
  /** Verified bytes of one package file. */
  readFile(path: string): Promise<Uint8Array>;
}

export interface ReportSources {
  readonly floors: readonly ReportFloorSource[];
  readonly fieldControls?: FieldControls | "invalid";
  readonly photos: readonly ReportPhoto[];
  readonly photosOmitted: boolean;
}

export interface SourceOptions {
  /** Budget for the reduced photos (tests lower it). */
  readonly photoBudgetBytes?: number;
}

function parseJson(bytes: Uint8Array): unknown {
  try {
    return JSON.parse(Buffer.from(bytes).toString("utf8")) as unknown;
  } catch {
    return undefined;
  }
}

export async function loadReportSources(
  request: SourceRequest,
  options: SourceOptions = {},
): Promise<ReportSources> {
  const files = request.files;
  // Floors: the capture record's captures, else the distinct captures of the files.
  const captures: Array<{ captureId: string; areaKey: string }> =
    request.captureRecord?.captures.map((c) => ({ captureId: c.captureId, areaKey: c.areaKey })) ??
    [];
  if (captures.length === 0) {
    for (const file of files) {
      if (
        file.captureId !== undefined &&
        file.areaKey !== undefined &&
        !captures.some((c) => c.captureId === file.captureId)
      ) {
        captures.push({ captureId: file.captureId, areaKey: file.areaKey });
      }
    }
  }
  const floors: ReportFloorSource[] = [];
  for (const capture of captures) {
    const file = files.find((f) => f.role === "capture_model" && f.captureId === capture.captureId);
    if (file === undefined) {
      floors.push({ ...capture, model: { status: "absent" } });
      continue;
    }
    const checked = validateCaptureModel(parseJson(await request.readFile(file.path)));
    floors.push({
      ...capture,
      model: checked.ok
        ? { status: "ok", model: checked.value as CaptureModel }
        : { status: "unreadable" },
    });
  }

  let fieldControls: FieldControls | "invalid" | undefined;
  const controlsFile = files.find((f) => f.role === "field_controls");
  if (controlsFile !== undefined) {
    const checked = validateFieldControls(parseJson(await request.readFile(controlsFile.path)));
    fieldControls = checked.ok ? (checked.value as FieldControls) : "invalid";
  }

  const photos: ReportPhoto[] = [];
  for (const file of files) {
    if (file.role !== "photo" || file.photo === undefined) {
      continue;
    }
    const image = await reducePhoto(await request.readFile(file.path));
    photos.push({
      path: file.path,
      ...(file.captureId === undefined ? {} : { captureId: file.captureId }),
      ...(file.areaKey === undefined ? {} : { areaKey: file.areaKey }),
      room: file.photo.room,
      direction: file.photo.direction,
      subject: file.photo.subject,
      takenAt: file.photo.takenAt,
      ...(image === undefined ? {} : { image }),
    });
  }
  const budget = options.photoBudgetBytes ?? PHOTO_BUDGET_BYTES;
  const estimate = (list: readonly ReportPhoto[]) =>
    list.reduce((sum, photo) => sum + (photo.image?.byteLength ?? 0), 0) + PDF_OVERHEAD_BYTES;
  let reduced = photos;
  if (estimate(reduced) > budget) {
    const smaller: ReportPhoto[] = [];
    for (const photo of photos) {
      const image = photo.image === undefined ? undefined : await shrinkPhoto(photo.image);
      const { image: _old, ...rest } = photo;
      smaller.push({ ...rest, ...(image === undefined ? {} : { image }) });
    }
    reduced = smaller;
  }
  if (estimate(reduced) > budget) {
    return {
      floors,
      ...(fieldControls === undefined ? {} : { fieldControls }),
      photos: [],
      photosOmitted: true,
    };
  }
  return {
    floors,
    ...(fieldControls === undefined ? {} : { fieldControls }),
    photos: reduced,
    photosOmitted: false,
  };
}
