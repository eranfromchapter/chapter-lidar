// swift-tools-version: 6.0
// CaptureCore: the Chapter Capture scan core (RoomPlan + ARKit LiDAR behind one session API),
// the adapter into the contract CaptureModel, and the capture-record screens.
//
// Targets and where they build:
//   CaptureModelMapping  pure Swift + Foundation. Linux, macOS, iOS. Transforms, room polygons,
//                        opening-to-wall assignment. The mapping math is tested here.
//   CaptureCore          Foundation only. Linux, macOS, iOS. CaptureSession protocol, ReplaySession,
//                        device gate, raw-originals writer, capture-record form logic.
//   CaptureRoomPlan      APPLE ONLY (RoomPlan + ARKit). Guarded by `#if canImport(RoomPlan)`, so
//                        it compiles to an empty module on Linux. Carries the `.apple-only` marker.
//   CaptureUI            APPLE ONLY (SwiftUI). Guarded by `#if canImport(SwiftUI)`. Carries the
//                        `.apple-only` marker.
//   CaptureTestSupport   test helper (fixture paths, JSON Schema subset validator). Not a product.
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
    .library(name: "CaptureRoomPlan", targets: ["CaptureRoomPlan"]),
    .library(name: "CaptureUI", targets: ["CaptureUI"]),
  ],
  dependencies: [
    // Package identity of a path dependency is the directory name, here "swift".
    .package(path: "../../../contract/swift")
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
      name: "CaptureRoomPlan",
      dependencies: [
        "CaptureCore", "CaptureModelMapping", .product(name: "CaptureContract", package: "swift"),
      ],
      exclude: [".apple-only"],
      // RoomPlan and ARKit delegates are Objective-C protocols with non-Sendable arguments.
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "CaptureUI",
      dependencies: ["CaptureCore", .product(name: "CaptureContract", package: "swift")],
      exclude: [".apple-only"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(name: "CaptureTestSupport"),
    .testTarget(
      name: "CaptureModelMappingTests",
      dependencies: [
        "CaptureModelMapping", "CaptureTestSupport",
        .product(name: "CaptureContract", package: "swift"),
      ]
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
  ]
)
