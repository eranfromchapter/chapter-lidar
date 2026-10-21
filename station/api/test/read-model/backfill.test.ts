// Migrations 0009-0011 on a registry that already holds production data, and the one-off
// backfill of the review read model (scripts/backfill-review-read-model.ts).
//
// 1. A throwaway Postgres gets migrations 0001-0008 only (the production schema before v2) and
//    rows shaped like production: sealed packages with verdicts, publications, decisions and
//    audit rows, and an upload in progress. Their blobs are in a disposable Azurite.
// 2. Migrations 0009-0011 apply on top; every existing row is unchanged (also updated_at) and
//    the new columns and tables are empty.
// 3. The backfill dry run (library and CLI) reports what it would write and writes nothing;
//    --apply fills manifest_bytes and contract-valid field controls, leaves updated_at alone,
//    audits each package (in the same transaction: a failed audit row leaves the package
//    unfilled), reports missing or different blobs as failures, and a re-run finds nothing left
//    to write.
// 4. The v2 guards: read model columns and carry-over are immutable once set.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFileSync, mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import type { QueryResult, QueryResultRow } from "pg";
import { withThrowawayDatabase } from "../../scripts/lib/throwaway-postgres.js";
import { createDatabase, urlConnection, type Database, type Queryable } from "../../src/core/db.js";
import { MIGRATIONS_DIR, runMigrations } from "../../src/core/migrate.js";
import { backfillReviewReadModel, BACKFILL_ACTOR } from "../../src/read-model/backfill.js";
import { getPackage } from "../../src/routes/packages/store.js";
import { createAzureOriginalsStorage } from "../../src/storage/azure-blob.js";
import { manifestBlobName, type OriginalsStorage } from "../../src/storage/originals.js";
import { startAzurite, type TestAzurite } from "../packages/azurite.js";
import {
  CAPTURE_RECORD,
  FIELD_CONTROLS,
  MANIFEST,
  VERDICT,
  type ManifestFile,
} from "../packages/support.js";

const REPO = fileURLToPath(new URL("../../../../", import.meta.url));
const SCRIPT = join(REPO, "scripts", "backfill-review-read-model.ts");
const V1_MIGRATIONS = 8;

const SEALED_ID = "11111111-1111-4111-8111-111111111111";
const INVALID_CONTROLS_ID = "22222222-2222-4222-8222-222222222222";
const NO_CONTROLS_ID = "33333333-3333-4333-8333-333333333333";
const UPLOADING_ID = "44444444-4444-4444-8444-444444444444";
const MISSING_MANIFEST_ID = "55555555-5555-4555-8555-555555555555";
const WRONG_MANIFEST_ID = "66666666-6666-4666-8666-666666666666";
const ACTOR = "0c7f5e2a-3b4d-4e6f-8a9b-1c2d3e4f5a6b";

const CONTROLS_FILE = MANIFEST.files.find((file) => file.role === "field_controls")!;
const RECORD_FILE = MANIFEST.files.find((file) => file.role === "capture_record")!;

let azurite: TestAzurite;
let storage: OriginalsStorage;
let db: Database;
let url: string;
let release: () => void = () => undefined;
let held: Promise<void>;
let v1Dir: string;

function sha256(data: string): string {
  return createHash("sha256").update(data).digest("hex");
}

function visitOf(packageId: string): string {
  return `a${packageId.slice(1)}`;
}

function manifestOf(packageId: string): string {
  return JSON.stringify({ ...MANIFEST, packageId, visitId: visitOf(packageId) }, null, 2);
}

/** A sealed package as the v1 station registered it, with its blobs (unless leftOut). */
async function seedSealed(
  packageId: string,
  options: {
    controls?: string | null;
    manifestBlob?: "stored" | "missing" | "different";
    status?: string;
  } = {},
): Promise<void> {
  const visitId = visitOf(packageId);
  const manifest = manifestOf(packageId);
  const record = JSON.stringify({ ...CAPTURE_RECORD, visitId });
  const controls =
    options.controls === undefined ? JSON.stringify(FIELD_CONTROLS) : options.controls;
  const files: (ManifestFile & { data: string })[] = [
    { ...RECORD_FILE, path: `Source Register/${visitId}/capture-record.json`, data: record },
  ];
  if (controls !== null) {
    files.push({
      ...CONTROLS_FILE,
      path: `Field Measurements/${visitId}/field-controls.json`,
      data: controls,
    });
  }
  await db.query(
    `INSERT INTO packages
       (package_id, visit_id, deal_id, revision, status, session_request, created_by_id,
        created_by_name, created_at, manifest, manifest_sha256, sealed_at, registered_at,
        capture_record)
     VALUES ($1, $2, 'HUB-1001', 1, $3, '{"files": []}', $4, 'Dana Field',
             '2026-05-16T13:58:00Z', $5::jsonb, $6, '2026-05-16T13:57:00Z',
             '2026-05-16T14:01:00Z', $7::jsonb)`,
    [
      packageId,
      visitId,
      options.status ?? "checks_queued",
      ACTOR,
      manifest,
      sha256(manifest),
      record,
    ],
  );
  for (const file of files) {
    const blobName = `${packageId}/${file.path}`;
    await db.query(
      `INSERT INTO package_files
         (package_id, path, role, sha256, bytes, status, actual_sha256, actual_bytes, checked_at,
          verified_at, blob_name)
       VALUES ($1, $2, $3, $4, $5, 'verified', $4, $5, '2026-05-16T14:00:00Z',
               '2026-05-16T14:00:00Z', $6)`,
      [packageId, file.path, file.role, sha256(file.data), Buffer.byteLength(file.data), blobName],
    );
    await azurite.put(blobName, file.data);
  }
  const blob = options.manifestBlob ?? "stored";
  if (blob !== "missing") {
    await azurite.put(
      manifestBlobName(packageId, visitId),
      blob === "stored" ? manifest : `${manifest}\n`,
    );
  }
}

interface Snapshot {
  packages: unknown[];
  files: unknown[];
  others: unknown[];
}

async function snapshot(): Promise<Snapshot> {
  const packages = await db.query(
    `SELECT to_jsonb(p) - 'field_controls' - 'manifest_bytes' AS row FROM packages p
      ORDER BY package_id`,
  );
  const files = await db.query(
    `SELECT to_jsonb(f) - 'carried_over_from' AS row FROM package_files f
      ORDER BY package_id, path`,
  );
  const others = await db.query(
    `SELECT 'verdicts' AS t, to_jsonb(v) AS row FROM verdicts v
     UNION ALL SELECT 'hub_publications', to_jsonb(h) FROM hub_publications h
     UNION ALL SELECT 'modeling_decisions', to_jsonb(d) FROM modeling_decisions d
     UNION ALL SELECT 'audit_log', to_jsonb(a) FROM audit_log a
     ORDER BY 1, 2`,
  );
  return { packages: packages.rows, files: files.rows, others: others.rows };
}

async function readModel(): Promise<
  Map<string, { field_controls: unknown; manifest_bytes: number | null }>
> {
  const rows = await db.query<{
    package_id: string;
    field_controls: unknown;
    manifest_bytes: number | null;
  }>("SELECT package_id, field_controls, manifest_bytes FROM packages ORDER BY package_id");
  return new Map(
    rows.rows.map((row) => [
      row.package_id,
      { field_controls: row.field_controls, manifest_bytes: row.manifest_bytes },
    ]),
  );
}

/** db whose audit inserts fail inside transactions, like an audit_log outage mid-run. */
function failingAudits(base: Database): Pick<Database, "query" | "transaction"> {
  return {
    query: base.query.bind(base),
    transaction: <T>(fn: (tx: Queryable) => Promise<T>) =>
      base.transaction((tx) =>
        fn({
          query: <R extends QueryResultRow>(text: string, values?: readonly unknown[]) =>
            /INSERT INTO audit_log/.test(text)
              ? Promise.reject<QueryResult<R>>(new Error("audit_log is unavailable"))
              : tx.query<R>(text, values),
        }),
      ),
  };
}

function runScript(args: string[], env: Record<string, string>) {
  return spawnSync(process.execPath, ["--import", "tsx", SCRIPT, ...args], {
    cwd: join(REPO, "station", "api"),
    encoding: "utf8",
    env: { PATH: process.env.PATH ?? "", NODE_ENV: "test", ...env },
  });
}

let beforeUpgrade: Snapshot;

before(async () => {
  azurite = await startAzurite();
  const created = createAzureOriginalsStorage({
    connectionString: azurite.connectionString,
    originalsContainer: "originals",
    reportsContainer: "reports",
  });
  assert.ok(created);
  storage = created;

  let ready: (value: string) => void = () => undefined;
  const urlReady = new Promise<string>((resolve) => {
    ready = resolve;
  });
  held = withThrowawayDatabase(async (throwaway) => {
    ready(throwaway.url);
    await new Promise<void>((resolve) => {
      release = resolve;
    });
  });
  url = await urlReady;

  v1Dir = mkdtempSync(join(tmpdir(), "station-v1-migrations-"));
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((name) => /^\d{4}_.+\.sql$/.test(name))
    .sort();
  for (const name of files.slice(0, V1_MIGRATIONS)) {
    copyFileSync(join(MIGRATIONS_DIR, name), join(v1Dir, name));
  }
  const applied = await runMigrations({ connection: urlConnection(url), dir: v1Dir });
  assert.equal(applied.length, V1_MIGRATIONS);
  db = createDatabase({ connection: urlConnection(url), poolMax: 3 });

  await seedSealed(SEALED_ID, { status: "verdict_ready" });
  await db.query(
    `INSERT INTO verdicts (verdict_id, package_id, outcome, evaluated_at, document)
     VALUES ($1, $2, $3, $4, $5::jsonb)`,
    [
      VERDICT.verdictId,
      SEALED_ID,
      VERDICT.outcome,
      VERDICT.evaluatedAt,
      JSON.stringify({ ...VERDICT, packageId: SEALED_ID }),
    ],
  );
  await db.query(
    `INSERT INTO hub_publications (package_id, verdict_id, status, attempts, published_at)
     VALUES ($1, $2, 'published', 1, '2026-05-16T14:03:00Z')`,
    [SEALED_ID, VERDICT.verdictId],
  );
  await db.query(
    `INSERT INTO modeling_decisions (package_id, element, decision, sources, decided_by_id,
                                     decided_by_name)
     VALUES ($1, 'Kitchen north wall', 'Tape distance A.', $2::jsonb, $3, 'Bea Modeler')`,
    [
      SEALED_ID,
      JSON.stringify([{ path: `Source Register/${visitOf(SEALED_ID)}/capture-record.json` }]),
      ACTOR,
    ],
  );
  await db.query(
    `INSERT INTO audit_log (actor_type, actor_id, action, target_type, target_id)
     VALUES ('user', $1, 'package.seal', 'package', $2)`,
    [ACTOR, SEALED_ID],
  );
  await seedSealed(INVALID_CONTROLS_ID, { controls: '{"schemaVersion":"9.9.9"}' });
  await seedSealed(NO_CONTROLS_ID, { controls: null });
  await db.query(
    `INSERT INTO packages (package_id, visit_id, deal_id, revision, session_request,
                           created_by_id)
     VALUES ($1, $2, 'HUB-1001', 1, '{"files": []}', $3)`,
    [UPLOADING_ID, visitOf(UPLOADING_ID), ACTOR],
  );
  beforeUpgrade = await snapshot();
});

after(async () => {
  await db?.close();
  release();
  await held;
  azurite?.stop();
  if (v1Dir !== undefined) {
    rmSync(v1Dir, { recursive: true, force: true });
  }
});

describe("migrations 0009-0011 on a production registry", () => {
  it("apply on top of 0001-0008 and change no existing row", async () => {
    const applied = await runMigrations({ connection: urlConnection(url) });
    assert.deepEqual(applied, [
      "0009_carry-over",
      "0010_spatial-reports",
      "0011_review-read-model",
    ]);
    assert.deepEqual(await snapshot(), beforeUpgrade);
  });

  it("start the new columns and tables empty", async () => {
    for (const row of (await readModel()).values()) {
      assert.deepEqual(row, { field_controls: null, manifest_bytes: null });
    }
    const counts = await db.query<{ carried: number; notices: number; reports: number }>(
      `SELECT (SELECT count(*) FROM package_files WHERE carried_over_from IS NOT NULL) AS carried,
              (SELECT count(*) FROM next_revision_notices) AS notices,
              (SELECT count(*) FROM spatial_reports) AS reports`,
    );
    assert.deepEqual(counts.rows[0], { carried: 0, notices: 0, reports: 0 });
  });
});

describe("the review read model backfill", () => {
  it("dry run (library): reports every sealed package it would fill and writes nothing", async () => {
    const lines: string[] = [];
    const report = await backfillReviewReadModel({ db, storage, log: (line) => lines.push(line) });
    assert.equal(report.apply, false);
    assert.deepEqual(
      report.packages.map((item) => [item.packageId, item.manifestBytes, item.fieldControls]),
      [
        [SEALED_ID, Buffer.byteLength(manifestOf(SEALED_ID)), "stored"],
        [INVALID_CONTROLS_ID, Buffer.byteLength(manifestOf(INVALID_CONTROLS_ID)), "invalid"],
        [NO_CONTROLS_ID, Buffer.byteLength(manifestOf(NO_CONTROLS_ID)), "none"],
      ],
    );
    assert.equal(report.updated, 3);
    assert.equal(report.failed, 0);
    assert.ok(
      lines.every((line) => line.endsWith("(dry run)")),
      lines.join("\n"),
    );
    assert.deepEqual(await snapshot(), beforeUpgrade);
    for (const row of (await readModel()).values()) {
      assert.deepEqual(row, { field_controls: null, manifest_bytes: null });
    }
  });

  it("dry run (scripts/backfill-review-read-model.ts): the same report, exit 0, nothing written", () => {
    const result = runScript([], {
      DATABASE_URL: url,
      AZURE_STORAGE_CONNECTION_STRING: azurite.connectionString,
    });
    assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
    const lines = result.stdout.trim().split("\n");
    assert.equal(lines[0], "Dry run: nothing is written. Pass --apply to write.");
    assert.equal(
      lines[1],
      `${SEALED_ID} manifest_bytes=${Buffer.byteLength(manifestOf(SEALED_ID))}, field_controls stored (dry run)`,
    );
    assert.equal(lines.at(-1), "3 package(s) checked, 3 would be updated, 0 failed.");
  });

  it("the script refuses unknown arguments and a missing storage setting (exit 2)", () => {
    const unknown = runScript(["--force"], {
      DATABASE_URL: url,
      AZURE_STORAGE_CONNECTION_STRING: azurite.connectionString,
    });
    assert.equal(unknown.status, 2, unknown.stderr);
    assert.match(unknown.stderr, /unknown argument --force/);
    const noStorage = runScript([], { DATABASE_URL: url });
    assert.equal(noStorage.status, 2, noStorage.stderr);
    assert.match(noStorage.stderr, /AZURE_STORAGE_ACCOUNT_URL or AZURE_STORAGE_CONNECTION_STRING/);
    assert.equal(runScript(["--help"], {}).status, 0);
  });

  it("--apply stops and leaves the package unfilled when its audit row cannot be written", async () => {
    await assert.rejects(
      backfillReviewReadModel({ db: failingAudits(db), storage, apply: true }),
      /audit_log is unavailable/,
    );
    for (const row of (await readModel()).values()) {
      assert.deepEqual(row, { field_controls: null, manifest_bytes: null });
    }
    assert.deepEqual(await snapshot(), beforeUpgrade);
  });

  it("--apply fills the read model, keeps updated_at, audits, and reports blobs that do not match", async () => {
    await seedSealed(MISSING_MANIFEST_ID, { manifestBlob: "missing" });
    await seedSealed(WRONG_MANIFEST_ID, { manifestBlob: "different" });
    const updatedBefore = await db.query<{ package_id: string; updated_at: Date }>(
      "SELECT package_id, updated_at FROM packages ORDER BY package_id",
    );

    const report = await backfillReviewReadModel({ db, storage, apply: true });
    assert.equal(report.updated, 3);
    assert.equal(report.failed, 2);
    assert.deepEqual(
      report.packages
        .filter((item) => item.failure !== undefined)
        .map((item) => [item.packageId, item.failure]),
      [
        [MISSING_MANIFEST_ID, "manifest blob is missing"],
        [WRONG_MANIFEST_ID, "manifest blob does not match its registered SHA-256"],
      ],
    );

    const model = await readModel();
    assert.deepEqual(model.get(SEALED_ID), {
      field_controls: FIELD_CONTROLS,
      manifest_bytes: Buffer.byteLength(manifestOf(SEALED_ID)),
    });
    assert.deepEqual(model.get(INVALID_CONTROLS_ID), {
      field_controls: null,
      manifest_bytes: Buffer.byteLength(manifestOf(INVALID_CONTROLS_ID)),
    });
    assert.deepEqual(model.get(NO_CONTROLS_ID)?.field_controls, null);
    for (const id of [UPLOADING_ID, MISSING_MANIFEST_ID, WRONG_MANIFEST_ID]) {
      assert.deepEqual(model.get(id), { field_controls: null, manifest_bytes: null }, id);
    }

    const updatedAfter = await db.query<{ package_id: string; updated_at: Date }>(
      "SELECT package_id, updated_at FROM packages ORDER BY package_id",
    );
    assert.deepEqual(updatedAfter.rows, updatedBefore.rows);

    const audits = await db.query<{
      actor_type: string;
      actor_name: string;
      target_id: string;
      details: Record<string, unknown>;
    }>(
      `SELECT actor_type, actor_name, target_id, details FROM audit_log
        WHERE action = 'package.read_model_backfill' ORDER BY target_id`,
    );
    assert.deepEqual(
      audits.rows.map((row) => [
        row.actor_type,
        row.actor_name,
        row.target_id,
        row.details.fieldControls,
      ]),
      [
        ["system", BACKFILL_ACTOR, SEALED_ID, "stored"],
        ["system", BACKFILL_ACTOR, INVALID_CONTROLS_ID, "invalid"],
        ["system", BACKFILL_ACTOR, NO_CONTROLS_ID, "none"],
      ],
    );

    const detail = await getPackage(db, {}, SEALED_ID);
    assert.deepEqual(detail?.fieldControls, FIELD_CONTROLS);
    assert.deepEqual(detail?.manifestFile, {
      path: `Source Register/${visitOf(SEALED_ID)}/manifest.json`,
      sha256: sha256(manifestOf(SEALED_ID)),
      bytes: Buffer.byteLength(manifestOf(SEALED_ID)),
    });
  });

  it("a re-run writes nothing more", async () => {
    const report = await backfillReviewReadModel({ db, storage, apply: true });
    assert.equal(report.updated, 0);
    // Left: field controls that break the contract (reported again, never stored) and the
    // packages whose manifest blob does not match (still failing, nothing written).
    assert.deepEqual(
      report.packages.map((item) => [
        item.packageId,
        item.manifestBytes,
        item.fieldControls,
        item.failure,
      ]),
      [
        [INVALID_CONTROLS_ID, undefined, "invalid", undefined],
        [MISSING_MANIFEST_ID, undefined, "none", "manifest blob is missing"],
        [
          WRONG_MANIFEST_ID,
          undefined,
          "none",
          "manifest blob does not match its registered SHA-256",
        ],
      ],
    );
    const audits = await db.query<{ n: number }>(
      "SELECT count(*) AS n FROM audit_log WHERE action = 'package.read_model_backfill'",
    );
    assert.equal(audits.rows[0]?.n, 3);
  });
});

describe("the v2 guards", () => {
  it("keep the read model columns once set, and leave updated_at alone when only they change", async () => {
    await assert.rejects(
      db.query(`UPDATE packages SET field_controls = '{"x": 1}' WHERE package_id = $1`, [
        SEALED_ID,
      ]),
      /field controls are immutable/,
    );
    await assert.rejects(
      db.query("UPDATE packages SET manifest_bytes = 1 WHERE package_id = $1", [SEALED_ID]),
      /manifest size is immutable/,
    );
    await assert.rejects(
      db.query("UPDATE packages SET manifest_bytes = 1 WHERE package_id = $1", [UPLOADING_ID]),
      /packages_manifest_bytes_rule/,
    );
    const before = await db.query<{ updated_at: Date }>(
      "SELECT updated_at FROM packages WHERE package_id = $1",
      [SEALED_ID],
    );
    await db.query("UPDATE packages SET status = 'checking' WHERE package_id = $1", [SEALED_ID]);
    const after = await db.query<{ updated_at: Date }>(
      "SELECT updated_at FROM packages WHERE package_id = $1",
      [SEALED_ID],
    );
    assert.ok(
      after.rows[0]!.updated_at > before.rows[0]!.updated_at,
      "a status change moves updated_at",
    );
  });

  it("keep carry-over part of a verified file's frozen state", async () => {
    const nextId = "77777777-7777-4777-8777-777777777777";
    await db.query(
      `INSERT INTO packages (package_id, visit_id, deal_id, revision, supersedes_package_id,
                             session_request, created_by_id)
       VALUES ($1, $2, 'HUB-1001', 2, $3, '{"files": []}', $4)`,
      [nextId, visitOf(SEALED_ID), SEALED_ID, ACTOR],
    );
    const source = await db.query<Record<string, unknown>>(
      "SELECT * FROM package_files WHERE package_id = $1 LIMIT 1",
      [SEALED_ID],
    );
    const file = source.rows[0]!;
    await assert.rejects(
      db.query(
        `INSERT INTO package_files (package_id, path, role, sha256, bytes, carried_over_from)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [nextId, file.path, file.role, file.sha256, file.bytes, SEALED_ID],
      ),
      /package_files_carried_over_verified/,
    );
    await db.query(
      `INSERT INTO package_files (package_id, path, role, sha256, bytes, status, actual_sha256,
                                  actual_bytes, checked_at, verified_at, blob_name,
                                  carried_over_from)
       SELECT $1, path, role, sha256, bytes, status, actual_sha256, actual_bytes, checked_at,
              verified_at, blob_name, $2
         FROM package_files WHERE package_id = $2 AND path = $3`,
      [nextId, SEALED_ID, file.path],
    );
    await assert.rejects(
      db.query("UPDATE package_files SET carried_over_from = NULL WHERE package_id = $1", [nextId]),
      /verified and immutable/,
    );
  });

  it("refuse a next-revision notice without a revision and changes", async () => {
    await assert.rejects(
      db.query(
        `INSERT INTO next_revision_notices (package_id, notice, updated_by_id)
         VALUES ($1, '{"revision": 2}', $2)`,
        [SEALED_ID, ACTOR],
      ),
      /next_revision_notices_notice_object/,
    );
  });
});
