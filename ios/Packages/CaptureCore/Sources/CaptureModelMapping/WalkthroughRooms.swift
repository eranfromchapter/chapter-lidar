/// Faces of the final arrangement grouped into rooms (section 12 of the phase 3 spec): faces
/// without a seed are kept as rooms when they are enclosed or hold a defining object, otherwise
/// merged into a neighbour; a room inside another is merged into it; room boundaries are then
/// simplified together, so neighbouring rooms still share their edges exactly.
struct WalkthroughRooms {
  let arr: PlanArrangement
  /// Union-find over faces; the root of a group is its lowest face index.
  private var parent: [Int]

  init(arrangement: PlanArrangement) {
    arr = arrangement
    parent = Array(arrangement.faces.indices)
  }

  func find(_ face: Int) -> Int {
    var f = face
    while parent[f] != f { f = parent[f] }
    return f
  }

  mutating func union(_ a: Int, _ b: Int) {
    let ra = find(a)
    let rb = find(b)
    if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
  }

  /// Faces of each room, by root; empty for a face that is not a root.
  func members() -> [[Int]] {
    var result = [[Int]](repeating: [], count: parent.count)
    for f in parent.indices { result[find(f)].append(f) }
    return result
  }

  /// Roots in ascending order.
  func roots() -> [Int] { parent.indices.filter { find($0) == $0 } }

  /// The room on the left of the half-edge from `u` to `v`, or -1 for the outside.
  func room(of u: Int, _ v: Int) -> Int {
    arr.face(of: u, v).map(find) ?? -1
  }

  /// Boundary cycles of room `r` (faces `faces`), largest first. At a node where the boundary
  /// touches itself, the cycle takes the edge just clockwise of the way it came in.
  func boundary(_ r: Int, faces: [Int]) -> [[Int]] {
    var edges: [HalfEdge] = []
    for f in faces {
      let c = arr.faces[f]
      for i in c.indices {
        let u = c[i]
        let v = c[(i + 1) % c.count]
        if room(of: v, u) != r { edges.append(HalfEdge(u, v)) }
      }
    }
    var next: [Int: [Int]] = [:]
    for e in edges { next[e.u, default: []].append(e.v) }
    var cycles: [[Int]] = []
    var used = Set<HalfEdge>()
    for e0 in edges.sorted() where !used.contains(e0) {
      var cycle = [e0.u]
      used.insert(e0)
      var current = e0.v
      var previous = e0.u
      while current != e0.u {
        cycle.append(current)
        let options = (next[current] ?? []).filter { !used.contains(HalfEdge(current, $0)) }
        if options.isEmpty { break }
        var w = options[0]
        if options.count > 1 {
          let centre = arr.points[current]
          let sortedOptions = Plan2D.sortedAround(options, centre: centre, points: arr.points)
          let all = Plan2D.sortedAround(options + [previous], centre: centre, points: arr.points)
          let k = all.firstIndex(of: previous) ?? 0
          w = all[(k - 1 + all.count) % all.count]
          if w == previous { w = sortedOptions[0] }
        }
        used.insert(HalfEdge(current, w))
        previous = current
        current = w
      }
      cycles.append(cycle)
    }
    let areas = cycles.map { Plan2D.area($0.map { arr.points[$0] }) }
    return cycles.indices.sorted { (-areas[$0], $0) < (-areas[$1], $1) }.map { cycles[$0] }
  }

  /// Per neighbouring room: the length of boundary shared with room `r`, and how much of it is
  /// virtual.
  func shared(_ r: Int, faces: [Int]) -> [Int: (total: Double, virtual: Double)] {
    var result: [Int: (total: Double, virtual: Double)] = [:]
    for f in faces {
      let c = arr.faces[f]
      for i in c.indices {
        let u = c[i]
        let v = c[(i + 1) % c.count]
        let other = room(of: v, u)
        if other == r || other < 0 { continue }
        let length = Plan2D.dist(arr.points[u], arr.points[v])
        let virtual = arr.edgeClass(u, v) == .virtual ? length : 0
        let sums = result[other] ?? (0, 0)
        result[other] = (sums.total + length, sums.virtual + virtual)
      }
    }
    return result
  }

  /// The virtual share of room `r`'s boundary (cuts and closures), 1 when it has no boundary.
  func virtualFraction(_ r: Int, faces: [Int]) -> Double {
    var total = 0.0
    var virtual = 0.0
    for f in faces {
      let c = arr.faces[f]
      for i in c.indices {
        let u = c[i]
        let v = c[(i + 1) % c.count]
        if room(of: v, u) == r { continue }
        let length = Plan2D.dist(arr.points[u], arr.points[v])
        total += length
        if arr.edgeClass(u, v) == .virtual { virtual += length }
      }
    }
    return total != 0 ? virtual / total : 1
  }

  func area(of faces: [Int]) -> Double {
    var sum = 0.0
    for f in faces { sum += Plan2D.area(arr.polygon(f)) }
    return sum
  }

  /// Merges faces without a seed that are slivers, or that are neither enclosed (at most
  /// `enclosedVirtual` of the boundary virtual) nor hold a defining object, into the neighbour
  /// they share the most virtual boundary with; then merges rooms that lie inside another room.
  mutating func resolve(
    seedFaces: Set<Int>, plan: WalkthroughInput.Plan, parameters p: WalkthroughSplitter.Parameters,
    diagnostics: inout WalkthroughSplitter.Diagnostics
  ) {
    var kept = Set<Int>()
    for _ in 0..<500 {
      var changed = false
      let groups = members()
      let order = roots().sorted { (area(of: groups[$0]), $0) < (area(of: groups[$1]), $1) }
      for r in order {
        let faces = groups[r]
        if kept.contains(r) || faces.contains(where: seedFaces.contains) { continue }
        guard let ring = boundary(r, faces: faces).first else { continue }
        let poly = ring.map { arr.points[$0] }
        let a = area(of: faces)
        let perimeter = Plan2D.perimeter(poly)
        let virtualFraction = virtualFraction(r, faces: faces)
        let definingObjects = plan.objects.contains { object in
          object.definingType != nil
            && faces.contains { Plan2D.contains(arr.polygon($0), object.center) }
        }
        let sliver = a < p.sliverArea || 2 * a / perimeter < p.sliverWidth
        if !sliver && (definingObjects || virtualFraction <= p.enclosedVirtual) {
          kept.insert(r)
          continue
        }
        let neighbours = shared(r, faces: faces)
        var best: (key: (Double, Double, Int), room: Int)?
        for g in neighbours.keys.sorted() {
          let sums = neighbours[g]!
          let key = (sums.virtual, sums.total, -g)
          if best == nil || key > best!.key { best = (key, g) }
        }
        guard let best else {
          kept.insert(r)
          continue
        }
        diagnostics.merges.append(
          .init(kind: sliver ? .sliver : .sectionless, areaM2: a, virtualFraction: virtualFraction))
        union(r, best.room)
        kept = kept.filter { find($0) == $0 }
        changed = true
        break
      }
      if !changed { break }
    }
    // One contract polygon has no holes: a room that encloses another takes it in.
    for _ in 0..<50 {
      let groups = members()
      var swallowed = false
      for r in roots() {
        for hole in boundary(r, faces: groups[r]).dropFirst() {
          let other = room(of: hole[1 % hole.count], hole[0])
          if other >= 0 && other != r {
            diagnostics.merges.append(
              .init(kind: .enclosed, areaM2: area(of: groups[other]), virtualFraction: 0))
            union(r, other)
            swallowed = true
            break
          }
        }
        if swallowed { break }
      }
      if !swallowed { break }
    }
  }

  /// Each room's ring with the boundary simplified: a node of degree 2 whose two edges have the
  /// same rooms on them is dropped when it, and every node already dropped along its two edges,
  /// lies within `tolerance` of the chord (1e-6 m for outline corners). Then, per room, vertices
  /// collinear within 1e-6 m are dropped. Indexed by root.
  func simplifiedRings(
    tolerance: Double, diagnostics: inout WalkthroughSplitter.Diagnostics
  ) -> [Int: [Int]] {
    let groups = members()
    let roots = roots()
    var rings: [Int: [Int]] = [:]
    for r in roots { rings[r] = boundary(r, faces: groups[r]).first ?? [] }
    var edgeRooms: [EdgeKey: [Int]] = [:]
    for r in roots {
      let ring = rings[r]!
      for i in ring.indices {
        let key = EdgeKey(ring[i], ring[(i + 1) % ring.count])
        var rooms = edgeRooms[key] ?? []
        if !rooms.contains(r) {
          rooms.append(r)
          rooms.sort()
        }
        edgeRooms[key] = rooms
      }
    }
    var neighbours: [Int: Set<Int>] = [:]
    for key in edgeRooms.keys {
      neighbours[key.u, default: []].insert(key.v)
      neighbours[key.v, default: []].insert(key.u)
    }
    var removedOn: [EdgeKey: [Int]] = [:]
    var dropped = Set<Int>()
    func limit(_ node: Int) -> Double { arr.isFixed[node] ? 1e-6 : tolerance }
    var changed = true
    while changed {
      changed = false
      for x in neighbours.keys.sorted() {
        guard !dropped.contains(x), let around = neighbours[x], around.count == 2 else { continue }
        let pair = around.sorted()
        let u = pair[0]
        let w = pair[1]
        let pu = arr.points[u]
        let pw = arr.points[w]
        let px = arr.points[x]
        if Plan2D.dot(px - pu, pw - px) <= 0 { continue }
        let chord = [x] + (removedOn[EdgeKey(u, x)] ?? []) + (removedOn[EdgeKey(x, w)] ?? [])
        let length = Plan2D.dist(pu, pw)
        if length < 1e-9 { continue }
        let direction = (pw - pu) * (1 / length)
        if chord.contains(where: { abs(Plan2D.cross(direction, arr.points[$0] - pu)) > limit($0) })
        {
          continue
        }
        if edgeRooms[EdgeKey(u, x)] != edgeRooms[EdgeKey(x, w)] { continue }
        if edgeRooms[EdgeKey(u, w)] != nil { continue }
        let rooms = edgeRooms.removeValue(forKey: EdgeKey(u, x))
        edgeRooms[EdgeKey(x, w)] = nil
        edgeRooms[EdgeKey(u, w)] = rooms
        removedOn[EdgeKey(u, w)] = chord
        neighbours[u]?.remove(x)
        neighbours[w]?.remove(x)
        neighbours[u]?.insert(w)
        neighbours[w]?.insert(u)
        neighbours[x] = nil
        dropped.insert(x)
        diagnostics.simplifiedShared += 1
        changed = true
      }
    }
    var out: [Int: [Int]] = [:]
    for r in roots {
      var ring = rings[r]!.filter { !dropped.contains($0) }
      var again = true
      while again && ring.count > 3 {
        again = false
        for i in ring.indices {
          let a = arr.points[ring[(i - 1 + ring.count) % ring.count]]
          let x = arr.points[ring[i]]
          let b = arr.points[ring[(i + 1) % ring.count]]
          let length = Plan2D.dist(a, b)
          if length > 1e-9, abs(Plan2D.cross(b - a, x - a)) / length <= 1e-6,
            Plan2D.dot(x - a, b - x) > 0
          {
            ring.remove(at: i)
            diagnostics.simplifiedCollinear += 1
            again = true
            break
          }
        }
      }
      out[r] = ring
    }
    return out
  }
}
