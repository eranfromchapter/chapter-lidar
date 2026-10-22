# Build tracks for Chapter Capture v2

Written Oct 21, 2026 with `00-critique.md`. Twelve tracks. Each file in the repo has **one**
owning track; two tracks never edit the same file. Where an area spec lists a file that belongs to
another track, the owning track builds that part (the "Built by" notes in each spec's addendum).

Repo: `chapter-lidar`, base `feat/floorplan-report` (05f16e8). One branch per track
(`v2/<track>`), rebased on the integration branch `v2/main` after each merge.

---

## 1. Tracks at a glance

| Track | Areas (spec sections) | Owns (globs) | Depends on |
|---|---|---|---|
| **T0 contract-and-fixtures** | compass §4, §4.5; phone-field §10; phone-package §10.1, §10.2 (schemas); web-review §8.2, §9.1 (schemas); spatial-report §8.3 (schema), §8.5 (merged into `review-text.ts`); plan-sheet §4.6 (vectors merged); critique R-1, R-14…R-15d, R-19 | `contract/**`; `fixtures/generator/**`, `fixtures/generated/**`, `fixtures/report/**`; one-keyword edits to `ios/Packages/CaptureCore/Sources/CaptureTestSupport/SchemaValidator.swift` and `ios/Packages/PackageKit/Tests/PackageKitTests/Support/SchemaValidator.swift` | — |
| **T1 phone-foundation** | phone-capture §2 (ChapterUI, fonts, logo, appearance), critique R-17, R-18, R-18b–d | `ios/Packages/ChapterUI/**`; `tools/brand/generate_plan_brand.py`; `ios/project.yml`; `.github/workflows/ios.yml`; `ios/App/Sources/App/ChapterCaptureApp.swift`; `scripts/swift-test.sh` (only if the package list needs it) | — |
| **T2 station-api** | phone-package §10.3 (carry-over, `packageView`, next-revision notice, links); web-review §8.3, §9.1 A–F and H (API part), backfill; spatial-report §8.2 (migration), §8.3 (endpoint); critique R-13…R-16 | `station/api/**`; `station/db/**` (migrations `0009_carry-over`, `0010_spatial-reports`, `0011_review-read-model`, phase 3 `0012_archive-job`); `scripts/backfill-review-read-model.ts` (new) | T0 |
| **T3 station-checks** | compass §8.2 (`orientation.compass`, evaluator 1.1.0, Q-B constant) | `station/checks/**` | T0 |
| **T4 spatial-report** | spatial-report (all); compass §8.3; phone-package §11 station/hub and worker rows; web-review §9.1 H worker job (phase 3) | `station/hub/**`; `station/worker/**`; `infra/**`; `.github/workflows/ci.yml` | T0; T2 (migration 0010, endpoint); T5 (parity goldens); T3 (rule count in baselines) |
| **T5 plan-export** | plan-sheet (all); compass §6.3; phone-package §11 PlanExport rows; spatial-report §11.2 (Swift goldens) | `ios/Packages/PlanExport/**`; `fixtures/report-parity/**`; `scripts/verify/plan-sheet-snapshot.sh` (new); `scripts/verify-exports.sh` | T0 |
| **T6 web-review** | web-review (all); compass §9 (`web/lib/compass.ts`); phone-package §11 web rows | `web/**`; `tools/brand/chapter-wordmark.svg`; `.github/workflows/web-e2e.yml` (new) | T0; T2 (live API; mock until then); T4 (report link); T3 (baselines) |
| **T7 phone-capture-core** | phone-capture §3 (screens as views), §5.1, §5.5–5.7; compass §3, §5.1, §5.2, `CaptureCompass`; device tests D0–D1 | `ios/Packages/CaptureCore/**` (except T0's validator line); `docs/qa/compass-device-tests.md` (new) | T0, T1 |
| **T8 phone-field** | phone-field (all except §10 and App wiring); `NoRoomsSkippedConfirmation` `Codable` | `ios/Packages/FieldKit/**` | T0, T1 |
| **T9 phone-package** | phone-package §3–§9 phone side, §13 unit tests | `ios/Packages/PackageKit/**` (except T0's validator line); `ios/Packages/StationClient/**`; `ios/App/AppCore/Sources/AppCore/{UploadCoordinator,Summaries,StationQueries,StationUploadService,VisitPackageBuilder,UITestStation,UITestBlobTransport}.swift` + new `{RevisionBuilder,RevisionChanges,StationStatusCache}.swift`; their AppCore tests incl. `PackagePipelineTests`, `ManifestRoleTests`; `ios/App/Sources/App/Views/PackageScreens.swift`; `ios/App/Sources/App/AppDelegate.swift` | T0, T1 |
| **T10 phone-app-shell** | phone-capture §3.0, §3.1/§3.5 builders, §3.6, §5.2–5.4 (App/AppCore), §6 App rows; compass app wiring (§3.5 `CompassService` ownership, `CompassPhotoHeading`, §6.3 `FloorplanView`, R-24); phone-field §2/§14 App rows; phone-package §9.5 VisitView/VisitModel/AppModel/Info.plist parts and §13.3 UI tests | `ios/App/Sources/App/{AppModel,VisitModel}.swift` + new `{HomeModel,CompassPhotoHeading}.swift`; `ios/App/Sources/App/Views/{RootView,VisitView→AppNavigation,ScanViewer,FloorplanView,ModelStyle}.swift`; `ios/App/Sources/App/Debug/**`; `ios/App/Sources/App/Auth/**`; `ios/App/AppCore/Package.swift`; `ios/App/AppCore/Sources/AppCore/{VisitFlow,VisitWorkspace,VisitRoomNames,LaunchMode,AppConfiguration,StationAliases}.swift` + new `{CaptureLibrary,VisitStore,OverviewBuilder,StationProjectListing}.swift`; AppCore tests `{VisitFlowTests,CaptureLibraryTests,VisitStoreTests,OverviewBuilderTests,LocationNotStoredTests}`; `ios/App/Resources/**`; `ios/App/UITests/**` | T7, T8, T9, T5 (and T0, T1) |
| **T11 docs** | every spec's docs rows | `docs/**` (except `docs/qa/compass-device-tests.md`); `ios/App/README.md` | all others |

Package-level READMEs (`ios/Packages/FieldKit/README.md`, `contract/swift/README.md`,
`fixtures/generator/README.md`, …) belong to the track that owns the package.

---

## 2. Order and parallelism

```
Wave 0 (parallel, short)      T0 contract-and-fixtures      T1 phone-foundation
                                   │                              │
Wave 1 (parallel)     ┌────────────┼──────────────┬───────────────┼──────────────┐
                      T2 station-api   T3 checks   T5 plan-export  T7 capture-core
                      │                │           │               T8 phone-field
                      │                │           │               T9 phone-package
                      ├── T4 spatial-report (needs T2 migration, T5 goldens, T3 counts)
                      └── T6 web-review (mock station first; live after T2, T4)
Wave 2                                     T10 phone-app-shell (after T7, T8, T9, T5)
Wave 3                                     T11 docs
```

- **Merge order into `v2/main`:** T0 → T1 → T2 → T3 → T5 → (T7, T8, T9 in any order) → T4 → T6 →
  T10 → T11.
- **Critical paths:** T0 → T7 → T10 (phone app) and T0 → T2 → T4 (station report).
- **Deploy order (production):** contract + station API (T0, T2) and checks (T3) → worker/hub
  (T4) → web (T6) → app build (T5, T7–T10). The station must accept capture-record and manifest
  1.1.0 before any app writes them (compass §4.6, phone-field §10).
- **T7 starts with device tests D0–D1** (compass G5). If D1 finds that the capture frame is not the
  ARKit world frame, a small follow-up PR to T0 fixes `CompassMath.captureFrameYaw` before T5/T4
  rely on `heading`.
- **Baselines:** fixture-based expectations in T4 (F9 tests, report snapshots) and T6 (Playwright
  baselines, `package-detail.test.tsx`) are recorded after T3 merges (13 rules, evaluator 1.1.0,
  compass findings).

---

## 3. Interfaces frozen at kickoff (so Wave 1 can run in parallel)

Each owner publishes these signatures in its first PR (stubs allowed); consumers code against
them.

| Interface | Owner | Consumers | Content |
|---|---|---|---|
| Contract v1.1 | T0 | all | `manifest` 1.1.0, `capture-record` 1.1.0, OpenAPI 1.1.0 (merged per critique R-14…R-16, incl. `NextRevisionNotice.changes[].method`, `HubProject.projectManager`, `PackageFile.generator*`), TS `compass.ts`, `review-text.ts`, Swift `CompassState`, `NorthSymbol`, `CompassMath`, `HeadingSource`, `HeadingIssue`, `ManifestSchemaVersion`, `PhotoDirectionSource`, `FileRole.isRetired`, test vectors |
| ChapterUI | T1 | T7, T8, T9, T10 | `ChapterTheme.Color/Font/Metric`, `ChapterFonts.register()`, `ChapterAppearance.apply()`, `ChapterLogo`, the component union of critique R-18, `ChapterUISnapshotTesting` |
| Capture screens | T7 | T10 | `CapturesHomeScreen(state: CapturesHomeState, actions)`, `NewCaptureScreen`, `ScanSetupScreen`, `LiveScanScreen`, `CaptureOverviewScreen(state: CaptureOverviewState, actions)`, `CaptureFlowModel` (compass API names of compass §10.2), `CompassService`, `FakeCompass` |
| Field screens | T8 | T10 | phone-field §2 signatures plus `focus: ChecklistItemID?`, `isReadOnly: Bool`, `PhotoHeadingProviding`, `ControlsList`, `CompassSummary` |
| Package screens | T9 | T10 | `PackageReadyView`, `PackageStatusView(packageId:)`, `VerdictView`, `RevisionReviewView`, `StationStatusCache` (read/write), `CaptureCountText`, `VisitPackageBuilder.revisionPlan`, notification routing entry `openPackage(id:)` |
| PlanExport | T5 | T10, T9 (file names) | `FloorplanWriter.Options.north`, `PlanExportContext.compass`, `exportAll` = five files incl. `plan-sheet.pdf` |
| Station API | T2 | T6, T9, T4 | the OpenAPI 1.1.0 of T0; `spatial_reports` table (T2 migration) written by T4's worker |
| Report renderer | T4 | T2 (stores `floors`, `checksPage` via the worker) | `RenderedReport { bytes, sha256, pages, checksPage, recordPage, name, floors }` |

---

## 4. Shared-file rules (files more than one spec mentions)

| File | Mentioned by | Single owner |
|---|---|---|
| `contract/openapi/station.yaml` | phone-package, web-review, spatial-report, phone-capture | T0 |
| `contract/schema/manifest.schema.json` | phone-field, phone-package | T0 |
| `contract/schema/capture-record.schema.json` | compass, plan-sheet | T0 |
| `contract/ts/src/review-text.ts` / `verdict-words.ts` | web-review, spatial-report | T0 (one file `review-text.ts`) |
| `fixtures/generator/**` | phone-package, compass, plan-sheet, spatial-report | T0 |
| `ios/Packages/PlanExport/Sources/PlanExport/{PreviewWriters,SpatialReportWriter,NorthArrow,FloorPlanDrawing,FloorplanWriter,PlanExportContext}.swift` | plan-sheet, compass, phone-package | T5 |
| `ios/Packages/FieldKit/Sources/FieldKitUI/FieldTheme.swift`, `FieldKit/Package.swift` | phone-capture, phone-field | T8 |
| `ios/App/AppCore/Sources/AppCore/VisitFlow.swift` | phone-capture, phone-package, compass | T10 |
| `ios/App/AppCore/Sources/AppCore/UploadCoordinator.swift` | phone-capture, phone-package | T9 |
| `ios/App/AppCore/Sources/AppCore/StationQueries.swift` | phone-capture, phone-package | T9 (phone-capture's `listing()` goes into T10's new `StationProjectListing.swift`) |
| `ios/App/AppCore/Tests/AppCoreTests/PackagePipelineTests.swift` | phone-field, phone-package, plan-sheet | T9 (merges all three expectations) |
| `ios/App/Sources/App/{AppModel,VisitModel}.swift`, `Views/VisitView.swift` | phone-capture, phone-field, phone-package, compass | T10 |
| `ios/App/Sources/App/Debug/UITestEnvironment.swift` | phone-capture, phone-field, compass | T10 |
| `ios/App/Resources/Info.plist` | phone-capture, compass, phone-package, phone-field | T10 (location string from compass §3.1; background modes from phone-package §7) |
| `ios/App/UITests/ReplayFlowUITests.swift` | all phone specs, compass | T10 |
| `ios/project.yml`, `.github/workflows/ios.yml` | phone-capture, phone-field | T1 |
| `station/api/src/routes/packages/store.ts`, `uploads/views.ts`, `uploads/index.ts`, `core/config.ts` | phone-package, web-review, spatial-report | T2 |
| `station/hub/src/plan.ts` | phone-package, spatial-report | T4 |
| `station/worker/test/e2e/pipeline.e2e.ts` | phone-package, spatial-report | T4 |
| `web/lib/format.ts`, `web/test/package-detail.test.tsx` | phone-package, web-review | T6 |
| `docs/waves/design/DESIGN.md`, `docs/waves/specs/F*.md`, `docs/floorplan-report-plan.md` | every spec | T11 |
| `package-lock.json` (npm workspaces) | T0, T2, T3, T4, T6 (each adds deps to its workspace) | never hand-merged: after a rebase run `npm install --package-lock-only` and commit |

**Ripple exception for T0.** Contract type changes (for example `PackageManifest.schemaVersion`
becoming `ManifestSchemaVersion`) and regenerated fixtures (`plan-sheet.pdf`, no
`spatial-report.pdf`, manifest 1.1.0) can break compilation or expectations in packages owned by
other tracks. T0 makes the **minimal** compile fixes and expectation updates needed to keep `main`
green in the same PR, and merges **before** the other tracks branch, so these edits never collide.

---

## 5. Definition of done per track

| Track | Done when |
|---|---|
| T0 | `swift test --package-path contract/swift`, `npm test --workspace contract/ts`, generated files committed, every example valid/invalid as listed, fixtures regenerated with `index.json`, all existing CI jobs green |
| T1 | ChapterUI builds for iOS and (empty) on Linux; component snapshots recorded; `ChapterFonts.register()` idempotent; `ios.yml` has the `ChapterUI` job; generator reproduces the committed TTFs and logo data byte for byte |
| T2 | OpenAPI conformance tests for every new operation; carry-over, review routes, decisions list, spatial-report link, next-revision notice tests; migrations up on a fresh DB and on a copy of production schema; backfill script dry run |
| T3 | 13 rules, evaluator 1.1.0, compass findings per fixture, Q-B constant tested both ways |
| T4 | spatial-report §11 (unit, parity, visual, B&W, size, API/worker/e2e) and the updated F9 tests green |
| T5 | plan-sheet §13 (PS1–PS8) green, colour Floorplan bytes unchanged with `north: nil`, parity goldens committed |
| T6 | web-review §12 (unit, component, station, Playwright) green; addendum D1–D10 covered by tests |
| T7 | phone-capture §10.1–10.2 (minus the compass rows superseded by compass), compass §13.1/§13.3 phone parts; D0–D1 recorded |
| T8 | phone-field §15.1–15.2 (AC1–AC6, AC9, AC11) with the addendum changes |
| T9 | phone-package §13.1 unit tests, PackageKit tests, visual checks via `ChapterUISnapshotTesting` |
| T10 | all phone UI tests (phone-capture §10.3, phone-field §15.3, phone-package §13.3, compass §13.4) in `ReplayFlowUITests` green; accessibility audit (U10); font check (no SF in own screens) |
| T11 | DESIGN.md "Design v2 (Oct 21, 2026)" section, F2/F3/F5/F6/F9/F10 ACs updated, plan doc lines (manual north withdrawn, phone report retired) |
