// Display rules from the frozen design (docs/waves/design/DESIGN.md, screen-review).

import type {
  CaptureMode,
  CaptureRecord,
  Outcome,
  Role,
  Severity,
} from "@chapter/capture-contract";
import type { PackageFile, PackageStatus } from "./station-types";

/** Verdicts always carry a word and a shape, never colour alone. */
export const OUTCOME = {
  ready: {
    shape: "●",
    word: "Ready",
    plain: "ready for the stated preliminary task",
  },
  limited: {
    shape: "▲",
    word: "Limited",
    plain: "usable with named limitations",
  },
  blocked: {
    shape: "■",
    word: "Blocked",
    plain: "missing information prevents the task",
  },
} as const satisfies Record<Outcome, { shape: string; word: string; plain: string }>;

/** "▲ Limited" */
export function outcomeLabel(outcome: Outcome): string {
  return `${OUTCOME[outcome].shape} ${OUTCOME[outcome].word}`;
}

/** "▲ Limited: usable with named limitations" */
export function outcomeHeadline(outcome: Outcome): string {
  return `${outcomeLabel(outcome)}: ${OUTCOME[outcome].plain}`;
}

/** Severity groups in the order they are listed. */
export const SEVERITY_ORDER: readonly Severity[] = ["blocker", "limitation", "info"];

export const SEVERITY_GROUP: Record<Severity, string> = {
  blocker: "Blockers",
  limitation: "Limitations",
  info: "Information and passed checks",
};

/**
 * Severity cell of a finding. Info findings of a passed check read "● Passed" as in the design;
 * other info findings read "● Info".
 */
export function severityLabel(severity: Severity, checkPassed: boolean): string {
  switch (severity) {
    case "blocker":
      return "■ Blocker";
    case "limitation":
      return "▲ Limited";
    case "info":
      return checkPassed ? "● Passed" : "● Info";
  }
}

/** CSS tone of a severity cell. */
export function severityTone(severity: Severity): "blocked" | "limited" | "ready" {
  switch (severity) {
    case "blocker":
      return "blocked";
    case "limitation":
      return "limited";
    case "info":
      return "ready";
  }
}

export const PACKAGE_STATUS: Record<PackageStatus, string> = {
  uploading: "Uploading",
  checks_queued: "Checks queued",
  checking: "Checks running",
  verdict_ready: "Verdict ready",
  check_error: "Check error",
};

export const ROLE_LABEL: Record<Role, string> = {
  capture_record: "Capture record",
  raw_roomplan_json: "RoomPlan JSON (raw)",
  raw_depth: "Depth samples (raw)",
  capture_model: "Capture model",
  plan_dxf: "Plan DXF",
  rooms_csv: "Rooms CSV",
  plan_pdf: "Plan PDF",
  spatial_report_pdf: "Spatial report PDF",
  plan_png: "Plan PNG",
  plan_svg: "Plan SVG",
  mesh_glb: "Mesh GLB",
  mesh_obj: "Mesh OBJ",
  mesh_mtl: "Mesh MTL",
  texture: "Texture",
  point_cloud_las: "Point cloud LAS",
  photo: "Photo",
  field_controls: "Field controls",
};

export const MODE_LABEL: Record<CaptureMode, string> = {
  room: "one room",
  floor: "whole floor",
  exterior: "exterior",
};

/**
 * HUB upload cap shown on screen-review: an upload-role file is linked, not uploaded, when its
 * size is over this many bytes (45 MiB = 47,185,920). MUST match MAX_HUB_UPLOAD_BYTES in
 * station/hub/src/plan.ts, the authoritative publisher (a test guards against drift).
 */
export const HUB_LINK_THRESHOLD_BYTES = 45 * 1024 * 1024;

/**
 * Package file roles the station uploads to the HUB (when not over the size cap). MUST match
 * HUB_UPLOAD_ROLES in station/hub/src/plan.ts (a test guards against drift). Every other
 * package file is only listed in the verdict report with a link to this screen.
 */
export const HUB_UPLOAD_ROLES: readonly Role[] = Object.freeze([
  "plan_dxf",
  "rooms_csv",
  "plan_pdf",
  "spatial_report_pdf",
  "plan_png",
]);

/**
 * "In the HUB" cell: the station's publication rule for this file, not live HUB state (the
 * station API exposes no per-file publish state). Upload roles up to the cap are "Uploaded",
 * larger ones "Linked (over 45 MB)" (the design's wording); every other role is "Linked",
 * reachable only through this screen.
 */
export function hubState(role: Role, bytes: number): string {
  if (!HUB_UPLOAD_ROLES.includes(role)) {
    return "Linked";
  }
  return bytes > HUB_LINK_THRESHOLD_BYTES ? "Linked (over 45 MB)" : "Uploaded";
}

/** Decimal sizes as in the design: 1.2 MB, 96 MB, 180 MB. */
export function formatBytes(bytes: number): string {
  if (bytes < 1000) {
    return `${bytes} B`;
  }
  const units = ["kB", "MB", "GB", "TB"];
  let value = bytes;
  let unit = "B";
  for (const next of units) {
    if (value < 1000) {
      break;
    }
    value /= 1000;
    unit = next;
  }
  const rounded = value < 10 ? Math.round(value * 10) / 10 : Math.round(value);
  return `${rounded} ${unit}`;
}

/** "9f2c…a41e" */
export function shortSha(sha256: string): string {
  return sha256.length <= 8 ? sha256 : `${sha256.slice(0, 4)}…${sha256.slice(-4)}`;
}

/** Every Chapter market is on Eastern Time; times are shown there with the zone named. */
const TIME_ZONE = "America/New_York";

const DATE_FORMAT = new Intl.DateTimeFormat("en-US", {
  timeZone: TIME_ZONE,
  year: "numeric",
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

function parse(iso: string): Date | undefined {
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

/** "Oct 17, 2026" */
export function formatDate(iso: string): string {
  const date = parse(iso);
  return date === undefined ? iso : DATE_FORMAT.format(date);
}

/** "Oct 17, 2026, 11:20 AM EDT" */
export function formatDateTime(iso: string): string {
  const date = parse(iso);
  return date === undefined ? iso : DATE_TIME_FORMAT.format(date);
}

/** Label of the capture a file belongs to, from the capture record. */
export function captureLabel(
  record: CaptureRecord | undefined,
  captureId: string | undefined,
  areaKey: string | undefined,
): string | undefined {
  if (captureId === undefined) {
    return undefined;
  }
  const capture = record?.captures.find((item) => item.captureId === captureId);
  return capture?.label ?? areaKey;
}

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
  const label = captureLabel(record, captureId, areaKey);
  return label === undefined ? name : `${label} / ${name}`;
}

/** Display name of a package path, using the package file entry when there is one. */
export function pathDisplayName(
  path: string,
  files: readonly PackageFile[],
  record: CaptureRecord | undefined,
): string {
  const file = files.find((item) => item.path === path);
  return fileDisplayName(path, record, file?.captureId, file?.areaKey);
}

/** "whole floor × 2" or "whole floor, exterior" */
export function modeSummary(record: CaptureRecord): string {
  const counts = new Map<CaptureMode, number>();
  for (const capture of record.captures) {
    counts.set(capture.mode, (counts.get(capture.mode) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([mode, count]) => (count > 1 ? `${MODE_LABEL[mode]} × ${count}` : MODE_LABEL[mode]))
    .join(", ");
}

/** "2 floors", "1 floor", or "3 areas" when not every capture is a whole floor. */
export function areaCount(record: CaptureRecord): string {
  const count = record.captures.length;
  const allFloors = record.captures.every((capture) => capture.mode === "floor");
  const noun = allFloors ? "floor" : "area";
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}

export function plural(count: number, singular: string, pluralForm = `${singular}s`): string {
  return `${count} ${count === 1 ? singular : pluralForm}`;
}
