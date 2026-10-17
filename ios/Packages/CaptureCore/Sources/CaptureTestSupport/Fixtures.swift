import Foundation

/// Locates the shared fixtures and schemas in the repository. Nothing is copied into the
/// package; the tests read `fixtures/generated` and `contract/schema` in place.
public enum Fixtures {
  /// The repository root (this file is ios/Packages/CaptureCore/Sources/CaptureTestSupport/Fixtures.swift).
  public static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // CaptureTestSupport
    .deletingLastPathComponent()  // Sources
    .deletingLastPathComponent()  // CaptureCore
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // ios
    .deletingLastPathComponent()  // repository root

  public static var generatedDirectory: URL {
    repositoryRoot.appendingPathComponent("fixtures/generated", isDirectory: true)
  }

  public static func schemaURL(_ fileName: String) -> URL {
    repositoryRoot.appendingPathComponent("contract/schema/\(fileName)")
  }

  public static func load(_ name: String) throws -> GeneratedFixture {
    try GeneratedFixture(name: name)
  }
}

/// One generated fixture (`fixtures/generated/<name>`): the truth and the folder of its first capture.
public struct GeneratedFixture {
  public let name: String
  public let directory: URL
  public let truth: JSON

  init(name: String) throws {
    self.name = name
    directory = Fixtures.generatedDirectory.appendingPathComponent(name, isDirectory: true)
    truth = try JSON.parse(contentsOf: directory.appendingPathComponent("truth.json"))
  }

  public var visitId: String { truth["visitId"]?.string ?? "" }

  public var packageRoot: URL { directory.appendingPathComponent("package", isDirectory: true) }

  /// Truth of capture `index`.
  public func captureTruth(_ index: Int = 0) -> JSON {
    truth["captures"]?[index] ?? .null
  }

  /// `package/Original Exports/{areaKey}/{captureId}/` of capture `index`.
  public func captureDirectory(_ index: Int = 0) -> URL {
    let capture = captureTruth(index)
    return packageRoot
      .appendingPathComponent("Original Exports", isDirectory: true)
      .appendingPathComponent(capture["areaKey"]?.string ?? "", isDirectory: true)
      .appendingPathComponent(capture["captureId"]?.string ?? "", isDirectory: true)
  }

  public func roomPlanData(_ index: Int = 0) throws -> Data {
    try Data(contentsOf: captureDirectory(index).appendingPathComponent("roomplan.json"))
  }

  public func depthSamplesData(_ index: Int = 0) throws -> Data {
    try Data(contentsOf: captureDirectory(index).appendingPathComponent("depth-samples.bin"))
  }

  /// The generator's own capture model of capture `index`.
  public func captureModel(_ index: Int = 0) throws -> JSON {
    try JSON.parse(contentsOf: captureDirectory(index).appendingPathComponent("capture-model.json"))
  }
}
