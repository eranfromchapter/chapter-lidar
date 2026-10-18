# CaptureCore

The scan core of Chapter Capture (spec F2): Apple RoomPlan and ARKit LiDAR behind one session API,
raw originals kept unchanged, the adapter into the contract `CaptureModel`, and the capture
screens.

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
| `CaptureCore`         | Linux, macOS, iOS     | `CaptureSession` protocol, `ReplaySession`, `DeviceGate`, raw-originals writer and debug export, capture-record form logic, `CaptureFlowModel`   |
| `CaptureRoomPlan`     | iOS only (RoomPlan)   | `LiveCaptureSession` (RoomPlan + ARKit), `RoomPlanAdapter`, `DeviceCapabilities.current()`, `LiveCameraPreview`, `CaptureSessionPreview`         |
| `CaptureUI`           | iOS only (SwiftUI)    | The three capture screens of the frozen design (`CaptureFlowView`) and the design tokens                                                         |
| `CaptureTestSupport`  | everywhere, test only | Fixture paths and a JSON Schema subset validator; not a product                                                                                  |

### How the Apple-only targets are guarded

There is no `.apple-only` marker at the package root. `scripts/swift-test.sh` skips a whole package
that has one, and the mapping, schema and capture-record tests must run on Linux. Instead:

- Every source file of `CaptureRoomPlan` and `CaptureUI` is wrapped in
  `#if canImport(RoomPlan) && canImport(ARKit) && os(iOS)` (or `canImport(SwiftUI)`), so the target
  compiles to an empty module on Linux and macOS.
- Each of those two targets carries an `.apple-only` marker file in its own source folder (excluded
  from the build in `Package.swift`) as the documented signal that it needs Apple frameworks.
- The macOS runner (`.github/workflows/ios.yml`) builds the whole package for iOS, scheme
  `CaptureCore-Package`, and runs every test on the simulator, including `CaptureRoomPlanTests`.
- `CaptureRoomPlan` and `CaptureUI` use Swift language mode 5: RoomPlan and ARKit delegates are
  Objective-C protocols with non-Sendable arguments.

## Showing the camera feed

`CaptureFlowModel.currentSession` is the session of the scan in progress (nil before Start scan and
after Finish floor or Cancel; observed, so views follow it). The host passes
`CaptureSessionPreview` from `CaptureRoomPlan` as the `preview` of `CaptureFlowView`: it shows
`LiveCameraPreview` of the `LiveCaptureSession`'s `ARSession`, and nothing for a `ReplaySession` or
no session, so the panel keeps the design's dark placeholder. It only displays the feed; the session
runs it.

```swift
import CaptureRoomPlan
import CaptureUI

CaptureFlowView(model: model, preview: { CaptureSessionPreview(model: model) })
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
