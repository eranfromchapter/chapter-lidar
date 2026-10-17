// CLI: apply pending migrations. Used by `npm run migrate` and by the image:
//
//   node dist/core/migrate-main.js        (working directory /app/station/api)
//
// Reads only NODE_ENV and the database variables (DB_AUTH=url: DATABASE_URL; DB_AUTH=entra:
// PGHOST, PGPORT, PGDATABASE, PGUSER, PGSSLMODE, AZURE_CLIENT_ID), the same sign-in as the
// server. Exit codes: 0 done, 1 migration failed, 2 invalid configuration.

import { ConfigError, loadDatabaseConfig } from "./config.js";
import { tokenProviderFor } from "./db.js";
import { runMigrations } from "./migrate.js";

let database;
try {
  ({ database } = loadDatabaseConfig());
} catch (error) {
  console.error(error instanceof ConfigError ? error.message : String(error));
  process.exit(2);
}

try {
  const tokenProvider = tokenProviderFor(database.connection);
  const applied = await runMigrations({
    connection: database.connection,
    ...(tokenProvider === undefined ? {} : { tokenProvider }),
    logger: {
      info: (message) => console.log(message),
      warn: (message) => console.warn(message),
      error: (message) => console.error(message),
    },
  });
  console.log(
    applied.length === 0
      ? "No migrations to run."
      : `Applied ${applied.length} migration(s): ${applied.join(", ")}`,
  );
} catch (error) {
  console.error(`Migration failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
}
