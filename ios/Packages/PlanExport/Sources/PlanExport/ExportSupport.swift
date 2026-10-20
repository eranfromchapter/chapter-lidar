import CaptureContract
import Foundation

/// Names written into the package manifest for every file this package produces.
public enum PlanExportInfo {
  /// Manifest `generator` value.
  public static let generator = "chapter-capture-ios/PlanExport"
  /// Manifest `generatorVersion` value.
  public static let generatorVersion = "1.0.0"
}

/// One written file with what the package manifest needs to describe it.
public struct ExportedFile: Hashable, Sendable {
  /// File name inside `Original Exports/{areaKey}/{captureId}/`, for example `plan.dxf`.
  public let fileName: String
  /// Manifest role of the file.
  public let role: FileRole
  /// Manifest MIME type.
  public let mime: String
  public let data: Data
  /// Manifest `generator`.
  public let generator: String
  /// Manifest `generatorVersion`.
  public let generatorVersion: String

  init(fileName: String, role: FileRole, mime: String, data: Data) {
    self.fileName = fileName
    self.role = role
    self.mime = mime
    self.data = data
    self.generator = PlanExportInfo.generator
    self.generatorVersion = PlanExportInfo.generatorVersion
  }
}

public enum PlanExportError: Error, Equatable, CustomStringConvertible {
  /// The capture record has no capture with the model's `captureId`.
  case captureNotInRecord(captureId: String)
  /// A door, window or opening names a wall that is not in the model.
  case unknownWall(openingId: String, wallId: String)
  /// A coordinate or size is not a finite number, or a room outline has fewer than 3 points.
  case invalidGeometry(String)
  /// The model has no walls, rooms or objects to draw.
  case noPlanGeometry
  /// The plan does not fit an A3 sheet even at the coarsest supported scale.
  case planTooLarge

  public var description: String {
    switch self {
    case .captureNotInRecord(let captureId):
      return "The capture record has no capture \(captureId)."
    case .unknownWall(let openingId, let wallId):
      return "Opening \(openingId) refers to wall \(wallId), which is not in the model."
    case .invalidGeometry(let detail):
      return "Invalid geometry: \(detail)"
    case .noPlanGeometry:
      return "The model has no walls, rooms or objects to draw."
    case .planTooLarge:
      return "The plan does not fit an A3 sheet at any supported scale."
    }
  }
}

/// Number and text formatting shared by every writer. All output is locale independent.
enum Format {
  /// Fixed decimals, never "-0.00".
  static func fixed(_ value: Double, _ digits: Int) -> String {
    var text = String(format: "%.\(digits)f", value)
    if text.hasPrefix("-"), Double(text) == 0 {
      text.removeFirst()
    }
    return text
  }

  /// Whole millimetres from metres.
  static func millimetres(_ metres: Double) -> Int {
    Int((metres * 1000).rounded())
  }

  /// Feet and inches with inches to two decimals, for example `13' 1.48"`.
  static func feetInches(millimetres: Double) -> String {
    let totalInches = (millimetres / 25.4 * 100).rounded() / 100
    let sign = totalInches < 0 ? "-" : ""
    let magnitude = abs(totalInches)
    var feet = (magnitude / 12).rounded(.down)
    var inches = ((magnitude - feet * 12) * 100).rounded() / 100
    if inches >= 12 {
      feet += 1
      inches = 0
    }
    return "\(sign)\(Int(feet))' \(fixed(inches, 2))\""
  }

  static func squareFeet(squareMetres: Double) -> String {
    fixed(squareMetres * 10.763_910_416_709_722, 1)
  }

  /// A length for labels: whole millimetres for metric, feet-inches for imperial.
  static func length(metres: Double, units: DisplayUnitSystem) -> String {
    switch units {
    case .metric: return "\(millimetres(metres)) mm"
    case .imperial: return feetInches(millimetres: metres * 1000)
    }
  }

  /// One line of text without control characters.
  static func singleLine(_ text: String) -> String {
    String(
      String.UnicodeScalarView(
        text.unicodeScalars.map { scalar in
          scalar.value < 0x20 || scalar.value == 0x7F ? " " : scalar
        })
    )
  }

  /// `text` with each letter and its accents composed into one character where Unicode has one
  /// (NFC), so a decomposed "e" + U+0301 is measured and written as the one character "é".
  static func composed(_ text: String) -> String {
    text.utf8.allSatisfy { $0 < 0x80 } ? text : text.precomposedStringWithCanonicalMapping
  }

  /// Compact number for labels, for example `0.5` or `2`.
  static func compact(_ value: Double) -> String {
    let rounded = (value * 1000).rounded() / 1000
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(rounded)
  }
}
