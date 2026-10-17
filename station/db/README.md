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

| Table                | Written by      | Purpose                                                   |
| -------------------- | --------------- | --------------------------------------------------------- |
| `projects_cache`     | API (projects)  | HUB projects with a confirmed address, until `expires_at` |
| `packages`           | API (uploads)   | One row per package revision; manifest and capture record |
| `package_files`      | API (uploads)   | Declared files with the server-side SHA-256/size check    |
| `jobs`               | API, worker     | `checks` and `publish` queue, claimed with `SKIP LOCKED`  |
| `check_runs`         | worker          | One run of the acceptance checks                          |
| `check_results`      | worker          | Per-rule result of a run                                  |
| `verdicts`           | worker          | Current verdict document of each package                  |
| `hub_publications`   | worker          | HUB publication state per package revision                |
| `modeling_decisions` | API (decisions) | Append-only modeling decision log                         |
| `audit_log`          | API, worker     | Append-only who/what/when of every write                  |

Guards enforced in the database: declared file values and sealed manifests are immutable,
verified files cannot change or be deleted, sealed packages cannot be deleted, and
`modeling_decisions` and `audit_log` reject UPDATE, DELETE and TRUNCATE.
