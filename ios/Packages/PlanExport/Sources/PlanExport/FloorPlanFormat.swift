import CaptureContract
import Foundation

/// How the floor plan drawing writes lengths and areas. Imperial is the default (feet and
/// inches to a tenth of an inch, square feet to one decimal); metric writes metres to the
/// centimetre and square metres to one decimal.
public enum FloorPlanUnits: String, Hashable, Sendable, CaseIterable {
  /// `10' 0.3"`, `192.1 ft²`.
  case feetInchesTenths
  /// `10' 0"`, `192.1 ft²`.
  case feetInchesWhole
  /// `3.05 m`, `17.8 m²`.
  case metres

  public init(_ system: DisplayUnitSystem) {
    self = system == .metric ? .metres : .feetInchesTenths
  }

  public var isMetric: Bool { self == .metres }

  /// A length label.
  public func length(metres: Double) -> String {
    switch self {
    case .feetInchesTenths:
      let tenths = Int((abs(metres) / 0.00254).rounded())
      let sign = metres < 0 && tenths > 0 ? "-" : ""
      return "\(sign)\(tenths / 120)' \((tenths % 120) / 10).\(tenths % 10)\""
    case .feetInchesWhole:
      let inches = Int((abs(metres) / 0.0254).rounded())
      let sign = metres < 0 && inches > 0 ? "-" : ""
      return "\(sign)\(inches / 12)' \(inches % 12)\""
    case .metres:
      return "\(Format.fixed(metres, 2)) m"
    }
  }

  /// An area label, square feet or square metres to one decimal.
  public func area(squareMetres: Double) -> String {
    switch self {
    case .feetInchesTenths, .feetInchesWhole:
      return "\(Format.squareFeet(squareMetres: squareMetres)) ft\u{00B2}"
    case .metres:
      return "\(Format.fixed(squareMetres, 1)) m\u{00B2}"
    }
  }

  /// Scale bar length in metres and its label: a round number of feet or metres whose paper
  /// length at 1:`scaleDenominator` is closest to 20 mm.
  func scaleBar(scaleDenominator: Double) -> (metres: Double, label: String) {
    let target = 0.020 * scaleDenominator
    if isMetric {
      let choices = [0.25, 0.5, 1, 2, 5, 10, 20, 50]
      let best = choices.min { abs(log($0 / target)) < abs(log($1 / target)) }!
      return (best, "\(Format.compact(best)) m")
    }
    let choices = [1.0, 2, 3, 5, 10, 20, 50, 100, 200]
    let best = choices.min { abs(log($0 * 0.3048 / target)) < abs(log($1 * 0.3048 / target)) }!
    return (best * 0.3048, "\(Int(best)) ft")
  }
}
