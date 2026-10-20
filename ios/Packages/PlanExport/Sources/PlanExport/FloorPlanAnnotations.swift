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

/// One outside dimension: a piece of an outer wall run between its corners and the partitions
/// that meet it, or (`overall`) the whole width or height of the building on an outer row.
struct ExteriorDimension: Sendable {
  /// The wall loop and run it measures; -1 for an overall dimension.
  var loop: Int
  var run: Int
  /// Along the outside face, corner to corner (or to a partition's centre line).
  var lengthM: Double
  var label: String
  /// 1 for the row nearest the wall.
  var tier: Int
  /// Where the label went: on the line, or beside it (outside) when it does not fit.
  var placement: String
  /// True when no free place was found and the label was put where it overlaps least.
  var crowded: Bool
  /// How badly that place overlaps (see `AnnotationLayout.conflicts`); 0 when free.
  var conflictScore: Int
  /// The overlap score plus how far out the line stands and whether the label left its line.
  var cost: Int
  /// Which side of the building it is on (`AnnotationLayout.sideKey`) and how far out its
  /// line stands there (plan metres along the side's outward direction).
  var side: Int
  var position: Double
  var overall = false
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
  /// Plumbing fixtures and appliances, which a room name never covers.
  var fixtures: [Obstacle]
  /// The quarter circles the doors sweep.
  var swings: [Obstacle]
  /// Outside faces of the closed exterior wall loops; labels outside stay off the building.
  var building: [Obstacle]
  var wallPieces: [Obstacle]
  var items: [DrawingLayer: [DrawingItem]] = [:]
  var exteriorDimensions: [ExteriorDimension] = []
  /// The outside dimension lines and their witness lines placed so far.
  var exteriorLines: [(Point2, Point2)] = []
  var exteriorWitnesses: [(Point2, Point2)] = []
  var droppedInteriorDimensions = 0
  /// Short outside runs left without a dimension because it could only cross others.
  var omittedExteriorDimensions = 0

  init(
    style: FloorPlanStyle, units: UnitFormatter, scaleDenominator: Double,
    symbols: [[Point2]], fixtures: [[Point2]] = [], building: [[Point2]],
    wallPieces: [[Point2]], swings: [[Point2]] = []
  ) {
    self.style = style
    self.units = units
    self.k = scaleDenominator / 1000
    self.symbols = symbols.map(Obstacle.init)
    self.fixtures = fixtures.map(Obstacle.init)
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
  /// going to the centroid. It never covers another label, a door swing or a fixture (a
  /// toilet, a sink, a bath, an appliance) where the room has space elsewhere; in a room too
  /// small for that it covers as little of them as it can, and then has no patch behind it,
  /// so the fixture still shows. Furniture is weighed, not avoided: a place with
  /// `labelFurnitureClearance` of open floor all round counts in full, one well within a piece
  /// of furniture (on a patch of the room's colour) a little less, and one squeezed up against
  /// furniture or across its edge least, so a label sits either clear of the furniture or
  /// within it, at the middle, never hard against it.
  ///
  /// A name too wide for the room is fitted to it (`fittedRoomLabel`): wrapped onto two lines,
  /// then set smaller, down to the size of the area, then cut short with an ellipsis. Where
  /// even that finds no place (a room smaller than its area line), the label goes at the
  /// middle with the name on one line at that smallest size, cut after
  /// `minimumNameCharacters` characters; so a name never runs far past its room and never
  /// grows the drawing.
  mutating func placeRoomLabel(
    roomId: String, name: String?, area: String?, polygon: [Point2], fill: DrawingColor
  ) {
    let name = name.map { Format.singleLine($0).trimmingCharacters(in: .whitespaces) }
      .flatMap { $0.isEmpty ? nil : $0 }
    let area = area.flatMap { $0.isEmpty ? nil : $0 }
    guard name != nil || area != nil, polygon.count >= 3 else { return }
    let (block, place) = fittedRoomLabel(name: name, area: area, polygon: polygon)
    let center = place ?? PlanGeometry.labelPoint(of: polygon)
    // Each line spans its glyph box, descender to cap height (0.97 em).
    let lineGap = 0.15 * style.roomNameSize * k
    let height = AnnotationLayout.blockHeight(block, lineGap: lineGap)
    let u = Point2(x: 1, y: 0)
    let label = OrientedBox(
      center: center, u: u, halfWidth: AnnotationLayout.blockWidth(block) / 2,
      halfHeight: height / 2)
    // A patch of the room's colour behind the text, so furniture lines do not run through it;
    // none over a fixture, which must stay whole.
    var knockout = label
    knockout.halfWidth += 0.4 * k
    knockout.halfHeight += 0.2 * k
    let knockoutCorners = knockout.corners
    if !fixtures.contains(where: { Geo.convexOverlap(knockoutCorners, $0.polygon) }) {
      var patch = PathBuilder()
      patch.polygon(knockoutCorners)
      add(.shape(DrawingShape(path: patch.path, fill: fill, layer: .roomLabel)), .roomLabel)
    }
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
        kind: .room, text: block.map(\.text).joined(separator: "\n"), box: label,
        roomId: roomId))
  }

  /// A room name always keeps at least this many characters when it is cut short.
  static let minimumNameCharacters = 12

  /// Height of a block of centred lines, `lineGap` apart.
  static func blockHeight(_ block: [(text: String, size: Double)], lineGap: Double) -> Double {
    block.map(\.size).reduce(0, +) * 0.97 + lineGap * Double(max(0, block.count - 1))
  }

  /// Width of the widest line of a block.
  static func blockWidth(_ block: [(text: String, size: Double)]) -> Double {
    block.map { FontMetrics.width($0.text, size: $0.size) }.max() ?? 0
  }

  /// The name split at the space that makes the longer of its two lines shortest; nil when it
  /// has no space between words.
  static func balancedSplit(_ name: String, size: Double) -> [String]? {
    let characters = Array(name)
    var best: (lines: [String], longer: Double)?
    for index in characters.indices where characters[index] == " " {
      let first = String(characters[..<index]).trimmingCharacters(in: .whitespaces)
      let second = String(characters[(index + 1)...]).trimmingCharacters(in: .whitespaces)
      guard !first.isEmpty, !second.isEmpty else { continue }
      let longer = max(
        FontMetrics.width(first, size: size), FontMetrics.width(second, size: size))
      if best.map({ longer < $0.longer }) ?? true { best = ([first, second], longer) }
    }
    return best?.lines
  }

  /// `text` cut to fit `width` with an ellipsis, or whole when it fits.
  static func cut(_ text: String, size: Double, width: Double) -> String {
    guard FontMetrics.width(text, size: size) > width else { return text }
    var characters = Array(text)
    while !characters.isEmpty {
      characters.removeLast()
      let shorter =
        String(characters).trimmingCharacters(in: .whitespaces) + "\u{2026}"
      if FontMetrics.width(shorter, size: size) <= width { return shorter }
    }
    return "\u{2026}"
  }

  /// The name on lines no wider than `width`: whole on one line when it fits; otherwise as
  /// much as fits on the first line (broken after a word where there is one), and the rest on
  /// a second line, cut short with an ellipsis when it is still too long.
  static func wrapped(_ name: String, size: Double, width: Double) -> [String] {
    guard FontMetrics.width(name, size: size) > width else { return [name] }
    let characters = Array(name)
    var count = 0
    while count < characters.count,
      FontMetrics.width(String(characters[...count]), size: size) <= width
    {
      count += 1
    }
    count = max(1, count)
    // Back to the end of the last whole word, unless the line already ends at one.
    if count < characters.count, characters[count] != " ",
      let space = characters[..<count].lastIndex(of: " "), space > 0
    {
      count = space
    }
    let first = String(characters[..<count]).trimmingCharacters(in: .whitespaces)
    let rest = String(characters[count...]).trimmingCharacters(in: .whitespaces)
    guard !rest.isEmpty else { return [first] }
    return [first, cut(rest, size: size, width: width)]
  }

  /// The lines of a room label and where it goes (nil: nowhere fits; see `placeRoomLabel`).
  /// Layouts are tried in order until one finds a place inside the room: the name on one
  /// line, then on two, at the name size, between sizes, then the area size; then cut short
  /// at the area size, as wide as still fits.
  func fittedRoomLabel(name: String?, area: String?, polygon: [Point2])
    -> (block: [(text: String, size: Double)], place: Point2?)
  {
    let nameSize = style.roomNameSize * k
    let smallest = min(style.roomAreaSize * k, nameSize)
    func block(_ lines: [String], _ size: Double) -> [(text: String, size: Double)] {
      lines.map { ($0, size) } + (area.map { [($0, style.roomAreaSize * k)] } ?? [])
    }
    guard let name else {
      let only = block([], nameSize)
      return (only, roomLabelPlace(only, polygon: polygon))
    }
    var sizes = [nameSize]
    if smallest < nameSize - 1e-12 { sizes += [(nameSize + smallest) / 2, smallest] }
    for size in sizes {
      var options = [[name]]
      if let split = AnnotationLayout.balancedSplit(name, size: size) { options.append(split) }
      for lines in options {
        let candidate = block(lines, size)
        if let place = roomLabelPlace(candidate, polygon: polygon) { return (candidate, place) }
      }
    }
    // Cut short: the widest lines that still find a place, keeping at least
    // `minimumNameCharacters` characters.
    func cutShort(_ width: Double) -> [(text: String, size: Double)] {
      block(AnnotationLayout.wrapped(name, size: smallest, width: width), smallest)
    }
    let kept = String(name.prefix(AnnotationLayout.minimumNameCharacters))
    var low = FontMetrics.width(
      kept + (kept.count < name.count ? "\u{2026}" : ""), size: smallest)
    var high = FontMetrics.width(name, size: smallest)
    guard let first = roomLabelPlace(cutShort(low), polygon: polygon) else {
      // Nowhere fits: one line at the middle.
      let line = AnnotationLayout.cut(name, size: smallest, width: low)
      return (block([line], smallest), nil)
    }
    var found = (block: cutShort(low), place: first)
    for _ in 0..<10 where high - low > 0.05 * k {
      let width = (low + high) / 2
      let candidate = cutShort(width)
      if let place = roomLabelPlace(candidate, polygon: polygon) {
        found = (candidate, place)
        low = width
      } else {
        high = width
      }
    }
    return (found.block, found.place)
  }

  /// The best place for `block` inside the room (see `placeRoomLabel`); nil when it fits
  /// nowhere.
  func roomLabelPlace(_ block: [(text: String, size: Double)], polygon: [Point2]) -> Point2? {
    let lineGap = 0.15 * style.roomNameSize * k
    let height = AnnotationLayout.blockHeight(block, lineGap: lineGap)
    let halfWidth = AnnotationLayout.blockWidth(block) / 2
    let u = Point2(x: 1, y: 0)
    func box(at c: Point2) -> OrientedBox {
      OrientedBox(center: c, u: u, halfWidth: halfWidth, halfHeight: height / 2)
    }
    let padding = 0.6 * k
    let roomy = max(style.labelFurnitureClearance, padding)
    let centroid = PlanGeometry.labelPoint(of: polygon)
    let size = max(
      (polygon.map(\.x).max()! - polygon.map(\.x).min()!),
      (polygon.map(\.y).max()! - polygon.map(\.y).min()!), 1e-6)
    struct Place {
      var point: Point2
      /// How much of the box covers labels (100 each), fixtures and door swings (sampled).
      var hits: Int
      /// Open floor round it, weighed by the furniture near it and nudged to the centroid.
      var value: Double
    }
    let samples = (0..<5).flatMap { i in (0..<3).map { j in (Double(i) / 4, Double(j) / 2) } }
    func evaluate(_ c: Point2) -> Place? {
      var b = box(at: c)
      b.halfWidth += padding
      b.halfHeight += padding
      guard b.isInside(polygon) else { return nil }
      let corners = b.corners
      let extent = Extent(corners)
      var hits = 0
      for label in labels where label.extent.overlaps(extent) && label.box.overlaps(b) {
        hits += 100
      }
      for obstacle in fixtures + swings
      where obstacle.extent.overlaps(extent) && Geo.convexOverlap(corners, obstacle.polygon) {
        // Covering a corner of it is better than covering it all.
        hits += 1
        for (x, y) in samples {
          let p = corners[0] + (corners[1] - corners[0]) * x + (corners[3] - corners[0]) * y
          if PlanGeometry.contains(obstacle.polygon, p) { hits += 1 }
        }
      }
      var clearance = Double.infinity
      for p in corners + [c] {
        clearance = min(clearance, PlanGeometry.distanceToBoundary(of: polygon, from: p))
      }
      // On furniture: well within the pieces it covers, not across or along an edge of one.
      let under = symbols.filter {
        $0.extent.overlaps(extent) && Geo.convexOverlap(corners, $0.polygon)
      }
      var inset = box(at: c)
      inset.halfWidth += roomy
      inset.halfHeight += roomy
      let insetCorners = inset.corners
      let on =
        !under.isEmpty
        && under.allSatisfy { piece in
          insetCorners.allSatisfy { PlanGeometry.contains(piece.polygon, $0) }
        }
      var wide = box(at: c)
      wide.halfWidth += roomy
      wide.halfHeight += roomy
      let wideCorners = wide.corners
      let wideExtent = Extent(wideCorners)
      let near = symbols.contains {
        $0.extent.overlaps(wideExtent) && Geo.convexOverlap(wideCorners, $0.polygon)
      }
      let weight = !near ? 1 : (on ? 0.8 : 0.45)
      let value = clearance * weight - 0.02 * c.distance(to: centroid) / size * k
      return Place(point: c, hits: hits, value: value)
    }
    // Grid search, refined three times round the best.
    let xs = polygon.map(\.x)
    let ys = polygon.map(\.y)
    var lo = Point2(x: xs.min()!, y: ys.min()!)
    var hi = Point2(x: xs.max()!, y: ys.max()!)
    var best: Place?
    for round in 0..<4 {
      let n = round == 0 ? 28 : 10
      for i in 0...n {
        for j in 0...n {
          let p = Point2(
            x: lo.x + (hi.x - lo.x) * Double(i) / Double(n),
            y: lo.y + (hi.y - lo.y) * Double(j) / Double(n))
          guard let place = evaluate(p) else { continue }
          if let current = best,
            place.hits > current.hits
              || (place.hits == current.hits && place.value <= current.value + 1e-12)
          {
            continue
          }
          best = place
        }
      }
      guard let current = best else { break }
      let spanX = (hi.x - lo.x) / Double(n)
      let spanY = (hi.y - lo.y) / Double(n)
      lo = Point2(x: current.point.x - spanX, y: current.point.y - spanY)
      hi = Point2(x: current.point.x + spanX, y: current.point.y + spanY)
    }
    return best?.point
  }

  // MARK: Exterior dimensions

  /// An outside wall run to dimension: its outside face from `p0` to `p1` along `d`, facing
  /// `out`, broken at `breaks` where partitions meet it, and `baseline` (on `out`), where its
  /// dimension rows start: its own face, or a face across its span that stands too close in
  /// front of it to leave room, so the line clears the building. Runs on one side whose
  /// baselines nearly agree share the outermost (a chain on one line).
  struct ExteriorItem {
    var loop: Int
    var run: Int
    var p0: Point2
    var p1: Point2
    var d: Point2
    var out: Point2
    var baseline: Double
    /// Where partitions meet the run, as distances along `d` between p0 and p1, in order.
    var breaks: [Double] = []
    var length: Double { (p1 - p0).dot(d) }
    /// The pieces between the corners and the breaks, as distances along `d`.
    var pieces: [(Double, Double)] {
      let stops = [p0.dot(d)] + breaks + [p1.dot(d)]
      return (1..<stops.count).map { (stops[$0 - 1], stops[$0]) }
    }
  }

  /// Outside wall runs worth a dimension: every run of the outside wall loops at least
  /// `minimum` long, broken where a partition meets it from inside (at the partition's centre
  /// line, when both pieces are at least `minimum` long), so each room's outside length shows.
  /// Shorter steps and returns are left out (their neighbours are chained across them); of two
  /// short parallel runs facing each other with the same length (the two sides of a bay) only
  /// the first is kept; and a run with the same corners and breaks as the run facing it across
  /// the building (the far side of a rectangle) is given once, on the top or left.
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
        // Partitions standing on the run from inside.
        var stops: [Double] = []
        for other in walls.segments where other.kind != .exterior && other.length > 0 {
          guard abs(other.direction.dot(d)) < 0.3 else { continue }
          for (end, far) in [(other.a, other.b), (other.b, other.a)] {
            guard abs((end - segment.a).dot(segment.normal)) < 0.03,
              (far - end).dot(segment.normal) > 0.05
            else { continue }
            stops.append(end.dot(d))
          }
        }
        var breaks: [Double] = []
        for t in stops.sorted()
        where t >= p0.dot(d) + minimum - 1e-9 && t <= p1.dot(d) - minimum + 1e-9
          && (breaks.last.map { t - $0 >= minimum - 1e-9 } ?? true)
        {
          breaks.append(t)
        }
        let item = ExteriorItem(
          loop: loopIndex, run: runIndex, p0: p0, p1: p1, d: d, out: out, baseline: baseline,
          breaks: breaks)
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
    // The far side of a plain run: the top or left one kept.
    let preferred = items.indices.sorted {
      let a = items[$0].out
      let b = items[$1].out
      let ka = a.y > 0.5 || a.x < -0.5 ? 0 : 1
      let kb = b.y > 0.5 || b.x < -0.5 ? 0 : 1
      return ka < kb || (ka == kb && $0 < $1)
    }
    var dropped = Set<Int>()
    var kept: [Int] = []
    // Corners and breaks of a run along `d`, in order.
    func stops(_ item: ExteriorItem, along d: Point2) -> [Double] {
      ([item.p0.dot(d), item.p1.dot(d)] + item.breaks.map { $0 * item.d.dot(d) }).sorted()
    }
    for index in preferred {
      let item = items[index]
      let repeated = kept.contains { other in
        let o = items[other]
        guard o.out.dot(item.out) < -0.999, o.breaks.count == item.breaks.count else {
          return false
        }
        let a = stops(item, along: item.d)
        let b = stops(o, along: item.d)
        return zip(a, b).allSatisfy { abs($0 - $1) < 0.0127 }
      }
      if repeated { dropped.insert(index) } else { kept.append(index) }
    }
    items = items.indices.filter { !dropped.contains($0) }.map { items[$0] }
    // Chains: on each side, dimension lines whose baselines nearly agree share the outermost.
    let snap = style.exteriorTierStep * k
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

  /// True when segments ab and cd cross at a point within `reach` of an end of each: two
  /// dimension lines turning an inside corner of the outline, each a fixed distance in front of
  /// its own face, cross there.
  static func cornerCrossing(
    _ a: Point2, _ b: Point2, _ c: Point2, _ d: Point2, reach: Double
  ) -> Bool {
    guard abs((b - a).unit.cross((d - c).unit)) > 0.5,
      let p = Geo.lineIntersection(a, (b - a).unit, c, (d - c).unit)
    else { return false }
    return min(p.distance(to: a), p.distance(to: b)) <= reach
      && min(p.distance(to: c), p.distance(to: d)) <= reach
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

  /// Outside dimensions (see `exteriorItems`), outside the building, measured along the outside
  /// face: one chain per wall run, a fixed distance in front of its own face, with a witness
  /// line at each corner and where each partition meets the run, and each piece's length on
  /// the line (or beside it, outside, when it does not fit). A run whose labels or lines would
  /// clash goes on the next row out, and a long run hardly ever: a short step that could only
  /// cross another dimension or stand far out is left out instead. No dimension or witness line
  /// crosses another. Then, on a row outside those, the overall width and height of the
  /// building where a side has more than one piece (`placeOverallDimensions`).
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
        + 80 * layout.omittedExteriorDimensions
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
    placeOverallDimensions(walls: walls)
  }

  private mutating func placeExteriorDimensions(items: [ExteriorItem]) {
    let size = style.exteriorDimensionSize * k
    let gap = style.labelGap * k
    let tick = style.tickLength * k
    let stub = style.minimumStub * k
    let step = style.exteriorTierStep * k
    var sideBaselines: [Int: [Double]] = [:]
    for item in items {
      sideBaselines[AnnotationLayout.sideKey(item.out), default: []].append(item.baseline)
    }
    for item in items {
      let d = item.d
      let out = item.out
      let u = AnnotationLayout.readingDirection(d)
      let pieces = item.pieces
      let texts = pieces.map { units.dimension($0.1 - $0.0) }
      let widths = texts.map { FontMetrics.width($0, size: size) }

      struct Candidate {
        var tier: Int
        var position: Double
        var line: (Point2, Point2)
        var drawn: [(Point2, Point2)]
        var witnesses: [(Point2, Point2)]
        /// Each piece's label: its centre, and whether it sits on the line.
        var labels: [(center: Point2, onLine: Bool)]
        /// Witness lines that would run through the building.
        var through: Int
        /// How far the line stands beyond its own first row, plan metres.
        var distance: Double
        /// The label is off the middle of its line.
        var slid: Bool
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
        guard position > previous + 0.3 * step else { continue }
        previous = position
        let origin = item.p0 + out * (position - item.p0.dot(out))
        func at(_ s: Double) -> Point2 { origin + d * (s - item.p0.dot(d)) }
        let a = at(item.p0.dot(d))
        let b = at(item.p1.dot(d))
        let distance = position - item.baseline - style.exteriorOffset * k
        // At each corner and break a tick towards the wall, or a witness line down to it when
        // the line stands further off; none where it would run along a wall face.
        var witnesses: [(Point2, Point2)] = []
        var through = 0
        let feet =
          [item.p0] + item.breaks.map { item.p0 + d * ($0 - item.p0.dot(d)) } + [item.p1]
        for foot in feet {
          let end = at(foot.dot(d))
          let height = position - foot.dot(out)
          var reach = height - gap <= tick * 1.5 ? min(tick, max(height - gap, 0)) : height - gap
          // Stop short of the first wall in the way (a step in the outline above the corner).
          if let hit = AnnotationLayout.firstHit(
            from: end, direction: out * -1, within: reach + gap, building: building)
          {
            reach = min(reach, hit - gap)
          }
          guard reach > 1e-6 else { continue }
          let bottom = end - out * reach
          let middle = (end + bottom) * 0.5
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
          witnesses.append((bottom, end))
        }
        // Each piece's length on its stretch of line when it fits there, else beside it; the
        // length of a run in one piece may also slide along the line, off a crossing.
        let slides = pieces.count == 1 ? [0.0, -1, 1] : [0.0]
        for slide in slides {
          var labels: [(center: Point2, onLine: Bool)] = []
          var cuts: [(Double, Double)] = []
          for (index, piece) in pieces.enumerated() {
            let width = widths[index]
            let span = piece.1 - piece.0
            let fits = width + 2 * gap + 2 * stub <= span
            let room = fits ? span / 2 - width / 2 - gap - stub : 0
            let middle = (piece.0 + piece.1) / 2 + slide * room
            if slide != 0, room < 0.05 * span { continue }
            if fits {
              labels.append((at(middle), true))
              cuts.append((middle - width / 2 - gap, middle + width / 2 + gap))
            } else {
              labels.append((at(middle) + out * (size * 0.6 + gap), false))
            }
          }
          guard labels.count == pieces.count else { continue }
          var drawn: [(Point2, Point2)] = []
          var from = item.p0.dot(d)
          for cut in cuts {
            drawn.append((at(from), at(cut.0)))
            from = cut.1
          }
          drawn.append((at(from), at(item.p1.dot(d))))
          candidates.append(
            Candidate(
              tier: tier, position: position, line: (a, b), drawn: drawn, witnesses: witnesses,
              labels: labels, through: through, distance: distance,
              slid: slide != 0))
        }
      }
      var chosen: (candidate: Candidate, conflicts: Int, cost: Int)?
      // Two lines may cross where they turn an inside corner, each near its own end there.
      let cornerReach = (style.exteriorOffset + style.labelGap) * k
      // A long run is pulled hard towards its own wall.
      let weight = max(1, item.length / 2)
      for candidate in candidates {
        let own = (candidate.drawn + candidate.witnesses).map {
          OrientedBox.around($0.0, $0.1, halfWidth: style.lineClearance * k)
        }
        var count = 1000 * candidate.through
        var boxes: [OrientedBox] = []
        for (index, label) in candidate.labels.enumerated() {
          let box = textBox(texts[index], center: label.center, u: u, size: size)
          count += conflicts(
            box, padding: style.labelPadding * k, outside: true, ownLines: index == 0 ? own : [])
          var padded = box
          padded.halfWidth += style.labelPadding * k
          padded.halfHeight += style.labelPadding * k
          for other in boxes where padded.overlaps(other) { count += 100 }
          for (p, q) in exteriorLines + exteriorWitnesses
          where padded.overlaps(convex: OrientedBox.around(p, q, halfWidth: 1e-4 * k).corners) {
            count += 100
          }
          boxes.append(box)
        }
        // No line crosses another dimension's lines.
        for (p, q) in exteriorWitnesses
        where AnnotationLayout.linesClash(candidate.line.0, candidate.line.1, p, q) {
          count += 1000
        }
        for (p, q) in exteriorLines {
          if AnnotationLayout.linesClash(candidate.line.0, candidate.line.1, p, q),
            !AnnotationLayout.cornerCrossing(
              candidate.line.0, candidate.line.1, p, q, reach: cornerReach)
          {
            count += 1000
          }
          for w in candidate.witnesses where AnnotationLayout.linesClash(w.0, w.1, p, q) {
            count += 1000
          }
        }
        // Nearer rows and labels on their line win when they are as free; each row further
        // out costs more than the last.
        let rows = max(0, candidate.distance / step)
        let cost =
          count + Int((25 * rows * rows * weight).rounded())
          + candidate.labels.filter { !$0.onLine }.count + (candidate.slid ? 1 : 0)
        if chosen == nil || cost < chosen!.cost { chosen = (candidate, count, cost) }
      }
      guard let pick = chosen?.candidate else { continue }
      // A short run whose dimension would cover or cross anything or stand far off (the sides
      // of a narrow recess, a step tucked under another dimension) is left out.
      if item.length < style.exteriorOptionalM,
        (chosen?.conflicts ?? 0) > 0 || pick.distance > 2.5 * step
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
      for (index, label) in pick.labels.enumerated() {
        add(
          centredText(
            texts[index], center: label.center, u: u, size: size, color: style.ink,
            layer: .exteriorDimension), .exteriorDimension)
        labels.append(
          PlacedLabel(
            kind: .exteriorDimension, text: texts[index],
            box: textBox(texts[index], center: label.center, u: u, size: size), roomId: nil))
        exteriorDimensions.append(
          ExteriorDimension(
            loop: item.loop, run: item.run, lengthM: pieces[index].1 - pieces[index].0,
            label: texts[index], tier: pick.tier + 1,
            placement: label.onLine ? "line" : "beside", crowded: (chosen?.conflicts ?? 0) > 0,
            conflictScore: chosen?.conflicts ?? 0, cost: index == 0 ? (chosen?.cost ?? 0) : 0,
            side: AnnotationLayout.sideKey(out), position: pick.position))
      }
      for (a, b) in pick.drawn + pick.witnesses where a.distance(to: b) > 1e-6 {
        lines.append(Obstacle(line: a, b, halfWidth: style.lineClearance * k))
      }
      exteriorLines.append(pick.line)
      exteriorWitnesses += pick.witnesses
    }
  }

  /// The building's overall width and its overall height, each once, on a row one step
  /// outside the dimensions of the side where its witness lines are shortest, when that side
  /// has two or more pieces and both ends of the building come out near its face. Left out
  /// where a piece already gives it, where it would cover or cross anything, or where a
  /// witness line could not reach its corner.
  mutating func placeOverallDimensions(walls: WallLayout) {
    let points = walls.loops.flatMap(\.outer)
    guard !points.isEmpty else { return }
    let size = style.exteriorDimensionSize * k
    let gap = style.labelGap * k
    let step = style.exteriorTierStep * k
    for d in [Point2(x: 1, y: 0), Point2(x: 0, y: 1)] {
      let u = AnnotationLayout.readingDirection(d)
      let low = points.map { $0.dot(d) }.min()!
      let high = points.map { $0.dot(d) }.max()!
      let length = high - low
      guard length > style.exteriorOptionalM else { continue }
      let label = units.dimension(length)
      // Not when a piece already gives it (one run spans the building).
      guard
        !exteriorDimensions.contains(where: {
          !$0.overall && abs($0.lengthM - length) < 0.0127
        })
      else { continue }
      struct Pick {
        var out: Point2
        var position: Double
        var line: (Point2, Point2)
        var witnesses: [(Point2, Point2)]
        var center: Point2
        var reach: Double
      }
      var best: Pick?
      for out in [d.leftNormal, d.rightNormal] {
        let key = AnnotationLayout.sideKey(out)
        let placed = exteriorDimensions.filter { $0.side == key && !$0.overall }
        guard placed.count >= 2 else { continue }
        // The outermost corner at each end of the building, seen from this side.
        func foot(_ s: Double) -> Point2 {
          points.filter { abs($0.dot(d) - s) < 0.01 }.max { $0.dot(out) < $1.dot(out) }!
        }
        let feet = [foot(low), foot(high)]
        let face = points.map { $0.dot(out) }.max()!
        // Only where both ends of the building come out near this side's face: a witness
        // line running far across the sheet to a corner set back from it reads as clutter.
        guard feet.allSatisfy({ face - $0.dot(out) <= 2 * step }) else { continue }
        var position =
          max(placed.map(\.position).max()!, face + style.exteriorOffset * k) + step
        var found: Pick?
        for _ in 0..<2 {
          defer { position += step }
          let ends = feet.map { $0 + out * (position - $0.dot(out)) }
          var witnesses: [(Point2, Point2)] = []
          var reachTotal = 0.0
          for (end, corner) in zip(ends, feet) {
            let height = position - corner.dot(out)
            // The witness line must reach its corner without running into the building.
            if let hit = AnnotationLayout.firstHit(
              from: end, direction: out * -1, within: height, building: building),
              hit < height - 0.01
            {
              witnesses = []
              break
            }
            witnesses.append((end - out * (height - gap), end))
            reachTotal += height
          }
          guard witnesses.count == 2 else { break }
          let line = (ends[0], ends[1])
          let own = ([line] + witnesses).map {
            OrientedBox.around($0.0, $0.1, halfWidth: style.lineClearance * k)
          }
          var clash = false
          for (p, q) in exteriorWitnesses
          where AnnotationLayout.linesClash(line.0, line.1, p, q) {
            clash = true
          }
          for (p, q) in exteriorLines {
            if AnnotationLayout.linesClash(line.0, line.1, p, q) { clash = true }
            for w in witnesses where AnnotationLayout.linesClash(w.0, w.1, p, q) { clash = true }
          }
          guard !clash else { continue }
          for t in [0.5, 0.4, 0.6, 0.3, 0.7] {
            let center = line.0 + (line.1 - line.0) * t
            let box = textBox(label, center: center, u: u, size: size)
            var padded = box
            padded.halfWidth += style.labelPadding * k
            padded.halfHeight += style.labelPadding * k
            let crossed = (exteriorLines + exteriorWitnesses).contains {
              padded.overlaps(convex: OrientedBox.around($0.0, $0.1, halfWidth: 1e-4 * k).corners)
            }
            guard !crossed,
              conflicts(box, padding: style.labelPadding * k, outside: true, ownLines: own) == 0
            else { continue }
            found = Pick(
              out: out, position: position, line: line, witnesses: witnesses, center: center,
              reach: reachTotal)
            break
          }
          if found != nil { break }
        }
        if let found, best == nil || found.reach < best!.reach - 1e-9 { best = found }
      }
      guard let pick = best else { continue }
      let width = FontMetrics.width(label, size: size)
      let along = (pick.line.1 - pick.line.0).unit
      let drawn = [
        (pick.line.0, pick.center - along * (width / 2 + gap)),
        (pick.center + along * (width / 2 + gap), pick.line.1),
      ]
      var path = PathBuilder()
      for (a, b) in drawn + pick.witnesses where a.distance(to: b) > 1e-6 { path.segment(a, b) }
      add(
        .shape(
          DrawingShape(
            path: path.path,
            stroke: DrawingStroke(color: style.ink, width: style.exteriorDimensionWidth * k * 1000),
            layer: .exteriorDimension)), .exteriorDimension)
      add(
        centredText(
          label, center: pick.center, u: u, size: size, color: style.ink,
          layer: .exteriorDimension), .exteriorDimension)
      labels.append(
        PlacedLabel(
          kind: .exteriorDimension, text: label,
          box: textBox(label, center: pick.center, u: u, size: size), roomId: nil))
      for (a, b) in drawn + pick.witnesses where a.distance(to: b) > 1e-6 {
        lines.append(Obstacle(line: a, b, halfWidth: style.lineClearance * k))
      }
      exteriorLines.append(pick.line)
      exteriorWitnesses += pick.witnesses
      exteriorDimensions.append(
        ExteriorDimension(
          loop: -1, run: -1, lengthM: length, label: label, tier: 0, placement: "line",
          crowded: false, conflictScore: 0, cost: 0, side: AnnotationLayout.sideKey(pick.out),
          position: pick.position, overall: true))
    }
  }

  // MARK: Interior dimensions

  /// Dimensions along the edges of each room, just inside it, measured between the wall faces.
  /// Every room first gets its overall length and width: its longest edge across the sheet and
  /// its longest edge up it, or a facing edge of the same length when a door swings across the
  /// first. Then the other edges, longest first. A label may sit over furniture, on a patch of
  /// the room's colour, but never over another label, a wall or a door swing; no line runs
  /// through a door swing (the length and width only when nothing else is free), and a line
  /// keeps off furniture where a free place lets it. Of two edges facing each other close by
  /// with the same length (the two faces of a short return) only one is dimensioned. A
  /// dimension that finds no place is left out.
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
      var length: Double { a.distance(to: b) }
    }
    var edges: [Edge] = []
    // Per room and direction, the edges of its overall length, best first.
    var overall: [[Int]] = []
    for (index, room) in rooms.enumerated() {
      let polygon = room.clear
      let first = edges.count
      for i in polygon.indices {
        let a = polygon[i]
        let b = polygon[(i + 1) % polygon.count]
        let length = a.distance(to: b)
        guard length >= style.interiorMinimumM else { continue }
        let label = units.dimension(length)
        let d = (b - a).unit
        // The other face of a short return: facing this one, close by, the same length.
        let twin = edges[first...].contains { other in
          let e = (other.b - other.a).unit
          guard e.dot(d) < -0.999, other.label == label else { return false }
          let distance = abs((other.a - a).cross(d))
          let s0 = min(other.a.dot(d), other.b.dot(d))
          let s1 = max(other.a.dot(d), other.b.dot(d))
          let overlap = min(s1, max(a.dot(d), b.dot(d))) - max(s0, min(a.dot(d), b.dot(d)))
          return distance < 0.5 && overlap > 0.5 * length
        }
        if !twin { edges.append(Edge(room: index, a: a, b: b, label: label)) }
      }
      for across in [true, false] {
        let candidates = (first..<edges.count).filter {
          let d = (edges[$0].b - edges[$0].a).unit
          return across ? abs(d.x) >= abs(d.y) : abs(d.x) < abs(d.y)
        }
        guard let longest = candidates.map({ edges[$0].length }).max() else { continue }
        let group = candidates.filter { edges[$0].length >= longest - 0.0127 }.sorted {
          edges[$0].length > edges[$1].length + 1e-9
            || (abs(edges[$0].length - edges[$1].length) <= 1e-9 && $0 < $1)
        }
        overall.append(group)
      }
    }

    struct Option {
      var center: Point2
      var lines: [(Point2, Point2)]
      var soft: Int
      var crossesSwing: Bool
    }
    // The best place for an edge's dimension: on the first row from the wall, else the second;
    // the label on the line or beside it.
    func bestOption(_ edge: Edge) -> Option? {
      let polygon = rooms[edge.room].clear
      let length = edge.length
      let d = (edge.b - edge.a).unit
      let inward = d.leftNormal
      let label = edge.label
      let width = FontMetrics.width(label, size: size)
      let u = AnnotationLayout.readingDirection(d)
      let stub = style.minimumStub * k
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
          // Furniture under the label, a little; under the line, less; a door swing under
          // either, most.
          let corners = padded.corners
          let extent = Extent(corners)
          var soft = tier
          for symbol in symbols where symbol.extent.overlaps(extent) {
            if Geo.convexOverlap(corners, symbol.polygon) { soft += 2 }
          }
          for line in own.prefix(own.count - 2) {
            let lineCorners = line.corners
            let lineExtent = Extent(lineCorners)
            for symbol in symbols
            where symbol.extent.overlaps(lineExtent)
              && Geo.convexOverlap(lineCorners, symbol.polygon, margin: 0.01)
            {
              soft += 1
            }
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
          if crossesSwing { soft += 20 }
          if best == nil || soft < best!.soft {
            best = Option(
              center: option.center, lines: option.lines, soft: soft,
              crossesSwing: crossesSwing)
          }
          if soft == 0 { break }
        }
        if let current = best, current.soft <= tier { break }
      }
      return best
    }

    func place(_ edge: Edge, _ pick: Option) {
      let label = edge.label
      let u = AnnotationLayout.readingDirection(edge.b - edge.a)
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

    // The overall length and width of each room first, on an edge no door swings across
    // when one of them is free.
    var placed = Set<Int>()
    for group in overall {
      var chosen: (index: Int, option: Option)?
      for index in group {
        guard let option = bestOption(edges[index]) else { continue }
        if !option.crossesSwing {
          chosen = (index, option)
          break
        }
        if chosen == nil { chosen = (index, option) }
      }
      if let chosen {
        place(edges[chosen.index], chosen.option)
        placed.insert(chosen.index)
      }
    }
    // Then the other edges, longest first.
    let order = edges.indices.filter { !placed.contains($0) }.sorted {
      edges[$0].length > edges[$1].length + 1e-9
        || (abs(edges[$0].length - edges[$1].length) <= 1e-9 && $0 < $1)
    }
    for index in order {
      guard let option = bestOption(edges[index]), !option.crossesSwing else {
        droppedInteriorDimensions += 1
        continue
      }
      place(edges[index], option)
    }
  }
}
