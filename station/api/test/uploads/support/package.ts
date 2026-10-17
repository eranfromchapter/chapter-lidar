// Test packages built from the generated box-room fixture (fixtures/generated/box-room).
//
// Every call gives a fresh package: new packageId and visitId (visit + revision is unique in the
// registry), with the visitId rewritten in paths and file contents and every SHA-256 and size
// recomputed, so the manifest stays consistent with the bytes.

import { createHash, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { FileEntry, PackageManifest } from "@chapter/capture-contract";
import type { UploadSessionRequest } from "../../../src/routes/uploads/schemas.js";

export const FIXTURE_ROOT = fileURLToPath(
  new URL("../../../../../fixtures/generated/box-room/package/", import.meta.url),
);
const FIXTURE_VISIT_ID = "c1b6d1fb-17af-4f4a-877c-2565ef9bdb86";
const FIXTURE_MANIFEST = join(FIXTURE_ROOT, "Source Register", FIXTURE_VISIT_ID, "manifest.json");
export const FIXTURE_DEAL_ID = "fixture-deal-0001";

export interface TestPackage {
  readonly packageId: string;
  readonly visitId: string;
  readonly manifest: PackageManifest;
  /** Manifest bytes as the phone would send them. */
  readonly manifestBytes: Buffer;
  readonly session: UploadSessionRequest;
  /** File bytes by manifest path. */
  readonly files: ReadonlyMap<string, Buffer>;
}

export function sha256(data: Buffer): string {
  return createHash("sha256").update(data).digest("hex");
}

function rewrite(data: Buffer, from: string, to: string): Buffer {
  const text = data.toString("latin1");
  return text.includes(from) ? Buffer.from(text.split(from).join(to), "latin1") : data;
}

export interface MakePackageOptions {
  readonly revision?: number;
  readonly supersedesPackageId?: string;
  readonly visitId?: string;
}

export function makePackage(options: MakePackageOptions = {}): TestPackage {
  const original = JSON.parse(readFileSync(FIXTURE_MANIFEST, "utf8")) as PackageManifest;
  const packageId = randomUUID();
  const visitId = options.visitId ?? randomUUID();
  const revision = options.revision ?? 1;

  const files = new Map<string, Buffer>();
  const entries: FileEntry[] = original.files.map((entry) => {
    const path = entry.path.split(FIXTURE_VISIT_ID).join(visitId);
    const data = rewrite(readFileSync(join(FIXTURE_ROOT, entry.path)), FIXTURE_VISIT_ID, visitId);
    files.set(path, data);
    return {
      ...entry,
      path,
      sha256: sha256(data),
      bytes: data.length,
      derivedFrom: entry.derivedFrom.map((from) => from.split(FIXTURE_VISIT_ID).join(visitId)),
    };
  });

  const manifest: PackageManifest = {
    schemaVersion: original.schemaVersion,
    layoutVersion: original.layoutVersion,
    packageId,
    visitId,
    revision,
    ...(options.supersedesPackageId === undefined
      ? {}
      : { supersedesPackageId: options.supersedesPackageId }),
    sealedAt: original.sealedAt,
    files: entries as PackageManifest["files"],
  };
  const session: UploadSessionRequest = {
    packageId,
    visitId,
    dealId: FIXTURE_DEAL_ID,
    revision,
    ...(options.supersedesPackageId === undefined
      ? {}
      : { supersedesPackageId: options.supersedesPackageId }),
    files: entries.map((entry) => ({
      path: entry.path,
      role: entry.role,
      ...(entry.captureId === undefined ? {} : { captureId: entry.captureId }),
      ...(entry.areaKey === undefined ? {} : { areaKey: entry.areaKey }),
      sha256: entry.sha256,
      bytes: entry.bytes,
    })),
  };
  return {
    packageId,
    visitId,
    manifest,
    manifestBytes: Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8"),
    session,
    files,
  };
}
