// swift-tools-version: 6.0
// StationClient: the phone's client for the station API (contract/openapi/station.yaml), the
// access-token seam for Microsoft Entra sign-in and the HUB project list with an offline cache.
//
// Targets
// - StationClient: Foundation (+ FoundationNetworking on Linux) and CaptureContract only.
//   The Keychain token store is wrapped in `#if canImport(Security)`, so the target builds and
//   tests on Linux. MSAL is not a dependency here: the app shell provides the MSAL-backed
//   AccessTokenProvider.
//
// There is deliberately no `.apple-only` marker: scripts/swift-test.sh runs StationClientTests on
// Linux. No third-party packages.
import PackageDescription

let package = Package(
  name: "StationClient",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "StationClient", targets: ["StationClient"])
  ],
  dependencies: [
    .package(path: "../../../contract/swift")
  ],
  targets: [
    .target(
      name: "StationClient",
      dependencies: [.product(name: "CaptureContract", package: "swift")]
    ),
    .testTarget(
      name: "StationClientTests",
      dependencies: [
        "StationClient",
        .product(name: "CaptureContract", package: "swift"),
      ]
    ),
  ]
)
