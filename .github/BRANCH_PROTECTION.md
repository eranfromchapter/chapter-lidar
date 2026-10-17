# Branch protection, environments and release settings

These settings live in GitHub, Azure, Apple and Vercel, not in code. A repo admin applies them by
hand. No secret value is ever written in this file, in a workflow, in chat or in Slack.

## 1. Where the repo lives

- Today: `github.com/eranfromchapter/chapter-capture`.
- Later: it moves to the `HelloChapter` GitHub org.
- After the transfer, go through the checklist in section 9. Rules, environments, the Azure
  OIDC trust and the Vercel link all name the owner, so they must be checked and re-applied.

The workflows never hardcode the owner or repo name. They use `github.repository`.

## 2. Rules for `main`

Create a branch ruleset (Settings > Rules > Rulesets) that targets `main`:

| Setting                                         | Value                          |
| ----------------------------------------------- | ------------------------------ |
| Restrict deletions                              | on                             |
| Block force pushes                              | on                             |
| Require a pull request before merging           | on                             |
| Required approvals                              | 1                              |
| Dismiss stale approvals when new commits arrive | on                             |
| Require conversation resolution                 | on                             |
| Require status checks to pass                   | on, with the checks in 2.1     |
| Require branches to be up to date               | on                             |
| Bypass list                                     | empty (admins follow the rule) |

GitHub does not let the author approve their own pull request. While Eran is the only human
maintainer, either add a second maintainer as a reviewer or set required approvals to 0 and keep
every required check on. Write the choice down.

Do not add these rules to `wave/*` branches. The build agents push there directly.

### 2.1 Required status checks

A check name is the job name in the workflow.

| Workflow  | Required checks                                                                             |
| --------- | ------------------------------------------------------------------------------------------- |
| `ci.yml`  | `gates`                                                                                     |
| `ios.yml` | `CaptureCore`, `PlanExport`, `MeshExport`, `FieldKit`, `PackageKit`, `StationClient`, `App` |

- GitHub only offers a check in the list after it has run once. Push a branch first, then add them.
- Confirm the names against `ci.yml` and `ios.yml` after they are merged. A wrong name blocks
  every merge, because the check never reports.
- A job skipped by its `if:` condition counts as passed.
- `deploy-station` and `testflight` are not required checks. They deploy; they do not gate merges.

## 3. Environments

Create three environments (Settings > Environments). Each one limits deployments to `main`
(Deployment branches and tags > Selected branches and tags > `main`).

| Environment  | Used by                               | Required reviewers                                        |
| ------------ | ------------------------------------- | --------------------------------------------------------- |
| `staging`    | `deploy-station.yml` (push to `main`) | none                                                      |
| `production` | `deploy-station.yml` (manual run)     | at least one named person (for example Eran or Eli Moyal) |
| `testflight` | `testflight.yml` (manual run)         | the Apple Developer account holder                        |

A production deploy or a TestFlight upload waits until a required reviewer approves it in the
Actions run page. `deploy-station.yml` also refuses a production run that is not on `main`.

### 3.1 Variables and secrets (names only)

Values are set in the environment, never in the repo.

| Environment  | Variables                                                     | Secrets                                                                                           |
| ------------ | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `staging`    | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | none                                                                                              |
| `production` | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | none                                                                                              |
| `testflight` | `APPLE_TEAM_ID`                                               | `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8` |

- Azure needs no secret: sign-in uses OIDC (section 4). The ids are not secret.
- `APP_STORE_CONNECT_API_KEY_P8` is the full content of the `.p8` file, pasted as is.
- The HUB credential is not in GitHub. It lives in Key Vault `kv-chapter-capture-<env>` and the
  container apps read it with their managed identity.

To set them from a terminal (the value is read from a prompt or a file, never typed on the
command line):

```sh
gh variable set AZURE_CLIENT_ID --env staging --repo <owner>/chapter-capture
gh secret set APP_STORE_CONNECT_API_KEY_P8 --env testflight --repo <owner>/chapter-capture < AuthKey_<key id>.p8
```

Delete the local `.p8` file after it is stored. Never commit it.

## 4. Azure sign-in (OIDC)

One Entra app registration (or user-assigned managed identity) per environment in the
"Chapter Main" tenant, each with one federated credential:

| Field    | Value                                                                |
| -------- | -------------------------------------------------------------------- |
| Issuer   | `https://token.actions.githubusercontent.com`                        |
| Subject  | `repo:<owner>/chapter-capture:environment:staging` (or `production`) |
| Audience | `api://AzureADTokenExchange`                                         |

Role assignments for that identity:

| Scope                                     | Role                                                      |
| ----------------------------------------- | --------------------------------------------------------- |
| Container registry `acrchaptercapture`    | `AcrPush` (push and pull images)                          |
| Resource group `rg-chapter-capture-<env>` | `Contributor` (update the apps, update and start the job) |

`Contributor` on the resource group is the simple start. Narrow it later to a custom role with
only the `Microsoft.App/containerApps/*` and `Microsoft.App/jobs/*` actions the workflow uses.
The deploy identity needs no Key Vault or Postgres access.

## 5. What `deploy-station.yml` expects from Azure

Fixed names, shared with `infra/` (see `docs/waves/specs/F12.md`). `<env>` is `staging` or
`production`.

| Resource                       | Name                            |
| ------------------------------ | ------------------------------- |
| Resource group                 | `rg-chapter-capture-<env>`      |
| API container app              | `ca-capture-api-<env>`          |
| Worker container app           | `ca-capture-worker-<env>`       |
| Container registry (shared)    | `acrchaptercapture`             |
| Image repositories             | `capture-api`, `capture-worker` |
| Migration job (Container Apps) | `caj-capture-migrate-<env>`     |

- The migration job is a manually triggered Container Apps job in the same environment as the
  API, with the API's identity, database settings and Key Vault references. Its command is
  `npm run migrate --workspace station/api`. The workflow only changes its image. If the job does
  not exist, the deploy stops before anything changes.
- Each app and the job have one container and pull from `acrchaptercapture` with a managed
  identity.
- The API has external ingress and answers `GET /health` with 200.
- The worker keeps at least one replica running (it polls the job queue).

Deploy order, all in one job:

1. Build the API and worker images from the repo root with `station/api/Dockerfile` and
   `station/worker/Dockerfile`, tag them with the commit SHA and push them. If that tag already
   exists, the same image is reused, so production runs exactly what staging ran.
2. Point the migration job at the new API image, run it once and wait for `Succeeded`. On any
   other result the apps are not touched.
3. Update the API and worker apps to the new images and wait until the new revisions are ready.
4. Call `https://<api fqdn>/health` until it returns 200 (5 minutes at most), or fail.

The workflow skips cleanly while either Dockerfile is missing. There is no automatic rollback: if
the smoke test fails, redeploy the previous commit by running the workflow on it.

## 6. TestFlight

- App Store Connect API key: a team key. Uploading needs the App Manager role. Automatic cloud
  signing in `xcodebuild` needs a key with access to cloud-managed distribution certificates
  (Admin role). The account holder decides and creates the key.
- Bundle id `com.hellochapter.capture` on Chapter's Apple team.
- The build number is the workflow run number unless the manual run sets one. It must be higher
  than any build already uploaded. `ios/project.yml` must take `CFBundleVersion` from
  `CURRENT_PROJECT_VERSION`; the workflow stops if it does not.
- `ios/ci/ExportOptions.plist` holds a placeholder team id. The workflow writes the real one into
  a temporary copy.
- The workflow skips cleanly while `ios/project.yml` is missing.

## 7. Web (Vercel)

`web/` deploys through the Vercel Git integration on the Chapter Vercel team. There is no GitHub
workflow for it.

- Connect the repo in the Vercel project, root directory `web`.
- Production branch `main`. Every other branch gets a preview deployment.
- Web environment variables are set in the Vercel project settings, never in the repo.

## 8. What stays out of the repo

No Azure secret, Apple key, certificate, provisioning profile, team id, HUB credential or
connection string is committed. `npm run lint` runs secretlint over the repo, and the F12
acceptance check runs it over `.github/**` and `infra/**`.

## 9. Checklist after moving to the HelloChapter org

1. Re-create the `main` ruleset (section 2) if it did not carry over, and re-check the required
   checks.
2. Re-check the three environments, their reviewers, branch limits, variables and secrets
   (section 3).
3. In Azure, change each federated credential subject to
   `repo:HelloChapter/chapter-capture:environment:<env>` (section 4). Until then every deploy
   fails at sign-in.
4. Reconnect the Vercel project to the new repo location (section 7).
5. Update any local `origin` remote to the new URL.
6. Run `deploy-station` to staging and check the smoke test passes.
