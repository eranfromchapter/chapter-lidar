import CaptureContract
import FieldRules
import Foundation

/// One length as the operator types it on a sketch screen (spec F14 2.1): the text in one
/// unit, read exactly by `LengthParser` (the Field controls' rules, nothing rounded), and
/// whether it was measured with a tape or laser or is an "about" estimate by eye. An "about"
/// value or an empty field is what marks an estimate in the model (1.5).
public struct SketchLengthField: Hashable, Sendable {
  public var text: String
  /// The unit the text is in: feet and inches or inches for an imperial capture, millimetres
  /// for a metric one (`SketchUnits`).
  public var unit: EnteredUnit
  /// True (the default) for a tape or laser reading; false for "About".
  public var measured: Bool

  public init(text: String = "", unit: EnteredUnit, measured: Bool = true) {
    self.text = text
    self.unit = unit
    self.measured = measured
  }

  /// The text as typed: surrounding spaces trimmed, a comma read as a decimal point (decimal
  /// pads in many regions show `,`).
  var cleaned: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
  }

  public var isEmpty: Bool { cleaned.isEmpty }

  /// The parsed value, or why it is refused; nil when nothing is typed.
  public var result: Result<ParsedLength, LengthParseError>? {
    guard !isEmpty else { return nil }
    return Result { try LengthParser.parse(cleaned, unit: unit) }
      .mapError { $0 as? LengthParseError ?? .invalidFormat("Enter a measurement.") }
  }

  /// The entered length for `sketch-measurements.json`; nil when empty or refused.
  public var length: SketchMeasurements.Length? {
    guard case .success(let parsed)? = result else { return nil }
    return SketchMeasurements.Length(
      valueMm: parsed.valueMm, enteredUnit: parsed.unit, enteredText: parsed.enteredText,
      measured: measured)
  }

  /// A value that parses was entered (measured or about).
  public var isEntered: Bool { length != nil }

  /// The message under the field for a value that is typed and refused; nil when empty or valid,
  /// and while a value is half typed (a trailing decimal point, foot or inch mark, slash or
  /// space), which cannot be saved either but is not wrong yet.
  public var errorMessage: String? {
    guard case .failure(let error)? = result else { return nil }
    if let last = cleaned.last, ".'\"/ -".contains(last) { return nil }
    return error.message
  }

  /// `7,518 mm · 24' 8"` once the value parses: what is stored, in both units.
  public var storedText: String? {
    length.map { LengthFormatter.both($0.valueMm) }
  }

  /// The same field in another unit with the text cleared: nothing is converted silently (the
  /// operator types what the tape shows in that unit). A field that is empty only changes unit.
  public func cleared(unit: EnteredUnit) -> SketchLengthField {
    SketchLengthField(unit: unit, measured: measured)
  }

  /// The field of a stored length, for a draft rebuilt from a document: the entered text and
  /// unit as they were.
  public init(_ length: SketchMeasurements.Length) {
    self.init(text: length.enteredText, unit: length.enteredUnit, measured: length.measured)
  }
}

/// The entry units of a sketch capture: long lengths (walls, diagonals, ceiling) and short
/// ones (openings and their distances from a corner). Imperial: feet and inches, and inches;
/// metric: millimetres for both. Fields are made in these units; a field keeps its unit once
/// typed.
public struct SketchUnits: Hashable, Sendable {
  public var long: EnteredUnit
  public var short: EnteredUnit

  public init(long: EnteredUnit, short: EnteredUnit) {
    self.long = long
    self.short = short
  }

  public init(display: DisplayUnitSystem) {
    switch display {
    case .imperial: self.init(long: .ftIn, short: .inches)
    case .metric: self.init(long: .mm, short: .mm)
    }
  }

  /// The suffix drawn after a field: `ft-in`, `in`, `mm`, `m`.
  public static func suffix(_ unit: EnteredUnit) -> String {
    switch unit {
    case .mm: return "mm"
    case .cm: return "cm"
    case .m: return "m"
    case .inches: return "in"
    case .ft: return "ft"
    case .ftIn: return "ft-in"
    }
  }

  /// The prompt of an empty field: an example in that unit.
  public static func prompt(_ unit: EnteredUnit) -> String {
    switch unit {
    case .mm: return "4000"
    case .cm: return "400"
    case .m: return "4.0"
    case .inches: return "36"
    case .ft: return "13"
    case .ftIn: return "13' 1.5\""
    }
  }
}
