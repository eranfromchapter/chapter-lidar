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

// MARK: Room labels

extension AnnotationLayout {
  /// Plan sheet room label (plan-sheet §3.4): the name in capitals, Inter SemiBold 7.5 pt with
  /// 0.9 pt letter spacing, in ink, and under it the area, Inter 7.5 pt muted, its baseline
  /// 11.25 pt below the name's; both centred, no patch behind them. Placed as the colour
  /// Floorplan places its labels (`roomLabelPlace`), never smaller than 7.5 pt: a name too wide
  /// for its room wraps onto two lines (9 pt apart), then is cut with "...".
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
    func place(_ lines: [String]) -> Point2? {
      let b = box(lines)
      return roomLabelPlace(halfWidth: b.halfWidth, height: b.height, polygon: polygon)
    }
    var lines: [String] = []
    var center: Point2?
    if let name {
      var options = [[name]]
      if let split = SheetLabel.balancedSplit(name, measure: nameWidth) { options.append(split) }
      for candidate in options {
        if let found = place(candidate) {
          (lines, center) = (candidate, found)
          break
        }
      }
      if center == nil {
        // Cut short: the widest two lines that still find a place, keeping at least
        // `minimumNameCharacters` characters.
        let kept = String(name.prefix(AnnotationLayout.minimumNameCharacters))
        var low = nameWidth(kept + (kept.count < name.count ? "..." : ""))
        var high = nameWidth(name)
        let first = SheetLabel.wrapped(name, width: low, measure: nameWidth)
        if let found = place(first) {
          (lines, center) = (first, found)
          for _ in 0..<10 where high - low > 0.05 * k {
            let width = (low + high) / 2
            let candidate = SheetLabel.wrapped(name, width: width, measure: nameWidth)
            if let found = place(candidate) {
              (lines, center) = (candidate, found)
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
      center = place([])
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
