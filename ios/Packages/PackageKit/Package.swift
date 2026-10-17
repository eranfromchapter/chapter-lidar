// swift-tools-version: 6.0
// PackageKit: turns one site visit into the intake package and gets it to the station without
// losing anything (spec F6, steps F6.1 and F6.2).
//
// Targets
// - PackageCore: pure Swift + Foundation. Package layout and paths, manifest with SHA-256 of every
//   file, sealing (read-only) and revision rules, the station upload protocol and its Codable
//   types, and the resumable upload state machine. Builds and tests on Linux.
// - PackageTransport: blob transports. `HTTPBlobTransport` (foreground URLSession) is portable;
//   `BackgroundBlobTransport` (background URLSession) is wrapped in `#if canImport(Darwin)`, so
//   the target is portable and the whole package builds and tests on Linux.
//
// There is deliberately no `.apple-only` marker: scripts/swift-test.sh runs PackageKitTests on
// Linux. PackageKit depends only on the contract; it does not depend on StationClient,
// CaptureCore, FieldKit, PlanExport or MeshExport (inputs are plain file URLs plus metadata).
import PackageDescription

let package = Package(
  name: "PackageKit",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "PackageKit", targets: ["PackageCore", "PackageTransport"])
  ],
  dependencies: [
    .package(path: "../../../contract/swift")
  ],
  targets: [
    .target(
      name: "PackageCore",
      dependencies: [.product(name: "CaptureContract", package: "swift")]
    ),
    .target(
      name: "PackageTransport",
      dependencies: [
        "PackageCore",
        .product(name: "CaptureContract", package: "swift"),
      ]
    ),
    .testTarget(
      name: "PackageKitTests",
      dependencies: [
        "PackageCore",
        "PackageTransport",
        .product(name: "CaptureContract", package: "swift"),
      ]
    ),
  ]
)
