# Chapter Capture infrastructure (Azure, Bicep)

`infra/main.bicep` deploys one station environment (`staging` or `production`) into the
"Chapter Main" Azure tenant. It is a **subscription-scope** template: it creates the resource
group and everything inside it.

No secret value is stored in this folder. Azure access from GitHub Actions uses an OIDC
federated credential. Postgres uses Entra ID sign-in only. Storage has shared keys turned off.
Secrets such as the HUB service credential are set by an admin directly in Key Vault.

## What gets deployed

| Resource                    | Name                              | Notes                                                                                       |
| --------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------- |
| Resource group              | `rg-chapter-capture-<env>`        | Created by the template.                                                                    |
| Container Apps environment  | `cae-chapter-capture-<env>`       | Consumption profile, logs to Log Analytics.                                                 |
| API container app           | `ca-capture-api-<env>`            | External HTTPS ingress to port 8080, system-assigned identity.                              |
| Worker container app        | `ca-capture-worker-<env>`         | No ingress, at least 1 replica (polls the job queue), system-assigned identity.             |
| Container registry (shared) | `acrchaptercapture`               | Created by the production deployment in `rg-chapter-capture-production`. Admin user off.    |
| Storage account             | `stchaptercapture<env>`           | StorageV2, HTTPS only, TLS 1.2, no public blob access, shared key off, infra encryption on. |
| Blob container              | `originals`                       | Versioning, soft delete, version-level immutability, default time-based retention policy.   |
| Key Vault                   | `kv-chapter-capture-<env>`        | RBAC authorization, soft delete, purge protection.                                          |
| Postgres Flexible Server    | `pg-chapter-capture-<env>`        | Postgres 16, Entra auth on, password auth off, database `chapter_capture`.                  |
| Log Analytics workspace     | `log-chapter-capture-<env>`       | Container Apps logs.                                                                        |
| GitHub deploy identity      | `id-chapter-capture-deploy-<env>` | User-assigned identity with a federated credential for GitHub environment `<env>`.          |

The first seven names are fixed and shared with the workflows in `.github/`. They are set in one
place, the `names` block in `main.bicep`.

Default region: `eastus2` (East US 2, the closest region to New York and Miami). Override with the
`location` parameter in the parameter file.

### Identities and roles

| Identity                         | Role                                                    | Scope                       |
| -------------------------------- | ------------------------------------------------------- | --------------------------- |
| API app (system-assigned)        | Storage Blob Data Contributor, Storage Blob Delegator   | storage account             |
| API app                          | Key Vault Secrets User                                  | Key Vault                   |
| API app, worker app              | AcrPull                                                 | registry                    |
| Worker app (system-assigned)     | Storage Blob Data Reader                                | storage account             |
| Admin Entra group                | Key Vault Secrets Officer; Postgres Entra administrator | Key Vault; Postgres server  |
| GitHub deploy identity (`<env>`) | Contributor                                             | the two container apps only |
| GitHub deploy identity           | Reader                                                  | environment resource group  |
| GitHub deploy identity           | AcrPush                                                 | registry                    |

The station signs upload and download links with **user-delegation SAS**: the API identity asks
Blob storage for a user delegation key (Storage Blob Delegator) and signs SAS tokens with it. No
account key is used, which is why shared key access is disabled on the account.

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
    --account-name stchaptercaptureproduction --container-name originals \
    --if-match "$(az storage container immutability-policy show \
      --account-name stchaptercaptureproduction --container-name originals --query etag -o tsv)"
  ```

  After locking, re-deploying with a different `originalsRetentionDays` fails, except to extend it
  with `az storage container immutability-policy extend`.

## Parameters

`params/staging.bicepparam` and `params/production.bicepparam` hold every value. They contain no
secrets. A few values are read from environment variables when you deploy:

| Variable                        | Required | Meaning                                                                              |
| ------------------------------- | -------- | ------------------------------------------------------------------------------------ |
| `CAPTURE_ADMIN_GROUP_OBJECT_ID` | yes      | Object ID of the Entra group that administers Chapter Capture.                       |
| `CAPTURE_ADMIN_GROUP_NAME`      | yes      | That group's display name, exactly as in Entra ID.                                   |
| `CAPTURE_BOOTSTRAP`             | no       | `true` only for the first deployment of an environment (see below). Default `false`. |
| `CAPTURE_API_IMAGE`             | no       | Image the API app runs. Empty means the public placeholder image.                    |
| `CAPTURE_WORKER_IMAGE`          | no       | Image the worker app runs. Empty means the public placeholder image.                 |

The compile fails if the two admin group variables are missing. These are identifiers, not
secrets. Once the group exists you can also put them straight into both parameter files.

`githubRepository` is `eranfromchapter/chapter-capture`. When the repository moves to the
HelloChapter organization, change it in both parameter files and re-deploy. That updates the
federated credentials.

**Images on re-deploy:** the template sets the container image. If you re-run it after the
workflow has deployed a real image, set `CAPTURE_API_IMAGE` and `CAPTURE_WORKER_IMAGE` to the
images that are running now. Otherwise the apps go back to the placeholder:

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
3. **Resource providers.** Register them once per subscription:
   `Microsoft.App`, `Microsoft.ContainerRegistry`, `Microsoft.DBforPostgreSQL`,
   `Microsoft.KeyVault`, `Microsoft.ManagedIdentity`, `Microsoft.OperationalInsights`,
   `Microsoft.Storage` (`az provider register --namespace <name>`).
4. **GitHub OIDC.** The template creates the deploy identity and its federated credential. The
   subject is `repo:<githubRepository>:environment:<env>`, so only jobs that run in the GitHub
   environment `staging` or `production` can sign in. After deploying, set these **variables**
   (not secrets; they are identifiers) on the matching GitHub environment:
   - `AZURE_CLIENT_ID` = deployment output `deployClientId`
   - `AZURE_TENANT_ID` = `az account show --query tenantId -o tsv`
   - `AZURE_SUBSCRIPTION_ID` = `az account show --query id -o tsv`

   Add a required reviewer to the `production` GitHub environment.

5. **HUB service credential.** After the first (bootstrap) deployment, an admin group member sets
   the secret value in each vault. Do not paste it on the command line, in chat or in Slack. Use the
   portal, or a file that is deleted afterwards:

   ```sh
   az keyvault secret set --vault-name kv-chapter-capture-staging \
     --name hub-service-credential --file <path-to-file-with-the-value>
   ```

6. **Postgres roles for the apps.** Sign in as a member of the admin group and create a database
   role for each app identity (the role name equals the container app name, which is also
   `PGUSER` in the app):

   ```sh
   export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)
   psql "host=pg-chapter-capture-staging.postgres.database.azure.com dbname=postgres user=<admin group name> sslmode=require" \
     -c "select * from pgaadauth_create_principal('ca-capture-api-staging', false, false);" \
     -c "select * from pgaadauth_create_principal('ca-capture-worker-staging', false, false);"
   ```

   Then grant those roles the privileges the migrations need on database `chapter_capture`.

## Deploy

Run from the repository root with the Azure CLI signed in (`az login`, then
`az account set --subscription <id>`). Always run `what-if` first and read it.

**Order:** production first (it creates the shared registry), then staging. On the very first run
of each environment, set `CAPTURE_BOOTSTRAP=true`. A system-assigned identity only exists after
its app is created, so the ACR pull and Key Vault references are left out until the role
assignments exist. Then do admin steps 4-6 and deploy again with bootstrap off.

```sh
export CAPTURE_ADMIN_GROUP_OBJECT_ID=<object id>
export CAPTURE_ADMIN_GROUP_NAME="<group name>"

# First run of an environment only
export CAPTURE_BOOTSTRAP=true

az deployment sub what-if --name chapter-capture-production --location eastus2 \
  --template-file infra/main.bicep --parameters infra/params/production.bicepparam
az deployment sub create --name chapter-capture-production --location eastus2 \
  --template-file infra/main.bicep --parameters infra/params/production.bicepparam

# Repeat for staging with infra/params/staging.bicepparam.
# Then: set the hub-service-credential secret, create the Postgres roles, wait a few minutes
# for role assignments to propagate, and deploy again with bootstrap off:
unset CAPTURE_BOOTSTRAP
az deployment sub what-if --name chapter-capture-staging --location eastus2 \
  --template-file infra/main.bicep --parameters infra/params/staging.bicepparam
az deployment sub create --name chapter-capture-staging --location eastus2 \
  --template-file infra/main.bicep --parameters infra/params/staging.bicepparam
```

The placeholder image (`mcr.microsoft.com/dotnet/samples:aspnetapp`, a public Microsoft sample
that serves HTTP on 8080) keeps the apps healthy until `deploy-station.yml` pushes the real
station images.

## Verify locally

The checks use the same pinned Azure CLI image as CI (`mcr.microsoft.com/azure-cli:2.67.0`).

```sh
# Template compiles (acceptance check AC2)
docker run --rm -v $PWD:/w -w /w mcr.microsoft.com/azure-cli:2.67.0 az bicep build --file infra/main.bicep

# Both parameter files compile against the template
docker run --rm -v $PWD:/w -w /w \
  -e CAPTURE_ADMIN_GROUP_OBJECT_ID=00000000-0000-0000-0000-000000000000 \
  -e CAPTURE_ADMIN_GROUP_NAME=compile-check \
  mcr.microsoft.com/azure-cli:2.67.0 sh -c \
  'az bicep build-params --file infra/params/staging.bicepparam --stdout >/dev/null &&
   az bicep build-params --file infra/params/production.bicepparam --stdout >/dev/null && echo ok'

# Storage policy test (AC5): compiles the template and both parameter files, then checks
# versioning, soft delete, the originals immutability policy and the retention days
node infra/test/storage-policy.mjs

# Or check JSON that is already built
node infra/test/storage-policy.mjs main.json [staging.parameters.json production.parameters.json]

# No secrets (AC3)
npx --no-install secretlint 'infra/**'
```

The all-zero object ID above is only for compiling. Never deploy with it.

`az bicep build` downloads the Bicep CLI on first use. Behind a TLS-inspecting proxy, give the
container the proxy CA (`-v <ca>:/ca.pem -e SSL_CERT_FILE=/ca.pem -e REQUESTS_CA_BUNDLE=/ca.pem`).
`storage-policy.mjs` does this on its own when `SSL_CERT_FILE` or `REQUESTS_CA_BUNDLE` is set on
the host.
