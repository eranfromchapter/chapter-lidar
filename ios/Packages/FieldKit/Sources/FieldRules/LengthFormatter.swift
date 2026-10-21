import Foundation

/// Display text for stored millimetre values, so a measurement can be shown in both units
/// (phone-field §8): comma thousands and ASCII feet and inch marks (`7,520 mm`, `24' 8.1"`),
/// locale independent. Stored values are always millimetres.
///
/// Rounding is exact: a stored value has at most 4 decimals of a millimetre (`LengthParser`), so
/// it is read as a whole number of ten-thousandths and rounded with integer arithmetic, half away
/// from zero. Feet and inches are rounded to 0.1 in as a whole before they are split, so 11.96 in
/// prints as `1' 0"`, never `0' 12"`.
public enum LengthFormatter {
  /// Whole millimetres with a comma every 3 digits: `7,520 mm`, `3,061 mm` (3060.7), `914 mm`.
  public static func millimetres(_ valueMm: Double) -> String {
    "\(grouped(roundedQuotient(tenThousandths(valueMm), 10_000))) mm"
  }

  /// `2,690–2,740 mm` (en dash, no spaces), or `2,690 mm` when both round to the same millimetre.
  public static func millimetreRange(_ low: Double, _ high: Double) -> String {
    let lowMm = roundedQuotient(tenThousandths(low), 10_000)
    let highMm = roundedQuotient(tenThousandths(high), 10_000)
    guard lowMm != highMm else { return "\(grouped(lowMm)) mm" }
    return "\(grouped(lowMm))\u{2013}\(grouped(highMm)) mm"
  }

  /// Feet and inches to 0.1 in with ASCII marks; a trailing `.0` is dropped: `24' 8"` (7518.4),
  /// `24' 8.1"` (7520), `36' 10.5"` (11239.5), `5' 0"` (1524).
  public static func feetInches(_ valueMm: Double) -> String {
    // 1 in = 25.4 mm = 254,000 ten-thousandths of a mm, so a tenth of an inch is 25,400 of them.
    let tenths = roundedQuotient(tenThousandths(valueMm), 25_400)
    let sign = tenths < 0 ? "-" : ""
    let magnitude = abs(tenths)
    let feet = magnitude / 120
    let inchTenths = magnitude % 120
    let fraction = inchTenths % 10 == 0 ? "" : ".\(inchTenths % 10)"
    return "\(sign)\(feet)' \(inchTenths / 10)\(fraction)\""
  }

  /// Both units on one line: `7,520 mm · 24' 8.1"`.
  public static func both(_ valueMm: Double) -> String {
    "\(millimetres(valueMm)) \u{00B7} \(feetInches(valueMm))"
  }

  /// What VoiceOver reads for `millimetres(_:)`: `7,520 millimetres`.
  public static func spokenMillimetres(_ valueMm: Double) -> String {
    "\(grouped(roundedQuotient(tenThousandths(valueMm), 10_000))) millimetres"
  }

  /// What VoiceOver reads for `feetInches(_:)`: `24 feet 8.1 inches`.
  public static func spokenFeetInches(_ valueMm: Double) -> String {
    let text = feetInches(valueMm).dropLast()  // the inch mark
    let parts = text.split(separator: "'", maxSplits: 1).map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    guard parts.count == 2 else { return String(text) }
    return "\(parts[0]) feet \(parts[1]) inches"
  }

  // MARK: Exact arithmetic

  /// The value in whole ten-thousandths of a millimetre (exact for stored values).
  private static func tenThousandths(_ valueMm: Double) -> Int {
    guard valueMm.isFinite else { return 0 }
    return Int((valueMm * 10_000).rounded())
  }

  /// `value / divisor` rounded half away from zero.
  private static func roundedQuotient(_ value: Int, _ divisor: Int) -> Int {
    let magnitude = (2 * abs(value) + divisor) / (2 * divisor)
    return value < 0 ? -magnitude : magnitude
  }

  /// `7520` → `7,520`; `-1200` → `-1,200`.
  private static func grouped(_ value: Int) -> String {
    let digits = String(abs(value))
    var result = ""
    for (offset, character) in digits.reversed().enumerated() {
      if offset > 0, offset % 3 == 0 { result.append(",") }
      result.append(character)
    }
    return (value < 0 ? "-" : "") + String(result.reversed())
  }
}
