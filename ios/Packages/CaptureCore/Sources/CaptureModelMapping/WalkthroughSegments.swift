/// The segments of a walk-through's arrangement: the floor outline, the interior walls clipped to
/// it, and short closures where a wall end stops short of the wall it should meet.
///
/// RoomPlan leaves parts of the outline without a wall and stops wall ends 0.15 to 3.6 m short of
/// their junction, so walls alone rarely close a room. Walls that run along the outline are left
/// out here (the outline already bounds the rooms); they are only split downstream.
struct WalkthroughSegments {
  /// Outline edges (fixed), then interior wall pieces, then gap closures.
  var segments: [PlanSegment] = []
  var outlineWalls: [Int] = []
  var interiorWalls: [Int] = []
  var dangling: [WalkthroughSplitter.DanglingEnd] = []
  var duplicatesMerged = 0
  var overshootsTrimmed = 0

  init(plan: WalkthroughInput.Plan, parameters p: WalkthroughSplitter.Parameters, eps: Double) {
    let outline = plan.outline
    let n = outline.count
    for i in 0..<n {
      segments.append(
        PlanSegment(a: outline[i], b: outline[(i + 1) % n], kind: .outline, fixed: true))
    }
    var pieces: [PlanSegment] = []
    for wall in plan.walls {
      if Self.runsAlongOutline(wall, outline: outline, tolerance: p.outlineTolerance) {
        outlineWalls.append(wall.index)
        continue
      }
      interiorWalls.append(wall.index)
      for piece in Self.clip(wall.a, wall.b, to: outline, eps: eps) {
        pieces.append(PlanSegment(a: piece.0, b: piece.1, kind: .wall, wall: wall.index))
      }
    }
    pieces = mergeDuplicates(pieces, p)
    pieces = trimOvershoots(pieces, outline: outline, p, eps: eps)
    segments += pieces
    Self.snapEnds(&segments, outline: outline, eps: eps)
    closeDanglingEnds(outline: outline, p, eps: eps)
    Self.snapEnds(&segments, outline: outline, eps: eps)
  }

  /// A wall is an outline wall when 4 of 5 samples along it lie within `tolerance` of a parallel
  /// (within 10 degrees) outline edge.
  static func runsAlongOutline(_ wall: WalkthroughInput.Wall, outline: [P2], tolerance: Double)
    -> Bool
  {
    let n = outline.count
    guard let d = Plan2D.unit(wall.b - wall.a) else { return false }
    var hits = 0
    for t in [0.1, 0.3, 0.5, 0.7, 0.9] {
      let s = wall.a + (wall.b - wall.a) * t
      for i in 0..<n {
        let a = outline[i]
        let b = outline[(i + 1) % n]
        guard let e = Plan2D.unit(b - a) else { continue }
        if Plan2D.segPoint(s, a, b).distance <= tolerance, abs(Plan2D.dot(d, e)) >= Plan2D.cos10 {
          hits += 1
          break
        }
      }
    }
    return hits >= 4
  }

  /// The parts of the segment from `a` to `b` inside the outline, longer than `eps`.
  static func clip(_ a: P2, _ b: P2, to outline: [P2], eps: Double) -> [(P2, P2)] {
    var ts = [0.0, 1.0]
    let n = outline.count
    for i in 0..<n {
      if let r = Plan2D.segSeg(a, b, outline[i], outline[(i + 1) % n]), 0 < r.t, r.t < 1,
        -1e-9 <= r.u, r.u <= 1 + 1e-9
      {
        ts.append(r.t)
      }
    }
    ts.sort()
    var out: [(P2, P2)] = []
    for k in ts.indices.dropFirst() {
      let t0 = ts[k - 1]
      let t1 = ts[k]
      if t1 - t0 < 1e-9 { continue }
      let p = a + (b - a) * t0
      let q = a + (b - a) * t1
      let m = a + (b - a) * ((t0 + t1) / 2)
      if Plan2D.contains(outline, m), Plan2D.polyDist(outline, m) > 1e-7, Plan2D.dist(p, q) > eps {
        out.append((p, q))
      }
    }
    return out
  }

  /// Near-duplicate pieces (parallel within 5 degrees, both ends of the shorter within
  /// `duplicateLateral` of the longer's line, overlapping by at least `duplicateOverlap` of the
  /// shorter): the shorter is dropped and the longer extended to cover both. Longest first.
  private mutating func mergeDuplicates(
    _ input: [PlanSegment], _ p: WalkthroughSplitter.Parameters
  ) -> [PlanSegment] {
    var pieces = input
    let order = pieces.indices.sorted {
      (-Plan2D.dist(pieces[$0].a, pieces[$0].b), $0) < (
        -Plan2D.dist(pieces[$1].a, pieces[$1].b), $1
      )
    }
    var dead = [Bool](repeating: false, count: pieces.count)
    for i in order where !dead[i] {
      for j in order where j != i && !dead[j] {
        let a = pieces[i].a
        let b = pieces[i].b
        let c = pieces[j].a
        let d = pieces[j].b
        let li = Plan2D.dist(a, b)
        let lj = Plan2D.dist(c, d)
        if lj > li || (lj == li && j < i) { continue }
        guard let u = Plan2D.unit(b - a), let v = Plan2D.unit(d - c) else { continue }
        if abs(Plan2D.cross(u, v)) > Plan2D.sin5 { continue }
        if abs(Plan2D.cross(u, c - a)) > p.duplicateLateral
          || abs(Plan2D.cross(u, d - a)) > p.duplicateLateral
        {
          continue
        }
        let sc = min(Plan2D.dot(c - a, u), Plan2D.dot(d - a, u))
        let sd = max(Plan2D.dot(c - a, u), Plan2D.dot(d - a, u))
        let overlap = min(li, sd) - max(0, sc)
        if overlap < p.duplicateOverlap * lj { continue }
        pieces[i].a = a + u * min(0, sc)
        pieces[i].b = a + u * max(li, sd)
        dead[j] = true
        duplicatesMerged += 1
      }
    }
    return pieces.indices.filter { !dead[$0] }.map { pieces[$0] }
  }

  /// A dangling end at most `overshoot` past the nearest crossing (at 30 degrees or more) of its
  /// piece is cut back to that crossing.
  private mutating func trimOvershoots(
    _ pieces: [PlanSegment], outline: [P2], _ p: WalkthroughSplitter.Parameters, eps: Double
  ) -> [PlanSegment] {
    let n = outline.count
    var base: [(P2, P2)] = (0..<n).map { (outline[$0], outline[($0 + 1) % n]) }
    base += pieces.map { ($0.a, $0.b) }
    var out: [PlanSegment] = []
    for (k, piece) in pieces.enumerated() {
      let a = piece.a
      let b = piece.b
      let length = Plan2D.dist(a, b)
      guard let u = Plan2D.unit(b - a) else { continue }
      var xs: [Double] = []
      for (j, segment) in base.enumerated() where j != n + k {
        if let r = Plan2D.segSeg(a, b, segment.0, segment.1), 0 < r.t, r.t < 1,
          -1e-9 <= r.u, r.u <= 1 + 1e-9, let e = Plan2D.unit(segment.1 - segment.0),
          abs(Plan2D.cross(u, e)) >= Plan2D.sin30
        {
          xs.append(r.t)
        }
      }
      var trimmed = piece
      for (isStart, tEnd) in [(true, 0.0), (false, 1.0)] {
        let end = isStart ? piece.a : piece.b
        let touching = base.enumerated().contains { j, segment in
          j != n + k && Plan2D.segPoint(end, segment.0, segment.1).distance <= eps
        }
        guard !touching, let first = xs.min(), let last = xs.max() else { continue }
        let t = isStart ? first : last
        let over = abs(t - tEnd) * length
        if eps < over, over <= p.overshoot {
          if isStart { trimmed.a = a + (b - a) * t } else { trimmed.b = a + (b - a) * t }
          overshootsTrimmed += 1
        }
      }
      if Plan2D.dist(trimmed.a, trimmed.b) > eps { out.append(trimmed) }
    }
    return out
  }

  /// Snaps each end of every segment that is not on the outline, in order: to the first outline
  /// vertex within `eps`, else to the nearest outline edge within `eps`, else to the nearest other
  /// segment within `eps` (inside its span).
  static func snapEnds(_ segments: inout [PlanSegment], outline: [P2], eps: Double) {
    let n = outline.count
    for k in segments.indices where segments[k].kind != .outline {
      for isStart in [true, false] {
        let p = isStart ? segments[k].a : segments[k].b
        var q: P2? = outline.first { Plan2D.dist(p, $0) < eps }
        if q == nil {
          var best: (distance: Double, point: P2)?
          for i in 0..<n {
            let a = outline[i]
            let b = outline[(i + 1) % n]
            let (d, t) = Plan2D.segPoint(p, a, b)
            if d < eps, best == nil || d < best!.distance { best = (d, a + (b - a) * t) }
          }
          q = best?.point
        }
        if q == nil {
          var best: (distance: Double, point: P2)?
          for (j, other) in segments.enumerated() where j != k && other.kind != .outline {
            let (d, t) = Plan2D.segPoint(p, other.a, other.b)
            if d < eps, 0 < t, t < 1, best == nil || d < best!.distance {
              best = (d, other.a + (other.b - other.a) * t)
            }
          }
          q = best?.point
        }
        if let q {
          if isStart { segments[k].a = q } else { segments[k].b = q }
        }
      }
    }
  }

  /// The nearest hit of the ray from `o` along `d` up to `maxLength`: a segment it crosses, or a
  /// segment end within `lateral` of the ray. Returns the distance along the ray.
  static func rayHit(
    _ o: P2, _ d: P2, _ segments: [(P2, P2)], maxLength: Double, lateral: Double, skip: Int? = nil
  ) -> Double? {
    var best: Double?
    let far = o + d * maxLength
    for (k, segment) in segments.enumerated() where k != skip {
      if let r = Plan2D.segSeg(o, far, segment.0, segment.1) {
        let s = r.t * maxLength
        if 1e-6 < s, s <= maxLength, -1e-9 <= r.u, r.u <= 1 + 1e-9, best == nil || s < best! {
          best = s
        }
      }
      for e in [segment.0, segment.1] {
        let v = e - o
        let s = Plan2D.dot(v, d)
        if 1e-6 < s, s <= maxLength, abs(Plan2D.cross(d, v)) <= lateral, best == nil || s < best! {
          best = s
        }
      }
    }
    return best
  }

  /// Closes each wall-piece end that touches nothing: to the nearest point of another segment
  /// within `join`; else along the wall to the first segment within `ext` (or to the crossing of
  /// two such rays, an L corner); else to the nearest vertex within `ext` and 20 degrees of the
  /// wall direction. Every decision looks only at the segments as they were before closing.
  private mutating func closeDanglingEnds(
    outline: [P2], _ p: WalkthroughSplitter.Parameters, eps: Double
  ) {
    let base = segments.map { ($0.a, $0.b) }
    struct End {
      var segment: Int
      var p: P2
      var d: P2
      var wall: Int?
    }
    var ends: [End] = []
    for (k, segment) in segments.enumerated() where segment.kind == .wall {
      for (end, other) in [(segment.a, segment.b), (segment.b, segment.a)] {
        let free = base.enumerated().allSatisfy { j, s in
          j == k || Plan2D.segPoint(end, s.0, s.1).distance > eps
        }
        if free, let d = Plan2D.unit(end - other) {
          ends.append(End(segment: k, p: end, d: d, wall: segment.wall))
        }
      }
    }
    let reach = p.extend
    let rays = ends.map { ($0.p, $0.p + $0.d * reach) }
    for (i, end) in ends.enumerated() {
      var near: (distance: Double, point: P2)?
      for (j, s) in base.enumerated() where j != end.segment {
        let (d, t) = Plan2D.segPoint(end.p, s.0, s.1)
        if d <= p.join, near == nil || d < near!.distance { near = (d, s.0 + (s.1 - s.0) * t) }
      }
      if let near {
        segments.append(PlanSegment(a: end.p, b: near.point, kind: .gap, wall: end.wall))
        dangling.append(.init(wall: end.wall ?? -1, method: .join, gapM: near.distance))
        continue
      }
      let hit = Self.rayHit(end.p, end.d, base, maxLength: reach, lateral: eps, skip: end.segment)
      let otherRays = rays.enumerated().filter { $0.offset != i }.map(\.element)
      let corner = Self.rayHit(end.p, end.d, otherRays, maxLength: reach, lateral: 0)
      if let hit, corner == nil || hit <= corner! + 1e-9 {
        segments.append(PlanSegment(a: end.p, b: end.p + end.d * hit, kind: .gap, wall: end.wall))
        dangling.append(.init(wall: end.wall ?? -1, method: .ray, gapM: hit))
      } else if let corner {
        segments.append(
          PlanSegment(a: end.p, b: end.p + end.d * corner, kind: .gap, wall: end.wall))
        dangling.append(.init(wall: end.wall ?? -1, method: .corner, gapM: corner))
      } else {
        var best: (distance: Double, point: P2)?
        var targets = outline
        for (j, s) in base.enumerated() where j != end.segment { targets += [s.0, s.1] }
        for v in targets {
          let w = v - end.p
          let length = Plan2D.norm(w)
          if 1e-6 < length, length <= reach, Plan2D.dot(w, end.d) >= length * Plan2D.cos20,
            best == nil || length < best!.distance
          {
            best = (length, v)
          }
        }
        if let best {
          segments.append(PlanSegment(a: end.p, b: best.point, kind: .gap, wall: end.wall))
          dangling.append(.init(wall: end.wall ?? -1, method: .cone, gapM: best.distance))
        } else {
          dangling.append(.init(wall: end.wall ?? -1, method: .unclosed, gapM: nil))
        }
      }
    }
  }
}
