# Station database

Postgres 16 schema of the Chapter Capture station. The station API (`station/api`) owns every
migration, including the tables the worker, HUB publish and review screen use, so there is one
owner and one order.

## Migrations

- `migrations/NNNN_<name>.sql`, applied in number order by node-pg-migrate
  (`npm run migrate --workspace station/api`, or `MIGRATE_ON_START=true` for the API).
- Forward-only: each file has only an `-- Up Migration` section. Never edit or delete an applied
  file; change the schema with a new file.
- `npm run migrate:check --workspace station/api` applies every file to an empty throwaway
  database, re-runs them, and fails unless the second run changes nothing. It also rejects
  misnamed files and any down migration.

## Tables

| Table                   | Written by      | Purpose                                                     |
| ----------------------- | --------------- | ----------------------------------------------------------- |
| `projects_cache`        | API (projects)  | HUB projects with a confirmed address, until `expires_at`   |
| `packages`              | API (uploads)   | One row per package revision; manifest and capture record   |
| `package_files`         | API (uploads)   | Declared files with the server-side SHA-256/size check      |
| `jobs`                  | API, worker     | `checks` and `publish` queue, claimed with `SKIP LOCKED`    |
| `check_runs`            | worker          | One run of the acceptance checks                            |
| `check_results`         | worker          | Per-rule result of a run                                    |
| `verdicts`              | worker          | Current verdict document of each package                    |
| `hub_publications`      | worker          | HUB publication state per package revision                  |
| `modeling_decisions`    | API (decisions) | Append-only modeling decision log                           |
| `audit_log`             | API, worker     | Append-only who/what/when of every write                    |
| `next_revision_notices` | API (packages)  | The phone's description of a sealed package's next revision |
| `spatial_reports`       | worker          | Spatial report PDF of each package's current verdict        |

Columns added for v2: `package_files.carried_over_from` (0009: a file of revision n+1 verified
by carry-over from revision n, sharing its blob), `packages.field_controls` and
`packages.manifest_bytes` (0011: the review read model, filled at sealing; packages sealed
before 0011 are filled once by `scripts/backfill-review-read-model.ts`, dry run unless
`--apply`).

Guards enforced in the database: declared file values and sealed manifests are immutable,
verified files (including how they were verified: blob, check result, carry-over) cannot change
or be deleted, sealed packages cannot be deleted, the read model columns are set once, and
`modeling_decisions` and `audit_log` reject UPDATE, DELETE and TRUNCATE.
