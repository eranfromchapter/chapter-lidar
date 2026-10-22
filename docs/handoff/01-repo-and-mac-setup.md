# 01 · Repo and Mac setup

How to get the code, which tools to install on the Mac, and how to build and test every part.
All commands run from the repo root unless a step says otherwise.

## 1. Get the code

```sh
git clone https://github.com/eranfromchapter/chapter-lidar.git
cd chapter-lidar
git switch v2/main
git log --oneline -1
```

- Expect `add2d74` or later at the top. If you see `2ca19b0`, the owner has not pushed the newer
  commits yet (**Input needed**, see [README](README.md#repo-and-branch)).
- `main` is the v1 build. Do not start from it.
- The build agents also left local track branches (`v2/t0-contract` to `v2/t10-app-shell` and
  their `-fix` branches). They are merged into `v2/main` and are not on GitHub.

## 2. Repo map

| Folder                                                                              | What it is                                                                                                                                                                                       |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `contract/`                                                                         | Shared contract: `schema/*.schema.json`, `openapi/station.yaml` (1.1.0), `ts/` (npm `@chapter/capture-contract` 1.1.0), `swift/` (Swift package `CaptureContract`), `examples/`, `test-vectors/` |
| `ios/project.yml`                                                                   | XcodeGen spec of the standalone app (target `App`, UI tests `AppUITests`, schemes `App` and `ChapterUISnapshots`)                                                                                |
| `ios/App/`                                                                          | App target sources (`Sources/App`), `AppCore` (Foundation-only Swift package), `Config/*.xcconfig`, `Resources/` (Info.plist, entitlements), `UITests/`                                          |
| `ios/Packages/`                                                                     | Swift packages: `ChapterUI`, `CaptureCore`, `FieldKit`, `PlanExport`, `MeshExport`, `PackageKit`, `StationClient`                                                                                |
| `station/api`, `station/checks`, `station/hub`, `station/worker`, `station/dev-idp` | Station backend (npm workspaces `@chapter/station-*`)                                                                                                                                            |
| `station/db/migrations/`                                                            | Postgres 16 migrations `0001` to `0011`                                                                                                                                                          |
| `web/`                                                                              | Web review app (npm workspace `@chapter/web`, Next.js)                                                                                                                                           |
| `infra/`                                                                            | Azure Bicep (`main.bicep`, `modules/`, `params/staging.bicepparam`, `params/production.bicepparam`)                                                                                              |
| `fixtures/`                                                                         | Test fixtures and their generator (npm workspace `@chapter/fixtures`)                                                                                                                            |
| `tools/`                                                                            | `brand/` (logo and font generator), `plan-render/` (macOS Floorplan renderer), `scan-browser/` (field-test file browser)                                                                         |
| `scripts/`                                                                          | `swift-test.sh`, `bootstrap-swift.sh`, `ensure-simulator.sh`, `verify-exports.sh`, `verify/`, `backfill-review-read-model.ts`, `workspaces.mjs`, `wait-workflow.sh`                              |
| `.github/workflows/`                                                                | `ci.yml`, `ios.yml`, `web-e2e.yml`, `testflight.yml`, `deploy-station.yml`                                                                                                                       |
| `docs/`                                                                             | Design (`waves/design/DESIGN.md`), feature specs (`waves/specs/F1.md`-`F13.md`), architecture, QA notes, this kit                                                                                |

npm workspaces: `contract/ts`, `fixtures/generator`, `station/*`, `web` (`package.json:11-16`).

## 3. Mac tools

| Tool                  | Version                                                                                                | Needed for                                                                | Source                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Xcode                 | see "Xcode version" below                                                                              | iOS packages, the app, simulator tests                                    | `.github/workflows/ios.yml:42-43`, `testflight.yml:64-65`                              |
| iOS deployment target | 17.0                                                                                                   | every Swift package and the app                                           | `ios/project.yml:12-13,21`; each `Package.swift` declares `.iOS(.v17)`, `.macOS(.v14)` |
| Swift tools version   | 6.0 (`// swift-tools-version: 6.0` in all 8 manifests)                                                 | the Swift packages                                                        | line 1 of each `Package.swift`                                                         |
| XcodeGen              | 2.46.0, SHA-256 `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`                     | generating `ios/ChapterCapture.xcodeproj`                                 | `.github/workflows/ios.yml:50-51`                                                      |
| Simulator             | iPhone 17 Pro. UI tests on `OS=latest`; snapshot tests on iOS **26.0** (references are recorded there) | simulator tests                                                           | `.github/workflows/ios.yml:44-49`, `ios/Packages/ChapterUI/README.md:17-18`            |
| MSAL (Swift package)  | `exactVersion: 2.16.0`, `https://github.com/AzureAD/microsoft-authentication-library-for-objc`         | Entra sign-in in the app                                                  | `ios/project.yml:43-45`                                                                |
| Node.js               | 22 (`.nvmrc`); engines `>=22.13.0`                                                                     | station, web, contract, fixtures, root scripts                            | `.nvmrc`, `package.json:7-10`                                                          |
| npm                   | `>=10`                                                                                                 | same                                                                      | `package.json:9`                                                                       |
| Docker                | not pinned; Docker with `docker compose` is required                                                   | local station, station API tests, export validators, infra compile checks | `station/api/scripts/local-up.sh:15-25`                                                |
| Playwright Chromium   | `@playwright/test` 1.64.0                                                                              | web end-to-end tests                                                      | `web/package.json:28`                                                                  |
| poppler (`pdftoppm`)  | CI uses Ubuntu `poppler-utils`; snapshots were recorded with poppler 26.04.0 on macOS                  | station spatial report visual tests (they skip locally without it)        | `.github/workflows/ci.yml:66-73`, `station/hub/test/report-visual/visual.test.ts:1-16` |
| Python 3 + fontTools  | fontTools 4.62.1, Inter 3.019                                                                          | only to regenerate brand assets                                           | `tools/brand/generate_plan_brand.py:1-25`                                              |
| Azure CLI             | `mcr.microsoft.com/azure-cli:2.67.0` (run in Docker)                                                   | infra checks and deploys                                                  | `infra/README.md:269-294`                                                              |

Pinned Docker images used by the scripts: `postgres:16.15-bookworm`,
`mcr.microsoft.com/azure-storage/azurite:3.35.0`, `node:22.23.3-bookworm-slim`
(`station/api/docker-compose.yml`), `python:3.12.15-slim-bookworm`,
`debian:bookworm-20261005-slim`, `pdal/pdal:2.9.2` (`scripts/verify-exports.sh:17-22`).

### Xcode version (read this first)

- CI pins Xcode **26.3** on the `macos-15` runner (`.github/workflows/ios.yml:42-43`). The
  TestFlight workflow pins the same version; its comment says "App Store Connect requires an Xcode
  26 SDK build" (`.github/workflows/testflight.yml:64-65`).
- The App target **does not compile on Xcode 26.3.**
  `ios/App/Sources/App/Views/ModelStyle.swift` lines 2265, 2331 and 2495 fail with "the compiler
  is unable to type-check this expression in reasonable time" (CI run `39707269821`, commit
  `2ca19b0`). The package jobs build; the App job fails.
- Every local v2 build used **Xcode 27.2 beta (27B5038j)** on the owner's Mac (macOS 27.0), and
  the App compiled there. The owner's Mac also has Xcode 27.1 (27A9275); the App was not built
  with it.
- **Verify:** App Store builds are normally made with a release (non-beta) Xcode.
- **First task for the iOS developer:** pick the release Xcode the PM app will ship with, make
  `ModelStyle.swift` compile on it (split the three expressions), and move the CI pins in
  `ios.yml` and `testflight.yml` to it. Moving the snapshot simulator pin means recording the
  phone snapshots again (`TEST_RUNNER_RECORD_SNAPSHOTS=1`, `ios/Packages/ChapterUI/README.md:23-34`).
- Use `xcode-select` or `DEVELOPER_DIR` to choose the Xcode, as CI does
  (`.github/workflows/ios.yml:43`).

## 4. Install and root checks

```sh
npm ci                  # all npm workspaces; builds contract/ts through its prepare script
npm run format:check    # prettier --check .
npm run lint            # eslint + secretlint over the repo
npm run typecheck       # every workspace
npm test                # every workspace's tests, then scripts/swift-test.sh
```

Sources: `package.json:17-24`, `.github/workflows/ci.yml:40-79`, `contract/ts/package.json`
(`"prepare": "npm run build"`). `npm test` needs Docker for the station API tests (section 6).

`ci.yml` also runs `scripts/bootstrap-swift.sh` (installs Swift 6.4.1 on Linux when `swift` is
missing; `scripts/bootstrap-swift.sh:22`) and installs `poppler-utils` before `npm test`. On a Mac,
Xcode provides Swift.

## 5. Contract

```sh
npm test --workspace contract/ts                          # TypeScript types and schema tests
npm run generate -w @chapter/capture-contract             # regenerate contract/ts/src/generated/** from contract/schema/**
swift test --package-path contract/swift                  # Swift types
```

- The generated TS files are committed. A schema change without regeneration fails
  `test/generated.test.ts` (`contract/ts/scripts/generate.ts:1-8`).
- Versions: see [04, section 2](04-station-and-deploy.md#2-contract-versions).

## 6. Station (Docker required)

Docker is required. `local-up.sh` exits when `docker` is missing
(`station/api/scripts/local-up.sh:15-18`). The station API tests start throwaway Postgres and
Azurite containers and throw when Docker is unavailable, unless you pass
`STATION_TEST_DATABASE_URL` / `STATION_TEST_STORAGE_CONNECTION_STRING`
(`station/api/test/uploads/support/infra.ts:1-10`).

```sh
station/api/scripts/local-up.sh          # or: npm run local:up --workspace station/api
curl http://localhost:8080/health
station/api/scripts/local-down.sh        # stops the stack and DELETES its data volumes

npm test --workspace station/api                  # needs Docker
npm run test:db --workspace station/api           # DB tests on a migrated throwaway database
npm run migrate:check --workspace station/api     # applies every migration twice; rejects down migrations
npm test -w @chapter/station-checks
npm test -w @chapter/station-hub                  # report visual tests skip locally without pdftoppm
npm test -w @chapter/station-worker
npm run test:local --workspace station/dev-idp    # needs the stack up
npm run test:e2e --workspace station/worker       # needs the stack up; runs the worker in process with a fake HUB
```

Sources: `station/api/package.json` scripts, `station/db/README.md:9-15`,
`station/worker/test/e2e/pipeline.e2e.ts:1-8`. Record report snapshots again with
`UPDATE_REPORT_SNAPSHOTS=1 npm test -w @chapter/station-hub`
(`station/hub/test/report-visual/visual.test.ts:1-16`).

### 6.1 The local stack

`station/api/docker-compose.yml`, compose project `chapter-station-local`:

| Service    | Image                                                                              | Host port                                  |
| ---------- | ---------------------------------------------------------------------------------- | ------------------------------------------ |
| `postgres` | `postgres:16.15-bookworm` (user and database `station`, trust auth)                | `127.0.0.1:55432` (`STATION_PG_PORT`)      |
| `azurite`  | `mcr.microsoft.com/azure-storage/azurite:3.35.0` (blob only)                       | `127.0.0.1:10000` (`STATION_AZURITE_PORT`) |
| `api`      | built from `station/api/Dockerfile` (context: repo root), `env_file: .env.example` | `8080` (`STATION_API_PORT`)                |
| `dev-idp`  | `node:22.23.3-bookworm-slim`, runs `station/dev-idp/src/server.mjs`                | `127.0.0.1:8090` (`STATION_DEV_IDP_PORT`)  |

- Settings come from `station/api/.env.example` (no secrets; it holds Azurite's published
  development account key). The local API runs `HUB_MODE=fake`, `MIGRATE_ON_START=true` and
  `REVIEW_BASE_URL=http://localhost:3000` (`station/api/.env.example:15-46`).
- The fake HUB returns deals `fixture-deal-0001` and `fixture-deal-0002` with confirmed
  addresses. `fixture-deal-0003` has no confirmed address and is never returned
  (`station/api/src/hub/fake.ts:7-40`).
- Test tokens come from `dev-idp`: `POST /token` with `{"roles": ["capture"|"bim"|"admin", ...]}`
  returns `{"access_token", "token_type": "Bearer", "expires_in"}`, valid at most 1 hour
  (`station/dev-idp/src/server.mjs:9-17`). It refuses `NODE_ENV=production`.
- The compose file has **no worker service**. The worker e2e test runs the worker in process.
  Running the worker as a separate local process is not documented; it needs at least
  `DATABASE_URL`, a storage connection string and `REVIEW_BASE_URL`
  ([04, section 4.2](04-station-and-deploy.md#42-worker)).
- Behind a TLS-inspecting proxy, `local-up.sh` passes `NODE_EXTRA_CA_CERTS` to the image build as
  `STATION_BUILD_CA_FILE` (`station/api/scripts/local-up.sh:20-23`).

### 6.2 What cannot talk to the local station

- **A real iPhone.** The app allows plain `http` only for `localhost` and `127.0.0.1`
  (`ios/Packages/StationClient/Sources/StationClient/StationClient.swift:28-31`). A phone cannot
  reach the Mac's station over HTTP. Device tests against a real station need an HTTPS station.
- **The live app sign-in.** The app signs in with MSAL against Entra (section 7 and
  [02, section 10](02-ios-into-pm-app.md#10-sign-in-and-station-settings)). The local station
  accepts only `dev-idp` tokens unless you point its `ENTRA_TENANT_ID` and `ENTRA_AUDIENCE` at a
  real station app registration and unset `ENTRA_ISSUER` and `ENTRA_JWKS_URL`
  (`station/api/.env.example:19-27`).
- **The web sign-in.** The web requires an `https` Entra issuer that names a tenant, so it cannot
  use `dev-idp` (`web/lib/config.ts:47,62-77`). See section 8.

PackageKit's end-to-end upload test does reach the local station with a `dev-idp` token:

```sh
station/api/scripts/local-up.sh
STATION_URL=http://localhost:8080 swift test --package-path ios/Packages/PackageKit --filter E2EUploadTests
```

(`ios/Packages/PackageKit/Tests/PackageKitTests/E2EUploadTests.swift:7-15`)

## 7. iOS

### 7.1 Generate, build and test the standalone app

```sh
xcodegen generate --spec ios/project.yml        # writes ios/ChapterCapture.xcodeproj (do not commit it)
xcodebuild build -project ios/ChapterCapture.xcodeproj -scheme App \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project ios/ChapterCapture.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

(`ios/App/README.md:61-67`)

- The `App` scheme builds `App`. Its test action runs the UI tests `ReplayFlowUITests`, which
  replay the `box-room` fixture through every screen to the verdict with in-process stubs
  (`ios/App/README.md:129-150`).
- Run and Test use Debug; Archive uses Release (`ios/project.yml:187-201`).
- A build with placeholder settings shows "App is not configured" and sends nothing
  (`ios/App/README.md:88-91`). That is expected without `Local.xcconfig`.

### 7.2 Package tests

Pure-Swift tests on macOS (or Linux):

```sh
swift test --package-path ios/App/AppCore
swift build -c release --package-path ios/App/AppCore   # Release: no UI-test stubs compiled
bash scripts/swift-test.sh                              # every package; skips any with a root .apple-only marker
```

(`ios/App/README.md:69-74`, `scripts/swift-test.sh:1-14`)

On the simulator, as CI does (`.github/workflows/ios.yml:117-166`): in each package folder, use
scheme `<Name>-Package` when Xcode generates it, otherwise `<Name>`:

```sh
cd ios/Packages/ChapterUI
xcodebuild build -scheme ChapterUI-Package -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme ChapterUI-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0'
```

App-hosted snapshot tests (from the repo root):

```sh
xcodegen generate --spec ios/project.yml
xcodebuild test -project ios/ChapterCapture.xcodeproj -scheme ChapterUISnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0'
```

- Record snapshots again with `TEST_RUNNER_RECORD_SNAPSHOTS=1` in front of `xcodebuild test`
  (`ios/Packages/ChapterUI/README.md:23-34`).
- `scripts/ensure-simulator.sh "iPhone 17 Pro"` waits for the simulator, or creates it on the
  newest iOS runtime (`scripts/ensure-simulator.sh:1-11`).
- CI packages: `CaptureContract` (`contract/swift`), `ChapterUI`, `CaptureCore`, `PlanExport`,
  `MeshExport`, `FieldKit`, `PackageKit`, `StationClient` (`.github/workflows/ios.yml:62-82`).

### 7.3 Field-test build for a real iPhone

A Debug build with `CHAPTER_FIELD_TEST = YES` runs the real scan, camera and compass with the
in-process stub sign-in and station. A whole visit runs on the phone and nothing leaves it
(`ios/App/README.md:100-127`).

1. Create `ios/App/Config/Local.xcconfig` (git-ignored, never commit it):

   ```
   CHAPTER_FIELD_TEST = YES
   DEVELOPMENT_TEAM = <your team id>
   ```

2. Build:

   ```sh
   xcodegen generate --spec ios/project.yml
   xcodebuild build -project ios/ChapterCapture.xcodeproj -scheme App -configuration Debug \
     -destination generic/platform=iOS -derivedDataPath build/dd-v2 \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration
   /usr/libexec/PlistBuddy -c 'Print :ChapterFieldTest' \
     build/dd-v2/Build/Products/Debug-iphoneos/ChapterCapture.app/Info.plist   # YES
   ```

3. Install `build/dd-v2/Build/Products/Debug-iphoneos/ChapterCapture.app` with Xcode or
   `xcrun devicectl device install app` (`ios/App/README.md:126-127`). **Verify:** the full form
   is `xcrun devicectl device install app --device <device id> <path to .app>`.
4. Copy the sealed field-test packages off the phone
   (`ios/App/Sources/App/Debug/FieldTestEnvironment.swift:9-12`):

   ```sh
   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
     --domain-identifier com.hellochapter.capture --source Library/Application\ Support/FieldTestVisits \
     --destination <folder>
   ```

Notes:

- A personal Apple team gives a provisioning profile that expires after 7 days. The owner's
  field-test build of Oct 18 expires on Oct 25, 2026 (`embedded.mobileprovision` of that build).
  Use Chapter's Apple Developer team for anything longer-lived (**Input needed**).
- Release ignores the flag and excludes the `UITest*` and `FieldTest*` sources
  (`ios/project.yml:72-74`, `ios/App/Config/Release.xcconfig:3-4`).
- The scan browser shows the files a field-test build wrote and draws each scan's Floorplan with
  the current code: `npm run scan-browser` (data folder `~/ChapterCaptureScans`, port 4321;
  `tools/scan-browser/README.md:24-30`). It builds `tools/plan-render`, a macOS-only Swift tool.

### 7.4 Running the app against a real station

Put the four settings in `ios/App/Config/Local.xcconfig` (identifiers, not secrets):

```
CHAPTER_ENTRA_CLIENT_ID = <uuid>
CHAPTER_ENTRA_TENANT_ID = <uuid>
CHAPTER_STATION_API_SCOPE = api:/$()/<station app id>/<scope>
CHAPTER_STATION_URL = https:/$()/<station host>
```

- In xcconfig `//` starts a comment, so a URL is written `https:/$()/host`
  (`ios/App/Config/Base.xcconfig:4-5`). The `api://` scope has `//` too, so the same rule
  applies to it (derived from that rule; the repo shows it only for the URL).
- Validation rules are in [02, section 10](02-ios-into-pm-app.md#10-sign-in-and-station-settings).
- The Entra registration needs the redirect URI `msauth.com.hellochapter.capture://auth` for the
  standalone app (`ios/App/README.md:93`).
- **Input needed:** the training and production station URLs, the station API scope and an Entra
  client id.

## 8. Web

```sh
npm run dev --workspace web          # next dev
npm run build --workspace web        # next build (needs no secrets)
npm run start --workspace web        # next start
npm run typecheck --workspace web
npm test --workspace web             # vitest
npx --workspace web playwright install --with-deps chromium
npm run e2e --workspace web          # playwright: next build + next start on 3916 against web/e2e/mock-station.ts on 3917
```

Sources: `web/package.json:10-17`, `.github/workflows/web-e2e.yml:48-52`,
`web/playwright.config.ts:1-71`.

- `web/` is not standalone. Install from the repo root (`npm ci`) so the
  `@chapter/capture-contract` workspace resolves.
- `npm run e2e` needs no secrets and no Entra: it uses test settings and a mock station
  (`web/test/support/tokens.ts:1-15`). This is the quickest way to see every page.
- `npm run dev` with real data needs the six required variables in `web/.env.local` (never
  committed; names in `web/.env.example:1-18`) and a real Entra app registration. The Entra
  callback path is `/api/auth/callback/microsoft-entra-id` (`web/test/auth.test.ts:184`).
- Variables and their rules: [03, section 5](03-web-into-hub.md#5-environment-variables).

## 9. Tools and validators

```sh
scripts/verify-exports.sh <dxf|pdf|preview|gltf|las> <dir>    # Docker for dxf, pdf, preview, las
scripts/verify/plan-sheet-snapshot.sh [--record] [<test-output dir>]   # after swift test --package-path ios/Packages/PlanExport
node station/hub/scripts/generate-brand-assets.mjs --check     # station report brand assets match the phone's
python3 -I tools/brand/generate_plan_brand.py --logo tools/brand/chapter-logo.svg \
  --inter "<path to>/Inter-VariableFont_slnt,wght.ttf" --check
```

Sources: `scripts/verify-exports.sh:1-13`, `scripts/verify/plan-sheet-snapshot.sh:1-23` (the
reference render runs in Docker; without Docker it uses the local `pdftoppm` and stand-in fonts),
`station/hub/scripts/generate-brand-assets.mjs:1-27`, `ios/Packages/ChapterUI/README.md:55-60`.
Do not edit the generated fonts, logo data or `ChapterBrandAssets.swift` by hand
(`ios/Packages/ChapterUI/README.md:48-60`).

## 10. Infra checks (Docker)

```sh
docker run --rm -v $PWD:/w -w /w mcr.microsoft.com/azure-cli:2.67.0 az bicep build --file infra/main.bicep
node infra/test/storage-policy.mjs
npx --no-install secretlint --secretlintrc scripts/secretlint/secretlintrc.json '.github/**' 'infra/**'
```

(`infra/README.md:267-294`; the parameter-file compile check is there too.)
