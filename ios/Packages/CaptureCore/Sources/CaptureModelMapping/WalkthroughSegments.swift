/// The segments of a walk-through's arrangement: the floor outline, the interior walls clipped to
/// it, and short closures where a wall end stops short of the wall it should meet.
///
/// RoomPlan leaves parts of the outline without a wall and stops wall ends 0.15 to 3.6 m short of
/// their junction, so walls alone rarely close a room. Walls that run along the outline are left
/// out here (the outline already bounds the rooms); they are only split downstream.
///
/// Two points touch when they are less than `eps` apart, in every step here and in the welding of
/// `PlanArrangement`, so an end that touches something is never also left open.
struct WalkthroughSegments {
  /// Outline edges (fixed), then interior wall pieces (walls in `canonicalOrder`), then gap
  /// closures.
  var segments: [PlanSegment] = []
  /// Source wall indexes, ascending.
  var outlineWalls: [Int] = []
  var interiorWalls: [Int] = []
  /// By source wall.
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
    for wall in Self.canonicalOrder(plan.walls) {
      if Self.runsAlongOutline(wall, outline: outline, tolerance: p.outlineTolerance) {
        outlineWalls.append(wall.index)
        continue
      }
      interiorWalls.append(wall.index)
      for piece in Self.clip(wall.a, wall.b, to: outline, eps: eps) {
        pieces.append(PlanSegment(a: piece.0, b: piece.1, kind: .wall, wall: wall.index))
      }
    }
    outlineWalls.sort()
    interiorWalls.sort()
    pieces = mergeDuplicates(pieces, p)
    pieces = trimOvershoots(pieces, outline: outline, p, eps: eps)
    pieces = Self.weldEnds(pieces, outline: outline, eps: eps)
    segments += pieces
    Self.snapEnds(&segments, outline: outline, eps: eps)
    closeDanglingEnds(outline: outline, p, eps: eps)
    Self.snapEnds(&segments, outline: outline, eps: eps)
    // Diagnostics in document order; each wall's ends keep their order.
    let rank = dangling.indices.sorted { (dangling[$0].wall, $0) < (dangling[$1].wall, $1) }
    dangling = rank.map { dangling[$0] }
  }

  /// The walls longest first (lengths to a micrometre), ties by the midpoint, then the start, then
  /// the position in the document. RoomPlan's wall order means nothing, and snapping and welding
  /// keep the first of several ends that lie close together, so the order has to come from the
  /// walls themselves. Lengths do not change when the capture is turned or moved; only walls of the
  /// same length to a micrometre, which real scans rarely have, fall back to where they lie.
  static func canonicalOrder(_ walls: [WalkthroughInput.Wall]) -> [WalkthroughInput.Wall] {
    func key(_ wall: WalkthroughInput.Wall) -> [Int64] {
      let m = (wall.a + wall.b) * 0.5
      let length = Plan2D.dist(wall.a, wall.b)
      let rounded = [-length, m.x, m.y, wall.a.x, wall.a.y].map(WalkthroughCuts.micro)
      return rounded + [Int64(wall.index)]
    }
    let keys = walls.map(key)
    return walls.indices.sorted { keys[$0].lexicographicallyPrecedes(keys[$1]) }.map { walls[$0] }
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
  /// piece is cut back to that crossing. Only crossings more than `eps` from both ends count (a
  /// crossing at an end is where that end touches), a segment counts as crossed when the piece
  /// passes within `eps` of its span (a wall that stops just short of the piece makes a T as much
  /// as one that runs just past it), and no end is cut back to the middle of its piece or beyond.
  /// A piece that trimming would leave `eps` long or shorter is kept as it is, for the closing of
  /// dangling ends.
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
        let span = Plan2D.dist(segment.0, segment.1)
        if let r = Plan2D.segSeg(a, b, segment.0, segment.1), eps / length < r.t,
          r.t < 1 - eps / length, -eps / span <= r.u, r.u <= 1 + eps / span,
          let e = Plan2D.unit(segment.1 - segment.0), abs(Plan2D.cross(u, e)) >= Plan2D.sin30
        {
          xs.append(r.t)
        }
      }
      var trimmed = piece
      var trims = 0
      for (isStart, tEnd) in [(true, 0.0), (false, 1.0)] {
        let end = isStart ? piece.a : piece.b
        let touching = base.enumerated().contains { j, segment in
          j != n + k && Plan2D.segPoint(end, segment.0, segment.1).distance < eps
        }
        guard !touching, let first = xs.min(), let last = xs.max() else { continue }
        let t = isStart ? first : last
        let over = abs(t - tEnd) * length
        if eps < over, over <= p.overshoot, over < length / 2 {
          if isStart { trimmed.a = a + (b - a) * t } else { trimmed.b = a + (b - a) * t }
          trims += 1
        }
      }
      if Plan2D.dist(trimmed.a, trimmed.b) > eps {
        out.append(trimmed)
        overshootsTrimmed += trims
      } else {
        out.append(piece)
      }
    }
    return out
  }

  /// Wall-piece ends that meet move onto one point. Two ends meet when they are less than `eps`
  /// apart, or when one touches the other's piece less than `eps` from that end (a wall that stops
  /// beside another wall's end), directly or through other ends. Each group moves to its first end
  /// that touches the outline, else to its first end that touches a piece outside the group, else
  /// to its first end (pieces are in `canonicalOrder`, `a` before `b`); `snapEnds` then puts it
  /// on what it touches. Ends that do not meet are then `eps` or more apart, so whether ends meet
  /// never depends on which of several close ends the arrangement welds first, and an end that
  /// touches another end is never left open. A piece whose two ends meet is dropped.
  static func weldEnds(_ pieces: [PlanSegment], outline: [P2], eps: Double) -> [PlanSegment] {
    var ends: [P2] = []
    for piece in pieces { ends += [piece.a, piece.b] }
    // Union-find; each root is the lowest index of its group.
    var parent = Array(ends.indices)
    func root(_ i: Int) -> Int {
      var i = i
      while parent[i] != i { i = parent[i] }
      return i
    }
    func union(_ i: Int, _ j: Int) {
      let ri = root(i)
      let rj = root(j)
      if ri != rj { parent[max(ri, rj)] = min(ri, rj) }
    }
    for i in ends.indices {
      for j in (i + 1)..<ends.count where Plan2D.dist(ends[i], ends[j]) < eps { union(i, j) }
    }
    for i in ends.indices {
      for (k, piece) in pieces.enumerated() where k != i / 2 {
        let (distance, t) = Plan2D.segPoint(ends[i], piece.a, piece.b)
        guard distance < eps else { continue }
        let length = Plan2D.dist(piece.a, piece.b)
        let (along, end) = t <= 0.5 ? (t * length, 2 * k) : ((1 - t) * length, 2 * k + 1)
        if along < eps { union(i, end) }
      }
    }
    // The point of each group.
    let n = outline.count
    func touchesOutline(_ p: P2) -> Bool {
      (0..<n).contains { Plan2D.segPoint(p, outline[$0], outline[($0 + 1) % n]).distance < eps }
    }
    func touchesOtherPiece(_ i: Int) -> Bool {
      pieces.indices.contains { k in
        root(2 * k) != root(i) && root(2 * k + 1) != root(i)
          && Plan2D.segPoint(ends[i], pieces[k].a, pieces[k].b).distance < eps
      }
    }
    var groups = [[Int]](repeating: [], count: ends.count)
    for i in ends.indices { groups[root(i)].append(i) }
    var point = ends
    for (r, group) in groups.enumerated() where group.count > 1 {
      let i =
        group.first { touchesOutline(ends[$0]) } ?? group.first(where: touchesOtherPiece) ?? r
      point[r] = ends[i]
    }
    var out: [PlanSegment] = []
    for (k, piece) in pieces.enumerated() {
      let ra = root(2 * k)
      let rb = root(2 * k + 1)
      if ra == rb { continue }
      var welded = piece
      welded.a = point[ra]
      welded.b = point[rb]
      out.append(welded)
    }
    return out
  }

  /// Snaps each end of every segment that is not on the outline, in order: to the first outline
  /// vertex within `eps`, else to the nearest outline edge within `eps`, else to the nearest other
  /// segment within `eps` (inside its span, away from its ends by more than rounding). An end
  /// next to another segment's end is left to the welding of the arrangement (wall ends that close
  /// already coincide, `weldEnds`): a closure built to reach a wall ends on that wall's line, so
  /// the wall's own free end can project exactly onto the closure's tip, and rounding must not
  /// decide whether that end moves.
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
            if d < eps, 1e-9 < t, t < 1 - 1e-9, best == nil || d < best!.distance {
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
  /// segment end within `lateral` of the ray (no end when `lateral` is negative). Returns the
  /// distance along the ray.
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

  /// Closes each wall-piece end that touches nothing (no segment less than `eps` away): to the
  /// nearest point of another segment within `join` (or, when two such ends would each join the
  /// other's piece, to each other); else along the wall to the first segment within `ext` (or to
  /// the crossing of two such rays at 30 degrees or more, an L corner); else to the nearest vertex
  /// within `ext` and 20 degrees of the wall direction. Every decision looks only at the segments
  /// as they were before closing.
  ///
  /// Two rays that are nearly in line (the ends of a doorway in one wall) make no corner: where
  /// their lines cross would be decided by rounding, so the result would depend on how the capture
  /// is turned.
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
          j == k || Plan2D.segPoint(end, s.0, s.1).distance >= eps
        }
        if free, let d = Plan2D.unit(end - other) {
          ends.append(End(segment: k, p: end, d: d, wall: segment.wall))
        }
      }
    }
    let reach = p.extend
    let rays = ends.map { ($0.p, $0.p + $0.d * reach) }
    // The nearest point of another segment within `join`, per end.
    let nearest = ends.map { end -> (distance: Double, point: P2, segment: Int)? in
      var near: (distance: Double, point: P2, segment: Int)?
      for (j, s) in base.enumerated() where j != end.segment {
        let (d, t) = Plan2D.segPoint(end.p, s.0, s.1)
        if d <= p.join, near == nil || d < near!.distance {
          near = (d, s.0 + (s.1 - s.0) * t, j)
        }
      }
      return near
    }
    // Two ends within `join` of each other that would each join the other's piece (two pieces
    // in line that overlap a little, side by side) are linked end to end instead: two joins
    // would cross and close a loop of a few centimetres that hides both pieces from the cuts.
    var partner = [Int?](repeating: nil, count: ends.count)
    for i in ends.indices where partner[i] == nil {
      guard let near = nearest[i] else { continue }
      var best: (distance: Double, end: Int)?
      for k in ends.indices where k != i && partner[k] == nil && ends[k].segment == near.segment {
        let d = Plan2D.dist(ends[i].p, ends[k].p)
        if nearest[k]?.segment == ends[i].segment, d <= p.join, best == nil || d < best!.distance {
          best = (d, k)
        }
      }
      if let best {
        partner[i] = best.end
        partner[best.end] = i
      }
    }
    for (i, end) in ends.enumerated() {
      if let k = partner[i] {
        if i < k {
          segments.append(PlanSegment(a: end.p, b: ends[k].p, kind: .gap, wall: end.wall))
        }
        dangling.append(
          .init(wall: end.wall ?? -1, method: .join, gapM: Plan2D.dist(end.p, ends[k].p)))
        continue
      }
      if let near = nearest[i] {
        segments.append(PlanSegment(a: end.p, b: near.point, kind: .gap, wall: end.wall))
        dangling.append(.init(wall: end.wall ?? -1, method: .join, gapM: near.distance))
        continue
      }
      let hit = Self.rayHit(end.p, end.d, base, maxLength: reach, lateral: eps, skip: end.segment)
      let otherRays = ends.indices.filter {
        $0 != i && abs(Plan2D.cross(ends[$0].d, end.d)) >= Plan2D.sin30
      }.map { rays[$0] }
      let corner = Self.rayHit(end.p, end.d, otherRays, maxLength: reach, lateral: -1)
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
