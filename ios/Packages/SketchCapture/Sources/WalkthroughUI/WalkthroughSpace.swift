import CaptureContract
import Foundation

// The walkthrough screen's own 3D maths (spec F15 2): where the centre ray meets the vertical
// plane of a wall defined by its two floor corners, which wall that is, and where two wall
// lines meet on the floor. Points are in the walkthrough's AR frame: metres, +Y up.

/// A point or vector in the AR frame (a small value type, so nothing clashes with operators
/// other modules may define on `Vec3`).
struct WPoint: Equatable, Sendable {
  var x: Double
  var y: Double
  var z: Double

  init(_ x: Double, _ y: Double, _ z: Double) {
    self.x = x
    self.y = y
    self.z = z
  }

  init(_ v: Vec3) {
    self.init(v.x, v.y, v.z)
  }

  var vec3: Vec3 { Vec3(x: x, y: y, z: z) }

  static func + (a: WPoint, b: WPoint) -> WPoint { WPoint(a.x + b.x, a.y + b.y, a.z + b.z) }
  static func - (a: WPoint, b: WPoint) -> WPoint { WPoint(a.x - b.x, a.y - b.y, a.z - b.z) }
  static func * (a: WPoint, s: Double) -> WPoint { WPoint(a.x * s, a.y * s, a.z * s) }

  func dot(_ o: WPoint) -> Double { x * o.x + y * o.y + z * o.z }
  var length: Double { dot(self).squareRoot() }
  /// Length of the horizontal part (x, z).
  var horizontalLength: Double { (x * x + z * z).squareRoot() }
}

/// One wall as the screen knows it while walking: its two floor corners.
struct WalkthroughWallSegment: Equatable, Sendable {
  /// Wall `index` runs from corner `index` to corner `index + 1`.
  var index: Int
  var start: WPoint
  var end: WPoint

  var length: Double { (end - start).horizontalLength }
}

/// Where the centre ray met a wall.
struct WalkthroughWallHit: Equatable, Sendable {
  var wallIndex: Int
  var point: WPoint
  /// Distance along the ray, metres.
  var distance: Double
}

enum WalkthroughSpace {
  /// How far past its corners a wall still counts as hit (taps at a corner jamb).
  static let wallEndMargin = 0.10

  /// The vertical plane of `wall` hit by the ray from `origin` along `direction`: nil when the
  /// ray runs parallel to it, points away from it, or meets it outside the wall's length (with
  /// `wallEndMargin`) or below the floor of its corners.
  static func hit(
    _ wall: WalkthroughWallSegment, origin: WPoint, direction: WPoint
  ) -> WalkthroughWallHit? {
    let along = WPoint(wall.end.x - wall.start.x, 0, wall.end.z - wall.start.z)
    let length = along.horizontalLength
    guard length > 1e-6 else { return nil }
    let unit = along * (1 / length)
    // Horizontal normal of the wall's vertical plane.
    let normal = WPoint(-unit.z, 0, unit.x)
    let denominator = direction.dot(normal)
    guard abs(denominator) > 1e-9 else { return nil }
    let t = (wall.start - origin).dot(normal) / denominator
    guard t > 0.05 else { return nil }
    let point = origin + direction * t
    let s = (point - wall.start).dot(unit)
    guard s >= -wallEndMargin, s <= length + wallEndMargin else { return nil }
    let floor = min(wall.start.y, wall.end.y)
    guard point.y >= floor - 0.05 else { return nil }
    return WalkthroughWallHit(wallIndex: wall.index, point: point, distance: t)
  }

  /// The wall the ray meets first inside its extent (spec F15 2), or nil.
  static func firstHit(
    _ walls: [WalkthroughWallSegment], origin: WPoint, direction: WPoint
  ) -> WalkthroughWallHit? {
    walls.compactMap { hit($0, origin: origin, direction: direction) }
      .min { $0.distance < $1.distance }
  }

  /// The wall nearest to a floor point (a door's jambs), by horizontal distance to the segment.
  static func nearestWall(to point: WPoint, in walls: [WalkthroughWallSegment]) -> Int? {
    walls.min { distance(point, $0) < distance(point, $1) }?.index
  }

  static func distance(_ point: WPoint, _ wall: WalkthroughWallSegment) -> Double {
    let along = WPoint(wall.end.x - wall.start.x, 0, wall.end.z - wall.start.z)
    let lengthSquared = along.dot(along)
    let offset = WPoint(point.x - wall.start.x, 0, point.z - wall.start.z)
    guard lengthSquared > 1e-12 else { return offset.horizontalLength }
    let s = max(0, min(1, offset.dot(along) / lengthSquared))
    let foot = along * s
    return (offset - foot).horizontalLength
  }

  /// Where the floor lines of two walls meet (each through two taps), at the height `y`; nil
  /// when they are (nearly) parallel.
  static func intersect(
    _ a0: WPoint, _ a1: WPoint, _ b0: WPoint, _ b1: WPoint, y: Double
  ) -> WPoint? {
    let ax = a1.x - a0.x
    let az = a1.z - a0.z
    let bx = b1.x - b0.x
    let bz = b1.z - b0.z
    let cross = ax * bz - az * bx
    let lengths = (ax * ax + az * az).squareRoot() * (bx * bx + bz * bz).squareRoot()
    guard lengths > 1e-9, abs(cross) / lengths > 0.05 else { return nil }
    let dx = b0.x - a0.x
    let dz = b0.z - a0.z
    let t = (dx * bz - dz * bx) / cross
    return WPoint(a0.x + ax * t, y, a0.z + az * t)
  }

  /// The camera-to-world transform of a camera at `eye` looking along `direction` (+Y up), 16
  /// numbers column-major: the replay's frames.
  static func lookTransform(eye: WPoint, direction: WPoint) -> [Double] {
    let length = direction.length
    let forward = length > 1e-9 ? direction * (1 / length) : WPoint(0, 0, -1)
    // The camera looks along −Z: z axis = −forward.
    let zAxis = forward * -1
    // Right = forward × up.
    var xAxis = WPoint(-forward.z, 0, forward.x)
    let xLength = xAxis.length
    xAxis = xLength > 1e-9 ? xAxis * (1 / xLength) : WPoint(1, 0, 0)
    let yAxis = WPoint(
      zAxis.y * xAxis.z - zAxis.z * xAxis.y, zAxis.z * xAxis.x - zAxis.x * xAxis.z,
      zAxis.x * xAxis.y - zAxis.y * xAxis.x)
    return [
      xAxis.x, xAxis.y, xAxis.z, 0, yAxis.x, yAxis.y, yAxis.z, 0, zAxis.x, zAxis.y, zAxis.z, 0,
      eye.x, eye.y, eye.z, 1,
    ]
  }
}
