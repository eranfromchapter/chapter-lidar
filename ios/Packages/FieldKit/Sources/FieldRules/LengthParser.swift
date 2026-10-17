import CaptureContract
import Foundation

/// Why an entered length was refused. `message` is the text shown under the field.
public enum LengthParseError: Error, Equatable, Sendable, CustomStringConvertible {
  case empty
  case invalidFormat(String)
  case notPositive
  case tooLarge
  /// The exact value needs more than 4 decimal places in millimetres, so it cannot be stored
  /// exactly. Nothing is ever rounded silently.
  case tooPrecise
  case unsupportedFraction
  case inchesOutOfRange
  case textTooLong

  public var message: String {
    switch self {
    case .empty: return "Enter a measurement."
    case .invalidFormat(let hint): return hint
    case .notPositive: return "The measurement must be greater than zero."
    case .tooLarge: return "The measurement is larger than 200 m."
    case .tooPrecise: return "Too many decimal places. Enter what the tape or laser shows."
    case .unsupportedFraction: return "Use halves, quarters, eighths or sixteenths of an inch."
    case .inchesOutOfRange: return "Inches must be less than 12 when feet are given."
    case .textTooLong: return "Enter at most 40 characters."
    }
  }

  public var description: String { message }
}

/// An entered length converted to millimetres.
public struct ParsedLength: Hashable, Sendable {
  /// Exact value in millimetres (see `LengthParser` for the exactness rule).
  public let valueMm: Double
  public let unit: EnteredUnit
  /// The text exactly as entered, trimmed of surrounding whitespace.
  public let enteredText: String
}

/// Converts what the operator typed into millimetres, exactly.
///
/// Conversion rule (documented because the schema only says "millimetres"):
/// - 1 in = 25.4 mm, 1 ft = 304.8 mm, 1 cm = 10 mm, 1 m = 1000 mm, all exact.
/// - The entered text is read as an exact rational number (decimals and tape fractions with
///   denominators 2, 4, 8 or 16), converted with integer arithmetic, never with floating point.
/// - The result is stored with at most 4 decimal places of a millimetre. A value that would need
///   more is refused (`LengthParseError.tooPrecise`) instead of being rounded, so every stored
///   `valueMm` is exactly the entered length. Example: 24' 8" is 7518.4 mm and 36' 10 1/2" is
///   11239.5 mm; 1/16 in is 1.5875 mm.
/// - The decimal string is converted to the nearest `Double`, which JSON writes back as the same
///   shortest decimal (7518.4, not 7518.400000000001).
/// - Accepted range: greater than 0 and at most 200 000 mm (schema `measurement.valueMm`).
///
/// Accepted spellings per unit:
/// - mm, cm, m, ft: a plain decimal with `.`, an optional trailing unit symbol, spaces ignored
///   ("2690", "2 690 mm", "2.69 m").
/// - in: a decimal, a fraction or a mixed number ("36", "10 1/2", "0.75"), optional `"` or "in".
/// - ft_in: feet and inches ("24' 8\"", "24 8", "36' 10 1/2\"", "36-10 1/2", "5'", "96\""). A bare
///   number without a feet or inch mark is refused because it is ambiguous.
public enum LengthParser {
  /// Longest value the schema allows, in millimetres.
  public static let maximumMm = 200_000
  /// Longest `enteredText` the schema allows.
  public static let maximumTextLength = 40
  /// Denominators of tape fractions that convert exactly.
  public static let fractionDenominators: [Int] = [2, 4, 8, 16]

  public static func parse(_ text: String, unit: EnteredUnit) throws -> ParsedLength {
    let entered = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !entered.isEmpty else { throw LengthParseError.empty }
    guard entered.count <= maximumTextLength else { throw LengthParseError.textTooLong }

    let mm: Rational
    switch unit {
    case .mm:
      mm = try decimalMm(entered, suffixes: ["mm"], millimetresPerUnit: Rational(1, 1))
    case .cm:
      mm = try decimalMm(entered, suffixes: ["cm"], millimetresPerUnit: Rational(10, 1))
    case .m:
      mm = try decimalMm(entered, suffixes: ["m"], millimetresPerUnit: Rational(1000, 1))
    case .ft:
      mm = try decimalMm(
        entered, suffixes: ["ft", "'", "\u{2032}"], millimetresPerUnit: Rational(3048, 10))
    case .inches:
      var body = entered.lowercased()
      for suffix in ["inches", "inch", "in", "\"", "\u{2033}"] where body.hasSuffix(suffix) {
        body = String(body.dropLast(suffix.count))
        break
      }
      let inches = try parseInches(body)
      mm = try inches.times(Rational(254, 10))
    case .ftIn:
      mm = try parseFeetInches(entered).times(Rational(254, 10))
    }
    return ParsedLength(
      valueMm: try storedMillimetres(mm), unit: unit, enteredText: entered)
  }

  // MARK: Exact arithmetic

  /// Non-negative rational number with overflow-checked 64-bit arithmetic.
  struct Rational: Equatable {
    var numerator: Int
    var denominator: Int

    init(_ numerator: Int, _ denominator: Int) {
      self.numerator = numerator
      self.denominator = denominator
    }

    func times(_ other: Rational) throws -> Rational {
      let n = numerator.multipliedReportingOverflow(by: other.numerator)
      let d = denominator.multipliedReportingOverflow(by: other.denominator)
      guard !n.overflow, !d.overflow else { throw LengthParseError.tooLarge }
      return Rational(n.partialValue, d.partialValue).reduced()
    }

    func plus(_ other: Rational) throws -> Rational {
      let a = numerator.multipliedReportingOverflow(by: other.denominator)
      let b = other.numerator.multipliedReportingOverflow(by: denominator)
      let d = denominator.multipliedReportingOverflow(by: other.denominator)
      guard !a.overflow, !b.overflow, !d.overflow else { throw LengthParseError.tooLarge }
      let n = a.partialValue.addingReportingOverflow(b.partialValue)
      guard !n.overflow else { throw LengthParseError.tooLarge }
      return Rational(n.partialValue, d.partialValue).reduced()
    }

    func reduced() -> Rational {
      var a = numerator
      var b = denominator
      while b != 0 { (a, b) = (b, a % b) }
      guard a > 1 else { return self }
      return Rational(numerator / a, denominator / a)
    }
  }

  /// Millimetres as a whole number of ten-thousandths, then a `Double`.
  private static func storedMillimetres(_ mm: Rational) throws -> Double {
    guard mm.numerator > 0 else { throw LengthParseError.notPositive }
    let scaledNumerator = mm.numerator.multipliedReportingOverflow(by: 10_000)
    guard !scaledNumerator.overflow else { throw LengthParseError.tooLarge }
    guard scaledNumerator.partialValue % mm.denominator == 0 else {
      throw LengthParseError.tooPrecise
    }
    let scaled = scaledNumerator.partialValue / mm.denominator
    guard scaled <= maximumMm * 10_000 else { throw LengthParseError.tooLarge }
    let whole = scaled / 10_000
    let fraction = String(scaled % 10_000)
    let padded = String(repeating: "0", count: 4 - fraction.count) + fraction
    guard let value = Double("\(whole).\(padded)") else { throw LengthParseError.tooLarge }
    return value
  }

  // MARK: Plain decimals (mm, cm, m, ft)

  private static func decimalMm(
    _ text: String, suffixes: [String], millimetresPerUnit: Rational
  ) throws -> Rational {
    var body = text.lowercased().filter { !$0.isWhitespace }
    for suffix in suffixes where body.hasSuffix(suffix) {
      body = String(body.dropLast(suffix.count))
      break
    }
    return try parseDecimal(body).times(millimetresPerUnit)
  }

  /// `123`, `12.5`, `.5`. No sign, no exponent, no comma, no trailing dot.
  private static func parseDecimal(_ text: String) throws -> Rational {
    let hint = "Enter a number such as 2690 or 2.69."
    guard !text.isEmpty else { throw LengthParseError.empty }
    if text.hasPrefix("-") { throw LengthParseError.notPositive }
    let parts = text.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count <= 2 else { throw LengthParseError.invalidFormat(hint) }
    let whole = String(parts[0])
    let fraction = parts.count == 2 ? String(parts[1]) : ""
    guard whole.allSatisfy(isASCIIDigit), fraction.allSatisfy(isASCIIDigit),
      !(whole.isEmpty && fraction.isEmpty), !(parts.count == 2 && fraction.isEmpty)
    else { throw LengthParseError.invalidFormat(hint) }
    guard whole.count + fraction.count <= 15 else { throw LengthParseError.tooLarge }
    guard let digits = Int(whole + fraction) else { throw LengthParseError.invalidFormat(hint) }
    var denominator = 1
    for _ in 0..<fraction.count { denominator *= 10 }
    return Rational(digits, denominator).reduced()
  }

  // MARK: Inches and feet-inches

  private static let feetInchesHint = "Enter feet and inches, for example 24' 8\" or 36' 10 1/2\"."

  private static func isASCIIDigit(_ character: Character) -> Bool {
    character.isASCII && character.isNumber
  }

  private static func parseWholeNumber(_ text: String) throws -> Int {
    guard !text.isEmpty, text.allSatisfy(isASCIIDigit), text.count <= 9, let value = Int(text)
    else { throw LengthParseError.invalidFormat(feetInchesHint) }
    return value
  }

  /// A decimal (`8`, `8.5`), a fraction (`1/2`) or a mixed number (`10 1/2`) of inches.
  private static func parseInches(_ text: String) throws -> Rational {
    let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    switch tokens.count {
    case 1:
      if tokens[0].contains("/") { return try parseFraction(tokens[0]) }
      return try parseDecimal(tokens[0])
    case 2:
      guard !tokens[0].contains("/"), tokens[1].contains("/") else {
        throw LengthParseError.invalidFormat(feetInchesHint)
      }
      return try Rational(parseWholeNumber(tokens[0]), 1).plus(parseFraction(tokens[1]))
    default:
      throw LengthParseError.invalidFormat(feetInchesHint)
    }
  }

  private static func parseFraction(_ text: String) throws -> Rational {
    let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2 else { throw LengthParseError.invalidFormat(feetInchesHint) }
    let numerator = try parseWholeNumber(parts[0])
    let denominator = try parseWholeNumber(parts[1])
    guard fractionDenominators.contains(denominator), numerator >= 1, numerator < denominator
    else { throw LengthParseError.unsupportedFraction }
    return Rational(numerator, denominator).reduced()
  }

  private static func parseFeetInches(_ text: String) throws -> Rational {
    var body = text.lowercased()
    for prime in ["\u{2032}", "\u{2019}", "\u{2018}"] {
      body = body.replacingOccurrences(of: prime, with: "'")
    }
    for prime in ["\u{2033}", "\u{201D}", "\u{201C}"] {
      body = body.replacingOccurrences(of: prime, with: "\"")
    }
    for word in ["feet", "foot", "ft"] { body = body.replacingOccurrences(of: word, with: "'") }
    for word in ["inches", "inch", "in"] { body = body.replacingOccurrences(of: word, with: "\"") }
    body = body.replacingOccurrences(of: "-", with: " ")

    guard body.filter({ $0 == "'" }).count <= 1, body.filter({ $0 == "\"" }).count <= 1 else {
      throw LengthParseError.invalidFormat(feetInchesHint)
    }
    let hasInchMark = body.contains("\"")
    if hasInchMark {
      guard body.hasSuffix("\"") else { throw LengthParseError.invalidFormat(feetInchesHint) }
      body.removeLast()
    }

    let feetText: String
    let inchesText: String
    if let mark = body.firstIndex(of: "'") {
      feetText = String(body[..<mark]).trimmingCharacters(in: .whitespaces)
      inchesText = String(body[body.index(after: mark)...]).trimmingCharacters(in: .whitespaces)
    } else if hasInchMark {
      feetText = ""
      inchesText = body.trimmingCharacters(in: .whitespaces)
    } else {
      let tokens = body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      guard tokens.count >= 2 else { throw LengthParseError.invalidFormat(feetInchesHint) }
      feetText = tokens[0]
      inchesText = tokens.dropFirst().joined(separator: " ")
    }

    let hasFeet = !feetText.isEmpty
    let feet = try hasFeet ? parseWholeNumber(feetText) : 0
    guard hasFeet || !inchesText.isEmpty else {
      throw LengthParseError.invalidFormat(feetInchesHint)
    }
    let inches = try inchesText.isEmpty ? Rational(0, 1) : parseInches(inchesText)
    if hasFeet, inches.numerator >= 12 * inches.denominator {
      throw LengthParseError.inchesOutOfRange
    }
    return try Rational(feet * 12, 1).plus(inches)
  }
}
