import CaptureContract
import Foundation

/// Which control the "New measurement" card is for.
public enum ControlKind: String, CaseIterable, Sendable {
  case distanceA
  case distanceB
  case ceilingHeight
  case opening
  case floorToFloor
  case landmark

  /// Title of the row on the Field controls screen.
  public var rowTitle: String {
    switch self {
    case .distanceA: return "Long distance A"
    case .distanceB: return "Long distance B \u{27C2}"
    case .ceilingHeight: return "Ceiling heights"
    case .opening: return "Openings"
    case .floorToFloor: return "Floor to floor"
    case .landmark: return "Shared landmarks"
    }
  }

  /// Name used in "New measurement · Floor to floor".
  public var entryTitle: String {
    switch self {
    case .distanceA: return "Long distance A"
    case .distanceB: return "Long distance B"
    case .ceilingHeight: return "Ceiling height"
    case .opening: return "Opening"
    case .floorToFloor: return "Floor to floor"
    case .landmark: return "Landmark"
    }
  }
}

/// Units offered in the unit menu. Stored values are always millimetres; the entered unit is
/// recorded. (`cm`, `in` and `ft` are valid in the contract but are not offered in v1.)
public enum UnitChoice {
  public static let offered: [EnteredUnit] = [.ftIn, .m, .mm]

  public static func title(_ unit: EnteredUnit) -> String {
    switch unit {
    case .mm: return "mm"
    case .cm: return "cm"
    case .m: return "m"
    case .inches: return "in"
    case .ft: return "ft"
    case .ftIn: return "ft-in"
    }
  }
}

/// The typed value and unit of one measurement, with live conversion for the hint line
/// ("Stored in mm. Shown in both units.").
public struct MeasurementEntryDraft: Hashable, Sendable {
  public var text: String
  public var unit: EnteredUnit
  public var method: MeasurementMethod

  public init(text: String = "", unit: EnteredUnit = .ftIn, method: MeasurementMethod = .tape) {
    self.text = text
    self.unit = unit
    self.method = method
  }

  public var result: Result<ParsedLength, LengthParseError> {
    Result { try LengthParser.parse(text, unit: unit) }
      .mapError { $0 as? LengthParseError ?? .invalidFormat("Enter a measurement.") }
  }

  /// `7 518 mm · 24′ 8″` once the text parses, otherwise nil.
  public var bothUnits: String? {
    if case .success(let parsed) = result { return LengthFormatter.both(parsed.valueMm) }
    return nil
  }

  /// Message for an entry that is not empty but does not parse.
  public var errorMessage: String? {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    if case .failure(let error) = result { return error.message }
    return nil
  }

  public func measurement(recordedAt: UTCTimestamp) throws -> FieldControls.Measurement {
    try FieldMeasurement.make(text: text, unit: unit, method: method, recordedAt: recordedAt)
  }
}
