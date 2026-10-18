# Chapter Capture app shell (spec F6, step F6.4)

One site visit, in the order of the frozen design: capture record → scan (per floor or area,
replay in UI tests) → photos → field controls → before you leave (checklist gate) → package
ready (seal) → uploading and station status.

- **Live scan camera feed.** The scan panel is `CaptureSessionPreview(model:)` from
  `CaptureRoomPlan`: the camera feed of `CaptureFlowModel.currentSession` when it is a
  `LiveCaptureSession`, the design's dark placeholder otherwise (`ReplaySession` in UI tests).
- **"No rooms skipped".** On "Before you leave", the skipped-rooms row fails until a room note
  exists or the operator taps **No rooms skipped**. The tap is kept in `VisitFlow`
  (`confirmNoRoomsSkipped()`, FieldRules' `NoRoomsSkippedConfirmation`) and fed to
  `ChecklistInput.noRoomsSkippedConfirmed`. It covers only the captures that existed at the tap:
  a new floor from "Add more rooms" opens the row again. A new visit starts unconfirmed.

| Path                   | What                                                                                              |
| ---------------------- | ------------------------------------------------------------------------------------------------- |
| `../project.yml`       | XcodeGen spec: target `App`, UI-test target `AppUITests`, scheme `App`                            |
| `AppCore/`             | Pure-Swift logic, Linux-testable (no MSAL, UIKit or SwiftUI)                                      |
| `Sources/App/`         | SwiftUI app: MSAL sign-in, screens, background upload hook (`.apple-only`)                        |
| `Sources/App/Debug/`   | UI-test mode, `UITest*` files, Debug only                                                         |
| `UITests/`             | `ReplayFlowUITests`: replays the box-room fixture through every screen to "Checks queued"         |
| `Config/*.xcconfig`    | Configuration (placeholders committed, no secrets)                                                |
| `Resources/`           | `Info.plist`, `App.entitlements` (MSAL Keychain group)                                            |

## Generate and run

Needs Xcode 26.3 and XcodeGen 2.46.0 (the versions `.github/workflows/ios.yml` pins).

```sh
xcodegen generate --spec ios/project.yml        # writes ios/ChapterCapture.xcodeproj (do not commit it)
xcodebuild build -project ios/ChapterCapture.xcodeproj -scheme App \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project ios/ChapterCapture.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

AppCore on Linux or macOS (not part of `npm test`, which only scans `ios/Packages/*`):

```sh
swift test --package-path ios/App/AppCore
swift build -c release --package-path ios/App/AppCore   # Release: no UI-test stubs compiled
```

## Configuration

Info.plist keys, filled from build settings in `Config/Base.xcconfig`:

| Info.plist key           | Build setting               | Value                                                    |
| ------------------------ | --------------------------- | -------------------------------------------------------- |
| `ChapterEntraClientID`   | `CHAPTER_ENTRA_CLIENT_ID`   | Entra application (client) id, a UUID                    |
| `ChapterEntraTenantID`   | `CHAPTER_ENTRA_TENANT_ID`   | Entra directory (tenant) id, a UUID                      |
| `ChapterStationAPIScope` | `CHAPTER_STATION_API_SCOPE` | `api://<station app id>/<scope>`                         |
| `ChapterStationURL`      | `CHAPTER_STATION_URL`       | `https:/$()/station.host` (`//` is a comment in xcconfig) |

The committed values are `__SET_…__` placeholders. Put real values in `Config/Local.xcconfig`
(included with `#include?`, keep it out of git) or pass them as `xcodebuild` settings. A missing,
placeholder or invalid value shows **App is not configured** and creates no station client and
no MSAL application: nothing is sent anywhere and there is no fallback station or demo data.

The Entra app registration needs the redirect URI `msauth.com.hellochapter.capture://auth`.
Tokens stay in MSAL's Keychain cache (`$(AppIdentifierPrefix)com.microsoft.adalcache`); the app
never writes or logs a token. Sign-out (`AppModel.signOut()`) removes the MSAL accounts and calls
`ProjectStore.clearCache()`.

**Sign out** is a caption link at the bottom of New capture: "Signed in as <name> · Sign out"
(`accessibilityIdentifier` `account.signOut`). The name is the MSAL account's `name` claim, else its
username. Rules:

- Shown only on New capture of a visit with no capture yet (`VisitFlow.allowsSignOut`), so a
  sign-out never abandons unsealed originals. From the first floor on, it is hidden.
- Sign-out deletes no file. Sealed packages the station has not confirmed stay on the phone and
  resume after the next sign-in; while there are any, the link shows "Uploads resume after you
  sign in again."
- After sign-out the sign-in screen is shown.

## Debug-only UI-test mode

Launching with `-ChapterUITestReplay box-room` selects `LaunchMode.uiTestReplay`: the scan replays
the bundled `fixtures/generated/box-room/package` capture (`ReplaySession`), "Take photo" returns
the fixture's photo, and the station, blob storage and token are in-process stubs from AppCore
(`UITestStationTransport`, `UITestBlobTransport`, `UITestTokenProvider`). Nothing leaves the
simulator. The real StationClient, bridge, PackageAssembler and PackageUploader still run.
The signed-in name is `UITestTokenProvider.operatorName` ("UI Test Operator"). The replay test
checks that the sign-out link is on New capture but does not tap it (there is no MSAL to sign in
again), and it taps "No rooms skipped" instead of entering a skipped room.

Why a Release build cannot select it:

1. `LaunchModeResolver.resolve(arguments:isDebugBuild:)` returns `.live` whenever `isDebugBuild`
   is false (tested in `LaunchModeTests.testReleaseBuildNeverSelectsTheReplayMode`); the app passes
   its own `#if DEBUG` flag.
2. The stubs in AppCore and the app's `UITestEnvironment` / `UITestViewfinder` are wrapped in
   `#if DEBUG`, so they do not exist in a Release build (`swift build -c release` of AppCore
   compiles without them).
3. `project.yml` sets `EXCLUDED_SOURCE_FILE_NAMES = "UITest* package"` for Release, so the stub
   sources and the fixture folder are not even in the Release target.

## Data rules

- Originals are only read: raw scan files (`originals/`), photos (`photos/`). Generated files go
  to a new `drafts/<id>/` folder per build; sealed packages to `packages/<packageId>/`, read-only.
- Nothing is deleted from the phone. There is no delete UI in v1. `UploadSnapshot.isConfirmedByStation`
  (PackageKit's `UploadState.isConfirmedByStation`) is the only signal that the station has a package.
- Uploads use PackageKit's `BackgroundBlobTransport` (one instance, identifier
  `com.hellochapter.capture.package-upload`); `AppDelegate` passes
  `handleEventsForBackgroundURLSession`'s handler to it. Sealed packages not yet confirmed are found
  at launch (`PendingUploads`) and resumed.

## Not compiled here

This phase was written on Linux without Xcode, the iOS SDK, XcodeGen or a simulator. `AppCore`
builds and its tests pass on Linux; everything under `Sources/App/`, `UITests/` and `project.yml`
has not been compiled or run and is first checked by the `App` job of `ios.yml`. The app and UI
test targets use Swift language mode 5 with `SWIFT_STRICT_CONCURRENCY = complete`, like the
`CaptureUI` and `CaptureRoomPlan` targets, so a concurrency annotation the SDK disagrees with is a
warning rather than a failed build.

APIs used by the phase P6c-fix1 changes that were not compiled here: `CaptureSessionPreview` and
`CaptureFlowModel.currentSession` (CaptureCore), the `onConfirmNoRoomsSkipped:` argument of
`BeforeYouLeaveView` (FieldKitUI), and SwiftUI's `safeAreaInset(edge:spacing:content:)`, `truncationMode(_:)` and
`accessibilityIdentifier(_:)` in `VisitView`.
