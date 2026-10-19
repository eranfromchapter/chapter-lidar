/// What an arrangement edge is made of. An edge can carry several kinds when segments overlap.
struct EdgeKinds: OptionSet, Hashable, Sendable {
  let rawValue: Int

  // Kinds of the whole-scan arrangement.
  /// An edge of the floor outline.
  static let outline = EdgeKinds(rawValue: 1 << 0)
  /// A piece of an interior wall.
  static let wall = EdgeKinds(rawValue: 1 << 1)
  /// A short closure of a wall end that stops short.
  static let gap = EdgeKinds(rawValue: 1 << 2)
  /// A cut that separates two sections.
  static let cut = EdgeKinds(rawValue: 1 << 3)
  /// A closure that encloses a room without a section.
  static let close = EdgeKinds(rawValue: 1 << 4)
  // Kinds of a local check of one face.
  /// A ring edge backed by a wall, the outline or a gap.
  static let real = EdgeKinds(rawValue: 1 << 5)
  /// A ring edge that is a cut or a closure.
  static let virtual = EdgeKinds(rawValue: 1 << 6)
  /// A wall stub hanging into the face.
  static let hint = EdgeKinds(rawValue: 1 << 7)
  /// A segment of the candidate being checked.
  static let new = EdgeKinds(rawValue: 1 << 8)

  /// `real` when a wall, the outline or a gap closure backs the edge, otherwise `virtual`.
  var edgeClass: EdgeKinds {
    isDisjoint(with: [.wall, .outline, .gap]) ? .virtual : .real
  }
}

/// A segment to arrange. Fixed segments form the boundary ring.
struct PlanSegment: Sendable {
  var a: P2
  var b: P2
  var kind: EdgeKinds
  /// Source wall index of a wall piece or a gap.
  var wall: Int?
  var fixed: Bool = false
}

/// An undirected edge, `u < v`.
struct EdgeKey: Hashable, Comparable, Sendable {
  var u: Int
  var v: Int

  init(_ a: Int, _ b: Int) {
    u = min(a, b)
    v = max(a, b)
  }

  static func < (l: EdgeKey, r: EdgeKey) -> Bool { (l.u, l.v) < (r.u, r.v) }
}

/// A directed edge from `u` to `v`.
struct HalfEdge: Hashable, Comparable, Sendable {
  var u: Int
  var v: Int

  init(_ u: Int, _ v: Int) {
    self.u = u
    self.v = v
  }

  static func < (l: HalfEdge, r: HalfEdge) -> Bool { (l.u, l.v) < (r.u, r.v) }
}

/// The planar arrangement of segments inside a boundary ring: nodes welded within `eps`, segments
/// split where they cross or touch, and the faces traced. Used for the whole scan (the boundary is
/// the floor outline) and for the local check of one face (the boundary is the face ring).
///
/// Boundary vertices stay exact, and points on a fixed segment only weld to nodes that lie on it.
/// Edges whose two sides are the same face (wall stubs) become hints, as do components that touch
/// no boundary vertex (a column). Every order is by index, never by hashing.
struct PlanArrangement {
  struct EdgeInfo: Sendable {
    var kinds: EdgeKinds
    var fixed: Bool
  }

  let eps: Double
  let boundary: [P2]
  private(set) var points: [P2] = []
  private(set) var isFixed: [Bool] = []
  private(set) var edges: [EdgeKey: EdgeInfo] = [:]
  /// Edges that bound faces, sorted.
  private(set) var active: [EdgeKey] = []
  /// Wall stubs and islands, sorted.
  private(set) var hints: [EdgeKey] = []
  private(set) var islandEdges = 0
  /// Faces as node rings, counter-clockwise, in discovery order.
  private(set) var faces: [[Int]] = []
  /// Traced cycles that are not faces (the outer side of each component).
  private(set) var negatives = 0
  private var faceOfHalfEdge: [HalfEdge: Int] = [:]
  private var fixedIds: [Int] = []

  init(segments: [PlanSegment], eps: Double, boundary: [P2]) {
    self.eps = eps
    self.boundary = boundary
    for p in boundary { _ = fixedNode(p) }
    // The node of each end of a segment that is not fixed, found once, in segment order.
    var endNode = [[Int]](repeating: [], count: segments.count)
    for (i, segment) in segments.enumerated() where !segment.fixed {
      endNode[i] = [node(segment.a), node(segment.b)]
    }

    // Split parameters: (t, point, append order, what the point is). A segment end, wherever it
    // splits a segment, is the node found for it above, and a crossing is one node on both
    // segments; found again later, a point could weld to a node made in between, and an edge
    // would then cross another without a node.
    enum Source {
      case end(Int, Int)
      case crossing(Int)
    }
    var params: [[(t: Double, p: P2, order: Int, source: Source)]] = segments.indices.map {
      [(0, segments[$0].a, 0, .end($0, 0)), (1, segments[$0].b, 1, .end($0, 1))]
    }
    var crossings = 0
    func append(_ i: Int, _ t: Double, _ p: P2, _ source: Source) {
      params[i].append((t, p, params[i].count, source))
    }
    let n = segments.count
    for i in 0..<n {
      let a = segments[i].a
      let b = segments[i].b
      let l = Plan2D.dist(a, b)
      if l < 1e-12 { continue }
      for j in (i + 1)..<max(i + 1, n) {
        let c = segments[j].a
        let d = segments[j].b
        let m = Plan2D.dist(c, d)
        if m < 1e-12 { continue }
        if let r = Plan2D.segSeg(a, b, c, d), -eps / l <= r.t, r.t <= 1 + eps / l,
          -eps / m <= r.u, r.u <= 1 + eps / m
        {
          // Parameters past an end stay as they are: such a crossing extends the segment, so it
          // comes before its start or after its end, not between the start and the next point.
          let p = a + (b - a) * r.t
          append(i, r.t, p, .crossing(crossings))
          append(j, r.u, p, .crossing(crossings))
          crossings += 1
        }
      }
      // An end that projects onto one of this segment's own ends (for example the free end of a
      // wall next to the tip of a closure built at right angles to that wall) is left to the
      // welding: rounding must not decide whether it also splits this segment.
      for j in 0..<n where j != i {
        for (k, e) in [segments[j].a, segments[j].b].enumerated() {
          let (distance, t) = Plan2D.segPoint(e, a, b)
          if distance < eps, 1e-9 < t, t < 1 - 1e-9 { append(i, t, e, .end(j, k)) }
        }
      }
    }
    var crossingNode = [Int?](repeating: nil, count: crossings)
    for (i, segment) in segments.enumerated() {
      let sorted = params[i].sorted { ($0.t, $0.order) < ($1.t, $1.order) }
      var ids: [Int] = []
      for entry in sorted {
        let id: Int
        switch entry.source {
        case .end(let j, let k) where !segment.fixed && !endNode[j].isEmpty:
          id = endNode[j][k]
        case .crossing(let c) where !segment.fixed && crossingNode[c] != nil:
          id = crossingNode[c]!
        case .crossing(let c):
          id = node(entry.p, on: segment.fixed ? (segment.a, segment.b) : nil)
          if crossingNode[c] == nil { crossingNode[c] = id }
        default:
          id = node(entry.p, on: segment.fixed ? (segment.a, segment.b) : nil)
        }
        if ids.last != id { ids.append(id) }
      }
      for k in ids.indices.dropFirst() {
        addEdge(ids[k - 1], ids[k], kind: segment.kind, fixed: segment.fixed)
      }
    }
    for key in edges.keys.sorted() {
      guard let info = edges[key], !info.fixed else { continue }
      let m = (points[key.u] + points[key.v]) * 0.5
      if !Plan2D.contains(boundary, m) || Plan2D.polyDist(boundary, m) <= 1e-7 {
        edges[key] = nil
      }
    }
    traceAll()
  }

  private mutating func fixedNode(_ p: P2) -> Int {
    for i in fixedIds where Plan2D.dist(points[i], p) <= 1e-12 { return i }
    points.append(p)
    isFixed.append(true)
    fixedIds.append(points.count - 1)
    return points.count - 1
  }

  /// The nearest node less than `eps` away (ties to the lowest id), or a new node. With `on`, only
  /// nodes within 1e-7 of that segment qualify. Nodes are made in segment order, so of several
  /// ends within `eps` the first one made stays; the walk-through passes its walls in an order
  /// taken from the walls themselves (`WalkthroughSegments.canonicalOrder`), not from the file,
  /// and has already moved wall ends that meet onto one point (`WalkthroughSegments.weldEnds`).
  private mutating func node(_ p: P2, on: (P2, P2)? = nil) -> Int {
    var best: (distance: Double, id: Int)?
    for (i, q) in points.enumerated() {
      if let on, Plan2D.segPoint(q, on.0, on.1).distance > 1e-7 { continue }
      let d = Plan2D.dist(p, q)
      if d < eps, best == nil || d < best!.distance { best = (d, i) }
    }
    if let best { return best.id }
    points.append(p)
    isFixed.append(false)
    return points.count - 1
  }

  private mutating func addEdge(_ u: Int, _ v: Int, kind: EdgeKinds, fixed: Bool) {
    guard u != v else { return }
    let key = EdgeKey(u, v)
    var info = edges[key] ?? EdgeInfo(kinds: [], fixed: false)
    info.kinds.formUnion(kind)
    info.fixed = info.fixed || fixed
    edges[key] = info
  }

  // MARK: Faces

  /// Cycles of the half-edges of `keys`: at each node the next half-edge turns as far right as
  /// possible, so bounded faces come out counter-clockwise.
  private func trace(_ keys: [EdgeKey]) -> (cycles: [[Int]], cycleOf: [HalfEdge: Int]) {
    var around = [[Int]](repeating: [], count: points.count)
    for key in keys {
      around[key.u].append(key.v)
      around[key.v].append(key.u)
    }
    for u in around.indices where !around[u].isEmpty {
      around[u] = Plan2D.sortedAround(around[u], centre: points[u], points: points)
    }
    var cycleOf: [HalfEdge: Int] = [:]
    var cycles: [[Int]] = []
    for u0 in around.indices {
      for v0 in around[u0] where cycleOf[HalfEdge(u0, v0)] == nil {
        var ring: [Int] = []
        var u = u0
        var v = v0
        while cycleOf[HalfEdge(u, v)] == nil {
          cycleOf[HalfEdge(u, v)] = cycles.count
          ring.append(u)
          let list = around[v]
          let position = list.firstIndex(of: u) ?? 0
          let w = list[(position - 1 + list.count) % list.count]
          u = v
          v = w
        }
        cycles.append(ring)
      }
    }
    return (cycles, cycleOf)
  }

  private mutating func traceAll() {
    var active = edges.keys.sorted()
    var hints: [EdgeKey] = []
    var traced = trace(active)
    while true {
      let bad = active.filter {
        traced.cycleOf[HalfEdge($0.u, $0.v)] == traced.cycleOf[HalfEdge($0.v, $0.u)]
      }
      if bad.isEmpty { break }
      hints += bad
      let badSet = Set(bad)
      active = active.filter { !badSet.contains($0) }
      traced = trace(active)
    }
    // Islands: components of the active edges without a boundary vertex.
    var adjacency = [[Int]](repeating: [], count: points.count)
    for key in active {
      adjacency[key.u].append(key.v)
      adjacency[key.v].append(key.u)
    }
    var component = [Int](repeating: -1, count: points.count)
    for s in adjacency.indices where !adjacency[s].isEmpty && component[s] < 0 {
      component[s] = s
      var stack = [s]
      while let x = stack.popLast() {
        for y in adjacency[x] where component[y] < 0 {
          component[y] = s
          stack.append(y)
        }
      }
    }
    var grounded = Set<Int>()
    for x in component.indices where component[x] >= 0 && isFixed[x] {
      grounded.insert(component[x])
    }
    let islands = active.filter { !grounded.contains(component[$0.u]) }
    if !islands.isEmpty {
      hints += islands
      let islandSet = Set(islands)
      active = active.filter { !islandSet.contains($0) }
      traced = trace(active)
    }
    self.active = active
    self.hints = hints.sorted()
    islandEdges = islands.count
    faces = []
    negatives = 0
    for cycle in traced.cycles {
      if Plan2D.area(cycle.map { points[$0] }) > 1e-9 {
        faces.append(cycle)
      } else {
        negatives += 1
      }
    }
    faceOfHalfEdge = [:]
    for (f, ring) in faces.enumerated() {
      for i in ring.indices {
        faceOfHalfEdge[HalfEdge(ring[i], ring[(i + 1) % ring.count])] = f
      }
    }
  }

  /// The ring of face `f` as points.
  func polygon(_ f: Int) -> [P2] { faces[f].map { points[$0] } }

  /// The face on the left of the half-edge from `u` to `v`, or nil (the outside).
  func face(of u: Int, _ v: Int) -> Int? { faceOfHalfEdge[HalfEdge(u, v)] }

  func info(_ u: Int, _ v: Int) -> EdgeInfo? { edges[EdgeKey(u, v)] }

  /// `real` or `virtual` (see `EdgeKinds.edgeClass`); an unknown edge is virtual.
  func edgeClass(_ u: Int, _ v: Int) -> EdgeKinds {
    info(u, v)?.kinds.edgeClass ?? .virtual
  }

  func length(_ key: EdgeKey) -> Double { Plan2D.dist(points[key.u], points[key.v]) }

  /// No two active edges cross, the faces tile the boundary, and there is one outer cycle.
  func selfCheck() -> Bool {
    let e = active
    for i in e.indices {
      for j in (i + 1)..<max(i + 1, e.count) {
        let (a, b) = (e[i].u, e[i].v)
        let (c, d) = (e[j].u, e[j].v)
        if a == c || a == d || b == c || b == d { continue }
        if let r = Plan2D.segSeg(points[a], points[b], points[c], points[d]),
          1e-9 < r.t, r.t < 1 - 1e-9, 1e-9 < r.u, r.u < 1 - 1e-9
        {
          return false
        }
      }
    }
    var total = 0.0
    for f in faces.indices { total += Plan2D.area(polygon(f)) }
    let boundaryArea = Plan2D.area(boundary)
    guard abs(total - boundaryArea) <= 1e-6 * max(1, boundaryArea) else { return false }
    return negatives == 1
  }

  /// The first face that contains `p`, or nil.
  func faceContaining(_ p: P2) -> Int? {
    faces.indices.first { Plan2D.contains(polygon($0), p) }
  }

  /// The first face that contains `p`, or else the nearest face (ties to the lower index).
  func faceNearest(_ p: P2) -> Int {
    if let f = faceContaining(p) { return f }
    var best: (distance: Double, face: Int)?
    for f in faces.indices {
      let d = Plan2D.polyDist(polygon(f), p)
      if best == nil || d < best!.distance { best = (d, f) }
    }
    return best?.face ?? 0
  }
}
