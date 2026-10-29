import CaptureContract
import Foundation

/// The text a length would have had if typed in the operator's units, in the shape FieldKit's
/// `LengthFormatter` and `LengthParser` use (FieldKit is not a dependency of this target): whole
/// millimetres for metric (`4012`), feet and inches to 0.1 in for imperial (`13' 1.5"`). The
/// same as the walkthrough converter's.
enum SketchReadingText {
  static func unit(_ units: DisplayUnitSystem) -> EnteredUnit {
    units == .imperial ? .ftIn : .mm
  }

  static func text(_ valueMm: Double, units: DisplayUnitSystem) -> String {
    switch units {
    case .metric:
      return "\(Int(valueMm.rounded()))"
    case .imperial:
      let tenths = Int((valueMm / 2.54).rounded())  // tenths of an inch
      let feet = tenths / 120
      let inchTenths = tenths % 120
      let fraction = inchTenths % 10 == 0 ? "" : ".\(inchTenths % 10)"
      return "\(feet)' \(inchTenths / 10)\(fraction)\""
    }
  }

  /// A value for people in notes: "8.7" from 8.6957, no trailing ".0".
  static func number(_ value: Double, places: Int) -> String {
    let factor = pow(10, Double(places))
    var text = String((value * factor).rounded() / factor)
    if text.hasSuffix(".0") { text.removeLast(2) }
    return text
  }
}

/// Rounding with no negative zero.
func rounded(_ value: Double, places: Int) -> Double {
  let factor = pow(10, Double(places))
  let result = (value * factor).rounded() / factor
  return result == 0 ? 0 : result
}

/// An angle in degrees brought into (−180, 180].
func normalizedDegrees(_ degrees: Double) -> Double {
  var angle = degrees.truncatingRemainder(dividingBy: 360)
  if angle <= -180 { angle += 360 }
  if angle > 180 { angle -= 360 }
  return angle
}

/// Metres rounded to a micrometre with no negative zero.
func micrometres(_ metres: Double) -> Double {
  rounded(metres, places: 6)
}

/// The median of a non-empty list (the mean of the middle two for an even count).
func median(_ values: [Double]) -> Double {
  let sorted = values.sorted()
  let middle = sorted.count / 2
  if sorted.count % 2 == 1 { return sorted[middle] }
  let low: Double = sorted[middle - 1]
  let high: Double = sorted[middle]
  return (low + high) / 2
}
