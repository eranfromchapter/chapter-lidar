// swift-tools-version: 6.0
// plan-render: writes the plans of a scan on the Mac with the current app code: the plan sheet
// (PlanExport's `PlanSheetWriter`, the Tabloid page the package carries and the phone shows
// first): plan-sheet.pdf and plan-sheet.png; and the colour Floorplan (`FloorplanWriter`, the
// phone's "Colour floorplan"): floorplan.pdf, floorplan.svg and floorplan.png. The scan browser
// (tools/scan-browser) builds and runs it.
//
// Testing tool only, macOS only (the PNG is drawn with CoreGraphics). Not one of the packages
// scripts/swift-test.sh runs.
import PackageDescription

let package = Package(
  name: "plan-render",
  platforms: [.macOS(.v14)],
  dependencies: [
    // Package identity of a path dependency is the directory name, here "swift".
    .package(path: "../../contract/swift"),
    .package(path: "../../ios/Packages/CaptureCore"),
    .package(path: "../../ios/Packages/PlanExport"),
  ],
  targets: [
    .executableTarget(
      name: "plan-render",
      dependencies: [
        .product(name: "CaptureContract", package: "swift"),
        .product(name: "CaptureModelMapping", package: "CaptureCore"),
        .product(name: "PlanExport", package: "PlanExport"),
      ]
    )
  ]
)
