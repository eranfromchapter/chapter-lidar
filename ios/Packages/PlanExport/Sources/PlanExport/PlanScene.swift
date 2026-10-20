import CaptureContract
import Foundation

/// Layers of the drawn plan. Raw values are the layer names shared with the DXF where one exists.
enum SceneLayer: String, Sendable {
  case area = "A-AREA"
  case wall = "A-WALL"
  case door = "A-DOOR"
  case glazing = "A-GLAZ"
  case opening = "A-OPEN"
  case annotation = "A-ANNO-TEXT"
  case object = "A-FLOR-OBJ"
  case dimension = "A-ANNO-DIMS"
  case scaleBar = "A-ANNO-SCALE"
  /// White strokes that open a gap in a wall for a door, window or opening.
  case gap = "A-GAP"
}

enum TextAnchor: Sendable {
  case leading
  case center
}

/// A drawing in paper millimetres (x right, y up) at a chosen scale. Every renderer (PDF, SVG,
/// PNG) draws the same scene, so the previews match the printed plan. Line widths and text sizes
/// are paper sizes and do not change with the scale; plan lengths are metres * 1000 / scale.
struct PlanScene: Sendable {
  enum Item: Sendable {
    case polyline(
      points: [Point2], closed: Bool, fillGray: Double?, strokeGray: Double?, widthMM: Double,
      layer: SceneLayer)
    /// `sizeMM` is the font size (em). `at` is the baseline start or baseline centre.
    case text(
      String, at: Point2, sizeMM: Double, rotationDegrees: Double, anchor: TextAnchor, bold: Bool,
      gray: Double, layer: SceneLayer)
  }

  var items: [Item] = []
  /// Scene extent including the margin that holds dimension strings.
  var widthMM: Double
  var heightMM: Double
  var scaleDenominator: Int

  /// Margin around the plan for dimension strings and the scale bar, paper millimetres.
  static let margin = 16.0
  /// Paper widths, millimetres.
  static let wallWidth = 0.5
  static let scaleBarWidth = 0.4
  static let dimensionOffset = 7.0
  /// Gray of the room fills: the lightest gray in the scene below white (paper and wall gaps).
  static let roomFillGray = 0.95

  // MARK: Building

  static func build(
    geometry: PlanGeometry, scaleDenominator: Int, units: DisplayUnitSystem,
    includeScaleBar: Bool
  ) throws -> PlanScene {
    guard let bounds = geometry.bounds else { throw PlanExportError.noPlanGeometry }
    let k = 1000.0 / Double(scaleDenominator)
    func paper(_ p: Point2) -> Point2 {
      Point2(x: (p.x - bounds.minX) * k + margin, y: (p.y - bounds.minY) * k + margin)
    }
    var scene = PlanScene(
      widthMM: bounds.width * k + 2 * margin, heightMM: bounds.height * k + 2 * margin,
      scaleDenominator: scaleDenominator)
    func polyline(
      _ points: [Point2], closed: Bool = false, fill: Double? = nil, stroke: Double? = 0,
      width: Double, layer: SceneLayer
    ) {
      scene.items.append(
        .polyline(
          points: points, closed: closed, fillGray: fill, strokeGray: stroke, widthMM: width,
          layer: layer))
    }
    func text(
      _ value: String, at: Point2, size: Double, rotation: Double = 0,
      anchor: TextAnchor = .center, bold: Bool = false, gray: Double = 0, layer: SceneLayer
    ) {
      scene.items.append(
        .text(
          value, at: at, sizeMM: size, rotationDegrees: rotation, anchor: anchor, bold: bold,
          gray: gray, layer: layer))
    }

    let roomsById = Dictionary(geometry.rooms.map { ($0.id, $0) }) { first, _ in first }

    for room in geometry.rooms {
      polyline(
        room.polygon.map(paper), closed: true, fill: roomFillGray, stroke: nil, width: 0,
        layer: .area)
    }
    for object in geometry.objects {
      polyline(
        object.corners.map(paper), closed: true, stroke: 0.45, width: 0.15, layer: .object)
    }
    for wall in geometry.walls where wall.length > 0 {
      if wall.thickness > 0 {
        let normal = (wall.end - wall.start).unit.leftNormal * (wall.thickness / 2)
        polyline(
          [wall.start + normal, wall.end + normal, wall.end - normal, wall.start - normal]
            .map(paper),
          closed: true, fill: 0.8, stroke: 0, width: 0.2, layer: .wall)
      } else {
        polyline([paper(wall.start), paper(wall.end)], width: wallWidth, layer: .wall)
      }
    }

    for opening in geometry.openings {
      let from = paper(opening.from)
      let to = paper(opening.to)
      let along = (to - from).unit
      let across = along.leftNormal
      let half = max(0.5, opening.wallThickness * k / 2)
      // Gap in the wall.
      polyline(
        [from, to], stroke: 1, width: max(1.0, 2 * half + 0.4), layer: .gap)
      switch opening.kind {
      case .door:
        // Leaf: a line from the hinge (span start) swung 90 degrees into the room side.
        var side = 1.0
        if let id = opening.roomIds.first, let room = roomsById[id] {
          let middle = (from + to) * 0.5
          side = across.dot(paper(room.labelPoint) - middle) >= 0 ? 1 : -1
        }
        let radius = from.distance(to: to)
        let leafEnd = from + across * (side * radius)
        polyline([from, leafEnd], width: 0.25, layer: .door)
        let startAngle = atan2(along.y, along.x)
        var points: [Point2] = []
        for step in 0...16 {
          let angle = startAngle + side * (Double.pi / 2) * Double(step) / 16
          points.append(
            Point2(x: from.x + radius * cos(angle), y: from.y + radius * sin(angle)))
        }
        polyline(points, width: 0.15, layer: .door)
      case .window:
        for offset in [-half * 0.5, half * 0.5] {
          polyline(
            [from + across * offset, to + across * offset], width: 0.2, layer: .glazing)
        }
        polyline([from - across * half, from + across * half], width: 0.2, layer: .glazing)
        polyline([to - across * half, to + across * half], width: 0.2, layer: .glazing)
      case .opening:
        polyline([from - across * half, from + across * half], width: 0.25, layer: .opening)
        polyline([to - across * half, to + across * half], width: 0.25, layer: .opening)
      }
    }

    for room in geometry.rooms {
      let at = paper(room.labelPoint)
      text(room.label, at: Point2(x: at.x, y: at.y + 1.0), size: 3.2, bold: true, layer: .annotation)
      text(
        "\(Format.fixed(room.areaM2, 2)) m\u{00B2}",
        at: Point2(x: at.x, y: at.y - 2.6), size: 2.4, gray: 0.25, layer: .annotation)
    }
    for object in geometry.objects {
      // Label inside the footprint's top-left corner so it stays clear of the room label.
      let corners = object.corners.map(paper)
      let left = corners.map(\.x).min() ?? 0
      let top = corners.map(\.y).max() ?? 0
      text(
        object.category.rawValue.replacingOccurrences(of: "_", with: " "),
        at: Point2(x: left + 1, y: top - 2.4), size: 1.8, anchor: .leading, gray: 0.35,
        layer: .object)
    }

    // Dimension strings on every wall that bounds at most one room.
    for wall in geometry.walls where wall.length > 0 && wall.roomIds.count <= 1 {
      let a = paper(wall.start)
      let b = paper(wall.end)
      let paperLength = a.distance(to: b)
      let label = Format.length(metres: wall.length, units: units)
      let size = 2.2
      let labelWidth = FontMetrics.width(label, size: size) * 25.4 / 72
      guard paperLength >= labelWidth + 2 else { continue }
      let along = (b - a).unit
      let normal = along.leftNormal
      // Offset away from the room the wall bounds.
      var side = 1.0
      let probe = max(0.05, wall.thickness / 2 + 0.05)
      let middle = (wall.start + wall.end) * 0.5
      let planNormal = (wall.end - wall.start).unit.leftNormal
      if let id = wall.roomIds.first, let room = roomsById[id] {
        let plus = PlanGeometry.contains(room.polygon, middle + planNormal * probe)
        let minus = PlanGeometry.contains(room.polygon, middle - planNormal * probe)
        if plus && !minus { side = -1 } else if minus && !plus { side = 1 }
      }
      let offset = normal * (side * dimensionOffset)
      let lineA = a + offset
      let lineB = b + offset
      let thin = 0.12
      polyline([lineA, lineB], width: thin, layer: .dimension)
      for (anchor, end) in [(a, lineA), (b, lineB)] {
        let gap = normal * (side * 1.5)
        polyline([anchor + gap, end + normal * (side * 1.5)], width: thin, layer: .dimension)
        let tick = (along + normal * side).unit * 0.9
        polyline([end - tick, end + tick], width: 0.25, layer: .dimension)
      }
      var angle = atan2(along.y, along.x) * 180 / .pi
      if angle > 90 { angle -= 180 } else if angle <= -90 { angle += 180 }
      let radians = angle * .pi / 180
      let up = Point2(x: -sin(radians), y: cos(radians))
      let middleLine = (lineA + lineB) * 0.5
      text(
        label, at: middleLine + up * 0.5, size: size, rotation: angle, layer: .dimension)
    }

    if includeScaleBar {
      scene.items += scaleBarItems(
        scaleDenominator: scaleDenominator, origin: Point2(x: margin, y: 3))
    }
    return scene
  }

  // MARK: Scale bar

  /// Length of the scale bar on paper, millimetres.
  static let scaleBarPaperLength = 40.0
  /// Divisions of the scale bar.
  static let scaleBarDivisions = 4

  /// Scale bar metres: 2 m at 1:50, 4 m at 1:100, 8 m at 1:200, 20 m at 1:500.
  static func scaleBarMetres(scaleDenominator: Int) -> Double {
    scaleBarPaperLength * Double(scaleDenominator) / 1000
  }

  /// Scale bar with its left end at `origin` (paper mm): a baseline `scaleBarPaperLength` long,
  /// division ticks and labels in metres.
  static func scaleBarItems(scaleDenominator: Int, origin: Point2) -> [Item] {
    let metres = scaleBarMetres(scaleDenominator: scaleDenominator)
    var items: [Item] = []
    items.append(
      .polyline(
        points: [origin, Point2(x: origin.x + scaleBarPaperLength, y: origin.y)], closed: false,
        fillGray: nil, strokeGray: 0, widthMM: scaleBarWidth, layer: .scaleBar))
    for step in 0...scaleBarDivisions {
      let x = origin.x + scaleBarPaperLength * Double(step) / Double(scaleBarDivisions)
      let tall = step == 0 || step == scaleBarDivisions
      items.append(
        .polyline(
          points: [Point2(x: x, y: origin.y), Point2(x: x, y: origin.y + (tall ? 2.0 : 1.2))],
          closed: false, fillGray: nil, strokeGray: 0, widthMM: 0.2, layer: .scaleBar))
      let value = metres * Double(step) / Double(scaleBarDivisions)
      let label = step == scaleBarDivisions ? "\(Format.compact(value)) m" : Format.compact(value)
      items.append(
        .text(
          label, at: Point2(x: x, y: origin.y + 2.6), sizeMM: 2.0, rotationDegrees: 0,
          anchor: .center, bold: false, gray: 0, layer: .scaleBar))
    }
    return items
  }
}

enum PaperSize: String, Sendable {
  case letter = "Letter"
  case a3 = "A3"

  /// Portrait size, millimetres.
  var portrait: (width: Double, height: Double) {
    switch self {
    case .letter: return (215.9, 279.4)
    case .a3: return (297, 420)
    }
  }
}

/// Sheet and scale for a plan: 1:50 or 1:100 on Letter or A3, whichever fits first (finest scale
/// first, Letter before A3, the orientation that matches the plan's shape first). Larger plans
/// fall back to 1:200 and 1:500 on A3 and say so in the title block.
struct PlanSheet: Sendable {
  var paper: PaperSize
  var landscape: Bool
  var scaleDenominator: Int

  static let scales = [50, 100, 200, 500]
  static let pageMargin = 10.0
  static let headerHeight = 12.0
  static let titleBlockHeight = 38.0
  static let gap = 3.0

  var widthMM: Double { landscape ? paper.portrait.height : paper.portrait.width }
  var heightMM: Double { landscape ? paper.portrait.width : paper.portrait.height }

  /// Area available for the scene, paper millimetres from the page's bottom-left corner.
  var drawingArea: (x: Double, y: Double, width: Double, height: Double) {
    let x = PlanSheet.pageMargin
    let y = PlanSheet.pageMargin + PlanSheet.titleBlockHeight + PlanSheet.gap
    return (
      x, y, widthMM - 2 * PlanSheet.pageMargin,
      heightMM - y - PlanSheet.pageMargin - PlanSheet.headerHeight
    )
  }

  static func choose(bounds: PlanBounds) throws -> PlanSheet {
    for scale in scales {
      let k = 1000.0 / Double(scale)
      let width = bounds.width * k + 2 * PlanScene.margin
      let height = bounds.height * k + 2 * PlanScene.margin
      for paper in [PaperSize.letter, .a3] {
        let landscapeFirst = width >= height
        for landscape in [landscapeFirst, !landscapeFirst] {
          let sheet = PlanSheet(paper: paper, landscape: landscape, scaleDenominator: scale)
          let area = sheet.drawingArea
          if width <= area.width && height <= area.height { return sheet }
        }
      }
    }
    throw PlanExportError.planTooLarge
  }
}
