// Rows of the package page's Files card (web-review §6.4.6): order, display names, role labels
// and filter groups, photo groups, the virtual manifest and spatial report rows, HUB badges, and
// the floor / role / text filters. Built on the server; the client component only filters and
// expands. Rows carry app URLs only (download routes), never a signed link.

import type { Role } from "@chapter/capture-contract";
import {
  captureLabel,
  fileDisplayName,
  formatBytes,
  ROLE_FILTER_GROUP,
  ROLE_LABEL,
  shortSha,
} from "./format";
import type { HubFileState, PackageFile, StationPackage } from "./station-types";

export type BadgeTone = "neutral" | "accent" | "success" | "warning" | "danger" | "info";

/** The "In the HUB" badge of a row; null shows a muted "—" (not published). */
export interface HubBadge {
  readonly text: string;
  readonly tone: BadgeTone;
}

export interface FileRowView {
  /** Unique key: the path, "photos:{captureId}", "manifest" or "spatial-report". */
  readonly key: string;
  readonly kind: "file" | "photoGroup" | "manifest" | "report";
  readonly name: string;
  /** Full path, shown in the name's title. */
  readonly path?: string;
  /** "Role" column. */
  readonly role: string;
  /** Role filter group. */
  readonly group: string;
  /** Capture of the row; undefined for visit-wide rows (listed under "All floors" only). */
  readonly captureId?: string;
  readonly size: string;
  readonly sha: string;
  /** Full SHA-256, shown in the short one's title. */
  readonly shaFull?: string;
  readonly hub: HubBadge | null;
  /** Download route of this app; undefined when the file is not verified. */
  readonly download?: string;
  /** Number of package files the row stands for (a photo group counts every photo). */
  readonly files: number;
  /** The photos of a photo group. */
  readonly children?: readonly FileRowView[];
}

/** Rows shown before "Show all {n} files". */
export const COLLAPSED_ROWS = 8;

/** Display order of the roles; photo groups, the station report and the manifest are placed too. */
const ORDER: readonly (Role | "photos" | "report" | "manifest")[] = [
  "plan_dxf",
  "rooms_csv",
  "plan_pdf",
  "plan_png",
  "mesh_glb",
  "point_cloud_las",
  "photos",
  "report",
  "plan_svg",
  "mesh_obj",
  "mesh_mtl",
  "texture",
  "capture_model",
  "raw_roomplan_json",
  "raw_depth",
  "field_controls",
  "capture_record",
  "manifest",
  "spatial_report_pdf",
];

/** Role filter groups in the order the Role select lists them. */
export const FILTER_GROUP_ORDER: readonly string[] = [
  "Plan DXF",
  "Rooms CSV",
  "Plan sheet PDF",
  "Plan PNG",
  "Plan SVG",
  "Mesh GLB",
  "OBJ + MTL",
  "Point cloud LAS",
  "Raw RoomPlan",
  "Depth",
  "Capture model",
  "Site photo",
  "Field controls",
  "Capture record",
  "Manifest",
  "Spatial report",
];

/** The HUB badge of a file state (the station's publication record, not a rule of the web). */
export function hubBadge(state: HubFileState | undefined): HubBadge | null {
  if (state === undefined) {
    return null;
  }
  if (state.state === "uploaded") {
    return { text: "Uploaded", tone: "neutral" };
  }
  return state.reason === "too_large"
    ? { text: "Linked · over 45 MB", tone: "info" }
    : { text: "Linked", tone: "info" };
}

function sameBadge(a: HubBadge | null, b: HubBadge | null): boolean {
  return a?.text === b?.text && a?.tone === b?.tone;
}

/** Download route of a package file (or the manifest) in this app. */
export function fileDownloadRoute(packageId: string, path: string): string {
  return `/packages/${encodeURIComponent(packageId)}/files/download?path=${encodeURIComponent(path)}`;
}

/** Download route of the station's spatial report in this app. */
export function reportDownloadRoute(packageId: string): string {
  return `/packages/${encodeURIComponent(packageId)}/report/download`;
}

/** Preview route of a plan PNG (streamed through this app). */
export function previewRoute(packageId: string, path: string): string {
  return `/packages/${encodeURIComponent(packageId)}/files/preview?path=${encodeURIComponent(path)}`;
}

function fileRow(pkg: StationPackage, file: PackageFile): FileRowView {
  return {
    key: file.path,
    kind: "file",
    name: fileDisplayName(file.path, pkg.captureRecord, file.captureId, file.areaKey),
    path: file.path,
    role: ROLE_LABEL[file.role],
    group: ROLE_FILTER_GROUP[file.role],
    ...(file.captureId === undefined ? {} : { captureId: file.captureId }),
    size: formatBytes(file.bytes),
    sha: shortSha(file.sha256),
    shaFull: file.sha256,
    hub: hubBadge(file.hub),
    ...(file.status === "verified"
      ? { download: fileDownloadRoute(pkg.packageId, file.path) }
      : {}),
    files: 1,
  };
}

/** Capture order of the package: capture record order once sealed, else the station's. */
function captureOrder(pkg: StationPackage): Map<string, number> {
  const ids =
    pkg.captureRecord?.captures.map((capture) => capture.captureId) ??
    pkg.captures.map((capture) => capture.captureId);
  return new Map(ids.map((id, index) => [id, index]));
}

function byCaptureThenPath(order: Map<string, number>) {
  const rank = (id: string | undefined) =>
    id === undefined ? -1 : (order.get(id) ?? Number.MAX_SAFE_INTEGER);
  return (a: PackageFile, b: PackageFile) =>
    rank(a.captureId) - rank(b.captureId) || (a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
}

/** Every row of the Files card in display order (photos grouped per capture). */
export function buildFileRows(pkg: StationPackage): FileRowView[] {
  const order = captureOrder(pkg);
  const sorted = [...pkg.files].sort(byCaptureThenPath(order));
  const multiCapture = (pkg.captureRecord?.captures.length ?? pkg.captures.length) > 1;
  const rows: FileRowView[] = [];
  for (const slot of ORDER) {
    if (slot === "photos") {
      const captures = [
        ...new Set(sorted.filter((file) => file.role === "photo").map((file) => file.captureId)),
      ];
      for (const captureId of captures) {
        const photos = sorted.filter(
          (file) => file.role === "photo" && file.captureId === captureId,
        );
        const children = photos.map((photo) => fileRow(pkg, photo));
        const first = children[0]?.hub ?? null;
        const mixed = children.some((child) => !sameBadge(child.hub, first));
        const label = captureLabel(pkg.captureRecord, captureId, photos[0]?.areaKey);
        rows.push({
          key: `photos:${captureId ?? "visit"}`,
          kind: "photoGroup",
          name: `${multiCapture && label !== undefined ? `${label} / ` : ""}Site Photos / ${photos.length} files`,
          role: ROLE_LABEL.photo,
          group: ROLE_FILTER_GROUP.photo,
          ...(captureId === undefined ? {} : { captureId }),
          size: formatBytes(photos.reduce((sum, photo) => sum + photo.bytes, 0)),
          sha: "per file",
          hub: mixed ? { text: "Mixed", tone: "neutral" } : first,
          files: photos.length,
          children,
        });
      }
    } else if (slot === "report") {
      const report = pkg.report;
      if (report?.status === "ready") {
        rows.push({
          key: "spatial-report",
          kind: "report",
          name: "spatial-report.pdf",
          role: "Spatial report · station",
          group: "Spatial report",
          size: report.bytes === undefined ? "—" : formatBytes(report.bytes),
          sha: report.sha256 === undefined ? "—" : shortSha(report.sha256),
          ...(report.sha256 === undefined ? {} : { shaFull: report.sha256 }),
          hub: hubBadge(report.hub),
          download: reportDownloadRoute(pkg.packageId),
          files: 1,
        });
      }
    } else if (slot === "manifest") {
      const manifest = pkg.manifestFile;
      if (manifest !== undefined) {
        rows.push({
          key: "manifest",
          kind: "manifest",
          name: "manifest.json",
          path: manifest.path,
          role: "Manifest",
          group: "Manifest",
          size: formatBytes(manifest.bytes),
          sha: shortSha(manifest.sha256),
          shaFull: manifest.sha256,
          hub: hubBadge(manifest.hub),
          download: fileDownloadRoute(pkg.packageId, manifest.path),
          files: 1,
        });
      }
    } else {
      for (const file of sorted.filter((item) => item.role === slot)) {
        rows.push(fileRow(pkg, file));
      }
    }
  }
  return rows;
}

/** Floor select options: "All floors", then each capture in capture-record order. */
export function floorOptions(pkg: StationPackage): { value: string; label: string }[] {
  const captures =
    pkg.captureRecord?.captures.map((capture) => ({
      value: capture.captureId,
      label: capture.label,
    })) ??
    pkg.captures.map((capture) => ({
      value: capture.captureId,
      label: captureLabel(undefined, capture.captureId, capture.areaKey) ?? capture.areaKey,
    }));
  return [{ value: "all", label: "All floors" }, ...captures];
}

/** Role select options: "All roles", then the groups present in the rows, in fixed order. */
export function roleOptions(rows: readonly FileRowView[]): { value: string; label: string }[] {
  const present = new Set(rows.map((row) => row.group));
  return [
    { value: "all", label: "All roles" },
    ...FILTER_GROUP_ORDER.filter((group) => present.has(group)).map((group) => ({
      value: group,
      label: group,
    })),
  ];
}

export interface FileFilters {
  /** "all" or a captureId. */
  readonly floor: string;
  /** "all" or a role filter group. */
  readonly role: string;
  readonly text: string;
}

export const NO_FILTERS: FileFilters = { floor: "all", role: "all", text: "" };

function matchesText(row: FileRowView, needle: string): boolean {
  return row.name.toLowerCase().includes(needle) || (row.path ?? "").toLowerCase().includes(needle);
}

/**
 * The rows that pass the filters. Visit-wide rows are listed under "All floors" only. A photo
 * group passes the text filter by its own name or by its photos; in the latter case it keeps
 * only the matching photos (`matchedChildren`).
 */
export function filterRows(
  rows: readonly FileRowView[],
  filters: FileFilters,
): { row: FileRowView; matchedChildren?: readonly FileRowView[] }[] {
  const needle = filters.text.trim().toLowerCase();
  const out: { row: FileRowView; matchedChildren?: readonly FileRowView[] }[] = [];
  for (const row of rows) {
    if (filters.floor !== "all" && row.captureId !== filters.floor) {
      continue;
    }
    if (filters.role !== "all" && row.group !== filters.role) {
      continue;
    }
    if (needle.length === 0 || matchesText(row, needle)) {
      out.push({ row });
      continue;
    }
    const children = row.children?.filter((child) => matchesText(child, needle)) ?? [];
    if (children.length > 0) {
      out.push({ row, matchedChildren: children });
    }
  }
  return out;
}

/** Package files a filtered list stands for ("Show all {n} files"). */
export function fileCount(
  filtered: readonly { row: FileRowView; matchedChildren?: readonly FileRowView[] }[],
): number {
  return filtered.reduce((sum, item) => sum + (item.matchedChildren?.length ?? item.row.files), 0);
}

/** The top-level row holding `path` (a file row, or the photo group of that photo). */
export function rowHolding(rows: readonly FileRowView[], path: string): FileRowView | undefined {
  return rows.find(
    (row) => row.path === path || row.children?.some((child) => child.path === path) === true,
  );
}
