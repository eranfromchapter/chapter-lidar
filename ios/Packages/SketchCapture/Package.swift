// swift-tools-version: 6.0
// SketchCapture: the no-LiDAR capture path (spec F14). A hand sketch or existing plan plus the
// measurements the operator enters become the same capture model, plans and 3D model a scan
// produces.
//
// Targets and where they build:
//   SketchSolver   pure Swift + Foundation. Linux, macOS, iOS. SketchMeasurements -> CaptureModel
//                  (closure, estimates, confidences) and the sketch summary of the capture record.
//   SketchMesh     Foundation only. The capture model extruded into a MeshExport TriangleMesh
//                  (floor, walls with openings cut, ceiling) for mesh.glb / mesh.obj.
//   SketchEntry    Foundation only. The guided measurement entry: what is asked, in what order,
//                  and the SketchMeasurements it builds; the method choice; the walkthrough's
//                  floor writer. Tested on Linux.
//   SketchUI       APPLE ONLY (SwiftUI, on ChapterUI). The sketch screens. Carries `.apple-only`.
//   Walkthrough    Foundation only. AR walkthrough taps -> SketchMeasurements (spec F15): drift,
//                  wall lines, square corners, openings, scale check. Tested on Linux.
//   WalkthroughUI  The AR walkthrough: its model, the session protocol and the replay session are
//                  Foundation only (tested with SketchEntryTests); the live ARKit session, the
//                  recording and the screens are APPLE ONLY (`#if canImport(ARKit)`, SwiftUI).
//                  Carries `.apple-only`.
//
// No `.apple-only` marker at the package root: scripts/swift-test.sh runs the solver, mesh and
// entry tests on Linux.
import PackageDescription

let package = Package(
  name: "SketchCapture",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "SketchSolver", targets: ["SketchSolver"]),
    .library(name: "SketchMesh", targets: ["SketchMesh"]),
    .library(name: "SketchEntry", targets: ["SketchEntry"]),
    .library(name: "SketchUI", targets: ["SketchUI"]),
    .library(name: "Walkthrough", targets: ["Walkthrough"]),
    .library(name: "SketchReading", targets: ["SketchReading"]),
    .library(name: "WalkthroughUI", targets: ["WalkthroughUI"]),
  ],
  dependencies: [
    // Package identity of a path dependency is the directory name, here "swift".
    .package(path: "../../../contract/swift"),
    .package(path: "../CaptureCore"),
    .package(path: "../MeshExport"),
    .package(path: "../FieldKit"),
    .package(path: "../ChapterUI"),
  ],
  targets: [
    .target(
      name: "SketchSolver",
      dependencies: [
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "CaptureModelMapping", package: "CaptureCore"),
      ]
    ),
    .target(
      name: "SketchMesh",
      dependencies: [
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "MeshExport", package: "MeshExport"),
      ]
    ),
    .target(
      name: "SketchEntry",
      dependencies: [
        "SketchSolver",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "FieldKit", package: "FieldKit"),
      ]
    ),
    .target(
      name: "SketchUI",
      dependencies: [
        "SketchEntry", "SketchSolver",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "ChapterUI", package: "ChapterUI"),
        .product(name: "FieldKit", package: "FieldKit"),
      ],
      exclude: [".apple-only"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .target(
      name: "Walkthrough",
      dependencies: ["SketchSolver", .product(name: "CaptureContract", package: "swift")]
    ),
    // What Claude read from a sketch photo -> SketchMeasurements (spec F16). Linux-tested.
    .target(
      name: "SketchReading",
      dependencies: ["SketchSolver", .product(name: "CaptureContract", package: "swift")]
    ),
    .testTarget(
      name: "SketchReadingTests",
      dependencies: [
        "SketchReading", "SketchSolver", "SketchMesh",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "CaptureTestSupport", package: "CaptureCore"),
        .product(name: "MeshExport", package: "MeshExport"),
      ]
    ),
    .target(
      name: "WalkthroughUI",
      dependencies: [
        "Walkthrough", "SketchEntry", "SketchSolver", "SketchUI",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "ChapterUI", package: "ChapterUI"),
        .product(name: "FieldKit", package: "FieldKit"),
      ],
      exclude: [".apple-only"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
      name: "WalkthroughTests",
      dependencies: [
        "Walkthrough", "SketchSolver",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "CaptureTestSupport", package: "CaptureCore"),
      ]
    ),
    .testTarget(
      name: "SketchSolverTests",
      dependencies: [
        "SketchSolver",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "CaptureTestSupport", package: "CaptureCore"),
      ]
    ),
    .testTarget(
      name: "SketchMeshTests",
      dependencies: [
        "SketchMesh", "SketchSolver",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "MeshExport", package: "MeshExport"),
      ]
    ),
    .testTarget(
      name: "SketchEntryTests",
      dependencies: [
        "SketchEntry", "SketchSolver", "Walkthrough", "WalkthroughUI",
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "CaptureTestSupport", package: "CaptureCore"),
      ]
    ),
  ]
)
