# Chapter Capture infrastructure (Azure, Bicep)

`infra/main.bicep` deploys one station environment (`staging` or `production`) into the
"Chapter Main" Azure tenant. It is a **subscription-scope** template: it creates the resource
group and everything inside it.

No secret value is stored in this folder. Azure access from GitHub Actions uses an OIDC
federated credential. Postgres uses Entra ID sign-in only: the api, the worker and the migration
job each sign in with their own managed identity and an Entra access token (`DB_AUTH=entra`), so
there is no database password anywhere. Storage has shared keys turned off. The one app secret,
`hub-service-credential`, is set by an admin directly in Key Vault and referenced by name.

## What gets deployed

`<env>` is `staging` or `production`. Key Vault and storage account names are limited to 24
characters, so they use the short token `stg` / `prod` (decided 2026-10-17, spec F12).

| Resource                    | Name                                                 | Notes                                                                                       |
| --------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Resource group              | `rg-chapter-capture-<env>`                           | Created by the template.                                                                    |
| Container Apps environment  | `cae-chapter-capture-<env>`                          | Consumption profile, logs to Log Analytics.                                                 |
| API container app           | `ca-capture-api-<env>`                               | External HTTPS ingress to 8080, `/health` readiness probe, system-assigned identity.        |
| Worker container app        | `ca-capture-worker-<env>`                            | No ingress, at least 1 replica (polls the job queue, runs checks and HUB publish).          |
| Migration job               | `caj-capture-migrate-<env>`                          | Manual trigger, api image, `node dist/core/migrate-main.js`, 10-minute timeout, no retries. |
| Container registry (shared) | `acrchaptercapture`                                  | Created by the production deployment in `rg-chapter-capture-production`. Admin user off.    |
| Storage account             | `stchaptercapturestg` / `stchaptercaptureprod`       | StorageV2, HTTPS only, TLS 1.2, no public blob access, shared key off, infra encryption on. |
| Blob container              | `originals`                                          | Versioning, soft delete, version-level immutability, default time-based retention policy.   |
| Key Vault                   | `kv-chapter-capture-stg` / `kv-chapter-capture-prod` | RBAC authorization, soft delete, purge protection.                                          |
| Postgres Flexible Server    | `pg-chapter-capture-<env>`                           | Postgres 16, Entra auth on, password auth off, database `chapter_capture`.                  |
| Log Analytics workspace     | `log-chapter-capture-<env>`                          | Container Apps logs.                                                                        |
| GitHub deploy identity      | `id-chapter-capture-deploy-<env>`                    | User-assigned identity with a federated credential for GitHub environment `<env>`.          |

All names except the last three are fixed and shared with the workflows in `.github/`. They are
set in one place, the `names` block in `main.bicep`.

Default region: `eastus2` (East US 2, the closest region to New York and Miami). Override with the
`location` parameter in the parameter file.

### Identities and roles

| Identity                         | Role                                                    | Scope                                      |
| -------------------------------- | ------------------------------------------------------- | ------------------------------------------ |
| API app (system-assigned)        | Storage Blob Data Contributor, Storage Blob Delegator   | storage account                            |
| Worker app (system-assigned)     | Storage Blob Data Reader                                | storage account                            |
| API app, worker app              | Key Vault Secrets User                                  | Key Vault                                  |
| API app, worker app, migrate job | AcrPull                                                 | registry                                   |
| API app, worker app, migrate job | own Postgres role (Entra principal, see admin step 7)   | database `chapter_capture`                 |
| Admin Entra group                | Key Vault Secrets Officer; Postgres Entra administrator | Key Vault; Postgres server                 |
| GitHub deploy identity (`<env>`) | Contributor (update image, start the job)               | the two container apps and the migrate job |
| GitHub deploy identity           | Reader                                                  | environment resource group                 |
| GitHub deploy identity           | AcrPush                                                 | registry                                   |

A system-assigned identity belongs to one resource, so the migration job has its own identity
(`caj-capture-migrate-<env>`). It needs no Key Vault access: it reads only the database settings.

The station signs upload and download links with **user-delegation SAS**: the API identity asks
Blob storage for a user delegation key (Storage Blob Delegator) and signs SAS tokens with it. No
account key is used, which is why shared key access is disabled on the account.

### App settings

Names match `station/api/src/core/config.ts`. Set on the api, the worker and the migration job
(the job reads only `NODE_ENV` and the database variables):

| Variable                      | Value                                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| `NODE_ENV`                    | `production`                                                                         |
| `MIGRATE_ON_START`            | `false` (migrations run in the job)                                                  |
| `ENTRA_TENANT_ID`             | tenant of the deployment (Chapter Main)                                              |
| `ENTRA_AUDIENCE`              | parameter `entraAudience` (`CAPTURE_ENTRA_AUDIENCE`)                                 |
| `ENTRA_ISSUER`                | `https://login.microsoftonline.com/<tenant>/v2.0`                                    |
| `ENTRA_JWKS_URL`              | `https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys`                     |
| `DB_AUTH`                     | `entra` (Entra access token for the resource's managed identity)                     |
| `PGHOST`                      | Postgres server FQDN                                                                 |
| `PGPORT`                      | `5432`                                                                               |
| `PGDATABASE`                  | `chapter_capture`                                                                    |
| `PGUSER`                      | the resource's own Postgres role: its name (`ca-capture-api-<env>` and so on)        |
| `PGSSLMODE`                   | `require`                                                                            |
| `HUB_MODE`                    | `live`                                                                               |
| `HUB_BASE_URL`                | parameter `hubBaseUrl` (`CAPTURE_HUB_BASE_URL`, https)                               |
| `AZURE_STORAGE_ACCOUNT_URL`   | blob endpoint of the storage account                                                 |
| `STORAGE_ORIGINALS_CONTAINER` | `originals`                                                                          |
| `HUB_SERVICE_CREDENTIAL`      | Key Vault reference `hub-service-credential` (api and worker, not in bootstrap mode) |

`DATABASE_URL`, `PGPASSWORD` and `AZURE_CLIENT_ID` are not set: the identities are
system-assigned, and the station refuses a database password when `DB_AUTH` is `entra`.

The api also gets `PORT=8080`. Outside bootstrap mode it has a startup probe (TCP 8080), a
readiness probe (`GET /health`, which returns 503 while the database is down, so traffic stops)
and a lenient liveness probe (TCP 8080 every 30 s, 5 failures). A database outage does not
restart replicas.

### Originals immutability

- Blob versioning is on for the whole account, so an overwrite keeps the earlier version.
- `originals` is created with version-level immutability support and a default time-based
  retention policy of `originalsRetentionDays`: every blob version written to it cannot be
  modified or deleted for that many days after it is created.
- Production: 2557 days (7 years). Staging: 1 day.
- The policy is deployed **unlocked**. Locking makes it permanent: it can then only be extended,
  never shortened or removed, and the storage account cannot be deleted while protected data
  exists. Locking is a business decision for an admin, done once by hand:

  ```sh
  az storage container immutability-policy lock \
    --account-name stchaptercaptureprod --container-name originals \
    --if-match "$(az storage container immutability-policy show \
      --account-name stchaptercaptureprod --container-name originals --query etag -o tsv)"
  ```

  After locking, re-deploying with a different `originalsRetentionDays` fails, except to extend it
  with `az storage container immutability-policy extend`.

## Parameters

`params/staging.bicepparam` and `params/production.bicepparam` hold every value. They contain no
secrets. A few values are read from environment variables when you deploy:

| Variable                        | Required | Meaning                                                                                 |
| ------------------------------- | -------- | --------------------------------------------------------------------------------------- |
| `CAPTURE_ADMIN_GROUP_OBJECT_ID` | yes      | Object ID of the Entra group that administers Chapter Capture.                          |
| `CAPTURE_ADMIN_GROUP_NAME`      | yes      | That group's display name, exactly as in Entra ID.                                      |
| `CAPTURE_ENTRA_AUDIENCE`        | yes      | Station app registration client ID and/or App ID URI, comma-separated (ENTRA_AUDIENCE). |
| `CAPTURE_HUB_BASE_URL`          | yes      | HUB REST API base URL, https (HUB_BASE_URL).                                            |
| `CAPTURE_BOOTSTRAP`             | no       | `true` only for the first deployment of an environment (see below). Default `false`.    |
| `CAPTURE_API_IMAGE`             | no       | Image the api app and the migration job run. Empty means the placeholder image.         |
| `CAPTURE_WORKER_IMAGE`          | no       | Image the worker app runs. Empty means the placeholder image.                           |

The compile fails if any required variable is missing. These are identifiers, not secrets. Once
they are known you can also put them straight into both parameter files.

`githubRepository` is `eranfromchapter/chapter-capture`. When the repository moves to the
HelloChapter organization, change it in both parameter files and re-deploy. That updates the
federated credentials.

**Images on re-deploy:** the template sets the container images. If you re-run it after the
workflow has deployed real images, set `CAPTURE_API_IMAGE` and `CAPTURE_WORKER_IMAGE` to the
images that are running now. Otherwise the apps and the job go back to the placeholder:

```sh
export CAPTURE_API_IMAGE=$(az containerapp show -g rg-chapter-capture-staging \
  -n ca-capture-api-staging --query "properties.template.containers[0].image" -o tsv)
export CAPTURE_WORKER_IMAGE=$(az containerapp show -g rg-chapter-capture-staging \
  -n ca-capture-worker-staging --query "properties.template.containers[0].image" -o tsv)
```

## One-time admin steps (not automated)

1. **Subscription.** Use the existing Chapter Main subscription. The person deploying needs
   `Owner` (or `Contributor` + `User Access Administrator`) on it, because the template creates
   role assignments.
2. **Admin group.** Create or choose an Entra security group for Chapter Capture admins. Note its
   object ID and display name for `CAPTURE_ADMIN_GROUP_OBJECT_ID` / `CAPTURE_ADMIN_GROUP_NAME`.
3. **Station app registration.** Create the Entra app registration the station API validates
   tokens for (roles `capture`, `bim`, `admin`). Its client ID and/or App ID URI go into
   `CAPTURE_ENTRA_AUDIENCE`.
4. **Resource providers.** Register them once per subscription:
   `Microsoft.App`, `Microsoft.ContainerRegistry`, `Microsoft.DBforPostgreSQL`,
   `Microsoft.KeyVault`, `Microsoft.ManagedIdentity`, `Microsoft.OperationalInsights`,
   `Microsoft.Storage` (`az provider register --namespace <name>`).
5. **GitHub OIDC.** The template creates the deploy identity and its federated credential. The
   subject is `repo:<githubRepository>:environment:<env>`, so only jobs that run in the GitHub
   environment `staging` or `production` can sign in. After deploying, set these **variables**
   (not secrets; they are identifiers) on the matching GitHub environment:
   - `AZURE_CLIENT_ID` = deployment output `deployClientId`
   - `AZURE_TENANT_ID` = `az account show --query tenantId -o tsv`
   - `AZURE_SUBSCRIPTION_ID` = `az account show --query id -o tsv`

   Add a required reviewer to the `production` GitHub environment.

6. **HUB service credential.** After the first (bootstrap) deployment, an admin group member sets
   the secret `hub-service-credential` in each vault (`kv-chapter-capture-stg`,
   `kv-chapter-capture-prod`). It is the only app secret: the database needs none. Do not paste
   the value on the command line, in chat or in Slack. Use the portal, or a file that is deleted
   afterwards:

   ```sh
   az keyvault secret set --vault-name kv-chapter-capture-stg \
     --name hub-service-credential --file <path-to-file-with-the-value>
   ```

7. **Postgres roles (one per identity).** The api, the worker and the migration job each sign in
   as their own Entra principal. The Postgres role name must equal the identity's name, which
   is the app or job name and also its `PGUSER`. Sign in with `psql` as a member of the admin
   group (user = the admin group's display name). When `psql` asks for a password, paste a
   short-lived Entra access token from
   `az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv`. Do not
   store the token anywhere.

   In database `postgres`, create the three roles:

   ```sql
   select * from pgaadauth_create_principal('ca-capture-api-staging', false, false);
   select * from pgaadauth_create_principal('ca-capture-worker-staging', false, false);
   select * from pgaadauth_create_principal('caj-capture-migrate-staging', false, false);
   ```

   In database `chapter_capture`, make the migration role the owner of the database. On
   Postgres 16 the database owner owns schema `public` (`pg_database_owner`), so the role owns
   everything the migrations create. Then give the api and worker roles data access only:

   ```sql
   -- Let the admin act for the migration role while setting this up.
   grant "caj-capture-migrate-staging" to "<admin group name>";
   alter database chapter_capture owner to "caj-capture-migrate-staging";
   grant connect on database chapter_capture to "ca-capture-api-staging", "ca-capture-worker-staging";
   grant usage on schema public to "ca-capture-api-staging", "ca-capture-worker-staging";
   alter default privileges for role "caj-capture-migrate-staging" in schema public
     grant select, insert, update, delete on tables to "ca-capture-api-staging", "ca-capture-worker-staging";
   alter default privileges for role "caj-capture-migrate-staging" in schema public
     grant usage, select on sequences to "ca-capture-api-staging", "ca-capture-worker-staging";
   revoke "caj-capture-migrate-staging" from "<admin group name>";
   ```

   Check it: `\l chapter_capture` shows owner `caj-capture-migrate-staging`, and `\ddp` lists
   the two default privileges. Repeat with `production` names on the production server.

## Deploy

Run from the repository root with the Azure CLI signed in (`az login`, then
`az account set --subscription <id>`). Always run `what-if` first and read it.

**Order:** production first (it creates the shared registry), then staging. On the very first run
of each environment, set `CAPTURE_BOOTSTRAP=true`. A system-assigned identity only exists after
its app or job is created. So the ACR pull, the Key Vault references and the api probes are left
out until the role assignments and the HUB secret exist. Then do admin steps 5-7 and deploy
again with bootstrap off.

```sh
export CAPTURE_ADMIN_GROUP_OBJECT_ID=<object id>
export CAPTURE_ADMIN_GROUP_NAME="<group name>"
export CAPTURE_ENTRA_AUDIENCE="<client id or App ID URI>"
export CAPTURE_HUB_BASE_URL="https://<hub host>"

# First run of an environment only
export CAPTURE_BOOTSTRAP=true

az deployment sub what-if --name chapter-capture-production --location eastus2 \
  --template-file infra/main.bicep --parameters infra/params/production.bicepparam
az deployment sub create --name chapter-capture-production --location eastus2 \
  --template-file infra/main.bicep --parameters infra/params/production.bicepparam

# Repeat for staging with infra/params/staging.bicepparam.
# Then: set the HUB secret, create the Postgres roles, wait a few minutes for role
# assignments to propagate, and deploy again with bootstrap off:
unset CAPTURE_BOOTSTRAP
az deployment sub what-if --name chapter-capture-staging --location eastus2 \
  --template-file infra/main.bicep --parameters infra/params/staging.bicepparam
az deployment sub create --name chapter-capture-staging --location eastus2 \
  --template-file infra/main.bicep --parameters infra/params/staging.bicepparam
```

The placeholder image (`mcr.microsoft.com/dotnet/samples:aspnetapp`, a public Microsoft sample
that serves HTTP on 8080) keeps the apps running until `deploy-station.yml` pushes the real
station images. Do not start the migration job while it still runs the placeholder.

Running migrations by hand (the deploy workflow does the same):

```sh
az containerapp job start -g rg-chapter-capture-staging -n caj-capture-migrate-staging
```

## Verify locally

The checks use the same pinned Azure CLI image as CI (`mcr.microsoft.com/azure-cli:2.67.0`).

```sh
# Template compiles (acceptance check AC2)
docker run --rm -v $PWD:/w -w /w mcr.microsoft.com/azure-cli:2.67.0 az bicep build --file infra/main.bicep

# Both parameter files compile against the template
docker run --rm -v $PWD:/w -w /w \
  -e CAPTURE_ADMIN_GROUP_OBJECT_ID=00000000-0000-0000-0000-000000000000 \
  -e CAPTURE_ADMIN_GROUP_NAME=compile-check \
  -e CAPTURE_ENTRA_AUDIENCE=api://compile-check \
  -e CAPTURE_HUB_BASE_URL=https://hub.compile-check.invalid \
  mcr.microsoft.com/azure-cli:2.67.0 sh -c \
  'az bicep build-params --file infra/params/staging.bicepparam --stdout >/dev/null &&
   az bicep build-params --file infra/params/production.bicepparam --stdout >/dev/null && echo ok'

# Storage policy test (AC5): compiles the template and both parameter files, then checks
# versioning, soft delete, the originals immutability policy and the retention days
node infra/test/storage-policy.mjs

# Or check JSON that is already built
node infra/test/storage-policy.mjs main.json [staging.parameters.json production.parameters.json]

# No secrets (AC3)
npx --no-install secretlint --secretlintrc scripts/secretlint/secretlintrc.json '.github/**' 'infra/**'
```

The all-zero object ID and `compile-check` values above are only for compiling. Never deploy with
them.

`az bicep build` downloads the Bicep CLI on first use. Behind a TLS-inspecting proxy, give the
container the proxy CA (`-v <ca>:/ca.pem -e SSL_CERT_FILE=/ca.pem -e REQUESTS_CA_BUNDLE=/ca.pem`).
`storage-policy.mjs` does this on its own when `SSL_CERT_FILE` or `REQUESTS_CA_BUNDLE` is set on
the host.
