import CaptureContract
import Foundation

/// Why `field-controls.json` was not written.
public struct FieldControlsFileError: Error, Equatable, Sendable, CustomStringConvertible {
  public let issues: [String]
  public var description: String {
    "field-controls.json is not valid: " + issues.joined(separator: "; ")
  }
}

/// Writes `Field Measurements/{visitId}/field-controls.json`.
public enum FieldControlsFile {
  public static let fileName = "field-controls.json"

  /// Package-relative path with forward slashes.
  public static func relativePath(visitId: LowercaseUUID) -> String {
    "\(PackageFolder.fieldMeasurements.name)/\(visitId.rawValue)/\(fileName)"
  }

  /// Validated, byte-stable JSON (sorted keys, unescaped slashes).
  public static func encode(
    _ controls: FieldControls, knownCaptures: [FieldControls.CaptureRef]? = nil
  ) throws -> Data {
    let issues = FieldControlsValidator.issues(for: controls, knownCaptures: knownCaptures)
    guard issues.isEmpty else { throw FieldControlsFileError(issues: issues) }
    return try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(controls)
  }

  /// Writes the file under `packageRoot` at `relativePath(visitId:)` and returns its URL.
  @discardableResult
  public static func write(
    _ controls: FieldControls, intoPackageRoot packageRoot: URL,
    knownCaptures: [FieldControls.CaptureRef]? = nil
  ) throws -> URL {
    let data = try encode(controls, knownCaptures: knownCaptures)
    let url = packageRoot.appendingPathComponent(relativePath(visitId: controls.visitId))
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    return url
  }
}
