import CaptureContract
import Foundation

/// How a length is written.
public enum LengthStyle: String, CaseIterable, Hashable, Sendable {
  /// Feet and inches to a tenth of an inch, for example `6' 2.0"`.
  case feetInchesTenths
  /// Whole feet and inches, for example `6' 2"`.
  case feetInches
  /// Whole inches, for example `74"`.
  case inches
  /// Feet to two decimals, for example `6.16'`.
  case decimalFeet
  /// Metres to two decimals, for example `1.88 m`.
  case metres
  /// Whole centimetres, for example `188 cm`.
  case centimetres
  /// Whole millimetres, for example `1879 mm`.
  case millimetres
}

/// The one formatter for measurements in reports, plans and screens. Locale independent.
///
/// Imperial: lengths in feet-inches to 0.1 in by default, areas in ft² to one decimal, volumes in
/// ft³ to two decimals. Metric: lengths in metres to two decimals by default, areas in m² and
/// volumes in m³ to two decimals.
///
/// Rounding is to the nearest step, half away from zero. A value within a millionth of a step of
/// a half counts as that half, so that a length entered in inches and stored in metres prints
/// back as entered. Feet-inches are rounded as a whole before they are split, so 11.96 in prints
/// as `1' 0.0"`, never `0' 12.0"`. Negative values get a leading `-`; zero never does. A value
/// that is not a finite number prints as `-`.
public struct UnitFormatter: Hashable, Sendable {
  public static let metresPerInch = 0.0254
  public static let metresPerFoot = 0.3048
  public static let squareMetresPerSquareFoot = 0.092_903_04
  public static let cubicMetresPerCubicFoot = 0.028_316_846_592

  public var system: DisplayUnitSystem
  public var lengthStyle: LengthStyle

  /// `lengthStyle` defaults to feet-inches to 0.1 in for imperial and metres for metric.
  public init(system: DisplayUnitSystem, lengthStyle: LengthStyle? = nil) {
    self.system = system
    self.lengthStyle = lengthStyle ?? (system == .imperial ? .feetInchesTenths : .metres)
  }

  /// A length given in metres, in `lengthStyle`.
  public func length(_ metres: Double) -> String {
    Self.length(metres, style: lengthStyle)
  }

  /// A floor or wall area given in square metres: `300.1 ft²` or `27.88 m²`.
  public func area(_ squareMetres: Double) -> String {
    switch system {
    case .imperial: return Self.squareFeet(squareMetres)
    case .metric: return Self.squareMetres(squareMetres)
    }
  }

  /// A volume given in cubic metres: `2476.67 ft³` or `70.13 m³`.
  public func volume(_ cubicMetres: Double) -> String {
    switch system {
    case .imperial: return Self.cubicFeet(cubicMetres)
    case .metric: return Self.cubicMetres(cubicMetres)
    }
  }

  // MARK: Fixed formats

  public static func length(_ metres: Double, style: LengthStyle) -> String {
    switch style {
    case .feetInchesTenths:
      guard let tenths = steps(metres / metresPerInch, of: 0.1) else { return invalid }
      let magnitude = tenths.magnitude
      let feet = magnitude / 120
      let inchTenths = magnitude % 120
      return "\(sign(tenths))\(feet)' \(inchTenths / 10).\(inchTenths % 10)\""
    case .feetInches:
      guard let inches = steps(metres / metresPerInch, of: 1) else { return invalid }
      return "\(sign(inches))\(inches.magnitude / 12)' \(inches.magnitude % 12)\""
    case .inches:
      guard let inches = steps(metres / metresPerInch, of: 1) else { return invalid }
      return "\(inches)\""
    case .decimalFeet:
      return decimals(metres / metresPerFoot, places: 2).map { "\($0)'" } ?? invalid
    case .metres:
      return decimals(metres, places: 2).map { "\($0) m" } ?? invalid
    case .centimetres:
      return steps(metres * 100, of: 1).map { "\($0) cm" } ?? invalid
    case .millimetres:
      return steps(metres * 1000, of: 1).map { "\($0) mm" } ?? invalid
    }
  }

  /// Square feet to one decimal, for example `300.1 ft²`.
  public static func squareFeet(_ squareMetres: Double) -> String {
    decimals(squareMetres / squareMetresPerSquareFoot, places: 1).map { "\($0) ft\u{00B2}" }
      ?? invalid
  }

  /// Cubic feet to two decimals, for example `2476.67 ft³`.
  public static func cubicFeet(_ cubicMetres: Double) -> String {
    decimals(cubicMetres / cubicMetresPerCubicFoot, places: 2).map { "\($0) ft\u{00B3}" }
      ?? invalid
  }

  /// Square metres to two decimals, for example `27.88 m²`.
  public static func squareMetres(_ squareMetres: Double) -> String {
    decimals(squareMetres, places: 2).map { "\($0) m\u{00B2}" } ?? invalid
  }

  /// Cubic metres to two decimals, for example `70.13 m³`.
  public static func cubicMetres(_ cubicMetres: Double) -> String {
    decimals(cubicMetres, places: 2).map { "\($0) m\u{00B3}" } ?? invalid
  }

  // MARK: Rounding

  private static let invalid = "-"

  /// A millionth of a step: how close to a half a value must be to round as that half.
  private static let tieTolerance = 1e-6

  /// `value / step` rounded half away from zero to a whole number of steps; nil when the value
  /// is not finite or too large to count.
  static func steps(_ value: Double, of step: Double) -> Int? {
    let scaled = value / step
    guard scaled.isFinite, scaled.magnitude < 1e15 else { return nil }
    let rounded = (scaled.magnitude + tieTolerance).rounded(.toNearestOrAwayFromZero)
    let count = Int(rounded)
    return scaled < 0 ? -count : count
  }

  /// `value` with exactly `places` decimals, for example `6.16` or `300.1`.
  static func decimals(_ value: Double, places: Int) -> String? {
    var unit = 1
    for _ in 0..<places { unit *= 10 }
    guard let count = steps(value, of: 1 / Double(unit)) else { return nil }
    let magnitude = count.magnitude
    let whole = magnitude / UInt(unit)
    guard places > 0 else { return "\(sign(count))\(whole)" }
    var fraction = String(magnitude % UInt(unit))
    while fraction.count < places { fraction = "0" + fraction }
    return "\(sign(count))\(whole).\(fraction)"
  }

  private static func sign(_ count: Int) -> String { count < 0 ? "-" : "" }
}
