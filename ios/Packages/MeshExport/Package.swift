// swift-tools-version: 6.0
// MeshExport: GLB, OBJ+MTL and LAS 1.4 writers for Chapter Capture.
// Foundation only, so it builds and tests on Linux as well as iOS and macOS.
// CaptureContract is used by the tests only (to read the fixtures' capture-model.json).
import PackageDescription

let package = Package(
  name: "MeshExport",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "MeshExport", targets: ["MeshExport"])
  ],
  dependencies: [
    .package(path: "../../../contract/swift")
  ],
  targets: [
    .target(name: "MeshExport"),
    .testTarget(
      name: "MeshExportTests",
      dependencies: [
        "MeshExport",
        .product(name: "CaptureContract", package: "swift"),
      ]
    ),
  ]
)
