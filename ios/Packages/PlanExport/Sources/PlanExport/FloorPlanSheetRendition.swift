import CaptureContract
import Foundation

// The plan sheet rendition of `FloorPlanDrawing` (plan-sheet §3.4, artboard 1b): the same
// squared plan, walls and label placement as the colour Floorplan, drawn in the design-token
// palette with the sheet's line weights, symbols and dimensions. Sizes are given in paper points
// and drawn in plan millimetres at the drawing's scale.

extension FloorPlanDrawing {
  /// What the plan sheet rendition draws, in drawing order, and what it measured.
  struct SheetParts {
    var items: [DrawingItem]
    var labels: [PlacedLabel]
    var dimensions: [SheetDimension]
    var frame: PlanBounds?
    var classes: [String: RoomFillClass]
  }

  /// The plan sheet's drawing: room fills by class (hall fill in the colour of the room it opens
  /// to), object boxes and fixture symbols, walls in ink, window clears and their two lines,
  /// door and passage thresholds, capitalised room labels and the two tiers of outside
  /// dimensions. `geometry` and `rooms` are in the drawing frame; `rotation` is the turn
  /// (radians, counter-clockwise) from the capture's plan frame to it.
  static func sheetParts(
    model: CaptureModel, geometry: PlanGeometry, rooms: [DrawnRoom], walls: WallLayout,
    assumedWalls: WallLayout, symbols: [PlacedSymbol], options: Options, metrics: PlanMetrics,
    rotation: Double
  ) -> SheetParts {
    let n = options.scaleDenominator
    // Plan millimetres per paper point, and plan metres per paper point.
    let pt = 25.4 / 72 * n
    let pointM = pt / 1000
    let palette = ChapterBrand.Sheet.self
    var items: [DrawingItem] = []

    // Room classes.
    var classes: [String: RoomFillClass] = [:]
    var roomClasses: [RoomFillClass] = []
    for room in rooms {
      let source = model.rooms.first { $0.id == room.id }
      let objects = geometry.objects.filter { $0.roomId == room.id }.map(\.category)
      let fillClass = RoomFillClass.of(
        label: room.label, type: source?.type, objects: objects, mode: options.captureMode)
      classes[room.id] = fillClass
      roomClasses.append(fillClass)
    }

    // Floor left out between rooms behind an opening, in the fill of the room it opens to.
    let wallPieces = walls.pieces
    let hall = HallFill().regions(
      rooms: rooms.map(\.polygon), walls: wallPieces,
      openings: walls.gaps.filter { $0.opening.kind != .window }.map {
        ($0.a, $0.b, $0.normal, $0.lo, $0.hi)
      })
    for region in hall {
      var path = PathBuilder()
      for rect in region.rects { path.polygon(rect) }
      let fill = region.room.flatMap { roomClasses[$0].fill } ?? palette.ground
      items.append(.shape(DrawingShape(path: path.path, fill: fill, layer: .roomFill)))
    }
    // Room fills; an outdoor room is its dashed edge only.
    for (index, room) in rooms.enumerated() {
      var path = PathBuilder()
      path.polygon(room.polygon)
      if let fill = roomClasses[index].fill {
        items.append(.shape(DrawingShape(path: path.path, fill: fill, layer: .roomFill)))
      } else {
        items.append(
          .shape(
            DrawingShape(
              path: path.path,
              stroke: DrawingStroke(
                color: palette.muted, width: 0.6 * pt, dash: [4 * pt, 3 * pt]),
              layer: .roomFill)))
      }
    }

    // Objects: boxes (and the four fixture symbols) filled with the page colour and outlined
    // 0.6 pt muted, dashed 1.8 / 1.2 for a low-confidence detection (its inner lines solid),
    // lowest first; overhead and wall-hung objects last, as an unfilled solid box.
    let order = symbols.indices.sorted {
      let a = symbols[$0]
      let b = symbols[$1]
      if a.overhead != b.overhead { return !a.overhead }
      return a.top < b.top - 1e-9 || (abs(a.top - b.top) <= 1e-9 && $0 < $1)
    }
    let solid = DrawingStroke(color: palette.muted, width: 0.6 * pt)
    for index in order {
      let symbol = symbols[index]
      if symbol.overhead {
        var outline = PathBuilder()
        outline.polygon(symbol.footprint)
        items.append(.shape(DrawingShape(path: outline.path, stroke: solid, layer: .symbol)))
        continue
      }
      var outlineStroke = solid
      if symbol.lowConfidence { outlineStroke.dash = [1.8 * pt, 1.2 * pt] }
      if !symbol.outline.isEmpty {
        items.append(
          .shape(
            DrawingShape(
              path: symbol.outline.path, fill: palette.surface, stroke: outlineStroke,
              layer: .symbol)))
      }
      if !symbol.details.isEmpty {
        items.append(.shape(DrawingShape(path: symbol.details.path, stroke: solid, layer: .symbol)))
      }
    }

    // Walls: one path, nonzero, so overlapping pieces paint as their union.
    var wallPath = PathBuilder()
    for piece in wallPieces { wallPath.polygon(piece) }
    if !wallPath.isEmpty {
      items.append(.shape(DrawingShape(path: wallPath.path, fill: palette.ink, layer: .wall)))
    }

    // Openings: a window's piece of wall in the page colour with two 0.6 pt ink lines 2 pt apart;
    // a door's threshold along the wall's centre line, 0.4 pt muted, solid; an open passage's
    // dashed 2 / 2. No leaf, swing or jamb.
    var clears = PathBuilder()
    var glazing = PathBuilder()
    var doors = PathBuilder()
    var passages = PathBuilder()
    for gap in walls.gaps where gap.a.distance(to: gap.b) > 0.01 {
      let n = gap.normal
      let middle = (gap.lo + gap.hi) / 2
      switch gap.opening.kind {
      case .window:
        clears.polygon([
          gap.a + n * gap.lo, gap.b + n * gap.lo, gap.b + n * gap.hi, gap.a + n * gap.hi,
        ])
        for offset in [middle - pointM, middle + pointM] {
          glazing.segment(gap.a + n * offset, gap.b + n * offset)
        }
      case .door:
        doors.segment(gap.a + n * middle, gap.b + n * middle)
      case .opening:
        passages.segment(gap.a + n * middle, gap.b + n * middle)
      }
    }
    if !clears.isEmpty {
      items.append(.shape(DrawingShape(path: clears.path, fill: palette.surface, layer: .window)))
    }
    if !glazing.isEmpty {
      items.append(
        .shape(
          DrawingShape(
            path: glazing.path, stroke: DrawingStroke(color: palette.ink, width: 0.6 * pt),
            layer: .window)))
    }
    if !doors.isEmpty {
      items.append(
        .shape(
          DrawingShape(
            path: doors.path, stroke: DrawingStroke(color: palette.muted, width: 0.4 * pt),
            layer: .door)))
    }
    if !passages.isEmpty {
      items.append(
        .shape(
          DrawingShape(
            path: passages.path,
            stroke: DrawingStroke(color: palette.muted, width: 0.4 * pt, dash: [2 * pt, 2 * pt]),
            layer: .opening)))
    }

    // Room labels.
    let building = walls.loops.filter { $0.closed && Geo.signedArea($0.outer) > 0 }.map(\.outer)
    var layout = AnnotationLayout(
      style: FloorPlanStyle(), units: options.units, scaleDenominator: n,
      symbols: symbols.filter { !$0.overhead }.map(\.footprint),
      fixtures: symbols.filter { !$0.overhead && $0.isFixture }.map(\.footprint),
      building: building, wallPieces: wallPieces)
    // No patch behind a sheet label: it keeps off every object's outline, overhead ones too.
    layout.outlines = symbols.map { Obstacle($0.footprint) }
    if options.roomNames || options.roomAreas {
      for room in rooms {
        layout.placeSheetRoomLabel(
          roomId: room.id, name: options.roomNames ? room.label : nil,
          area: options.roomAreas ? UnitFormatter.sheetArea(room.areaM2) : nil,
          polygon: room.clear.count >= 3 ? room.clear : room.polygon)
      }
    }
    items += layout.items[.roomLabel] ?? []

    // Dimension strings.
    var dimensions: [SheetDimension] = []
    var frame: PlanBounds?
    if options.exteriorDimensions {
      let placed = PlanSheetDimensions.place(
        rooms: rooms, assumedWalls: assumedWalls, metrics: metrics, rotation: rotation,
        scaleDenominator: n)
      items += placed.items
      dimensions = placed.dimensions
      frame = placed.frame
    }
    return SheetParts(
      items: items, labels: layout.labels, dimensions: dimensions, frame: frame,
      classes: classes)
  }
}

// MARK: Openings through every wall

extension WallLayout {
  /// Parallel bands this close to an opening's wall (plan metres) are part of it.
  static let throughJoin = 0.05
  /// The thickest wall an opening is cut through, plan metres.
  static let throughLimit = 0.6
  /// A band this close to square with an opening's wall (cosine) runs across the opening.
  static let acrossCosine = cos(10 * Double.pi / 180)

  /// The plan sheet draws a door as a gap in its wall and no swing (plan-sheet §3.4), so a
  /// doorway must be open through the whole wall. Where two rooms lie about a wall's thickness
  /// apart, each draws its own band on its own edge and the two overlap; `cut(for:)` opens only
  /// the band the opening lies in, and the other band would stay solid across the doorway.
  /// This also cuts, over each opening's span, every band parallel to it that overlaps its
  /// band (or a band already cut, within `throughJoin`) as long as the wall stays within
  /// `throughLimit`, and moves the gap's faces (`lo`, `hi`) out to the outermost faces cut, so
  /// a threshold or window lines sit in the middle of the whole wall. A wall running across
  /// the opening inside its span (one that meets it between the jambs) stops at the opening's
  /// faces. The colour Floorplan does not use it: its door swings show every doorway.
  mutating func cutOpeningsThrough() {
    for index in gaps.indices {
      let gap = gaps[index]
      guard let host = gap.segment else { continue }
      let width = gap.a.distance(to: gap.b)
      guard width > 0.01 else { continue }
      let u = (gap.b - gap.a).unit
      let n = gap.normal
      var low = gap.lo
      var high = gap.hi
      var taken: Set<Int> = [host]
      var grew = true
      while grew {
        grew = false
        for (other, segment) in segments.enumerated()
        where !taken.contains(other) && segment.length > 0 {
          guard abs(segment.direction.cross(u)) < WallLayout.parallelSine else { continue }
          // The band's span along the opening, and its faces across it at the opening's ends.
          let q0 = segment.parameter(gap.a)
          let q1 = segment.parameter(gap.b)
          let t0 = max(0, min(q0, q1))
          let t1 = min(1, max(q0, q1))
          guard (t1 - t0) * segment.length > 0.01 else { continue }
          let faces = [t0, t1].flatMap { t in
            [segment.lo, segment.hi].map { (segment.point(t, $0) - gap.a).dot(n) }
          }
          let bandLow = faces.min()!
          let bandHigh = faces.max()!
          guard bandHigh >= low - WallLayout.throughJoin,
            bandLow <= high + WallLayout.throughJoin,
            max(high, bandHigh) - min(low, bandLow) <= WallLayout.throughLimit
          else { continue }
          taken.insert(other)
          low = min(low, bandLow)
          high = max(high, bandHigh)
          segments[other].cuts.append((t0, t1))
          grew = true
        }
      }
      // Walls across the opening that reach into it between its jambs end at its faces.
      for (other, segment) in segments.enumerated()
      where !taken.contains(other) && segment.length > 0 {
        guard abs(segment.direction.dot(n)) > WallLayout.acrossCosine else { continue }
        let along = segment.band.map { ($0 - gap.a).dot(u) }
        guard min(along.max()!, width) - max(along.min()!, 0) > 0.01 else { continue }
        let q0 = segment.parameter(gap.a + n * low)
        let q1 = segment.parameter(gap.a + n * high)
        let t0 = max(0, min(q0, q1))
        let t1 = min(1, max(q0, q1))
        if t1 > t0 { segments[other].cuts.append((t0, t1)) }
      }
      gaps[index].lo = low
      gaps[index].hi = high
    }
  }
}

// MARK: Room labels

extension AnnotationLayout {
  /// Plan sheet room label (plan-sheet §3.4): the name in capitals, Inter SemiBold 7.5 pt with
  /// 0.9 pt letter spacing, in ink, and under it the area, Inter 7.5 pt muted, its baseline
  /// 11.25 pt below the name's; both centred, no patch behind them. Placed as the colour
  /// Floorplan places its labels (`roomLabelPlace`), never smaller than 7.5 pt: a name too wide
  /// for its room wraps onto two lines (9 pt apart), then is cut with "...". With no patch, the
  /// lines themselves (not their bounding box) keep off fixtures and off every object's
  /// outline, and a name goes on two lines when that covers less than one.
  mutating func placeSheetRoomLabel(roomId: String, name: String?, area: String?, polygon: [Point2])
  {
    let name = name.map {
      Format.singleLine($0).trimmingCharacters(in: .whitespaces)
        .uppercased(with: Locale(identifier: "en_US_POSIX"))
    }.flatMap { $0.isEmpty ? nil : $0 }
    let area = area.flatMap { $0.isEmpty ? nil : $0 }
    guard name != nil || area != nil, polygon.count >= 3 else { return }
    let pointM = 25.4 / 72 * k
    let size = SheetLabel.size * pointM
    let tracking = SheetLabel.tracking * pointM
    func nameWidth(_ text: String) -> Double {
      FontMetrics.width(text, size: size, font: .interSemiBold)
        + tracking * Double(max(0, text.unicodeScalars.count - 1))
    }
    let areaWidth = area.map { FontMetrics.width($0, size: size, font: .interRegular) } ?? 0
    // Cap height of the first line to the descender of the last.
    func box(_ lines: [String]) -> (halfWidth: Double, height: Double) {
      let width = max(lines.map(nameWidth).max() ?? 0, areaWidth)
      var height = (0.727 + 0.22) * size
      if !lines.isEmpty { height += SheetLabel.nameAdvance * pointM * Double(lines.count - 1) }
      if !lines.isEmpty, area != nil { height += SheetLabel.areaDrop * pointM }
      return (width / 2, height)
    }
    // The label's outline: each line's glyph box (cap height to descender) and, between two
    // lines, a box as wide as the narrower of them. Without a patch behind it the label is kept
    // off object outlines by its lines, not by its bounding box, so in a small room it can sit
    // with a short area line beside a fixture its wider name clears.
    func parts(_ lines: [String]) -> [LabelPart] {
      let top = box(lines).height / 2
      var rows: [(baseline: Double, halfWidth: Double)] = []
      var baseline = top - 0.727 * size
      for line in lines {
        rows.append((baseline, nameWidth(line) / 2))
        baseline -= SheetLabel.nameAdvance * pointM
      }
      if area != nil {
        let areaBaseline =
          rows.last.map { $0.baseline - SheetLabel.areaDrop * pointM } ?? top - 0.727 * size
        rows.append((areaBaseline, areaWidth / 2))
      }
      var out: [LabelPart] = []
      for (index, row) in rows.enumerated() {
        let upper = row.baseline + 0.727 * size
        let lower = row.baseline - 0.22 * size
        out.append(
          LabelPart(
            dy: (upper + lower) / 2, halfWidth: row.halfWidth, halfHeight: (upper - lower) / 2))
        guard index + 1 < rows.count else { continue }
        let next = rows[index + 1]
        let nextUpper = next.baseline + 0.727 * size
        if lower > nextUpper {
          out.append(
            LabelPart(
              dy: (lower + nextUpper) / 2, halfWidth: min(row.halfWidth, next.halfWidth),
              halfHeight: (lower - nextUpper) / 2))
        }
      }
      return out
    }
    // Where the label goes and how much it covers there. In a crowded room, where the first
    // search finds no free place, a second one on a grid about a point fine looks for a gap the
    // first stepped over.
    func place(_ lines: [String]) -> (point: Point2, hits: Int)? {
      let shape = parts(lines)
      guard let first = roomLabelSearch(parts: shape, polygon: polygon) else { return nil }
      guard first.hits > 0 else { return first }
      let xs = polygon.map(\.x)
      let ys = polygon.map(\.y)
      let across = max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
      let fine = min(SheetLabel.fineGrid, Int((across / pointM).rounded(.up)))
      guard fine > 28,
        let second = roomLabelSearch(parts: shape, polygon: polygon, grid: fine),
        second.hits < first.hits
      else { return first }
      return second
    }
    var lines: [String] = []
    var center: Point2?
    if let name {
      // On one line, or on two when that covers less.
      var options = [[name]]
      if let split = SheetLabel.balancedSplit(name, measure: nameWidth) { options.append(split) }
      var fewest: Int?
      for candidate in options {
        guard let found = place(candidate) else { continue }
        if fewest.map({ found.hits < $0 }) ?? true {
          fewest = found.hits
          (lines, center) = (candidate, found.point)
        }
        if found.hits == 0 { break }
      }
      if center == nil {
        // Cut short: the widest two lines that still find a place, keeping at least
        // `minimumNameCharacters` characters.
        let kept = String(name.prefix(AnnotationLayout.minimumNameCharacters))
        var low = nameWidth(kept + (kept.count < name.count ? "..." : ""))
        var high = nameWidth(name)
        let first = SheetLabel.wrapped(name, width: low, measure: nameWidth)
        if let found = place(first) {
          (lines, center) = (first, found.point)
          for _ in 0..<10 where high - low > 0.05 * k {
            let width = (low + high) / 2
            let candidate = SheetLabel.wrapped(name, width: width, measure: nameWidth)
            if let found = place(candidate) {
              (lines, center) = (candidate, found.point)
              low = width
            } else {
              high = width
            }
          }
        } else {
          lines = [SheetLabel.cut(name, width: low, measure: nameWidth)]
        }
      }
    } else {
      center = place([])?.point
    }
    let block = box(lines)
    let middle = center ?? PlanGeometry.labelPoint(of: polygon)
    let top = middle.y + block.height / 2
    var baseline = top - 0.727 * size
    for line in lines {
      add(
        .text(
          DrawingText(
            line, position: PathBuilder.mm(Point2(x: middle.x, y: baseline)), size: size * 1000,
            anchor: .center, font: .interSemiBold, letterSpacing: tracking * 1000,
            color: ChapterBrand.Sheet.ink, layer: .roomLabel)),
        .roomLabel)
      baseline -= SheetLabel.nameAdvance * pointM
    }
    if let area {
      let areaBaseline =
        lines.isEmpty
        ? top - 0.727 * size
        : baseline + (SheetLabel.nameAdvance - SheetLabel.areaDrop) * pointM
      add(
        .text(
          DrawingText(
            area, position: PathBuilder.mm(Point2(x: middle.x, y: areaBaseline)),
            size: size * 1000, anchor: .center, font: .interRegular,
            color: ChapterBrand.Sheet.muted, layer: .roomLabel)),
        .roomLabel)
    }
    labels.append(
      PlacedLabel(
        kind: .room, text: (lines + (area.map { [$0] } ?? [])).joined(separator: "\n"),
        box: OrientedBox(
          center: middle, u: Point2(x: 1, y: 0), halfWidth: block.halfWidth,
          halfHeight: block.height / 2),
        roomId: roomId))
  }
}

/// Sizes and text helpers of the plan sheet's room labels (points).
enum SheetLabel {
  static let size = 7.5
  static let tracking = 0.9
  /// Between the baselines of two name lines.
  static let nameAdvance = 9.0
  /// From the last name baseline to the area baseline.
  static let areaDrop = 11.25
  /// Most steps across a room of the second, fine search for a crowded label.
  static let fineGrid = 120

  /// The name split at the space that makes the longer line shortest; nil without a space.
  static func balancedSplit(_ name: String, measure: (String) -> Double) -> [String]? {
    let characters = Array(name)
    var best: (lines: [String], longer: Double)?
    for index in characters.indices where characters[index] == " " {
      let first = String(characters[..<index]).trimmingCharacters(in: .whitespaces)
      let second = String(characters[(index + 1)...]).trimmingCharacters(in: .whitespaces)
      guard !first.isEmpty, !second.isEmpty else { continue }
      let longer = max(measure(first), measure(second))
      if best.map({ longer < $0.longer }) ?? true { best = ([first, second], longer) }
    }
    return best?.lines
  }

  /// `text` cut with "..." to fit `width`, or whole when it fits.
  static func cut(_ text: String, width: Double, measure: (String) -> Double) -> String {
    guard measure(text) > width else { return text }
    var characters = Array(text)
    while !characters.isEmpty {
      characters.removeLast()
      let shorter = String(characters).trimmingCharacters(in: .whitespaces) + "..."
      if measure(shorter) <= width { return shorter }
    }
    return "..."
  }

  /// The name on at most two lines no wider than `width`: whole when it fits, else broken
  /// after the last word that fits (or mid-word), the rest cut with "...".
  static func wrapped(_ name: String, width: Double, measure: (String) -> Double) -> [String] {
    guard measure(name) > width else { return [name] }
    let characters = Array(name)
    var count = 0
    while count < characters.count, measure(String(characters[...count])) <= width {
      count += 1
    }
    count = max(1, count)
    if count < characters.count, characters[count] != " ",
      let space = characters[..<count].lastIndex(of: " "), space > 0
    {
      count = space
    }
    let first = String(characters[..<count]).trimmingCharacters(in: .whitespaces)
    let rest = String(characters[count...]).trimmingCharacters(in: .whitespaces)
    guard !rest.isEmpty else { return [first] }
    return [first, cut(rest, width: width, measure: measure)]
  }
}
