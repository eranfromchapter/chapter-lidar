// swift-tools-version: 6.0
// FieldKit: labeled site photos, independent field controls and the before-leaving checklist.
//
// Targets
// - FieldRules: pure Swift + Foundation (checklist rules, unit conversion, field-controls model).
// - PhotoStore: pure Swift + Foundation (photo records, original-bytes store, SHA-256).
// - FieldKitUI: SwiftUI + AVFoundation screens. Every file is wrapped in `#if canImport(...)`, so
//   the target is empty on Linux and the whole package builds and tests there.
//
// There is deliberately no `.apple-only` marker: scripts/swift-test.sh runs FieldRulesTests and
// PhotoStoreTests on Linux; the macOS runner (ios.yml, job FieldKit) builds the UI for iOS.
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
    .package(path: "../../../contract/swift")
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
      ]
    ),
    .testTarget(
      name: "FieldRulesTests",
      dependencies: [
        "FieldRules",
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
  ]
)
