// swift-tools-version: 6.0
// PlanExport: plan files written from a CaptureModel on the phone, with no network:
// DXF, room CSV, plan PDF, Spatial Report PDF, PNG and SVG previews, and the one-page colour
// Floorplan (PDF and SVG).
// Pure Swift + Foundation (no CoreGraphics, PDFKit or UIKit) so every writer builds and tests on Linux.
import PackageDescription

let package = Package(
  name: "PlanExport",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "PlanExport", targets: ["PlanExport"])
  ],
  dependencies: [
    .package(path: "../../../contract/swift"),
    // Tests only: maps the synthetic walk-through RoomPlan fixture into rooms.
    .package(path: "../CaptureCore"),
  ],
  targets: [
    .target(
      name: "PlanExport",
      dependencies: [.product(name: "CaptureContract", package: "swift")]
    ),
    .testTarget(
      name: "PlanExportTests",
      dependencies: [
        "PlanExport", .product(name: "CaptureContract", package: "swift"),
        .product(name: "CaptureModelMapping", package: "CaptureCore"),
      ]
    ),
  ]
)
