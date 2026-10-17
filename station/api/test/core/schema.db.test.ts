// Database tests for the station schema and the core DB helpers. They need a migrated, empty
// database in STATION_TEST_DATABASE_URL and skip otherwise; `npm run test:db` provides one.

import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, it } from "node:test";
import { ROLES, SCHEMAS } from "@chapter/capture-contract";
import { writeAudit } from "../../src/core/audit.js";
import { type Database, type Queryable, createDatabase } from "../../src/core/db.js";

const url = process.env.STATION_TEST_DATABASE_URL;
const skip = url ? false : "STATION_TEST_DATABASE_URL is not set (run npm run test:db)";

const SHA_A = "a".repeat(64);
const SHA_B = "b".repeat(64);
const ACTOR = "0c7f5e2a-3b4d-4e6f-8a9b-1c2d3e4f5a6b";

let db: Database;

async function insertPackage(
  q: Queryable = db,
  overrides: { revision?: number; supersedes?: string | null; visitId?: string } = {},
): Promise<string> {
  const packageId = randomUUID();
  await q.query(
    `INSERT INTO packages (package_id, visit_id, deal_id, revision, supersedes_package_id,
                           session_request, created_by_id, created_by_name)
     VALUES ($1, $2, 'deal-1001', $3, $4, '{"files":[]}', $5, 'Dana Field')`,
    [
      packageId,
      overrides.visitId ?? randomUUID(),
      overrides.revision ?? 1,
      overrides.supersedes ?? null,
      ACTOR,
    ],
  );
  return packageId;
}

async function insertFile(
  packageId: string,
  path: string,
  extra: { role?: string; captureId?: string | null; areaKey?: string | null } = {},
): Promise<void> {
  const role = extra.role ?? "plan_dxf";
  const visit = role === "capture_record" || role === "field_controls";
  await db.query(
    `INSERT INTO package_files (package_id, path, role, capture_id, area_key, sha256, bytes)
     VALUES ($1, $2, $3, $4, $5, $6, 10)`,
    [
      packageId,
      path,
      role,
      extra.captureId === undefined ? (visit ? null : randomUUID()) : extra.captureId,
      extra.areaKey === undefined ? (visit ? null : "floor-1") : extra.areaKey,
      SHA_A,
    ],
  );
}

async function sealPackage(packageId: string): Promise<void> {
  await db.query(
    `UPDATE packages SET status = 'checks_queued', manifest = '{"packageId":"x"}',
            manifest_sha256 = $2, sealed_at = now(), registered_at = now()
     WHERE package_id = $1`,
    [packageId, SHA_B],
  );
}

describe("station schema", { skip }, () => {
  before(() => {
    db = createDatabase({ url: url ?? "", poolMax: 4 });
  });
  after(async () => {
    await db?.close();
  });

  it("allows exactly the contract file roles", async () => {
    const result = await db.query<{ def: string }>(
      `SELECT pg_get_constraintdef(c.oid) AS def
       FROM pg_constraint c JOIN pg_type t ON t.oid = c.contypid
       WHERE t.typname = 'station_file_role'`,
    );
    const def = result.rows[0]?.def ?? "";
    const allowed = [...def.matchAll(/'([a-z_]+)'::text/g)].map((match) => match[1]).sort();
    assert.deepEqual(allowed, [...ROLES].sort());
  });

  it("accepts and rejects the same relative paths as the contract", async () => {
    const defs = (SCHEMAS.manifest as { $defs: { relativePath: { pattern: string } } }).$defs;
    const contract = new RegExp(defs.relativePath.pattern);
    const samples = [
      "Original Exports/floor-1/plan.dxf",
      "Photos/floor-1/kitchen N 01.jpg",
      "a",
      "a/b/c.d",
      "..a/b",
      "/abs",
      "a//b",
      "a/",
      "./a",
      "a/../b",
      "a/..",
      "a\\b",
      "tab\there",
      "x".repeat(1025),
    ];
    for (const sample of samples) {
      const expected = contract.test(sample) && sample.length <= 1024;
      const result = await db.query<{ ok: boolean }>(
        `SELECT pg_input_is_valid($1, 'station_relative_path') AS ok`,
        [sample],
      );
      assert.equal(result.rows[0]?.ok, expected, JSON.stringify(sample));
    }
  });

  it("enforces the revision and supersedes rule", async () => {
    const visitId = randomUUID();
    const first = await insertPackage(db, { visitId });
    await insertPackage(db, { visitId, revision: 2, supersedes: first });
    await assert.rejects(insertPackage(db, { revision: 2, supersedes: null }), /supersedes_rule/);
    await assert.rejects(insertPackage(db, { revision: 1, supersedes: first }), /supersedes_rule/);
    await assert.rejects(
      insertPackage(db, { visitId, revision: 2, supersedes: first }),
      /packages_visit_revision_key/,
    );
  });

  it("requires a manifest exactly when the package is sealed and keeps it immutable", async () => {
    const packageId = await insertPackage();
    await assert.rejects(
      db.query(`UPDATE packages SET status = 'checks_queued' WHERE package_id = $1`, [packageId]),
      /packages_sealed_rule/,
    );
    await sealPackage(packageId);
    await db.query(`UPDATE packages SET status = 'checking' WHERE package_id = $1`, [packageId]);
    await db.query(`UPDATE packages SET capture_record = '{"a":1}' WHERE package_id = $1`, [
      packageId,
    ]);
    await assert.rejects(
      db.query(`UPDATE packages SET manifest = '{"other":1}' WHERE package_id = $1`, [packageId]),
      /manifest is immutable/,
    );
    await assert.rejects(
      db.query(`UPDATE packages SET capture_record = '{"a":2}' WHERE package_id = $1`, [packageId]),
      /capture record is immutable/,
    );
    await assert.rejects(
      db.query(`UPDATE packages SET deal_id = 'deal-2' WHERE package_id = $1`, [packageId]),
      /identity fields are immutable/,
    );
    await assert.rejects(
      db.query(`DELETE FROM packages WHERE package_id = $1`, [packageId]),
      /sealed and cannot be deleted/,
    );
  });

  it("enforces visit-wide and per-capture file rules", async () => {
    const packageId = await insertPackage();
    await insertFile(packageId, "Source Register/capture-record.json", { role: "capture_record" });
    await insertFile(packageId, "Original Exports/floor-1/plan.dxf");
    await assert.rejects(
      insertFile(packageId, "x.json", {
        role: "field_controls",
        captureId: randomUUID(),
        areaKey: "floor-1",
      }),
      /visit_role_rule/,
    );
    await assert.rejects(
      insertFile(packageId, "y.dxf", { captureId: null, areaKey: null }),
      /visit_role_rule/,
    );
    await assert.rejects(insertFile(packageId, "z.dxf", { areaKey: null }), /capture_pair/);
    await assert.rejects(
      insertFile(packageId, "w.dxf", { role: "blueprint" }),
      /station_file_role/,
    );
  });

  it("only marks a file verified when the stored blob matches, then freezes it", async () => {
    const packageId = await insertPackage();
    const path = "Original Exports/floor-1/plan.dxf";
    await insertFile(packageId, path);
    const setStatus = (
      status: string,
      sha: string | null,
      bytes: number | null,
      verified: boolean,
    ) =>
      db.query(
        `UPDATE package_files SET status = $3, actual_sha256 = $4, actual_bytes = $5,
                checked_at = now(), verified_at = CASE WHEN $6 THEN now() END
         WHERE package_id = $1 AND path = $2`,
        [packageId, path, status, sha, bytes, verified],
      );
    await assert.rejects(setStatus("verified", SHA_B, 10, true), /status_rule/);
    await assert.rejects(setStatus("verified", null, null, true), /status_rule/);
    await assert.rejects(setStatus("sha256_mismatch", SHA_A, 10, false), /status_rule/);
    await setStatus("sha256_mismatch", SHA_B, 10, false);
    await setStatus("verified", SHA_A, 10, true);
    await assert.rejects(setStatus("sha256_mismatch", SHA_B, 10, false), /verified and immutable/);
    await assert.rejects(
      db.query(`UPDATE package_files SET sha256 = $3 WHERE package_id = $1 AND path = $2`, [
        packageId,
        path,
        SHA_B,
      ]),
      /declared fields/,
    );
    await assert.rejects(
      db.query(`DELETE FROM package_files WHERE package_id = $1 AND path = $2`, [packageId, path]),
      /cannot be deleted/,
    );
  });

  it("parses bigint columns as numbers", async () => {
    const result = await db.query<{ n: number }>(`SELECT 9007199254740991::bigint AS n`);
    assert.equal(result.rows[0]?.n, Number.MAX_SAFE_INTEGER);
    await assert.rejects(db.query(`SELECT 9007199254740993::bigint AS n`), /safe integer/);
  });
});

describe("jobs queue", { skip }, () => {
  before(() => {
    db = createDatabase({ url: url ?? "", poolMax: 4 });
  });
  after(async () => {
    await db?.close();
  });

  it("keeps one active job per package and type", async () => {
    const packageId = await insertPackage();
    await sealPackage(packageId);
    await db.query(`INSERT INTO jobs (type, package_id) VALUES ('checks', $1)`, [packageId]);
    await assert.rejects(
      db.query(`INSERT INTO jobs (type, package_id) VALUES ('checks', $1)`, [packageId]),
      /jobs_one_active_per_package_type/,
    );
    await db.query(`INSERT INTO jobs (type, package_id) VALUES ('publish', $1)`, [packageId]);
  });

  it("lets concurrent workers claim different jobs with SKIP LOCKED", async () => {
    await db.query(
      `UPDATE jobs SET status = 'failed', finished_at = now() WHERE status = 'queued'`,
    );
    for (let i = 0; i < 2; i += 1) {
      const packageId = await insertPackage();
      await sealPackage(packageId);
      await db.query(
        `INSERT INTO jobs (type, package_id, run_after) VALUES ('checks', $1, now() - interval '1 minute')`,
        [packageId],
      );
    }
    const claim = (tx: Queryable, worker: string) =>
      tx.query<{ job_id: string }>(
        `UPDATE jobs SET status = 'running', locked_at = now(), locked_by = $1, attempts = attempts + 1
         WHERE job_id = (
           SELECT job_id FROM jobs WHERE status = 'queued' AND run_after <= now()
           ORDER BY run_after, created_at FOR UPDATE SKIP LOCKED LIMIT 1)
         RETURNING job_id`,
        [worker],
      );
    let releaseFirst: () => void = () => undefined;
    const held = new Promise<void>((resolve) => {
      releaseFirst = resolve;
    });
    let firstJob: string | undefined;
    let claimed!: () => void;
    const firstClaimed = new Promise<void>((resolve) => {
      claimed = resolve;
    });
    const first = db.transaction(async (tx) => {
      firstJob = (await claim(tx, "worker-a")).rows[0]?.job_id;
      claimed();
      await held;
    });
    await firstClaimed;
    const secondJob = await db.transaction(
      async (tx) => (await claim(tx, "worker-b")).rows[0]?.job_id,
    );
    releaseFirst();
    await first;
    assert.ok(firstJob);
    assert.ok(secondJob);
    assert.notEqual(firstJob, secondJob);
  });

  it("requires a lock for running jobs", async () => {
    const packageId = await insertPackage();
    await sealPackage(packageId);
    await assert.rejects(
      db.query(`INSERT INTO jobs (type, package_id, status) VALUES ('publish', $1, 'running')`, [
        packageId,
      ]),
      /jobs_lock_rule/,
    );
  });
});

describe("verdicts, publications and decisions", { skip }, () => {
  before(() => {
    db = createDatabase({ url: url ?? "", poolMax: 4 });
  });
  after(async () => {
    await db?.close();
  });

  it("keeps one verdict per package that matches its document", async () => {
    const packageId = await insertPackage();
    await sealPackage(packageId);
    const verdictId = randomUUID();
    const insert = (id: string, outcome: string, document: Record<string, unknown>) =>
      db.query(
        `INSERT INTO verdicts (verdict_id, package_id, outcome, evaluated_at, document)
         VALUES ($1, $2, $3, now(), $4)
         ON CONFLICT (package_id) DO UPDATE
           SET verdict_id = EXCLUDED.verdict_id, outcome = EXCLUDED.outcome,
               evaluated_at = EXCLUDED.evaluated_at, document = EXCLUDED.document`,
        [id, packageId, outcome, JSON.stringify(document)],
      );
    await assert.rejects(
      insert(verdictId, "ready", { verdictId, packageId, outcome: "blocked" }),
      /verdicts_document_matches/,
    );
    await assert.rejects(
      insert(verdictId, "ready", { packageId, outcome: "ready" }),
      /document_matches/,
    );
    await insert(verdictId, "ready", { verdictId, packageId, outcome: "ready" });
    const rerun = randomUUID();
    await insert(rerun, "limited", { verdictId: rerun, packageId, outcome: "limited" });
    const rows = await db.query(`SELECT verdict_id FROM verdicts WHERE package_id = $1`, [
      packageId,
    ]);
    assert.deepEqual(rows.rows, [{ verdict_id: rerun }]);
  });

  it("cascades check results when a run is replaced", async () => {
    const packageId = await insertPackage();
    await sealPackage(packageId);
    const run = await db.query<{ run_id: string }>(
      `INSERT INTO check_runs (package_id) VALUES ($1) RETURNING run_id`,
      [packageId],
    );
    const runId = run.rows[0]?.run_id;
    await db.query(
      `INSERT INTO check_results (run_id, ordinal, rule_id, title, status)
       VALUES ($1, 0, 'units.scale', 'Units and scale', 'passed')`,
      [runId],
    );
    await assert.rejects(
      db.query(
        `INSERT INTO check_results (run_id, ordinal, rule_id, title, status)
         VALUES ($1, 1, 'Units', 'Bad', 'passed')`,
        [runId],
      ),
      /rule_id_valid/,
    );
    await db.query(`DELETE FROM check_runs WHERE run_id = $1`, [runId]);
    const left = await db.query(`SELECT count(*)::int AS n FROM check_results WHERE run_id = $1`, [
      runId,
    ]);
    assert.deepEqual(left.rows, [{ n: 0 }]);
  });

  it("stores the HUB error when a publication fails", async () => {
    const packageId = await insertPackage();
    await sealPackage(packageId);
    await db.query(`INSERT INTO hub_publications (package_id) VALUES ($1)`, [packageId]);
    await assert.rejects(
      db.query(`UPDATE hub_publications SET status = 'publish_failed' WHERE package_id = $1`, [
        packageId,
      ]),
      /failed_has_error/,
    );
    await db.query(
      `UPDATE hub_publications SET status = 'publish_failed', attempts = 5,
              error = '{"status":503,"message":"HUB unavailable"}' WHERE package_id = $1`,
      [packageId],
    );
    await assert.rejects(
      db.query(`INSERT INTO hub_publications (package_id) VALUES ($1)`, [packageId]),
      /hub_publications_package_id_key/,
    );
  });

  it("keeps modeling decisions append-only", async () => {
    const packageId = await insertPackage();
    const decision = await db.query<{ decision_id: string }>(
      `INSERT INTO modeling_decisions (package_id, element, decision, sources, decided_by_id, decided_by_name)
       VALUES ($1, 'Floor 1 kitchen north wall', 'Length from tape distance A',
               '[{"path":"Field Controls/field-controls.json","controlId":"A"}]', $2, 'Dana Field')
       RETURNING decision_id`,
      [packageId, ACTOR],
    );
    const id = decision.rows[0]?.decision_id;
    await assert.rejects(
      db.query(`UPDATE modeling_decisions SET note = 'x' WHERE decision_id = $1`, [id]),
      /append-only/,
    );
    await assert.rejects(
      db.query(`DELETE FROM modeling_decisions WHERE decision_id = $1`, [id]),
      /append-only/,
    );
    await assert.rejects(
      db.query(
        `INSERT INTO modeling_decisions (package_id, element, decision, sources, decided_by_id, decided_by_name)
         VALUES ($1, 'e', 'd', '[]', $2, 'n')`,
        [packageId, ACTOR],
      ),
      /sources_nonempty/,
    );
  });
});

describe("audit log", { skip }, () => {
  before(() => {
    db = createDatabase({ url: url ?? "", poolMax: 4 });
  });
  after(async () => {
    await db?.close();
  });

  it("writes redacted rows and rolls back with the transaction", async () => {
    const id = await writeAudit(db, {
      actor: { type: "user", id: ACTOR, name: "Dana Field", roles: ["capture"] },
      action: "package.create",
      target: { type: "package", id: "p-db-1" },
      details: { token: "secret-value", url: "https://a.blob.core.windows.net/o/x?sig=SECRET" },
      requestId: "req-db-1",
    });
    assert.equal(typeof id, "number");
    const row = await db.query<{ details: Record<string, unknown>; actor_roles: string[] }>(
      `SELECT details, actor_roles FROM audit_log WHERE audit_id = $1`,
      [id],
    );
    assert.deepEqual(row.rows[0]?.actor_roles, ["capture"]);
    assert.ok(!JSON.stringify(row.rows[0]?.details).includes("SECRET"));
    assert.ok(!JSON.stringify(row.rows[0]?.details).includes("secret-value"));

    await assert.rejects(
      db.transaction(async (tx) => {
        await writeAudit(tx, {
          actor: { type: "system" },
          action: "package.create",
          target: { type: "package", id: "p-db-rollback" },
        });
        throw new Error("write failed");
      }),
      /write failed/,
    );
    const rolledBack = await db.query(`SELECT 1 FROM audit_log WHERE target_id = 'p-db-rollback'`);
    assert.equal(rolledBack.rowCount, 0);
  });

  it("rejects UPDATE, DELETE and TRUNCATE", async () => {
    await assert.rejects(db.query(`UPDATE audit_log SET action = 'x.y'`), /append-only/);
    await assert.rejects(db.query(`DELETE FROM audit_log`), /append-only/);
    await assert.rejects(db.query(`TRUNCATE audit_log`), /append-only/);
  });
});
