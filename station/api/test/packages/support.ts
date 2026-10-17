// Shared setup for the package and decision tests: a migrated throwaway Postgres (core's
// helper: a database on DATABASE_URL's server, else a disposable Docker container), the app
// with a loopback Entra stand-in, and seed rows written directly with SQL from the contract
// examples (one site visit, two captures), plus a file verified on a retry blob for the
// download-link tests.

import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import type { FastifyInstance } from "fastify";
import { withThrowawayDatabase } from "../../scripts/lib/throwaway-postgres.js";
import { buildServer } from "../../src/core/app.js";
import type { Role } from "../../src/core/auth.js";
import { createDatabase, urlConnection, type Database } from "../../src/core/db.js";
import { runMigrations } from "../../src/core/migrate.js";
import type { StationServices } from "../../src/core/services.js";
import { logCollector, startTestIssuer, testConfig, type TestIssuer } from "../core/helpers.js";

const EXAMPLES = new URL("../../../../contract/examples/", import.meta.url);

function example<T = Record<string, unknown>>(path: string): T {
  return JSON.parse(readFileSync(fileURLToPath(new URL(path, EXAMPLES)), "utf8")) as T;
}

export interface ManifestFile {
  path: string;
  role: string;
  captureId?: string;
  areaKey?: string;
  sha256: string;
  bytes: number;
}

export const MANIFEST = example<{
  packageId: string;
  visitId: string;
  revision: number;
  sealedAt: string;
  files: ManifestFile[];
}>("manifest/valid/two-captures.json");
export const CAPTURE_RECORD = example("capture-record/valid/two-captures.json");
export const VERDICT = example<{ verdictId: string; outcome: string; evaluatedAt: string }>(
  "verdict/valid/limited.json",
);

export const DEAL_ID = "HUB-1001";
export const OTHER_DEAL_ID = "HUB-2002";
export const PACKAGE_ID = MANIFEST.packageId;
export const VISIT_ID = MANIFEST.visitId;
export const FLOOR_1 = { captureId: "3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35", areaKey: "floor-1" };
export const FLOOR_2 = { captureId: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60", areaKey: "floor-2" };

/** Revision 2 of the same visit, still uploading. */
export const REVISION_2_ID = "0d9e8f7a-6b5c-4d3e-8f2a-1b0c9d8e7f6a";
/** Another visit of the same deal, sealed and waiting for checks. */
export const QUEUED_ID = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d";
export const QUEUED_VISIT_ID = "2b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e";
/** A package of another deal. */
export const OTHER_DEAL_PACKAGE_ID = "3c4d5e6f-7a8b-4c9d-8e0f-2a3b4c5d6e7f";
/** Status verdict_ready but its verdict document breaks the contract. */
export const BROKEN_VERDICT_ID = "4d5e6f7a-8b9c-4d0e-9f1a-3b4c5d6e7f8a";
/** A package id that is not in the registry. */
export const UNKNOWN_ID = "5e6f7a8b-9c0d-4e1f-8a2b-4c5d6e7f8a9b";
/** A package (seedRetriedFile) whose file was verified on its second upload attempt. */
export const RETRIED_ID = "9d0e1f2a-3b4c-4d5e-8f6a-7b8c9d0e1f2a";

export const FIELD_CONTROLS_PATH = MANIFEST.files.find((f) => f.role === "field_controls")!.path;
export const CAPTURE_MODEL_PATH = MANIFEST.files.find(
  (f) => f.role === "capture_model" && f.areaKey === "floor-1",
)!.path;
export const PLAN_DXF_PATH = MANIFEST.files.find((f) => f.role === "plan_dxf")!.path;

export const BIM_OID = "6f7a8b9c-0d1e-4f2a-8b3c-5d6e7f8a9b0c";
export const BIM_NAME = "Bea Modeler";

export interface TestStation {
  readonly app: FastifyInstance;
  readonly db: Database;
  readonly issuer: TestIssuer;
  readonly logs: string[];
  /** Bearer header for a user with these roles. */
  auth(roles: readonly Role[], claims?: Record<string, unknown>): Promise<Record<string, string>>;
  close(): Promise<void>;
}

/** Starts a migrated throwaway database and the app on it. Call close() in after(). */
export async function startStation(
  options: {
    services?: Partial<StationServices>;
    /** Test-only routes, registered before the app is ready. */
    routes?: (app: FastifyInstance) => void;
  } = {},
): Promise<TestStation> {
  let release: () => void = () => undefined;
  let ready: (url: string) => void = () => undefined;
  const urlReady = new Promise<string>((resolve) => {
    ready = resolve;
  });
  const held = withThrowawayDatabase(async (throwaway) => {
    await runMigrations({ connection: urlConnection(throwaway.url) });
    ready(throwaway.url);
    await new Promise<void>((resolve) => {
      release = resolve;
    });
  });
  const url = await Promise.race([urlReady, held.then(() => Promise.reject(new Error("db gone")))]);

  const db = createDatabase({ connection: urlConnection(url), poolMax: 4 });
  const issuer = await startTestIssuer();
  const logs = logCollector();
  const app = await buildServer({
    config: testConfig({ ENTRA_JWKS_URL: issuer.jwksUrl, DATABASE_URL: url }),
    db,
    services: options.services ?? {},
    logStream: logs.stream,
  });
  options.routes?.(app);
  await app.ready();

  return {
    app,
    db,
    issuer,
    logs: logs.lines,
    async auth(roles, claims = {}) {
      const token = await issuer.mint({
        roles: [...roles],
        oid: BIM_OID,
        name: BIM_NAME,
        ...claims,
      });
      return { authorization: `Bearer ${token}` };
    },
    async close() {
      await app.close();
      await db.close();
      await issuer.close();
      release();
      await held;
    },
  };
}

function sha256Of(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

async function insertFile(
  db: Database,
  packageId: string,
  file: ManifestFile,
  state: "pending" | "verified" | "sha256_mismatch" | "bytes_mismatch" | "not_uploaded",
): Promise<void> {
  const checked = state !== "pending";
  const actualSha =
    state === "verified" || state === "bytes_mismatch"
      ? file.sha256
      : state === "sha256_mismatch"
        ? sha256Of(`other:${file.path}`)
        : null;
  const actualBytes =
    state === "verified" || state === "sha256_mismatch"
      ? file.bytes
      : state === "bytes_mismatch"
        ? file.bytes + 1
        : null;
  await db.query(
    `INSERT INTO package_files
       (package_id, path, role, capture_id, area_key, sha256, bytes, status, actual_sha256,
        actual_bytes, checked_at, verified_at, blob_name)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`,
    [
      packageId,
      file.path,
      file.role,
      file.captureId ?? null,
      file.areaKey ?? null,
      file.sha256,
      file.bytes,
      state,
      actualSha,
      actualBytes,
      checked ? "2026-10-17T15:10:30.250Z" : null,
      state === "verified" ? "2026-10-17T15:10:30.250Z" : null,
      state === "verified" ? `${packageId}/${file.path}` : null,
    ],
  );
}

interface PackageSeed {
  packageId: string;
  visitId: string;
  dealId: string;
  revision: number;
  supersedes?: string;
  status: string;
  createdAt: string;
  sealed?: { manifest: Record<string, unknown>; captureRecord?: Record<string, unknown> };
}

async function insertPackage(db: Database, seed: PackageSeed, files: ManifestFile[]) {
  const sessionRequest = {
    packageId: seed.packageId,
    visitId: seed.visitId,
    dealId: seed.dealId,
    revision: seed.revision,
    files,
  };
  const manifest = seed.sealed?.manifest ?? null;
  await db.query(
    `INSERT INTO packages
       (package_id, visit_id, deal_id, revision, supersedes_package_id, status, session_request,
        created_by_id, created_by_name, created_at, manifest, manifest_sha256, sealed_at,
        registered_at, capture_record)
     VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10, $11::jsonb, $12, $13, $14, $15::jsonb)`,
    [
      seed.packageId,
      seed.visitId,
      seed.dealId,
      seed.revision,
      seed.supersedes ?? null,
      seed.status,
      JSON.stringify(sessionRequest),
      "0c7f5e2a-3b4d-4e6f-8a9b-1c2d3e4f5a6b",
      "Dana Field",
      seed.createdAt,
      manifest === null ? null : JSON.stringify(manifest),
      manifest === null ? null : sha256Of(JSON.stringify(manifest)),
      manifest === null ? null : String(manifest.sealedAt),
      manifest === null ? null : "2026-10-17T15:11:02.900Z",
      seed.sealed?.captureRecord === undefined ? null : JSON.stringify(seed.sealed.captureRecord),
    ],
  );
}

function filesOf(manifest: { files: ManifestFile[] }): ManifestFile[] {
  return manifest.files.map((file) => ({
    path: file.path,
    role: file.role,
    ...(file.captureId === undefined ? {} : { captureId: file.captureId }),
    ...(file.areaKey === undefined ? {} : { areaKey: file.areaKey }),
    sha256: file.sha256,
    bytes: file.bytes,
  }));
}

export interface RetriedFile {
  readonly packageId: string;
  readonly path: string;
  /** Bytes of the verified upload (attempt 2). */
  readonly body: string;
  readonly sha256: string;
  readonly bytes: number;
  /** Where the verified upload is stored: `<packageId>.retry-2/<path>`. */
  readonly blobName: string;
  /** Attempt 1 (`<packageId>/<path>`), whose bytes did not match and stay there. */
  readonly rejectedBlobName: string;
  readonly rejectedBody: string;
}

/**
 * Seeds RETRIED_ID: an uploading package with one file whose first upload was rejected and
 * whose second upload (blob `<packageId>.retry-2/<path>`) is verified, as the upload routes
 * record it. Upload the blobs yourself (Azurite).
 */
export async function seedRetriedFile(db: Database): Promise<RetriedFile> {
  const base = MANIFEST.files.find((f) => f.role === "plan_dxf")!;
  const body = "0\nSECTION\n2\nENTITIES\n0\nENDSEC\n0\nEOF\n# attempt 2\n";
  const file: ManifestFile = { ...base, sha256: sha256Of(body), bytes: Buffer.byteLength(body) };
  await insertPackage(
    db,
    {
      packageId: RETRIED_ID,
      visitId: "0a1b2c3d-4e5f-4a6b-9c7d-8e9f0a1b2c3d",
      // Its own deal, so the listPackages expectations of the main seed do not change.
      dealId: "HUB-3003",
      revision: 1,
      status: "uploading",
      createdAt: "2026-10-17T18:00:00.000Z",
    },
    [file],
  );
  const blobName = `${RETRIED_ID}.retry-2/${file.path}`;
  await db.query(
    `INSERT INTO package_files
       (package_id, path, role, capture_id, area_key, sha256, bytes, status, actual_sha256,
        actual_bytes, checked_at, verified_at, blob_name)
     VALUES ($1, $2, $3, $4, $5, $6, $7, 'verified', $6, $7, $8, $8, $9)`,
    [
      RETRIED_ID,
      file.path,
      file.role,
      file.captureId ?? null,
      file.areaKey ?? null,
      file.sha256,
      file.bytes,
      "2026-10-17T18:05:00.000Z",
      blobName,
    ],
  );
  return {
    packageId: RETRIED_ID,
    path: file.path,
    body,
    sha256: file.sha256,
    bytes: file.bytes,
    blobName,
    rejectedBlobName: `${RETRIED_ID}/${file.path}`,
    rejectedBody: "rejected first attempt",
  };
}

/**
 * Seeds the registry:
 * - PACKAGE_ID: revision 1, sealed, every file verified, verdict ready (limited example).
 * - REVISION_2_ID: revision 2 of the same visit, uploading, files in every unverified state.
 * - QUEUED_ID: another visit of the deal, sealed, checks queued, no verdict.
 * - BROKEN_VERDICT_ID: verdict_ready with a verdict document that breaks the contract.
 * - OTHER_DEAL_PACKAGE_ID: a package of another deal.
 */
export async function seedRegistry(db: Database): Promise<void> {
  const files = filesOf(MANIFEST);
  await insertPackage(
    db,
    {
      packageId: PACKAGE_ID,
      visitId: VISIT_ID,
      dealId: DEAL_ID,
      revision: 1,
      status: "verdict_ready",
      createdAt: "2026-10-17T15:06:10.123Z",
      sealed: { manifest: MANIFEST, captureRecord: CAPTURE_RECORD },
    },
    files,
  );
  for (const file of files) {
    await insertFile(db, PACKAGE_ID, file, "verified");
  }
  await db.query(
    `INSERT INTO verdicts (verdict_id, package_id, outcome, evaluated_at, document)
     VALUES ($1, $2, $3, $4, $5::jsonb)`,
    [VERDICT.verdictId, PACKAGE_ID, VERDICT.outcome, VERDICT.evaluatedAt, JSON.stringify(VERDICT)],
  );

  const states = [
    "pending",
    "sha256_mismatch",
    "bytes_mismatch",
    "not_uploaded",
    "verified",
  ] as const;
  const rev2Files = files.slice(0, states.length);
  await insertPackage(
    db,
    {
      packageId: REVISION_2_ID,
      visitId: VISIT_ID,
      dealId: DEAL_ID,
      revision: 2,
      supersedes: PACKAGE_ID,
      status: "uploading",
      createdAt: "2026-10-17T16:00:00.000Z",
    },
    rev2Files,
  );
  for (const [index, file] of rev2Files.entries()) {
    await insertFile(db, REVISION_2_ID, file, states[index]!);
  }

  const queuedManifest = {
    ...MANIFEST,
    packageId: QUEUED_ID,
    visitId: QUEUED_VISIT_ID,
    files: MANIFEST.files.slice(0, 1),
  };
  await insertPackage(
    db,
    {
      packageId: QUEUED_ID,
      visitId: QUEUED_VISIT_ID,
      dealId: DEAL_ID,
      revision: 1,
      status: "checks_queued",
      createdAt: "2026-10-16T09:00:00.000Z",
      sealed: { manifest: queuedManifest },
    },
    filesOf(queuedManifest),
  );
  await insertFile(db, QUEUED_ID, filesOf(queuedManifest)[0]!, "verified");

  const brokenManifest = {
    ...MANIFEST,
    packageId: BROKEN_VERDICT_ID,
    visitId: "6a7b8c9d-0e1f-4a2b-8c3d-4e5f6a7b8c9d",
    files: MANIFEST.files.slice(0, 1),
  };
  await insertPackage(
    db,
    {
      packageId: BROKEN_VERDICT_ID,
      visitId: brokenManifest.visitId,
      dealId: OTHER_DEAL_ID,
      revision: 1,
      status: "verdict_ready",
      createdAt: "2026-10-15T09:00:00.000Z",
      sealed: { manifest: brokenManifest },
    },
    filesOf(brokenManifest),
  );
  const brokenVerdictId = "7b8c9d0e-1f2a-4b3c-9d4e-5f6a7b8c9d0e";
  await db.query(
    `INSERT INTO verdicts (verdict_id, package_id, outcome, evaluated_at, document)
     VALUES ($1, $2, 'ready', $3, $4::jsonb)`,
    [
      brokenVerdictId,
      BROKEN_VERDICT_ID,
      "2026-10-15T09:30:00Z",
      JSON.stringify({
        verdictId: brokenVerdictId,
        packageId: BROKEN_VERDICT_ID,
        outcome: "ready",
      }),
    ],
  );

  await insertPackage(
    db,
    {
      packageId: OTHER_DEAL_PACKAGE_ID,
      visitId: "8c9d0e1f-2a3b-4c4d-8e5f-6a7b8c9d0e1f",
      dealId: OTHER_DEAL_ID,
      revision: 1,
      status: "uploading",
      createdAt: "2026-10-17T17:00:00.000Z",
    },
    filesOf(MANIFEST).slice(0, 1),
  );
}
