# 05 · Status and open items

State on Oct 22, 2026, at `v2/main` commit `add2d74`. Sources: `git`, `gh run list`, the CI logs,
the build logs of the local runs on the owner's Mac, `docs/waves/design/DESIGN.md`,
`docs/waves/specs/F*.md`, `plan.md`.

**One line:** v2 is built, integrated and pushed (`v2/main` at `add2d74`). On GitHub, `ci` (Node,
Swift on Linux, export validators in Docker, report snapshots on Linux) and `web-e2e` are green;
`ios` is red because the App compiles only with the Xcode 27.2 beta and the runner has no iOS 26.0
simulator for the package tests. The integrated worker e2e last timed out, the compass device
tests never ran, nothing is deployed, and the HUB, Apple, Entra, Azure and PM app inputs are still
to come.

## 1. Branches

| Branch                  | Head      | On GitHub                              | What it is                                                           |
| ----------------------- | --------- | -------------------------------------- | -------------------------------------------------------------------- |
| `main`                  | `3e22c19` | yes                                    | v1 build                                                             |
| `fix/ios-ci-first-push` | `80182ea` | yes, **PR #1** to `main`, open         | iOS CI fixes, field-test mode; already inside `v2/main` (superseded) |
| `feat/floorplan-report` | `05f16e8` | yes                                    | floorplan-report phases, Chapter brand, rename rooms; base of v2     |
| `v2/main`               | `add2d74` | yes (pushed Oct 22, 2026, 09:46 -0600) | Design v2 integration branch: the code to hand off                   |
| `v2/handoff`            | this kit  | no                                     | `v2/main` plus `docs/handoff/`                                       |

The push of `add2d74` brought the 16 commits after `2ca19b0` to GitHub: the T5 plan sheet merge
(`cb71f62`), the T4 spatial report merge (`dd635d1`), parity fixes (`cc5a056`, `03cdeef`), docs
(`f11c972`, `f53c1bc`, `5527e29`) and report fixes (`9c7d45d`, `add2d74`).

## 2. What is built (v2)

Source of truth: `docs/waves/design/DESIGN.md` section "Design v2 (Oct 21, 2026)"
(`DESIGN.md:50-156`), specs `docs/waves/specs/F1.md`-`F13.md`, `ios/App/README.md`.

- **Contract (F1) 1.1:** manifest 1.1.0 retires the phone's `spatial_report_pdf`; photos record
  `photo.directionSource`; capture record 1.1.0 adds `heading`, `headingAccuracy`,
  `headingSource`, `headingRecordedAt` or `headingIssue`; OpenAPI 1.1.0 adds review routes,
  carry-over, next-revision notice and `GET /packages/{packageId}/spatial-report`
  (`F1.md:35-41`).
- **Phone capture (F2):** Captures home, New capture, What are you scanning? (with Compass), Live
  scan with compass chip, Capture overview; `CompassService`; the compass never blocks; no
  location stored (`F2.md:38-49`).
- **Plan exports (F3):** plan sheet on Tabloid 11 x 17 (scale ladder 1:50 → 1:100 → 1:200, 1:500
  exterior, quarter turn per rung, never fitted); `exportAll` writes DXF, CSV, plan sheet, PNG,
  SVG (`F3.md:30-49`).
- **Photos and field controls (F5):** "Looking toward" from the compass; feet and inches fields;
  Before you leave; rename rooms; read-only after sealing; `ChecklistPolicy.standard`
  (`F5.md:35-44`).
- **Package, upload, app shell (F6):** one `NavigationStack`; Package ready, Package status,
  Verdict received, Revision n; revision n+1 uploads only added and changed files; field-test mode
  (`F6.md:37-49`).
- **Checks (F8):** 13 rules including `orientation.compass`, evaluator 1.1.0.
- **Worker and HUB publish (F9):** spatial report on US Letter landscape (cover, plan per floor,
  room schedule, checks, room pages, photo pages with EXIF/GPS stripped, package record pages),
  stored in `reports`, published to the HUB (`F9.md:37-47`).
- **Web review (F10):** HUB design system; projects, project and package pages; plan sheet and
  spatial report downloads (`F10.md:29-39`).
- The plan sheet and the spatial report print the same room names, areas, number formats, fill
  class, compass state and date; checked by PlanExport `ReportParityGoldenTests` and the station's
  `plan-sheet-parity.test.ts` and `metrics-parity.test.ts` (`DESIGN.md:137-148`).

## 3. Test results (last known)

### 3.1 GitHub Actions

| Workflow       | Branch, commit                    | Date (UTC)   | Result                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------- | --------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ci             | `v2/main` `add2d74`               | Oct 22 15:46 | **success** (run `39807980144`): format, lint, typecheck; Node tests, 0 failed (contract 151, fixtures 119, station-api 514, station-checks 298, dev-idp 51, station-hub 219 including the 19 spatial report snapshot pages with pdftoppm 24.02.0, station-worker 23, web 290); Linux `swift test`, all 9 packages passed (AppCore 184 tests, 0 failures); "Verify export files" in Docker: dxf 5, pdf 26, preview 70, gltf 13, las 11 files, all passed. |
| ios            | `v2/main` `add2d74`               | Oct 22 15:46 | **failure** (run `39807980031`): App job, `ModelStyle.swift:2265, 2331, 2495` type-check timeouts on Xcode 26.3. Every package job builds, then its tests stop: no iPhone 17 Pro simulator with iOS 26.0 on the runner (it has 26.0.1, 26.1, 26.2).                                                                                                                                                                                                       |
| web-e2e        | `v2/main` `add2d74`               | Oct 22 15:46 | success (run `39807979797`): 25 e2e tests passed                                                                                                                                                                                                                                                                                                                                                                                                          |
| ci             | `v2/main` `2ca19b0`               | Oct 22 01:42 | failure: Linux `swift test` of `ios/App/AppCore`, 184 tests, 1 failure: `PackagePipelineTests.testSealUploadAndStationConfirmationKeepOriginalsByteIdentical` (`XCTUnwrap` of `StationStatusCache`, `PackagePipelineTests.swift:190`). It did not happen again on `add2d74`. "Verify export files" skipped.                                                                                                                                               |
| ios            | `v2/main` `2ca19b0`               | Oct 22 01:42 | failure: the same two causes as on `add2d74`                                                                                                                                                                                                                                                                                                                                                                                                              |
| web-e2e        | `v2/main` `2ca19b0`               | Oct 22 01:42 | success                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ci             | `feat/floorplan-report` `05f16e8` | Oct 21 03:51 | success, including "Verify export files"                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ios            | `fix/ios-ci-first-push` `80182ea` | Oct 18 19:40 | success: **the last green ios run**                                                                                                                                                                                                                                                                                                                                                                                                                       |
| deploy-station | `main` `3e22c19`                  | Oct 18 13:56 | failure: GitHub environment `staging` has no `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`                                                                                                                                                                                                                                                                                                                                                |
| testflight     | —                                 | —            | never run                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

Times are UTC. The `ios` run on `feat/floorplan-report` `05f16e8` (Oct 21) also failed; the last
green `ios` run is the one on `80182ea`.

### 3.2 Local runs on the owner's Mac (Oct 21-22)

| Run                                                                                 | Result                                                                                                                                                                                                                                                                                                                                 |
| ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Root gates (after the T4/T5 merges, before `9c7d45d` and `add2d74`)                 | format:check, lint (with secretlint), typecheck (8 workspaces), workspace tests, `next build`: all OK. Node tests, 0 failed: contract 151, fixtures 119, station-api 514, station-checks 298, dev-idp 51, station-hub 212, station-worker 23, web 290. Station tests ran on a private Postgres 16 and an Azurite stand-in, not Docker. |
| Swift packages (`scripts/swift-test.sh`, Swift 6.4.2, macOS 27.0)                   | all 9 packages passed (AppCore 184, PlanExport 207, CaptureCore 151 + 159, ...). Skipped: 2 real-scan tests (`CHAPTER_REAL_ROOMPLAN_DIR` unset), PackageKit `E2EUploadTests` (`STATION_URL` unset).                                                                                                                                    |
| iOS build and simulator tests, Xcode 27.2 beta, after T10/T6 (content of `2ca19b0`) | all 8 packages of the `ios.yml` matrix and the App built; package tests passed; **App UI tests 16 passed** (third run; the first run failed `testNotConfigured`); web e2e 25 passed; `migrate:check` 11 migrations PASS.                                                                                                               |
| iOS after the T4/T5 merges, Xcode 27.2 beta                                         | all packages and the App built; CaptureContract, ChapterUI, CaptureCore tests passed. PlanExport test run did not finish. MeshExport, FieldKit, PackageKit, StationClient, ChapterUISnapshots and **App UI tests were not run** after T5 changed PlanExport.                                                                           |
| Plan sheet snapshots                                                                | 18 renders, 0 pixels differ, but rendered with the local `pdftoppm` and macOS stand-in fonts, not the Docker reference image.                                                                                                                                                                                                          |
| Device build (Debug, field test)                                                    | BUILD SUCCEEDED with Xcode 27.2 beta, signed with the owner's personal team.                                                                                                                                                                                                                                                           |
| Worker e2e, integrated tree (Oct 22 01:15)                                          | **6 tests: 0 pass, 2 fail, 4 cancelled.** "stores a verdict and publishes it to the HUB within 120 s" timed out; then "Cannot use a pool after calling end on the pool". The same suite passed 6/6 on the T4 branch alone (Oct 21). Root cause not recorded; not re-run.                                                               |

## 4. Not run or not verified

- Docker-based export validators **locally** (Docker is not installed on the owner's Mac). On
  GitHub CI they ran on `add2d74` and passed (section 3.1).
- Plan sheet golden reference render in Docker (`scripts/verify/plan-sheet-snapshot.sh`); CI does
  not run this script.
- App UI tests and the package simulator suites after T4/T5: not run locally after T5 changed
  PlanExport (section 3.2), and on GitHub they fail before testing (App does not compile on
  Xcode 26.3; no iOS 26.0 simulator for the packages).
- Worker e2e on the integrated tree (failed, section 3.2).
- PackageKit `E2EUploadTests` against a local station.
- Real-scan tests (`CHAPTER_REAL_ROOMPLAN_DIR` unset).
- **Compass device tests D0 and D1: pending** (`docs/qa/compass-device-tests.md:9-12`). D1 decides
  whether `CompassMath.captureFrameYaw` is right before the sheet and the report rely on `heading`.
- TestFlight, App Store, any Azure deploy, any call to a live HUB.
- Human acceptance (`plan.md:504-508`): a recorded scan into `fixtures/recorded/`, TestFlight
  approval, live acceptance at one property (Polycam against Chapter Capture, tape controls,
  DXF/GLB in Revit 2027, LAS in ReCap). No record that they were done.

## 5. Known issues

| #   | Issue                                                                                                                                                                                                                                           | Where                                                                                                  |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 1   | **App does not compile on Xcode 26.3** (CI pin). Compiles on Xcode 27.2 beta. App Store builds need a release Xcode (**Verify**).                                                                                                               | `ios/App/Sources/App/Views/ModelStyle.swift:2265,2331,2495`                                            |
| 2   | **iOS CI simulator pin.** `SNAPSHOT_SIMULATOR_DESTINATION` wants iOS 26.0; the runner has 26.0.1, 26.1, 26.2, so every package job fails (still so on `add2d74`). Moving it means recording phone snapshots again.                              | `.github/workflows/ios.yml:45-49`                                                                      |
| 3   | **AppCore test failed once on Linux** (`StationStatusCache` nil) on `2ca19b0`; it passed on `add2d74` (184 tests, 0 failures) and on macOS. Root cause not recorded.                                                                            | `ios/App/AppCore/Tests/AppCoreTests/PackagePipelineTests.swift:190`                                    |
| 4   | **Worker e2e timeout** on the integrated tree.                                                                                                                                                                                                  | `station/worker/test/e2e/pipeline.e2e.ts`                                                              |
| 5   | **`REVIEW_BASE_URL` not set by `infra/`**; the worker exits without it. `HUB_WEB_DEAL_URL_TEMPLATE` not set either.                                                                                                                             | `infra/modules/containerapps.bicep:137-221`, `station/worker/src/config.ts:296-302`, `plan.md:497-498` |
| 6   | **HUB REST mapping unconfirmed** and different from the Aug 2025 HUB snapshot.                                                                                                                                                                  | `station/api/src/hub/mapping.ts:4-11`, `station/hub/src/mapping.ts:4-11`                               |
| 7   | **OIDC repo name** in infra params is `eranfromchapter/chapter-capture`; the repo is `chapter-lidar`. Also `BRANCH_PROTECTION.md:8` and its required check `gates` (job is `ci`).                                                               | `infra/params/*.bicepparam:9`, `.github/BRANCH_PROTECTION.md:8,43`                                     |
| 8   | **Station accepts any `ENTRA_ISSUER` in production** (Bicep sets the right one).                                                                                                                                                                | `station/api/src/core/config.ts:419-429`, `plan.md:493-494`                                            |
| 9   | **Block uploads on real Azure untested** (create-only SAS; Azurite rejects Put Block List).                                                                                                                                                     | `plan.md:482-484`                                                                                      |
| 10  | **"Download all" (package ZIP) not built** (OpenAPI declares it; no route, no migration 0012).                                                                                                                                                  | `station/api/test/core/openapi-conformance.coverage.test.ts:24-29`                                     |
| 11  | **LGPL libraries in the worker image**: `@img/sharp-libvips-*` 1.3.4 (LGPL-3.0-or-later) and `libheif-js` 1.23.5 (LGPL-3.0). Licence review by Chapter needed before production.                                                                | `station/hub/THIRD_PARTY_NOTICES.md:24-35`                                                             |
| 12  | **Spatial report plan page:** before `add2d74` the report printed "Room 2" without an area and no "Room 5" label, where the plan sheet prints both. Not investigated; re-check after `add2d74` (which fixed the room labels over object boxes). | `station/hub/src/report/`                                                                              |
| 13  | **Personal-team provisioning profile** of the owner's field-test build expires Oct 25, 2026.                                                                                                                                                    | `build/dd-v2/.../embedded.mobileprovision` (local)                                                     |
| 14  | **`GET /health` reports `1.0.0` in Azure**, not the commit (no `STATION_VERSION` build arg).                                                                                                                                                    | `station/api/Dockerfile:55-58`                                                                         |
| 15  | **No 0011 backfill job in `infra/`**; the migration identity has no storage role. Only matters where v1 packages exist.                                                                                                                         | `infra/README.md:55-56`                                                                                |
| 16  | **Snapshot goldens tied to the machine**: plan sheet (macOS stand-in fonts), phone (iOS 26.0 simulator). The station report snapshots, recorded on macOS, also matched on Linux CI on `add2d74`.                                                | sections 3.1, 3.2                                                                                      |

## 6. Open decisions

### 6.1 Owner questions Q-A to Q-G (defaults applied in the build)

All seven are still open questions to the owner. The build ships the default
(`DESIGN.md:125-135`; design spec `00-critique.md` section 5).

| #   | Question                                                                                       | Default as built                                                                                                                                                                       |
| --- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q-A | Field controls policy: tape/laser required (drawings) or scan values enough (Oct 18 decision)? | `ChecklistPolicy.standard` ships (scan values enough); the manual policy is built behind one constant, `ChecklistPolicy.shipping`                                                      |
| Q-B | Does a missing or poor compass reading make a package Limited?                                 | Only for captures scanned with the compass (capture record 1.1.0 with a reading or `headingIssue`); older records get an info finding; `COMPASS_LIMITATION_FOR_LEGACY_RECORDS = false` |
| Q-C | Does the HUB give the PM name and phone, and the web URLs of a deal and its Files folder?      | Optional fields and config (`HUB_WEB_DEAL_URL_TEMPLATE` → `links.hub`); "PM {name}", "Open in the HUB" and the Files link hidden until provided                                        |
| Q-D | Who reads the spatial report (photos in the HUB copy)?                                         | Photo pages as drawn: 356 x 444 px JPEG, EXIF and GPS stripped; report at most 45 MiB (photo pages dropped with a note otherwise)                                                      |
| Q-E | Package record pages at the end of the report?                                                 | Added: every file with role, size, SHA-256 and where it is                                                                                                                             |
| Q-F | A floor too big for the sheet?                                                                 | 1:50 → 1:100 → 1:200 (→ 1:500 exterior), quarter turn per rung, never fitted; cut at the frame with a footnote                                                                         |
| Q-G | Time zone of printed dates?                                                                    | America/New_York on the sheet, the report (`REPORT_TIME_ZONE`) and the web                                                                                                             |

### 6.2 Integration decisions for the team (not decided anywhere in the repo)

| Decision                                                                               | Recommendation in this kit                                                    | Guide                                                                                          |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| How the phase 1 PM app binary excludes capture                                         | No capture code in it; integrate on a branch merged after approval (option A) | [02, section 9](02-ios-into-pm-app.md#9-capture-off-for-the-first-submission-on-in-the-update) |
| Reuse the PM app's sign-in or keep `EntraSignIn`                                       | Reuse it if it is Entra/MSAL; otherwise capture keeps its own Entra sign-in   | [02, section 10](02-ios-into-pm-app.md#10-sign-in-and-station-settings)                        |
| Keep `fetch` and the verdict BGTask in the PM app                                      | Team choice; foreground refresh works without them                            | [02, section 8](02-ios-into-pm-app.md#8-permissions-background-work-and-entitlements)          |
| Raise the PM app's minimum iOS to 17                                                   | Required to link the packages; decide before phase 3                          | [02, section 3](02-ios-into-pm-app.md#3-what-the-capture-code-needs-from-the-host)             |
| How the web goes into the HUB                                                          | Own service on a HUB sub-domain, linked from the HUB (option A)               | [03, section 3](03-web-into-hub.md#3-integration-options-and-the-recommendation)               |
| Which station serves HUB training                                                      | Use `staging`; it needs the production Bicep applied in phase 2               | [04, section 9.3](04-station-and-deploy.md#93-which-environment-serves-training-input-needed)  |
| When v2 is merged into `main`, and when the production web is connected                | Training from `v2/main`; merge in phase 3; production web project in phase 4  | [README](README.md#branches-deploys-and-the-web)                                               |
| Web host (Vercel or other) and host names per environment                              | Vercel: a training project now, a production project in phase 4               | [03, section 4.1](03-web-into-hub.md#41-a-stable-training-host-on-vercel)                      |
| How the training and App Store builds get their station values                         | Separate training archive; App Store archive checked against production       | [02, section 10](02-ios-into-pm-app.md#10-sign-in-and-station-settings)                        |
| Station API scope name (`Capture.Upload` and `access_as_user` both appear as examples) | One name, used by the PM app and the web                                      | [02, section 10](02-ios-into-pm-app.md#10-sign-in-and-station-settings)                        |

## 7. Inputs needed from Chapter

### 7.1 Apple and the PM app

1. **PM app source** (repo, branch, access) and its stack.
2. PM app bundle id, Apple team, minimum iOS, iPad support, orientations, dark mode, current
   sign-in, existing notification delegate, BGTask ids, background modes, privacy manifest, build
   and submission pipeline.
3. Chapter's Apple Developer team and App Store Connect access for the PM app record.
4. An App Review demo account with the `capture` role on the production station, a dedicated test
   deal in the production HUB (confirmed address) for it, and a decision on whether the reviewer
   may see every other production deal (the station does not filter deals per user; 02, section
   13).
5. App Privacy questionnaire and export-compliance answers (account holder).
6. A release Xcode chosen for the App Store build; someone to fix `ModelStyle.swift` on it and
   move the CI pins.
7. A LiDAR iPhone (or iPad Pro) for development, the compass device tests D0/D1 and a recorded scan.
8. For the standalone app's `testflight.yml` only (if still used): environment `testflight`
   variable `APPLE_TEAM_ID`, secrets `APP_STORE_CONNECT_API_KEY_ID`,
   `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8` (`.github/BRANCH_PROTECTION.md:70-74`).

### 7.2 Microsoft Entra ("Chapter Main" tenant)

1. Tenant id.
2. The station API app registration: app roles `capture`, `bim`, `admin`; the delegated scope
   name; v2.0 access tokens; its client id and/or App ID URI (`CAPTURE_ENTRA_AUDIENCE`).
3. The PM app's client id (its own registration or a new one) with redirect URI
   `msauth.<PM bundle id>://auth` and permission to the station scope.
4. The review screen's app registration per environment (client id and secret), with redirect
   URI `https://<web host>/api/auth/callback/microsoft-entra-id`.
5. Who gets `capture`, `bim` and `admin` (users or groups), in training and production.
6. An Entra admin group for Chapter Capture (`CAPTURE_ADMIN_GROUP_OBJECT_ID`,
   `CAPTURE_ADMIN_GROUP_NAME`).

### 7.3 Azure and GitHub

1. Rights on the Chapter Main subscription (`Owner`, or `Contributor` + `User Access Administrator`).
2. The `infra/` one-time admin steps (04, section 7.6).
3. GitHub environments `staging` and `production` with `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID`; a required reviewer on `production`; `staging` allowing `v2/main`
   until v2 is merged (README, "Branches, deploys and the web").
4. The correct repo name in `infra/params/*.bicepparam` (`githubRepository`), and whether the repo
   moves to the `HelloChapter` org first (`.github/BRANCH_PROTECTION.md:6-11`).
5. Approval to create the production Azure resources in phase 2, if `staging` serves training,
   and the production HUB base URL for that deploy (04, section 9.1).
6. The Vercel projects (Chapter Vercel team) or another web host, and DNS for the web host names;
   whether a Vercel project is already connected to this repo (README, "Branches, deploys and the
   web").

### 7.4 HUB (training now, production later)

1. HUB training REST API base URL (`HUB_BASE_URL` / `CAPTURE_HUB_BASE_URL`).
2. A HUB training service credential (`HUB_SERVICE_CREDENTIAL`, Key Vault secret
   `hub-service-credential`) and how it is sent.
3. HUB team confirmation of the deals list, upload and document search endpoints and fields
   (04, section 5).
4. HUB training test deals whose confirmed-address flag is `true`. A package sealed into a deal
   without it never gets a verdict (04, section 5).
5. HUB training URLs: front end (`HUB_APP_URL`), deal page pattern (`HUB_WEB_DEAL_URL_TEMPLATE`),
   Files folder pattern (`HUB_FILES_URL_TEMPLATE`).
6. Training login credentials for the HUB training front end (to check publication), given to the
   team directly, never in the repo.
7. The live HUB front-end source and its navigation file (for the "Capture review" link), and
   whether the live HUB uses Entra.
8. The same items for HUB production, before phase 3.
9. `INTAKE_GUIDE_URL` target (the File Intake Guide).

### 7.5 Other

1. Licence review of the LGPL libraries in the worker image (section 5, item 11).
2. Answers to Q-A to Q-G, or confirmation that the defaults stand.

## 8. Earlier plan phases still open

From `docs/floorplan-report-plan.md:73-108`, checked against the code on `v2/main`:

| Phase                                            | Status                                                                                                                               |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| 4 Rooms screen: rename, retype, merge, split     | **Partly:** rename only (`room-names.json`, `ios/App/AppCore/Sources/AppCore/VisitRoomNames.swift:8-18`). No retype, merge or split. |
| 7 Floorplan Report PDF                           | Moved to the station as the spatial report (done on `v2/main`)                                                                       |
| 8 In-app screens: Floorplan, Report, Files       | Floorplan done; phone Report dropped by Design v2; no "Files" screen as such                                                         |
| 9 Location and true north                        | Replaced by the v2 compass                                                                                                           |
| 10 3D viewer: layers, orbit, top/walk, measuring | **Partly:** `ScanViewer` shows the model with camera control (`ScanViewer.swift:291-293`); no layers, top/walk views or measuring    |
| 11 Station check of report numbers               | Not a check rule; covered by parity tests (`metrics-parity.test.ts`, `plan-sheet-parity.test.ts`)                                    |

Also open from the plan defaults (`docs/floorplan-report-plan.md:41-52,70-71`): Xactimate (ESX)
export parked; wall thickness assumed (4.5 in / 6 in); `points.las` not produced on real devices
("both real exports have a header-only depth-samples.bin").
