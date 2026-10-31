import CaptureContract
import Foundation

/// A point or vector on the plan while reading a sketch. `x` is the drawing's x and `y` is the
/// drawing's −y ("up the sheet"), so that, as in the solver's plan maths, a left turn is a +90°
/// rotation and a loop with a positive shoelace area is counter-clockwise seen from +Y. Drawing
/// units or millimetres, depending on where it is used.
struct PlanPoint: Hashable, Sendable {
  var x: Double
  var y: Double

  init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }

  /// A drawing point seen on the plan.
  init(_ point: SketchInterpretation.Point) {
    self.init(point.x, -point.y)
  }

  static func + (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(a.x + b.x, a.y + b.y) }
  static func - (a: PlanPoint, b: PlanPoint) -> PlanPoint { PlanPoint(a.x - b.x, a.y - b.y) }
  static func * (a: PlanPoint, s: Double) -> PlanPoint { PlanPoint(a.x * s, a.y * s) }

  func dot(_ other: PlanPoint) -> Double { x * other.x + y * other.y }

  /// The z component of the cross product; positive when `other` is to the left of `self`.
  func cross(_ other: PlanPoint) -> Double { x * other.y - y * other.x }

  var length: Double { (x * x + y * y).squareRoot() }

  /// Angle from +x, counter-clockwise seen from +Y, in degrees.
  var degrees: Double { atan2(y, x) * 180 / Double.pi }

  /// The signed turn from `self` to `next` in degrees, left positive, in (−180, 180].
  func turn(to next: PlanPoint) -> Double {
    atan2(cross(next), dot(next)) * 180 / Double.pi
  }

  /// Twice the signed area of the loop: positive when counter-clockwise seen from +Y.
  static func signedArea2(_ loop: [PlanPoint]) -> Double {
    guard loop.count >= 3 else { return 0 }
    var sum = 0.0
    for index in loop.indices {
      sum += loop[index].cross(loop[(index + 1) % loop.count])
    }
    return sum
  }
}

/// Where a position along one of the drawing's walls lands on the document's wall: the
/// fraction `f` along drawn wall `i` (0 at corner `i`) is `offset + f * span` along `wall`.
struct WallSpan: Hashable, Sendable {
  var wall: Int
  var offset: Double
  var span: Double

  func map(_ fraction: Double) -> Double { offset + fraction * span }

  /// The same position counted from the other end of the wall, on wall `wall` of the rewound
  /// outline.
  func reversed(wallCount: Int) -> WallSpan {
    WallSpan(wall: wallCount - 1 - wall, offset: 1 - offset, span: -span)
  }
}

/// One room's outline as the document needs it: repeated corners dropped, straight-through
/// corners merged (one wall drawn in two strokes), and wound counter-clockwise seen from +Y with
/// corner 0 kept, together with how the drawing's wall numbers map onto the document's.
struct RoomOutline: Sendable {
  /// The corners in drawing coordinates, in document order.
  var corners: [SketchInterpretation.Point]
  /// For each drawn wall (by the drawing's index), where it lies in the document; nil for a
  /// wall with no length (a repeated corner).
  var wallMap: [WallSpan?]
  /// For each document wall, the drawn wall it is exactly (nil when it was merged from several).
  var drawnWall: [Int?]
  /// True when the drawing went clockwise and the corners were renumbered.
  var rewound: Bool
  /// Corners dropped because they repeated the previous one or lay on a straight wall.
  var removedCorners: Int

  /// Two corners closer than this (drawing units) are the same corner.
  static let sameCornerUnits = 0.5

  /// Builds the outline, or nil when fewer than three corners remain.
  static func make(_ points: [SketchInterpretation.Point], straightToleranceDegrees: Double)
    -> RoomOutline?
  {
    let n = points.count
    guard n >= 3 else { return nil }
    let plan = points.map(PlanPoint.init)
    var keep = Array(0..<n)

    // Drop repeated corners (the first corner repeated at the end among them), then corners on
    // a straight line; one at a time, since each removal changes its neighbours' turns.
    var removing = true
    while removing {
      removing = false
      guard keep.count >= 3 else { return nil }
      let m = keep.count
      for j in 0..<m {
        let next = (j + 1) % m
        if (plan[keep[next]] - plan[keep[j]]).length < sameCornerUnits {
          keep.remove(at: next == 0 ? j : next)
          removing = true
          break
        }
      }
      if removing { continue }
      for j in 0..<m {
        let before = plan[keep[(j + m - 1) % m]]
        let corner = plan[keep[j]]
        let after = plan[keep[(j + 1) % m]]
        if abs((corner - before).turn(to: after - corner)) <= straightToleranceDegrees {
          keep.remove(at: j)
          removing = true
          break
        }
      }
    }
    guard keep.count >= 3 else { return nil }

    let m = keep.count
    var wallMap = [WallSpan?](repeating: nil, count: n)
    var drawnWall = [Int?](repeating: nil, count: m)
    for j in 0..<m {
      let first = keep[j]
      let last = keep[(j + 1) % m]
      var run: [Int] = []
      var index = first
      repeat {
        run.append(index)
        index = (index + 1) % n
      } while index != last
      let lengths = run.map { (plan[($0 + 1) % n] - plan[$0]).length }
      let total = lengths.reduce(0, +)
      guard total > 0 else { continue }
      var travelled = 0.0
      var real: [Int] = []
      for (position, wall) in run.enumerated() {
        let length = lengths[position]
        if length >= sameCornerUnits {
          wallMap[wall] = WallSpan(wall: j, offset: travelled / total, span: length / total)
          real.append(wall)
        }
        travelled += length
      }
      drawnWall[j] = real.count == 1 ? real[0] : nil
    }

    var corners = keep.map { points[$0] }
    var rewound = false
    if PlanPoint.signedArea2(keep.map { plan[$0] }) < 0 {
      corners = [corners[0]] + corners.dropFirst().reversed()
      wallMap = wallMap.map { $0?.reversed(wallCount: m) }
      drawnWall = Array(drawnWall.reversed())
      rewound = true
    }
    return RoomOutline(
      corners: corners, wallMap: wallMap, drawnWall: drawnWall, rewound: rewound,
      removedCorners: n - m)
  }
}
