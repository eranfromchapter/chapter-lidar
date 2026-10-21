// Cross-field rules of the upload routes (422 unprocessable_content), kept pure for unit tests.

import { isVisitRole, type PackageManifest } from "@chapter/capture-contract";
import type { ProblemFieldError } from "../../core/problem.js";
import { manifestPath } from "../../storage/originals.js";
import type { UploadFileDeclaration, UploadSessionRequest } from "./schemas.js";

/**
 * Longest accepted file path. A blob name is at most 1024 characters (Azure, and the
 * package_files.blob_name check); the longest prefix is `<packageId>.retry-<n>/`.
 */
export const MAX_FILE_PATH_LENGTH = 960;
/** Azure allows at most 254 path segments in a blob name, one of which is the package prefix. */
export const MAX_FILE_PATH_SEGMENTS = 250;

/** Rules of an upload session request the JSON schema cannot express. */
export function sessionRequestErrors(body: UploadSessionRequest): ProblemFieldError[] {
  const errors: ProblemFieldError[] = [];

  if (body.revision === 1 && body.supersedesPackageId !== undefined) {
    errors.push({ pointer: "/supersedesPackageId", message: "must be omitted when revision is 1" });
  }
  if (body.revision > 1 && body.supersedesPackageId === undefined) {
    errors.push({
      pointer: "/supersedesPackageId",
      message: "is required when revision is greater than 1",
    });
  }
  if (body.supersedesPackageId !== undefined && body.supersedesPackageId === body.packageId) {
    errors.push({ pointer: "/supersedesPackageId", message: "must differ from packageId" });
  }

  const reserved = manifestPath(body.visitId);
  const seen = new Map<string, number>();
  body.files.forEach((file, index) => {
    const at = `/files/${index}`;
    const first = seen.get(file.path);
    if (first !== undefined) {
      errors.push({ pointer: `${at}/path`, message: `duplicates /files/${first}/path` });
    } else {
      seen.set(file.path, index);
    }
    if (file.path.length > MAX_FILE_PATH_LENGTH) {
      errors.push({
        pointer: `${at}/path`,
        message: `must be at most ${MAX_FILE_PATH_LENGTH} characters (blob name limit)`,
      });
    }
    if (file.path.split("/").length > MAX_FILE_PATH_SEGMENTS) {
      errors.push({
        pointer: `${at}/path`,
        message: `must have at most ${MAX_FILE_PATH_SEGMENTS} segments (blob name limit)`,
      });
    }
    if (file.path === reserved) {
      errors.push({
        pointer: `${at}/path`,
        message: "is the manifest path; the manifest is sent at sealing, not uploaded",
      });
    }
    if (isVisitRole(file.role)) {
      if (file.captureId !== undefined) {
        errors.push({
          pointer: `${at}/captureId`,
          message: `must be omitted for role ${file.role}`,
        });
      }
      if (file.areaKey !== undefined) {
        errors.push({ pointer: `${at}/areaKey`, message: `must be omitted for role ${file.role}` });
      }
    } else {
      if (file.captureId === undefined) {
        errors.push({ pointer: `${at}/captureId`, message: `is required for role ${file.role}` });
      }
      if (file.areaKey === undefined) {
        errors.push({ pointer: `${at}/areaKey`, message: `is required for role ${file.role}` });
      }
    }
  });
  return errors;
}

/** The superseded package as the station holds it, for the carry-over rule. */
export interface SupersededIdentity {
  readonly visitId: string;
  readonly dealId: string;
  readonly revision: number;
  /** False while it is still uploading. */
  readonly sealed: boolean;
}

/**
 * Why the package named by supersedesPackageId cannot be the previous revision of this
 * session (all at /supersedesPackageId): another visit or deal, not revision - 1, or not sealed.
 */
export function supersedesMismatchErrors(
  body: UploadSessionRequest,
  superseded: SupersededIdentity,
): ProblemFieldError[] {
  const pointer = "/supersedesPackageId";
  const errors: ProblemFieldError[] = [];
  if (superseded.visitId !== body.visitId) {
    errors.push({ pointer, message: "names a package of another visit" });
  }
  if (superseded.dealId !== body.dealId) {
    errors.push({ pointer, message: "names a package of another deal" });
  }
  if (superseded.revision !== body.revision - 1) {
    errors.push({
      pointer,
      message: `names revision ${superseded.revision}, not revision ${body.revision - 1}`,
    });
  }
  if (!superseded.sealed) {
    errors.push({ pointer, message: "names a package that is still uploading" });
  }
  return errors;
}

/** A verified file of the superseded package, as the registry holds it. */
export interface VerifiedFileRef {
  readonly role: string;
  readonly capture_id: string | null;
  readonly area_key: string | null;
  readonly sha256: string;
  readonly bytes: number;
}

/**
 * True when a declared file is the same file as a verified file of the superseded package at
 * the same path: same role, capture, area, SHA-256 and size (carry-over).
 */
export function carryOverMatch(
  declared: UploadFileDeclaration,
  verified: VerifiedFileRef,
): boolean {
  return (
    declared.role === verified.role &&
    (declared.captureId ?? null) === verified.capture_id &&
    (declared.areaKey ?? null) === verified.area_key &&
    declared.sha256 === verified.sha256 &&
    declared.bytes === verified.bytes
  );
}

/** The package's session, as registered by POST /packages. */
export interface SessionIdentity {
  readonly packageId: string;
  readonly visitId: string;
  readonly revision: number;
  readonly supersedesPackageId?: string;
}

/**
 * Differences between a (schema-valid) manifest and the upload session: identity fields and the
 * file list (same paths, each with the same role, capture, area, SHA-256 and size).
 */
export function manifestMismatchErrors(
  manifest: PackageManifest,
  session: SessionIdentity,
  declared: readonly UploadFileDeclaration[],
): ProblemFieldError[] {
  const errors: ProblemFieldError[] = [];
  if (manifest.packageId !== session.packageId) {
    errors.push({ pointer: "/packageId", message: "does not match the package in the URL" });
  }
  if (manifest.visitId !== session.visitId) {
    errors.push({ pointer: "/visitId", message: "does not match the upload session" });
  }
  if (manifest.revision !== session.revision) {
    errors.push({ pointer: "/revision", message: "does not match the upload session" });
  }
  if (manifest.supersedesPackageId !== session.supersedesPackageId) {
    errors.push({ pointer: "/supersedesPackageId", message: "does not match the upload session" });
  }

  const byPath = new Map(declared.map((file) => [file.path, file]));
  const listed = new Set<string>();
  manifest.files.forEach((entry, index) => {
    const at = `/files/${index}`;
    if (listed.has(entry.path)) {
      errors.push({ pointer: `${at}/path`, message: "is listed more than once" });
      return;
    }
    listed.add(entry.path);
    const file = byPath.get(entry.path);
    if (file === undefined) {
      errors.push({ pointer: `${at}/path`, message: "was not declared in the upload session" });
      return;
    }
    const fields = ["role", "captureId", "areaKey", "sha256", "bytes"] as const;
    for (const field of fields) {
      if (entry[field] !== file[field]) {
        errors.push({
          pointer: `${at}/${field}`,
          message: "does not match the upload session declaration",
        });
      }
    }
  });
  for (const file of declared) {
    if (!listed.has(file.path)) {
      errors.push({
        pointer: "/files",
        message: `declared file ${JSON.stringify(file.path)} is missing from the manifest`,
      });
    }
  }
  return errors;
}
