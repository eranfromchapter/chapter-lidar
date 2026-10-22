# Chapter Capture: developer handoff kit

Start here. This kit is for experienced developers who have not seen the project. It was written
on Oct 22, 2026 from branch `v2/main` at commit `add2d74`. Every command, path, version and
setting name in it comes from the repo or from its CI and build logs; `path:line` points at the
source. Anything else carries one of the markers listed at the end of this page.

## What Chapter Capture is

Chapter Capture is Chapter Renovation's own LiDAR capture system. It replaces Polycam. A project
manager scans a property with an iPhone Pro or iPad Pro (LiDAR and Apple RoomPlan), takes
labelled site photos and seals one capture package per visit. The package holds the raw scans,
the 3D model, the plan files made on the phone (plan sheet PDF on Tabloid 11 x 17, DXF, CSV, PNG,
SVG), the photos and a capture record. The phone uploads the files straight to Azure Blob storage
through short-lived links the station hands out (`contract/openapi/station.yaml:10-29`,
`ios/App/README.md:6-12,30-33`).

The station is the Azure backend. It checks every package against 13 rules and gives a verdict:
Ready, Limited or Blocked (`station/checks/README.md`, `station/checks/src/verdict.ts:31`). It
then makes the spatial report PDF and publishes the report and the plan files to the HUB
project's Files tab (`docs/waves/design/DESIGN.md:94-97`, `station/hub/src/plan.ts:1-31`). The web
review app lets BIM operators and project managers find a project, open a package, read the
verdict and every finding, download files and record modeling decisions
(`docs/waves/specs/F10.md:15-17`).

## What goes where

| Part            | Folder in the repo       | Goes into                                                                         | Guide                                                |
| --------------- | ------------------------ | --------------------------------------------------------------------------------- | ---------------------------------------------------- |
| iOS capture     | `ios/`, `contract/swift` | Chapter's existing **PM app** (the project managers' iPhone app)                  | [02-ios-into-pm-app.md](02-ios-into-pm-app.md)       |
| Web review      | `web/`                   | The **HUB** (Chapter's backoffice and operations platform)                        | [03-web-into-hub.md](03-web-into-hub.md)             |
| Station backend | `station/`, `infra/`     | **Azure**, "Chapter Main" tenant (Container Apps, Postgres, Blob, Key Vault)      | [04-station-and-deploy.md](04-station-and-deploy.md) |
| Shared contract | `contract/`              | Used by all three: JSON schemas, OpenAPI `station.yaml` 1.1.0, TS and Swift types | [04-station-and-deploy.md](04-station-and-deploy.md) |

The repo builds the iOS part as a standalone app ("Chapter Capture", bundle id
`com.hellochapter.capture`, `ios/project.yml:63-64`). That app target is a shell. The capture code
lives in Swift packages that the PM app adds. The web review is a standalone Next.js app in the
HUB look. The recommended way into the HUB is a HUB sub-domain with links from the HUB navigation
([03, section 3](03-web-into-hub.md#3-integration-options-and-the-recommendation)).

## Timeline (owner direction, binding)

Four phases. Phase 2 runs in parallel with phase 1. Each phase ends at a gate.

1. **PM app submitted to Apple and approved, WITHOUT space capture.**
   - The binary sent to App Review holds no capture code: no capture packages linked, no capture
     entry point, no capture camera or location strings, no `fetch` background mode or capture
     BGTask id, no capture MSAL URL scheme
     ([02, section 9](02-ios-into-pm-app.md#9-capture-off-for-the-first-submission-on-in-the-update)).
   - The capture integration is built at the same time on a separate PM app branch. It does not
     enter this binary.
   - **Gate:** Apple approves this PM app version.
2. **In parallel: web review connected to the HUB training environment, with a training
   station.**
   - Deploy a station that talks to the HUB training API (`HUB_MODE=live`, `HUB_BASE_URL`,
     `HUB_SERVICE_CREDENTIAL`, `REVIEW_BASE_URL`). `infra/` knows only `staging` and `production`;
     which one serves training is an **Input needed**
     ([04, section 9.3](04-station-and-deploy.md#93-which-environment-serves-training-input-needed)).
   - Deploy the web review on a training host name against that station, with its own Entra
     redirect URI ([03, section 8](03-web-into-hub.md#8-training-connection-now-phase-2)).
   - **Gate:** a `bim` user signs in on the training web, sees HUB training deals, and opens a
     test package that reached a verdict and was published to the HUB training Files tab
     ([03, section 10](03-web-into-hub.md#10-acceptance-checklist)).
3. **Space capture added to the PM app and shipped as an App Store update, after the phase 1
   approval.**
   - The production station (v2, migrations through `0011`) is live and connected to the
     production HUB before the update is submitted. The station must accept capture record and
     manifest 1.1.0 before any app writes them (`docs/floorplan-report-plan.md:99`; design spec
     `00-tracks.md` section 2). App Review also needs a working station and a demo account with
     the `capture` role ([02, section 13](02-ios-into-pm-app.md#13-app-store-review-for-the-update-phase-3)).
   - Debug and TestFlight builds are tested against the training station first.
   - **Gate:** Apple approves the update, then one real visit works end to end in production:
     scan, photos, seal, upload, verdict, spatial report and plan files in the HUB Files tab.
4. **Web review deployed to HUB production, only after the iOS capture works end to end in the
   PM app (gate of phase 3).**
   - Production web host, production Entra redirect URI, production station URL and scope, HUB
     production links. Vercel deploys production from `main` only
     (`.github/BRANCH_PROTECTION.md:171`), so v2 must be merged to `main` first.
   - **Gate:** the production part of the checklist in
     [03, section 10](03-web-into-hub.md#10-acceptance-checklist) passes.

One dependency crosses phases 3 and 4. The station worker does not start without
`REVIEW_BASE_URL` (`station/worker/src/config.ts:296-302`) and prints that link into every
spatial report (`station/hub/src/plan.ts:129-133`). Choose the production web host name during
phase 3. Links in reports made before phase 4 open only once the production web is live.

## Mac requirements

The iOS part needs a Mac with Xcode. The other parts also build on the same Mac.

| Tool       | Version                                                                                                                        | Source                                                                |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------- |
| macOS      | a version that runs the chosen Xcode; the owner's Mac runs macOS 27.0                                                          | build logs                                                            |
| Xcode      | CI pins 26.3, but the App target does **not** compile on 26.3. It compiled with Xcode 27.2 beta (27B5038j). See 01, section 3. | `.github/workflows/ios.yml:42-43`, `05-status-open-items.md`          |
| XcodeGen   | 2.46.0                                                                                                                         | `.github/workflows/ios.yml:50-51`                                     |
| Node / npm | Node 22 (`.nvmrc`), engines `>=22.13.0`; npm `>=10`                                                                            | `.nvmrc`, `package.json:7-10`                                         |
| Docker     | required for the local station, the station API tests and the export validators                                                | `station/api/scripts/local-up.sh:15-18`                               |
| iPhone     | an iPhone Pro or iPad Pro with LiDAR, iOS 17 or later, for real scans                                                          | `ios/Packages/CaptureCore/Sources/CaptureCore/DeviceGate.swift:32-41` |

Full list and setup steps: [01-repo-and-mac-setup.md](01-repo-and-mac-setup.md).

## Repo and branch

- Repo: `https://github.com/eranfromchapter/chapter-lidar` (`git remote -v`).
- Branch: **`v2/main`** holds the complete v2 work. `main` holds only the v1 build (OpenAPI 1.0.0,
  migrations `0001`-`0008`).
- **Input needed (owner):** push `v2/main`. On Oct 22, 2026 at 09:38 the local `v2/main` was at
  `add2d74`, while GitHub's `v2/main` was at `2ca19b0`, 16 commits behind. The newer commits hold
  the station spatial report (T4), the plan sheet v2 (T5) and the docs. A clone made before the
  push misses them.
- This kit is on branch `v2/handoff` (one commit on top of `v2/main` at `add2d74`). It is not
  pushed either.
- PR #1 (`fix/ios-ci-first-push` to `main`) is open and superseded: its head `80182ea` is already
  inside `v2/main`.

## Documents in this kit

| File                                                 | What it covers                                                                                                                                                                                                                       |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [01-repo-and-mac-setup.md](01-repo-and-mac-setup.md) | Clone, Mac tools with versions, build and test commands for every part, local station (Docker), field-test build for a real iPhone                                                                                                   |
| [02-ios-into-pm-app.md](02-ios-into-pm-app.md)       | Packages to add, what to port, Info.plist keys and strings, permissions, background modes, sign-in and station settings, capture OFF then ON, App Review, LiDAR gating, native vs React Native or Flutter host, acceptance checklist |
| [03-web-into-hub.md](03-web-into-hub.md)             | Integration options and the recommendation, environment variables, Entra and roles, HUB links, the training connection, production go-live gate, acceptance checklist                                                                |
| [04-station-and-deploy.md](04-station-and-deploy.md) | Components, environment variables, migrations and backfill, Azure resources, CI/CD, deploy order, contract versions                                                                                                                  |
| [05-status-open-items.md](05-status-open-items.md)   | What is done and tested, what was not run, known issues, open decisions with the defaults applied, inputs needed from Chapter                                                                                                        |
| [design/README.md](design/README.md)                 | The v2 design specs (copied into `design/specs/`), which one wins when they disagree, and the Claude Design project link                                                                                                             |

Background documents already in the repo: `docs/waves/design/DESIGN.md` (section "Design v2"),
`docs/waves/specs/F1.md` to `F13.md`, `docs/waves/context/architecture.md`,
`docs/floorplan-report-plan.md`, `plan.md`, `.github/BRANCH_PROTECTION.md`, `infra/README.md`,
`ios/App/README.md`.

## Markers used in this kit

- **Input needed:** Chapter must provide it. It is not in the repo.
- **Not built:** it does not exist in the repo yet.
- **Recommendation:** our proposal. It is not in the repo yet.
- **Verify:** general Apple, Microsoft or vendor behaviour that is not in the repo. Check it
  against the vendor's current documentation before relying on it.

No secret is in this kit. Secrets go only into the stores named in it (Key Vault, GitHub
environments, Vercel project settings, the PM app's own secret store).

## Brand rules (owner decisions, binding)

- The real Chapter logo everywhere, never typed text. Inter everywhere
  (`docs/waves/design/DESIGN.md:75-84`).
- The web review keeps the HUB look: HUB tokens, white HUB wordmark, Inter 400/600 self-hosted
  (`DESIGN.md:85-88`).
- The colour Floorplan stays as approved (`DESIGN.md:107-108`).
- The plan sheet is made on the phone; the spatial report is made on the station
  (`DESIGN.md:89-97`).
