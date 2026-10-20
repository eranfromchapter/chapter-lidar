import CaptureContract
import Foundation

/// Thick walls of the floor plan drawing, laid along the room outlines rather than per scanned
/// wall (scanned walls stop short of corners and leave gaps). Plan metres, sheet-aligned frame.
///
/// - Every outline edge that no other room shares is an exterior wall: a band of the exterior
///   thickness outside the room, so the room keeps its full measured floor. The edges are
///   traced into loops around the whole floor and the bands are mitred at every corner.
/// - An edge two rooms share is an interior wall where a scanned wall runs along it: a band of
///   the interior thickness centred on the edge. Where no wall runs along it the rooms are open
///   to each other and nothing is drawn.
/// - Scanned walls that lie on no room edge (a short return inside a room) are drawn centred.
/// - Doors, windows and open passages cut the bands they sit in.
///
/// Thickness is assumed (RoomPlan reports none): 4.5 in interior and 6 in exterior by default.
struct WallLayout {
  enum Kind: Sendable {
    case exterior
    case interior
    case stray
  }

  /// One straight band: the reference line from `a` to `b`, and the band between `lo` and `hi`
  /// along the line's left normal. Exterior bands run from `lo` = -thickness (outside) to
  /// `hi` = 0 (the room's edge); interior and stray bands are centred.
  struct Segment: Sendable {
    var kind: Kind
    var a: Point2
    var b: Point2
    var lo: Double
    var hi: Double
    /// Corners of the band at its two ends: mitred, extended into a joining wall, or square.
    var startLo: Point2
    var startHi: Point2
    var endLo: Point2
    var endHi: Point2
    /// Parameter ranges (0 at `a`, 1 at `b`) cut out for openings.
    var cuts: [(Double, Double)] = []

    var length: Double { a.distance(to: b) }
    var direction: Point2 { (b - a).unit }
    var normal: Point2 { direction.leftNormal }

    func point(_ t: Double, _ offset: Double) -> Point2 { a + (b - a) * t + normal * offset }
    func parameter(_ p: Point2) -> Double {
      length > 0 ? (p - a).dot(direction) / length : 0
    }

    init(kind: Kind, a: Point2, b: Point2, lo: Double, hi: Double) {
      self.kind = kind
      self.a = a
      self.b = b
      self.lo = lo
      self.hi = hi
      let n = (b - a).unit.leftNormal
      startLo = a + n * lo
      startHi = a + n * hi
      endLo = b + n * lo
      endHi = b + n * hi
    }

    /// Lengthens the start (or end) by `distance` along the line, keeping square corners.
    mutating func extend(start: Bool, by distance: Double) {
      guard distance > 0 else { return }
      let d = direction * distance
      if start {
        startLo = startLo - d
        startHi = startHi - d
      } else {
        endLo = endLo + d
        endHi = endHi + d
      }
    }

    /// The band less its cuts, as counter-clockwise quadrilaterals.
    var pieces: [[Point2]] { cutPieces.map(\.corners) }

    /// The band less its cuts, with whether each piece ends at a cut (frames an opening).
    var cutPieces: [(corners: [Point2], atCut: Bool)] {
      var spans: [(Double, Double)] = []
      var from = 0.0
      for cut in cuts.sorted(by: { $0.0 < $1.0 }) {
        if cut.0 > from { spans.append((from, cut.0)) }
        from = max(from, cut.1)
      }
      if from < 1 { spans.append((from, 1)) }
      let minimum = length > 0 ? 0.003 / length : 1
      var out: [(corners: [Point2], atCut: Bool)] = []
      for (t0, t1) in spans where t1 - t0 > minimum {
        let s = t0 <= 0 ? (startLo, startHi) : (point(t0, lo), point(t0, hi))
        let e = t1 >= 1 ? (endLo, endHi) : (point(t1, lo), point(t1, hi))
        // A cut that reaches into a mitred corner leaves nothing on that side of it.
        guard parameter(s.0) < parameter(e.0) - minimum / 2,
          parameter(s.1) < parameter(e.1) - minimum / 2
        else { continue }
        out.append(([s.0, e.0, e.1, s.1], t0 > 0 || t1 < 1))
      }
      return out
    }

    /// The whole band, ignoring cuts.
    var band: [Point2] { [startLo, endLo, endHi, startHi] }
  }

  /// Where an opening sits: its span on a band's reference line, and the band faces.
  struct Gap: Sendable {
    var opening: PlanOpening
    /// The band it cuts, nil when it lies on no band.
    var segment: Int?
    var a: Point2
    var b: Point2
    var lo: Double
    var hi: Double
    /// Unit normal of the reference line; `lo` and `hi` are offsets along it.
    var normal: Point2
    /// Distance from `a` and from `b` to the nearer end of their band (where a hinge goes).
    var distanceToStart: Double
    var distanceToEnd: Double
  }

  /// A loop of exterior walls around (part of) the floor.
  struct Loop: Sendable {
    /// Room-side corners, counter-clockwise around the floor (clockwise around a courtyard).
    var inner: [Point2]
    /// Outside faces at the same corners (mitre points).
    var outer: [Point2]
    /// Index into `segments` of the band from corner i to corner i + 1.
    var segments: [Int]
    var closed: Bool
  }

  var segments: [Segment] = []
  var loops: [Loop] = []
  var gaps: [Gap] = []
  let exteriorThickness: Double
  let interiorThickness: Double

  /// Exterior band pieces, interior and stray, all counter-clockwise: filled together with the
  /// nonzero rule they paint as their union. A scrap of wall shorter than one and a half times
  /// its thickness is left out unless it meets another wall, or frames an opening and is at
  /// least as long as the wall is thick (a shorter one would be a loose square).
  var pieces: [[Point2]] {
    var out: [[Point2]] = []
    for (index, segment) in segments.enumerated() {
      let thickness = segment.hi - segment.lo
      for piece in segment.cutPieces {
        let c = piece.corners
        let start = (c[0] + c[3]) * 0.5
        let end = (c[1] + c[2]) * 0.5
        let along = start.distance(to: end)
        if along >= 1.5 * thickness {
          out.append(c)
          continue
        }
        let meets = [start, end].contains { p in
          segments.indices.contains { other in
            other != index
              && (PlanGeometry.contains(segments[other].band, p)
                || PlanGeometry.distanceToBoundary(of: segments[other].band, from: p) < 0.02)
          }
        }
        if meets || (piece.atCut && along >= thickness - 1e-6) { out.append(c) }
      }
    }
    return out
  }

  /// Floor area within the outside faces of the exterior walls (closed loops only).
  var grossAreaM2: Double {
    loops.filter(\.closed).map { Geo.signedArea($0.outer) }.reduce(0, +)
  }

  // MARK: Building

  /// Tolerances, metres.
  static let vertexOnEdge = 0.02
  static let probe = 0.03
  static let wallOnEdge = 0.10
  static let wallNearEdge = 0.30
  static let parallelSine = sin(8 * Double.pi / 180)
  /// Scanned walls stop short of corners and junctions (by up to half a metre in real
  /// exports, a little more once the plan is squared): gaps up to `coverageBridge` along an
  /// edge are closed, and a wall ending within `coverageSnap` of the edge's end is carried on
  /// to it. A doorway is wider than that.
  static let coverageBridge = 0.25
  static let coverageSnap = 0.65
  static let strayMinimum = 0.25
  static let chainJoin = 0.02

  init(
    rooms: [[Point2]], walls: [PlanWall], openings: [PlanOpening], exterior: Double,
    interior: Double
  ) {
    exteriorThickness = exterior
    interiorThickness = interior

    // 1. Room edges, split where another room's corner touches them, each either exterior
    //    (no room beyond it) or shared with the room beyond it.
    struct Piece {
      var room: Int
      var a: Point2
      var b: Point2
      var other: Int?
    }
    var pieces: [Piece] = []
    for (r, polygon) in rooms.enumerated() {
      for i in polygon.indices {
        let p = polygon[i]
        let q = polygon[(i + 1) % polygon.count]
        let length = p.distance(to: q)
        guard length > 0.005 else { continue }
        var ts = [0.0, 1.0]
        for (s, other) in rooms.enumerated() where s != r {
          for v in other {
            let (distance, t) = Geo.segmentDistance(v, p, q)
            if distance < WallLayout.vertexOnEdge, t * length > 0.01, (1 - t) * length > 0.01 {
              ts.append(t)
            }
          }
        }
        ts.sort()
        var unique: [Double] = []
        for t in ts where unique.last.map({ (t - $0) * length > 0.01 }) ?? true { unique.append(t) }
        if unique.last != 1 { unique[unique.count - 1] = 1 }
        for k in unique.indices.dropFirst() {
          let a = p + (q - p) * unique[k - 1]
          let b = p + (q - p) * unique[k]
          let middle = (a + b) * 0.5
          let outside = middle + (b - a).unit.rightNormal * WallLayout.probe
          let other = rooms.indices.first { $0 != r && PlanGeometry.contains(rooms[$0], outside) }
          pieces.append(Piece(room: r, a: a, b: b, other: other))
        }
      }
    }

    // 2. Exterior loops, traced edge to edge with the floor on the left.
    let exteriorPieces = pieces.filter { $0.other == nil }
    var used = Array(repeating: false, count: exteriorPieces.count)
    var chains: [(points: [Point2], closed: Bool)] = []
    for start in exteriorPieces.indices where !used[start] {
      used[start] = true
      var chain = [exteriorPieces[start].a]
      var current = exteriorPieces[start]
      var closed = false
      while true {
        if current.b.distance(to: exteriorPieces[start].a) <= WallLayout.chainJoin,
          chain.count > 1
        {
          closed = true
          break
        }
        // Of the edges leaving this corner, the one turning furthest right.
        let incoming = (current.b - current.a).unit
        var best: (index: Int, turn: Double)?
        for (index, piece) in exteriorPieces.enumerated()
        where !used[index] && piece.a.distance(to: current.b) <= WallLayout.chainJoin {
          let outgoing = (piece.b - piece.a).unit
          let turn = atan2(incoming.cross(outgoing), incoming.dot(outgoing))
          if best == nil || turn < best!.turn - 1e-9 { best = (index, turn) }
        }
        guard let next = best else { break }
        used[next.index] = true
        chain.append(exteriorPieces[next.index].a)
        current = exteriorPieces[next.index]
      }
      if !closed { chain.append(current.b) }
      chains.append((chain, closed))
    }

    for chain in chains {
      var corners = chain.points
      if chain.closed {
        corners = Geo.clean(corners, merge: 0.005, straightDegrees: 1, deviation: 0.01)
        guard corners.count >= 3 else { continue }
      } else {
        corners = WallLayout.straighten(corners)
        guard corners.count >= 2 else { continue }
      }
      let count = corners.count
      let runs = chain.closed ? count : count - 1
      var loop = Loop(inner: corners, outer: [], segments: [], closed: chain.closed)
      var runSegments: [Segment] = []
      for i in 0..<runs {
        runSegments.append(
          Segment(
            kind: .exterior, a: corners[i], b: corners[(i + 1) % count], lo: -exterior, hi: 0))
      }
      // Mitre the outside faces where runs meet; inside faces meet at the corner itself.
      var outer: [Point2] = []
      for i in 0..<count {
        let incoming = i > 0 ? i - 1 : (chain.closed ? runs - 1 : nil)
        let outgoing = i < runs ? i : nil
        var point: Point2
        if let incoming, let outgoing {
          let s0 = runSegments[incoming]
          let s1 = runSegments[outgoing]
          let fallback = corners[i] + s1.normal * -exterior
          if let mitre = Geo.lineIntersection(
            s0.a + s0.normal * -exterior, s0.direction, s1.a + s1.normal * -exterior,
            s1.direction), mitre.distance(to: corners[i]) <= exterior * 4
          {
            point = mitre
          } else {
            point = fallback
          }
          runSegments[incoming].endLo = point
          runSegments[incoming].endHi = corners[i]
          runSegments[outgoing].startLo = point
          runSegments[outgoing].startHi = corners[i]
        } else if let outgoing {
          // Open end: square, lengthened by the wall thickness to cover the corner.
          runSegments[outgoing].extend(start: true, by: exterior)
          point = runSegments[outgoing].startLo
        } else {
          let last = runs - 1
          runSegments[last].extend(start: false, by: exterior)
          point = runSegments[last].endLo
        }
        outer.append(point)
      }
      loop.outer = outer
      for segment in runSegments {
        loop.segments.append(segments.count)
        segments.append(segment)
      }
      loops.append(loop)
    }
    let exteriorCount = segments.count

    // 3. Interior walls: shared edges where a scanned wall runs along them.
    var shared: [(Point2, Point2)] = []
    for piece in pieces where piece.other != nil {
      let duplicate = shared.contains { kept in
        (kept.0.distance(to: piece.a) < 0.02 && kept.1.distance(to: piece.b) < 0.02)
          || (kept.0.distance(to: piece.b) < 0.02 && kept.1.distance(to: piece.a) < 0.02)
      }
      if !duplicate { shared.append((piece.a, piece.b)) }
    }
    for (a, b) in shared {
      let covered = WallLayout.coverage(
        of: a, b, by: walls.map { ($0.start, $0.end) }, distance: WallLayout.wallOnEdge,
        bridge: WallLayout.coverageBridge, snap: WallLayout.coverageSnap)
      for (t0, t1) in covered {
        segments.append(
          Segment(
            kind: .interior, a: a + (b - a) * t0, b: a + (b - a) * t1, lo: -interior / 2,
            hi: interior / 2))
      }
    }

    // 4. Scanned walls (or parts) on no room edge.
    let edges = pieces.map { ($0.a, $0.b) }
    for wall in walls where wall.length > WallLayout.strayMinimum {
      let covered = WallLayout.coverage(
        of: wall.start, wall.end, by: edges, distance: WallLayout.wallNearEdge, bridge: 0.05,
        snap: 0.05)
      var from = 0.0
      var spans: [(Double, Double)] = []
      for (t0, t1) in covered {
        if t0 > from { spans.append((from, t0)) }
        from = max(from, t1)
      }
      if from < 1 { spans.append((from, 1)) }
      for (t0, t1) in spans where (t1 - t0) * wall.length >= WallLayout.strayMinimum {
        let a = wall.start + (wall.end - wall.start) * t0
        let b = wall.start + (wall.end - wall.start) * t1
        segments.append(Segment(kind: .stray, a: a, b: b, lo: -interior / 2, hi: interior / 2))
      }
    }

    // 5. Ends of interior and stray walls: into the exterior wall they meet, or half a
    //    thickness into the interior wall they meet; free ends stay square.
    for index in exteriorCount..<segments.count {
      for start in [true, false] {
        let segment = segments[index]
        let end = start ? segment.a : segment.b
        let outward = start ? segment.direction * -1 : segment.direction
        var reach = 0.0
        for (other, candidate) in segments.enumerated() where other != index {
          let (distance, _) = Geo.segmentDistance(end, candidate.a, candidate.b)
          if candidate.kind == .exterior {
            if distance <= 0.03, outward.dot(candidate.normal) < 0.2 {
              reach = max(reach, exterior)
            }
          } else if distance <= interior / 2 + 0.03 {
            reach = max(reach, interior / 2)
          }
        }
        segments[index].extend(start: start, by: reach)
      }
    }

    // 6. Openings cut the band they lie in.
    for opening in openings {
      gaps.append(cut(for: opening))
    }

    // 7. Next to an opening at a corner the walls meet square, not mitred: the wall that goes
    //    on is carried square through the corner and the jamb is square.
    let near = 1.5 * exterior
    for loop in loops {
      let count = loop.segments.count
      for position in 0..<count where loop.closed || position + 1 < count {
        let i = loop.segments[position]
        let j = loop.segments[(position + 1) % count]
        let li = segments[i].length
        let lj = segments[j].length
        guard li > 0, lj > 0 else { continue }
        let openEnd = segments[i].cuts.contains { (1 - $0.1) * li <= near }
        let openStart = segments[j].cuts.contains { $0.0 * lj <= near }
        guard openEnd != openStart else { continue }
        if openStart {
          // i carries on through the corner; j starts square.
          var s = segments[i]
          let reach = (s.endLo - s.b).dot(s.direction)
          s.endLo = s.b + s.normal * s.lo + s.direction * reach
          s.endHi = s.b + s.normal * s.hi + s.direction * reach
          segments[i] = s
          segments[j].startLo = segments[j].a + segments[j].normal * segments[j].lo
          segments[j].startHi = segments[j].a + segments[j].normal * segments[j].hi
        } else {
          var s = segments[j]
          let reach = (s.startLo - s.a).dot(s.direction)
          s.startLo = s.a + s.normal * s.lo + s.direction * reach
          s.startHi = s.a + s.normal * s.hi + s.direction * reach
          segments[j] = s
          segments[i].endLo = segments[i].b + segments[i].normal * segments[i].lo
          segments[i].endHi = segments[i].b + segments[i].normal * segments[i].hi
        }
      }
    }
  }

  /// Places `opening` on the nearest band along it and cuts that band (and any band continuing
  /// it in line) for the opening's width.
  private mutating func cut(for opening: PlanOpening) -> Gap {
    let direction = (opening.to - opening.from).unit
    let middle = (opening.from + opening.to) * 0.5
    var best: (index: Int, score: Double)?
    for (index, segment) in segments.enumerated() where segment.length > 0 {
      guard abs(direction.cross(segment.direction)) < sin(10 * Double.pi / 180) else { continue }
      let offset = (middle - segment.a).dot(segment.normal)
      guard offset >= segment.lo - 0.15, offset <= segment.hi + 0.15 else { continue }
      let p0 = segment.parameter(opening.from)
      let p1 = segment.parameter(opening.to)
      guard min(max(p0, p1), 1) - max(min(p0, p1), 0) > 0 else { continue }
      // Prefer the room-outline walls to a stray wall nearby.
      let score =
        abs(offset - (segment.lo + segment.hi) / 2) + (segment.kind == .stray ? 0.5 : 0)
      if best == nil || score < best!.score - 1e-9 { best = (index, score) }
    }
    guard let chosen = best?.index else {
      let half = max(opening.wallThickness, interiorThickness) / 2
      return Gap(
        opening: opening, segment: nil, a: opening.from, b: opening.to, lo: -half, hi: half,
        normal: direction.leftNormal, distanceToStart: 0, distanceToEnd: 0)
    }
    let host = segments[chosen]
    // The opening's span on the host, kept within the faces of the walls that meet the host
    // there: an opening scanned a little wider than the space between them would otherwise
    // bite a notch out of each and leave stepped jambs.
    let p0 = host.parameter(opening.from)
    let p1 = host.parameter(opening.to)
    var low = min(p0, p1) * host.length
    var high = max(p0, p1) * host.length
    let width = high - low
    for (index, other) in segments.enumerated() where index != chosen && other.length > 0 {
      guard abs(other.direction.cross(host.direction)) > 0.5,
        let (u0, u1) = WallLayout.span(of: other.band, across: host)
      else { continue }
      if u0 <= low + 1e-6, u1 > low, u1 < high {
        low = u1
      } else if u1 >= high - 1e-6, u0 < high, u0 > low {
        high = u0
      }
    }
    if high - low < 0.5 * width {
      low = min(p0, p1) * host.length
      high = max(p0, p1) * host.length
    }
    let from = host.a + host.direction * low
    let to = host.a + host.direction * high
    for (index, segment) in segments.enumerated() {
      let inLine =
        index == chosen
        || (segment.kind == host.kind && abs(segment.direction.cross(host.direction)) < 0.02
          && abs((segment.a - host.a).dot(host.normal)) < 0.02)
      guard inLine, segment.length > 0 else { continue }
      let q0 = segment.parameter(from)
      let q1 = segment.parameter(to)
      let t0 = max(0, min(q0, q1))
      let t1 = min(1, max(q0, q1))
      if t1 > t0 { segments[index].cuts.append((t0, t1)) }
    }
    let s0 = low / host.length
    let s1 = high / host.length
    let a = host.point(s0, 0)
    let b = host.point(s1, 0)
    return Gap(
      opening: opening, segment: chosen, a: a, b: b, lo: host.lo, hi: host.hi,
      normal: host.normal, distanceToStart: max(0, s0) * host.length,
      distanceToEnd: max(0, 1 - s1) * host.length)
  }

  /// Where `polygon` (a convex band) lies within `host`'s band, as a range of distances along
  /// the host from its start; nil when they share no area. The polygon is clipped to the strip
  /// between the host's two faces (Sutherland-Hodgman), so a mitred corner counts only as far
  /// as it reaches into the host.
  static func span(of polygon: [Point2], across host: Segment) -> (Double, Double)? {
    var points = polygon
    for (bound, sign) in [(host.lo, 1.0), (host.hi, -1.0)] {
      // Keep the side where sign * (offset - bound) >= 0.
      let value = { (p: Point2) in sign * ((p - host.a).dot(host.normal) - bound) }
      var out: [Point2] = []
      for index in points.indices {
        let p = points[index]
        let q = points[(index + 1) % points.count]
        let vp = value(p)
        let vq = value(q)
        if vp >= 0 { out.append(p) }
        if (vp >= 0) != (vq >= 0) { out.append(p + (q - p) * (vp / (vp - vq))) }
      }
      points = out
      if points.count < 3 { return nil }
    }
    guard abs(Geo.signedArea(points)) > 1e-6 else { return nil }
    let along = points.map { ($0 - host.a).dot(host.direction) }
    return (along.min()!, along.max()!)
  }

  /// Parameter ranges of segment ab that lie along any of `lines` (parallel and within
  /// `distance`), merged across gaps up to `bridge` and carried to the ends when within `snap`.
  static func coverage(
    of a: Point2, _ b: Point2, by lines: [(Point2, Point2)], distance: Double, bridge: Double,
    snap: Double
  ) -> [(Double, Double)] {
    let length = a.distance(to: b)
    guard length > 0 else { return [] }
    let d = (b - a).unit
    var ranges: [(Double, Double)] = []
    for (p, q) in lines {
      let e = q - p
      guard e.length > 1e-6, abs(e.unit.cross(d)) < parallelSine else { continue }
      guard abs((p - a).cross(d)) <= distance, abs((q - a).cross(d)) <= distance else {
        continue
      }
      let s0 = (p - a).dot(d) / length
      let s1 = (q - a).dot(d) / length
      let t0 = max(0, min(s0, s1))
      let t1 = min(1, max(s0, s1))
      if t1 > t0 { ranges.append((t0, t1)) }
    }
    ranges.sort { $0.0 < $1.0 }
    var merged: [(Double, Double)] = []
    for range in ranges {
      if let last = merged.last, (range.0 - last.1) * length <= bridge {
        merged[merged.count - 1].1 = max(last.1, range.1)
      } else {
        merged.append(range)
      }
    }
    if let first = merged.first, first.0 * length <= snap { merged[0].0 = 0 }
    if let last = merged.last, (1 - last.1) * length <= snap { merged[merged.count - 1].1 = 1 }
    return merged
  }

  /// An open chain without the corners where it runs straight on.
  static func straighten(_ points: [Point2]) -> [Point2] {
    var out: [Point2] = []
    for p in points where out.last.map({ $0.distance(to: p) > 0.005 }) ?? true { out.append(p) }
    var index = 1
    while index + 1 < out.count {
      let a = out[index] - out[index - 1]
      let b = out[index + 1] - out[index]
      if abs(a.unit.cross(b.unit)) < sin(Double.pi / 180), a.dot(b) > 0 {
        out.remove(at: index)
      } else {
        index += 1
      }
    }
    return out
  }
}
