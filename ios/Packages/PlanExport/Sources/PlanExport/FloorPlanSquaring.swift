import Foundation

/// Squaring a plan that is already turned to the sheet: walls a few degrees off the sheet axes
/// are put onto them, and small steps between wall faces that continue each other are taken
/// out, so the drawing is orthogonal the way a drafted plan is. Plan metres.
///
/// The room outlines are snapped together, as one network: corners shared by rooms (or lying
/// on another room's edge) stay shared, so neighbouring rooms keep meeting along one line.
/// - An edge within `tolerance` of an axis is put on it: its two corners get one x (vertical)
///   or one y (horizontal). The common value is the length-weighted mean, so long walls stay
///   where they were measured and short ones move to them.
/// - A short edge (under `shortEdge`) at any angle becomes a step along its main direction.
/// - Two parallel faces that continue each other end to end, less than `jog` apart, become one
///   line (a scanned wall face that steps by a few inches where two rooms meet).
/// Walls, openings and objects follow the room edge nearest to them. When squaring would
/// change a room's area by more than a little, or break an outline, the plan is left as it is.
struct PlanSquaring {
  var tolerance = 5.5 * Double.pi / 180
  var shortEdge = 0.4
  var jog = 0.16
  /// Corners closer than this are one corner.
  var weld = 0.02

  /// Union-find over indices.
  private struct Groups {
    var parent: [Int]
    init(_ count: Int) { parent = Array(0..<count) }
    mutating func find(_ i: Int) -> Int {
      var root = i
      while parent[root] != root { root = parent[root] }
      var node = i
      while parent[node] != root {
        let next = parent[node]
        parent[node] = root
        node = next
      }
      return root
    }
    mutating func union(_ a: Int, _ b: Int) {
      let ra = find(a)
      let rb = find(b)
      if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
    }
  }

  func squared(_ geometry: PlanGeometry) -> PlanGeometry {
    // 1. Corners, welded across rooms.
    var nodes: [Point2] = []
    var counts: [Int] = []
    var outlines: [[Int]] = []
    for room in geometry.rooms {
      var outline: [Int] = []
      for p in room.polygon {
        var index = nodes.firstIndex { $0.distance(to: p) <= weld }
        if let found = index {
          let n = Double(counts[found])
          nodes[found] = (nodes[found] * n + p) * (1 / (n + 1))
          counts[found] += 1
        } else {
          nodes.append(p)
          counts.append(1)
          index = nodes.count - 1
        }
        if outline.last != index { outline.append(index!) }
      }
      while outline.count > 1, outline.first == outline.last { outline.removeLast() }
      outlines.append(outline)
    }
    guard !nodes.isEmpty else { return geometry }

    // 2. Edges along an axis (or short ones) tie their corners' x or y together.
    struct Edge {
      var a: Int
      var b: Int
    }
    var edges: [Edge] = []
    for outline in outlines where outline.count >= 2 {
      for i in outline.indices {
        let a = outline[i]
        let b = outline[(i + 1) % outline.count]
        if a != b { edges.append(Edge(a: a, b: b)) }
      }
    }
    var xs = Groups(nodes.count)
    var ys = Groups(nodes.count)
    var weightX = Array(repeating: 0.0, count: nodes.count)
    var weightY = Array(repeating: 0.0, count: nodes.count)
    let sine = sin(tolerance)
    // 0 horizontal, 1 vertical, nil neither.
    var axes: [Int?] = []
    for edge in edges {
      let d = nodes[edge.b] - nodes[edge.a]
      let length = d.length
      var axis: Int?
      var weight = length
      if abs(d.y) <= length * sine {
        axis = 0
      } else if abs(d.x) <= length * sine {
        axis = 1
      } else if length < shortEdge {
        axis = abs(d.x) >= abs(d.y) ? 0 : 1
        weight = 0.001
      }
      axes.append(axis)
      if axis == 0 {
        ys.union(edge.a, edge.b)
        weightY[edge.a] += weight
        weightY[edge.b] += weight
      } else if axis == 1 {
        xs.union(edge.a, edge.b)
        weightX[edge.a] += weight
        weightX[edge.b] += weight
      }
    }
    // A corner on another room's edge stays on it.
    for (index, edge) in edges.enumerated() {
      guard let axis = axes[index] else { continue }
      let a = nodes[edge.a]
      let b = nodes[edge.b]
      for v in nodes.indices where v != edge.a && v != edge.b {
        let (distance, t) = Geo.segmentDistance(nodes[v], a, b)
        guard distance <= weld, t > 0, t < 1 else { continue }
        if axis == 0 { ys.union(v, edge.a) } else { xs.union(v, edge.a) }
      }
    }

    // 3. One value per line: the weighted mean of its corners.
    func values(_ groups: inout Groups, _ weights: [Double], _ coordinate: (Point2) -> Double)
      -> [Double]
    {
      var sum: [Int: Double] = [:]
      var total: [Int: Double] = [:]
      var plain: [Int: Double] = [:]
      var count: [Int: Double] = [:]
      var roots: [Int] = []
      for v in nodes.indices {
        let root = groups.find(v)
        roots.append(root)
        sum[root, default: 0] += coordinate(nodes[v]) * weights[v]
        total[root, default: 0] += weights[v]
        plain[root, default: 0] += coordinate(nodes[v])
        count[root, default: 0] += 1
      }
      return roots.map { root in
        let w = total[root]!
        return w > 1e-9 ? sum[root]! / w : plain[root]! / count[root]!
      }
    }

    // 4. Lines less than `jog` apart that continue each other end to end become one.
    func mergeSteps(_ groups: inout Groups, _ weights: [Double], value: [Double], other: [Double]) {
      var spans: [Int: (lo: Double, hi: Double, weight: Double, value: Double)] = [:]
      for v in nodes.indices {
        let root = groups.find(v)
        var span = spans[root] ?? (other[v], other[v], 0, value[v])
        span.lo = min(span.lo, other[v])
        span.hi = max(span.hi, other[v])
        span.weight += weights[v]
        spans[root] = span
      }
      // Only lines that carry an edge take part.
      let roots = spans.keys.filter { spans[$0]!.weight > 0.01 && spans[$0]!.hi > spans[$0]!.lo }
        .sorted()
      for (i, r) in roots.enumerated() {
        for s in roots[(i + 1)...] {
          let a = spans[r]!
          let b = spans[s]!
          guard abs(a.value - b.value) < jog else { continue }
          let overlap = min(a.hi, b.hi) - max(a.lo, b.lo)
          if overlap >= -weld && overlap <= weld { groups.union(r, s) }
        }
      }
    }
    let firstX = values(&xs, weightX) { $0.x }
    let firstY = values(&ys, weightY) { $0.y }
    mergeSteps(&xs, weightX, value: firstX, other: firstY)
    mergeSteps(&ys, weightY, value: firstY, other: firstX)
    let finalX = values(&xs, weightX) { $0.x }
    let finalY = values(&ys, weightY) { $0.y }
    let moved = nodes.indices.map { Point2(x: finalX[$0], y: finalY[$0]) }

    // 5. New outlines; give up when one breaks or changes much.
    var squared = geometry
    for (r, outline) in outlines.enumerated() {
      let polygon = PlanSquaring.tidy(outline.map { moved[$0] })
      let before = PlanGeometry.area(of: geometry.rooms[r].polygon)
      let after = PlanGeometry.area(of: polygon)
      guard polygon.count >= 3, abs(after - before) <= max(0.08 * before, 0.3),
        !PlanSquaring.selfIntersects(polygon)
      else { return geometry }
      squared.rooms[r].polygon = polygon
      squared.rooms[r].labelPoint = PlanGeometry.labelPoint(of: polygon)
    }

    // 6. Walls, openings and objects follow the nearest room edge. A wall or opening along a
    //    room edge moves with that edge as a whole (and goes when the edge does); any other is
    //    moved by its ends and then squared like an edge.
    func map(_ p: Point2, along chosen: Edge? = nil) -> Point2 {
      var best: (distance: Double, edge: Edge)?
      if let chosen {
        best = (0, chosen)
      } else {
        for edge in edges {
          let d = Geo.segmentDistance(p, nodes[edge.a], nodes[edge.b]).distance
          if best == nil || d < best!.distance - 1e-12 { best = (d, edge) }
        }
      }
      guard let edge = best?.edge else { return p }
      let a = nodes[edge.a]
      let b = nodes[edge.b]
      let a2 = moved[edge.a]
      let b2 = moved[edge.b]
      let length = a.distance(to: b)
      let newLength = a2.distance(to: b2)
      guard length > 1e-9, newLength > 1e-9 else { return p + (a2 - a) }
      let d = (b - a).unit
      let t = max(0, min(1, (p - a).dot(d) / length))
      let along = (p - a).dot(d) - t * length
      let offset = d.cross(p - a)
      let d2 = (b2 - a2).unit
      return a2 + d2 * (t * newLength + along) + d2.leftNormal * offset
    }
    /// The room edge a segment runs along, if any.
    func carrier(_ p: Point2, _ q: Point2) -> Edge? {
      let u = (q - p).unit
      guard p.distance(to: q) > 1e-6 else { return nil }
      var best: (score: Double, edge: Edge)?
      for edge in edges {
        let a = nodes[edge.a]
        let b = nodes[edge.b]
        guard a.distance(to: b) > 1e-6, abs((b - a).unit.cross(u)) < sin(10 * Double.pi / 180)
        else { continue }
        let score =
          Geo.segmentDistance(p, a, b).distance + Geo.segmentDistance(q, a, b).distance
        if score < 0.3, best == nil || score < best!.score - 1e-12 { best = (score, edge) }
      }
      return best?.edge
    }
    func moveSegment(_ p: Point2, _ q: Point2) -> (Point2, Point2) {
      if let edge = carrier(p, q) {
        if moved[edge.a].distance(to: moved[edge.b]) < 1e-6 { return (p, p) }
        return (map(p, along: edge), map(q, along: edge))
      }
      var p2 = map(p)
      var q2 = map(q)
      let d = q2 - p2
      if d.length > 1e-6 {
        var angle = atan2(d.y, d.x)
        let quarter = Double.pi / 2
        angle -= (angle / quarter).rounded() * quarter
        if abs(angle) > 1e-12, abs(angle) <= tolerance {
          let middle = (p2 + q2) * 0.5
          p2 = middle + (p2 - middle).rotated(by: -angle)
          q2 = middle + (q2 - middle).rotated(by: -angle)
        }
      }
      return (p2, q2)
    }
    squared.walls = geometry.walls.map { wall in
      var w = wall
      (w.start, w.end) = moveSegment(wall.start, wall.end)
      return w
    }
    squared.openings = geometry.openings.map { opening in
      var o = opening
      (o.from, o.to) = moveSegment(opening.from, opening.to)
      return o
    }
    squared.objects = geometry.objects.map { object in
      var o = object
      let center = map(object.center)
      let shift = center - object.center
      var corners = object.corners.map { $0 + shift }
      // Square the footprint too when it is nearly square to the sheet.
      if corners.count == 4 {
        let edge = corners[3] - corners[0]
        if edge.length > 1e-6 {
          var angle = atan2(edge.y, edge.x)
          let quarter = Double.pi / 2
          angle -= (angle / quarter).rounded() * quarter
          if abs(angle) > 1e-9, abs(angle) <= tolerance {
            corners = corners.map { center + ($0 - center).rotated(by: -angle) }
          }
        }
      }
      o.center = center
      o.corners = corners
      return o
    }
    var bounds: PlanBounds?
    let points =
      squared.walls.flatMap { [$0.start, $0.end] } + squared.rooms.flatMap(\.polygon)
      + squared.objects.flatMap(\.corners)
    for p in points {
      if bounds == nil {
        bounds = PlanBounds(minX: p.x, minY: p.y, maxX: p.x, maxY: p.y)
      } else {
        bounds!.grow(p)
      }
    }
    squared.bounds = bounds
    return squared
  }

  /// An outline without repeated corners, corners where it runs straight on, or spikes where
  /// it doubles back on itself.
  static func tidy(_ polygon: [Point2]) -> [Point2] {
    var points = polygon
    var changed = true
    while changed && points.count >= 3 {
      changed = false
      for index in points.indices {
        let previous = points[(index + points.count - 1) % points.count]
        let current = points[index]
        let next = points[(index + 1) % points.count]
        let a = current - previous
        let b = next - current
        if a.length < 0.003 || abs(a.unit.cross(b.unit)) < 1e-6 || b.length < 1e-9 {
          points.remove(at: index)
          changed = true
          break
        }
      }
    }
    return points
  }

  /// True when two edges that are not neighbours cross or touch.
  static func selfIntersects(_ polygon: [Point2]) -> Bool {
    let n = polygon.count
    guard n > 3 else { return false }
    for i in 0..<(n - 2) {
      for j in (i + 2)..<n where !(i == 0 && j == n - 1) {
        if Geo.segmentsIntersect(
          polygon[i], polygon[(i + 1) % n], polygon[j], polygon[(j + 1) % n])
        {
          return true
        }
      }
    }
    return false
  }
}
