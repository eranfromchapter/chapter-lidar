import CaptureContract

/// Cuts that separate the seeds of one face, and closures that enclose a room without a section
/// (sections 8 to 11 of the phase 3 spec).
///
/// A face that holds two or more seeds is split by the cheapest valid cut: a ray from a reflex
/// corner, a wall stub extended or bridged to the boundary, two stubs joined, or two corners
/// joined. Each candidate is checked by building the arrangement of the face alone with it. A face
/// with no such cue stays one room; there is no straight-line fallback.
struct WalkthroughCuts {
  let plan: WalkthroughInput.Plan
  let parameters: WalkthroughSplitter.Parameters
  let axes: PlanAxes
  let eps: Double

  struct Candidate {
    /// The virtual segments of the cut; the wall parts are hint edges already in the arrangement.
    var segments: [(P2, P2)]
    var tag: String
  }

  struct Check {
    var pieces: [[P2]]
    /// The piece of each seed of the face, in seed order.
    var owner: [Int?]
    var virtualLength: Double
    var wallLength: Double
    var score: Double
    /// Per piece, the length of its boundary that is virtual (cuts and closures).
    var virtualPerimeter: [Double]
  }

  func build(_ segments: [PlanSegment]) -> PlanArrangement {
    PlanArrangement(segments: segments, eps: eps, boundary: plan.outline)
  }

  /// The hint edges whose midpoint lies inside face `f`.
  func faceHints(_ arr: PlanArrangement, _ f: Int) -> [EdgeKey] {
    let poly = arr.polygon(f)
    return arr.hints.filter {
      Plan2D.contains(poly, (arr.points[$0.u] + arr.points[$0.v]) * 0.5)
    }
  }

  // MARK: Candidates

  static func reflexVertices(_ poly: [P2]) -> [Int] {
    let n = poly.count
    var out: [Int] = []
    for i in 0..<n {
      let a = poly[(i - 1 + n) % n]
      let v = poly[i]
      let b = poly[(i + 1) % n]
      let e1 = v - a
      let e2 = b - v
      if Plan2D.cross(e1, e2) < -Plan2D.sin5 * Plan2D.norm(e1) * Plan2D.norm(e2) { out.append(i) }
    }
    return out
  }

  /// The nearest crossing of the ray from `o` along `d` with the ring, up to `maxLength`, skipping
  /// the two edges at vertex `skipVertex`.
  static func boundaryHit(_ poly: [P2], _ o: P2, _ d: P2, maxLength: Double, skipVertex: Int? = nil)
    -> Double?
  {
    var best: Double?
    let n = poly.count
    let far = o + d * maxLength
    for i in 0..<n {
      if let skipVertex, i == skipVertex || (i + 1) % n == skipVertex { continue }
      if let r = Plan2D.segSeg(o, far, poly[i], poly[(i + 1) % n]), -1e-9 <= r.u, r.u <= 1 + 1e-9 {
        let s = r.t * maxLength
        if 1e-6 < s, s <= maxLength, best == nil || s < best! { best = s }
      }
    }
    return best
  }

  static func hintHit(
    _ arr: PlanArrangement, _ hints: [EdgeKey], _ o: P2, _ d: P2, maxLength: Double,
    skipNodes: [Int]
  ) -> Double? {
    var best: Double?
    let far = o + d * maxLength
    for key in hints where !skipNodes.contains(key.u) && !skipNodes.contains(key.v) {
      if let r = Plan2D.segSeg(o, far, arr.points[key.u], arr.points[key.v]),
        -1e-9 <= r.u, r.u <= 1 + 1e-9
      {
        let s = r.t * maxLength
        if 1e-6 < s, s <= maxLength, best == nil || s < best! { best = s }
      }
    }
    return best
  }

  struct StubPath {
    var nodes: [Int]
    /// The ring node the stub hangs from; nil for a floating stub.
    var base: Int?
    var gaps: [(P2, P2)]
    var chained: Bool
  }

  /// Hint chains hanging into face `f`, as node paths from base to tip (base nil when floating).
  /// An attached chain is also offered continued through floating chains in line with it.
  func stubPaths(_ arr: PlanArrangement, _ f: Int, _ hints: [EdgeKey]) -> [StubPath] {
    var adjacency: [Int: [Int]] = [:]
    for key in hints {
      adjacency[key.u, default: []].append(key.v)
      adjacency[key.v, default: []].append(key.u)
    }
    for key in adjacency.keys.sorted() { adjacency[key]?.sort() }
    let onRing = Set(arr.faces[f])
    var raw: [StubPath] = []
    var seen = Set<EdgeKey>()
    for leaf in adjacency.keys.sorted() {
      guard let first = adjacency[leaf], first.count == 1, !onRing.contains(leaf) else { continue }
      var path = [leaf]
      var previous: Int?
      var current = leaf
      while true {
        let neighbours = adjacency[current] ?? []
        if current != leaf && (onRing.contains(current) || neighbours.count != 2) { break }
        guard let next = neighbours.first(where: { $0 != previous }) else { break }
        previous = current
        current = next
        path.append(current)
      }
      let key = EdgeKey(path[0], path[path.count - 1])
      if seen.contains(key) { continue }
      seen.insert(key)
      path.reverse()
      raw.append(
        StubPath(
          nodes: path, base: onRing.contains(path[0]) ? path[0] : nil, gaps: [], chained: false))
    }
    let floating = raw.filter { $0.base == nil }
    var out = raw
    for stub in raw where stub.base != nil && stub.nodes.count >= 2 {
      var nodes = stub.nodes
      var gaps: [(P2, P2)] = []
      var used = Set<Int>()
      while true {
        let tip = arr.points[nodes[nodes.count - 1]]
        guard let along = Plan2D.unit(tip - arr.points[nodes[nodes.count - 2]]) else { break }
        let d = axes.snap(along)
        var best: (along: Double, index: Int, order: [Int])?
        for (k, other) in floating.enumerated() where !used.contains(k) {
          var ends: [(along: Double, lateral: Double, node: Int)] = []
          for e in [other.nodes[0], other.nodes[other.nodes.count - 1]] {
            let v = arr.points[e] - tip
            ends.append((Plan2D.dot(v, d), abs(Plan2D.cross(d, v)), e))
          }
          if ends.map(\.lateral).max()! > parameters.chainLateral { continue }
          let near = ends.min { ($0.along, $0.lateral, $0.node) < ($1.along, $1.lateral, $1.node) }!
          if !(1e-6 < near.along && near.along <= parameters.bridgeMax) { continue }
          let order = near.node == other.nodes[0] ? other.nodes : other.nodes.reversed()
          if best == nil || near.along < best!.along { best = (near.along, k, order) }
        }
        guard let best else { break }
        used.insert(best.index)
        gaps.append((arr.points[nodes[nodes.count - 1]], arr.points[best.order[0]]))
        nodes += best.order
        out.append(StubPath(nodes: nodes, base: stub.base, gaps: gaps, chained: true))
      }
    }
    return out
  }

  /// Cut candidates in face `f`, in a fixed order: rays from reflex corners; per wall stub the
  /// extension, the two perpendiculars and bridges to corners and edges; stub to stub; corner to
  /// corner. Duplicates keep the first.
  func candidates(_ arr: PlanArrangement, _ f: Int, _ hints: [EdgeKey]) -> [Candidate] {
    let p = parameters
    let ring = arr.faces[f]
    let poly = arr.polygon(f)
    let n = poly.count
    var out: [Candidate] = []
    let reflex = Self.reflexVertices(poly)

    func ray(
      _ o: P2, _ d: P2, _ tag: String, gaps: [(P2, P2)] = [], skipNodes: [Int] = [],
      skipVertex: Int? = nil
    ) {
      let h = Self.boundaryHit(poly, o, d, maxLength: p.cutMax, skipVertex: skipVertex)
      if let h { out.append(Candidate(segments: gaps + [(o, o + d * h)], tag: tag)) }
      if let s = Self.hintHit(arr, hints, o, d, maxLength: p.cutMax, skipNodes: skipNodes),
        h == nil || s < h! - 1e-9
      {
        out.append(Candidate(segments: gaps + [(o, o + d * s)], tag: tag + "-to-stub"))
      }
    }

    for i in reflex {
      let v = poly[i]
      for d in [Plan2D.unit(v - poly[(i - 1 + n) % n]), Plan2D.unit(v - poly[(i + 1) % n])] {
        if let d { ray(v, d, "reflex-ray", skipNodes: [ring[i]], skipVertex: i) }
      }
    }

    var tips: [(stub: StubPath, points: [P2])] = []
    for stub in stubPaths(arr, f, hints) {
      let pts = stub.nodes.map { arr.points[$0] }
      if pts.count < 2 { continue }
      let tag = stub.chained ? "chain-" : "stub-"
      if stub.base == nil {
        guard let u1 = Plan2D.unit(pts[0] - pts[1]),
          let u2 = Plan2D.unit(pts[pts.count - 1] - pts[pts.count - 2])
        else { continue }
        let d1 = axes.snap(u1)
        let d2 = axes.snap(u2)
        if let h1 = Self.boundaryHit(poly, pts[0], d1, maxLength: p.cutMax),
          let h2 = Self.boundaryHit(poly, pts[pts.count - 1], d2, maxLength: p.cutMax)
        {
          out.append(
            Candidate(
              segments: [
                (pts[0] + d1 * h1, pts[0]), (pts[pts.count - 1], pts[pts.count - 1] + d2 * h2),
              ], tag: "floating-extend"))
        }
        continue
      }
      let tip = pts[pts.count - 1]
      tips.append((stub, pts))
      guard let along = Plan2D.unit(tip - pts[pts.count - 2]) else { continue }
      let d = axes.snap(along)
      let skip = [stub.nodes[stub.nodes.count - 1]]
      ray(tip, d, tag + "extend", gaps: stub.gaps, skipNodes: skip)
      ray(tip, P2(-d.y, d.x), tag + "perp", gaps: stub.gaps, skipNodes: skip)
      ray(tip, P2(d.y, -d.x), tag + "perp", gaps: stub.gaps, skipNodes: skip)
      for i in reflex where Plan2D.dist(tip, poly[i]) <= p.bridgeMax {
        out.append(Candidate(segments: stub.gaps + [(tip, poly[i])], tag: tag + "bridge-corner"))
      }
      for i in 0..<n {
        let (dd, t) = Plan2D.segPoint(tip, poly[i], poly[(i + 1) % n])
        if dd <= p.bridgeMax, 1e-6 < t, t < 1 - 1e-6 {
          let q = poly[i] + (poly[(i + 1) % n] - poly[i]) * t
          out.append(Candidate(segments: stub.gaps + [(tip, q)], tag: tag + "bridge-edge"))
        }
      }
    }
    for x in tips.indices {
      for y in (x + 1)..<max(x + 1, tips.count) {
        let (s1, p1) = tips[x]
        let (s2, p2) = tips[y]
        let t1 = p1[p1.count - 1]
        let t2 = p2[p2.count - 1]
        if s1.base == s2.base || Plan2D.dist(t1, t2) > p.bridgeMax { continue }
        if !Set(s1.nodes).isDisjoint(with: s2.nodes) { continue }
        out.append(Candidate(segments: s1.gaps + [(t1, t2)] + s2.gaps, tag: "stub-stub"))
      }
    }
    for x in reflex.indices {
      for y in (x + 1)..<max(x + 1, reflex.count) {
        let i = reflex[x]
        let j = reflex[y]
        if Plan2D.dist(poly[i], poly[j]) <= p.bridgeMax, abs(i - j) != 1, abs(i - j) != n - 1 {
          out.append(Candidate(segments: [(poly[i], poly[j])], tag: "corner-corner"))
        }
      }
    }

    var seen = Set<[Int64]>()
    var result: [Candidate] = []
    for var candidate in out {
      candidate.segments = candidate.segments.filter { Plan2D.dist($0.0, $0.1) > 1e-9 }
      if candidate.segments.isEmpty { continue }
      let key = candidate.segments.map { segment -> [Int64] in
        let a = [Self.micro(segment.0.x), Self.micro(segment.0.y)]
        let b = [Self.micro(segment.1.x), Self.micro(segment.1.y)]
        return a.lexicographicallyPrecedes(b) ? a + b : b + a
      }.sorted { $0.lexicographicallyPrecedes($1) }.flatMap { $0 }
      if seen.contains(key) { continue }
      seen.insert(key)
      result.append(candidate)
    }
    return result
  }

  /// `x` rounded to a micrometre, as an integer key.
  static func micro(_ x: Double) -> Int64 { Int64((x * 1e6).rounded(.toNearestOrEven)) }

  // MARK: Local check

  /// Builds the arrangement of face `f` alone with its hints and the candidate; nil when the
  /// candidate does not cut the face cleanly or breaks an object rule, else the pieces and score.
  func check(
    _ arr: PlanArrangement, _ f: Int, _ hints: [EdgeKey], _ candidate: Candidate,
    seeds: [WalkthroughSeed]
  ) -> Check? {
    let p = parameters
    let ring = arr.faces[f]
    let poly = arr.polygon(f)
    var segments: [PlanSegment] = []
    for i in ring.indices {
      let u = ring[i]
      let v = ring[(i + 1) % ring.count]
      segments.append(
        PlanSegment(a: arr.points[u], b: arr.points[v], kind: arr.edgeClass(u, v), fixed: true))
    }
    for key in hints {
      segments.append(PlanSegment(a: arr.points[key.u], b: arr.points[key.v], kind: .hint))
    }
    var virtualTotal = 0.0
    for segment in candidate.segments {
      segments.append(PlanSegment(a: segment.0, b: segment.1, kind: .new))
      virtualTotal += Plan2D.dist(segment.0, segment.1)
    }
    let local = PlanArrangement(segments: segments, eps: 1e-7, boundary: poly)
    let pieces = local.faces.indices.map { local.polygon($0) }
    if pieces.count < 2 { return nil }
    var piecesArea = 0.0
    for piece in pieces { piecesArea += Plan2D.area(piece) }
    let faceArea = Plan2D.area(poly)
    if abs(piecesArea - faceArea) > 1e-6 * max(1, faceArea) { return nil }
    var virtualActive = 0.0
    var wallLength = 0.0
    for key in local.active {
      guard let info = local.edges[key] else { continue }
      if info.kinds.contains(.new) {
        virtualActive += local.length(key)
      } else if info.kinds.contains(.hint) {
        wallLength += local.length(key)
      }
    }
    // Part of the cut dangles or leaves the face.
    if abs(virtualActive - virtualTotal) > 1e-6 { return nil }
    let owner: [Int?] = seeds.map { seed in
      pieces.indices.first { Plan2D.contains(pieces[$0], seed.at) }
    }
    var virtualPerimeter = [Double](repeating: 0, count: pieces.count)
    for g in local.faces.indices {
      let c = local.faces[g]
      for i in c.indices {
        let u = c[i]
        let v = c[(i + 1) % c.count]
        if let kinds = local.info(u, v)?.kinds, !kinds.isDisjoint(with: [.virtual, .new]),
          kinds.isDisjoint(with: [.real, .hint])
        {
          virtualPerimeter[g] += Plan2D.dist(local.points[u], local.points[v])
        }
      }
    }
    let objects = plan.objects.filter { Plan2D.contains(poly, $0.center) }
    // Never cut through a bed, toilet, bathtub or appliance.
    for object in objects where object.definingType != nil {
      let footprint = WalkthroughInput.shrink(object.footprint, by: p.vetoShrink)
      var inside = 0.0
      for segment in candidate.segments {
        inside += Plan2D.clipLenConvex(segment.0, segment.1, footprint)
      }
      if inside > p.objectCross { return nil }
    }
    // A defining object stays with a seed of its type.
    let seedTypes = seeds.map(\.type)
    for object in objects {
      guard let type = object.definingType, seedTypes.contains(type) else { continue }
      let g = pieces.indices.first { Plan2D.contains(pieces[$0], object.center) }
      if !seeds.indices.contains(where: { seeds[$0].type == type && owner[$0] == g }) { return nil }
    }
    var virtualCost = 0.0
    for segment in candidate.segments {
      let length = Plan2D.dist(segment.0, segment.1)
      let deviation = Plan2D.unit(segment.1 - segment.0).map(axes.deviation) ?? 0
      virtualCost += length * (1 + p.axisWeight * max(0, deviation - Plan2D.sin1))
    }
    var nearCost = 0.0
    for seed in seeds {
      var d = Double.infinity
      for segment in candidate.segments {
        d = min(d, Plan2D.segPoint(seed.at, segment.0, segment.1).distance)
      }
      nearCost += p.nearWeight * max(0, p.nearSection - d)
    }
    var objectCost = 0.0
    for object in objects where object.definingType == nil {
      let footprint = WalkthroughInput.shrink(object.footprint, by: p.penaltyShrink)
      var inside = 0.0
      for segment in candidate.segments {
        inside += Plan2D.clipLenConvex(segment.0, segment.1, footprint)
      }
      if inside > p.objectCross {
        objectCost +=
          WalkthroughInput.bigObjects.contains(object.category)
          ? p.objectPenaltyBig : p.objectPenaltySmall
      }
    }
    let score = virtualCost + nearCost + objectCost - p.realBonus * wallLength
    return Check(
      pieces: pieces, owner: owner, virtualLength: virtualTotal, wallLength: wallLength,
      score: score, virtualPerimeter: virtualPerimeter)
  }

  /// True when no seed's piece area differs by more than max(0.25 m2, 2 % of the larger).
  func samePartition(_ a: Check, _ b: Check, seedCount: Int) -> Bool {
    for k in 0..<seedCount {
      let a1 = a.owner[k].map { Plan2D.area(a.pieces[$0]) } ?? 0
      let a2 = b.owner[k].map { Plan2D.area(b.pieces[$0]) } ?? 0
      if abs(a1 - a2)
        > max(parameters.samePartitionAbsolute, parameters.samePartitionRelative * max(a1, a2))
      {
        return false
      }
    }
    return true
  }

  // MARK: Separate and enclose

  /// Splits faces that hold two or more seeds, lowest face first, until every face holds at most
  /// one seed or no valid cut is left.
  func separate(
    _ input: [PlanSegment], seeds: [WalkthroughSeed],
    diagnostics: inout WalkthroughSplitter.Diagnostics
  ) -> (segments: [PlanSegment], arrangement: PlanArrangement) {
    var segments = input
    var stuck: [[Int]] = []
    for _ in 0..<30 {
      let arr = build(segments)
      let byFace = WalkthroughSeeds.byFace(arr, seeds)
      guard
        let target = byFace.indices.first(where: {
          byFace[$0].count >= 2 && !stuck.contains(byFace[$0].map { seeds[$0].id }.sorted())
        })
      else { return (segments, arr) }
      let inside = byFace[target].map { seeds[$0] }
      let key = inside.map(\.id).sorted()
      let hints = faceHints(arr, target)
      var best: (candidate: Candidate, check: Check)?
      var valid: [(order: Int, candidate: Candidate, check: Check)] = []
      for candidate in candidates(arr, target, hints) {
        guard let check = check(arr, target, hints, candidate, seeds: inside) else { continue }
        let groups = Set(check.owner.compactMap { $0 })
        if groups.count < 2 { continue }
        if groups.contains(where: { Plan2D.area(check.pieces[$0]) < parameters.minPiece }) {
          continue
        }
        valid.append((valid.count, candidate, check))
        if best == nil || check.score < best!.check.score - 1e-9 { best = (candidate, check) }
      }
      guard let best else {
        stuck.append(key)
        diagnostics.unsplit.append(inside.map(\.label))
        continue
      }
      let ranked = valid.sorted { ($0.check.score, $0.order) < ($1.check.score, $1.order) }
      let second = ranked.first { !samePartition(best.check, $0.check, seedCount: inside.count) }
      let trial =
        segments + best.candidate.segments.map { PlanSegment(a: $0.0, b: $0.1, kind: .cut) }
      if !build(trial).selfCheck() {
        stuck.append(key)
        diagnostics.unsplit.append(inside.map(\.label))
        continue
      }
      let margin = second.map { $0.check.score - best.check.score }
      diagnostics.cuts.append(
        WalkthroughSplitter.CutDecision(
          seedLabels: inside.map(\.label), tag: best.candidate.tag,
          virtualLengthM: best.check.virtualLength, wallLengthM: best.check.wallLength,
          score: best.check.score, margin: margin,
          approximate: margin.map { $0 < parameters.approximateMargin } ?? false,
          pieceAreasM2: best.check.pieces.map(Plan2D.area)))
      segments = trial
    }
    return (segments, build(segments))
  }

  static let enclosureTags: Set<String> = [
    "stub-extend", "chain-extend", "stub-stub", "stub-extend-to-stub", "chain-extend-to-stub",
  ]

  /// Closes off rooms without a section: in a face with at most one seed, a short closure (at most
  /// `enclose` long) from a wall stub that cuts off a seedless piece of at least `minPiece` whose
  /// boundary is mostly real.
  func enclose(
    _ input: [PlanSegment], seeds: [WalkthroughSeed],
    diagnostics: inout WalkthroughSplitter.Diagnostics
  ) -> (segments: [PlanSegment], arrangement: PlanArrangement) {
    var segments = input
    let p = parameters
    for _ in 0..<20 {
      let arr = build(segments)
      let byFace = WalkthroughSeeds.byFace(arr, seeds)
      var applied = false
      for f in arr.faces.indices {
        let inside = byFace[f].map { seeds[$0] }
        if inside.count >= 2 { continue }
        let hints = faceHints(arr, f)
        var best: (candidate: Candidate, check: Check)?
        for candidate in candidates(arr, f, hints) where Self.enclosureTags.contains(candidate.tag)
        {
          var length = 0.0
          for segment in candidate.segments { length += Plan2D.dist(segment.0, segment.1) }
          if length > p.enclose { continue }
          guard let check = check(arr, f, hints, candidate, seeds: inside) else { continue }
          let areas = check.pieces.map(Plan2D.area)
          guard let g = areas.indices.min(by: { (areas[$0], $0) < (areas[$1], $1) }) else {
            continue
          }
          if check.owner.contains(g) || areas[g] < p.minPiece { continue }
          if check.virtualPerimeter[g] / Plan2D.perimeter(check.pieces[g]) > p.enclosedVirtual {
            continue
          }
          if check.owner.contains(where: { $0.map { areas[$0] < p.minPiece } ?? false }) {
            continue
          }
          if best == nil || check.score < best!.check.score - 1e-9 { best = (candidate, check) }
        }
        guard let best else { continue }
        let trial =
          segments + best.candidate.segments.map { PlanSegment(a: $0.0, b: $0.1, kind: .close) }
        if !build(trial).selfCheck() { continue }
        diagnostics.enclosures.append(
          WalkthroughSplitter.CutDecision(
            seedLabels: inside.map(\.label), tag: best.candidate.tag,
            virtualLengthM: best.check.virtualLength, wallLengthM: best.check.wallLength,
            score: best.check.score, margin: nil, approximate: false,
            pieceAreasM2: best.check.pieces.map(Plan2D.area)))
        segments = trial
        applied = true
        break
      }
      if !applied { return (segments, arr) }
    }
    return (segments, build(segments))
  }
}
