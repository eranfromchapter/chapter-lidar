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
  /// The overlap score plus how far out the line stands and whether the label left its line.
  var cost: Int
}

/// Lays out the text and dimension strings of the floor plan drawing so that no label
/// overlaps another label or a wall, and no outside dimension a symbol (room names and inside
/// dimensions may sit over furniture, on a patch of the room's colour). Sizes are given in
/// paper millimetres and converted with `k` (the scale denominator / 1000).
struct AnnotationLayout {
  let style: FloorPlanStyle
  let units: UnitFormatter
  /// Plan metres per paper millimetre.
  let k: Double
  var labels: [PlacedLabel] = []
  /// Dimension and witness lines, as thin boxes.
  var lines: [Obstacle] = []
  var symbols: [Obstacle]
  /// The quarter circles the doors sweep.
  var swings: [Obstacle]
  /// Outside faces of the closed exterior wall loops; labels outside stay off the building.
  var building: [Obstacle]
  var wallPieces: [Obstacle]
  var items: [DrawingLayer: [DrawingItem]] = [:]
  var exteriorDimensions: [ExteriorDimension] = []
  var droppedInteriorDimensions = 0
  /// Short outside runs left without a dimension because it could only cross others.
  var omittedExteriorDimensions = 0

  init(
    style: FloorPlanStyle, units: UnitFormatter, scaleDenominator: Double,
    symbols: [[Point2]], building: [[Point2]], wallPieces: [[Point2]], swings: [[Point2]] = []
  ) {
    self.style = style
    self.units = units
    self.k = scaleDenominator / 1000
    self.symbols = symbols.map(Obstacle.init)
    self.swings = swings.map(Obstacle.init)
    self.building = building.map(Obstacle.init)
    self.wallPieces = wallPieces.map(Obstacle.init)
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
    // Mostly across the sheet: left to right. Mostly up it: bottom to top (read from the
    // right-hand edge of the sheet).
    if abs(u.x) >= abs(u.y) - 1e-9 {
      if u.x < 0 { u = u * -1 }
    } else if u.y < 0 {
      u = u * -1
    }
    return u
  }

  /// How badly a candidate label box (and its own dimension lines) runs into things; 0 when it
  /// is free. Covering text, a wall or the building weighs most, a symbol less, and crossing a
  /// line least, so a crowded label goes where it hides the least.
  func conflicts(
    _ box: OrientedBox, padding: Double, outside: Bool, ownLines: [OrientedBox] = [],
    symbols checkSymbols: Bool = true, swings checkSwings: Bool = true
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
    where checkSymbols && symbol.extent.overlaps(extent)
      && Geo.convexOverlap(corners, symbol.polygon)
    {
      score += 30
    }
    for swing in swings
    where checkSwings && swing.extent.overlaps(extent)
      && Geo.convexOverlap(corners, swing.polygon)
    {
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
        score += 100
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

  /// Puts the room's name and area at the middle of the room: the point farthest from its
  /// walls (pole of inaccessibility), searched on a grid and refined around the best, ties
  /// going to the centroid. Furniture does not push the label into a corner: a place clear of
  /// furniture and door swings wins only when it is nearly as central, else the label sits on
  /// the furniture over a patch of the room's colour. It never covers another label.
  mutating func placeRoomLabel(
    roomId: String, name: String?, area: String?, polygon: [Point2], fill: DrawingColor
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
    let centroid = PlanGeometry.labelPoint(of: polygon)
    let size = max(
      (polygon.map(\.x).max()! - polygon.map(\.x).min()!),
      (polygon.map(\.y).max()! - polygon.map(\.y).min()!), 1e-6)
    // Score: covering another label rules a place out; then its clearance from the walls,
    // cut when it covers furniture or a door swing, nudged towards the centroid.
    func score(_ c: Point2) -> (blocked: Bool, value: Double)? {
      var b = box(at: c)
      b.halfWidth += padding
      b.halfHeight += padding
      guard b.isInside(polygon) else { return nil }
      var clearance = Double.infinity
      let corners = b.corners
      for p in corners + [c] {
        clearance = min(clearance, PlanGeometry.distanceToBoundary(of: polygon, from: p))
      }
      let extent = Extent(corners)
      let blocked = labels.contains { $0.extent.overlaps(extent) && $0.box.overlaps(b) }
      let covers =
        symbols.contains { $0.extent.overlaps(extent) && Geo.convexOverlap(corners, $0.polygon) }
        || swings.contains { $0.extent.overlaps(extent) && Geo.convexOverlap(corners, $0.polygon) }
        || lines.contains { $0.extent.overlaps(extent) && Geo.convexOverlap(corners, $0.polygon) }
      let value = clearance * (covers ? 0.6 : 1) - 0.02 * c.distance(to: centroid) / size * k
      return (blocked, value)
    }
    let xs = polygon.map(\.x)
    let ys = polygon.map(\.y)
    var lo = Point2(x: xs.min()!, y: ys.min()!)
    var hi = Point2(x: xs.max()!, y: ys.max()!)
    var best: (point: Point2, blocked: Bool, value: Double)?
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
              (!s.blocked && current.blocked)
              || (s.blocked == current.blocked && s.value > current.value + 1e-12)
          } else {
            better = true
          }
          if better { best = (p, s.blocked, s.value) }
        }
      }
      guard let current = best else { break }
      let spanX = (hi.x - lo.x) / Double(n)
      let spanY = (hi.y - lo.y) / Double(n)
      lo = Point2(x: current.point.x - spanX, y: current.point.y - spanY)
      hi = Point2(x: current.point.x + spanX, y: current.point.y + spanY)
    }
    let center = best?.point ?? centroid
    // A patch of the room's colour behind the text, so furniture lines do not run through it.
    var knockout = box(at: center)
    knockout.halfWidth += 0.4 * k
    knockout.halfHeight += 0.2 * k
    var patch = PathBuilder()
    patch.polygon(knockout.corners)
    add(.shape(DrawingShape(path: patch.path, fill: fill, layer: .roomLabel)), .roomLabel)
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

  /// An outside wall run to dimension: its outside face from `p0` to `p1` along `d`, facing
  /// `out`, and `baseline` (on `out`), where its dimension rows start: its own face, or a face
  /// across its span that stands too close in front of it to leave room, so the line clears
  /// the building; runs on one side with close baselines share the outermost (a chain).
  struct ExteriorItem {
    var loop: Int
    var run: Int
    var p0: Point2
    var p1: Point2
    var d: Point2
    var out: Point2
    var baseline: Double
    var length: Double { (p1 - p0).dot(d) }
  }

  /// Outside wall runs worth a dimension: every run of the outside wall loops at least
  /// `minimum` long. Shorter steps and returns are left out (their neighbours are chained across
  /// them), and of two short parallel runs facing each other with the same length (the two sides
  /// of a bay) only the first is kept.
  func exteriorItems(walls: WallLayout, minimum: Double) -> [ExteriorItem] {
    // Outside faces corner to corner (the mitre points), whatever the joints drawn.
    func face(_ loop: WallLayout.Loop, _ run: Int) -> (Point2, Point2) {
      (loop.outer[run], loop.outer[(run + 1) % loop.outer.count])
    }
    var faces: [(Point2, Point2)] = []
    for loop in walls.loops {
      for run in loop.segments.indices { faces.append(face(loop, run)) }
    }
    var items: [ExteriorItem] = []
    for (loopIndex, loop) in walls.loops.enumerated() {
      for (runIndex, segmentIndex) in loop.segments.enumerated() {
        let segment = walls.segments[segmentIndex]
        let d = segment.direction
        let out = segment.normal * -1
        let (p0, p1) = face(loop, runIndex)
        guard (p1 - p0).dot(d) >= minimum else { continue }
        // The faces across the span (its ends left out), as ranges on `out`.
        let lo = p0.dot(d) + 0.01
        let hi = p1.dot(d) - 0.01
        var ranges: [(Double, Double)] = []
        for (a, b) in faces {
          let ta = a.dot(d)
          let tb = b.dot(d)
          var u0 = 0.0
          var u1 = 1.0
          if abs(tb - ta) < 1e-9 {
            guard ta > lo, ta < hi else { continue }
          } else {
            let ua = (lo - ta) / (tb - ta)
            let ub = (hi - ta) / (tb - ta)
            u0 = max(u0, min(ua, ub))
            u1 = min(u1, max(ua, ub))
            guard u1 > u0 else { continue }
          }
          let c0 = (a + (b - a) * u0).dot(out)
          let c1 = (a + (b - a) * u1).dot(out)
          ranges.append((min(c0, c1), max(c0, c1)))
        }
        // The line goes in the open space in front of the face: past any face that stands
        // closer in front of it than a dimension needs (a wall jutting out across the span),
        // but not past faces beyond open ground (the far side of a recess).
        let room = (style.exteriorOffset + style.exteriorDimensionSize * 1.6 + style.labelGap) * k
        var baseline = max(p0.dot(out), p1.dot(out))
        var moved = true
        while moved {
          moved = false
          for (c0, c1) in ranges where c0 <= baseline + room && c1 > baseline + 1e-6 {
            baseline = c1
            moved = true
          }
        }
        let item = ExteriorItem(
          loop: loopIndex, run: runIndex, p0: p0, p1: p1, d: d, out: out, baseline: baseline)
        // The second side of a bay.
        let label = units.dimension(item.length)
        let twin = items.contains { other in
          other.length < 1.0 && other.out.dot(out) < -0.999
            && units.dimension(other.length) == label
            && abs((other.p0 - p0).dot(out)) < 3.5
            && min(other.p0.dot(d), other.p1.dot(d)) < p1.dot(d) - 0.8 * item.length
            && max(other.p0.dot(d), other.p1.dot(d)) > p0.dot(d) + 0.8 * item.length
        }
        if !twin { items.append(item) }
      }
    }
    // Chains: on each side, dimension lines whose baselines are close share the outermost one.
    let snap = 1.5 * style.exteriorTierStep * k
    var order = items.indices.sorted {
      let a = items[$0]
      let b = items[$1]
      let ka = AnnotationLayout.sideKey(a.out)
      let kb = AnnotationLayout.sideKey(b.out)
      if ka != kb { return ka < kb }
      if abs(a.baseline - b.baseline) > 1e-9 { return a.baseline < b.baseline }
      return $0 < $1
    }
    var start = 0
    while start < order.count {
      var end = start + 1
      let key = AnnotationLayout.sideKey(items[order[start]].out)
      while end < order.count, AnnotationLayout.sideKey(items[order[end]].out) == key,
        items[order[end]].baseline - items[order[start]].baseline <= snap
      {
        end += 1
      }
      let outermost = order[start..<end].map { items[$0].baseline }.max()!
      for index in order[start..<end] { items[index].baseline = outermost }
      start = end
    }
    // Placing order: the longest runs first, so the main dimensions get the best places and
    // short steps fit round them (or are left out).
    order = items.indices.sorted {
      let a = items[$0].length
      let b = items[$1].length
      return a > b + 1e-9 || (abs(a - b) <= 1e-9 && $0 < $1)
    }
    return order.map { items[$0] }
  }

  /// Which side of the building a face looks out to, as a whole number of degrees.
  static func sideKey(_ out: Point2) -> Int {
    var degrees = Int((atan2(out.y, out.x) * 180 / .pi).rounded())
    if degrees <= -180 { degrees += 360 }
    return degrees
  }

  /// Distance along the ray from `p` in `direction` (a unit vector) to the first outline edge
  /// it meets within `within`, nil when it meets none.
  static func firstHit(
    from p: Point2, direction: Point2, within: Double, building: [Obstacle]
  ) -> Double? {
    var best: Double?
    for face in building {
      let polygon = face.polygon
      for index in polygon.indices {
        let c = polygon[index]
        let d = polygon[(index + 1) % polygon.count]
        let e = d - c
        let denominator = direction.cross(e)
        guard abs(denominator) > 1e-12 else { continue }
        let t = (c - p).cross(e) / denominator
        let u = (c - p).cross(direction) / denominator
        guard t > 1e-9, t <= within + 1e-9, u >= -1e-9, u <= 1 + 1e-9 else { continue }
        if best == nil || t < best! { best = t }
      }
    }
    return best
  }

  /// True when segments ab and cd cross away from their ends, or run along each other.
  static func linesClash(_ a: Point2, _ b: Point2, _ c: Point2, _ d: Point2) -> Bool {
    let ab = b - a
    let cd = d - c
    let tolerance = 1e-5
    guard ab.length > tolerance, cd.length > tolerance else { return false }
    let denominator = ab.cross(cd)
    if abs(denominator) < 1e-12 * ab.length * cd.length {
      // Parallel: a clash when on one line and overlapping by more than a touch.
      guard abs((c - a).cross(ab.unit)) < tolerance else { return false }
      let u = ab.unit
      let overlap =
        min(max(a.dot(u), b.dot(u)), max(c.dot(u), d.dot(u)))
        - max(min(a.dot(u), b.dot(u)), min(c.dot(u), d.dot(u)))
      return overlap > tolerance
    }
    let s = (c - a).cross(cd) / denominator
    let t = (c - a).cross(ab) / denominator
    let ms = tolerance / ab.length
    let mt = tolerance / cd.length
    return s > ms && s < 1 - ms && t > mt && t < 1 - mt
  }

  /// One dimension per outside wall run (see `exteriorItems`), outside the building, measured
  /// along the outside face from corner to corner. Runs on one side share a line where they
  /// can (a chain), at a fixed distance beyond the building there; a run whose label or lines
  /// would clash goes on the next row out. No dimension or witness line crosses another, and
  /// a label too long for its run goes past the end of its line or beside it. None is
  /// dropped.
  mutating func placeExteriorDimensions(walls: WallLayout) {
    let items = exteriorItems(walls: walls, minimum: style.exteriorMinimumM)
    // Longest first, shortest first, then the crowded ones of the better of those first: the
    // order whose dimensions clash least, stand nearest their walls and leave out fewest wins.
    let longest = Array(items.indices)
    let shortest = Array(items.indices.reversed())
    var best: AnnotationLayout?
    var bestScore = Int.max
    var bestOrder = longest
    func score(_ layout: AnnotationLayout) -> Int {
      layout.exteriorDimensions.map(\.cost).reduce(0, +)
        + 200 * layout.omittedExteriorDimensions
    }
    for order in [longest, shortest] {
      var trial = self
      trial.placeExteriorDimensions(items: order.map { items[$0] })
      let value = score(trial)
      if value < bestScore {
        best = trial
        bestScore = value
        bestOrder = order
      }
    }
    if let current = best, current.exteriorDimensions.contains(where: \.crowded) {
      let crowded = Set(
        current.exteriorDimensions.filter(\.crowded).map { "\($0.loop)/\($0.run)" })
      let key = { (i: Int) in "\(items[i].loop)/\(items[i].run)" }
      let order =
        bestOrder.filter { crowded.contains(key($0)) }
        + bestOrder.filter { !crowded.contains(key($0)) }
      var trial = self
      trial.placeExteriorDimensions(items: order.map { items[$0] })
      if score(trial) < bestScore { best = trial }
    }
    if let best { self = best }
  }

  private mutating func placeExteriorDimensions(items: [ExteriorItem]) {
    let size = style.exteriorDimensionSize * k
    let gap = style.labelGap * k
    let tick = style.tickLength * k
    var dimensionLines: [(Point2, Point2)] = []
    var witnessLines: [(Point2, Point2)] = []
    var sideBaselines: [Int: [Double]] = [:]
    for item in items {
      sideBaselines[AnnotationLayout.sideKey(item.out), default: []].append(item.baseline)
    }
    for item in items {
      let d = item.d
      let out = item.out
      let along = item.length
      let label = units.dimension(along)
      let width = FontMetrics.width(label, size: size)
      let u = AnnotationLayout.readingDirection(d)

      struct Candidate {
        var tier: Int
        var placement: String
        var center: Point2
        var line: (Point2, Point2)
        var drawn: [(Point2, Point2)]
        var witnesses: [(Point2, Point2)]
        /// Witness lines that would run through the building.
        var through: Int
        /// How far the line stands beyond its own first row, plan metres.
        var distance: Double
      }
      // Where the line can go: rows out from its own baseline, then the first two rows of the
      // chains further out on the same side, nearest first.
      var positions: [(tier: Int, at: Double)] = []
      func row(_ base: Double, _ tier: Int) -> Double {
        base + (style.exteriorOffset + Double(tier) * style.exteriorTierStep) * k
      }
      for tier in 0..<style.exteriorTiers { positions.append((tier, row(item.baseline, tier))) }
      let outer = Set(sideBaselines[AnnotationLayout.sideKey(out)] ?? []).filter {
        $0 > item.baseline + 1e-6
      }
      for base in outer.sorted() {
        for tier in 0..<2 { positions.append((tier, row(base, tier))) }
      }
      positions.sort { $0.at < $1.at - 1e-9 || (abs($0.at - $1.at) <= 1e-9 && $0.tier < $1.tier) }
      var candidates: [Candidate] = []
      var previous = -Double.infinity
      for (tier, position) in positions {
        guard position > previous + 0.3 * style.exteriorTierStep * k else { continue }
        previous = position
        let a = item.p0 + out * (position - item.p0.dot(out))
        let b = item.p1 + out * (position - item.p1.dot(out))
        let distance = position - item.baseline - style.exteriorOffset * k
        // At each end a tick towards the wall, or a witness line down to the corner when the
        // line stands further off; none where it would run along a wall face.
        var witnesses: [(Point2, Point2)] = []
        var through = 0
        for (end, corner) in [(a, item.p0), (b, item.p1)] {
          let height = position - corner.dot(out)
          var reach = height - gap <= tick * 1.5 ? min(tick, max(height - gap, 0)) : height - gap
          // Stop short of the first wall in the way (a step in the outline above the corner).
          if let hit = AnnotationLayout.firstHit(
            from: end, direction: out * -1, within: reach + gap, building: building)
          {
            reach = min(reach, hit - gap)
          }
          guard reach > 1e-6 else { continue }
          let foot = end - out * reach
          let middle = (end + foot) * 0.5
          // Along a wall face (an inside corner): left out. Through the building: a clash.
          if building.contains(where: {
            PlanGeometry.distanceToBoundary(of: $0.polygon, from: middle) < 0.05 * k
          }) {
            continue
          }
          if building.contains(where: { PlanGeometry.contains($0.polygon, middle) }) {
            through += 1
            continue
          }
          witnesses.append((foot, end))
        }
        let middle = (a + b) * 0.5
        let stub = style.minimumStub * k
        if width + 2 * gap + 2 * stub <= along {
          let cutA = middle - d * (width / 2 + gap)
          let cutB = middle + d * (width / 2 + gap)
          candidates.append(
            Candidate(
              tier: tier, placement: "line", center: middle, line: (a, b),
              drawn: [(a, cutA), (cutB, b)], witnesses: witnesses, through: through,
              distance: distance))
        } else {
          // Past the nearer free end, on the line carried on, with no stubs.
          for (end, sign, name) in [(b, 1.0, "past-end"), (a, -1.0, "past-start")] {
            candidates.append(
              Candidate(
                tier: tier, placement: name, center: end + d * (sign * (gap + width / 2)),
                line: (a, b), drawn: [(a, b)], witnesses: witnesses, through: through,
                distance: distance))
          }
        }
        candidates.append(
          Candidate(
            tier: tier, placement: "beside", center: middle + out * (size * 0.6 + gap),
            line: (a, b), drawn: [(a, b)], witnesses: witnesses, through: through,
            distance: distance))
      }
      var chosen: (candidate: Candidate, conflicts: Int, cost: Int)?
      for candidate in candidates {
        let box = textBox(label, center: candidate.center, u: u, size: size)
        let own = (candidate.drawn + candidate.witnesses).map {
          OrientedBox.around($0.0, $0.1, halfWidth: style.lineClearance * k)
        }
        var count = conflicts(box, padding: style.labelPadding * k, outside: true, ownLines: own)
        count += 1000 * candidate.through
        // No line crosses another dimension's lines, and no label sits on them.
        for (p, q) in witnessLines
        where AnnotationLayout.linesClash(candidate.line.0, candidate.line.1, p, q) {
          count += 1000
        }
        for (p, q) in dimensionLines {
          if AnnotationLayout.linesClash(candidate.line.0, candidate.line.1, p, q) {
            count += 1000
          }
          for w in candidate.witnesses where AnnotationLayout.linesClash(w.0, w.1, p, q) {
            count += 1000
          }
        }
        var padded = box
        padded.halfWidth += style.labelPadding * k
        padded.halfHeight += style.labelPadding * k
        for (p, q) in dimensionLines + witnessLines
        where padded.overlaps(convex: OrientedBox.around(p, q, halfWidth: 1e-4 * k).corners) {
          count += 100
        }
        // Nearer rows and a label on its line win when they are as free.
        let cost =
          count + Int((2 * candidate.distance / (style.exteriorTierStep * k)).rounded())
          + (candidate.placement == "line" ? 0 : 1)
        if chosen == nil || cost < chosen!.cost { chosen = (candidate, count, cost) }
        if cost == 0 { break }
      }
      guard let pick = chosen?.candidate else { continue }
      // A short run whose dimension would cover or cross anything or stand far off (the sides
      // of a narrow recess, a step tucked under another dimension) is left out.
      if along < style.exteriorOptionalM,
        (chosen?.conflicts ?? 0) > 0 || pick.distance > 2.5 * style.exteriorTierStep * k
      {
        omittedExteriorDimensions += 1
        continue
      }
      let stroke = DrawingStroke(
        color: style.ink, width: style.exteriorDimensionWidth * k * 1000)
      var path = PathBuilder()
      for (a, b) in pick.drawn + pick.witnesses where a.distance(to: b) > 1e-6 {
        path.segment(a, b)
      }
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
      for (a, b) in pick.drawn + pick.witnesses where a.distance(to: b) > 1e-6 {
        lines.append(Obstacle(line: a, b, halfWidth: style.lineClearance * k))
      }
      dimensionLines.append(pick.line)
      witnessLines += pick.witnesses
      exteriorDimensions.append(
        ExteriorDimension(
          loop: item.loop, run: item.run, lengthM: along, label: label, tier: pick.tier + 1,
          placement: pick.placement, crowded: (chosen?.conflicts ?? 0) > 0,
          conflictScore: chosen?.conflicts ?? 0, cost: chosen?.cost ?? 0))
    }
  }

  // MARK: Interior dimensions

  /// Dimensions along the edges of each room, just inside it, measured between the wall faces.
  /// Every room first gets its overall length and width (its longest edge across the sheet and
  /// its longest edge up it), then the other edges, longest first. A label may sit over
  /// furniture, on a patch of the room's colour, but never over another label, a wall or a
  /// door swing, and no line runs through a door swing; the length and width may cross a
  /// swing when nothing else is free. Of two edges facing each other close by with the same
  /// length (the two faces of a short return) only one is dimensioned. A dimension that finds
  /// no place is left out.
  mutating func placeInteriorDimensions(
    rooms: [(id: String, clear: [Point2], fill: DrawingColor)]
  ) {
    let size = style.interiorDimensionSize * k
    let gap = style.labelGap * k
    struct Edge {
      var room: Int
      var a: Point2
      var b: Point2
      var label: String
      var required: Bool
      var length: Double { a.distance(to: b) }
    }
    var edges: [Edge] = []
    for (index, room) in rooms.enumerated() {
      let polygon = room.clear
      var roomEdges: [Edge] = []
      for i in polygon.indices {
        let a = polygon[i]
        let b = polygon[(i + 1) % polygon.count]
        let length = a.distance(to: b)
        guard length >= style.interiorMinimumM else { continue }
        let label = units.dimension(length)
        let d = (b - a).unit
        // The other face of a short return: facing this one, close by, the same length.
        let twin = roomEdges.contains { other in
          let e = (other.b - other.a).unit
          guard e.dot(d) < -0.999, other.label == label else { return false }
          let distance = abs((other.a - a).cross(d))
          let s0 = min(other.a.dot(d), other.b.dot(d))
          let s1 = max(other.a.dot(d), other.b.dot(d))
          let overlap = min(s1, max(a.dot(d), b.dot(d))) - max(s0, min(a.dot(d), b.dot(d)))
          return distance < 0.5 && overlap > 0.5 * length
        }
        if !twin {
          roomEdges.append(Edge(room: index, a: a, b: b, label: label, required: false))
        }
      }
      // The room's length and width.
      for across in [true, false] {
        let pick = roomEdges.indices.filter {
          let d = (roomEdges[$0].b - roomEdges[$0].a).unit
          return across ? abs(d.x) >= abs(d.y) : abs(d.x) < abs(d.y)
        }.max {
          roomEdges[$0].length < roomEdges[$1].length - 1e-9
            || (abs(roomEdges[$0].length - roomEdges[$1].length) <= 1e-9 && $0 > $1)
        }
        if let pick { roomEdges[pick].required = true }
      }
      edges += roomEdges
    }
    let order = edges.indices.sorted {
      let e0 = edges[$0]
      let e1 = edges[$1]
      if e0.required != e1.required { return e0.required }
      return e0.length > e1.length + 1e-9 || (abs(e0.length - e1.length) <= 1e-9 && $0 < $1)
    }
    for index in order {
      let edge = edges[index]
      let polygon = rooms[edge.room].clear
      let length = edge.length
      let d = (edge.b - edge.a).unit
      let inward = d.leftNormal
      let label = edge.label
      let width = FontMetrics.width(label, size: size)
      let u = AnnotationLayout.readingDirection(d)
      let stub = style.minimumStub * k
      struct Option {
        var center: Point2
        var lines: [(Point2, Point2)]
        var soft: Int
      }
      var best: Option?
      for tier in 0..<2 {
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
            conflicts(
              box, padding: style.labelPadding * k, outside: false, ownLines: own,
              symbols: false, swings: false) == 0
          else { continue }
          // Furniture under the label, a little; a door swing under it or its lines, more.
          let corners = padded.corners
          let extent = Extent(corners)
          var soft = Double(tier)
          for symbol in symbols
          where symbol.extent.overlaps(extent) && Geo.convexOverlap(corners, symbol.polygon) {
            soft += 2
          }
          var crossesSwing = false
          for swing in swings {
            if swing.extent.overlaps(extent) && Geo.convexOverlap(corners, swing.polygon) {
              crossesSwing = true
            }
            for line in own where Geo.convexOverlap(line.corners, swing.polygon, margin: 1e-4) {
              crossesSwing = true
            }
          }
          if crossesSwing {
            guard edge.required else { continue }
            soft += 20
          }
          if best == nil || Int(soft) < best!.soft {
            best = Option(center: option.center, lines: option.lines, soft: Int(soft))
          }
          if soft == 0 { break }
        }
        if let current = best, current.soft <= tier { break }
      }
      guard let pick = best else {
        droppedInteriorDimensions += 1
        continue
      }
      let stroke = DrawingStroke(
        color: style.interiorDimensionLine, width: style.interiorDimensionWidth * k * 1000)
      var path = PathBuilder()
      for (p, q) in pick.lines where p.distance(to: q) > 1e-6 { path.segment(p, q) }
      add(
        .shape(DrawingShape(path: path.path, stroke: stroke, layer: .interiorDimension)),
        .interiorDimension)
      let box = textBox(label, center: pick.center, u: u, size: size)
      var knockout = box
      knockout.halfWidth += 0.3 * k
      knockout.halfHeight += 0.1 * k
      var patch = PathBuilder()
      patch.polygon(knockout.corners)
      add(
        .shape(
          DrawingShape(path: patch.path, fill: rooms[edge.room].fill, layer: .interiorDimension)
        ), .interiorDimension)
      add(
        centredText(
          label, center: pick.center, u: u, size: size, color: style.interiorDimension,
          layer: .interiorDimension), .interiorDimension)
      labels.append(
        PlacedLabel(kind: .interiorDimension, text: label, box: box, roomId: rooms[edge.room].id))
      for (p, q) in pick.lines where p.distance(to: q) > 1e-6 {
        lines.append(Obstacle(line: p, q, halfWidth: style.lineClearance * k))
      }
    }
  }
}
