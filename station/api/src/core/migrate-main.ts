// CLI: apply pending migrations to DATABASE_URL. Used by `npm run migrate` and the image
// (node dist/core/migrate-main.js). Reads only DATABASE_URL.

import { runMigrations } from "./migrate.js";

const databaseUrl = process.env.DATABASE_URL?.trim();
if (!databaseUrl) {
  console.error("DATABASE_URL is required");
  process.exit(2);
}

try {
  const applied = await runMigrations({
    databaseUrl,
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
