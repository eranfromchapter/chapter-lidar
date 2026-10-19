import CaptureContract

/// A point that must end up in a room of its own: a RoomPlan section, or a kitchen found from its
/// appliances.
struct WalkthroughSeed: Sendable {
  var id: Int
  var label: String
  var at: P2
  /// Position in `RoomPlanRoom.sections`; nil for a kitchen object seed.
  var sectionIndex: Int?
  var story: Int?
  var centerY: Double
  var type: RoomType?

  var isObjectSeed: Bool { sectionIndex == nil }
}

/// Seeds from the sections (section 7 of the phase 3 spec).
enum WalkthroughSeeds {
  /// One seed per section with a centre, in section order:
  /// - a centre outside every face but within `sectionSnap` of the outline (or inside it) moves to
  ///   the nearest face; one farther out is ignored;
  /// - a kitchen, bathroom or bedroom section in a face without its defining objects moves to a
  ///   face within `relocate` that has them and holds no seed;
  /// - when no section is a kitchen, a face with appliances of two or more kinds, at least
  ///   `objectSeedDistance` from the face's seeds, gets a kitchen seed.
  static func make(
    arrangement arr: PlanArrangement, plan: WalkthroughInput.Plan,
    parameters p: WalkthroughSplitter.Parameters, diagnostics: inout WalkthroughSplitter.Diagnostics
  ) -> [WalkthroughSeed] {
    var seeds: [WalkthroughSeed] = []
    for section in plan.sections {
      var at = section.at
      if arr.faceContaining(at) == nil {
        let d = Plan2D.polyDist(plan.outline, at)
        if d > p.sectionSnap, !Plan2D.contains(plan.outline, at) {
          diagnostics.sectionsIgnored.append(section.sectionIndex)
          continue
        }
        var best: (distance: Double, face: Int)?
        for g in arr.faces.indices {
          let dg = Plan2D.polyDist(arr.polygon(g), at)
          if best == nil || dg < best!.distance { best = (dg, g) }
        }
        guard let best else { continue }
        at = nearestInside(arr.polygon(best.face), at)
        diagnostics.sectionsSnapped.append(section.sectionIndex)
      }
      seeds.append(
        WalkthroughSeed(
          id: seeds.count, label: section.label, at: at, sectionIndex: section.sectionIndex,
          story: section.story, centerY: section.centerY, type: section.type))
    }

    for k in seeds.indices {
      guard let type = seeds[k].type, [.kitchen, .bathroom, .bedroom].contains(type),
        let f = arr.faceContaining(seeds[k].at)
      else { continue }
      let own = arr.polygon(f)
      if plan.objects.contains(where: { $0.definingType == type && Plan2D.contains(own, $0.center) }
      ) {
        continue
      }
      var best: (distance: Double, face: Int, objects: [WalkthroughInput.Object])?
      for g in arr.faces.indices where g != f {
        let pg = arr.polygon(g)
        let objects = plan.objects.filter {
          $0.definingType == type && Plan2D.contains(pg, $0.center)
        }
        if objects.isEmpty || seeds.contains(where: { Plan2D.contains(pg, $0.at) }) { continue }
        let d = Plan2D.polyDist(pg, seeds[k].at)
        if d <= p.relocate, best == nil || (d, g) < (best!.distance, best!.face) {
          best = (d, g, objects)
        }
      }
      guard let best else { continue }
      var c = mean(best.objects.map(\.center))
      if !Plan2D.contains(arr.polygon(best.face), c) {
        c = Plan2D.interiorPoint(arr.polygon(best.face))
      }
      seeds[k].at = c
      diagnostics.sectionsRelocated.append(seeds[k].sectionIndex ?? -1)
    }

    if p.kitchenObjectSeeds, !plan.sections.contains(where: { $0.label == "kitchen" }) {
      for f in arr.faces.indices {
        let poly = arr.polygon(f)
        let inside = seeds.filter { Plan2D.contains(poly, $0.at) }
        if inside.isEmpty || inside.contains(where: { $0.type == .kitchen }) { continue }
        let appliances = plan.objects.filter {
          WalkthroughInput.kitchenAppliances.contains($0.category)
            && Plan2D.contains(poly, $0.center)
        }
        if Set(appliances.map(\.category)).count < 2 { continue }
        let c = mean(appliances.map(\.center))
        if Plan2D.contains(poly, c),
          inside.allSatisfy({ Plan2D.dist(c, $0.at) >= p.objectSeedDistance })
        {
          seeds.append(
            WalkthroughSeed(
              id: seeds.count, label: "object:kitchen", at: c, sectionIndex: nil, story: nil,
              centerY: plan.floorY, type: .kitchen))
          diagnostics.objectSeeds += 1
        }
      }
    }
    return seeds
  }

  /// Seed indexes per face: each seed goes to the first face that contains it, otherwise to the
  /// nearest face.
  static func byFace(_ arr: PlanArrangement, _ seeds: [WalkthroughSeed]) -> [[Int]] {
    var result = [[Int]](repeating: [], count: arr.faces.count)
    guard !arr.faces.isEmpty else { return result }
    for (k, seed) in seeds.enumerated() {
      result[arr.faceNearest(seed.at)].append(k)
    }
    return result
  }

  /// A point inside `poly` near `p`: its projection on the nearest ring edge (kept off the edge's
  /// ends) moved 5 cm inward, or else a point well inside.
  static func nearestInside(_ poly: [P2], _ p: P2, inset: Double = 0.05) -> P2 {
    let n = poly.count
    var best: (distance: Double, edge: Int, t: Double)?
    for i in 0..<n {
      let (d, t) = Plan2D.segPoint(p, poly[i], poly[(i + 1) % n])
      if best == nil || d < best!.distance - 1e-12 { best = (d, i, t) }
    }
    guard let best else { return p }
    let a = poly[best.edge]
    let b = poly[(best.edge + 1) % n]
    var q = a + (b - a) * min(0.9, max(0.1, best.t))
    if let e = Plan2D.unit(b - a) { q = q + P2(-e.y, e.x) * inset }
    return Plan2D.contains(poly, q) ? q : Plan2D.interiorPoint(poly)
  }

  static func mean(_ points: [P2]) -> P2 {
    var x = 0.0
    var y = 0.0
    for p in points {
      x += p.x
      y += p.y
    }
    return P2(x, y) * (1.0 / Double(points.count))
  }
}
