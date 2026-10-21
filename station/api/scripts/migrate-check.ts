// migrate:check (F7 AC2): migrations apply from empty and re-running them is a no-op.
//
// 1. Every file in station/db/migrations is NNNN_<name>.sql, numbered 0001.. without gaps, with
//    an "-- Up Migration" section and no down migration (forward-only).
// 2. On an empty throwaway database (see scripts/lib/throwaway-postgres.ts) every file applies.
// 3. Every station table exists.
// 4. A second run applies nothing, and the schema snapshot (columns, constraints, indexes,
//    triggers, functions, domains) and the migrations table are unchanged.

import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import pg from "pg";
import {
  MIGRATION_FILE_PATTERN,
  MIGRATIONS_DIR,
  MIGRATIONS_TABLE,
  runMigrations,
} from "../src/core/migrate.js";
import { urlConnection } from "../src/core/db.js";
import { withThrowawayDatabase } from "./lib/throwaway-postgres.js";

const STATION_TABLES = [
  "projects_cache",
  "packages",
  "package_files",
  "jobs",
  "check_runs",
  "check_results",
  "verdicts",
  "hub_publications",
  "modeling_decisions",
  "audit_log",
  "next_revision_notices",
  "spatial_reports",
];

const UP_MARKER = /^\s*--[\s-]*up\s+migration/im;
const DOWN_MARKER = /^\s*--[\s-]*down\s+migration/im;

/** Checks the migration folder and returns the migration names in order. */
function lintMigrations(dir: string = MIGRATIONS_DIR): string[] {
  const entries = readdirSync(dir, { withFileTypes: true });
  const problems: string[] = [];
  const names: string[] = [];
  for (const entry of entries) {
    if (!entry.isFile() || !MIGRATION_FILE_PATTERN.test(entry.name)) {
      problems.push(`${entry.name}: not a migration file (expected NNNN_name.sql)`);
      continue;
    }
    const sql = readFileSync(join(dir, entry.name), "utf8");
    if (!UP_MARKER.test(sql)) {
      problems.push(`${entry.name}: missing "-- Up Migration" section`);
    }
    if (DOWN_MARKER.test(sql)) {
      problems.push(`${entry.name}: has a down migration; migrations are forward-only`);
    }
    names.push(entry.name.replace(/\.sql$/, ""));
  }
  names.sort();
  names.forEach((name, index) => {
    const expected = String(index + 1).padStart(4, "0");
    if (!name.startsWith(`${expected}_`)) {
      problems.push(`${name}: expected number ${expected} (numbers start at 0001 without gaps)`);
    }
  });
  if (names.length === 0) {
    problems.push("no migrations found");
  }
  if (problems.length > 0) {
    throw new Error(`Migration folder ${dir} is invalid:\n- ${problems.join("\n- ")}`);
  }
  return names;
}

const SNAPSHOT_QUERIES: Record<string, string> = {
  columns: `
    SELECT table_name, column_name, ordinal_position, data_type, udt_name, domain_name,
           is_nullable, column_default, is_identity, is_generated
    FROM information_schema.columns
    WHERE table_schema = 'public'
    ORDER BY table_name, ordinal_position`,
  constraints: `
    SELECT conrelid::regclass::text AS table_name, contypid::regtype::text AS domain_name,
           conname, contype, pg_get_constraintdef(oid) AS definition
    FROM pg_constraint
    WHERE connamespace = 'public'::regnamespace
    ORDER BY table_name, domain_name, conname`,
  indexes: `
    SELECT tablename, indexname, indexdef
    FROM pg_indexes
    WHERE schemaname = 'public'
    ORDER BY tablename, indexname`,
  triggers: `
    SELECT tgrelid::regclass::text AS table_name, tgname, pg_get_triggerdef(oid) AS definition
    FROM pg_trigger
    WHERE NOT tgisinternal
    ORDER BY table_name, tgname`,
  functions: `
    SELECT proname, md5(pg_get_functiondef(oid)) AS definition_md5
    FROM pg_proc
    WHERE pronamespace = 'public'::regnamespace
    ORDER BY proname`,
  domains: `
    SELECT domain_name, data_type, domain_default
    FROM information_schema.domains
    WHERE domain_schema = 'public'
    ORDER BY domain_name`,
  migrations: `SELECT id, name, run_on FROM ${MIGRATIONS_TABLE} ORDER BY id`,
};

async function schemaSnapshot(url: string): Promise<Record<string, unknown[]>> {
  const client = new pg.Client({ connectionString: url });
  await client.connect();
  try {
    const snapshot: Record<string, unknown[]> = {};
    for (const [name, sql] of Object.entries(SNAPSHOT_QUERIES)) {
      snapshot[name] = (await client.query(sql)).rows;
    }
    return snapshot;
  } finally {
    await client.end();
  }
}

async function publicRelationCount(url: string): Promise<number> {
  const client = new pg.Client({ connectionString: url });
  await client.connect();
  try {
    const result = await client.query<{ count: string }>(
      "SELECT count(*) FROM pg_class WHERE relnamespace = 'public'::regnamespace",
    );
    return Number(result.rows[0]?.count ?? -1);
  } finally {
    await client.end();
  }
}

async function main(): Promise<void> {
  const names = lintMigrations();
  console.log(`migrate:check: ${names.length} forward-only migration file(s) in ${MIGRATIONS_DIR}`);

  await withThrowawayDatabase(async (db) => {
    console.log(`migrate:check: empty ${db.description}`);

    assert.equal(await publicRelationCount(db.url), 0, "the throwaway database must be empty");

    const first = await runMigrations({ connection: urlConnection(db.url) });
    assert.deepEqual(first, names, "the first run must apply every migration, in order");
    console.log(`migrate:check: first run applied ${first.length}: ${first.join(", ")}`);

    const afterFirst = await schemaSnapshot(db.url);
    const tables = new Set(
      (afterFirst.columns as { table_name: string }[]).map((row) => row.table_name),
    );
    const missing = STATION_TABLES.filter((table) => !tables.has(table));
    assert.deepEqual(missing, [], `missing station tables: ${missing.join(", ")}`);

    const second = await runMigrations({ connection: urlConnection(db.url) });
    assert.deepEqual(second, [], "the second run must apply nothing");

    const afterSecond = await schemaSnapshot(db.url);
    assert.deepEqual(afterSecond, afterFirst, "the second run must not change the schema");
    console.log(
      `migrate:check: second run applied 0; schema unchanged (${STATION_TABLES.length} station tables)`,
    );
  });
  console.log("migrate:check: PASS");
}

main().catch((error: unknown) => {
  console.error(`migrate:check: FAIL\n${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
