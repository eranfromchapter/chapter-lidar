import CaptureContract
import Foundation

/// A label on the drawing and the box it covers, for overlap checks. Plan metres.
struct PlacedLabel: Sendable {
  enum Kind: Sendable {
    case room
    case exteriorDimension
    case interiorDimension
    case scaleBar
    case compass
  }

  var kind: Kind
  var text: String
  /// The box of the text (the room name and area together for a room label).
  var box: OrientedBox
  var roomId: String?
  let extent: Extent

  init(kind: Kind, text: String, box: OrientedBox, roomId: String?) {
    self.kind = kind
    self.text = text
    self.box = box
    self.roomId = roomId
    extent = box.extent
  }
}

/// Something a label must keep clear of: a convex outline or, for the building, any outline.
struct Obstacle: Sendable {
  var polygon: [Point2]
  var extent: Extent

  init(_ polygon: [Point2]) {
    self.polygon = polygon
    extent = Extent(polygon)
  }

  init(line a: Point2, _ b: Point2, halfWidth: Double) {
    self.init(OrientedBox.around(a, b, halfWidth: halfWidth).corners)
  }
}

/// The dimension of one outer wall segment.
struct ExteriorDimension: Sendable {
  var loop: Int
  var run: Int
  /// Along the outside face, corner to corner.
  var lengthM: Double
  var label: String
  /// 1 for the row nearest the wall.
  var tier: Int
  /// Where the label went: on the line, beside it, or past an end (with a leader).
  var placement: String
  /// True when no free place was found and the label was put where it overlaps least.
  var crowded: Bool
  /// How badly that place overlaps (see `AnnotationLayout.conflicts`); 0 when free.
  var conflictScore: Int
}

/// Lays out the text and dimension strings of the floor plan drawing so that no label
/// overlaps another label, a symbol or a wall. Sizes are given in paper millimetres and
/// converted with `metresPerPaperMM` (the scale denominator / 1000).
struct AnnotationLayout {
  let style: FloorPlanStyle
  let units: UnitFormatter
  /// Plan metres per paper millimetre.
  let k: Double
  var labels: [PlacedLabel] = []
  /// Dimension lines, leaders, witness lines and door swings, as thin boxes.
  var lines: [Obstacle] = []
  var symbols: [Obstacle]
  /// Outside faces of the closed exterior wall loops; labels outside stay off the building.
  var building: [Obstacle]
  var wallPieces: [Obstacle]
  var items: [DrawingLayer: [DrawingItem]] = [:]
  var exteriorDimensions: [ExteriorDimension] = []
  var droppedInteriorDimensions = 0

  init(
    style: FloorPlanStyle, units: UnitFormatter, scaleDenominator: Double,
    symbols: [[Point2]], building: [[Point2]], wallPieces: [[Point2]],
    lines: [(Point2, Point2)] = []
  ) {
    self.style = style
    self.units = units
    self.k = scaleDenominator / 1000
    self.symbols = symbols.map(Obstacle.init)
    self.building = building.map(Obstacle.init)
    self.wallPieces = wallPieces.map(Obstacle.init)
    self.lines = lines.map { Obstacle(line: $0.0, $0.1, halfWidth: style.lineClearance * k) }
  }

  private mutating func add(_ item: DrawingItem, _ layer: DrawingLayer) {
    items[layer, default: []].append(item)
  }

  // MARK: Text boxes

  /// Box of one line of text centred at `center` (see `centredText`), reading along `u`: from
  /// the descender (0.22 em below the baseline) to the cap height (0.75 em above it), the same
  /// box `FloorPlanDrawing.textCorners` gives the drawn text.
  func textBox(_ text: String, center: Point2, u: Point2, size: Double, bold: Bool = false)
    -> OrientedBox
  {
    let width = FontMetrics.width(text, size: size, bold: bold)
    return OrientedBox(
      center: center - u.leftNormal * (0.095 * size), u: u, halfWidth: width / 2,
      halfHeight: size * 0.485)
  }

  /// Text item centred (both ways) on `center`.
  func centredText(
    _ text: String, center: Point2, u: Point2, size: Double, color: DrawingColor,
    layer: DrawingLayer, bold: Bool = false
  ) -> DrawingItem {
    let baseline = center - u.leftNormal * (size * 0.36)
    let angle = atan2(u.y, u.x) * 180 / .pi
    return .text(
      DrawingText(
        Format.singleLine(text), position: PathBuilder.mm(baseline), size: size * 1000,
        rotationDegrees: abs(angle) < 1e-9 ? 0 : angle, anchor: .center, bold: bold,
        color: color, layer: layer))
  }

  /// Reading direction for text along `direction`: left to right, or bottom to top.
  static func readingDirection(_ direction: Point2) -> Point2 {
    var u = direction.unit
    if u.x < -1e-9 || (abs(u.x) <= 1e-9 && u.y < 0) { u = u * -1 }
    return u
  }

  /// How badly a candidate label box (and its own dimension lines) runs into things; 0 when it
  /// is free. Covering text, a wall or the building weighs most, a symbol less, and crossing a
  /// line least, so a crowded label goes where it hides the least.
  func conflicts(
    _ box: OrientedBox, padding: Double, outside: Bool, ownLines: [OrientedBox] = []
  ) -> Int {
    var score = 0
    var padded = box
    padded.halfWidth += padding
    padded.halfHeight += padding
    let corners = padded.corners
    let extent = Extent(corners)
    for label in labels where label.extent.overlaps(extent) && label.box.overlaps(padded) {
      score += 100
    }
    for wall in wallPieces
    where wall.extent.overlaps(extent) && Geo.convexOverlap(corners, wall.polygon) {
      score += 100
    }
    for symbol in symbols
    where symbol.extent.overlaps(extent) && Geo.convexOverlap(corners, symbol.polygon) {
      score += 30
    }
    for line in lines
    where line.extent.overlaps(extent) && Geo.convexOverlap(corners, line.polygon) {
      score += 3
    }
    if outside {
      for face in building
      where face.extent.overlaps(extent) && Geo.polygonsOverlap(corners, face.polygon) {
        score += 100
      }
    }
    // The candidate's own lines must not cross labels already placed, nor run into the
    // building (ending on its face is fine).
    for line in ownLines {
      let lineCorners = line.corners
      let lineExtent = Extent(lineCorners)
      for label in labels
      where label.extent.overlaps(lineExtent) && label.box.overlaps(convex: lineCorners) {
        score += 10
      }
      if outside, line.halfWidth > 0.02 * k {
        var inner = line
        inner.halfWidth -= 0.02 * k
        inner.halfHeight = 1e-9
        let innerCorners = inner.corners
        for face in building
        where face.extent.overlaps(lineExtent)
          && Geo.polygonsOverlap(innerCorners, face.polygon)
        {
          score += 10
        }
      }
    }
    return score
  }

  // MARK: Room labels

  /// Puts the room's name and area at the point of the room farthest from its walls and from
  /// the furniture (pole of inaccessibility), searching a grid and refining around the best.
  mutating func placeRoomLabel(
    roomId: String, name: String?, area: String?, polygon: [Point2]
  ) {
    var block: [(text: String, size: Double)] = []
    if let name, !name.isEmpty { block.append((name, style.roomNameSize * k)) }
    if let area, !area.isEmpty { block.append((area, style.roomAreaSize * k)) }
    guard !block.isEmpty, polygon.count >= 3 else { return }
    // Each line spans its glyph box, descender to cap height (0.97 em).
    let lineGap = 0.15 * style.roomNameSize * k
    let height = block.map(\.size).reduce(0, +) * 0.97 + lineGap * Double(block.count - 1)
    let halfWidth = (block.map { FontMetrics.width($0.text, size: $0.size) }.max() ?? 0) / 2
    let u = Point2(x: 1, y: 0)
    func box(at c: Point2) -> OrientedBox {
      OrientedBox(center: c, u: u, halfWidth: halfWidth, halfHeight: height / 2)
    }
    let padding = 0.6 * k
    // Score: what the label box covers (other labels, door swings and dimension lines,
    // furniture), then its clearance from the room's walls and the furniture.
    func score(_ c: Point2) -> (cost: Int, value: Double)? {
      var b = box(at: c)
      b.halfWidth += padding
      b.halfHeight += padding
      guard b.isInside(polygon) else { return nil }
      var clearance = Double.infinity
      let corners = b.corners
      for p in corners + [c] {
        clearance = min(clearance, PlanGeometry.distanceToBoundary(of: polygon, from: p))
      }
      var cost = 0
      let extent = Extent(corners)
      for symbol in symbols {
        if symbol.extent.overlaps(extent), Geo.convexOverlap(corners, symbol.polygon) {
          cost += 2
          continue
        }
        for p in corners {
          clearance = min(
            clearance, PlanGeometry.distanceToBoundary(of: symbol.polygon, from: p))
        }
      }
      for label in labels where label.extent.overlaps(extent) && label.box.overlaps(b) {
        cost += 100
      }
      for line in lines
      where line.extent.overlaps(extent) && Geo.convexOverlap(corners, line.polygon) {
        cost += 3
      }
      return (cost, clearance)
    }
    let xs = polygon.map(\.x)
    let ys = polygon.map(\.y)
    var lo = Point2(x: xs.min()!, y: ys.min()!)
    var hi = Point2(x: xs.max()!, y: ys.max()!)
    var best: (point: Point2, cost: Int, value: Double)?
    let fallback = PlanGeometry.labelPoint(of: polygon)
    for round in 0..<4 {
      let n = round == 0 ? 28 : 10
      for i in 0...n {
        for j in 0...n {
          let p = Point2(
            x: lo.x + (hi.x - lo.x) * Double(i) / Double(n),
            y: lo.y + (hi.y - lo.y) * Double(j) / Double(n))
          guard let s = score(p) else { continue }
          let better: Bool
          if let current = best {
            better =
              s.cost < current.cost || (s.cost == current.cost && s.value > current.value + 1e-9)
          } else {
            better = true
          }
          if better { best = (p, s.cost, s.value) }
        }
      }
      guard let current = best else { break }
      let spanX = (hi.x - lo.x) / Double(n)
      let spanY = (hi.y - lo.y) / Double(n)
      lo = Point2(x: current.point.x - spanX, y: current.point.y - spanY)
      hi = Point2(x: current.point.x + spanX, y: current.point.y + spanY)
    }
    let center = best?.point ?? fallback
    // Lines from the top: the name, then the area.
    var top = center.y + height / 2
    for line in block {
      let baseline = top - line.size * 0.75
      let lineCenter = Point2(x: center.x, y: baseline + line.size * 0.36)
      add(
        centredText(
          line.text, center: lineCenter, u: u, size: line.size, color: style.ink,
          layer: .roomLabel),
        .roomLabel)
      top -= line.size * 0.97 + lineGap
    }
    labels.append(
      PlacedLabel(
        kind: .room, text: block.map(\.text).joined(separator: "\n"), box: box(at: center),
        roomId: roomId))
  }

  // MARK: Exterior dimensions

  /// One dimension per outer wall segment, outside the building, measured along the outside
  /// face from corner to corner. A label that does not fit goes beside its line or past one of
  /// its ends with a leader, on the first row (tier) where it is free; none is ever dropped.
  mutating func placeExteriorDimensions(walls: WallLayout) {
    // Segments in outline order, reversed, shortest first and longest first: the first order
    // that places every label freely wins, else the one that overlaps least.
    var natural: [(loop: Int, run: Int, segment: Int)] = []
    for (loopIndex, loop) in walls.loops.enumerated() {
      for (runIndex, segmentIndex) in loop.segments.enumerated() {
        natural.append((loopIndex, runIndex, segmentIndex))
      }
    }
    func length(_ entry: (loop: Int, run: Int, segment: Int)) -> Double {
      walls.segments[entry.segment].startLo.distance(to: walls.segments[entry.segment].endLo)
    }
    let ascending = natural.indices.sorted {
      let l0 = length(natural[$0])
      let l1 = length(natural[$1])
      return l0 < l1 - 1e-9 || (abs(l0 - l1) <= 1e-9 && $0 < $1)
    }.map { natural[$0] }
    var best: AnnotationLayout?
    var bestScore = Int.max
    var orders = [natural, natural.reversed(), ascending, ascending.reversed()]
    var tried = 0
    while tried < orders.count && tried < 8 {
      let order = orders[tried]
      tried += 1
      var trial = self
      trial.placeExteriorDimensions(walls: walls, order: order)
      let score = trial.exteriorDimensions.map(\.conflictScore).reduce(0, +)
      if score < bestScore {
        best = trial
        bestScore = score
      }
      if score == 0 { break }
      // Repair: the crowded ones choose first next time.
      let crowded = trial.exteriorDimensions.filter(\.crowded).map { ($0.loop, $0.run) }
      let first = order.filter { entry in crowded.contains { $0 == (entry.loop, entry.run) } }
      let rest = order.filter { entry in !crowded.contains { $0 == (entry.loop, entry.run) } }
      orders.append(first + rest)
    }
    if let best { self = best }
  }

  private mutating func placeExteriorDimensions(
    walls: WallLayout, order: [(loop: Int, run: Int, segment: Int)]
  ) {
    let size = style.exteriorDimensionSize * k
    let gap = style.labelGap * k
    do {
      for (loopIndex, runIndex, segmentIndex) in order {
        let segment = walls.segments[segmentIndex]
        let d = segment.direction
        let out = segment.normal * -1
        let p0 = segment.startLo
        let p1 = segment.endLo
        let along = (p1 - p0).dot(d)
        guard along > 0.01 else { continue }
        let label = units.length(along)
        let width = FontMetrics.width(label, size: size)
        let u = AnnotationLayout.readingDirection(d)

        struct Candidate {
          var tier: Int
          var placement: String
          var center: Point2
          var lines: [(Point2, Point2)]
        }
        var candidates: [Candidate] = []
        for tier in 1...style.exteriorTiers {
          let offset = (style.exteriorOffset + Double(tier - 1) * style.exteriorTierStep) * k
          let a = p0 + out * offset
          let b = p1 + out * offset
          let middle = (a + b) * 0.5
          // Witness lines: short brackets on the first row, down to the wall beyond it.
          let reach = tier == 1 ? min(style.tickLength * k, offset - gap) : offset - gap
          // At an inside corner a witness would run along the next wall's face: left out.
          let witnesses = [(a, a - out * reach), (b, b - out * reach)].filter { line in
            let middle = (line.0 + line.1) * 0.5
            return !building.contains {
              PlanGeometry.distanceToBoundary(of: $0.polygon, from: middle) < 0.05 * k
            }
          }
          let stub = style.minimumStub * k
          if width + 2 * gap + 2 * stub <= along {
            let cutA = middle - d * (width / 2 + gap)
            let cutB = middle + d * (width / 2 + gap)
            candidates.append(
              Candidate(
                tier: tier, placement: "line", center: middle,
                lines: [(a, cutA), (cutB, b)] + witnesses))
          }
          let besideCenter = middle + out * (size * 0.6 + gap)
          candidates.append(
            Candidate(
              tier: tier, placement: "beside", center: besideCenter,
              lines: [(a, b)] + witnesses))
          // Past an end, on the line carried on as a leader; further out when crowded.
          for reachOut in [0.0, 3.0, 6.0] {
            for (end, sign, name) in [(b, 1.0, "past-end"), (a, -1.0, "past-start")] {
              let leader = gap + reachOut * k
              let center = end + d * (sign * (leader + gap + width / 2))
              candidates.append(
                Candidate(
                  tier: tier, placement: name, center: center,
                  lines: [(a, b), (end, end + d * (sign * leader))] + witnesses))
            }
          }
        }
        var chosen: (candidate: Candidate, conflicts: Int)?
        for candidate in candidates {
          let box = textBox(label, center: candidate.center, u: u, size: size)
          let own = candidate.lines.map {
            OrientedBox.around($0.0, $0.1, halfWidth: style.lineClearance * k)
          }
          let count = conflicts(
            box, padding: style.labelPadding * k, outside: true, ownLines: own)
          if chosen == nil || count < chosen!.conflicts { chosen = (candidate, count) }
          if count == 0 { break }
        }
        guard let pick = chosen?.candidate else { continue }
        let stroke = DrawingStroke(
          color: style.ink, width: style.exteriorDimensionWidth * k * 1000)
        var path = PathBuilder()
        for (a, b) in pick.lines where a.distance(to: b) > 1e-6 { path.segment(a, b) }
        add(
          .shape(DrawingShape(path: path.path, stroke: stroke, layer: .exteriorDimension)),
          .exteriorDimension)
        add(
          centredText(
            label, center: pick.center, u: u, size: size, color: style.ink,
            layer: .exteriorDimension), .exteriorDimension)
        labels.append(
          PlacedLabel(
            kind: .exteriorDimension, text: label,
            box: textBox(label, center: pick.center, u: u, size: size), roomId: nil))
        for (a, b) in pick.lines where a.distance(to: b) > 1e-6 {
          lines.append(Obstacle(line: a, b, halfWidth: style.lineClearance * k))
        }
        exteriorDimensions.append(
          ExteriorDimension(
            loop: loopIndex, run: runIndex, lengthM: along, label: label, tier: pick.tier,
            placement: pick.placement, crowded: (chosen?.conflicts ?? 0) > 0,
            conflictScore: chosen?.conflicts ?? 0))
      }
    }
  }

  // MARK: Interior dimensions

  /// One dimension along each edge of each room, just inside it, measured between the wall
  /// faces. Longest edges first; a label that finds no free place along or beside its line is
  /// left out together with its line.
  mutating func placeInteriorDimensions(rooms: [(id: String, clear: [Point2])]) {
    let size = style.interiorDimensionSize * k
    let gap = style.labelGap * k
    var edges: [(room: Int, a: Point2, b: Point2)] = []
    for (index, room) in rooms.enumerated() {
      let polygon = room.clear
      for i in polygon.indices {
        let a = polygon[i]
        let b = polygon[(i + 1) % polygon.count]
        if a.distance(to: b) >= style.interiorMinimumM { edges.append((index, a, b)) }
      }
    }
    let order = edges.indices.sorted {
      let l0 = edges[$0].a.distance(to: edges[$0].b)
      let l1 = edges[$1].a.distance(to: edges[$1].b)
      return l0 > l1 + 1e-9 || (abs(l0 - l1) <= 1e-9 && $0 < $1)
    }
    for index in order {
      let edge = edges[index]
      let polygon = rooms[edge.room].clear
      let length = edge.a.distance(to: edge.b)
      let d = (edge.b - edge.a).unit
      let inward = d.leftNormal
      let label = units.length(length)
      let width = FontMetrics.width(label, size: size)
      let u = AnnotationLayout.readingDirection(d)
      let stub = style.minimumStub * k
      var placed = false
      tiers: for tier in 0..<2 {
        let offset = (style.interiorOffset + Double(tier) * style.interiorTierStep) * k
        let a = edge.a + inward * offset
        let b = edge.b + inward * offset
        let ticks = [(a, edge.a + inward * (gap * 0.5)), (b, edge.b + inward * (gap * 0.5))]
        var options: [(center: Point2, lines: [(Point2, Point2)])] = []
        for t in [0.5, 0.36, 0.64, 0.24, 0.76] {
          let center = a + (b - a) * t
          let before = t * length - width / 2 - gap
          let after = (1 - t) * length - width / 2 - gap
          guard before >= stub, after >= stub else { continue }
          let cutA = center - d * (width / 2 + gap)
          let cutB = center + d * (width / 2 + gap)
          options.append((center, [(a, cutA), (cutB, b)] + ticks))
        }
        options.append(((a + b) * 0.5 + inward * (size * 0.6 + gap), [(a, b)] + ticks))
        for option in options {
          let box = textBox(label, center: option.center, u: u, size: size)
          var padded = box
          padded.halfWidth += style.labelPadding * k
          padded.halfHeight += style.labelPadding * k
          guard padded.isInside(polygon) else { continue }
          let own = option.lines.map {
            OrientedBox.around($0.0, $0.1, halfWidth: style.lineClearance * k)
          }
          guard
            conflicts(box, padding: style.labelPadding * k, outside: false, ownLines: own) == 0
          else { continue }
          let stroke = DrawingStroke(
            color: style.interiorDimension, width: style.interiorDimensionWidth * k * 1000)
          var path = PathBuilder()
          for (p, q) in option.lines where p.distance(to: q) > 1e-6 { path.segment(p, q) }
          add(
            .shape(DrawingShape(path: path.path, stroke: stroke, layer: .interiorDimension)),
            .interiorDimension)
          add(
            centredText(
              label, center: option.center, u: u, size: size, color: style.interiorDimension,
              layer: .interiorDimension), .interiorDimension)
          labels.append(
            PlacedLabel(
              kind: .interiorDimension, text: label, box: box, roomId: rooms[edge.room].id))
          for (p, q) in option.lines where p.distance(to: q) > 1e-6 {
            lines.append(Obstacle(line: p, q, halfWidth: style.lineClearance * k))
          }
          placed = true
          break tiers
        }
      }
      if !placed { droppedInteriorDimensions += 1 }
    }
  }
}
