// Forward-only Postgres migrations from station/db/migrations (node-pg-migrate, plain SQL).
//
// Files are named NNNN_<name>.sql and contain only an "-- Up Migration" section. There are no
// down migrations: a change is always a new file. Runs take node-pg-migrate's advisory lock,
// so concurrent starts wait for each other, and all pending files run in one transaction.

import { fileURLToPath } from "node:url";
import { runner } from "node-pg-migrate";
import type { DatabaseConnection } from "./config.js";
import { pgConnectionConfig, type TokenProvider } from "./db.js";

/** station/db/migrations, from both src/core and dist/core. */
export const MIGRATIONS_DIR = fileURLToPath(new URL("../../../db/migrations", import.meta.url));
export const MIGRATIONS_TABLE = "pgmigrations";
/** Every migration file name must match this pattern. */
export const MIGRATION_FILE_PATTERN = /^\d{4}_[a-z0-9]+(?:-[a-z0-9]+)*\.sql$/;

export interface MigrationLogger {
  info(message: string): void;
  warn(message: string): void;
  error(message: string): void;
}

export interface RunMigrationsOptions {
  /** Same connection settings as the server (url or Entra managed identity). */
  readonly connection: DatabaseConnection;
  /** Required for entra connections; see tokenProviderFor in db.ts. */
  readonly tokenProvider?: TokenProvider;
  readonly dir?: string;
  readonly logger?: MigrationLogger;
}

const quietLogger: MigrationLogger = { info() {}, warn() {}, error() {} };

/** Applies every pending migration. Returns the names of the migrations it ran. */
export async function runMigrations(options: RunMigrationsOptions): Promise<string[]> {
  const logger = options.logger ?? quietLogger;
  const databaseUrl = pgConnectionConfig(options.connection, options.tokenProvider);
  const applied = await runner({
    databaseUrl,
    dir: options.dir ?? MIGRATIONS_DIR,
    // Only NNNN_name.sql files are migrations; anything else in the folder is ignored here
    // and rejected by migrate:check.
    ignorePattern: "(?!\\d{4}_[a-z0-9]+(?:-[a-z0-9]+)*\\.sql$).*",
    migrationsTable: MIGRATIONS_TABLE,
    direction: "up",
    checkOrder: true,
    singleTransaction: true,
    advisoryLockMode: "wait",
    createSchema: false,
    logger: { ...logger, debug() {} },
  });
  return applied.map((migration) => migration.name);
}
