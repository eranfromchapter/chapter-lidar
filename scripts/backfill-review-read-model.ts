// One-off backfill of the station's review read model (migration 0011_review-read-model):
// fills packages.manifest_bytes and packages.field_controls of packages sealed before it, from
// the stored originals. Run it in the deploy that applies migration 0011, after the migration.
//
//   npx tsx scripts/backfill-review-read-model.ts            dry run: prints what it would write
//   npx tsx scripts/backfill-review-read-model.ts --apply    writes
//
// Same environment as the station API's migration entrypoint plus storage: DB_AUTH and
// DATABASE_URL (or PGHOST, PGDATABASE, PGUSER, ... for Entra), AZURE_STORAGE_ACCOUNT_URL or
// AZURE_STORAGE_CONNECTION_STRING, STORAGE_ORIGINALS_CONTAINER. In the station image the same
// program is `node dist/read-model/backfill-main.js [--apply]`. See
// station/api/src/read-model/backfill.ts for the rules (fingerprint checks, idempotence, audit).

import "../station/api/src/read-model/backfill-main.js";
