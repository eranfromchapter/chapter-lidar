# Chapter Capture app shell (spec F6, Design v2)

The phone app of Design v2 (Oct 21, 2026; `docs/waves/design/DESIGN.md`, artboards 2b, 2d, 2f):
one `NavigationStack` (`Views/AppNavigation.swift`) with the **Captures home** at its root.

**Captures home** (In progress and Sealed rows) → **New capture** (HUB project, address
confirmed on site) → **What are you scanning?** (floor or area, mode, skipped rooms, coverage
notes, the Compass section) → **Live scan** (full-screen, compass chip) → **Photos** → **Capture
overview** (floors, photos, field controls, compass, rooms not scanned; the gate to the package)
→ **Field controls** and **Before you leave** → **Package ready** (seal) → **Package status**
(upload and station) → **Verdict received**. **Add to this capture** on the verdict starts
**Revision n** on the same visit.

- **Look.** Every screen is drawn with ChapterUI (`ios/Packages/ChapterUI`): Inter for all text
  (registered by `ChapterFonts.register()`, never through `UIAppFonts`), Times New Roman for the
  large titles, the system monospaced font for ids, the real Chapter logo (`ChapterLogo`), the
  system navigation bar and back chevron. No SF text and no typed "chapter / RENOVATION"
  (AppCore `FontUsageTests`, the UI test's font audit).
- **Compass.** One `CompassService` (CaptureCore target `CaptureCompass`) per app run feeds the
  pre-check on What are you scanning?, the reading taken at the start of each floor's scan, and
  the photo camera bearing ("Looking toward", through `CompassPhotoHeading`). Each capture of
  `capture-record.json` (1.1.0) gets the reading or, when the scan was read with the compass and
  gave none, `headingIssue`; a capture not scanned with the compass gets neither. The compass
  never blocks Start scan, Finish floor or the package. Location (`NSLocationWhenInUseUsageDescription`)
  only turns the compass into true north; no location value is written to any file or log
  (`LocationNotStoredTests`).
- **Live scan camera feed.** The scan screen shows `CaptureSessionPreview(model:)` from
  `CaptureRoomPlan`: the camera feed of `CaptureFlowModel.currentSession` when it is a
  `LiveCaptureSession`, the design's dark placeholder otherwise (`ReplaySession` in UI tests).
- **Plans on the phone.** Package ready builds, per capture, the plan sheet `plan-sheet.pdf`
  (Tabloid 11 x 17, PlanExport), DXF, CSV, PNG and SVG; the phone no longer writes a Spatial
  Report PDF (the station makes the spatial report after its checks). The in-app Floorplan screen
  (`FloorplanView`) keeps the colour Floorplan, with the north arrow when the reading is usable.
- **Rooms not scanned.** On Before you leave the skipped-rooms row fails until a room note exists
  or the operator taps **All rooms scanned**. The tap is kept in `VisitFlow`
  (`confirmNoRoomsSkipped()`, FieldRules' `NoRoomsSkippedConfirmation`) and covers only the
  captures that existed at the tap: a new floor opens the row again.

| Path | What |
| --- | --- |
| `../project.yml` | XcodeGen spec: target `App`, UI-test target `AppUITests`, scheme `App` |
| `AppCore/` | Pure-Swift logic, tested with `swift test` (no MSAL, UIKit or SwiftUI): `VisitFlow`, `VisitStore` (`visit.json`), `CaptureLibrary` (home rows), `OverviewBuilder`, `VisitPackageBuilder` and `RevisionBuilder`, `UploadCoordinator`, `StationStatusCache`, `LaunchMode` |
| `Sources/App/` | SwiftUI app: `AppModel`, `HomeModel`, `VisitModel`, `CompassPhotoHeading`, MSAL sign-in (`Auth/`), background upload hook (`AppDelegate`) (`.apple-only`) |
| `Sources/App/Views/` | `AppNavigation` (the one stack), `RootView`, `PackageScreens`, `FloorplanView`, `ScanViewer` |
| `Sources/App/Debug/` | UI-test and field-test modes (`UITest*`, `FieldTest*`), Debug only |
| `UITests/` | `ReplayFlowUITests`: replays the box-room fixture through every screen to the verdict |
| `Config/*.xcconfig` | Configuration (placeholders committed, no secrets; `Local.xcconfig` is not committed) |
| `Resources/` | `Info.plist`, `App.entitlements` (MSAL Keychain group) |

Files of one visit (Application Support, one folder per visit): `originals/` (raw scans, only
read), `photos/` (originals and `photo-records.json`), `controls/`, `room-names.json`,
`visit.json` (capture record draft, revision, sealed state), `drafts/<id>/` (generated files of
each build), `packages/<packageId>/` (sealed, read-only) with `<packageId>.upload-state.json` and
`<packageId>.station-status.json` next to them.

## Generate and run

Needs XcodeGen 2.46.0 and the Xcode `.github/workflows/ios.yml` pins (Xcode 26.3; the plans
phase was also built with the Xcode 27 beta).

```sh
xcodegen generate --spec ios/project.yml        # writes ios/ChapterCapture.xcodeproj (do not commit it)
xcodebuild build -project ios/ChapterCapture.xcodeproj -scheme App \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project ios/ChapterCapture.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

AppCore on Linux or macOS (`npm test` runs it through `scripts/swift-test.sh`):

```sh
swift test --package-path ios/App/AppCore
swift build -c release --package-path ios/App/AppCore   # Release: no UI-test stubs compiled
```

## Configuration

Info.plist keys, filled from build settings in `Config/Base.xcconfig`:

| Info.plist key | Build setting | Value |
| --- | --- | --- |
| `ChapterEntraClientID` | `CHAPTER_ENTRA_CLIENT_ID` | Entra application (client) id, a UUID |
| `ChapterEntraTenantID` | `CHAPTER_ENTRA_TENANT_ID` | Entra directory (tenant) id, a UUID |
| `ChapterStationAPIScope` | `CHAPTER_STATION_API_SCOPE` | `api://<station app id>/<scope>` |
| `ChapterStationURL` | `CHAPTER_STATION_URL` | `https:/$()/station.host` (`//` is a comment in xcconfig) |
| `ChapterFieldTest` | `CHAPTER_FIELD_TEST` | `YES` selects the field-test mode in a Debug build; `NO` otherwise (Release always `NO`) |

The committed values are `__SET_…__` placeholders. Put real values in `Config/Local.xcconfig`
(included with `#include?`, keep it out of git) or pass them as `xcodebuild` settings. A missing,
placeholder or invalid value shows **App is not configured** and creates no station client and
no MSAL application: nothing is sent anywhere and there is no fallback station or demo data.

The Entra app registration needs the redirect URI `msauth.com.hellochapter.capture://auth`.
Tokens stay in MSAL's Keychain cache (`$(AppIdentifierPrefix)com.microsoft.adalcache`); the app
never writes or logs a token. Sign-out (avatar on the Captures home → "Signed in as …" →
**Sign out**, `account.signOut`) removes the MSAL accounts and calls `ProjectStore.clearCache()`.
It deletes no file: sealed packages the station has not confirmed stay on the phone and resume
after the next sign-in.

## Field-test mode (the owner's iPhone)

A Debug build with `CHAPTER_FIELD_TEST = YES` runs the real scan, camera and compass with the
in-process stub sign-in and station of the UI-test mode, so a whole visit (scan, photos, controls,
seal, "upload", verdict) runs on the phone and nothing leaves it. Sealed packages stay in
`Application Support/FieldTestVisits`; copy them off with `xcrun devicectl device copy from …`
(see `Sources/App/Debug/FieldTestEnvironment.swift`).

`Config/Local.xcconfig` (not committed):

```
CHAPTER_FIELD_TEST = YES
DEVELOPMENT_TEAM = <your team id>
```

Build for a connected iPhone (signing with automatic provisioning):

```sh
xcodegen generate --spec ios/project.yml
xcodebuild build -project ios/ChapterCapture.xcodeproj -scheme App -configuration Debug \
  -destination generic/platform=iOS -derivedDataPath build/dd-v2 \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration
/usr/libexec/PlistBuddy -c 'Print :ChapterFieldTest' \
  build/dd-v2/Build/Products/Debug-iphoneos/ChapterCapture.app/Info.plist   # YES
```

Then install `build/dd-v2/Build/Products/Debug-iphoneos/ChapterCapture.app` with Xcode or `xcrun devicectl
device install app`. Release ignores the flag and excludes the `FieldTest*` sources.

## Debug-only UI-test mode

Launching with `-ChapterUITestReplay box-room` selects `LaunchMode.uiTestReplay`: the scan replays
the bundled `fixtures/generated/box-room/package` capture (`ReplaySession`), "Take photo" returns
the fixture's photo, and the station, blob storage and token are in-process stubs from AppCore
(`UITestStationTransport`, `UITestBlobTransport`, `UITestTokenProvider`). Nothing leaves the
simulator. The real StationClient, bridge, PackageAssembler and PackageUploader still run.
The signed-in name is `UITestTokenProvider.operatorName` ("UI Test Operator").

Options (`UITestLaunchOptions`, `UITestStationOptions`):

| Launch argument | Effect |
| --- | --- |
| `-ChapterUITestCompass verified\|approximate\|none` | `FakeCompass` script for the pre-check, the scan reading and the photo bearing (default `verified`: 212.4° ±8 true; photo 85° ±8 true, "E"); `none` records `not_calibrated` |
| `-ChapterUITestVerdict ready\|limited\|blocked` | the stub station's verdict |
| `-ChapterUITestRefuse` | the stub station refuses the first upload session (409, Upload stopped); later ones are accepted |
| `-ChapterUITestOffline [seconds]` | blob uploads fail as offline for that long (default 20 s), and the HUB project list is offline after its first answer |
| `-ChapterUITestVisitsRoot <name>` | keep the visits in `UITestVisits-<name>`, so a relaunch finds them |
| `-ChapterUITestTrackingLost <first> <last>` | the replay loses tracking between those steps |
| `-ChapterUITestScanStep <seconds>` | one replay step every that many seconds (default 0.5) |
| `-ChapterUITestV1Visits` | visit folders as the v1 app left them, made from the fixture |
| `-ChapterUITestNotifyDuringScan` | a verdict notification is tapped during a live scan |

Why a Release build cannot select the UI-test or field-test mode:

1. `LaunchModeResolver.resolve(arguments:isDebugBuild:fieldTestFlag:)` returns `.live` whenever
   `isDebugBuild` is false; the app passes its own `#if DEBUG` flag.
2. The stubs in AppCore and the app's `UITest*` / `FieldTest*` files are wrapped in `#if DEBUG`,
   so they do not exist in a Release build (`swift build -c release` of AppCore compiles without
   them).
3. `project.yml` sets `EXCLUDED_SOURCE_FILE_NAMES = "UITest* FieldTest* package"` for Release, so
   the stub sources and the fixture folder are not even in the Release target.

## Data rules

- Originals are only read: raw scan files (`originals/`), photos (`photos/`). Generated files go
  to a new `drafts/<id>/` folder per build; sealed packages to `packages/<packageId>/`, read-only.
- A package sealed by this app has manifest 1.1.0 and no `spatial_report_pdf` file. Packages
  sealed by an older build (1.0.0, with the phone report) still upload.
- Nothing is deleted from the phone. `UploadSnapshot.isConfirmedByStation` (PackageKit's
  `UploadState.isConfirmedByStation`) is the only signal that the station has a package.
- A revision n+1 is a new package of the same visit: it uploads only the files added or changed
  since the revision it builds on; the station carries the unchanged files over by SHA-256.
  Revision n stays byte-identical on the phone and at the station.
- Uploads use PackageKit's `BackgroundBlobTransport` (one instance, identifier
  `com.hellochapter.capture.package-upload`); `AppDelegate` passes
  `handleEventsForBackgroundURLSession`'s handler to it. Sealed packages not yet confirmed are found
  at launch (`PendingUploads`) and resumed. `UploadCoordinator` and the background refresh write
  `<packageId>.station-status.json` (`StationStatusCache`), which the Captures home reads.
