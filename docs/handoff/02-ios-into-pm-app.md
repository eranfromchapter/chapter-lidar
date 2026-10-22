# 02 · iOS capture into the PM app

The iOS capture goes **into Chapter's existing PM app** (the project managers' iPhone app). The
repo builds it as a standalone app, "Chapter Capture" (`ios/project.yml`). This guide says what to
add to the PM app, what to port, what to change, and how capture stays out of the first App Store
submission and arrives in the update.

**Input needed:** the PM app source is not in any repo we could read. Its stack, bundle id,
sign-in, minimum iOS version and build pipeline are unknown. Every step below that depends on them
says so.

## 1. Summary

- The capture code is Swift packages (`contract/swift`, `ios/Packages/*`, `ios/App/AppCore`) plus
  about 7,600 lines of SwiftUI app code in `ios/App/Sources/App` (`wc -l`, Debug folder
  included). The packages are added as they are. The app code is ported into the PM app.
- All capture UI is SwiftUI. The scan uses Apple RoomPlan and ARKit. Sign-in uses MSAL (Microsoft
  Entra). Uploads use a background `URLSession`. The capture must run as native Swift inside the
  PM app's iOS project, whatever the PM app's own stack is (section 14).
- Phase 1: the PM app goes to Apple **without** capture. Phase 3: capture ships as an App Store
  update after that approval (section 9).

## 2. Before you start

**Inputs needed from Chapter:**

1. PM app source repo and access; its stack (Swift/SwiftUI, UIKit, React Native or Flutter).
2. PM app bundle id, Apple team, minimum iOS version, iPad support, orientations, dark mode.
3. How the PM app signs in today (Entra/MSAL or other) and its MSAL version, if any.
4. Whether the PM app already has a notification delegate, push, BGTask ids, background modes or a
   privacy manifest (`PrivacyInfo.xcprivacy`).
5. How the PM app is built and submitted today (CI, signing, App Store Connect access).
6. Entra values: client id, tenant id, station API scope, `capture` role assignments (section 10).
7. Training and production station URLs (https).

**Blockers in the capture code to fix first:**

- `ios/App/Sources/App/Views/ModelStyle.swift` lines 2265, 2331, 2495 do not compile on Xcode 26.3
  (CI run `39707269821`). It compiled on Xcode 27.2 beta (27B5038j). It must compile on the release
  Xcode the PM app ships with ([01, section 3](01-repo-and-mac-setup.md#xcode-version-read-this-first)).
- `v2/main` must be pushed to GitHub ([README](README.md#repo-and-branch)).

## 3. What the capture code needs from the host

| Need                                     | Value                                                        | Source                                                                          |
| ---------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| Minimum iOS                              | 17.0. Every package declares `.iOS(.v17)`, `.macOS(.v14)`    | `ios/project.yml:12-13,21`, e.g. `ios/Packages/CaptureCore/Package.swift:29-32` |
| Swift tools                              | `// swift-tools-version: 6.0` (all 8 manifests)              | line 1 of each `Package.swift`                                                  |
| App target Swift settings in the repo    | `SWIFT_VERSION: "5.0"`, `SWIFT_STRICT_CONCURRENCY: complete` | `ios/project.yml:19-20`                                                         |
| Targets kept in Swift 5 language mode    | `CaptureCompass`, `CaptureRoomPlan`, `CaptureUI`             | `ios/Packages/CaptureCore/Package.swift:62,72,81`                               |
| MSAL                                     | `exactVersion: 2.16.0`                                       | `ios/project.yml:43-45`                                                         |
| Third-party dependencies in the packages | none; only the App target uses MSAL                          | `ios/Packages/StationClient/README.md:3-5`                                      |
| Device family in the repo                | `TARGETED_DEVICE_FAMILY: "1,2"` (iPhone and iPad)            | `ios/project.yml:68`                                                            |
| `Package.resolved`                       | none committed                                               | repo search                                                                     |

- **Verify:** Swift Package Manager refuses a package whose minimum platform is newer than the
  app's deployment target. If the PM app supports iOS below 17, raising it to 17 drops those users.
  Decide this before phase 3 (**Input needed**).

## 4. Packages to add

Local packages, paths from the repo root (`ios/project.yml:24-45`):

| Package (identity)        | Path                                                                   | Products                                                                               | Depends on                                                                                |
| ------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| CaptureContract (`swift`) | `contract/swift`                                                       | `CaptureContract`                                                                      | Foundation only                                                                           |
| ChapterUI                 | `ios/Packages/ChapterUI`                                               | `ChapterUI`, `ChapterUISnapshotTesting`                                                | none                                                                                      |
| CaptureCore               | `ios/Packages/CaptureCore`                                             | `CaptureModelMapping`, `CaptureCore`, `CaptureCompass`, `CaptureRoomPlan`, `CaptureUI` | CaptureContract, ChapterUI                                                                |
| PlanExport                | `ios/Packages/PlanExport`                                              | `PlanExport`                                                                           | CaptureContract                                                                           |
| MeshExport                | `ios/Packages/MeshExport`                                              | `MeshExport`                                                                           | CaptureContract (tests only)                                                              |
| FieldKit                  | `ios/Packages/FieldKit`                                                | `FieldKit` (targets FieldRules, PhotoStore, FieldKitUI)                                | CaptureContract, ChapterUI                                                                |
| PackageKit                | `ios/Packages/PackageKit`                                              | `PackageKit` (targets PackageCore, PackageTransport)                                   | CaptureContract                                                                           |
| StationClient             | `ios/Packages/StationClient`                                           | `StationClient`                                                                        | CaptureContract                                                                           |
| AppCore                   | `ios/App/AppCore`                                                      | `AppCore`                                                                              | CaptureContract, CaptureCore, PlanExport, MeshExport, FieldKit, PackageKit, StationClient |
| MSAL (remote)             | `https://github.com/AzureAD/microsoft-authentication-library-for-objc` | `MSAL`                                                                                 | —                                                                                         |

Products the App target links (`ios/project.yml:75-102`): `AppCore`, `CaptureContract`,
`ChapterUI`, `CaptureCore`, `CaptureModelMapping`, `CaptureRoomPlan`, `CaptureUI`, `PlanExport`,
`MeshExport`, `FieldKit`, `PackageKit`, `StationClient`, `MSAL`. `CaptureCompass` comes in
through `CaptureRoomPlan` (`ios/Packages/CaptureCore/Package.swift:64-69`).

- The packages point at each other by relative path, for example
  `.package(path: "../../../contract/swift")` (`ios/App/AppCore/Package.swift:28-34`).
- **Recommendation:** bring `contract/swift`, `ios/Packages/` and `ios/App/AppCore/` into the PM
  app repo together, with the same relative layout, or add this repo as a Git dependency. Copying
  one package alone breaks the paths.
- Apple-only targets compile to empty modules on Linux: CaptureCompass, CaptureRoomPlan, CaptureUI
  (`ios/Packages/CaptureCore/Package.swift:10-16`), ChapterUI (`ios/Packages/ChapterUI/Package.swift:17-21`),
  FieldKitUI (`ios/Packages/FieldKit/Package.swift:8-10`).
- The repo's Debug app bundles the UI-test fixture `fixtures/generated/box-room/package` as a
  resource. Release excludes it (`ios/project.yml:57-60,70-74`). The PM app needs it only if it
  keeps the replay UI test (section 15).

## 5. What to port from the App target

Already in packages, add them and do not port:

- **AppCore** (Foundation only): `AppConfiguration` / `ConfigurationLoader`, `LaunchMode`,
  `VisitFlow`, `VisitStore`, `CaptureLibrary`, `OverviewBuilder`, `VisitPackageBuilder`,
  `RevisionBuilder`, `UploadCoordinator`, `StationStatusCache`, `StationUploadService`, the
  Debug-only stubs `UITestStation` and `UITestBlobTransport` (`ios/App/README.md:42`).
- **CaptureCore**: `CaptureFlowModel`, `DeviceGate`, `ReplaySession`, compass maths;
  **CaptureRoomPlan**: `LiveCaptureSession`, `CaptureSessionPreview`, `DeviceCapabilities.current()`;
  **CaptureCompass**: `CompassService`; **CaptureUI**: `CapturesHomeScreen`, `NewCaptureScreen`,
  `ScanSetupScreen`, `LiveScanScreen`, `CaptureOverviewScreen`.
- **FieldKit**: the photo step (`PhotoCaptureFlowView`, `CameraEngine`), `FieldControlsView`,
  `BeforeYouLeaveView`.

In the App target (`ios/App/Sources/App/`), port into the PM app:

| File                                                      | Lines | What it is                                                                                                          | Note                                                                                          |
| --------------------------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `ChapterCaptureApp.swift`                                 | 47    | `@main`: `ChapterFonts.register()`, `ChapterAppearance.apply()`, `.onOpenURL` to MSAL, `didBecomeActive()`          | Replace with a capture entry point in the PM app. Do not call `apply()` app-wide (section 6). |
| `AppDelegate.swift`                                       | 242   | `BackgroundUploads`, `PackageRouter`, `VerdictNotifier`, `VerdictRefresh` (BGAppRefreshTask), notification delegate | Merge into the PM app's AppDelegate (section 8).                                              |
| `AppModel.swift`                                          | 305   | Composition root: services, configuration, MSAL, sign-in/out, upload coordinators, resume at launch                 | Where the PM app plugs in its token provider and configuration.                               |
| `HomeModel.swift`                                         | 331   | `AppRoute` and the Captures home's navigation state                                                                 | Port as is.                                                                                   |
| `VisitModel.swift`                                        | 910   | One open visit: screen models, `visit.json`, package build, seal, revision                                          | Port as is.                                                                                   |
| `CompassPhotoHeading.swift`                               | 29    | Photo "Looking toward" from the compass                                                                             | Port as is.                                                                                   |
| `Auth/EntraSignIn.swift`                                  | 142   | MSAL app, interactive and silent token, sign-out, `EntraTokenProvider`                                              | Keep, or replace with the PM app's sign-in (section 10).                                      |
| `Views/AppNavigation.swift`                               | 380   | The one `NavigationStack`, routes, live-scan `fullScreenCover`, alerts                                              | Port; present it from the PM app's entry point.                                               |
| `Views/RootView.swift`                                    | 145   | Not configured / sign-in / home; `WindowTint` sets `window.tintColor`                                               | Adapt (section 6).                                                                            |
| `Views/PackageScreens.swift`                              | 995   | Package ready, Package status, Verdict received, Revision n                                                         | Port.                                                                                         |
| `Views/FloorplanView.swift`                               | 318   | The colour Floorplan on the phone (stays as approved)                                                               | Port unchanged.                                                                               |
| `Views/ScanViewer.swift`                                  | 353   | One floor's 3D model and plan (RoomPlan, SceneKit)                                                                  | Port.                                                                                         |
| `Views/ModelStyle.swift`                                  | 2,797 | Restyles the RoomPlan USDZ in SceneKit                                                                              | Port. **Fails to compile on Xcode 26.3** (section 2).                                         |
| `Debug/UITest*.swift`, `Debug/FieldTestEnvironment.swift` | ~610  | UI-test replay and field-test modes, `#if DEBUG`                                                                    | Optional; Debug only (`ios/project.yml:72-74`).                                               |

Screen flow: Captures home → New capture → What are you scanning? → Live scan → Photos → Capture
overview → Field controls / Before you leave → Package ready → Package status → Verdict received.
"Add to this capture" starts Revision n (`ios/App/README.md:6-12`).

There is **no entry point that takes a preselected HUB project**. The operator picks the HUB
project on New capture (`VisitModel.swift:221-236`). **Not built:** a `startCapture(dealId:)`
entry, if the PM app wants to open capture from one of its own project screens.

## 6. Host-wide side effects to handle

Harmless in a standalone app; in the PM app they touch every screen.

1. **Navigation bar appearance is set for the whole app.** `ChapterAppearance.apply()` sets
   `UINavigationBar.appearance()` (`ios/Packages/ChapterUI/Sources/ChapterUI/ChapterAppearance.swift:19-29`).
   **Recommendation:** do not call it. Apply `ChapterAppearance.navigationBarAppearance()`
   (public, `ChapterAppearance.swift:39`) only to the capture flow's navigation bar. No scoped API
   exists in ChapterUI yet (**Not built**).
2. **Window tint.** `RootView`'s `WindowTint` sets `window.tintColor` to ink
   (`ios/App/Sources/App/Views/RootView.swift:21,35-65`). **Recommendation:** use `.chapterRoot()`
   on the capture root only (`ChapterAppearance.swift:79`), or restore the tint when capture closes.
3. **Light mode is forced app-wide** (`UIUserInterfaceStyle = Light`,
   `ios/App/Resources/Info.plist:78-79`). ChapterTheme colours are fixed RGB values. The live scan
   forces dark itself (`CaptureUI/LiveScanScreen.swift:47`). **Recommendation:** set
   `.preferredColorScheme(.light)` or `overrideUserInterfaceStyle = .light` on the capture
   flow's hosting controller only.
4. **Portrait only** (`Info.plist:64-67`); the compass sets `headingOrientation = .portrait`
   (`ios/Packages/CaptureCore/Sources/CaptureCompass/CompassService.swift:57`).
   **Recommendation:** lock the capture flow to portrait if the PM app allows landscape.
5. **One notification delegate.** `UNUserNotificationCenter.current().delegate = self`
   (`ios/App/Sources/App/AppDelegate.swift:199`). Verdict notifications have category `"verdict"`
   and userInfo key `"packageId"` (`ios/App/AppCore/Sources/AppCore/StationStatusCache.swift:163-168`).
   **Recommendation:** if the PM app has its own delegate, route `"verdict"` notifications from it
   to `PackageRouter`.
6. **Fonts.** `ChapterFonts.register()` registers Inter-Regular and Inter-SemiBold for the process.
   It is idempotent and harmless (`ios/Packages/ChapterUI/Sources/ChapterUI/ChapterFonts.swift:27-53`).
   Do not add the fonts to `UIAppFonts`; that "cannot see a package's bundle"
   (`ChapterFonts.swift:7-53`).
7. **Folder names are generic.** `Application Support/Visits`, `Application Support/StationCache`,
   `Application Support/FieldTestVisits` (`ios/App/Sources/App/AppModel.swift:87,98,123,146`) and
   `Caches/upload-scratch` (`AppDelegate.swift:20-23`). **Recommendation:** put them under a
   `ChapterCapture/` folder so they cannot collide with the PM app's folders.
8. **The capture record carries the host's version.** It reads `Bundle.main` through
   `CaptureRecord.AppInfo.from(bundle:)`, else `0.0.0` / `0` (`VisitModel.swift:118-120`). The schema
   wants `^[0-9]+\.[0-9]+\.[0-9]+$` (`contract/schema/capture-record.schema.json:110-121`). The PM
   app's `CFBundleShortVersionString` must be three dotted numbers.
9. **Hard-coded identifiers** that do not follow the host's bundle id:
   - `com.hellochapter.capture.package-upload`: background `URLSession` (`AppDelegate.swift:16`)
   - `com.hellochapter.capture.verdict-refresh`: BGTask (`StationStatusCache.swift:204`, `Info.plist:51`)
   - log subsystems `com.hellochapter.capture` and `com.hellochapter.ChapterUI`
     (`CompassService.swift:29`, `LiveCaptureSession.swift:91`, `ChapterFonts.swift:35`)

   They work in another app as they are. To rename them, change the code and the Info.plist
   together.

## 7. Info.plist keys and exact strings

From `ios/App/Resources/Info.plist`. The repo writes the plist by hand
(`GENERATE_INFOPLIST_FILE: NO`, `ios/project.yml:65-66`).

| Key                                                                  | Value in the repo                                                                                                       | Line  | In the PM app (phase 3 update)                                                                                          |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ----- | ----------------------------------------------------------------------------------------------------------------------- |
| `NSCameraUsageDescription`                                           | `Chapter Capture uses the camera for site photos and the LiDAR room scan.`                                              | 41-42 | Add. Name the PM app instead of "Chapter Capture" (**Recommendation**). If the PM app already has one, cover both uses. |
| `NSLocationWhenInUseUsageDescription`                                | `Chapter Capture uses your location only to turn the compass into true north on the plans. Your location is not saved.` | 43-44 | Add, same rule. Keep it specific; the code matches it (section 8).                                                      |
| `UIBackgroundModes`                                                  | `fetch`                                                                                                                 | 45-48 | Add, or drop the verdict refresh (section 8).                                                                           |
| `BGTaskSchedulerPermittedIdentifiers`                                | `com.hellochapter.capture.verdict-refresh`                                                                              | 49-52 | Add with `fetch`.                                                                                                       |
| `CFBundleURLTypes`                                                   | name `$(PRODUCT_BUNDLE_IDENTIFIER).msal`, scheme `msauth.$(PRODUCT_BUNDLE_IDENTIFIER)`                                  | 23-33 | Add if the PM app does not already register the MSAL scheme.                                                            |
| `LSApplicationQueriesSchemes`                                        | `msauthv2`, `msauthv3`                                                                                                  | 34-38 | Add with MSAL.                                                                                                          |
| `UIRequiredDeviceCapabilities`                                       | `arkit`                                                                                                                 | 53-56 | **Do not add** (section 12).                                                                                            |
| `UIUserInterfaceStyle`                                               | `Light`                                                                                                                 | 78-79 | Do not add app-wide (section 6).                                                                                        |
| `UISupportedInterfaceOrientations`                                   | `UIInterfaceOrientationPortrait`                                                                                        | 64-67 | Keep the PM app's own; lock the capture flow (section 6).                                                               |
| `UIApplicationSceneManifest` → `UIApplicationSupportsMultipleScenes` | `false`                                                                                                                 | 57-61 | Keep the PM app's own.                                                                                                  |
| `CFBundleDisplayName`                                                | `Chapter Capture`                                                                                                       | 7-8   | Keep the PM app's own.                                                                                                  |
| `ChapterEntraClientID`                                               | `$(CHAPTER_ENTRA_CLIENT_ID)`                                                                                            | 68-69 | Optional: the PM app can pass values in code instead (section 10).                                                      |
| `ChapterEntraTenantID`                                               | `$(CHAPTER_ENTRA_TENANT_ID)`                                                                                            | 70-71 | Same.                                                                                                                   |
| `ChapterStationAPIScope`                                             | `$(CHAPTER_STATION_API_SCOPE)`                                                                                          | 72-73 | Same.                                                                                                                   |
| `ChapterStationURL`                                                  | `$(CHAPTER_STATION_URL)`                                                                                                | 74-75 | Same.                                                                                                                   |
| `ChapterFieldTest`                                                   | `$(CHAPTER_FIELD_TEST)`                                                                                                 | 76-77 | Debug only; Release forces `NO` (`ios/App/Config/Release.xcconfig:3-4`).                                                |

Keys the repo does **not** have:

- No `NSMotionUsageDescription`. The compass uses `CMMotionManager` device motion and
  `CLLocationManager` (`CompassService.swift:31-32`). **Verify:** device-motion updates need no
  motion usage string; only activity and pedometer data do.
- No `NSPhotoLibrary*` key. Photos come from the app's own `AVCapturePhotoOutput` camera
  (`ios/Packages/FieldKit/Sources/FieldKitUI/CameraEngine.swift:34,44-54`). Nothing is saved to
  the photo library.
- No `NSUserNotificationsUsageDescription`; notifications are local only.
- No `ITSAppUsesNonExemptEncryption`. **Verify:** without it App Store Connect asks the
  export-compliance question at every upload.

## 8. Permissions, background work and entitlements

**Permissions and when they are asked:**

| Permission    | Asked                                                                                                                                                                          | Source                                                                               |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| Camera        | At the photo step (`CameraEngine.requestAccess()`); RoomPlan uses the camera for the scan                                                                                      | `CameraEngine.swift:44-47`                                                           |
| Location      | Only when status is `.notDetermined` (`CompassService.requestAuthorization()`). Accuracy `kCLLocationAccuracyThreeKilometers`. No location value is written to any file or log | `CompassService.swift:58,78-80`; `ios/App/README.md:24-26`; `LocationNotStoredTests` |
| Notifications | After the first seal; local "Verdict: {Word}" notifications only                                                                                                               | `AppDelegate.swift:65-98`, `VisitModel.swift:694`                                    |

**Background work:**

- **Uploads:** PackageKit's `BackgroundBlobTransport`, one instance for the app's lifetime,
  `URLSessionConfiguration.background(withIdentifier: "com.hellochapter.capture.package-upload")`,
  `isDiscretionary = false`, `sessionSendsLaunchEvents = true`
  (`ios/Packages/PackageKit/Sources/PackageTransport/BackgroundBlobTransport.swift:34-43`).
  The host's AppDelegate must forward
  `application(_:handleEventsForBackgroundURLSession:completionHandler:)` to it
  (`AppDelegate.swift:12-27,204-218`). Sealed packages the station has not confirmed are found at
  launch and resumed (`AppModel.swift:237-241`). A background `URLSession` needs no background mode.
- **Verdict refresh:** `BGAppRefreshTask` `com.hellochapter.capture.verdict-refresh`, at most
  every 15 minutes (`StationStatusCache.swift:204-206`). Registered in `didFinishLaunching`
  (`AppDelegate.swift:135,195-202`), only when Info.plist permits the id (`AppDelegate.swift:116-122`).
  This is the only user of `UIBackgroundModes` `fetch`.
- **Foreground:** `didBecomeActive()` retries uploads and sends next-revision notices
  (`AppModel.swift:225-230`).
- **Recommendation:** if the PM app does not want `fetch`, drop the BGTask and the key; verdicts
  then refresh in the foreground only.

These hooks must run when the capture UI is not open, for example after iOS relaunches the app in
the background for upload events. Put them in the PM app's AppDelegate, not in the capture screens.

**Entitlements** (`ios/App/Resources/App.entitlements:5-8`): `keychain-access-groups` =
`$(AppIdentifierPrefix)com.microsoft.adalcache`, MSAL's default token cache group
(`ios/App/Sources/App/Auth/EntraSignIn.swift:17-19`). Nothing else: no `aps-environment`, App
Groups or associated domains.

## 9. Capture OFF for the first submission, ON in the update

**No switch exists in the repo.** A search for `featureFlag`, `FeatureFlag`, `captureEnabled`,
`CAPTURE_ENABLED`, `SPACE_CAPTURE` and `ENABLE_CAPTURE` finds nothing. `CHAPTER_FIELD_TEST` and
`LaunchMode` are Debug test modes, not a release switch. The mechanism must be chosen and, for
option B, built.

**Option A (Recommendation): the phase 1 binary contains no capture code at all.**

- Do the capture integration on a separate PM app branch (for example `feature/space-capture`).
  Merge it only after Apple approves phase 1.
- The phase 1 binary then has: no capture packages linked, no capture entry point, no capture
  camera or location strings, no `fetch` mode or capture BGTask id, no capture MSAL URL scheme or
  keychain group (unless the PM app already uses MSAL), no capture background `URLSession`.
- Nothing to build. The update binary goes through App Review on its own.

**Option B: one branch, two variants (Not built).** If the team wants one branch that builds both,
add a build-time switch. Example: an xcconfig setting `CHAPTER_SPACE_CAPTURE = NO|YES` that
selects all of these together:

- the Swift condition (`SWIFT_ACTIVE_COMPILATION_CONDITIONS` gets `CHAPTER_SPACE_CAPTURE`) around
  the entry point and the AppDelegate hooks;
- which Info.plist and entitlements file the target uses;
- whether the capture package products are linked (a separate target or scheme).

`#if` around the entry point alone still links the frameworks. **Verify:** Apple's upload checks
can then ask for purpose strings for APIs the binary references.

**Do not** ship capture switched off and turn it on remotely after approval. **Verify:** App Store
Review Guideline 2.3.1 forbids hidden, dormant or undocumented features.

**Check of the phase 1 binary** (Recommendation): before upload, confirm the built `.app` has none
of the capture keys of section 7 in its Info.plist and none of the capture frameworks or package
products (`CaptureCore`, `CaptureRoomPlan`, `PlanExport`, `PackageKit`, `StationClient`, ...).

## 10. Sign-in and station settings

**Settings** (`ios/App/Config/Base.xcconfig:1-18`, `ios/App/README.md:76-91`, validation in
`ios/App/AppCore/Sources/AppCore/AppConfiguration.swift`):

| Build setting               | Info.plist key           | Rule                                                                                                                                        |
| --------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `CHAPTER_ENTRA_CLIENT_ID`   | `ChapterEntraClientID`   | a UUID (`AppConfiguration.swift:104-107`)                                                                                                   |
| `CHAPTER_ENTRA_TENANT_ID`   | `ChapterEntraTenantID`   | a UUID; domain tenants refused (`:109-112,152-156`)                                                                                         |
| `CHAPTER_STATION_API_SCOPE` | `ChapterStationAPIScope` | `api://…/…` or `https://…/…` (`:114-118,158-167`)                                                                                           |
| `CHAPTER_STATION_URL`       | `ChapterStationURL`      | https with a host, no query; `http` only for `localhost` and `127.0.0.1`; the client appends `/v1` (`:120-131`; `StationClient.swift:8-31`) |
| `CHAPTER_FIELD_TEST`        | `ChapterFieldTest`       | `YES`/`TRUE`/`1` selects field-test mode, Debug only (`LaunchMode.swift:49-53`)                                                             |

- Committed values are placeholders (`__SET_ENTRA_CLIENT_ID__`, `__SET_ENTRA_TENANT_ID__`,
  `__SET_STATION_API_SCOPE__`, `__SET_STATION_URL__`, `Base.xcconfig:6-9`). A missing or
  placeholder value shows "App is not configured" and sends nothing; there is no fallback station
  (`AppModel.swift:123-130`, `RootView.swift:67-93`).
- `ConfigurationLoader.load(_:)` takes a closure (`AppConfiguration.swift:83-84`). The PM app can
  supply the values from its own configuration without the `Chapter*` Info.plist keys.
- **Recommendation:** one value set per build configuration: Debug and TestFlight builds point at
  the training station, the App Store build at the production station.
- The scope name is not fixed in the repo. Examples differ: `api://<station app id>/Capture.Upload`
  in iOS (`AppConfiguration.swift:11`) and `api://<station-app-id>/access_as_user` in web
  (`web/lib/config.ts:38`). **Input needed:** the real scope of the station app registration.

**MSAL / Entra** (`ios/App/Sources/App/Auth/EntraSignIn.swift`):

- Authority `https://login.microsoftonline.com/<tenant id>` (`AppConfiguration.swift:55-59`).
  `MSALPublicClientApplicationConfig(clientId:, redirectUri: nil, authority:)`; with
  `redirectUri: nil`, MSAL uses `msauth.<bundle id>://auth` (`EntraSignIn.swift:28-35`).
- The standalone app's registered redirect URI is `msauth.com.hellochapter.capture://auth`
  (`ios/App/README.md:93`). **In the PM app it is `msauth.<PM app bundle id>://auth`.** Add it to
  the Entra app registration (**Input needed**: PM bundle id).
- The redirect returns through `.onOpenURL` → `MSALPublicClientApplication.handleMSALResponse(url,
sourceApplication: nil)` (`ChapterCaptureApp.swift:26-29`, `EntraSignIn.swift:38-40`).
- The token seam is `AccessTokenProvider.accessToken(forceRefresh:)`
  (`ios/Packages/StationClient/Sources/StationClient/AccessTokenProvider.swift:15-20`). A 401 gets
  one `forceRefresh: true` retry (`ios/Packages/StationClient/README.md:11`). `EntraTokenProvider`
  implements it (`EntraSignIn.swift:135-142`).
- Tokens stay in MSAL's Keychain cache; the app never writes or logs a token. Sign-out removes
  every MSAL account and clears the project cache; it deletes no file (`ios/App/README.md:94-98`).

**The station accepts only Entra v2.0 access tokens** (RS256, configured issuer, audience and
tenant; roles from the `roles` claim; `station/api/src/core/auth.ts:1-10,27,88-127`). Roles the
phone needs:

| Call                           | Roles                     | Source                                                |
| ------------------------------ | ------------------------- | ----------------------------------------------------- |
| HUB project list and project   | `capture`, `bim`, `admin` | `station/api/src/routes/projects/index.ts:43,55`      |
| Upload session, complete, seal | `capture`, `admin`        | `station/api/src/routes/uploads/index.ts:85`          |
| Read packages and verdicts     | `capture`, `bim`, `admin` | `station/api/src/routes/packages/index.ts:34`         |
| Next-revision notice           | `capture`, `admin`        | `station/api/src/routes/packages/next-revision.ts:29` |

**Every PM user who captures needs the `capture` app role** on the station app registration
(**Input needed**: who gets it).

- **Recommendation:** if the PM app already signs in with Entra/MSAL, reuse its
  `MSALPublicClientApplication`: implement `AccessTokenProvider` with a silent token for the
  station scope and drop `EntraSignIn`'s own sign-in screen. Use one MSAL version (the repo pins
  2.16.0).
- If the PM app does not use Entra, capture still needs an Entra sign-in, because the station
  accepts nothing else.

## 11. How the capture talks to the station

- `StationClient` (alias `StationAPI`) is written by hand from `contract/openapi/station.yaml`.
  It has 13 operations, checked against the document by `OpenAPIParityTests`
  (`ios/Packages/StationClient/README.md:7-26`). Base path `/v1`; every call except `/health`
  sends the bearer token. Ephemeral session, no redirects, nothing logged, SAS URLs redacted.
- The phone calls two hosts: the station host, and the Azure Blob host through the SAS upload
  links the station returns. Up to 8 MiB: Put Blob; larger: Put Block in 8 MiB blocks, then Put
  Block List (`ios/Packages/PackageKit/README.md:46-51`, `PackageCore/BlobTransport.swift:56`).
- Upload state is kept in `<packageId>.upload-state.json` (mode 0600, holds SAS URLs). Nothing is
  deleted from the phone (`ios/Packages/PackageKit/README.md:56-64`).
- The HUB project list is cached offline and used only when the station is unreachable
  (`ios/Packages/StationClient/README.md:14,40-42`). The phone shows `dealId`, `projectName`,
  `address`, `updatedAt`, `projectManagerPhone`
  (`ios/Packages/CaptureCore/Sources/CaptureCore/HubProjects.swift:5-29`).
- A real iPhone needs an HTTPS station; `http` is allowed only for `localhost` and `127.0.0.1`
  (`StationClient.swift:28-31`).
- Contract versions the phone writes: manifest and capture record **1.1.0**. The station must
  accept 1.1.0 before an app that writes it is released ([04, section 9](04-station-and-deploy.md#9-deploy-order)).

## 12. LiDAR and device gating

- `UIRequiredDeviceCapabilities` holds only `arkit` (`Info.plist:53-56`). No key requires LiDAR.
- The runtime gate `DeviceGate.evaluate` fails on `.noLidar`, `.roomPlanUnsupported` and
  `.osTooOld` (`ios/Packages/CaptureCore/Sources/CaptureCore/DeviceGate.swift:55-73`,
  `CaptureRoomPlan/DeviceCapabilities+Current.swift:35-41`). Messages (`DeviceGate.swift:32-41`):
  - "This device has no LiDAR scanner. Chapter Capture needs an iPhone Pro or iPad Pro with LiDAR."
  - "This device does not support Apple RoomPlan, which Chapter Capture needs to scan rooms."
  - "Update to iOS {n} or later to use Chapter Capture."
- On New capture, Continue is disabled with "This phone cannot scan"
  (`CaptureCore/CaptureFlowModel.swift:213-214,294`). `LiveCaptureSession.start` throws
  `.deviceNotSupported`, and `.tooHot` when the thermal state is serious or critical
  (`CaptureRoomPlan/LiveCaptureSession.swift:106-114`). The Captures home and earlier packages
  stay usable on a phone without LiDAR.
- **Do not add `UIRequiredDeviceCapabilities: arkit` to the PM app.** It would stop the PM app
  installing on devices without ARKit. **Verify:** App Store Connect also limits adding required
  device capabilities in an update of a published app.
- **Recommendation:** show or explain the capture entry point with
  `DeviceGate.evaluate(DeviceCapabilities.current()).isSupported`. The messages name "Chapter
  Capture"; change them if the PM app should name itself.

## 13. App Store review for the update (phase 3)

1. **Sign-in is required.** Every capture screen is behind Entra sign-in with the `capture` role.
   **Verify:** App Review needs working demo credentials. **Input needed:** a reviewer account
   with the `capture` role on the production station, and a production HUB project it can see.
2. **Reviewers may not have a LiDAR device.** Without LiDAR or RoomPlan, Continue says "This phone
   cannot scan". **Recommendation:** say in the review notes that capture needs an iPhone Pro or
   iPad Pro with LiDAR, and attach a screen recording of a real scan.
3. **Location purpose.** The string says location is used only for true north and not saved. The
   code matches: 3 km accuracy, nothing stored (`CompassService.swift:58`, `ios/App/README.md:24-26`).
4. **Background mode `fetch`.** Used only by the verdict refresh. Explain it in the review notes,
   or drop it (section 8).
5. **No privacy manifest in the repo** (no `PrivacyInfo.xcprivacy`). The code reads file
   timestamps: `contentModificationDateKey` (`ios/App/AppCore/Sources/AppCore/VisitStore.swift:262,282`,
   `CaptureLibrary.swift:155`, `ios/App/Sources/App/Views/ScanViewer.swift:58`) and
   `creationDateKey` (`VisitStore.swift:295`). **Verify:** file timestamps are a "required
   reason" API; the PM app's privacy manifest must declare it. Check whether MSAL 2.16.0 ships its
   own manifest.
6. **App Privacy labels.** The capture record holds `operatorName` and `operatorUserId` (the Entra
   object id) (`VisitModel.swift:221-225`, `EntraSignIn.swift:113-116`), device model, OS, site
   photos, scans and the HUB project address. No location. Declare these in App Store Connect
   (**Input needed**: the account holder answers).
7. **Encryption.** `ITSAppUsesNonExemptEncryption` is not set. **Verify:** HTTPS-only use is
   normally exempt; the account holder must answer.
8. **iPad.** If the PM app ships on iPad, the capture screens run there too. The gate allows an
   iPad Pro with LiDAR.
9. **Build.** The update must be built with a release Xcode that compiles `ModelStyle.swift`
   (section 2).
10. **Station first.** The production station must accept manifest and capture record 1.1.0 before
    the update is released, and must be up for App Review.

## 14. Native, React Native or Flutter host

The repo has no React Native or Flutter code. The capture is native Swift because:

- all capture UI is SwiftUI (CaptureUI, FieldKitUI, ChapterUI, the App views);
- the scan uses RoomPlan and ARKit in `CaptureRoomPlan` (`#if canImport(RoomPlan)`,
  `ios/Packages/CaptureCore/Package.swift:13-14`);
- the compass uses CoreLocation and CoreMotion; sign-in uses MSAL (Objective-C);
- uploads use a background `URLSession` that iOS relaunches the app for.

**Native Swift/SwiftUI or UIKit PM app:** add the packages (section 4), port the App files
(section 5), present `AppNavigation` full screen from a PM app entry point (in UIKit, through a
`UIHostingController`), and merge the AppDelegate hooks (section 8).

**React Native or Flutter PM app (Recommendation):**

- A native iOS module presents the whole capture flow in a `UIHostingController`, full screen,
  portrait, light.
- A small API to the JS or Dart side: `startCapture()` (optionally with a HUB `dealId`, which is
  **Not built**); a token callback that implements `AccessTokenProvider`, or MSAL kept on the
  native side; events such as "package sealed", "uploaded", "verdict".
- The iOS host's AppDelegate keeps `handleEventsForBackgroundURLSession`, the BGTask registration
  in `didFinishLaunching`, the notification delegate and MSAL's `handleMSALResponse`. These must
  work while the JS or Dart engine is not running.
- The capture code is Swift packages only, with no CocoaPods podspec. **Verify:** in React Native,
  add the local Swift packages to the iOS project in Xcode beside the Pods workspace; check the
  Flutter version's Swift Package Manager support before relying on it.

**Input needed:** the PM app's stack decides which of these applies.

## 15. Testing inside the PM app

- Keep running the package tests from this repo ([01, section 7.2](01-repo-and-mac-setup.md#72-package-tests)).
  Add them to the PM app's CI if the packages are vendored.
- The replay UI test (`ReplayFlowUITests`) and its launch options (`-ChapterUITestReplay box-room`,
  `-ChapterUITestCompass`, `-ChapterUITestVerdict`, ...) live in the standalone app's Debug build
  (`ios/App/README.md:129-150`, `ios/App/UITests/ReplayFlowUITests.swift:20-24`). Port
  `Debug/UITest*` and the fixture resource to keep this test in the PM app, or keep the standalone
  app as the reference build.
- The field-test mode (`CHAPTER_FIELD_TEST = YES`) runs a whole visit on a phone with no station
  ([01, section 7.3](01-repo-and-mac-setup.md#73-field-test-build-for-a-real-iphone)).
- Device tests D0 and D1 of the compass are still pending (`docs/qa/compass-device-tests.md:9-12`).
  D1 decides whether `CompassMath.captureFrameYaw` is right before the plan sheet and the spatial
  report rely on `heading`. Run them on a LiDAR iPhone before phase 3.

## 16. Acceptance checklist

**Phase 1 binary (no capture):**

- [ ] The PM app version for review contains no capture code, packages, entry point or capture
      Info.plist keys (section 9).
- [ ] The capture integration lives on its own branch (or behind the option B switch, if built).
- [ ] Apple approved the version.

**Phase 3 update (capture on):**

- [ ] `ModelStyle.swift` compiles on the release Xcode used for the App Store build; CI pins moved.
- [ ] PM app deployment target is iOS 17.0 or later.
- [ ] All packages of section 4 linked; App files of section 5 ported; the app builds in Release.
- [ ] Navigation bar, tint and colour scheme of the rest of the PM app are unchanged (section 6).
- [ ] Info.plist keys added as in section 7, with usage strings that name the PM app; no `arkit`
      required capability.
- [ ] AppDelegate forwards background `URLSession` events, registers the BGTask (if kept) and
      routes `"verdict"` notifications (section 8).
- [ ] Entra redirect URI `msauth.<PM bundle id>://auth` registered; sign-in returns a station token
      with the `capture` role; 401 retry works (section 10).
- [ ] Debug/TestFlight build against the training station: HUB training projects listed; a full
      visit scanned on a LiDAR phone, sealed, uploaded (also after the app is closed during
      upload), verdict received, notification shown.
- [ ] A phone without LiDAR shows the capture entry as unavailable, and the rest of the PM app
      works.
- [ ] Capture record `app.version` is the PM app version (three dotted numbers).
- [ ] Privacy manifest, App Privacy answers, export compliance and review notes ready (section 13).
- [ ] Production station live with v2 (manifest and capture record 1.1.0 accepted) before release.
- [ ] After approval: one real visit in production reaches a verdict, and the spatial report and
      plan files appear in the HUB deal's Files tab (the gate for phase 4).
