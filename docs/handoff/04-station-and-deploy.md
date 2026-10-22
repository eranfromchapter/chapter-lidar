# 04 · Station backend and deploy

The station is the Azure backend that the PM app's capture and the HUB web review both talk to.
It runs in the "Chapter Main" Azure tenant. **Nothing is deployed today** (section 8.3).

## 1. Components

| Part     | Folder                  | npm workspace                    | What it does                                                                                                                                                                                   |
| -------- | ----------------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| API      | `station/api`           | `@chapter/station-api` 1.0.0     | Fastify 5 HTTP API under `/v1`: Entra sign-in, HUB project lookup, upload sessions (SAS links), seal, verdict, spatial report link, review lists, modeling decisions. Owns every DB migration. |
| Checks   | `station/checks`        | `@chapter/station-checks` 1.0.0  | Library: 13 acceptance rules, evaluator `chapter-capture-station/checks` 1.1.0, returns a `Verdict` (ready, limited, blocked)                                                                  |
| HUB      | `station/hub`           | `@chapter/station-hub` 1.0.0     | Live HUB client (deal lookup, upload, document search), publication planner, spatial report PDF renderer (pdfkit, Inter, Chapter logo), fake HUB for tests                                     |
| Worker   | `station/worker`        | `@chapter/station-worker` 1.0.0  | Polls the Postgres `jobs` queue (`SKIP LOCKED`): `checks` job, then `publish` job. No ingress.                                                                                                 |
| Database | `station/db/migrations` | (SQL files)                      | Postgres 16, 11 forward-only migrations                                                                                                                                                        |
| Dev IdP  | `station/dev-idp`       | `@chapter/station-dev-idp` 1.0.0 | Local-only token issuer so the local API accepts test tokens. Refuses `NODE_ENV=production`.                                                                                                   |

Runtime: Node 22 (`.nvmrc`), engines `>=22.13.0`. Images: `station/api/Dockerfile`,
`station/worker/Dockerfile` (built from the repo root). The worker image needs `sharp` and
`heic-decode`; the Dockerfile fails early if they are missing (`station/worker/Dockerfile:44-47`).

Flow (`contract/openapi/station.yaml:10-29`): `GET /projects` → phone seals → `POST /packages`
(one write-only Blob SAS URL per file) → phone uploads each file → `POST .../files/complete`
(station computes SHA-256 and size of the stored blob) → `POST .../seal` (status
`checks_queued`) → worker runs the checks and stores the verdict (`verdict_ready`) → worker makes
the spatial report and publishes to the HUB.

## 2. Contract versions

| Item                                    | Version                                                                                   | Source                                             |
| --------------------------------------- | ----------------------------------------------------------------------------------------- | -------------------------------------------------- |
| OpenAPI `contract/openapi/station.yaml` | `1.1.0` (`openapi: 3.1.0`), base `/v1`. "1.1.0 is additive"; a 1.0.0 client keeps working | `station.yaml:4,36-37,44-46`                       |
| npm `@chapter/capture-contract`         | `1.1.0` (`contract/ts`)                                                                   | `contract/ts/package.json:3`                       |
| `manifest.schema.json` `schemaVersion`  | `1.0.0`, `1.1.0`                                                                          | `contract/schema/manifest.schema.json:18-21`       |
| `capture-record.schema.json`            | `1.0.0`, `1.1.0`                                                                          | `contract/schema/capture-record.schema.json:20-23` |
| `capture-model.schema.json`             | `1.0.0`, `1.1.0`                                                                          | `contract/schema/capture-model.schema.json`        |
| `verdict.schema.json`                   | `1.0.0`                                                                                   | `contract/schema/verdict.schema.json`              |
| `field-controls.schema.json`            | `1.0.0`                                                                                   | `contract/schema/field-controls.schema.json`       |
| Checks evaluator                        | `chapter-capture-station/checks` `1.1.0`                                                  | `station/checks/src/verdict.ts:31`                 |

- Readers accept 1.0.0 and 1.1.0; the v2 app writes manifest and capture record **1.1.0**
  (`docs/waves/specs/F1.md:35-41`). The station refuses an unknown version with 422
  (`invalid_manifest`, `invalid_capture_record`; `station/api/src/routes/uploads/index.ts:713-800`).
- `main` still has the v1 station: OpenAPI 1.0.0 and migrations `0001`-`0008` only.

## 3. API routes and auth

| Method    | Path (under `/v1`)                         | operationId                                   | Roles                      |
| --------- | ------------------------------------------ | --------------------------------------------- | -------------------------- |
| GET       | `/health` (also without `/v1`)             | getHealth                                     | public                     |
| GET       | `/projects`                                | listProjects                                  | capture, bim, admin        |
| GET       | `/projects/{dealId}`                       | getProject                                    | capture, bim, admin        |
| POST      | `/packages`                                | createUploadSession                           | capture, admin             |
| GET       | `/packages`                                | listPackages                                  | capture, bim, admin        |
| GET       | `/packages/{packageId}`                    | getPackage                                    | capture, bim, admin        |
| POST      | `/packages/{packageId}/files/complete`     | completeFile                                  | capture, admin             |
| GET       | `/packages/{packageId}/files/download`     | getFileDownloadLink                           | bim, admin                 |
| POST      | `/packages/{packageId}/seal`               | sealPackage                                   | capture, admin             |
| GET       | `/packages/{packageId}/verdict`            | getVerdict                                    | capture, bim, admin        |
| GET, POST | `/packages/{packageId}/modeling-decisions` | listModelingDecisions, createModelingDecision | bim, admin                 |
| PUT       | `/packages/{packageId}/next-revision`      | putNextRevisionNotice                         | capture, admin             |
| GET       | `/packages/{packageId}/spatial-report`     | getSpatialReportLink                          | bim, admin                 |
| POST, GET | `/packages/{packageId}/archive`            | requestPackageArchive, getPackageArchive      | bim, admin — **Not built** |
| GET       | `/review/projects`, `/review/packages`     | listReviewProjects, listReviewPackages        | capture, bim, admin        |
| GET       | `/modeling-decisions`                      | listAllModelingDecisions                      | bim, admin                 |

Source: `contract/openapi/station.yaml` (lines 63-744). The archive operations are in the
contract but have no route: "needs the worker's archive job (migration 0012_archive-job), which is
not built yet" (`station/api/test/core/openapi-conformance.coverage.test.ts:24-28`).

**Auth** (`station/api/src/core/auth.ts`): bearer token, RS256 only, verified against the
tenant's JWKS; checks issuer, audience, `exp`, `iat`, `tid`, `oid`; `tid` must equal
`ENTRA_TENANT_ID` (lines 88-127). Roles from the `roles` claim, `capture`, `bim`, `admin` (line
27). No token → 401 with `WWW-Authenticate: Bearer realm="chapter-station"`; a valid token without
a listed role → 403. Every route must declare its roles or the server does not start (lines
165-200).

**Link and upload rules:** upload SAS is create-only (`"c"`), valid 30 minutes
(`station/api/src/storage/azure-blob.ts:41`, `station/api/src/storage/originals.ts:21`); in Azure
it is a user-delegation SAS signed with the API's managed identity. Download links last 10
minutes (`station/api/src/routes/packages/download.ts:46`). Capture record and field controls are
at most 4 MiB each (`station/api/src/routes/uploads/index.ts:88-90`).

## 4. Environment variables

Config errors list variable names only; the API exits with code 2
(`station/api/src/server.ts:18-21`). Secrets are not enumerable on the config object.

### 4.1 API

`station/api/src/core/config.ts:368-394`:

| Variable                          | Default                                                          | Rule                                                                                         |
| --------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `NODE_ENV`                        | `development`                                                    | `development`, `test`, `production`. Production forces `DB_AUTH=entra` and `HUB_MODE=live`.  |
| `STATION_VERSION`                 | `station/api/package.json` version                               | Returned by `GET /health`; max 50 chars                                                      |
| `HOST`                            | `0.0.0.0`                                                        | Listen host                                                                                  |
| `PORT`                            | `8080`                                                           | Listen port                                                                                  |
| `LOG_LEVEL`                       | `info`                                                           | `fatal` … `trace`, `silent`                                                                  |
| `BODY_LIMIT_BYTES`                | `4194304`                                                        | 1024 to 64 MiB                                                                               |
| `DB_AUTH`                         | `url`                                                            | `url` or `entra` (managed-identity token as password). Production requires `entra`.          |
| `DATABASE_URL`                    | —                                                                | Required when `DB_AUTH=url`. Secret. Must not be set with `entra`.                           |
| `PGHOST`, `PGDATABASE`, `PGUSER`  | —                                                                | Required when `DB_AUTH=entra`. `PGUSER` = the identity's Postgres role                       |
| `PGPORT`                          | `5432`                                                           |                                                                                              |
| `PGSSLMODE`                       | `require`                                                        | `require` or `verify-full`                                                                   |
| `AZURE_CLIENT_ID`                 | unset                                                            | Only for a user-assigned identity. Infra uses system-assigned.                               |
| `PGPASSWORD`                      | must not be set                                                  | Refused with `DB_AUTH=entra`                                                                 |
| `DB_POOL_MAX`                     | `10`                                                             | 1-100                                                                                        |
| `MIGRATE_ON_START`                | `false`                                                          | Local stack `true`; Azure `false` (the migration job runs them)                              |
| `ENTRA_TENANT_ID`                 | required                                                         | Tenant GUID ("Chapter Main")                                                                 |
| `ENTRA_AUDIENCE`                  | required                                                         | Comma-separated accepted `aud` values (station app registration client id and/or App ID URI) |
| `ENTRA_ISSUER`                    | `https://login.microsoftonline.com/<tenant>/v2.0`                | Locally pointed at dev-idp                                                                   |
| `ENTRA_JWKS_URL`                  | `https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys` | Locally pointed at dev-idp                                                                   |
| `ENTRA_CLOCK_TOLERANCE_SECONDS`   | `60`                                                             | 0-300                                                                                        |
| `HUB_MODE`                        | `fake`                                                           | `fake` or `live`; `fake` refused in production                                               |
| `HUB_BASE_URL`                    | —                                                                | HUB REST API base URL; required when live; https in production                               |
| `HUB_SERVICE_CREDENTIAL`          | —                                                                | Secret; required when live; a Key Vault reference in Azure                                   |
| `AZURE_STORAGE_CONNECTION_STRING` | —                                                                | Secret (Azurite locally)                                                                     |
| `AZURE_STORAGE_ACCOUNT_URL`       | —                                                                | Blob endpoint for managed-identity access (Azure)                                            |
| `STORAGE_ORIGINALS_CONTAINER`     | `originals`                                                      |                                                                                              |
| `STORAGE_REPORTS_CONTAINER`       | `reports`                                                        |                                                                                              |
| `STORAGE_PUBLIC_BLOB_ENDPOINT`    | —                                                                | Blob endpoint as clients see it, when it differs (local stack)                               |
| `REVIEW_BASE_URL`                 | unset                                                            | Web review base URL for `links.review`; links omitted while unset; https unless loopback     |
| `HUB_WEB_DEAL_URL_TEMPLATE`       | unset                                                            | HUB deal page with `{dealId}`, for `links.hub`; omitted while unset                          |

Note: `deploy-station.yml` builds the images without `--build-arg STATION_VERSION`, so in Azure
`GET /health` reports `1.0.0`, not the commit (`station/api/Dockerfile:55-58`). The image carries
the commit as label `org.opencontainers.image.revision` (`.github/workflows/deploy-station.yml:177`).

### 4.2 Worker

`station/worker/src/config.ts:9-29`:

| Variable                                                                                                            | Default                  | Rule                                                                    |
| ------------------------------------------------------------------------------------------------------------------- | ------------------------ | ----------------------------------------------------------------------- |
| `NODE_ENV`                                                                                                          | `development`            | production forces `DB_AUTH=entra`, `HUB_MODE=live`                      |
| `LOG_LEVEL`                                                                                                         | `info`                   |                                                                         |
| `DB_AUTH`, `DATABASE_URL`, `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGSSLMODE`, `AZURE_CLIENT_ID`, `PGPASSWORD` | as the API               | same rules as the API                                                   |
| `DB_POOL_MAX`                                                                                                       | `4`                      | 1-50                                                                    |
| `AZURE_STORAGE_ACCOUNT_URL` or `AZURE_STORAGE_CONNECTION_STRING`                                                    | one required             | the account URL wins                                                    |
| `STORAGE_ORIGINALS_CONTAINER`                                                                                       | `originals`              |                                                                         |
| `STORAGE_REPORTS_CONTAINER`                                                                                         | `reports`                | must differ from originals                                              |
| `REPORT_TIME_ZONE`                                                                                                  | `America/New_York`       | IANA zone printed in the report                                         |
| `HUB_MODE`                                                                                                          | `fake`                   | `fake` refused in production                                            |
| `HUB_BASE_URL`                                                                                                      | —                        | required when live; https in production                                 |
| `HUB_SERVICE_CREDENTIAL`                                                                                            | —                        | secret; required when live; visible ASCII, no spaces                    |
| `REVIEW_BASE_URL`                                                                                                   | **required, no default** | web review base URL printed in the spatial report (`config.ts:296-302`) |
| `WORKER_ID`                                                                                                         | `<hostname>-<pid>`       |                                                                         |
| `WORKER_POLL_INTERVAL_MS`                                                                                           | `2000`                   |                                                                         |
| `WORKER_LOCK_TIMEOUT_SECONDS`                                                                                       | `900`                    | must exceed 4 × `HUB_PUBLISH_RETRY_MAX_MS` (`config.ts:312-316`)        |
| `WORKER_RETRY_BASE_SECONDS`                                                                                         | `30`                     |                                                                         |
| `WORKER_RETRY_MAX_SECONDS`                                                                                          | `900`                    |                                                                         |
| `HUB_PUBLISH_RETRY_BASE_MS`                                                                                         | `2000`                   |                                                                         |
| `HUB_PUBLISH_RETRY_MAX_MS`                                                                                          | `30000`                  |                                                                         |

## 5. HUB connection

The station calls the HUB REST API with a service credential. **Every HUB call below is marked
"NOT CONFIRMED WITH THE HUB TEAM" in the code** (`station/api/src/hub/mapping.ts:4-11`,
`station/hub/src/mapping.ts:4-11`), except the upload path and its multipart field `files`.

| Call             | Used by                                       | Method and path (relative to `HUB_BASE_URL`)                   | Fields                                                                                                                           |
| ---------------- | --------------------------------------------- | -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| List deals       | API `GET /projects`; worker (address, rule 3) | `GET /api/sales/deals` (body is the array)                     | `dealId`, `name`, `address`, `addressConfirmed` (only `true` counts), `updatedAt`, `projectManager.name`, `projectManager.phone` |
| Upload a file    | worker publish                                | `POST /api/projects/{dealId}/document-media/upload`, multipart | file field `files`, folder field `folder`; response array with `id`                                                              |
| Search documents | worker publish (idempotent retry, verify)     | `GET /api/projects/{dealId}/documents?search=<file name>`      | array of `{name, folder, id}`                                                                                                    |
| Auth             | all                                           | header `authorization: Bearer <HUB_SERVICE_CREDENTIAL>`        |                                                                                                                                  |

- `dealId` is always the HUB **sales** deal id, never a project record id.
- Clients fail closed: unexpected shape → error; redirects refused; credential never logged
  (`station/api/src/hub/live.ts:1-10`, `station/hub/src/live.ts:1-11`). Timeouts: API 10 s; hub
  15 s, uploads 180 s. The API caches the deal list 10 minutes per replica
  (`station/api/src/hub/cache.ts:12`).
- `GET /projects` answers 502 `hub_unavailable` when the HUB fails
  (`station/api/src/routes/projects/index.ts:20-35`). It lists every HUB deal with a confirmed
  address to every station role; there is no per-user filter (`index.ts:40-50`).
- Check rule 3 (`property.address`) needs the deal's address from the HUB. When the HUB has no
  such deal with a confirmed address (`getDeal` returns `null`,
  `station/hub/src/live.ts:137-168`), or the HUB call fails, the checks job throws a
  `RetryableJobError` (`station/worker/src/checks-job.ts:64-79`). The job is retried with
  backoff (`WORKER_RETRY_BASE_SECONDS` 30, doubling, `station/worker/src/queue.ts:130-137`) and,
  after `max_attempts` (default 5, `0004_jobs.sql`), fails: the package status becomes
  `check_error` and the package **never gets a verdict**; nothing is published
  (`checks-job.ts:211-260`, `queue.ts:100-128`). It does not produce a Blocked verdict.
- So every HUB deal used for tests, in training and in production, must carry the HUB's
  confirmed-address flag (only `true` counts, `station/hub/src/live.ts:153-156`). This is an input
  from the HUB team (item 3 below).
- Publication (`station/hub/src/plan.ts:1-31,114-133`): folders `Capture/<visitId>/r<revision>`
  (visit-wide) and `Capture/<areaKey>/<captureId>/r<revision>` (per capture). Uploaded: the spatial
  report `spatial-report-<verdictId>.pdf`, `manifest.json`, and per capture `plan_dxf`,
  `rooms_csv`, `plan_pdf`, `plan_png`. Files over 45 MiB and every other role are not uploaded;
  the report lists them with a review link. Up to 5 attempts with backoff 2 s to 30 s
  (`station/hub/src/publisher.ts:1-17,37-41`).
- **The HUB code base snapshot (Aug 24, 2025) does not match the mapping.** Its backoffice API
  has no `/api/sales/deals` (only `POST /api/deals/webhook`) and no `document-media/upload` (it
  has `POST /api/projects/:projectId/documents/upload` with fields `directoryName`, limited to five
  folders, and `file`). It verifies user JWTs signed with `TOKEN_HASH` and has no service-credential
  mechanism. The snapshot may be older than the live HUB.

**Input needed from the HUB team, per HUB environment (training, then production):**

1. HUB REST API base URL (`HUB_BASE_URL`, Bicep `CAPTURE_HUB_BASE_URL`).
2. A HUB service credential (`HUB_SERVICE_CREDENTIAL`) and how it is sent.
3. The deals list endpoint, envelope, paging and field names (sales `dealId`, address, the
   address-confirmed flag, `updatedAt`, project manager name and phone), and test deals in HUB
   training whose address-confirmed flag is `true`.
4. The upload endpoint and how the target folder is named.
5. The document search endpoint.
6. The HUB web URL of a deal page (`HUB_WEB_DEAL_URL_TEMPLATE`) and of its Files folder (web
   `HUB_FILES_URL_TEMPLATE`).

Change point when confirmed: `station/api/src/hub/mapping.ts` and `station/hub/src/mapping.ts`.
`station/hub/test/mapping-drift.test.ts` keeps them identical for deal lookup and auth.

## 6. Database: migrations and backfill

Postgres 16. The API owns every migration; node-pg-migrate 9.0.0, table `pgmigrations`,
forward-only, advisory lock, all pending files in one transaction
(`station/db/README.md`, `station/api/src/core/migrate.ts:1-14`).

| File                           | Adds                                                                       |
| ------------------------------ | -------------------------------------------------------------------------- |
| `0001_foundation.sql`          | trigger functions, contract value domains                                  |
| `0002_projects-cache.sql`      | `projects_cache` (HUB projects with a confirmed address, 10-minute expiry) |
| `0003_packages.sql`            | `packages`, `package_files`                                                |
| `0004_jobs.sql`                | `jobs` queue (`checks`, `publish`), `max_attempts` default 5               |
| `0005_checks-and-verdicts.sql` | `check_runs`, `check_results`, `verdicts`                                  |
| `0006_hub-publications.sql`    | `hub_publications`                                                         |
| `0007_modeling-decisions.sql`  | `modeling_decisions` (append-only)                                         |
| `0008_audit-log.sql`           | `audit_log` (append-only)                                                  |
| `0009_carry-over.sql`          | `package_files.carried_over_from`, next-revision notices (OpenAPI 1.1.0)   |
| `0010_spatial-reports.sql`     | `spatial_reports`                                                          |
| `0011_review-read-model.sql`   | `packages.field_controls`, `packages.manifest_bytes`, review indexes       |

Commands:

```sh
npm run migrate --workspace station/api          # applies pending migrations (tsx on src)
npm run migrate:check --workspace station/api    # throwaway DB, applied twice; rejects misnamed files and down migrations
```

- In the image: `node dist/core/migrate-main.js` (working dir `/app/station/api`); exit 0 done, 1
  failed, 2 bad config (`station/api/src/core/migrate-main.ts:1-7`). In Azure the migration job
  `caj-capture-migrate-<env>` runs it.

**Backfill for migration 0011** (`scripts/backfill-review-read-model.ts:1-12`,
`station/api/src/read-model/backfill-main.ts:1-10`):

```sh
npx tsx scripts/backfill-review-read-model.ts            # dry run
npx tsx scripts/backfill-review-read-model.ts --apply    # writes
npm run backfill:review-read-model --workspace station/api
node dist/read-model/backfill-main.js [--apply]          # in the API image
```

- "Run it in the deploy that applies migration 0011, after the migration." It fills only packages
  sealed before 0011. Exit 0 done, 1 a package failed, 2 bad config or arguments.
- No station has ever been deployed, so a first deploy has nothing to backfill.
- `infra/` has no job for the backfill, and the migration job's identity has no storage role
  (`infra/README.md:55-56`). An environment that already holds v1 packages needs one.

## 7. Azure resources (`infra/`, Bicep)

`infra/main.bicep` is subscription-scope (`targetScope = 'subscription'`, line 17). One
environment, `staging` or `production`, per deployment, default region `eastus2`. Params:
`infra/params/staging.bicepparam`, `infra/params/production.bicepparam`. No Terraform. **No
training environment.**

### 7.1 Resources

`infra/README.md:18-32`; names in the `names` block of `infra/main.bicep:160-173`.

| Resource                    | Name                                                                                                                        |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Resource group              | `rg-chapter-capture-<env>`                                                                                                  |
| Container Apps environment  | `cae-chapter-capture-<env>` (Consumption)                                                                                   |
| API container app           | `ca-capture-api-<env>` (external HTTPS ingress to 8080)                                                                     |
| Worker container app        | `ca-capture-worker-<env>` (no ingress, at least 1 replica)                                                                  |
| Migration job               | `caj-capture-migrate-<env>` (manual, API image, `node dist/core/migrate-main.js`, 10 min, no retries)                       |
| Container registry (shared) | `acrchaptercapture` (created by the production deployment)                                                                  |
| Storage account             | `stchaptercapturestg` / `stchaptercaptureprod` (shared key off); containers `originals` (immutability policy) and `reports` |
| Key Vault                   | `kv-chapter-capture-stg` / `kv-chapter-capture-prod`; one app secret `hub-service-credential`                               |
| Postgres Flexible Server    | `pg-chapter-capture-<env>`, Postgres 16, Entra auth only, database `chapter_capture`                                        |
| Log Analytics               | `log-chapter-capture-<env>`                                                                                                 |
| GitHub deploy identity      | `id-chapter-capture-deploy-<env>` (federated credential)                                                                    |

Sizes (params files, `infra/main.bicep:128-137`): staging Postgres `Standard_B1ms` 32 GB, API 0-2
replicas, originals retention 1 day; production `Standard_B2s` 64 GB, API 1-5 replicas, storage
`Standard_GZRS`, originals retention 2557 days (7 years). API 0.5 vCPU / 1 GiB, worker 1.0 vCPU /
2 GiB. Until the first app deploy the apps run the placeholder image
`mcr.microsoft.com/dotnet/samples:aspnetapp` (`infra/main.bicep:178`).

### 7.2 Identities and roles (`infra/README.md:40-60`)

- API: Storage Blob Data Contributor and Storage Blob Delegator (account).
- Worker: Storage Blob Data Reader (account), Storage Blob Data Contributor (`reports` only).
- API and worker: Key Vault Secrets User. API, worker and migration job: AcrPull and their own
  Postgres role.
- Admin Entra group: Key Vault Secrets Officer; Postgres Entra administrator.
- Deploy identity: Contributor on the two apps and the job, Reader on the resource group, AcrPush
  on the registry.

### 7.3 App settings set by Bicep

`infra/modules/containerapps.bicep:137-221`, `infra/README.md:62-95`: `NODE_ENV=production`,
`MIGRATE_ON_START=false`, `ENTRA_TENANT_ID`, `ENTRA_AUDIENCE`, `ENTRA_ISSUER`, `ENTRA_JWKS_URL`,
`HUB_MODE=live`, `HUB_BASE_URL`, `AZURE_STORAGE_ACCOUNT_URL`, `STORAGE_ORIGINALS_CONTAINER`,
`STORAGE_REPORTS_CONTAINER`, `REPORT_TIME_ZONE=America/New_York`, `DB_AUTH=entra`, `PGHOST`,
`PGPORT=5432`, `PGDATABASE=chapter_capture`, `PGSSLMODE=require`, `PGUSER=<app or job name>`,
`HUB_SERVICE_CREDENTIAL` (Key Vault reference `hub-service-credential`, not in bootstrap mode); the
API also gets `PORT=8080`.

### 7.4 Gaps in `infra/`

1. **`REVIEW_BASE_URL` is not set.** The worker requires it and exits without it
   (`station/worker/src/config.ts:296-302`). The API's optional `REVIEW_BASE_URL` and
   `HUB_WEB_DEAL_URL_TEMPLATE` are not set either, so review and HUB links are omitted. Recorded in
   `plan.md:497-498`. Add both to `containerapps.bicep` (or set them by hand) per environment.
2. **Repo name.** Both param files set `githubRepository = 'eranfromchapter/chapter-capture'`
   (`infra/params/staging.bicepparam:9`, `production.bicepparam:9`), used as the OIDC subject
   `repo:${githubRepository}:environment:${githubEnvironment}`
   (`infra/modules/deploy-identity.bicep:32`). The repo is `eranfromchapter/chapter-lidar`. GitHub
   sign-in to Azure fails until the param matches the real repo (or the repo moves).
3. **No production check on `ENTRA_ISSUER`.** The API takes it from the environment without
   refusing a non-Entra issuer in production (`station/api/src/core/config.ts:419-429`,
   `plan.md:493-494`). Bicep sets the Entra issuer, so the risk is a misconfiguration only.

### 7.5 Deploy-time variables (identifiers, not secrets)

`infra/README.md:123-131`: `CAPTURE_ADMIN_GROUP_OBJECT_ID` (required), `CAPTURE_ADMIN_GROUP_NAME`
(required), `CAPTURE_ENTRA_AUDIENCE` (required), `CAPTURE_HUB_BASE_URL` (required, https),
`CAPTURE_BOOTSTRAP` (first run only), `CAPTURE_API_IMAGE` and `CAPTURE_WORKER_IMAGE` (set them to
the running images on a re-deploy, or the apps go back to the placeholder).

### 7.6 One-time admin steps (`infra/README.md:151-220`)

1. `Owner` (or `Contributor` + `User Access Administrator`) on the Chapter Main subscription.
2. An Entra security group for Chapter Capture admins.
3. The station app registration with app roles `capture`, `bim`, `admin`. Its client id and/or App
   ID URI go into `CAPTURE_ENTRA_AUDIENCE`. It must also expose the delegated scope that the PM app
   and the web request (**Input needed**: scope name).
4. Register resource providers: `Microsoft.App`, `Microsoft.ContainerRegistry`,
   `Microsoft.DBforPostgreSQL`, `Microsoft.KeyVault`, `Microsoft.ManagedIdentity`,
   `Microsoft.OperationalInsights`, `Microsoft.Storage`.
5. GitHub environment variables `AZURE_CLIENT_ID` (output `deployClientId`), `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID`; a required reviewer on `production`.
6. Key Vault secret `hub-service-credential` in each vault (portal, or
   `az keyvault secret set --vault-name kv-chapter-capture-stg --name hub-service-credential --file <path>`;
   never on the command line, in chat or in Slack).
7. Three Postgres roles per environment with `pgaadauth_create_principal`; the migration role owns
   the database; API and worker get data access (SQL in `infra/README.md:194-217`).

### 7.7 Deploy commands (`infra/README.md:222-265`)

Production first (it creates the shared registry), then staging. First run of each environment
with `CAPTURE_BOOTSTRAP=true`; after admin steps 5-7, deploy again with bootstrap off.

```sh
export CAPTURE_ADMIN_GROUP_OBJECT_ID=<object id>
export CAPTURE_ADMIN_GROUP_NAME="<group name>"
export CAPTURE_ENTRA_AUDIENCE="<client id or App ID URI>"
export CAPTURE_HUB_BASE_URL="https://<hub host>"
export CAPTURE_BOOTSTRAP=true            # first run of an environment only

az deployment sub what-if --name chapter-capture-production --location eastus2 \
  --template-file infra/main.bicep --parameters infra/params/production.bicepparam
az deployment sub create --name chapter-capture-production --location eastus2 \
  --template-file infra/main.bicep --parameters infra/params/production.bicepparam

az containerapp job start -g rg-chapter-capture-staging -n caj-capture-migrate-staging   # migrations by hand
```

Do not start the migration job while it still runs the placeholder image.

## 8. CI/CD

### 8.1 Workflows (`.github/workflows/`)

| Workflow             | Trigger                                                                                        | Runner                                | Needs (names only)                                                                                                                                                                                                               |
| -------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci.yml` (job `ci`)  | push, every branch                                                                             | ubuntu-24.04                          | no secrets: format, lint (eslint + secretlint), typecheck, Swift 6, poppler-utils, `npm test`, export verification                                                                                                               |
| `ios.yml`            | push, every branch                                                                             | macos-15, Xcode 26.3, XcodeGen 2.46.0 | no secrets: one job per package and `App`                                                                                                                                                                                        |
| `web-e2e.yml`        | push touching `web/**`, `contract/**`, `fixtures/**`, `station/checks/**`, `package-lock.json` | ubuntu-24.04                          | no secrets; Playwright against `web/e2e/mock-station.ts`                                                                                                                                                                         |
| `testflight.yml`     | manual                                                                                         | macos-15, Xcode 26.3                  | environment `testflight`: variable `APPLE_TEAM_ID`; secrets `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`. Builds the **standalone** app, bundle `com.hellochapter.capture`. |
| `deploy-station.yml` | push to `main` → staging; manual with `staging` or `production` (production only from `main`)  | ubuntu-24.04                          | environment `staging` / `production` variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (OIDC, no secrets)                                                                                                  |

The web has no workflow; it deploys through the Vercel Git integration
(`.github/BRANCH_PROTECTION.md:165-172`). The PM app ships through its own pipeline
(**Input needed**); `testflight.yml` is for the standalone app only.

### 8.2 `deploy-station.yml` steps

Plan (pick the environment, check both Dockerfiles exist) → check the three Azure variables →
`azure/login` with OIDC → build and push `acrchaptercapture.azurecr.io/capture-api:<sha>` and
`capture-worker:<sha>` (reused if the tag exists) → point `caj-capture-migrate-<env>` at the API
image, start it, wait up to 20 minutes for `Succeeded` (apps untouched on failure) →
`az containerapp update` the API and worker, wait up to 10 minutes for ready revisions → smoke
test `GET https://<api fqdn>/health` until 200 (5 minutes). No automatic rollback: redeploy the
previous commit (`.github/BRANCH_PROTECTION.md:139-150`).

The workflow does not run the 0011 backfill (section 6).

### 8.3 What is deployed today

- **Nothing.** The only `deploy-station` run (39133760238, push to `main`, Oct 18, 2026) failed at
  "Check the Azure environment variables": the GitHub environment `staging` has no
  `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`. Any push to `main` (merging
  `v2/main` included) triggers it again and fails the same way until they exist.
- Whether `infra/` was ever applied to Azure is not visible from the repo.
- GitHub environments (`staging`, `production`, `testflight`) and the `main` ruleset of
  `.github/BRANCH_PROTECTION.md` sections 2-3: no evidence they are set.
- `BRANCH_PROTECTION.md:43` lists the required `ci.yml` check as `gates`, but the job is named `ci`
  (`.github/workflows/ci.yml:24-25`). A ruleset requiring `gates` would block every merge.
- The environments are to be limited to `main` (`BRANCH_PROTECTION.md:54`). With that rule set, a
  station deploy runs only from `main`. A manual `staging` run is otherwise allowed from any
  branch; only `production` is refused off `main` by the workflow itself
  (`.github/workflows/deploy-station.yml:83-86`).
- Merging v2 into `main` has a side effect beyond the station: a Vercel project connected with
  production branch `main` deploys `web/` to production
  (`.github/BRANCH_PROTECTION.md:165-172`). The owner allows the production web only after
  phase 3. So (**Recommendation**, see the [README](README.md#branches-deploys-and-the-web)):
  phase 2 deploys the training station from `v2/main` (the `staging` environment allows
  `v2/main` until the merge); v2 is merged into `main` in phase 3, before the production station
  deploy; the production web project is connected only in phase 4.
- If the `main` ruleset of `BRANCH_PROTECTION.md` section 2 is set, that merge also needs the
  required `ios.yml` checks (`App` and the package jobs, `BRANCH_PROTECTION.md:44`) green. On
  `add2d74` they fail ([05, section 3.1](05-status-open-items.md#31-github-actions)).

## 9. Deploy order

### 9.1 Across the owner's phases

From the specs: "contract + station API (T0, T2) and checks (T3) → worker/hub (T4) → web (T6) →
app build (T5, T7–T10). The station must accept capture-record and manifest 1.1.0 before any app
writes them" (design spec `00-tracks.md` section 2); "Station deployed before the app"
(`docs/floorplan-report-plan.md:99`).

| Phase | Station work                                                                                                                                                                                                                                                                                                                                                                         |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1     | None needed for the PM app submission (it has no capture). Prepare: fix the `infra/` gaps (section 7.4), set up Azure and GitHub (section 7.6).                                                                                                                                                                                                                                      |
| 2     | If `staging` serves training: apply the **production Bicep first** (it alone creates the shared registry; see below), then the staging Bicep. Deploy the **training** station (all of v2: API, checks, worker, hub, migrations through `0011`) from `v2/main` (section 8.3), connected to the HUB training API, with `REVIEW_BASE_URL` = training web origin. Then the training web. |
| 3     | Merge v2 into `main`. Deploy the **production** station (same v2) from `main`, connected to the production HUB, with `REVIEW_BASE_URL` = the planned production web origin, **before** the PM app update is submitted to App Review.                                                                                                                                                 |
| 4     | Production web (its Vercel project is connected only now), then set the production HUB links.                                                                                                                                                                                                                                                                                        |

**Phase 2 dependency on production infra.** Staging cannot be deployed alone: its params set
`createRegistry = false` and `registryResourceGroupName = 'rg-chapter-capture-production'`
(`infra/params/staging.bicepparam:20-22`), and the order is "production first (it creates the
shared registry), then staging" (`infra/README.md:227-231`). Applying the production Bicep in
phase 2 creates, and starts billing for, `rg-chapter-capture-production` with
(`infra/params/production.bicepparam`):

- Postgres `Standard_B2s`, 64 GB, 35-day backups;
- storage `Standard_GZRS`, with the `originals` immutability policy of 2557 days (deployed
  unlocked; locking it is a separate, permanent step, `infra/README.md:97-116`);
- Key Vault `kv-chapter-capture-prod` with purge protection and 90-day soft delete
  (`infra/README.md:29`; **Verify:** a deleted vault then keeps its name reserved for that time);
- the container apps with at least 1 API and 1 worker replica, running the placeholder image
  until a production station deploy (section 7.1); Log Analytics with 90-day retention;
- the registry `acrchaptercapture` (Basic).

It also needs the production deploy-time variables, including `CAPTURE_HUB_BASE_URL`, which is
required (the compile fails without it, `infra/README.md:123-133`). If the production HUB URL is
not known yet (**Input needed**), deploy with the best known value and deploy again in phase 3.
Chapter decides whether these production resources may exist from phase 2 (**Input needed**).
The alternative, a registry that staging creates for itself, is **Not built**: it changes the
params and the fixed registry name `acrchaptercapture` (`infra/main.bicep:165`,
`.github/workflows/deploy-station.yml:38`).

### 9.2 Within one station deploy

Images → migrations (job) → API and worker → smoke test (`deploy-station.yml`, section 8.2), then
the 0011 backfill if the environment holds packages sealed before 0011. Infra: production Bicep
first (shared registry), then staging (`infra/README.md:227-231`).

### 9.3 Which environment serves training (Input needed)

`infra/` knows `staging` and `production` only. Two ways:

- **Use `staging` as the training station** (Recommendation: no new infra code). Point its
  `CAPTURE_HUB_BASE_URL` and `hub-service-credential` at HUB training. Note that staging's
  `originals` retention is 1 day. It needs the production Bicep applied first, in phase 2, with
  the cost and governance effects listed in section 9.1, and a `staging` environment that allows
  `v2/main` until v2 is merged (section 8.3).
- **Add a `training` environment.** Needs a new params file, new names in the `names` block of
  `infra/main.bicep`, a new GitHub environment and changes to `deploy-station.yml`, which accepts
  only `staging` and `production`.

## 10. Checklist per environment

- [ ] Azure: admin steps 1-7 done; Bicep deployed (bootstrap, then normal).
- [ ] `infra/params/*.bicepparam` `githubRepository` matches the real repo.
- [ ] `REVIEW_BASE_URL` set on API and worker; `HUB_WEB_DEAL_URL_TEMPLATE` on the API.
- [ ] HUB mapping confirmed for this HUB environment; `hub-service-credential` set in Key Vault;
      the test deals carry the confirmed-address flag (section 5).
- [ ] GitHub environment variables set; `deploy-station` run green (migration job `Succeeded`,
      `/health` 200).
- [ ] 0011 backfill run if the database holds packages from before 0011.
- [ ] `GET /v1/projects` with a `capture` token lists HUB deals; a sealed package reaches
      `verdict_ready`; the spatial report and plan files appear in the HUB deal's Files tab.
- [ ] First Azure upload: large files upload with Put Block / Put Block List through the
      create-only SAS links. Azurite rejects that, so it is untested; if Azure rejects it too,
      switch to create+write links (`plan.md:482-484`).
