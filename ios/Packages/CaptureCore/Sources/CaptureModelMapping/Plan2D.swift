// Plan geometry for splitting a walk-through scan into rooms (floorplan plan, phase 3).
//
// The plan is the RoomPlan x/z plane used as a math (x, y) plane: `P2.x` is the RoomPlan x and
// `P2.y` the RoomPlan z. Rings are counter-clockwise in this plane (positive `Plan2D.area`); the
// mapper turns them into the contract winding at the end.
//
// Every formula is plain Double arithmetic in a fixed order, with `squareRoot()` and no trig at
// run time, so results are the same on Linux and on Apple platforms. Angles are constants
// (`Plan2D.cos10` and so on) and directions are ordered with an exact comparator.

/// A point or a direction in the plan.
struct P2: Hashable, Sendable {
  var x: Double
  var y: Double

  init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }

  static func + (a: P2, b: P2) -> P2 { P2(a.x + b.x, a.y + b.y) }
  static func - (a: P2, b: P2) -> P2 { P2(a.x - b.x, a.y - b.y) }
  static func * (a: P2, s: Double) -> P2 { P2(a.x * s, a.y * s) }

  /// The plan point of a 3D point: x and z.
  init(_ point: Vector3) {
    self.init(point.x, point.z)
  }
}

enum Plan2D {
  static let cos10 = 0.984807753012208
  static let cos20 = 0.9396926207859084
  static let sin1 = 0.01745240643728351
  static let sin5 = 0.08715574274765817
  static let sin10 = 0.17364817766693033
  static let sin30 = 0.5

  static func dot(_ a: P2, _ b: P2) -> Double { a.x * b.x + a.y * b.y }
  static func cross(_ a: P2, _ b: P2) -> Double { a.x * b.y - a.y * b.x }
  static func norm(_ a: P2) -> Double { (a.x * a.x + a.y * a.y).squareRoot() }
  static func dist(_ a: P2, _ b: P2) -> Double { norm(a - b) }

  /// `a` scaled to length 1, or nil when it has no length.
  static func unit(_ a: P2) -> P2? {
    let n = norm(a)
    return n > 1e-12 ? P2(a.x / n, a.y / n) : nil
  }

  /// The point at parameter `t` of the segment from `a` to `b`.
  static func lerp(_ a: P2, _ b: P2, _ t: Double) -> P2 { a + (b - a) * t }

  /// Signed shoelace area; positive for a counter-clockwise ring.
  static func area(_ poly: [P2]) -> Double {
    var sum = 0.0
    let n = poly.count
    for i in 0..<n {
      let a = poly[i]
      let b = poly[(i + 1) % n]
      sum += a.x * b.y - b.x * a.y
    }
    return sum / 2
  }

  static func perimeter(_ poly: [P2]) -> Double {
    var sum = 0.0
    for i in poly.indices {
      sum += dist(poly[i], poly[(i + 1) % poly.count])
    }
    return sum
  }

  /// Even-odd rule, the same test as `PolygonMath.contains` (x with x, z with y).
  static func contains(_ poly: [P2], _ p: P2) -> Bool {
    var inside = false
    let n = poly.count
    guard n > 0 else { return false }
    var j = n - 1
    for i in 0..<n {
      let a = poly[i]
      let b = poly[j]
      if (a.y > p.y) != (b.y > p.y) {
        let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
        if p.x < x { inside.toggle() }
      }
      j = i
    }
    return inside
  }

  /// Distance from `p` to the segment from `a` to `b`, and the parameter of the nearest point,
  /// clamped to [0, 1].
  static func segPoint(_ p: P2, _ a: P2, _ b: P2) -> (distance: Double, t: Double) {
    let d = b - a
    let l2 = dot(d, d)
    if l2 < 1e-18 { return (dist(p, a), 0) }
    let t = max(0, min(1, dot(p - a, d) / l2))
    return (dist(p, a + d * t), t)
  }

  /// Distance from `p` to the ring `poly`.
  static func polyDist(_ poly: [P2], _ p: P2) -> Double {
    var best = Double.infinity
    for i in poly.indices {
      best = min(best, segPoint(p, poly[i], poly[(i + 1) % poly.count]).distance)
    }
    return best
  }

  /// Line parameters of the crossing of p-q and a-b (`t` on p-q, `u` on a-b); nil when they are
  /// parallel.
  static func segSeg(_ p: P2, _ q: P2, _ a: P2, _ b: P2) -> (t: Double, u: Double)? {
    let r = q - p
    let s = b - a
    let den = cross(r, s)
    if abs(den) < 1e-12 * max(1, norm(r) * norm(s)) { return nil }
    let w = a - p
    return (cross(w, s) / den, cross(w, r) / den)
  }

  /// No edge shorter than 1e-9 and no two edges that are not neighbours touching.
  static func isSimple(_ poly: [P2]) -> Bool {
    let n = poly.count
    guard n >= 3 else { return false }
    for i in 0..<n {
      let a = poly[i]
      let b = poly[(i + 1) % n]
      if dist(a, b) < 1e-9 { return false }
      for j in (i + 1)..<n where !((j + 1) % n == i || (i + 1) % n == j) {
        if let r = segSeg(a, b, poly[j], poly[(j + 1) % n]),
          -1e-9 <= r.t, r.t <= 1 + 1e-9, -1e-9 <= r.u, r.u <= 1 + 1e-9
        {
          return false
        }
      }
    }
    return true
  }

  /// The smallest rectangle aligned with one of the polygon's edges: its long and short side.
  static func minRect(_ poly: [P2]) -> (long: Double, short: Double) {
    var best: (area: Double, long: Double, short: Double)?
    let n = poly.count
    for i in 0..<n {
      guard let d = unit(poly[(i + 1) % n] - poly[i]) else { continue }
      let normal = P2(-d.y, d.x)
      var minU = Double.infinity
      var maxU = -Double.infinity
      var minV = Double.infinity
      var maxV = -Double.infinity
      for p in poly {
        let u = dot(p, d)
        let v = dot(p, normal)
        minU = min(minU, u)
        maxU = max(maxU, u)
        minV = min(minV, v)
        maxV = max(maxV, v)
      }
      let w = maxU - minU
      let h = maxV - minV
      if best == nil || w * h < best!.area - 1e-12 {
        best = (w * h, max(w, h), min(w, h))
      }
    }
    return best.map { ($0.long, $0.short) } ?? (0, 0)
  }

  /// Sutherland-Hodgman: `subject` clipped by the convex counter-clockwise polygon `clip`.
  static func clipConvex(_ subject: [P2], _ clip: [P2]) -> [P2] {
    var output = subject
    let n = clip.count
    for i in 0..<n {
      let a = clip[i]
      let b = clip[(i + 1) % n]
      let input = output
      output = []
      if input.isEmpty { break }
      for j in input.indices {
        let p = input[j == 0 ? input.count - 1 : j - 1]
        let q = input[j]
        let pIn = cross(b - a, p - a) >= 0
        let qIn = cross(b - a, q - a) >= 0
        if qIn {
          if !pIn, let r = segSeg(p, q, a, b) { output.append(p + (q - p) * r.t) }
          output.append(q)
        } else if pIn, let r = segSeg(p, q, a, b) {
          output.append(p + (q - p) * r.t)
        }
      }
    }
    return output
  }

  /// Length of the segment from `a` to `b` inside the convex counter-clockwise polygon `quad`
  /// (Cyrus-Beck).
  static func clipLenConvex(_ a: P2, _ b: P2, _ quad: [P2]) -> Double {
    var t0 = 0.0
    var t1 = 1.0
    let d = b - a
    let n = quad.count
    for i in 0..<n {
      let p = quad[i]
      let q = quad[(i + 1) % n]
      let e = q - p
      let num = cross(e, a - p)
      let den = cross(e, d)
      if abs(den) < 1e-15 {
        if num < 0 { return 0 }
        continue
      }
      let t = -num / den
      if den > 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
      if t0 > t1 { return 0 }
    }
    return max(0, t1 - t0) * norm(d)
  }

  /// 0 for directions from +x (included) to -x (excluded) counter-clockwise, 1 for the rest.
  static func half(_ d: P2) -> Int {
    (d.y > 0 || (d.y == 0 && d.x > 0)) ? 0 : 1
  }

  /// Counter-clockwise order of directions starting at +x, exact (no atan2): -1 when `a` comes
  /// first, 1 when `b` does, 0 for the same direction.
  static func angleOrder(_ a: P2, _ b: P2) -> Int {
    let ha = half(a)
    let hb = half(b)
    if ha != hb { return ha < hb ? -1 : 1 }
    let c = cross(a, b)
    return c > 0 ? -1 : (c < 0 ? 1 : 0)
  }

  /// Node ids around `centre` in counter-clockwise order, ties by id.
  static func sortedAround(_ ids: [Int], centre: P2, points: [P2]) -> [Int] {
    ids.sorted { x, y in
      let order = angleOrder(points[x] - centre, points[y] - centre)
      return order != 0 ? order < 0 : x < y
    }
  }

  /// Principal square root of a + ib, with square roots only.
  static func csqrt(_ a: Double, _ b: Double) -> (re: Double, im: Double) {
    let r = (a * a + b * b).squareRoot()
    let re = ((r + a) / 2).squareRoot()
    let im = ((r - a) / 2).squareRoot()
    return (re, b >= 0 ? im : -im)
  }

  /// A point well inside `poly`: the middle of the widest span on one of up to 12 horizontal
  /// lines between vertex heights, nearest the mean height first.
  static func interiorPoint(_ poly: [P2]) -> P2 {
    guard let first = poly.first else { return P2(0, 0) }
    var ys: [Double] = []
    for y in poly.map(\.y).sorted() where ys.last != y { ys.append(y) }
    var sumY = 0.0
    for p in poly { sumY += p.y }
    let cy = sumY / Double(poly.count)
    var lines: [Double] = []
    if ys.count >= 2 {
      for i in 0..<(ys.count - 1) { lines.append((ys[i] + ys[i + 1]) / 2) }
    }
    lines.sort { (abs($0 - cy), $0) < (abs($1 - cy), $1) }
    var best: (width: Double, point: P2)?
    let n = poly.count
    for y in lines.prefix(12) {
      var xs: [Double] = []
      for i in 0..<n {
        let a = poly[i]
        let b = poly[(i + 1) % n]
        if (a.y > y) != (b.y > y) {
          xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
        }
      }
      xs.sort()
      var k = 0
      while k + 1 < xs.count {
        let w = xs[k + 1] - xs[k]
        if best == nil || w > best!.width { best = (w, P2((xs[k] + xs[k + 1]) / 2, y)) }
        k += 2
      }
    }
    return best?.point ?? first
  }
}

/// The two dominant wall directions of a scan, at right angles: `u` and `v = perp(u)`.
struct PlanAxes: Sendable, Equatable {
  var u: P2
  var v: P2

  /// The length-weighted mean wall direction modulo 90 degrees, without trig: the fourth root of
  /// the sum of L * (cos + i sin)^4.
  init(walls: [(a: P2, b: P2)]) {
    var sx = 0.0
    var sy = 0.0
    for wall in walls {
      let d = wall.b - wall.a
      let length = Plan2D.norm(d)
      if length < 1e-9 { continue }
      let c = d.x / length
      let s = d.y / length
      let c2 = c * c - s * s
      let s2 = 2 * c * s
      sx += length * (c2 * c2 - s2 * s2)
      sy += length * (2 * c2 * s2)
    }
    var u = P2(1, 0)
    if abs(sx) + abs(sy) >= 1e-12 {
      let m = (sx * sx + sy * sy).squareRoot()
      let first = Plan2D.csqrt(sx / m, sy / m)
      let second = Plan2D.csqrt(first.re, first.im)
      u = Plan2D.unit(P2(second.re, second.im)) ?? P2(1, 0)
    }
    self.u = u
    self.v = P2(-u.y, u.x)
  }

  /// Sine of the angle between the unit direction `d` and the nearer axis.
  func deviation(_ d: P2) -> Double {
    min(abs(Plan2D.cross(d, u)), abs(Plan2D.cross(d, v)))
  }

  /// `d` replaced by the nearest axis direction pointing the same way, when within 10 degrees.
  func snap(_ d: P2) -> P2 {
    var best: (sine: Double, axis: P2)?
    for axis in [u, v] {
      for sign in [1.0, -1.0] {
        let a = P2(axis.x * sign, axis.y * sign)
        let sine = abs(Plan2D.cross(d, a))
        if Plan2D.dot(a, d) > 0, sine <= Plan2D.sin10, best == nil || sine < best!.sine {
          best = (sine, a)
        }
      }
    }
    return best?.axis ?? d
  }
}
