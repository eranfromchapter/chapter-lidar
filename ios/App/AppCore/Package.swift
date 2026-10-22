// swift-tools-version: 6.0
// AppCore: the pure-Swift logic of the Chapter Capture app shell (spec F6, step F6.4).
//
// - The app flow state machine (capture record -> scan(s) per floor -> photos -> controls ->
//   checklist gate -> package ready / seal -> upload status).
// - The bridge that makes StationClient satisfy PackageKit's `PackageUploadService`, and the HUB
//   project provider over StationClient's `ProjectStore`.
// - Building the visit's package draft (plan and mesh exports, capture record, field controls,
//   photos) and the summaries the "Package ready" and "Uploading" screens show.
// - Configuration validation and the launch-mode switch (the UI-test replay mode exists only in
//   Debug builds).
//
// Foundation only: no MSAL, no UIKit, no SwiftUI. Builds and tests on Linux:
//   swift test --package-path ios/App/AppCore
import PackageDescription

let package = Package(
  name: "AppCore",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "AppCore", targets: ["AppCore"])
  ],
  dependencies: [
    // Package identity of a path dependency is the directory name.
    .package(path: "../../../contract/swift"),
    .package(path: "../../Packages/CaptureCore"),
    .package(path: "../../Packages/PlanExport"),
    .package(path: "../../Packages/MeshExport"),
    .package(path: "../../Packages/FieldKit"),
    .package(path: "../../Packages/PackageKit"),
    .package(path: "../../Packages/StationClient"),
  ],
  targets: [
    .target(
      name: "AppCore",
      dependencies: [
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "CaptureCore", package: "CaptureCore"),
        .product(name: "CaptureModelMapping", package: "CaptureCore"),
        .product(name: "PlanExport", package: "PlanExport"),
        .product(name: "MeshExport", package: "MeshExport"),
        .product(name: "FieldKit", package: "FieldKit"),
        .product(name: "PackageKit", package: "PackageKit"),
        .product(name: "StationClient", package: "StationClient"),
      ]
    ),
    .testTarget(
      name: "AppCoreTests",
      dependencies: [
        "AppCore",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "CaptureCore", package: "CaptureCore"),
        .product(name: "CaptureModelMapping", package: "CaptureCore"),
        .product(name: "FieldKit", package: "FieldKit"),
        .product(name: "PackageKit", package: "PackageKit"),
        .product(name: "StationClient", package: "StationClient"),
      ],
      // Visit folders of the v1 app, read in place (`Fixtures.v1Visits`).
      exclude: ["Fixtures"]
    ),
  ]
)
