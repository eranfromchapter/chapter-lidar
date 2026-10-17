// End-to-end support: the local stack (station/api/scripts/local-up.sh) and a sealed fixture
// package seeded exactly as the station API leaves it after POST /packages/{id}/seal.
//
// Local stack: Postgres postgres://station@127.0.0.1:<STATION_PG_PORT|55432>/station (trust
// auth; the API applied the migrations at start) and Azurite
// http://127.0.0.1:<STATION_AZURITE_PORT|10000>/devstoreaccount1.
//
// Each seeded package is fresh (new packageId and visitId: sealed packages cannot be deleted and
// visit + revision is unique), built from fixtures/generated/box-room with the visitId rewritten
// in paths and file contents and every SHA-256 and size recomputed.

import { createHash, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { BlobServiceClient, type ContainerClient } from "@azure/storage-blob";
import type { FileEntry, PackageManifest } from "@chapter/capture-contract";
import { createDatabase, type Database } from "../../src/db.js";

export const PG_PORT = Number(process.env.STATION_PG_PORT ?? "55432");
export const AZURITE_PORT = Number(process.env.STATION_AZURITE_PORT ?? "10000");
export const DATABASE_URL = `postgres://station@127.0.0.1:${PG_PORT}/station`;
export const ORIGINALS_CONTAINER = "originals";
export const FIXTURE_DEAL_ID = "fixture-deal-0001";

/** Azurite's published development account key (not a secret). */
const AZURITE_KEY = [
  "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq",
  "/K1SZFPTOtr/KBHBeksoGMGw==",
].join("");
export const AZURITE_CONNECTION_STRING = [
  "DefaultEndpointsProtocol=http",
  "AccountName=devstoreaccount1",
  `AccountKey=${AZURITE_KEY}`,
  `BlobEndpoint=http://127.0.0.1:${AZURITE_PORT}/devstoreaccount1`,
  "",
].join(";");

const FIXTURE_ROOT = fileURLToPath(
  new URL("../../../../fixtures/generated/box-room/package/", import.meta.url),
);
const FIXTURE_VISIT_ID = "c1b6d1fb-17af-4f4a-877c-2565ef9bdb86";

export function sha256(data: Buffer): string {
  return createHash("sha256").update(data).digest("hex");
}

function rewrite(data: Buffer, from: string, to: string): Buffer {
  const text = data.toString("latin1");
  return text.includes(from) ? Buffer.from(text.split(from).join(to), "latin1") : data;
}

export interface SeededPackage {
  readonly packageId: string;
  readonly visitId: string;
  readonly checksJobId: string;
  readonly manifest: PackageManifest;
  /** Blob name of each file by path. */
  readonly blobNames: ReadonlyMap<string, string>;
  readonly files: ReadonlyMap<string, Buffer>;
}

export interface SeedOptions {
  /** Store this file's blob with other bytes than the registry says (integrity failure). */
  readonly tamperPath?: (path: string) => boolean;
  readonly maxAttempts?: number;
  /** Insert the checks job as running under a dead worker's lock, 2 hours old. */
  readonly staleLock?: boolean;
}

export interface Stack {
  readonly db: Database;
  readonly container: ContainerClient;
  close(): Promise<void>;
}

export async function connectStack(): Promise<Stack> {
  const db = createDatabase({ connection: { auth: "url", url: DATABASE_URL }, poolMax: 4 });
  try {
    const tables = await db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM information_schema.tables
        WHERE table_name IN ('packages', 'package_files', 'jobs', 'check_runs', 'check_results', 'verdicts', 'hub_publications')`,
    );
    if (tables.rows[0]?.n !== 7) {
      throw new Error(
        "the station tables are missing: start the stack with station/api/scripts/local-up.sh",
      );
    }
  } catch (error) {
    await db.close();
    throw new Error(
      `local stack Postgres is not reachable on 127.0.0.1:${PG_PORT} (run station/api/scripts/local-up.sh): ${
        error instanceof Error ? error.message : String(error)
      }`,
      { cause: error },
    );
  }
  const container =
    BlobServiceClient.fromConnectionString(AZURITE_CONNECTION_STRING).getContainerClient(
      ORIGINALS_CONTAINER,
    );
  await container.createIfNotExists();
  return { db, container, close: () => db.close() };
}

/** Seeds one sealed box-room package with a queued checks job, as the station API would. */
export async function seedSealedPackage(
  stack: Stack,
  options: SeedOptions = {},
): Promise<SeededPackage> {
  const manifestFile = join(FIXTURE_ROOT, "Source Register", FIXTURE_VISIT_ID, "manifest.json");
  const original = JSON.parse(readFileSync(manifestFile, "utf8")) as PackageManifest;
  const packageId = randomUUID();
  const visitId = randomUUID();

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
    revision: 1,
    sealedAt: original.sealedAt,
    files: entries as PackageManifest["files"],
  };
  const manifestBytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, "utf8");

  // Blobs: attempt 1 is <packageId>/<path>; the capture model was "re-uploaded" once, so its
  // verified blob is <packageId>.retry-2/<path> (the worker must use package_files.blob_name).
  const blobNames = new Map<string, string>();
  for (const [path, data] of files) {
    const retried = path.endsWith("/capture-model.json");
    const blobName = retried ? `${packageId}.retry-2/${path}` : `${packageId}/${path}`;
    blobNames.set(path, blobName);
    const stored =
      options.tamperPath?.(path) === true
        ? Buffer.concat([data.subarray(0, data.length - 1), Buffer.from("#")])
        : data;
    await stack.container.getBlockBlobClient(blobName).upload(stored, stored.length);
    if (retried) {
      // The rejected first attempt stays (blobs are immutable); it must never be read.
      await stack.container
        .getBlockBlobClient(`${packageId}/${path}`)
        .upload(Buffer.from("rejected"), 8);
    }
  }
  await stack.container
    .getBlockBlobClient(`${packageId}/Source Register/${visitId}/manifest.json`)
    .upload(manifestBytes, manifestBytes.length);

  const recordEntry = entries.find((entry) => entry.role === "capture_record");
  const captureRecord = JSON.parse(
    (files.get(recordEntry?.path ?? "") ?? Buffer.from("{}")).toString("utf8"),
  ) as unknown;
  const session = {
    packageId,
    visitId,
    dealId: FIXTURE_DEAL_ID,
    revision: 1,
    files: entries.map((entry) => ({
      path: entry.path,
      role: entry.role,
      ...(entry.captureId === undefined ? {} : { captureId: entry.captureId }),
      ...(entry.areaKey === undefined ? {} : { areaKey: entry.areaKey }),
      sha256: entry.sha256,
      bytes: entry.bytes,
    })),
  };

  const checksJobId = await stack.db.transaction(async (tx) => {
    await tx.query(
      `INSERT INTO packages
         (package_id, visit_id, deal_id, revision, status, session_request, created_by_id, created_by_name,
          manifest, manifest_sha256, sealed_at, registered_at, capture_record)
       VALUES ($1, $2, $3, 1, 'checks_queued', $4::jsonb, 'e2e-test', 'E2E Test',
               $5::jsonb, $6, $7::timestamptz, now(), $8::jsonb)`,
      [
        packageId,
        visitId,
        FIXTURE_DEAL_ID,
        JSON.stringify(session),
        JSON.stringify(manifest),
        sha256(manifestBytes),
        manifest.sealedAt,
        JSON.stringify(captureRecord),
      ],
    );
    await tx.query(
      `INSERT INTO package_files
         (package_id, path, role, capture_id, area_key, sha256, bytes, status, actual_sha256, actual_bytes,
          checked_at, verified_at, blob_name)
       SELECT $1, f.path, f.role, f.capture_id, f.area_key, f.sha256, f.bytes, 'verified', f.sha256, f.bytes,
              now(), now(), f.blob_name
         FROM unnest($2::text[], $3::text[], $4::uuid[], $5::text[], $6::text[], $7::bigint[], $8::text[])
           AS f(path, role, capture_id, area_key, sha256, bytes, blob_name)`,
      [
        packageId,
        entries.map((e) => e.path),
        entries.map((e) => e.role),
        entries.map((e) => e.captureId ?? null),
        entries.map((e) => e.areaKey ?? null),
        entries.map((e) => e.sha256),
        entries.map((e) => e.bytes),
        entries.map((e) => blobNames.get(e.path)),
      ],
    );
    const job = options.staleLock
      ? await tx.query<{ job_id: string }>(
          `INSERT INTO jobs (type, package_id, max_attempts, status, attempts, locked_at, locked_by)
           VALUES ('checks', $1, $2, 'running', 1, now() - interval '2 hours', 'dead-worker')
           RETURNING job_id`,
          [packageId, options.maxAttempts ?? 5],
        )
      : await tx.query<{ job_id: string }>(
          `INSERT INTO jobs (type, package_id, max_attempts) VALUES ('checks', $1, $2) RETURNING job_id`,
          [packageId, options.maxAttempts ?? 5],
        );
    return job.rows[0]?.job_id ?? "";
  });

  return { packageId, visitId, checksJobId, manifest, blobNames, files };
}

/** Polls until check() returns a value (not undefined) or the timeout passes. */
export async function waitFor<T>(
  check: () => Promise<T | undefined>,
  timeoutMs: number,
  what: string,
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await check();
    if (value !== undefined) {
      return value;
    }
    if (Date.now() > deadline) {
      throw new Error(`timed out after ${timeoutMs} ms waiting for ${what}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
}
