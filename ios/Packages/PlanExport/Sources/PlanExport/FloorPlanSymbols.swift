import CaptureContract
import Foundation

/// A furniture, fixture or appliance symbol drawn inside an object's oriented footprint.
struct PlacedSymbol: Sendable {
  var objectId: String
  var category: ObjectCategory
  /// What was drawn, for example `bed` or `armchair`.
  var kind: String
  /// Footprint corners, counter-clockwise, plan metres.
  var footprint: [Point2]
  /// Unit vector from the centre towards the symbol's back (the nearest wall).
  var back: Point2
  /// The outline (dashed when the detection had low confidence).
  var outline: PathBuilder
  /// Inner detail lines.
  var details: PathBuilder
  var lowConfidence: Bool
}

/// Plan symbols in the footprint of each recognized object, built in a local frame: x across
/// the object, y from front (-) to back (+), the back being the side nearest a wall (a bed's
/// head, a sofa's back, a toilet's tank, the wall side of a cabinet). Every line stays inside
/// the footprint.
enum FloorPlanSymbols {
  /// RoomPlan attribute names and values that refine a category.
  enum Attribute {
    static let sofaType = "SofaType"
    static let chairType = "ChairType"
    static let chairArm = "ChairArmType"
    static let tableShape = "TableShapeType"
    static let tableType = "TableType"
    static let storageType = "StorageType"
  }

  /// `lines`: room edges and walls, to find each object's back. `tables`: table footprints,
  /// so a chair at a table turns its back to the table.
  static func symbol(
    for object: PlanObject, attributes: [String: String], lines: [(Point2, Point2)],
    tables: [PlanObject]
  ) -> PlacedSymbol? {
    guard object.corners.count == 4 else { return nil }
    let c = object.center
    let ex = (object.corners[3] - object.corners[0]) * 0.5
    let ez = (object.corners[1] - object.corners[0]) * 0.5
    guard max(ex.length, ez.length) >= 0.05 else { return nil }
    let kind = kind(of: object, attributes: attributes)

    // Candidate backs: the four sides, as the unit direction out of the side, half the side's
    // length and the distance from the centre.
    var sides: [(out: Point2, along: Double, depth: Double)] = []
    for (axis, other) in [(ex, ez), (ez, ex), (ex * -1, ez), (ez * -1, ex)]
    where axis.length > 1e-6 {
      sides.append((axis.unit, other.length, axis.length))
    }
    let longAxisSides = sides.filter { $0.depth >= $0.along - 1e-9 }
    let shortAxisSides = sides.filter { $0.depth <= $0.along + 1e-9 }
    let allowed: [(out: Point2, along: Double, depth: Double)]
    switch kind {
    case "bed", "toilet", "bathtub":
      // Head, tank or taps on a short side.
      allowed = longAxisSides
    case "sofa", "television", "shelf", "cabinet":
      allowed = shortAxisSides
    default:
      allowed = sides
    }

    func wallDistance(_ side: (out: Point2, along: Double, depth: Double)) -> Double {
      let middle = c + side.out * side.depth
      var best = Double.infinity
      for (a, b) in lines where a.distance(to: b) > 0.05 {
        let direction = (b - a).unit
        guard abs(direction.dot(side.out)) < 0.5 else { continue }
        best = min(best, Geo.segmentDistance(middle, a, b).distance)
      }
      return best
    }
    var chosen = allowed.first ?? sides[0]
    if kind == "chair" || kind == "armchair",
      let table = tables.min(by: { $0.center.distance(to: c) < $1.center.distance(to: c) }),
      table.center.distance(to: c) < 1.3
    {
      // Back to the table it stands at.
      let away = (c - table.center).unit
      chosen = allowed.max { $0.out.dot(away) < $1.out.dot(away) } ?? chosen
    } else {
      var bestDistance = Double.infinity
      for side in allowed {
        let distance = wallDistance(side)
        if distance < bestDistance - 1e-9 {
          bestDistance = distance
          chosen = side
        }
      }
    }

    let v = chosen.out
    let u = v.rightNormal
    let frame = DrawingFrame(origin: c, u: u, v: v)
    let h = chosen.along
    let k = chosen.depth
    var outline = PathBuilder()
    var details = PathBuilder()
    draw(kind: kind, h: h, k: k, frame: frame, outline: &outline, details: &details)
    let footprint = Geo.counterClockwise([
      frame.map(-h, -k), frame.map(h, -k), frame.map(h, k), frame.map(-h, k),
    ])
    return PlacedSymbol(
      objectId: object.id, category: object.category, kind: kind, footprint: footprint, back: v,
      outline: outline, details: details, lowConfidence: object.confidence == .low)
  }

  /// The symbol drawn for an object: its category, refined by attributes.
  static func kind(of object: PlanObject, attributes: [String: String]) -> String {
    let value = { (name: String) in attributes[name]?.lowercased() ?? "" }
    switch object.category {
    case .bathtub: return "bathtub"
    case .bed: return "bed"
    case .chair:
      if value(Attribute.chairArm) == "existing" { return "armchair" }
      if ["stool", "swivel"].contains(value(Attribute.chairType)) { return "stool" }
      return "chair"
    case .dishwasher: return "dishwasher"
    case .fireplace: return "fireplace"
    case .oven: return "oven"
    case .refrigerator: return "refrigerator"
    case .sink: return "sink"
    case .sofa:
      return value(Attribute.sofaType).contains("single") ? "armchair" : "sofa"
    case .stairs: return "stairs"
    case .storage: return value(Attribute.storageType) == "shelf" ? "shelf" : "cabinet"
    case .stove: return "stove"
    case .table:
      if ["circularelliptic", "circular", "elliptical", "round"].contains(
        value(Attribute.tableShape))
      {
        return "round-table"
      }
      if value(Attribute.tableType) == "desk" { return "desk" }
      return "table"
    case .television: return "television"
    case .toilet: return "toilet"
    case .washerDryer: return "washer-dryer"
    case .other: return "other"
    }
  }

  private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    max(low, min(high, value))
  }

  private static func draw(
    kind: String, h: Double, k: Double, frame f: DrawingFrame, outline: inout PathBuilder,
    details d: inout PathBuilder
  ) {
    let w = 2 * h
    let depth = 2 * k
    let small = min(w, depth)
    switch kind {
    case "bed":
      outline.rect(in: f, -h, -k, h, k, radius: 0.02)
      let head = clamp(depth * 0.05, 0.03, 0.08)
      d.rect(in: f, -h, k - head, h, k)
      let m = clamp(w * 0.03, 0.01, 0.04)
      d.rect(in: f, -h + m, -k + m, h - m, k - head, radius: 0.05)
      let count = w >= 1.15 ? 2 : 1
      let gap = clamp(w * 0.04, 0.02, 0.06)
      let pillowDepth = clamp(depth * 0.16, 0.1, 0.38)
      let top = k - head - gap
      let pillowWidth = (w - 2 * m - Double(count + 1) * gap) / Double(count)
      if pillowWidth > 0.05, top - pillowDepth > -k + m {
        for i in 0..<count {
          let x0 = -h + m + gap + Double(i) * (pillowWidth + gap)
          d.rect(in: f, x0, top - pillowDepth, x0 + pillowWidth, top, radius: 0.05)
        }
      }
      // Duvet turned down below the pillows, with its folded corner.
      let fold = top - pillowDepth - clamp(depth * 0.06, 0.04, 0.14)
      if fold > -k + m + 0.05 {
        d.segment(f.map(-h + m, fold), f.map(h - m, fold))
        let corner = min(0.25 * w, fold - (-k + m), 0.35)
        d.polyline([
          f.map(h - m - corner, fold), f.map(h - m, fold - corner),
        ])
      }
    case "sofa", "armchair":
      outline.rect(in: f, -h, -k, h, k, radius: 0.03)
      let back = clamp(depth * 0.22, 0.08, 0.25)
      let arm = clamp(w * (kind == "armchair" ? 0.16 : 0.08), 0.06, 0.22)
      d.rect(in: f, -h, k - back, h, k, radius: 0.03)
      d.rect(in: f, -h, -k, -h + arm, k - back, radius: 0.03)
      d.rect(in: f, h - arm, -k, h, k - back, radius: 0.03)
      let seat = w - 2 * arm
      let count = kind == "armchair" ? 1 : (seat > 1.9 ? 3 : (seat > 1.0 ? 2 : 1))
      let gap = 0.01
      let cushion = (seat - Double(count + 1) * gap) / Double(count)
      if cushion > 0.05 {
        for i in 0..<count {
          let x0 = -h + arm + gap + Double(i) * (cushion + gap)
          d.rect(in: f, x0, -k + gap, x0 + cushion, k - back - gap, radius: 0.04)
        }
      }
    case "chair":
      let back = clamp(depth * 0.15, 0.03, 0.09)
      outline.rect(in: f, -h, -k, h, k, radius: 0.03)
      d.rect(in: f, -h, k - back, h, k, radius: 0.02)
      let m = clamp(small * 0.06, 0.01, 0.03)
      if 2 * k - back - 2 * m > 0.05 {
        d.rect(in: f, -h + m, -k + m, h - m, k - back - m, radius: 0.04)
      }
    case "stool":
      outline.ellipse(in: f, cx: 0, cy: 0, rx: h, ry: k)
      d.ellipse(in: f, cx: 0, cy: 0, rx: h * 0.7, ry: k * 0.7)
    case "round-table":
      outline.ellipse(in: f, cx: 0, cy: 0, rx: h, ry: k)
    case "table":
      outline.rect(in: f, -h, -k, h, k, radius: 0.01)
    case "desk":
      outline.rect(in: f, -h, -k, h, k)
      let m = clamp(small * 0.04, 0.01, 0.03)
      d.rect(in: f, -h + m, -k + m, h - m, k - m)
    case "cabinet":
      outline.rect(in: f, -h, -k, h, k)
      let front = clamp(depth * 0.1, 0.015, 0.05)
      d.segment(f.map(-h, -k + front), f.map(h, -k + front))
      let doors = max(1, Int((w / 0.45).rounded()))
      let doorWidth = w / Double(doors)
      for i in 1..<max(1, doors) {
        let x = -h + Double(i) * doorWidth
        d.segment(f.map(x, -k), f.map(x, -k + front))
      }
      let knob = min(0.012, front * 0.4, doorWidth * 0.1)
      if knob > 0.003, depth > 2 * front + 2 * knob {
        for i in 0..<doors {
          d.circle(
            center: f.map(-h + (Double(i) + 0.5) * doorWidth, -k + front + knob * 2.2),
            radius: knob)
        }
      }
    case "shelf":
      outline.rect(in: f, -h, -k, h, k)
      d.segment(f.map(-h, 0), f.map(h, 0))
    case "toilet":
      let tank = clamp(depth * 0.28, 0.06, 0.22)
      let bowlDepth = depth - tank
      let rx = h * 0.82
      let ry = bowlDepth / 2
      outline.rect(in: f, -h, k - tank, h, k, radius: 0.02)
      d.ellipse(in: f, cx: 0, cy: -k + ry, rx: rx, ry: ry)
      d.ellipse(in: f, cx: 0, cy: -k + ry * 0.92, rx: rx * 0.66, ry: ry * 0.7)
    case "bathtub":
      outline.rect(in: f, -h, -k, h, k, radius: 0.04)
      let m = clamp(small * 0.1, 0.03, 0.1)
      d.rect(in: f, -h + m, -k + m, h - m, k - m, radius: min(0.15, small * 0.2))
      let r = min(0.025, small * 0.05)
      d.circle(center: f.map(0, k - m - r * 3), radius: r)
      d.circle(center: f.map(0, k - m / 2), radius: min(r * 0.6, m * 0.4))
    case "sink":
      outline.rect(in: f, -h, -k, h, k, radius: 0.01)
      let side = clamp(w * 0.08, 0.02, 0.06)
      let tap = clamp(depth * 0.2, 0.03, 0.1)
      let basins = w > 1.1 ? 2 : 1
      let gap = side
      let basinWidth = (w - Double(basins + 1) * gap) / Double(basins)
      let y0 = -k + side
      let y1 = k - tap
      if basinWidth > 0.05, y1 - y0 > 0.05 {
        for i in 0..<basins {
          let x0 = -h + gap + Double(i) * (basinWidth + gap)
          d.rect(in: f, x0, y0, x0 + basinWidth, y1, radius: min(0.07, basinWidth * 0.3))
          d.circle(
            center: f.map(x0 + basinWidth / 2, (y0 + y1) / 2), radius: min(0.015, basinWidth * 0.1))
          d.circle(
            center: f.map(x0 + basinWidth / 2, k - tap / 2), radius: min(0.018, tap * 0.35))
        }
      }
    case "stove":
      outline.rect(in: f, -h, -k, h, k)
      let front = clamp(depth * 0.06, 0.01, 0.04)
      d.segment(f.map(-h, -k + front), f.map(h, -k + front))
      let usable = depth - front
      let r = min(w, usable) * 0.17
      for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
        let center = f.map(sx * w / 4, -k + front + usable / 2 + sy * usable / 4)
        d.circle(center: center, radius: r)
        d.circle(center: center, radius: r * 0.45)
      }
    case "oven":
      outline.rect(in: f, -h, -k, h, k)
      let m = clamp(small * 0.12, 0.02, 0.08)
      d.rect(in: f, -h + m, -k + m, h - m, k - m, radius: 0.02)
      d.segment(f.map(-h * 0.6, -k + m / 2), f.map(h * 0.6, -k + m / 2))
    case "refrigerator":
      outline.rect(in: f, -h, -k, h, k)
      let door = clamp(depth * 0.1, 0.02, 0.07)
      d.segment(f.map(-h, -k + door), f.map(h, -k + door))
      if w > 0.78 { d.segment(f.map(0, -k), f.map(0, -k + door)) }
    case "dishwasher":
      outline.rect(in: f, -h, -k, h, k)
      let front = clamp(depth * 0.08, 0.015, 0.05)
      d.segment(f.map(-h, -k + front), f.map(h, -k + front))
      d.segment(f.map(-h * 0.5, -k + front / 2), f.map(h * 0.5, -k + front / 2))
    case "washer-dryer":
      outline.rect(in: f, -h, -k, h, k, radius: 0.02)
      let front = clamp(depth * 0.1, 0.02, 0.06)
      d.segment(f.map(-h, -k + front), f.map(h, -k + front))
      let r = min(w, depth - front) * 0.33
      d.circle(center: f.map(0, -k + front + (depth - front) / 2), radius: r)
    case "television":
      let screen = min(depth, 0.06)
      outline.rect(in: f, -h, k - screen, h, k, radius: min(0.01, screen / 3))
      let stand = min(0.08, depth - screen)
      if stand > 0.01 {
        d.rect(in: f, -h * 0.3, k - screen - stand, h * 0.3, k - screen)
      }
    case "fireplace":
      outline.rect(in: f, -h, -k, h, k)
      let hearth = clamp(depth * 0.3, 0.05, 0.45)
      d.segment(f.map(-h, -k + hearth), f.map(h, -k + hearth))
      let wall = clamp(depth * 0.12, 0.02, 0.12)
      if k - wall > -k + hearth + 0.02 {
        d.polygon([
          f.map(-h * 0.7, -k + hearth), f.map(h * 0.7, -k + hearth), f.map(h * 0.45, k - wall),
          f.map(-h * 0.45, k - wall),
        ])
      }
    case "stairs":
      // Treads across the run, along the longer side, with an arrow up the middle.
      outline.rect(in: f, -h, -k, h, k)
      let alongY = k >= h
      let run = alongY ? depth : w
      let width = alongY ? w : depth
      let steps = max(2, Int((run / 0.26).rounded()))
      for i in 1..<steps {
        let s = -run / 2 + run * Double(i) / Double(steps)
        if alongY {
          d.segment(f.map(-h, s), f.map(h, s))
        } else {
          d.segment(f.map(s, -k), f.map(s, k))
        }
      }
      let tip = run / 2 - min(0.1, run * 0.05)
      let head = min(width * 0.25, 0.15, run * 0.2)
      func p(_ along: Double, _ across: Double) -> Point2 {
        alongY ? f.map(across, along) : f.map(along, across)
      }
      d.segment(p(-tip, 0), p(tip, 0))
      d.polyline([p(tip - head, -head * 0.6), p(tip, 0), p(tip - head, head * 0.6)])
    default:
      outline.rect(in: f, -h, -k, h, k)
    }
  }
}
