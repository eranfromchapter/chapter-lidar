// swift-tools-version: 6.0
// CaptureContract: Codable models of the Chapter Capture package contract.
// Foundation only, no dependencies, so it builds on Linux as well as iOS and macOS.
// The JSON Schemas in contract/schema are the source of truth; the tests read them directly.
import PackageDescription

let package = Package(
  name: "CaptureContract",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "CaptureContract", targets: ["CaptureContract"])
  ],
  targets: [
    .target(name: "CaptureContract"),
    .testTarget(name: "CaptureContractTests", dependencies: ["CaptureContract"]),
  ]
)
