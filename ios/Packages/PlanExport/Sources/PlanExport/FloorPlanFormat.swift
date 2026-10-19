import Foundation

// The floor plan drawing writes its lengths and areas with the package's one `UnitFormatter`
// (`FloorPlanDrawing.Options.units`), so the plan prints the same strings as the reports.
// Only the scale bar, which the formatter does not cover, is chosen here.

extension LengthStyle {
  /// Metres, centimetres or millimetres.
  var isMetric: Bool {
    switch self {
    case .metres, .centimetres, .millimetres: return true
    case .feetInchesTenths, .feetInches, .inches, .decimalFeet: return false
    }
  }
}

extension UnitFormatter {
  /// Scale bar length in metres and its label: a round number of feet or metres whose paper
  /// length at 1:`scaleDenominator` is closest to 20 mm. The bar is in metres when lengths are
  /// written in a metric style, so it reads in the same unit as the dimensions next to it.
  func scaleBar(scaleDenominator: Double) -> (metres: Double, label: String) {
    let target = 0.020 * scaleDenominator
    if lengthStyle.isMetric {
      let choices = [0.25, 0.5, 1, 2, 5, 10, 20, 50]
      let best = choices.min { abs(log($0 / target)) < abs(log($1 / target)) }!
      return (best, "\(Format.compact(best)) m")
    }
    let foot = Self.metresPerFoot
    let choices = [1.0, 2, 3, 5, 10, 20, 50, 100, 200]
    let best = choices.min { abs(log($0 * foot / target)) < abs(log($1 * foot / target)) }!
    return (best * foot, "\(Int(best)) ft")
  }
}
