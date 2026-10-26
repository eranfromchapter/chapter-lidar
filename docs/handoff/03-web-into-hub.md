# 03 · Web review into the HUB

The web review app goes **into the HUB**, Chapter's backoffice and operations platform. Owner
timeline: connect it **now** to the HUB **training** environment; deploy it to HUB production
**only after** the iOS capture works end to end in the PM app ([README](README.md#timeline-owner-direction-binding)).

## 1. What the web review is

"Chapter Capture review screen: projects, packages, verdicts, files and the modeling decision log"
(`web/package.json:5`). BIM operators and PMs find a project, open a capture package, read the
verdict and every finding, download files and record where each modeling decision came from
(`docs/waves/specs/F10.md:15-17`). It is drawn in the HUB design system: HUB tokens, the white HUB
"chapter" wordmark, Inter 400/600 self-hosted from `web/public/brand/`, no Google fonts, no Times
(`F10.md:29-39`, `docs/waves/design/DESIGN.md:85-88`).

| Item     | Value                                                                     | Source                                        |
| -------- | ------------------------------------------------------------------------- | --------------------------------------------- |
| Package  | `@chapter/web` 0.0.0, private, ESM                                        | `web/package.json:2-6`                        |
| Node     | `>=22.13.0`; `.nvmrc` = `22`                                              | `web/package.json:8`, `.nvmrc`                |
| Next.js  | 16.4.2, App Router; `proxy.ts` is the Next 16 proxy (formerly middleware) | `web/package.json:20`, `web/proxy.ts:1-3`     |
| Auth     | `next-auth` 5.0.0-beta.32 (Auth.js v5), provider `microsoft-entra-id`     | `web/package.json:21`, `web/auth.ts:15-16`    |
| React    | 19.3.1                                                                    | `web/package.json:22-23`                      |
| Contract | `@chapter/capture-contract` 1.1.0 (npm workspace `contract/ts`)           | `web/package.json:19`                         |
| Tests    | vitest 5.0.5 (17 files, 290 tests), Playwright 1.64.0 (25 e2e tests)      | `web/package.json:28-40`, `web/e2e/*.spec.ts` |

Routes (`web/app`):

| URL                                                                                                 | Who                                   |
| --------------------------------------------------------------------------------------------------- | ------------------------------------- |
| `/` Projects with at least one package (tabs `all`, `blocked`, `limited`, `ready`, `progress`; `q`) | all station roles                     |
| `/packages` Packages (`q`)                                                                          | all station roles                     |
| `/projects/[dealId]` Project (`tab=packages` or `log`)                                              | all station roles                     |
| `/packages/[packageId]` Package (`?file=<path>`, `?floor=<areaKey>`)                                | all roles; `capture` sees status only |
| `/decisions` Modeling decision log                                                                  | `bim`, `admin`                        |
| `/sign-in`                                                                                          | no session                            |
| `/api/auth/*`                                                                                       | Auth.js                               |

The Projects page lists only projects that already have a package: it calls the station's
`listReviewProjects` (`web/app/(review)/page.tsx:64`, `web/lib/station.ts:69-70`;
`GET /v1/review/projects`, "Projects with at least one package",
`contract/openapi/station.yaml:643-653`). The web never calls `GET /v1/projects` (the HUB deal
list); that is the phone's call on New capture. The project page reads one deal with
`getProject` (`web/app/(review)/projects/[dealId]/page.tsx:110`).

File routes (`bim`, `admin` only; `web/lib/file-access.ts:28-63`): `/packages/{id}/files/download`
(303 to a 10-minute station link), `/packages/{id}/files/preview` (streams a plan PNG, the signed
link never reaches the browser), `/packages/{id}/report/download` (303 to the spatial report link),
`/packages/{id}/verdict.json`.

**Not built:** "Download all" (package ZIP, `/packages/[id]/archive`). The station lists the
archive operations as not implemented (`station/api/test/core/openapi-conformance.coverage.test.ts:24-28`).

## 2. Facts that decide the integration

1. **It is a Node server app, not static files.** Every page and route handler is
   `force-dynamic` (for example `web/app/(review)/layout.tsx:10`). It needs Vercel or `next start`.
   `next.config.ts` sets no `output`, `basePath` or `assetPrefix` (`web/next.config.ts:9-31`).
2. **It assumes it is served at the root of its host.** 41 root-relative path literals in 24 files
   (for example `components/shell/Sidebar.tsx:36,40`), the search form `action="/"`
   (`components/shell/SearchField.tsx:9`), `SIGN_IN_PATH = "/sign-in"` (`lib/auth-redirect.ts:6-16`),
   the proxy matcher (`proxy.ts:47-49`), and font `url()`s in `app/globals.css:13,21`. A HUB
   sub-domain needs no code change. A sub-path of the HUB host needs all of these changed.
3. **It cannot be framed.** Every path sends `X-Frame-Options: DENY` (`web/next.config.ts:21`).
   Showing it inside a HUB iframe means replacing that header (for example with a CSP
   `frame-ancestors` naming the HUB origin). That is a security decision, not a setting.
4. **It signs in with Microsoft Entra, separately from the HUB.** The station accepts only Entra
   access tokens with station roles (`contract/openapi/station.yaml:790-798`,
   `station/api/src/core/config.ts:381-416`). The HUB code base snapshot of Aug 24, 2025 has no
   Entra, OIDC or MSAL in any HUB front end or in the backoffice API: HUB users sign in with email
   and password and get a HUB-signed JWT (`backoffice-node-api-main/middleware/check-auth.js:4-22`,
   `HelloChapter-master/src/services/auth.service.ts:9-15`). **Input needed:** whether the live
   HUB uses Entra today.
5. **Station tokens never reach the browser.** The station client is server-only; the access and
   refresh tokens live only in the encrypted Auth.js session cookie (`web/lib/station.ts:1-5`,
   `web/lib/token.ts:1-3`, `F10.md:21-22`).

HUB code base snapshot (read-only, `Product_Platform - The HUB/The HUB - code base/zip Aug 24 2025`
on the Chapter OneDrive):

| Folder                              | What it is                                                                      | Stack                                            |
| ----------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------ |
| `CMS-main` (`hc-cms` 0.1.0)         | A page and template website builder (grapesjs), not the HUB backoffice          | Create React App, React 18, MUI 5, Redux Toolkit |
| `HelloChapter-master`               | Early backoffice (files from Jan 2023): projects, users, roles                  | Create React App, React 18, MUI 5, Redux, axios  |
| `hellochapter-client-portal-master` | Client portal (Dec 2022)                                                        | Create React App, React 18, MUI 5                |
| `backoffice-node-api-main`          | Express API (`/api/user`, `/api/projects`, `/api/deals`, `/api/documents`, ...) | Express 4, mongoose 6, `@azure/storage-blob`     |
| `hc-subcontractors-main`            | Subcontractor portal (Mar 2025)                                                 | **Next.js 15.2.0**, React 19, MUI 6              |
| `hc-mcp-server-main`                | MCP server over the HelloChapter Mongo DB                                       | Express, mongoose 8                              |

The live HUB front-end source is not in the snapshot (**Input needed**). The HUB team already runs
a Next.js and React 19 app (`hc-subcontractors-main`), so a Next.js service is not new to them.

## 3. Integration options and the recommendation

### Option A (Recommendation): its own service on a HUB sub-domain, linked from the HUB

- Host `web/` as it is, on a host name under the HUB's domain (for example
  `capture.<hub domain>`; the name is **Input needed**). No code change.
- Add a "Capture review" item to the HUB navigation and a per-deal link (section 7).
- Keeps every guarantee and test: server-only station client, token never in the browser, 290
  vitest tests and 25 e2e tests in the last local runs, CI `web-e2e.yml`.
- Limits: a separate Microsoft sign-in (unless the HUB moves to Entra); not embeddable in a HUB
  iframe as built.

### Option A2: a sub-path of the HUB host (for example `<hub host>/capture`)

Needs code changes: `basePath` in `web/next.config.ts`, the 41 root-relative literals in 24 files
and `SearchField`'s `action="/"`, the font `url()`s in `app/globals.css` and `lib/config.ts`,
`SIGN_IN_PATH` and `isAuthRoute`, the proxy matcher, `SidebarNav.activeItem`, the Auth.js
callback URL, the e2e suite, and a reverse-proxy rule on the HUB host. Prefer A.

### Option B: port the pages into the HUB front end (not recommended now)

- The HUB front ends in the snapshot are client-only Create React App SPAs. The review screen is
  server components, server actions and route handlers (about 8,100 lines of TS/TSX in `app/`,
  `components/`, `lib/`; 8 `"use client"` files).
- The station refuses HUB JWTs. Porting means putting a station token in the browser (forbidden by
  F10, `F10.md:21-22`) or building a HUB-backend proxy to the station with an Entra on-behalf-of
  flow and a HUB-role to station-role mapping. Both are new work in the HUB and possibly the station.
- Signed-link handling (303 at click time, preview streamed server side) would be rebuilt in the
  HUB API. The tests do not carry over.
- Consider B only if the HUB moves to Entra and the team wants one app.

### Option C: iframe inside a HUB page

Not possible as built (`X-Frame-Options: DENY`, section 2). Needs a security decision first.

## 4. Hosting

- **Vercel (documented path).** Vercel Git integration on the Chapter Vercel team, project root
  directory `web`, production branch `main`, every other branch a preview deployment; variables in
  the Vercel project settings, never in the repo (`.github/BRANCH_PROTECTION.md:165-172`). There
  is no `vercel.json` and no GitHub workflow for the web. Read section 4.1 before connecting any
  Vercel project to the repo.
- **Self-hosted** (`next start`, Node 22, in a container or on a VM). The e2e harness sets
  `AUTH_TRUST_HOST: "true"` when it runs `next start` outside Vercel
  (`web/playwright.config.ts:55-68`). **Verify:** a self-hosted Auth.js app behind a proxy needs
  the same host setting.
- The web server must reach the station over HTTPS (server to server; no CORS).
- `next build` needs no secrets; settings are read at request time (`web/lib/config.ts:3-6`).
- Install from the repo root (`npm ci`); `web/` uses the `contract/ts` workspace.
- **Input needed:** the host name per environment, who owns the DNS, and whether Vercel or another
  host is used. The Vercel project must point at `eranfromchapter/chapter-lidar` (or its future
  `HelloChapter` location).

### 4.1 A stable training host on Vercel

The documented Vercel setup has one project: production branch `main`, every other branch a
preview deployment (`.github/BRANCH_PROTECTION.md:170-171`). That does not fit the owner's
timeline as it stands:

- A preview deployment's URL changes per deployment, but the Entra redirect URI
  (`https://<web host>/api/auth/callback/microsoft-entra-id`, section 6) needs a fixed host.
- Once that project is connected, every push to `main` deploys `web/` to production. `main` holds
  the v1 web today, and v2 is merged into `main` in phase 3, before the production web is allowed
  (README, "Branches, deploys and the web").

**Recommendation** (Vercel behaviour below is **Verify**):

- **Training (phase 2):** a separate Vercel project for training (name **Input needed**), root
  directory `web`, its production branch set to the branch training deploys from (`v2/main`, and
  `main` after the phase 3 merge), with the training domain attached and the training values of
  section 8 as its Production-scoped variables. Its "production" deployment is the training web
  on a fixed host name.
- **Production (phase 4 only):** create and connect the production Vercel project (production
  branch `main`, `BRANCH_PROTECTION.md:171`) and attach the production domain only when the
  phase 4 gate opens.
- Alternative for training: one Vercel project with a domain assigned to a dedicated Git branch
  (for example `training`) and Preview variables scoped to that branch. It works only if the
  production domain is not attached and the project's production deployments are not used
  before phase 4.

## 5. Environment variables

**Required at request time.** Missing or invalid: every page answers 503 "Capture review is not
configured" and serves no data; the log names the variable, never its value
(`web/lib/config.ts:11-18,96-118,157-179`, `web/.env.example:1-18`).

| Variable                         | Meaning and rule                                                                                                                                       |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `AUTH_SECRET`                    | Auth.js session encryption secret ("generate with `npx auth secret`", `.env.example:6`). One per environment.                                          |
| `AUTH_MICROSOFT_ENTRA_ID_ID`     | Client id of the review screen's Entra app registration ("Chapter Main" tenant)                                                                        |
| `AUTH_MICROSOFT_ENTRA_ID_SECRET` | Its client secret                                                                                                                                      |
| `AUTH_MICROSOFT_ENTRA_ID_ISSUER` | `https://login.microsoftonline.com/<tenant id>/v2.0`; https and tenant-specific (not `common`, `organizations`, `consumers`; `lib/config.ts:47,62-77`) |
| `STATION_API_URL`                | Station host **without** `/v1`; https (http only for `localhost`, `127.0.0.1`, `[::1]`); trailing `/` removed (`lib/config.ts:58-93,149`)              |
| `STATION_API_SCOPE`              | Delegated scope of the station API app registration, for example `api://<station app id>/<scope name>` (`.env.example:17-18`)                          |

**Optional links** (https only; unset or invalid hides the link and warns once naming the
variable; `web/lib/links.ts:1-15`, `.env.example:20-30`):

| Variable                 | Shows                                                                                                 | Example from the repo comments (example only)                       |
| ------------------------ | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `HUB_APP_URL`            | Topbar "Open the HUB"                                                                                 | `https://hub.hellochapter.com`                                      |
| `HUB_FILES_URL_TEMPLATE` | Station card "HUB › Files › Capture › r{n}"; must contain `{dealId}` and `{folder}`, both URL-encoded | `https://hub.hellochapter.com/deals/{dealId}/files?folder={folder}` |
| `INTAKE_GUIDE_URL`       | Sidebar "Intake guide" (opens a new tab)                                                              | —                                                                   |

The project page's "Open in the HUB" link comes from the **station** (`links.hub`, built from the
station's `HUB_WEB_DEAL_URL_TEMPLATE`), not from a web variable (`web/lib/links.ts:10-11`). The
station returns links only when its `REVIEW_BASE_URL` is set
(`station/api/src/routes/packages/store.ts:420-436`).

Test-only variables (`web/playwright.config.ts:14-20,55-68`): `E2E_WEB_PORT` (default 3916),
`E2E_STATION_PORT` (3917), `E2E_SKIP_BUILD`, `E2E_OUTPUT`, `E2E_SCREENSHOTS`.

## 6. Entra sign-in and roles

- Scopes requested: `openid profile email offline_access ${STATION_API_SCOPE}`, so the access token
  Entra returns is a station token (`web/auth.ts:44-47`).
- Session: JWT strategy, `maxAge` 12 hours (`web/auth.ts:29,38`). Refresh 5 minutes before expiry
  in the proxy (`web/lib/token.ts:27`), through the issuer's `token_endpoint` with
  `grant_type=refresh_token` (`web/lib/token.ts:153-203`).
- Cookies: `__Secure-authjs.session-token` on https (`web/lib/viewer.ts:34`), host-only.
- **Redirect URI** to register: `https://<web host>/api/auth/callback/microsoft-entra-id`
  (callback path asserted in `web/test/auth.test.ts:184`). One per environment.
- **Roles** are the station app roles (`web/lib/roles.ts:5`, `contract/openapi/station.yaml:790-798`):

| Role      | Who             | In the web                                               |
| --------- | --------------- | -------------------------------------------------------- |
| `capture` | field operators | status only                                              |
| `bim`     | BIM operators   | download, preview plans, read and log modeling decisions |
| `admin`   | administrators  | as `bim`                                                 |
| none      | —               | "No station role" page (`web/lib/roles.ts:26-38`)        |

- Roles are assigned on the **station** app registration (`infra/README.md:158-160`). The web app
  registration needs a delegated permission to the station scope.
- **Verify:** the station accepts only the v2.0 issuer by default
  (`station/api/src/core/config.ts:382-383`), so the station app registration must issue v2.0
  access tokens (`requestedAccessTokenVersion: 2` in the Entra manifest; the setting name is not in
  the repo).

## 7. HUB navigation links

**To add in the HUB (HUB team, link-only work):**

- Main navigation item "Capture review" → the web origin. In the 2023 snapshot this menu is
  `HelloChapter-master/src/components/Menu/sidebar.tsx:15-38` (items are
  `<ListItemButton href=… component="a">`). The live file is **Input needed**.
- Deal or project page link "Capture review" → `<web origin>/projects/<encodeURIComponent(dealId)>`
  (route `web/app/(review)/projects/[dealId]/page.tsx`, path built at line 267). `dealId` is the
  HUB **sales** deal id, not the id of the HUB all-projects listing
  (`station/api/src/hub/mapping.ts:4-7`).

**Already built (needs only values):**

- HUB Files tab: the spatial report lists every package file not uploaded to the HUB with a link
  `${REVIEW_BASE_URL}/packages/<packageId>?file=<path>` (`station/hub/src/plan.ts:129-133`); the
  report's QR code and "Review link" open the package (`station/hub/src/report/input.ts:66-67`).
- Links back to the HUB from the review screen: `HUB_APP_URL`, `HUB_FILES_URL_TEMPLATE` (web),
  `HUB_WEB_DEAL_URL_TEMPLATE` (station).

## 8. Training connection (now, phase 2)

The web needs a running station. In Azure the station always runs `NODE_ENV=production` and
`HUB_MODE=live`, staging included, and requires `HUB_BASE_URL` and `HUB_SERVICE_CREDENTIAL`
(`infra/modules/containerapps.bicep:171-203`, `station/api/src/core/config.ts:431-442`). So
"connect to HUB training" means a station connected to the HUB training API, plus the web pointed
at that station.

Steps:

1. Decide which station serves training (**Input needed**): the existing `staging` environment of
   `infra/`, or a new environment. `infra/` knows only `staging` and `production`
   (`infra/params/`). The word "training" appears nowhere in the repo. Using `staging` needs the
   production Bicep applied first (shared registry;
   [04, section 9.1](04-station-and-deploy.md#91-across-the-owners-phases)).
2. Get the HUB training API details confirmed by the HUB team and update the mapping if needed
   ([04, section 5](04-station-and-deploy.md#5-hub-connection)). The HUB training deals used for
   tests must have a confirmed address (the HUB's confirmed-address flag, only `true` counts):
   the phone lists only those, and a package sealed into any other deal never gets a verdict.
3. Deploy the station for training from `v2/main` ([04](04-station-and-deploy.md), sections 8.3
   and 9), with the settings in the station table below.
4. Create the training Entra registration for the web and assign station roles to training users.
5. Deploy the web on the fixed training host with the web settings below, in its own Vercel
   project (section 4.1).
6. Add the training "Capture review" link in the HUB training navigation (optional for the gate).
7. Run the training checks in section 10.

**Web settings for training** (Vercel project or host environment):

| Variable                         | Training value (**Input needed** unless stated)                                                    |
| -------------------------------- | -------------------------------------------------------------------------------------------------- |
| `AUTH_SECRET`                    | a new random secret for training (`npx auth secret`)                                               |
| `AUTH_MICROSOFT_ENTRA_ID_ID`     | client id of the training review-screen app registration                                           |
| `AUTH_MICROSOFT_ENTRA_ID_SECRET` | its client secret, stored only in the host's settings                                              |
| `AUTH_MICROSOFT_ENTRA_ID_ISSUER` | `https://login.microsoftonline.com/<Chapter Main tenant id>/v2.0`                                  |
| `STATION_API_URL`                | https host of the training station, without `/v1` (for staging: the `ca-capture-api-staging` FQDN) |
| `STATION_API_SCOPE`              | `api://<station app id>/<scope name>` of the station registration that station validates           |
| `HUB_APP_URL`                    | HUB training front-end URL                                                                         |
| `HUB_FILES_URL_TEMPLATE`         | HUB training deal Files URL with `{dealId}` and `{folder}`                                         |
| `INTAKE_GUIDE_URL`               | File Intake Guide URL                                                                              |
| `AUTH_TRUST_HOST`                | only if not on Vercel (section 4)                                                                  |

**Station settings that tie it to the training web and HUB training:**

| Variable (station)                                                     | Training value (**Input needed**)                                                | Source                                                                           |
| ---------------------------------------------------------------------- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `REVIEW_BASE_URL` (API **and** worker)                                 | training web origin. The worker refuses to start without it.                     | `station/worker/src/config.ts:296-302`, `station/api/src/core/config.ts:391-393` |
| `HUB_WEB_DEAL_URL_TEMPLATE` (API)                                      | HUB training deal page URL with `{dealId}` (https)                               | `station/api/src/core/config.ts:392-393,449-459`                                 |
| `HUB_MODE`                                                             | `live` (set by infra)                                                            | `infra/modules/containerapps.bicep:196-199`                                      |
| `HUB_BASE_URL` (Bicep `hubBaseUrl`, deploy env `CAPTURE_HUB_BASE_URL`) | HUB training REST API base URL (https)                                           | `infra/README.md:82,128`                                                         |
| `HUB_SERVICE_CREDENTIAL` (Key Vault secret `hub-service-credential`)   | HUB training service credential, set by an admin in Key Vault, never in the repo | `infra/README.md:87,175-184`                                                     |
| `ENTRA_TENANT_ID`, `ENTRA_AUDIENCE` (`CAPTURE_ENTRA_AUDIENCE`)         | Chapter Main tenant; station app registration client id and/or App ID URI        | `infra/README.md:71-74,127`                                                      |

**Gap: `infra/` sets neither `REVIEW_BASE_URL` nor `HUB_WEB_DEAL_URL_TEMPLATE`**
(`infra/modules/containerapps.bicep:137-221`; no match for `REVIEW_BASE_URL` under `infra/`). As
deployed by `infra/`, the worker would exit at start. Add them to the Bicep app settings (or set
them by hand) once the training web host is known. Recorded as an open item in `plan.md:497-498`.

## 9. Production go-live gate (phase 4)

Start only when the phase 3 gate has passed: the PM app update with space capture is approved and
one real visit has gone through end to end in production.

- Same variable names with production values: production web host and Entra redirect URI,
  production station (`ca-capture-api-production`) host and scope, station `REVIEW_BASE_URL` = the
  production web origin, `HUB_WEB_DEAL_URL_TEMPLATE`, `HUB_BASE_URL` and `HUB_SERVICE_CREDENTIAL`
  of the production HUB.
- The production station's worker needs `REVIEW_BASE_URL` already in phase 3. Choose the
  production web host name then; links in reports made before this phase open only once it is live.
- v2 is already in `main` by now: it is merged in phase 3, because `deploy-station.yml` deploys
  the production station only from `main` (`.github/workflows/deploy-station.yml:83-86`). A push
  to `main` also deploys the station to staging (`deploy-station.yml:19-21`).
- Only now create and connect the production Vercel project (root `web`, production branch
  `main`, `.github/BRANCH_PROTECTION.md:165-172`) and attach the production domain (section 4.1).
  Its first production deployment is the go-live.
- Add the production "Capture review" link to the HUB navigation and the deal page.

## 10. Acceptance checklist

**Training (gate of phase 2):**

- [ ] `https://<training web host>/` without a session redirects to `/sign-in`; "Sign in with
      Microsoft" completes and returns to the page asked for.
- [ ] A user with no station role sees "No station role"; a `capture` user sees status only; a
      `bim` user sees downloads and the decision log.
- [ ] Before any package exists, the Projects page is empty: it lists only projects with at least
      one package (section 1). The HUB training deals with a confirmed address show on the
      phone's New capture (station `GET /v1/projects` against the HUB training API).
- [ ] A test package uploaded to the training station (from a Debug build of the standalone app or
      the PM app branch, configured for the training station, sealed into a HUB training deal with
      a confirmed address) reaches a verdict; its project now appears on the Projects page; the
      package page shows the verdict, findings and files.
- [ ] Spatial report download works (303 to a short-lived link); plan PNG preview loads; a file
      download works and the link expires.
- [ ] In the HUB training deal's Files tab: the spatial report and `manifest.json` under
      `Capture/<visitId>/r<revision>`, and each capture's plan files (DXF, rooms CSV, plan sheet
      PDF, plan PNG) under `Capture/<areaKey>/<captureId>/r<revision>`
      (`station/hub/src/plan.ts:3-6,114-122`).
- [ ] "Open the HUB", "Open in the HUB" and the Files link open the HUB training pages (if the
      variables are set).
- [ ] Removing one required variable shows the 503 "not configured" page (then restore it).
- [ ] No Google font request; the HUB wordmark and Inter load from `/brand/`.

**Production (gate of phase 4):**

- [ ] The same checks on the production host against the production station and HUB.
- [ ] HUB production navigation and deal pages link to the review screen.
- [ ] `robots` stays `noindex, nofollow` (`web/app/layout.tsx:9`); security headers present
      (`web/next.config.ts:3-30`).
