import Foundation

// Plane geometry for the floor plan drawing: polygons, segments, oriented boxes and the
// separating-axis overlap test used by label placement. Plan metres unless stated.

extension Point2 {
  func cross(_ other: Point2) -> Double { x * other.y - y * other.x }

  /// Turned counter-clockwise by `radians` about the origin.
  func rotated(by radians: Double) -> Point2 {
    let c = cos(radians)
    let s = sin(radians)
    return Point2(x: x * c - y * s, y: x * s + y * c)
  }

  /// Right-hand normal (90 degrees clockwise).
  var rightNormal: Point2 { Point2(x: y, y: -x) }
}

enum Geo {
  /// Shoelace area, positive for a counter-clockwise loop.
  static func signedArea(_ polygon: [Point2]) -> Double {
    var sum = 0.0
    for index in polygon.indices {
      sum += polygon[index].cross(polygon[(index + 1) % polygon.count])
    }
    return sum / 2
  }

  static func counterClockwise(_ polygon: [Point2]) -> [Point2] {
    signedArea(polygon) < 0 ? polygon.reversed() : polygon
  }

  /// Drops repeated points (closer than `merge`) and points where the outline runs straight on
  /// (turn below `straightDegrees` and off the line by less than `deviation`).
  static func clean(
    _ polygon: [Point2], merge: Double = 0.002, straightDegrees: Double = 0.6,
    deviation: Double = 0.01
  ) -> [Point2] {
    var points: [Point2] = []
    for p in polygon where points.last.map({ $0.distance(to: p) > merge }) ?? true {
      points.append(p)
    }
    while points.count > 3, let first = points.first, let last = points.last,
      first.distance(to: last) <= merge
    {
      points.removeLast()
    }
    var changed = true
    let limit = sin(straightDegrees * .pi / 180)
    while changed && points.count > 3 {
      changed = false
      for index in points.indices {
        let previous = points[(index + points.count - 1) % points.count]
        let current = points[index]
        let next = points[(index + 1) % points.count]
        let a = current - previous
        let b = next - current
        guard a.length > 0, b.length > 0 else { continue }
        let sine = abs(a.unit.cross(b.unit))
        let off = segmentDistance(current, previous, next).distance
        if sine < limit && a.dot(b) > 0 && off < deviation {
          points.remove(at: index)
          changed = true
          break
        }
      }
    }
    return points
  }

  /// Distance from `p` to segment ab and the parameter of the nearest point (0 at a, 1 at b).
  static func segmentDistance(_ p: Point2, _ a: Point2, _ b: Point2) -> (
    distance: Double, t: Double
  ) {
    let ab = b - a
    let lengthSquared = ab.dot(ab)
    guard lengthSquared > 0 else { return (p.distance(to: a), 0) }
    let t = max(0, min(1, (p - a).dot(ab) / lengthSquared))
    return (p.distance(to: a + ab * t), t)
  }

  /// Intersection of the lines p + s d and q + t e, nil when they are (nearly) parallel.
  static func lineIntersection(_ p: Point2, _ d: Point2, _ q: Point2, _ e: Point2) -> Point2? {
    let denominator = d.cross(e)
    guard abs(denominator) > 1e-9 else { return nil }
    let s = (q - p).cross(e) / denominator
    return p + d * s
  }

  /// True when segments ab and cd cross or touch.
  static func segmentsIntersect(_ a: Point2, _ b: Point2, _ c: Point2, _ d: Point2) -> Bool {
    func orient(_ p: Point2, _ q: Point2, _ r: Point2) -> Double { (q - p).cross(r - p) }
    let d1 = orient(c, d, a)
    let d2 = orient(c, d, b)
    let d3 = orient(a, b, c)
    let d4 = orient(a, b, d)
    if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
      return true
    }
    func on(_ p: Point2, _ q: Point2, _ r: Point2) -> Bool {
      abs(orient(p, q, r)) < 1e-12 && min(p.x, q.x) - 1e-12 <= r.x && r.x <= max(p.x, q.x) + 1e-12
        && min(p.y, q.y) - 1e-12 <= r.y && r.y <= max(p.y, q.y) + 1e-12
    }
    return on(c, d, a) || on(c, d, b) || on(a, b, c) || on(a, b, d)
  }

  /// Distance from `p` to the outline, positive inside and negative outside.
  static func signedDistance(_ polygon: [Point2], _ p: Point2) -> Double {
    let d = PlanGeometry.distanceToBoundary(of: polygon, from: p)
    return PlanGeometry.contains(polygon, p) ? d : -d
  }

  /// True when the closed outlines overlap by more than touching: an edge crosses another, or
  /// one lies inside the other.
  static func polygonsOverlap(_ a: [Point2], _ b: [Point2]) -> Bool {
    for i in a.indices {
      let a0 = a[i]
      let a1 = a[(i + 1) % a.count]
      for j in b.indices where segmentsIntersect(a0, a1, b[j], b[(j + 1) % b.count]) {
        return true
      }
    }
    if let p = a.first, PlanGeometry.contains(b, p) { return true }
    if let p = b.first, PlanGeometry.contains(a, p) { return true }
    return false
  }

  /// Separating-axis test for two convex outlines. They overlap only when they share more than
  /// `margin` along every axis, so outlines that merely touch do not.
  static func convexOverlap(_ a: [Point2], _ b: [Point2], margin: Double = 0) -> Bool {
    for polygon in [a, b] {
      for i in polygon.indices {
        let edge = polygon[(i + 1) % polygon.count] - polygon[i]
        guard edge.length > 1e-12 else { continue }
        let axis = edge.unit.leftNormal
        let pa = a.map { $0.dot(axis) }
        let pb = b.map { $0.dot(axis) }
        let overlap = min(pa.max()!, pb.max()!) - max(pa.min()!, pb.min()!)
        if overlap <= margin { return false }
      }
    }
    return true
  }
}

/// Axis-aligned extent of some points, for a quick no-overlap test before the exact one.
struct Extent: Sendable {
  var minX: Double
  var minY: Double
  var maxX: Double
  var maxY: Double

  init(_ points: [Point2]) {
    minX = points.map(\.x).min() ?? 0
    minY = points.map(\.y).min() ?? 0
    maxX = points.map(\.x).max() ?? 0
    maxY = points.map(\.y).max() ?? 0
  }

  func overlaps(_ other: Extent) -> Bool {
    minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
  }
}

/// A rectangle turned by an angle: centre, unit axis `u` (its width direction) and half sizes.
struct OrientedBox: Sendable {
  var center: Point2
  var u: Point2
  var halfWidth: Double
  var halfHeight: Double

  var v: Point2 { u.leftNormal }

  var corners: [Point2] {
    [
      center - u * halfWidth - v * halfHeight, center + u * halfWidth - v * halfHeight,
      center + u * halfWidth + v * halfHeight, center - u * halfWidth + v * halfHeight,
    ]
  }

  /// A thin box around segment ab, `halfWidth` either side of it.
  static func around(_ a: Point2, _ b: Point2, halfWidth: Double) -> OrientedBox {
    OrientedBox(
      center: (a + b) * 0.5, u: (b - a).unit, halfWidth: a.distance(to: b) / 2,
      halfHeight: halfWidth)
  }

  var extent: Extent { Extent(corners) }

  func overlaps(_ other: OrientedBox, margin: Double = 0) -> Bool {
    Geo.convexOverlap(corners, other.corners, margin: margin)
  }

  func overlaps(convex polygon: [Point2], margin: Double = 0) -> Bool {
    Geo.convexOverlap(corners, polygon, margin: margin)
  }

  /// True when every corner is inside `polygon` and no edge of the polygon crosses the box.
  func isInside(_ polygon: [Point2]) -> Bool {
    let box = corners
    guard box.allSatisfy({ PlanGeometry.contains(polygon, $0) }) else { return false }
    for i in polygon.indices where contains(polygon[i]) { return false }
    for i in box.indices {
      for j in polygon.indices
      where Geo.segmentsIntersect(
        box[i], box[(i + 1) % 4], polygon[j], polygon[(j + 1) % polygon.count])
      {
        return false
      }
    }
    return true
  }

  /// True when the box and `polygon` share no area.
  func isOutside(_ polygon: [Point2]) -> Bool {
    !Geo.polygonsOverlap(corners, polygon)
  }

  func contains(_ p: Point2) -> Bool {
    let d = p - center
    return abs(d.dot(u)) < halfWidth && abs(d.dot(v)) < halfHeight
  }
}
