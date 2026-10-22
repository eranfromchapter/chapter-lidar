// What a publication sends to the HUB and what it only links, and where each file goes.
//
// Folder rules (project Files tab):
// - visit-wide files (the station's spatial report PDF and manifest.json):
//   Capture/<visitId>/r<revision>
// - per-capture files: Capture/<areaKey>/<captureId>/r<revision>
//
// Uploaded: the spatial report PDF (spatial-report-<verdictId>.pdf, made by the station after
// the checks), manifest.json, and the plan DXF, rooms CSV, plan sheet PDF and plan PNG of every
// capture. A file over 45 MiB is never uploaded (the HUB caps uploads at 50 MB). Every package
// file that is not uploaded (too large, or a role the HUB does not get: meshes, LAS, photos, raw
// data, the retired phone report spatial_report_pdf of packages sealed before v2, ...) is listed
// in the report with a station link that requires Entra sign-in:
// ${REVIEW_BASE_URL}/packages/<packageId>?file=<path>.

import type { PhotoDirection, PhotoSubject, Role } from "@chapter/capture-contract";
import { HubError } from "./errors.js";

/** Largest file the station uploads to the HUB: 45 MiB. */
export const MAX_HUB_UPLOAD_BYTES = 45 * 1024 * 1024;

/**
 * Package file roles uploaded to the HUB (when not over the size limit). The phone's retired
 * spatial_report_pdf is never uploaded next to the station's spatial report: it is linked.
 */
export const HUB_UPLOAD_ROLES: readonly Role[] = Object.freeze([
  "plan_dxf",
  "rooms_csv",
  "plan_pdf",
  "plan_png",
]);

export const REPORT_CONTENT_TYPE = "application/pdf";
export const MANIFEST_CONTENT_TYPE = "application/json";

/** A verified package file (package_files row with the manifest's mime type). */
export interface PackageFileRecord {
  readonly path: string;
  readonly role: Role;
  readonly captureId?: string;
  readonly areaKey?: string;
  readonly sha256: string;
  readonly bytes: number;
  readonly mime?: string;
  /** Manifest photo labels (role photo): where the spatial report shows the photo. */
  readonly photo?: {
    readonly room: string;
    readonly direction: PhotoDirection;
    readonly subject: PhotoSubject;
    readonly takenAt: string;
  };
}

/** The package revision being published. */
export interface PublishPackage {
  readonly packageId: string;
  /** HUB sales dealId of the project (never a project record id). */
  readonly dealId: string;
  readonly visitId: string;
  readonly revision: number;
  /** Package path of the sealed manifest: Source Register/<visitId>/manifest.json. */
  readonly manifestPath: string;
  readonly manifestSha256: string;
  readonly manifestBytes: number;
  readonly files: readonly PackageFileRecord[];
  /** Manifest sealedAt (printed on the report). */
  readonly sealedAt?: string;
  /** Number of manifest entries (default: files.length). */
  readonly manifestFileCount?: number;
}

export type PlannedSource = "report" | "manifest" | "package";

export interface PlannedUpload {
  readonly kind: "upload";
  readonly source: PlannedSource;
  readonly folder: string;
  readonly name: string;
  readonly contentType: string;
  /** Package path (manifest and package files). */
  readonly path?: string;
  readonly role?: Role;
  readonly sha256: string;
  readonly bytes: number;
}

export interface PlannedLink {
  readonly kind: "link";
  readonly path: string;
  readonly role: Role | "manifest";
  readonly sha256: string;
  readonly bytes: number;
  /** Station link (Entra sign-in required). */
  readonly url: string;
  /** too_large: an upload role over 45 MiB; not_published: a role the HUB does not get. */
  readonly reason: "too_large" | "not_published";
}

export type PlannedFile = PlannedUpload | PlannedLink;

export interface PublicationPlan {
  /** Where the spatial report goes (its bytes are rendered from this plan). */
  readonly report: { readonly folder: string; readonly name: string };
  /** Every other file: manifest and package files, in package path order. */
  readonly files: readonly PlannedFile[];
}

export interface PlanOptions {
  /** Web review screen base URL (REVIEW_BASE_URL). */
  readonly reviewBaseUrl: string;
  readonly maxUploadBytes?: number;
}

/** Folder of visit-wide files. */
export function visitFolder(visitId: string, revision: number): string {
  return `Capture/${visitId}/r${revision}`;
}

/** Folder of one capture's files. */
export function captureFolder(areaKey: string, captureId: string, revision: number): string {
  return `Capture/${areaKey}/${captureId}/r${revision}`;
}

/** Name of the spatial report: one per verdict, so a new verdict never replaces an old file. */
export function reportName(verdictId: string): string {
  return `spatial-report-${verdictId}.pdf`;
}

/** Authenticated station link of one package file (the review screen, behind Entra sign-in). */
export function stationLink(reviewBaseUrl: string, packageId: string, path: string): string {
  const base = reviewBaseUrl.replace(/\/+$/, "");
  return `${base}/packages/${packageId}?file=${encodeURIComponent(path)}`;
}

function baseName(path: string): string {
  const index = path.lastIndexOf("/");
  return index === -1 ? path : path.slice(index + 1);
}

/** Builds the publication plan of a package and verdict. Throws HubError (conflict) on a name clash. */
export function planPublication(
  pkg: PublishPackage,
  verdictId: string,
  options: PlanOptions,
): PublicationPlan {
  const max = options.maxUploadBytes ?? MAX_HUB_UPLOAD_BYTES;
  const visit = visitFolder(pkg.visitId, pkg.revision);
  const report = { folder: visit, name: reportName(verdictId) };
  const files: PlannedFile[] = [];

  if (pkg.manifestBytes > max) {
    files.push({
      kind: "link",
      path: pkg.manifestPath,
      role: "manifest",
      sha256: pkg.manifestSha256,
      bytes: pkg.manifestBytes,
      url: stationLink(options.reviewBaseUrl, pkg.packageId, pkg.manifestPath),
      reason: "too_large",
    });
  } else {
    files.push({
      kind: "upload",
      source: "manifest",
      folder: visit,
      name: baseName(pkg.manifestPath),
      contentType: MANIFEST_CONTENT_TYPE,
      path: pkg.manifestPath,
      sha256: pkg.manifestSha256,
      bytes: pkg.manifestBytes,
    });
  }

  const sorted = [...pkg.files].sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  for (const file of sorted) {
    const uploadRole = HUB_UPLOAD_ROLES.includes(file.role);
    if (uploadRole && file.bytes <= max) {
      if (file.areaKey === undefined || file.captureId === undefined) {
        throw new HubError(
          "conflict",
          `File ${file.path} has no capture; cannot choose its folder`,
        );
      }
      files.push({
        kind: "upload",
        source: "package",
        folder: captureFolder(file.areaKey, file.captureId, pkg.revision),
        name: baseName(file.path),
        contentType: file.mime ?? "application/octet-stream",
        path: file.path,
        role: file.role,
        sha256: file.sha256,
        bytes: file.bytes,
      });
    } else {
      files.push({
        kind: "link",
        path: file.path,
        role: file.role,
        sha256: file.sha256,
        bytes: file.bytes,
        url: stationLink(options.reviewBaseUrl, pkg.packageId, file.path),
        reason: uploadRole ? "too_large" : "not_published",
      });
    }
  }

  // Two files with one name in one folder would be ambiguous in the HUB: refuse.
  const seen = new Set<string>([`${report.folder}\n${report.name}`]);
  for (const file of files) {
    if (file.kind !== "upload") {
      continue;
    }
    const key = `${file.folder}\n${file.name}`;
    if (seen.has(key)) {
      throw new HubError("conflict", `Two files would be named ${file.name} in ${file.folder}`);
    }
    seen.add(key);
  }
  return { report, files };
}
