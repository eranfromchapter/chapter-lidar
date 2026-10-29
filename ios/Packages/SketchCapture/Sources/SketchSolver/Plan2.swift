import CaptureContract
import CaptureModelMapping
import Foundation

/// A point or vector on the plan while solving, in millimetres. `x` is the model's x; `y` runs
/// "up the sheet" and becomes the model's −z. That choice makes the usual mathematics work
/// unchanged: a left turn is a +90° rotation, and a loop with positive shoelace area here is
/// counter-clockwise seen from +Y, the winding the capture model requires for room polygons.
struct Plan2: Hashable, Sendable {
  var x: Double
  var y: Double

  init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }

  static let zero = Plan2(0, 0)

  static func + (a: Plan2, b: Plan2) -> Plan2 { Plan2(a.x + b.x, a.y + b.y) }
  static func - (a: Plan2, b: Plan2) -> Plan2 { Plan2(a.x - b.x, a.y - b.y) }
  static func * (a: Plan2, s: Double) -> Plan2 { Plan2(a.x * s, a.y * s) }
  static prefix func - (a: Plan2) -> Plan2 { Plan2(-a.x, -a.y) }

  func dot(_ other: Plan2) -> Double { x * other.x + y * other.y }

  /// The z component of the cross product; positive when `other` is to the left of `self`.
  func cross(_ other: Plan2) -> Double { x * other.y - y * other.x }

  var length: Double { (x * x + y * y).squareRoot() }

  /// The vector scaled to length 1, or nil when it has no length.
  var normalized: Plan2? {
    let l = length
    return l > 1e-12 ? self * (1 / l) : nil
  }

  /// The unit normal to the right of the direction: for a room wound counter-clockwise, the side
  /// away from the room.
  var rightNormal: Plan2 { Plan2(y, -x) }

  func rotated(by angle: Double) -> Plan2 {
    let c = cos(angle)
    let s = sin(angle)
    return Plan2(x * c - y * s, x * s + y * c)
  }

  var angle: Double { atan2(y, x) }

  /// The contract point in metres at floor level, rounded to a micrometre so output is stable.
  var floorVec3: Vec3 {
    Vector3(x / 1000, 0, -y / 1000).contractVec3
  }

  /// The unit vector of a rectilinear heading: 0 is +x, 1 is +y, 2 is −x, 3 is −y.
  static func heading(_ quarterTurns: Int) -> Plan2 {
    switch ((quarterTurns % 4) + 4) % 4 {
    case 0: return Plan2(1, 0)
    case 1: return Plan2(0, 1)
    case 2: return Plan2(-1, 0)
    default: return Plan2(0, -1)
    }
  }

  /// Twice the signed area of the loop: positive when counter-clockwise.
  static func signedArea2(_ loop: [Plan2]) -> Double {
    guard loop.count >= 3 else { return 0 }
    var sum = 0.0
    for index in loop.indices {
      sum += loop[index].cross(loop[(index + 1) % loop.count])
    }
    return sum
  }

  /// Where the lines `p1 + s·d1` and `p2 + u·d2` meet, or nil when they are parallel.
  static func intersection(_ p1: Plan2, _ d1: Plan2, _ p2: Plan2, _ d2: Plan2) -> Plan2? {
    let denominator = d1.cross(d2)
    guard abs(denominator) > 1e-9 else { return nil }
    let s = (p2 - p1).cross(d2) / denominator
    return p1 + d1 * s
  }
}

/// Metres from millimetres, rounded to a micrometre with no negative zero.
func metres(_ millimetres: Double) -> Double {
  let rounded = (millimetres / 1000 * 1_000_000).rounded() / 1_000_000
  return rounded == 0 ? 0 : rounded
}
