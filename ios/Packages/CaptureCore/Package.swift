// swift-tools-version: 6.0
// CaptureCore: the Chapter Capture scan core (RoomPlan + ARKit LiDAR behind one session API),
// the adapter into the contract CaptureModel, and the capture-record screens.
//
// Targets and where they build:
//   CaptureModelMapping  pure Swift + Foundation. Linux, macOS, iOS. Transforms, room polygons,
//                        opening-to-wall assignment. The mapping math is tested here.
//   CaptureCore          Foundation only. Linux, macOS, iOS. CaptureSession protocol, ReplaySession,
//                        device gate, raw-originals writer, capture-record form logic.
//   CaptureCompass       APPLE ONLY (CoreLocation + CoreMotion). The app's one compass
//                        (`CompassService`) and the device-test recorder. Guarded by
//                        `#if canImport(CoreMotion) ... os(iOS)`. Carries the `.apple-only` marker.
//   CaptureRoomPlan      APPLE ONLY (RoomPlan + ARKit). Guarded by `#if canImport(RoomPlan)`, so
//                        it compiles to an empty module on Linux. Carries the `.apple-only` marker.
//   CaptureUI            APPLE ONLY (SwiftUI, on ChapterUI). The capture screens. Guarded by
//                        `#if canImport(SwiftUI)`. Carries the `.apple-only` marker.
//   CaptureTestSupport   test helper (fixture paths, JSON Schema subset validator), a product so
//                        other packages' tests (SketchCapture) can use it.
//
// Test targets: CaptureModelMappingTests and CaptureCoreTests run everywhere; CaptureUITests (the
// screens' snapshots, ChapterUISnapshotTesting) and CaptureCompassTests (CompassService on the
// simulator, device test D0 on a phone) are empty outside iOS.
//
// There is deliberately NO `.apple-only` marker at the package root: scripts/swift-test.sh skips a
// whole package that has one, and the mapping, schema and capture-record tests must run on Linux.
import PackageDescription

let package = Package(
  name: "CaptureCore",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "CaptureModelMapping", targets: ["CaptureModelMapping"]),
    .library(name: "CaptureCore", targets: ["CaptureCore"]),
    .library(name: "CaptureCompass", targets: ["CaptureCompass"]),
    .library(name: "CaptureRoomPlan", targets: ["CaptureRoomPlan"]),
    .library(name: "CaptureUI", targets: ["CaptureUI"]),
    // Test helper (fixture paths, JSON Schema subset validator) for other packages' tests.
    .library(name: "CaptureTestSupport", targets: ["CaptureTestSupport"]),
  ],
  dependencies: [
    // Package identity of a path dependency is the directory name, here "swift".
    .package(path: "../../../contract/swift"),
    .package(path: "../ChapterUI"),
  ],
  targets: [
    .target(
      name: "CaptureModelMapping",
      dependencies: [.product(name: "CaptureContract", package: "swift")]
    ),
    .target(
      name: "CaptureCore",
      dependencies: [
        "CaptureModelMapping",
        .product(name: "CaptureContract", package: "swift"),
      ]
    ),
    .target(
      name: "CaptureCompass",
      dependencies: ["CaptureCore", .product(name: "CaptureContract", package: "swift")],
      exclude: [".apple-only"],
      // CLLocationManagerDelegate and Core Motion handlers are Objective-C callbacks.
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "CaptureRoomPlan",
      dependencies: [
        "CaptureCore", "CaptureCompass", "CaptureModelMapping",
        .product(name: "CaptureContract", package: "swift"),
      ],
      exclude: [".apple-only"],
      // RoomPlan and ARKit delegates are Objective-C protocols with non-Sendable arguments.
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "CaptureUI",
      dependencies: [
        "CaptureCore", .product(name: "CaptureContract", package: "swift"),
        .product(name: "ChapterUI", package: "ChapterUI"),
      ],
      exclude: [".apple-only"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(name: "CaptureTestSupport"),
    .testTarget(
      name: "CaptureModelMappingTests",
      dependencies: [
        "CaptureModelMapping", "CaptureTestSupport",
        .product(name: "CaptureContract", package: "swift"),
      ],
      // Capture models of the mapper before walk-through splitting; the tests read them in place.
      exclude: ["Golden"]
    ),
    // Empty on Linux; on the macOS runner it checks the RoomPlan Codable assumptions.
    .testTarget(
      name: "CaptureRoomPlanTests",
      dependencies: ["CaptureCore", "CaptureModelMapping", "CaptureRoomPlan", "CaptureTestSupport"]
    ),
    .testTarget(
      name: "CaptureCoreTests",
      dependencies: [
        "CaptureCore", "CaptureModelMapping", "CaptureTestSupport",
        .product(name: "CaptureContract", package: "swift"),
      ]
    ),
    // iOS simulator only: the screens' snapshots (402 x 874 pt @3x, iOS 26.0), compared with the
    // PNGs in __Snapshots__ (read from the source tree).
    .testTarget(
      name: "CaptureUITests",
      dependencies: [
        "CaptureUI", "CaptureCore", .product(name: "CaptureContract", package: "swift"),
        .product(name: "ChapterUI", package: "ChapterUI"),
        .product(name: "ChapterUISnapshotTesting", package: "ChapterUI"),
      ],
      exclude: ["__Snapshots__"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    // CompassService on the simulator (no compass there) and device test D0 on a phone.
    .testTarget(
      name: "CaptureCompassTests",
      dependencies: ["CaptureCompass", "CaptureCore", .product(name: "CaptureContract", package: "swift")]
    ),
  ]
)
