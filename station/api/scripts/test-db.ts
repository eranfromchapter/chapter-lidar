// test:db: runs the database tests (test/**/*.db.test.ts) against a migrated throwaway
// database (see scripts/lib/throwaway-postgres.ts). Extra arguments filter test files like
// npm test does.

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { urlConnection } from "../src/core/db.js";
import { runMigrations } from "../src/core/migrate.js";
import { withThrowawayDatabase } from "./lib/throwaway-postgres.js";

const root = fileURLToPath(new URL("..", import.meta.url));
const filters = process.argv.slice(2);

const status = await withThrowawayDatabase(async (db) => {
  console.log(`test:db: ${db.description}`);
  await runMigrations({ connection: urlConnection(db.url) });
  const result = spawnSync(
    process.execPath,
    ["scripts/run-tests.mjs", ...(filters.length > 0 ? filters : [".db.test.ts"])],
    {
      cwd: root,
      stdio: "inherit",
      env: { ...process.env, STATION_TEST_DATABASE_URL: db.url },
    },
  );
  return result.status ?? 1;
});
process.exit(status);
