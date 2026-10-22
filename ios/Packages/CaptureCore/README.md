# CaptureCore

The scan core of Chapter Capture (spec F2, design v2): Apple RoomPlan and ARKit LiDAR behind one
session API, raw originals kept unchanged, the adapter into the contract `CaptureModel`, the
compass reading of each floor, and the capture screens (build specs phone-capture §3, §5 and
compass §3, §5 with the completeness critique).

```sh
swift test --package-path ios/Packages/CaptureCore                          # Linux or macOS
swift test --package-path ios/Packages/CaptureCore --filter MappingTests
# Real RoomPlan exports kept on this machine (never committed): decode, map, validate each one
CHAPTER_REAL_ROOMPLAN_DIR="/path/to/exports" swift test --package-path ios/Packages/CaptureCore --filter WalkthroughScanTests
```

## Targets

| Target                | Builds on             | Contents                                                                                                                                         |
| --------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CaptureModelMapping` | Linux, macOS, iOS     | Codable mirror of RoomPlan's JSON, transforms, room polygons, opening-to-wall assignment, `CaptureModelMapper`                                   |
| `CaptureCore`         | Linux, macOS, iOS     | `CaptureSession` protocol, `ReplaySession`, `DeviceGate`, raw-originals writer and debug export, capture-record form logic, `CaptureFlowModel`, the compass reading (`Compass/`), `TrackingMonitor`, `CaptureText`, `DeviceNames`, the screen states `CapturesHomeState` and `CaptureOverviewState` |
| `CaptureCompass`      | iOS only (CoreMotion) | `CompassService` (the app's one location and motion manager) and `CompassDeviceCheck` (device test D0)                                           |
| `CaptureRoomPlan`     | iOS only (RoomPlan)   | `LiveCaptureSession` (RoomPlan + ARKit, tracking, compass pairing), `RoomPlanAdapter`, `DeviceCapabilities.current()`, `LiveCameraPreview`, `CaptureSessionPreview` |
| `CaptureUI`           | iOS only (SwiftUI)    | The capture screens on ChapterUI: `CapturesHomeScreen`, `NewCaptureScreen`, `ScanSetupScreen`, `LiveScanScreen`, `CaptureOverviewScreen`; `ChapterTokens` (a façade over `ChapterTheme`) |
| `CaptureTestSupport`  | everywhere, test only | Fixture paths and a JSON Schema subset validator; not a product                                                                                  |

### How the Apple-only targets are guarded

There is no `.apple-only` marker at the package root. `scripts/swift-test.sh` skips a whole package
that has one, and the mapping, schema and capture-record tests must run on Linux. Instead:

- Every source file of `CaptureCompass`, `CaptureRoomPlan` and `CaptureUI` is wrapped in
  `#if canImport(CoreMotion) …`, `#if canImport(RoomPlan) && canImport(ARKit) && os(iOS)` or
  `canImport(SwiftUI)`, so the target compiles to an empty module on Linux and macOS. So are the
  test targets `CaptureUITests` and `CaptureCompassTests`.
- Each of those targets carries an `.apple-only` marker file in its own source folder (excluded
  from the build in `Package.swift`) as the documented signal that it needs Apple frameworks.
- The macOS runner (`.github/workflows/ios.yml`) builds the whole package for iOS, scheme
  `CaptureCore-Package`, and runs every test on the simulator, including `CaptureRoomPlanTests`.
- `CaptureCompass`, `CaptureRoomPlan` and `CaptureUI` use Swift language mode 5: Core Location,
  RoomPlan and ARKit delegates are Objective-C protocols with non-Sendable arguments.

## The capture screens

The screens take state and call actions; they hold no disk access, so every state is drawn from
fixtures in the snapshot tests. The app's NavigationStack hosts them (phone-capture §3.0):

| Screen | API | Driven by |
| --- | --- | --- |
| Captures home (2b-0) | `CapturesHomeScreen(state:actions:)` | `CapturesHomeState` (rows of critique R-28 via `Row.inProgress` / `Row.sealed`), built by the app's `CaptureLibrary` |
| New capture (2b-1, 1b, 1c) | `NewCaptureScreen(model:onDiscard:)` | `CaptureFlowModel` step 1: `continueBlocker`/`continueTitle`, `offlineBanner`, `addressToggleChanged(isOn:)`, `addressAlert(_:dial:discard:)` with the words of `AddressDifferentAlert` |
| What are you scanning? (2b-2) | `ScanSetupScreen(model:)` | step 2: `startScanBlocker`, `existingAreaKeys` (the "Floor N" suggestion and the duplicate check; the host sets it when adding a floor), `compassPrecheck`, `readCompassAgain()`, `openLocationSettings()`; no compass row when `hasCompass` is false |
| Live scan (2b-3, 3b) | `LiveScanScreen(model:preview:)` | `livePhase` (scanning, paused, tracking lost, stopped), `liveCompass`, `recordingStatus`, `restartFloor()` |
| Capture overview (2b-4) | `CaptureOverviewScreen(state:actions:)` | `CaptureOverviewState`, built by the app's `OverviewBuilder` |

`CaptureFlowView` still hosts step 1, step 2 and the live scan in a NavigationStack of its own for
the v1 app shell; it goes once the app's navigation hosts the screens.

## The compass of each floor

- **Pre-check** (step 2, never stored): `CompassProviding.precheck()` collects `CLHeading` for 2 s
  (`PrecheckReading`); the row shows it with the words of `CompassPhoneText`.
- **Scan-start reading** (stored): `LiveCaptureSession` pairs every 4 Hz frame with the Core
  Motion sample within 25 ms (`CompassService.motionRing`), gates it (`CompassPair.dropReason`:
  tracking, turning, gravity checks, heading age and accuracy, calibration) and feeds
  `HeadingWindow`: windows of 8 pairs, the consistency test, the best window, the 30 s start
  period. At Finish floor `FrameCheck` measures φ and `CaptureFlowModel.finishFloor()` writes
  `CaptureSessionResult.compass` into the capture with `setCompass`. No API takes a heading from
  the screens.
- **A reading or an issue**: every capture scanned with the compass carries the four reading
  fields or `headingIssue`, never neither. `HeadingWindow` gives `unavailable` only when the
  phone has no usable compass (`markUnavailable()`), `not_calibrated` when the pairs never had a
  valid heading accuracy or a calibrated field, and `rejected` otherwise: the windows failed the
  consistency test, the pairs never made a window, or no motion sample was ever paired with a
  frame (the readings could not be matched to the scan). A session that does not read the
  compass at all (a `LiveCaptureSession` without a compass service, a replay without a compass
  script) returns `.none(issue: nil)` and the capture carries no compass field: in a capture
  record 1.1.0 that is a capture scanned without the compass, which the station's
  `orientation.compass` does not grade (Q-B), like a floor carried over from an older revision.
  No issue is made up for it.
- **Tests**: `FakeCompass` scripts `verified` (212.4° ±8 true), `approximate` (±12 magnetic) and
  `none` (not calibrated, in the pre-check and the scan), for the pre-check,
  `ReplaySession(compass:)` and the photo camera (85° → "E"); `-ChapterUITestCompass` in the app
  selects it. Device tests D0 and D1 are in `docs/qa/compass-device-tests.md`.

## Tracking lost

`TrackingMonitor` turns ARKit's tracking state into `TrackingStatus`: lost after 1.0 s of
`notAvailable` or relocalizing, or 3.0 s of any limited state; normal again after 0.5 s. While a
frame is not tracked normally nothing is sampled (depth, pose, mesh), so "Recording paused" on the
live scan is true; scans with tracking trouble have fewer depth samples, as intended.

## Snapshot tests

`Tests/CaptureUITests` draws every screen and state with `ChapterUISnapshotTesting` (402 × 874 pt
at scale 3) and compares with `__Snapshots__/`, recorded on the iPhone 17 Pro simulator with iOS
26.0 (`ChapterSnapshot.referenceSystemVersion`; CI runs them on 26.0 or a point release of it). In package tests the system chrome comes out as ChapterUI's README describes
(no glass back pill, no switch knob) and system alerts are not drawn: the words, button order and
actions of the address-different alert of 1c are unit tests (`AddressDifferentAlert`,
`CaptureFlowModel.addressAlert`), and the drawn alert is checked by the app's UI tests. "Keyboard
up" is drawn with a stand-in of the keyboard's height, as the bare test process has no keyboard.

```sh
cd ios/Packages/CaptureCore
xcodebuild test -scheme CaptureCore-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0'
TEST_RUNNER_RECORD_SNAPSHOTS=1 xcodebuild test -scheme CaptureCore-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -only-testing:CaptureUITests
```

## Showing the camera feed

`CaptureFlowModel.currentSession` is the session of the scan in progress (nil before Start scan and
after Finish floor or Cancel; observed, so views follow it). The host passes
`CaptureSessionPreview` from `CaptureRoomPlan` as the `preview` of `LiveScanScreen`: it shows
RoomPlan's view of the `LiveCaptureSession`'s `ARSession`, and nothing for a `ReplaySession` or no
session, so the camera well stays plain. It only displays the feed; the session runs it.

```swift
import CaptureRoomPlan
import CaptureUI

LiveScanScreen(model: model) { CaptureSessionPreview(model: model) }
```

## From RoomPlan to the CaptureModel

1. The live session encodes `CapturedRoom` (one segment) or `CapturedStructure` (several) with
   RoomPlan's own Codable. Those bytes are the raw original (`roomplan.json`).
2. `RoomPlanDocument` decodes the same JSON on Linux and on the phone.
3. `CaptureModelMapper.map` produces the `CaptureModel`: metres, +Y up, the capture's own frame.

Rules: walls are centrelines at the wall base (local X axis, horizontal part only); ids are numbered
in document order (`room-1`, `wall-1`, `door-1`, `window-1`, `opening-1`, `object-1`); a partition
that two rooms list appears once per room; room outlines come from the floor surface, are wound
counter-clockwise seen from +Y with the first point not repeated, and fall back to chaining the
walls; each door, window and opening gets exactly one parent wall, from `parentIdentifier` or else
the closest wall it lies on (own room first); an opening that fits no wall is an error, not a guess;
output numbers are rounded to a micrometre.

### Walk-through scans

An operator who keeps walking through doorways produces one `CapturedRoom` for the whole
apartment: one floor outline, many walls, and a RoomPlan section (a label and a centre, no shape)
per room it recognized. `WalkthroughSplitter` splits such a capture (one `CapturedRoom`, a floor
outline, two or more sections with a centre) into rooms:

1. The interior walls are clipped to the floor outline; near-duplicates are merged, overshoots
   trimmed, ends welded, and ends that stop short are closed when the gap is short.
2. The planar arrangement of outline and walls is traced into faces (`PlanArrangement`).
3. Each section is a seed. A face with two or more seeds is cut along the cheapest structural cue
   (a ray from a reflex corner, a wall stub extended or bridged); each candidate is checked by
   building the face alone with it. A face without such a cue stays one room.
4. A face without a section is kept as a room when it is enclosed or holds a toilet, bathtub,
   appliance or bed (a closet, a second bathroom); slivers and open faces merge into a neighbour.
5. Walls are split where rooms meet, each opening goes to the piece under its centre with its
   offset from the piece start, and objects go to the room they stand in. A room is as high as the
   tallest wall that bounds it, as measured; a room without walls gets the scan's length-weighted
   median wall height (`heightFromWalls` is then false). Heights are never clamped, so the station
   still flags an implausible scan.

Types come from `RoomTyping` (sections, then objects); a small room without a type is a closet
and a long narrow one a hallway (`inferred`). The splitter is pure Double arithmetic with no trig
and no hash order, so Linux and the phone give the same rooms. Any other capture, or a split that
fails its checks, maps as before (goldens in `Tests/CaptureModelMappingTests/Golden`).

## Raw originals

`RawOriginalsWriter` writes bytes as given and refuses to overwrite. On the phone the folder is
`Original Exports/{areaKey}/{captureId}/`, the package layout:

| File                | Format                                                                |
| ------------------- | --------------------------------------------------------------------- |
| `roomplan.json`     | RoomPlan Codable JSON, unchanged (role `raw_roomplan_json`)           |
| `depth-samples.bin` | "CHDS" v1, confidence of medium or better (role `raw_depth`)          |
| `camera-poses.json` | intrinsics and per-frame camera poses (no manifest role)              |
| `mesh-anchors.bin`  | "CHMA" v1, ARMeshAnchor geometry, input of MeshExport (no role)       |

`CHMA` v1, little endian: header (magic `CHMA`, u32 version, u32 anchor count, u32 reserved), then
per anchor 16 bytes UUID, 16 x f32 transform (column-major), u32 vertex count, u32 triangle count,
vertices (3 x f32 each, anchor frame), triangles (3 x u32 each).

The debug build's "Export raw originals" (`DebugOriginalsExport`) writes exactly the three files of
`fixtures/recorded/README.md`: `raw-roomplan.json`, `depth-samples.bin`, `camera-poses.json`.
