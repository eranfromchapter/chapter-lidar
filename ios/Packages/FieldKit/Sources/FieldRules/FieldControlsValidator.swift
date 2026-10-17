import CaptureContract
import Foundation

/// Checks a `FieldControls` document against the rules of
/// `contract/schema/field-controls.schema.json` that the Swift types cannot express. The JSON
/// Schema stays the source of truth; the tests validate written files against it directly.
public enum FieldControlsValidator {
  /// One line per problem; empty when the document is valid.
  /// - Parameter knownCaptures: when given, every control must name a capture in this list.
  public static func issues(
    for controls: FieldControls, knownCaptures: [FieldControls.CaptureRef]? = nil
  ) -> [String] {
    var issues: [String] = []
    var ids: [String] = []

    func checkID(_ id: String) {
      if id.isEmpty || id.count > 128 { issues.append("id '\(id)' must be 1 to 128 characters") }
      ids.append(id)
    }
    func checkText(_ value: String, _ name: String, maximum: Int = 200) {
      if value.isEmpty || value.count > maximum {
        issues.append("\(name) must be 1 to \(maximum) characters")
      }
    }
    func checkCapture(_ capture: FieldControls.CaptureRef, _ name: String) {
      if !isValidAreaKey(capture.areaKey) {
        issues.append("\(name): areaKey '\(capture.areaKey)' is not a valid area key")
      }
      if let knownCaptures, !knownCaptures.contains(capture) {
        issues.append(
          "\(name): capture \(capture.captureId) / \(capture.areaKey) is not in the capture record")
      }
    }
    func checkMeasurement(_ measurement: FieldControls.Measurement, _ name: String) {
      if !(measurement.valueMm > 0 && measurement.valueMm <= Double(LengthParser.maximumMm)) {
        issues.append("\(name): valueMm must be greater than 0 and at most 200000")
      }
      if measurement.enteredText.isEmpty
        || measurement.enteredText.count > LengthParser.maximumTextLength
      {
        issues.append("\(name): enteredText must be 1 to 40 characters")
      }
    }

    for item in controls.distances {
      checkID(item.id)
      checkCapture(item.capture, item.id)
      checkText(item.from, "\(item.id) from")
      checkText(item.to, "\(item.id) to")
      checkMeasurement(item.measurement, item.id)
    }
    for item in controls.ceilingHeights {
      checkID(item.id)
      checkCapture(item.capture, item.id)
      checkText(item.room, "\(item.id) room")
      if let location = item.location { checkText(location, "\(item.id) location") }
      checkMeasurement(item.measurement, item.id)
    }
    for item in controls.openings {
      checkID(item.id)
      checkCapture(item.capture, item.id)
      checkText(item.room, "\(item.id) room")
      checkText(item.label, "\(item.id) label")
      checkMeasurement(item.width, "\(item.id) width")
      if let height = item.height { checkMeasurement(height, "\(item.id) height") }
    }
    for item in controls.floorToFloor {
      checkID(item.id)
      checkCapture(item.lower, "\(item.id) lower")
      checkCapture(item.upper, "\(item.id) upper")
      if item.lower.captureId == item.upper.captureId {
        issues.append("\(item.id): lower and upper must be different captures")
      }
      checkText(item.location, "\(item.id) location")
      checkMeasurement(item.measurement, item.id)
    }
    for item in controls.landmarks {
      checkID(item.id)
      checkText(item.label, "\(item.id) label")
      if let description = item.description {
        checkText(description, "\(item.id) description", maximum: 1000)
      }
      if item.captures.count < 2 || Set(item.captures).count != item.captures.count {
        issues.append("\(item.id): a landmark needs two or more different captures")
      }
      for capture in item.captures { checkCapture(capture, item.id) }
      for path in item.photoPaths ?? [] where !isValidRelativePath(path) {
        issues.append("\(item.id): photo path '\(path)' is not a valid package-relative path")
      }
    }

    for id in Set(ids) where ids.filter({ $0 == id }).count > 1 {
      issues.append("id '\(id)' is used more than once")
    }
    return issues.sorted()
  }

  /// `^[a-z0-9]+(-[a-z0-9]+)*$`, at most 64 characters.
  public static func isValidAreaKey(_ key: String) -> Bool {
    guard !key.isEmpty, key.count <= 64 else { return false }
    return key.split(separator: "-", omittingEmptySubsequences: false).allSatisfy { part in
      !part.isEmpty
        && part.unicodeScalars.allSatisfy {
          ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x61 && $0.value <= 0x7A)
        }
    }
  }

  /// Forward slashes, no leading or trailing slash, no empty, `.` or `..` segment, no backslash
  /// or control character, 1 to 1024 characters.
  static func isValidRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, path.count <= 1024, !path.hasPrefix("/"), !path.hasSuffix("/") else {
      return false
    }
    guard !path.unicodeScalars.contains(where: { $0 == "\\" || $0.value < 0x20 }) else {
      return false
    }
    return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
      !$0.isEmpty && $0 != "." && $0 != ".."
    }
  }
}
