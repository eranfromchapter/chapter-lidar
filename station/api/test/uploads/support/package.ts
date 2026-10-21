// Test packages built from the generated fixtures (fixtures/generated/<name>; box-room unless
// another fixture is named, for example legacy-1.0.0 with the retired phone report).
//
// Every call gives a fresh package: new packageId and visitId (visit + revision is unique in the
// registry), with the visitId rewritten in paths and file contents and every SHA-256 and size
// recomputed, so the manifest stays consistent with the bytes. A file's bytes can be replaced
// (fileOverrides, by fixture path) before the fingerprints are computed.

import { createHash, randomUUID } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { FileEntry, PackageManifest } from "@chapter/capture-contract";
import type { UploadSessionRequest } from "../../../src/routes/uploads/schemas.js";

const GENERATED = fileURLToPath(new URL("../../../../../fixtures/generated/", import.meta.url));
export const FIXTURE_ROOT = join(GENERATED, "box-room", "package");
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
  readonly dealId?: string;
  /** Fixture folder under fixtures/generated (default box-room). */
  readonly fixture?: string;
  /** Replacement bytes by fixture path (the path before the visitId is rewritten). */
  readonly fileOverrides?: ReadonlyMap<string, Buffer>;
  /** Manifest schemaVersion to write instead of the fixture's. */
  readonly schemaVersion?: string;
}

/** Root, visitId and manifest path of a generated fixture package. */
function fixturePackage(name: string): { root: string; visitId: string; manifest: string } {
  const root = join(GENERATED, name, "package");
  const visits = readdirSync(join(root, "Source Register"));
  const visitId = visits[0];
  if (visits.length !== 1 || visitId === undefined) {
    throw new Error(`fixture ${name} must hold exactly one visit`);
  }
  return { root, visitId, manifest: join(root, "Source Register", visitId, "manifest.json") };
}

export function makePackage(options: MakePackageOptions = {}): TestPackage {
  const fixture = fixturePackage(options.fixture ?? "box-room");
  const fixtureVisitId = fixture.visitId;
  const original = JSON.parse(readFileSync(fixture.manifest, "utf8")) as PackageManifest;
  const packageId = randomUUID();
  const visitId = options.visitId ?? randomUUID();
  const revision = options.revision ?? 1;

  const files = new Map<string, Buffer>();
  const entries: FileEntry[] = original.files.map((entry) => {
    const path = entry.path.split(fixtureVisitId).join(visitId);
    const data =
      options.fileOverrides?.get(entry.path) ??
      rewrite(readFileSync(join(fixture.root, entry.path)), fixtureVisitId, visitId);
    files.set(path, data);
    return {
      ...entry,
      path,
      sha256: sha256(data),
      bytes: data.length,
      derivedFrom: entry.derivedFrom.map((from) => from.split(fixtureVisitId).join(visitId)),
    };
  });

  const manifest = {
    schemaVersion: options.schemaVersion ?? original.schemaVersion,
    layoutVersion: original.layoutVersion,
    packageId,
    visitId,
    revision,
    ...(options.supersedesPackageId === undefined
      ? {}
      : { supersedesPackageId: options.supersedesPackageId }),
    sealedAt: original.sealedAt,
    files: entries as PackageManifest["files"],
  } as PackageManifest;
  const session: UploadSessionRequest = {
    packageId,
    visitId,
    dealId: options.dealId ?? FIXTURE_DEAL_ID,
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

/**
 * The next revision of a package: same visit and files except the given changes (bytes by
 * path of the base package; null removes a file) and added files (path -> bytes, copying the
 * declaration of the base file with the same role, capture and area as `like`).
 */
export function nextRevision(
  base: TestPackage,
  changes: {
    readonly replace?: ReadonlyMap<string, Buffer>;
    readonly add?: readonly { path: string; like: string; data: Buffer }[];
  } = {},
): TestPackage {
  const packageId = randomUUID();
  const revision = base.manifest.revision + 1;
  const files = new Map<string, Buffer>();
  const entries: FileEntry[] = [];
  for (const entry of base.manifest.files) {
    const data = changes.replace?.get(entry.path) ?? base.files.get(entry.path);
    if (data === undefined) {
      throw new Error(`no bytes for ${entry.path}`);
    }
    files.set(entry.path, data);
    entries.push({ ...entry, sha256: sha256(data), bytes: data.length });
  }
  for (const added of changes.add ?? []) {
    const like = base.manifest.files.find((entry) => entry.path === added.like);
    if (like === undefined) {
      throw new Error(`no base file ${added.like}`);
    }
    files.set(added.path, added.data);
    entries.push({
      ...like,
      path: added.path,
      sha256: sha256(added.data),
      bytes: added.data.length,
    } as FileEntry);
  }
  const manifest = {
    ...base.manifest,
    packageId,
    revision,
    supersedesPackageId: base.packageId,
    files: entries,
  } as PackageManifest;
  const session: UploadSessionRequest = {
    ...base.session,
    packageId,
    revision,
    supersedesPackageId: base.packageId,
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
    visitId: base.visitId,
    manifest,
    manifestBytes: Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8"),
    session,
    files,
  };
}
