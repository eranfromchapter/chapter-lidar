import CaptureContract
import Foundation

/// Which control a Field controls row and its entry sheet are for.
public enum ControlKind: String, CaseIterable, Sendable {
  case distanceA
  case distanceB
  case ceilingHeight
  case opening
  case floorToFloor
  case landmark

  /// Title of the row on the Field controls list (phone-field §9.1). A missing or optional
  /// long distance B is the compact row `Long distance B` (`ControlsList`).
  public var rowTitle: String {
    switch self {
    case .distanceA: return "Long distance A"
    case .distanceB: return "Long distance B \u{00B7} at a right angle to A"
    case .ceilingHeight: return "Ceiling height"
    case .opening: return "Openings \u{00B7} optional"
    case .floorToFloor: return "Floor to floor"
    case .landmark: return "Shared landmarks"
    }
  }

  /// Title of the entry sheet: `Long distance A`, `Shared landmark`.
  public var entryTitle: String {
    switch self {
    case .distanceA: return "Long distance A"
    case .distanceB: return "Long distance B"
    case .ceilingHeight: return "Ceiling height"
    case .opening: return "Opening"
    case .floorToFloor: return "Floor to floor"
    case .landmark: return "Shared landmark"
    }
  }

  /// The last part of the row's accessibility identifier, `controls.row.floor-1.distanceA`
  /// (phone-field §4.2, §9.5).
  public var rowKey: String {
    switch self {
    case .distanceA: return "distanceA"
    case .distanceB: return "distanceB"
    case .ceilingHeight: return "ceilingHeight"
    case .opening: return "openings"
    case .floorToFloor: return "floorToFloor"
    case .landmark: return "landmarks"
    }
  }

  /// Rows that hold one value (tapping one edits it) rather than a list (tapping one adds).
  public var isSingleValue: Bool {
    switch self {
    case .distanceA, .distanceB, .floorToFloor: return true
    case .ceilingHeight, .opening, .landmark: return false
    }
  }
}

/// Units offered in the entry sheet's segmented control, in its order. Stored values are always
/// millimetres; the entered unit is recorded. (`cm`, `in` and `ft` are valid in the contract but
/// are not offered.)
public enum UnitChoice {
  public static let offered: [EnteredUnit] = [.mm, .m, .ftIn]

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

  /// What VoiceOver reads for the segment.
  public static func spokenTitle(_ unit: EnteredUnit) -> String {
    switch unit {
    case .mm: return "Millimetres"
    case .cm: return "Centimetres"
    case .m: return "Metres"
    case .inches: return "Inches"
    case .ft: return "Feet"
    case .ftIn: return "Feet and inches"
    }
  }

  /// The unit a new entry starts in when nothing was entered in this visit yet: feet and inches
  /// for an imperial capture (the default), millimetres for a metric one.
  public static func defaultUnit(for display: DisplayUnitSystem) -> EnteredUnit {
    display == .metric ? .mm : .ftIn
  }
}

/// The value fields of the entry sheet (phone-field §5.4): feet and inches as two fields, or
/// one millimetre or metre field, and the instrument. `enteredText` is what goes into the
/// contract's `measurement.enteredText`, parsed exactly by `LengthParser` (never rounded).
public struct MeasurementEntryDraft: Hashable, Sendable {
  /// `.mm`, `.m` or `.ftIn` (`UnitChoice.offered`).
  public var unit: EnteredUnit
  /// Whole feet (ft-in only).
  public var feet: String
  /// Inches, a decimal (ft-in only).
  public var inches: String
  /// The millimetre or metre value (mm and m only).
  public var value: String
  public var method: MeasurementMethod

  public init(
    unit: EnteredUnit = .ftIn, feet: String = "", inches: String = "", value: String = "",
    method: MeasurementMethod = .tape
  ) {
    self.unit = unit
    self.feet = feet
    self.inches = inches
    self.value = value
    self.method = method
  }

  static let wholeFeetMessage = "Enter whole feet. Put the rest in inches."
  static let inchesMessage = "Enter inches as a number, for example 8 or 10.5."

  /// A field as typed: surrounding spaces trimmed, a comma read as a decimal point (decimal pads
  /// in many regions show `,`).
  static func cleaned(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
  }

  private var cleanFeet: String { Self.cleaned(feet) }
  private var cleanInches: String { Self.cleaned(inches) }
  private var cleanValue: String { Self.cleaned(value) }

  /// Nothing typed in the fields of the current unit.
  public var isEmpty: Bool {
    unit == .ftIn ? cleanFeet.isEmpty && cleanInches.isEmpty : cleanValue.isEmpty
  }

  /// The text stored verbatim in `measurement.enteredText`: `10' 0.5"` (both fields), `10'`
  /// (feet only), `96"` (inches only), or the typed number for mm and m (`3061`, `3.061`).
  public var enteredText: String {
    guard unit == .ftIn else { return cleanValue }
    switch (cleanFeet.isEmpty, cleanInches.isEmpty) {
    case (false, false): return "\(cleanFeet)' \(cleanInches)\""
    case (false, true): return "\(cleanFeet)'"
    case (true, false): return "\(cleanInches)\""
    case (true, true): return ""
    }
  }

  /// The parsed length, or why it is refused. Feet must be a whole number and inches a decimal
  /// before the text is parsed; `LengthParser` then applies its exact rules and messages.
  public var result: Result<ParsedLength, LengthParseError> {
    if unit == .ftIn {
      if !cleanFeet.isEmpty, !Self.isWholeNumber(cleanFeet) {
        return .failure(.invalidFormat(Self.wholeFeetMessage))
      }
      if !cleanInches.isEmpty, !Self.isDecimal(cleanInches) {
        return .failure(.invalidFormat(Self.inchesMessage))
      }
    }
    return Result { try LengthParser.parse(enteredText, unit: unit) }
      .mapError { $0 as? LengthParseError ?? .invalidFormat("Enter a measurement.") }
  }

  /// The message under the card for a value that is typed but refused; nil when empty or valid,
  /// and while a decimal is half typed (`10.`, before the `5`), which cannot be saved either.
  public var errorMessage: String? {
    guard !isEmpty, case .failure(let error) = result else { return nil }
    let typing = unit == .ftIn ? cleanInches : cleanValue
    if typing.hasSuffix("."), Self.isDecimal(String(typing.dropLast()) + "0") {
      if unit != .ftIn || cleanFeet.isEmpty || Self.isWholeNumber(cleanFeet) { return nil }
    }
    return error.message
  }

  /// `3,061 mm` once the value parses (`Stored as 3,061 mm.`), otherwise nil.
  public var storedText: String? {
    guard case .success(let parsed) = result else { return nil }
    return LengthFormatter.millimetres(parsed.valueMm)
  }

  /// Both units, `7,518 mm · 24' 8"`, once the value parses.
  public var bothUnits: String? {
    guard case .success(let parsed) = result else { return nil }
    return LengthFormatter.both(parsed.valueMm)
  }

  public func measurement(recordedAt: UTCTimestamp) throws -> FieldControls.Measurement {
    let parsed = try result.get()
    return FieldControls.Measurement(
      valueMm: parsed.valueMm, enteredUnit: parsed.unit, enteredText: parsed.enteredText,
      method: method, recordedAt: recordedAt)
  }

  /// The same unit and method with empty fields: the unit changed, so the fields are cleared (the
  /// operator types what the instrument shows in that unit; nothing is converted silently).
  public func cleared(unit: EnteredUnit) -> MeasurementEntryDraft {
    MeasurementEntryDraft(unit: unit, method: method)
  }

  /// The fields of a recorded measurement, to edit it: ft-in → feet and inches from the stored
  /// text (`10 1/2` → `10.5`); mm or m → the stored text without its unit; any other unit (never
  /// offered by the app) → empty fields in `defaultUnit`. The method is kept.
  public static func editing(
    _ measurement: FieldControls.Measurement, defaultUnit: EnteredUnit = .ftIn
  ) -> MeasurementEntryDraft {
    switch measurement.enteredUnit {
    case .ftIn:
      guard let split = try? LengthParser.feetAndInches(measurement.enteredText) else {
        return MeasurementEntryDraft(unit: .ftIn, method: measurement.method)
      }
      return MeasurementEntryDraft(
        unit: .ftIn, feet: String(split.feet), inches: split.inches, method: measurement.method)
    case .mm, .m:
      let suffix = measurement.enteredUnit == .mm ? "mm" : "m"
      var text = measurement.enteredText.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.lowercased().hasSuffix(suffix) { text = String(text.dropLast(suffix.count)) }
      return MeasurementEntryDraft(
        unit: measurement.enteredUnit, value: text.filter { !$0.isWhitespace },
        method: measurement.method)
    case .cm, .inches, .ft:
      return MeasurementEntryDraft(unit: defaultUnit, method: measurement.method)
    }
  }

  private static func isWholeNumber(_ text: String) -> Bool {
    (1...9).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isNumber }
  }

  /// `10`, `0.5`, `10.25`, `.5`.
  private static func isDecimal(_ text: String) -> Bool {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2 else { return false }
    let whole = parts[0]
    let fraction = parts.count == 2 ? parts[1] : ""
    let digits: (Substring) -> Bool = { $0.allSatisfy { $0.isASCII && $0.isNumber } }
    return digits(whole) && digits(fraction) && !(whole.isEmpty && fraction.isEmpty)
      && !(parts.count == 2 && fraction.isEmpty)
  }
}
