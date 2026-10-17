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
