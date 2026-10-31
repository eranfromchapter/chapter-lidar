// Display rules of the review screen (web-review spec §5.4, §6.4.6): sizes, lengths, areas,
// dates in Eastern Time, ids, file names and role labels. Verdict and check words are not here:
// they come from @chapter/capture-contract's review-text so the spatial report prints the same.

import type { CaptureMode, CaptureRecord, Role } from "@chapter/capture-contract";
import type { PackageFile } from "./station-types";

/** Every Chapter market is on Eastern Time; dates and times are shown there. */
export const TIME_ZONE = "America/New_York";

const UNITS = ["B", "KB", "MB", "GB", "TB"] as const;

/** Decimal sizes: "999 B", "14 KB", "1.2 MB", "96 MB", "768 MB" (one decimal below 10). */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 1000) {
    return `${Math.max(0, Math.round(bytes))} B`;
  }
  let unit = 0;
  let value = bytes;
  while (value >= 1000 && unit < UNITS.length - 1) {
    value /= 1000;
    unit += 1;
  }
  let rounded = value < 10 ? Math.round(value * 10) / 10 : Math.round(value);
  if (rounded >= 1000 && unit < UNITS.length - 1) {
    rounded = 1;
    unit += 1;
  }
  return `${rounded} ${UNITS[unit]}`;
}

const GROUPED = new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 });
const ONE_DECIMAL = new Intl.NumberFormat("en-US", {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});

/** "7,520 mm" */
export function formatMm(valueMm: number): string {
  return `${GROUPED.format(Math.round(valueMm))} mm`;
}

/** "807.5 sq ft" */
export function formatSqFt(squareFeet: number): string {
  return `${ONE_DECIMAL.format(squareFeet)} sq ft`;
}

function parse(iso: string): Date | undefined {
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

const DATE_FORMAT = new Intl.DateTimeFormat("en-US", {
  timeZone: TIME_ZONE,
  year: "numeric",
  month: "short",
  day: "numeric",
});

const DAY_FORMAT = new Intl.DateTimeFormat("en-US", {
  timeZone: TIME_ZONE,
  month: "short",
  day: "numeric",
});

const DATE_TIME_FORMAT = new Intl.DateTimeFormat("en-US", {
  timeZone: TIME_ZONE,
  year: "numeric",
  month: "short",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
  timeZoneName: "short",
});

const TIME_24_FORMAT = new Intl.DateTimeFormat("en-US", {
  timeZone: TIME_ZONE,
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

const DAY_KEY_FORMAT = new Intl.DateTimeFormat("en-CA", {
  timeZone: TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

const YEAR_FORMAT = new Intl.DateTimeFormat("en-US", { timeZone: TIME_ZONE, year: "numeric" });

/** "Oct 17, 2026" */
export function formatDate(iso: string): string {
  const date = parse(iso);
  return date === undefined ? iso : DATE_FORMAT.format(date);
}

/** "Oct 17, 2026, 11:20 AM EDT": the full time, for title attributes. */
export function formatDateTime(iso: string): string {
  const date = parse(iso);
  return date === undefined ? iso : DATE_TIME_FORMAT.format(date);
}

/** "14:02" (24 h, Eastern Time). */
function time24(date: Date): string {
  return TIME_24_FORMAT.format(date);
}

/** The New York calendar day of a time, "2026-05-16". */
function dayKey(date: Date): string {
  return DAY_KEY_FORMAT.format(date);
}

/** "May 16, 2026 14:02" (24 h, Eastern Time, no zone). */
export function formatDateTime24(iso: string): string {
  const date = parse(iso);
  return date === undefined ? iso : `${DATE_FORMAT.format(date)} ${time24(date)}`;
}

/** "May 16 · 13:58", or only "14:01" when on the same New York day as `previous`. */
export function formatDayTime(iso: string, previous?: string): string {
  const date = parse(iso);
  if (date === undefined) {
    return iso;
  }
  const before = previous === undefined ? undefined : parse(previous);
  if (before !== undefined && dayKey(before) === dayKey(date)) {
    return time24(date);
  }
  return `${DAY_FORMAT.format(date)} · ${time24(date)}`;
}

/** "Today" when the New York calendar day of `iso` is today's, else "Jan 25, 2025". */
export function dayLabel(iso: string, now: Date = new Date()): string {
  const date = parse(iso);
  if (date === undefined) {
    return iso;
  }
  return dayKey(date) === dayKey(now) ? "Today" : DATE_FORMAT.format(date);
}

/**
 * "just now" (under a minute), "{m} min ago", "{h} h ago" (under a day), else the date, without
 * the year when it is this year.
 */
export function updatedAgo(iso: string, now: Date = new Date()): string {
  const date = parse(iso);
  if (date === undefined) {
    return iso;
  }
  const seconds = Math.max(0, (now.getTime() - date.getTime()) / 1000);
  if (seconds < 60) {
    return "just now";
  }
  if (seconds < 3600) {
    return `${Math.floor(seconds / 60)} min ago`;
  }
  if (seconds < 86_400) {
    return `${Math.floor(seconds / 3600)} h ago`;
  }
  return YEAR_FORMAT.format(date) === YEAR_FORMAT.format(now)
    ? DAY_FORMAT.format(date)
    : DATE_FORMAT.format(date);
}

/** "9f2c…a41e" */
export function shortSha(sha256: string): string {
  return sha256.length <= 8 ? sha256 : `${sha256.slice(0, 4)}…${sha256.slice(-4)}`;
}

/** "3f6c2a9e…" */
export function shortId(uuid: string): string {
  return uuid.length <= 8 ? uuid : `${uuid.slice(0, 8)}…`;
}

export function plural(count: number, singular: string, pluralForm = `${singular}s`): string {
  return `${count} ${count === 1 ? singular : pluralForm}`;
}

export const MODE_LABEL: Record<CaptureMode, string> = {
  room: "one room",
  floor: "whole floor",
  exterior: "exterior",
};

/** "whole floor × 1", "whole floor × 2", "whole floor × 1, exterior × 1" */
export function modeSummary(modes: readonly CaptureMode[]): string {
  const counts = new Map<CaptureMode, number>();
  for (const mode of modes) {
    counts.set(mode, (counts.get(mode) ?? 0) + 1);
  }
  return [...counts.entries()].map(([mode, count]) => `${MODE_LABEL[mode]} × ${count}`).join(", ");
}

/** "floor" when every capture is a whole floor (or nothing is known yet), else "area". */
export function areaNoun(modes: readonly (CaptureMode | undefined)[]): "floor" | "area" {
  return modes.every((mode) => mode === undefined || mode === "floor") ? "floor" : "area";
}

/** "2 floors", "1 floor", or "3 areas" when not every capture is a whole floor. */
export function areaCount(modes: readonly (CaptureMode | undefined)[]): string {
  return plural(modes.length, areaNoun(modes));
}

/** "primary-closet" -> "Primary closet", "floor-1" -> "Floor 1". */
export function humanizeAreaKey(areaKey: string): string {
  const words = areaKey.split(/[-_]+/).filter((word) => word.length > 0);
  const text = words.join(" ");
  return text.length === 0 ? areaKey : text.charAt(0).toUpperCase() + text.slice(1);
}

/** Label of a capture: the capture record's, else the humanised areaKey. */
export function captureLabel(
  record: CaptureRecord | undefined,
  captureId: string | undefined,
  areaKey: string | undefined,
): string | undefined {
  if (captureId === undefined) {
    return areaKey === undefined ? undefined : humanizeAreaKey(areaKey);
  }
  const capture = record?.captures.find((item) => item.captureId === captureId);
  if (capture !== undefined) {
    return capture.label;
  }
  return areaKey === undefined ? undefined : humanizeAreaKey(areaKey);
}

/** Row label of each package file role (web-review §6.4.6). */
export const ROLE_LABEL: Record<Role, string> = {
  plan_dxf: "Plan DXF",
  rooms_csv: "Rooms CSV",
  plan_pdf: "Plan sheet PDF",
  plan_png: "Plan PNG",
  plan_svg: "Plan SVG",
  mesh_glb: "Mesh GLB",
  mesh_obj: "Mesh OBJ",
  mesh_mtl: "Mesh MTL",
  texture: "Texture",
  point_cloud_las: "Point cloud LAS",
  raw_roomplan_json: "Raw RoomPlan",
  raw_depth: "Depth",
  capture_model: "Capture model",
  photo: "Site photo",
  field_controls: "Field controls",
  capture_record: "Capture record",
  spatial_report_pdf: "Spatial report · phone (retired)",
  sketch_image: "Sketch image",
  sketch_measurements: "Sketch measurements",
  walkthrough_video: "Walkthrough video",
  walkthrough_log: "Walkthrough log",
  sketch_interpretation: "Sketch reading",
};

/** Files card role filter group of each role. */
export const ROLE_FILTER_GROUP: Record<Role, string> = {
  plan_dxf: "Plan DXF",
  rooms_csv: "Rooms CSV",
  plan_pdf: "Plan sheet PDF",
  plan_png: "Plan PNG",
  plan_svg: "Plan SVG",
  mesh_glb: "Mesh GLB",
  mesh_obj: "OBJ + MTL",
  mesh_mtl: "OBJ + MTL",
  texture: "OBJ + MTL",
  point_cloud_las: "Point cloud LAS",
  raw_roomplan_json: "Raw RoomPlan",
  raw_depth: "Depth",
  capture_model: "Capture model",
  photo: "Site photo",
  field_controls: "Field controls",
  capture_record: "Capture record",
  spatial_report_pdf: "Spatial report",
  sketch_image: "Sketch",
  sketch_measurements: "Sketch",
  walkthrough_video: "Walkthrough",
  walkthrough_log: "Walkthrough",
  sketch_interpretation: "Sketch",
};

/**
 * File name shown to people: "Floor 1 / plan.dxf" for a capture's file (mesh companions keep
 * their subfolder), the bare file name for visit-wide files.
 */
export function fileDisplayName(
  path: string,
  record: CaptureRecord | undefined,
  captureId?: string,
  areaKey?: string,
): string {
  const segments = path.split("/");
  let name = segments[segments.length - 1] ?? path;
  if (captureId !== undefined) {
    const index = segments.indexOf(captureId);
    if (index >= 0 && index < segments.length - 1) {
      name = segments.slice(index + 1).join("/");
    }
  }
  const label = captureId === undefined ? undefined : captureLabel(record, captureId, areaKey);
  return label === undefined ? name : `${label} / ${name}`;
}

const UUID_SEGMENT = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/**
 * Display name of a package path, using the package file entry when there is one. Without it
 * (a list across packages), a capture file is recognised by the layout's
 * "{folder}/{areaKey}/{captureId}/{name}" segments and labelled from its areaKey.
 */
export function pathDisplayName(
  path: string,
  files: readonly PackageFile[],
  record: CaptureRecord | undefined,
): string {
  const file = files.find((item) => item.path === path);
  if (file !== undefined) {
    return fileDisplayName(path, record, file.captureId, file.areaKey);
  }
  const segments = path.split("/");
  const index = segments.findIndex((segment, at) => at >= 2 && UUID_SEGMENT.test(segment));
  if (index >= 2 && index < segments.length - 1) {
    return fileDisplayName(path, record, segments[index], segments[index - 1]);
  }
  return fileDisplayName(path, record);
}
