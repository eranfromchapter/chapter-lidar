import XCTest

@testable import AppCore

final class ConfigurationTests: XCTestCase {
  private let valid: [ConfigurationKey: String] = [
    .entraClientId: "6F1C2B3A-1111-4222-8333-944455556666",
    .entraTenantId: "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d",
    .stationScope: "api://4b5c6d7e-1111-4222-8333-944455556666/Capture.Upload",
    .stationURL: "https://station.hellochapter.test",
  ]

  private func load(_ values: [ConfigurationKey: String]) -> ConfigurationState {
    ConfigurationLoader.load { values[$0] }
  }

  func testValidConfigurationIsAccepted() throws {
    let configuration = try XCTUnwrap(load(valid).configuration)
    XCTAssertEqual(configuration.entraClientId, "6f1c2b3a-1111-4222-8333-944455556666")
    XCTAssertEqual(
      configuration.authorityURL.absoluteString,
      "https://login.microsoftonline.com/0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d")
    XCTAssertEqual(configuration.stationURL.absoluteString, "https://station.hellochapter.test")
  }

  func testCommittedPlaceholdersAreNotConfigured() {
    // The values committed in ios/App/Config/Base.xcconfig.
    let placeholders: [ConfigurationKey: String] = [
      .entraClientId: "__SET_ENTRA_CLIENT_ID__",
      .entraTenantId: "__SET_ENTRA_TENANT_ID__",
      .stationScope: "__SET_STATION_API_SCOPE__",
      .stationURL: "__SET_STATION_URL__",
    ]
    XCTAssertEqual(
      load(placeholders),
      .notConfigured(ConfigurationKey.allCases.map { .placeholder($0) }))
  }

  func testMissingAndUnexpandedValuesAreNotConfigured() {
    var values = valid
    values[.entraClientId] = nil
    values[.stationURL] = "$(CHAPTER_STATION_URL)"
    values[.entraTenantId] = "   "
    guard case .notConfigured(let issues) = load(values) else {
      return XCTFail("expected notConfigured")
    }
    XCTAssertEqual(
      Set(issues),
      [.missing(.entraClientId), .placeholder(.stationURL), .missing(.entraTenantId)])
  }

  func testInvalidValuesAreReportedPerKey() {
    var values = valid
    values[.entraClientId] = "not-a-uuid"
    values[.stationScope] = "Capture.Upload"
    values[.stationURL] = "http://station.hellochapter.test"
    guard case .notConfigured(let issues) = load(values) else {
      return XCTFail("expected notConfigured")
    }
    XCTAssertEqual(issues.map(\.key), [.entraClientId, .stationScope, .stationURL])
  }

  func testNoFallbackForAnyMissingKey() {
    for key in ConfigurationKey.allCases {
      var values = valid
      values[key] = nil
      XCTAssertNil(load(values).configuration, "\(key) missing must not configure the app")
    }
  }

  func testInfoDictionaryReadsTheDocumentedKeys() {
    let info: [String: Any] = Dictionary(
      uniqueKeysWithValues: valid.map { ($0.key.rawValue, $0.value as Any) })
    XCTAssertNotNil(ConfigurationLoader.load(infoDictionary: info).configuration)
    XCTAssertNil(ConfigurationLoader.load(infoDictionary: nil).configuration)
  }
}

final class LaunchModeTests: XCTestCase {
  func testReleaseBuildNeverSelectsTheReplayMode() {
    let arguments = ["App", LaunchModeResolver.replayArgument, "box-room"]
    XCTAssertEqual(LaunchModeResolver.resolve(arguments: arguments, isDebugBuild: false), .live)
  }

  func testDebugBuildSelectsReplayOnlyWithTheFlagAndAKnownFixture() {
    XCTAssertEqual(
      LaunchModeResolver.resolve(
        arguments: ["App", LaunchModeResolver.replayArgument, "box-room"], isDebugBuild: true),
      .uiTestReplay(fixture: "box-room"))
    XCTAssertEqual(LaunchModeResolver.resolve(arguments: ["App"], isDebugBuild: true), .live)
    XCTAssertEqual(
      LaunchModeResolver.resolve(
        arguments: ["App", LaunchModeResolver.replayArgument], isDebugBuild: true), .live)
    XCTAssertEqual(
      LaunchModeResolver.resolve(
        arguments: ["App", LaunchModeResolver.replayArgument, "../../etc"], isDebugBuild: true),
      .live)
  }
}
