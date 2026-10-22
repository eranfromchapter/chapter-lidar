import CaptureContract
import Foundation

/// One dimension string of the plan sheet's drawing, plan metres in the drawing frame.
struct SheetDimension: Sendable {
  enum Side: String, CaseIterable, Sendable {
    case top
    case bottom
    case left
    case right
  }

  var side: Side
  /// 1: a room's dimension; 2: the building's overall width (top) or depth (left).
  var tier: Int
  /// The span the line covers: x for top and bottom, y for left and right.
  var from: Double
  var to: Double
  /// Where the line runs: y for top and bottom, x for left and right.
  var line: Double
  /// The length printed, metres.
  var valueM: Double
  var text: String
  /// The room measured (tier 1).
  var roomId: String?

  var spanM: Double { to - from }
}

/// The plan sheet's dimension strings (plan-sheet §3.4.2, "overall width and depth outside, room
/// dimensions inside", both tiers outside the building):
///
/// - `B` is the axis-aligned box of the wall pieces and room outlines at the assumed wall
///   thicknesses (4.5 in inside, 6 in outside; the 2 pt drawing minimum never changes a value).
/// - Tier 1, on every side, 12 pt outside `B`: each room whose own box edge on that side lies
///   within the exterior thickness + 0.30 m of `B`'s edge, spanning the room outline's extent
///   along the side. Spans shorter than 0.6 m or than their text + 4 pt are dropped; of two
///   that overlap by more than 0.05 m the one nearer the side is kept (tie: the longer). The
///   value printed is the room's `RoomMetrics.boundingBox` side running closest to that sheet
///   axis, so the sheet prints the spatial report's room schedule numbers.
/// - Tier 2, 33 pt outside `B`, on the top and left only: `B`'s width and depth.
/// - Lines 0.4 pt ink with 5 pt end ticks of 0.6 pt, no witness lines; text Courier 8.25 pt ink
///   centred on the span: 2.5 pt above a top line, baseline 10.75 pt below a bottom line,
///   turned +90 degrees (reading up) 2.5 pt left of a left line and 10.75 pt right of a right
///   line, so it always sits on the side away from the building. Feet-inches to 0.1 in
///   (`UnitFormatter.dimension`).
enum PlanSheetDimensions {
  /// Points.
  static let roomTier = 12.0
  static let overallTier = 33.0
  static let lineWidth = 0.4
  static let tickLength = 5.0
  static let tickWidth = 0.6
  static let textSize = 8.25
  static let nearGap = 2.5
  static let farGap = 10.75
  static let textClearance = 4.0
  /// Metres.
  static let minimumSpanM = 0.6
  static let overlapM = 0.05
  static let sideReachM = 0.30

  static let formatter = UnitFormatter(system: .imperial)

  static func place(
    rooms: [FloorPlanDrawing.DrawnRoom], assumedWalls: WallLayout, metrics: PlanMetrics,
    rotation: Double, scaleDenominator n: Double
  ) -> (items: [DrawingItem], dimensions: [SheetDimension], frame: PlanBounds?) {
    let pointM = 25.4 / 72 * n / 1000
    let points =
      assumedWalls.pieces.flatMap { $0 } + rooms.filter { $0.polygon.count >= 3 }.flatMap(\.polygon)
    guard let first = points.first else { return ([], [], nil) }
    var frame = PlanBounds(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
    for p in points { frame.grow(p) }

    var dimensions: [SheetDimension] = []
    let reach = assumedWalls.exteriorThickness + sideReachM
    for side in SheetDimension.Side.allCases {
      struct Candidate {
        var from: Double
        var to: Double
        var distance: Double
        var dimension: SheetDimension
      }
      var candidates: [Candidate] = []
      for room in rooms where room.polygon.count >= 3 {
        guard let measured = metrics.rooms.first(where: { $0.roomId == room.id }) else { continue }
        let xs = room.polygon.map(\.x)
        let ys = room.polygon.map(\.y)
        let (minX, maxX, minY, maxY) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        let distance: Double
        let span: (Double, Double)
        switch side {
        case .top: (distance, span) = (frame.maxY - maxY, (minX, maxX))
        case .bottom: (distance, span) = (minY - frame.minY, (minX, maxX))
        case .left: (distance, span) = (minX - frame.minX, (minY, maxY))
        case .right: (distance, span) = (frame.maxX - maxX, (minY, maxY))
        }
        guard distance <= reach + 1e-9 else { continue }
        let length = span.1 - span.0
        let value = Self.value(of: measured, side: side, rotation: rotation)
        let text = formatter.dimension(value)
        let textWidth = FontMetrics.width(text, size: textSize, font: .courier)
        guard length >= minimumSpanM, length / pointM >= textWidth + textClearance else {
          continue
        }
        candidates.append(
          Candidate(
            from: span.0, to: span.1, distance: distance,
            dimension: SheetDimension(
              side: side, tier: 1, from: span.0, to: span.1,
              line: Self.line(side: side, frame: frame, offset: roomTier * pointM),
              valueM: value, text: text, roomId: room.id)))
      }
      // Nearer the side first, then the longer; a span overlapping a kept one by more than
      // 0.05 m is dropped.
      let ranked = candidates.sorted {
        if abs($0.distance - $1.distance) > 1e-9 { return $0.distance < $1.distance }
        return $0.to - $0.from > $1.to - $1.from
      }
      var kept: [Candidate] = []
      for candidate in ranked {
        let clashes = kept.contains {
          min($0.to, candidate.to) - max($0.from, candidate.from) > overlapM
        }
        if !clashes { kept.append(candidate) }
      }
      dimensions += kept.sorted { $0.from < $1.from }.map(\.dimension)
    }
    // Tier 2: overall width on the top, depth on the left.
    for side in [SheetDimension.Side.top, .left] {
      let horizontal = side == .top
      let value = horizontal ? frame.width : frame.height
      dimensions.append(
        SheetDimension(
          side: side, tier: 2, from: horizontal ? frame.minX : frame.minY,
          to: horizontal ? frame.maxX : frame.maxY,
          line: Self.line(side: side, frame: frame, offset: overallTier * pointM), valueM: value,
          text: formatter.dimension(value), roomId: nil))
    }
    return (items(dimensions, pointM: pointM), dimensions, frame)
  }

  /// The room's bounding-box side that runs closest to the side's sheet axis: `alongM` when the
  /// room frame, turned into the drawing frame, is within 45 degrees of it, else `acrossM`.
  static func value(of room: RoomMetrics, side: SheetDimension.Side, rotation: Double) -> Double {
    var angle = (room.boundingBox.angleRadians - rotation).truncatingRemainder(dividingBy: .pi)
    if angle < 0 { angle += .pi }
    let alongIsHorizontal = min(angle, .pi - angle) <= .pi / 4 + 1e-12
    let alongIsVertical = abs(angle - .pi / 2) <= .pi / 4 + 1e-12
    switch side {
    case .top, .bottom:
      return alongIsHorizontal ? room.boundingBox.alongM : room.boundingBox.acrossM
    case .left, .right:
      return alongIsVertical ? room.boundingBox.alongM : room.boundingBox.acrossM
    }
  }

  static func line(side: SheetDimension.Side, frame: PlanBounds, offset: Double) -> Double {
    switch side {
    case .top: return frame.maxY + offset
    case .bottom: return frame.minY - offset
    case .left: return frame.minX - offset
    case .right: return frame.maxX + offset
    }
  }

  /// Lines, ticks and texts of `dimensions`, plan millimetres.
  static func items(_ dimensions: [SheetDimension], pointM: Double) -> [DrawingItem] {
    guard !dimensions.isEmpty else { return [] }
    let ink = ChapterBrand.Sheet.ink
    let pt = pointM * 1000
    var lines = PathBuilder()
    var ticks = PathBuilder()
    var texts: [DrawingItem] = []
    for d in dimensions {
      let horizontal = d.side == .top || d.side == .bottom
      func point(_ along: Double, _ across: Double) -> Point2 {
        horizontal ? Point2(x: along, y: across) : Point2(x: across, y: along)
      }
      lines.segment(point(d.from, d.line), point(d.to, d.line))
      let half = tickLength / 2 * pointM
      for end in [d.from, d.to] {
        ticks.segment(point(end, d.line - half), point(end, d.line + half))
      }
      let middle = (d.from + d.to) / 2
      let position: Point2
      switch d.side {
      case .top: position = Point2(x: middle, y: d.line + nearGap * pointM)
      case .bottom: position = Point2(x: middle, y: d.line - farGap * pointM)
      case .left: position = Point2(x: d.line - nearGap * pointM, y: middle)
      case .right: position = Point2(x: d.line + farGap * pointM, y: middle)
      }
      texts.append(
        .text(
          DrawingText(
            d.text, position: PathBuilder.mm(position), size: textSize * pt,
            rotationDegrees: horizontal ? 0 : 90, anchor: .center, font: .courier, color: ink,
            layer: .exteriorDimension)))
    }
    return [
      .shape(
        DrawingShape(
          path: lines.path, stroke: DrawingStroke(color: ink, width: lineWidth * pt),
          layer: .exteriorDimension)),
      .shape(
        DrawingShape(
          path: ticks.path, stroke: DrawingStroke(color: ink, width: tickWidth * pt),
          layer: .exteriorDimension)),
    ] + texts
  }
}
