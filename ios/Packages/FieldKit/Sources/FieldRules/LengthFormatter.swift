import Foundation

/// Display text for stored millimetre values, so a measurement can be shown in both units.
public enum LengthFormatter {
  /// Whole millimetres with a space between thousands, for example `7 518 mm`.
  public static func millimetres(_ valueMm: Double) -> String {
    let whole = Int(valueMm.rounded())
    let digits = String(whole)
    var grouped = ""
    for (offset, character) in digits.reversed().enumerated() {
      if offset > 0, offset % 3 == 0 { grouped.append(" ") }
      grouped.append(character)
    }
    return String(grouped.reversed()) + " mm"
  }

  /// `2 690 – 2 740 mm`, or `2 690 mm` when both round to the same millimetre.
  public static func millimetreRange(_ low: Double, _ high: Double) -> String {
    let lowText = millimetres(low)
    let highText = millimetres(high)
    guard lowText != highText else { return lowText }
    return "\(lowText.dropLast(3)) \u{2013} \(highText)"
  }

  /// Feet and inches to the nearest 1/16 in, for example `24′ 8″` or `36′ 10½″`.
  public static func feetInches(_ valueMm: Double) -> String {
    let sixteenths = Int((valueMm / 25.4 * 16).rounded())
    let feet = sixteenths / (12 * 16)
    let remainder = sixteenths % (12 * 16)
    let inches = remainder / 16
    let fraction = fractionText(sixteenths: remainder % 16)
    return "\(feet)\u{2032} \(inches)\(fraction)\u{2033}"
  }

  /// Both units on one line, for example `7 518 mm · 24′ 8″`.
  public static func both(_ valueMm: Double) -> String {
    "\(millimetres(valueMm)) · \(feetInches(valueMm))"
  }

  private static func fractionText(sixteenths: Int) -> String {
    switch sixteenths {
    case 0: return ""
    case 2: return "\u{215B}"
    case 4: return "\u{00BC}"
    case 6: return "\u{215C}"
    case 8: return "\u{00BD}"
    case 10: return "\u{215D}"
    case 12: return "\u{00BE}"
    case 14: return "\u{215E}"
    default: return " \(sixteenths)/16"
    }
  }
}
