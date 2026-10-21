// swift-tools-version: 6.0
// FieldKit: labeled site photos, independent field controls and the before-leaving checklist.
//
// Targets
// - FieldRules: pure Swift + Foundation (checklist rules, unit conversion, field-controls model,
//   the Field controls list, photo labels and the compass pre-fill rules).
// - PhotoStore: pure Swift + Foundation (photo records, original-bytes store, SHA-256).
// - FieldKitUI: SwiftUI + AVFoundation screens (design v2, artboard 2d) on ChapterUI's tokens and
//   components. Every file is wrapped in `#if canImport(...)`, so the target is empty on Linux and
//   macOS (ChapterUI is too) and the whole package builds and tests there.
// - FieldKitUISnapshotTests: the screens drawn with ChapterUISnapshotTesting on the iPhone 17 Pro
//   simulator (iOS only; an empty target elsewhere).
//
// There is deliberately no `.apple-only` marker: scripts/swift-test.sh runs FieldRulesTests and
// PhotoStoreTests on Linux; the macOS runner (ios.yml, job FieldKit) builds the UI for iOS and
// runs every test target, the snapshots included, on the simulator.
import PackageDescription

let package = Package(
  name: "FieldKit",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "FieldKit", targets: ["FieldRules", "PhotoStore", "FieldKitUI"])
  ],
  dependencies: [
    .package(path: "../../../contract/swift"),
    .package(path: "../ChapterUI"),
  ],
  targets: [
    .target(
      name: "FieldRules",
      dependencies: [.product(name: "CaptureContract", package: "swift")]
    ),
    .target(
      name: "PhotoStore",
      dependencies: [
        "FieldRules",
        .product(name: "CaptureContract", package: "swift"),
      ]
    ),
    .target(
      name: "FieldKitUI",
      dependencies: [
        "FieldRules",
        "PhotoStore",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "ChapterUI", package: "ChapterUI"),
      ]
    ),
    .testTarget(
      name: "FieldRulesTests",
      dependencies: [
        "FieldRules",
        // The checklist after a room rename relabels photos through the store, and the store's
        // index is checked against contract/schema with this target's validator.
        "PhotoStore",
        .product(name: "CaptureContract", package: "swift"),
      ]
    ),
    .testTarget(
      name: "PhotoStoreTests",
      dependencies: [
        "PhotoStore",
        "FieldRules",
        .product(name: "CaptureContract", package: "swift"),
      ]
    ),
    .testTarget(
      name: "FieldKitUISnapshotTests",
      dependencies: [
        "FieldKitUI",
        "FieldRules",
        "PhotoStore",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "ChapterUI", package: "ChapterUI"),
        .product(name: "ChapterUISnapshotTesting", package: "ChapterUI"),
      ],
      // Reference PNGs; the tests read them from the source tree (#filePath).
      exclude: ["__Snapshots__"]
    ),
  ]
)
