// CLI: backfill the review read model (packages.manifest_bytes, packages.field_controls) of
// packages sealed before migration 0011. Dry run unless --apply is given.
//
//   node dist/read-model/backfill-main.js [--apply]     (the image; working directory station/api)
//   npx tsx scripts/backfill-review-read-model.ts [--apply]   (from the repository root)
//
// Reads NODE_ENV, the database variables (the same sign-in as the server) and the storage
// variables (AZURE_STORAGE_ACCOUNT_URL with the managed identity, or
// AZURE_STORAGE_CONNECTION_STRING; STORAGE_ORIGINALS_CONTAINER). Prints one line per package
// and a summary. Exit codes: 0 done, 1 a package failed or the run failed, 2 invalid
// configuration or arguments.

import { ConfigError, loadMaintenanceConfig } from "../core/config.js";
import { createDatabase, tokenProviderFor } from "../core/db.js";
import { createAzureOriginalsStorage } from "../storage/azure-blob.js";
import { backfillReviewReadModel } from "./backfill.js";

const USAGE = "usage: backfill-review-read-model [--apply]";

const args = process.argv.slice(2);
if (args.some((arg) => arg === "--help" || arg === "-h")) {
  console.log(USAGE);
  process.exit(0);
}
const unknown = args.filter((arg) => arg !== "--apply");
if (unknown.length > 0) {
  console.error(`unknown argument ${unknown.join(" ")}\n${USAGE}`);
  process.exit(2);
}
const apply = args.includes("--apply");

let config;
try {
  config = loadMaintenanceConfig();
} catch (error) {
  console.error(error instanceof ConfigError ? error.message : String(error));
  process.exit(2);
}

const storage = createAzureOriginalsStorage(config.storage);
if (storage === undefined) {
  console.error("originals storage is not configured");
  process.exit(2);
}
const tokenProvider = tokenProviderFor(config.database.connection);
const db = createDatabase({
  connection: config.database.connection,
  ...(tokenProvider === undefined ? {} : { tokenProvider }),
  poolMax: 2,
  applicationName: "chapter-station-backfill",
});

let exitCode: number;
try {
  console.log(
    apply
      ? "Backfilling the review read model (writes)."
      : "Dry run: nothing is written. Pass --apply to write.",
  );
  const report = await backfillReviewReadModel({
    db,
    storage,
    apply,
    log: (line) => console.log(line),
  });
  console.log(
    `${report.packages.length} package(s) checked, ${report.updated} ${
      apply ? "updated" : "would be updated"
    }, ${report.failed} failed.`,
  );
  exitCode = report.failed > 0 ? 1 : 0;
} catch (error) {
  console.error(`Backfill failed: ${error instanceof Error ? error.message : String(error)}`);
  exitCode = 1;
} finally {
  await db.close();
}
process.exit(exitCode);
