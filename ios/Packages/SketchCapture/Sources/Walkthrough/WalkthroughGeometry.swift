import CaptureContract
import Foundation

/// A point or vector on the floor while converting a walkthrough, in metres. `x` is the AR (and
/// model) x; `y` is the AR −z, "up the sheet" seen from +Y. As in the solver's plan maths, that
/// makes a left turn a +90° rotation and a counter-clockwise loop (seen from +Y) one with a
/// positive shoelace area, so the usual formulas hold unchanged.
struct FloorPoint: Hashable, Sendable {
  var x: Double
  var y: Double

  init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }

  /// A tap projected to the floor: its height dropped.
  init(_ point: Vec3) {
    self.init(point.x, -point.z)
  }

  static func + (a: FloorPoint, b: FloorPoint) -> FloorPoint { FloorPoint(a.x + b.x, a.y + b.y) }
  static func - (a: FloorPoint, b: FloorPoint) -> FloorPoint { FloorPoint(a.x - b.x, a.y - b.y) }
  static func * (a: FloorPoint, s: Double) -> FloorPoint { FloorPoint(a.x * s, a.y * s) }

  func dot(_ other: FloorPoint) -> Double { x * other.x + y * other.y }

  /// The z component of the cross product; positive when `other` is to the left of `self`.
  func cross(_ other: FloorPoint) -> Double { x * other.y - y * other.x }

  var length: Double { (x * x + y * y).squareRoot() }

  var normalized: FloorPoint? {
    let l = length
    return l > 1e-12 ? self * (1 / l) : nil
  }

  /// Angle from +x, counter-clockwise seen from +Y, in radians.
  var angle: Double { atan2(y, x) }

  /// The point in the model frame (floor at y `floorY`), rounded to a micrometre.
  func vec3(floorY: Double = 0) -> Vec3 {
    Vec3(x: micrometres(x), y: floorY, z: micrometres(-y))
  }

  /// Twice the signed area of the loop: positive when counter-clockwise seen from +Y.
  static func signedArea2(_ loop: [FloorPoint]) -> Double {
    guard loop.count >= 3 else { return 0 }
    var sum = 0.0
    for index in loop.indices {
      sum += loop[index].cross(loop[(index + 1) % loop.count])
    }
    return sum
  }
}

/// A wall line on the floor: a point on it and its unit direction.
struct FloorLine: Hashable, Sendable {
  var point: FloorPoint
  var direction: FloorPoint

  /// Two consecutive walls closer than this to parallel have no corner worth the name: their
  /// intersection would run off by metres for a few millimetres of tap noise.
  static let parallelSine = sin(1.0 * Double.pi / 180)

  /// The line through the taps: through both for two, the total least squares fit (the
  /// principal axis through the centroid) for three or more. Directed from the first tap
  /// towards the last. Nil when the taps do not span a direction.
  static func fit(_ points: [FloorPoint]) -> FloorLine? {
    guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
    if points.count == 2 {
      guard let direction = (last - first).normalized else { return nil }
      return FloorLine(point: first, direction: direction)
    }
    let count = Double(points.count)
    let centroid = FloorPoint(
      points.reduce(0) { $0 + $1.x } / count, points.reduce(0) { $0 + $1.y } / count)
    var sxx = 0.0
    var sxy = 0.0
    var syy = 0.0
    for point in points {
      let d = point - centroid
      sxx += d.x * d.x
      sxy += d.x * d.y
      syy += d.y * d.y
    }
    guard sxx + syy > 1e-18 else { return nil }
    let theta = 0.5 * atan2(2 * sxy, sxx - syy)
    var direction = FloorPoint(cos(theta), sin(theta))
    if direction.dot(last - first) < 0 { direction = direction * -1 }
    return FloorLine(point: centroid, direction: direction)
  }

  /// Where this line meets `other`, or nil when the two are (nearly) parallel.
  func intersection(_ other: FloorLine) -> FloorPoint? {
    let denominator = direction.cross(other.direction)
    guard abs(denominator) > FloorLine.parallelSine else { return nil }
    let s = (other.point - point).cross(other.direction) / denominator
    return point + direction * s
  }

  /// The foot of `point` on the line.
  func project(_ other: FloorPoint) -> FloorPoint {
    point + direction * (other - point).dot(direction)
  }
}

/// Metres rounded to a micrometre with no negative zero.
func micrometres(_ metres: Double) -> Double {
  let rounded = (metres * 1_000_000).rounded() / 1_000_000
  return rounded == 0 ? 0 : rounded
}

/// The text a length would have had if typed in the operator's units, in the shape FieldKit's
/// `LengthFormatter` and `LengthParser` use (FieldKit is not a dependency of this target): whole
/// millimetres for metric (`4012`), feet and inches to 0.1 in for imperial (`13' 1.5"`).
enum WalkthroughLengthText {
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
}
