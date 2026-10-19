import CaptureContract
import Foundation

/// Paper sizes (millimetres on paper) and colours of the floor plan drawing.
struct FloorPlanStyle: Sendable {
  // Colours: Chapter ink for text and outside dimensions, slate walls, quiet grey symbols.
  var wall = DrawingColor(0.36, 0.37, 0.42)
  var ink = DrawingColor(hex: 0x1F2429)
  var symbol = DrawingColor(0.56, 0.57, 0.61)
  var interiorDimension = DrawingColor(0.60, 0.57, 0.94)

  // Line widths.
  var symbolWidth = 0.12
  var jambWidth = 0.16
  var leafWidth = 0.3
  var swingWidth = 0.13
  var windowWidth = 0.12
  var exteriorDimensionWidth = 0.14
  var interiorDimensionWidth = 0.12

  // Text sizes (em).
  var roomNameSize = 2.6
  var roomAreaSize = 2.1
  var exteriorDimensionSize = 2.2
  var interiorDimensionSize = 1.8
  var scaleBarTextSize = 2.3
  var compassTextSize = 2.6

  // Spacing.
  /// Space between a label and the line it breaks.
  var labelGap = 0.8
  /// Space kept free around every label.
  var labelPadding = 0.3
  /// Half width of a dimension line when checking it against labels.
  var lineClearance = 0.12
  /// Outside dimensions: first row from the wall face, then each further row.
  var exteriorOffset = 5.0
  var exteriorTierStep = 4.5
  var exteriorTiers = 6
  var tickLength = 2.0
  /// Shortest piece of dimension line left either side of a label.
  var minimumStub = 1.0
  /// Inside dimensions: first row from the wall face, then the second.
  var interiorOffset = 1.5
  var interiorTierStep = 3.2
  /// Room edges shorter than this (plan metres) get no inside dimension.
  var interiorMinimumM = 0.25
  /// Door and window jamb lines run this far past the wall faces.
  var jambOverhang = 0.5
  var compassRadius = 7.0
  var scaleBarHeight = 0.9

  /// Subtle fill of a room by what it is used for.
  static func roomFill(_ type: RoomType?) -> DrawingColor {
    switch type {
    case .bedroom: return DrawingColor(hex: 0xF3F4FB)  // pale lavender
    case .livingRoom: return DrawingColor(hex: 0xF9F4ED)  // warm beige
    case .diningRoom: return DrawingColor(hex: 0xF8F2EA)
    case .kitchen: return DrawingColor(hex: 0xF6F3FB)  // pale lilac
    case .bathroom: return DrawingColor(hex: 0xEFF6FC)  // pale blue
    case .closet: return DrawingColor(hex: 0xECF5ED)  // pale green
    case .hallway: return DrawingColor(hex: 0xF5F1E9)  // beige
    case .laundry: return DrawingColor(hex: 0xEEF4F9)
    case .office: return DrawingColor(hex: 0xF4F3F7)
    case .utility: return DrawingColor(hex: 0xF1F1EF)
    case .other, nil: return DrawingColor(hex: 0xF5F5F4)  // neutral
    }
  }

  /// Room type from a label, for models written before rooms had a type.
  static func type(fromLabel label: String) -> RoomType? {
    let text = label.lowercased()
    let table: [(RoomType, [String])] = [
      (.bedroom, ["bed"]), (.bathroom, ["bath", "toilet", "shower", "wc"]),
      (.kitchen, ["kitchen"]), (.livingRoom, ["living", "lounge", "family"]),
      (.diningRoom, ["dining"]), (.closet, ["closet", "wardrobe", "pantry"]),
      (.hallway, ["hall", "corridor", "entry", "foyer"]), (.laundry, ["laundry"]),
      (.office, ["office", "study"]),
    ]
    for (type, words) in table where words.contains(where: { text.contains($0) }) {
      return type
    }
    return nil
  }
}

/// A floor plan drawn as vector primitives in plan millimetres: thick walls along the room
/// outlines, doors with leaf and swing, windows, room fills by room type, furniture, fixture
/// and appliance symbols, outside and inside dimension strings, room names and areas, a compass
/// when true north is known, and a scale bar. The PDF and SVG writers draw the same primitives.
///
/// The plan is turned so that its walls run along the sheet axes (`rotationDegrees`). Line
/// widths and text sizes are paper sizes at 1:`scaleDenominator`, written in plan millimetres,
/// so the drawing is built for the scale it is printed at (`fitted` picks one for a page).
public struct FloorPlanDrawing: Sendable {
  public struct Options: Hashable, Sendable {
    /// Print scale: plan millimetres per paper millimetre (50 for 1:50).
    public var scaleDenominator: Double
    /// How lengths and areas are written (imperial feet-inches to 0.1 in by default).
    public var units: UnitFormatter
    public var exteriorDimensions: Bool
    public var interiorDimensions: Bool
    public var roomNames: Bool
    public var roomAreas: Bool
    public var symbols: Bool
    public var scaleBar: Bool
    /// True north in the capture's plan frame, degrees counter-clockwise from the plan's +y
    /// axis (the capture's -Z). Nil when north was not captured: no compass is drawn.
    public var northDegrees: Double?
    /// Turn the plan so its walls run along the sheet axes.
    public var alignToWalls: Bool
    /// Assumed wall thicknesses, metres (RoomPlan measures none).
    public var interiorWallThicknessM: Double
    public var exteriorWallThicknessM: Double

    public init(
      scaleDenominator: Double = 50, units: UnitFormatter = UnitFormatter(system: .imperial),
      exteriorDimensions: Bool = true, interiorDimensions: Bool = true, roomNames: Bool = true,
      roomAreas: Bool = true, symbols: Bool = true, scaleBar: Bool = true,
      northDegrees: Double? = nil, alignToWalls: Bool = true,
      interiorWallThicknessM: Double = 0.1143, exteriorWallThicknessM: Double = 0.1524
    ) {
      self.scaleDenominator = scaleDenominator
      self.units = units
      self.exteriorDimensions = exteriorDimensions
      self.interiorDimensions = interiorDimensions
      self.roomNames = roomNames
      self.roomAreas = roomAreas
      self.symbols = symbols
      self.scaleBar = scaleBar
      self.northDegrees = northDegrees
      self.alignToWalls = alignToWalls
      self.interiorWallThicknessM = interiorWallThicknessM
      self.exteriorWallThicknessM = exteriorWallThicknessM
    }
  }

  /// Extent of a drawing, plan millimetres.
  public struct Bounds: Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double
    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
  }

  /// A room as drawn: the outline in the sheet-aligned frame, plan metres.
  struct DrawnRoom: Sendable {
    var id: String
    var label: String
    var type: RoomType?
    var polygon: [Point2]
    /// The outline less the walls that stand on it (where the floor is clear).
    var clear: [Point2]
    var areaM2: Double
  }

  public let options: Options
  /// Primitives in drawing order.
  public let items: [DrawingItem]
  public let bounds: Bounds
  /// How far the capture's plan was turned (counter-clockwise) to square it with the sheet.
  public let rotationDegrees: Double
  /// Floor area within the outside faces of the exterior walls, with the assumed thickness.
  public let grossAreaM2: Double
  /// Sum of the rooms' floor areas.
  public let roomAreaM2: Double
  /// True when a compass was drawn (true north is known).
  public var hasCompass: Bool { options.northDegrees != nil }

  let style: FloorPlanStyle
  let rooms: [DrawnRoom]
  let walls: WallLayout
  let symbols: [PlacedSymbol]
  let labels: [PlacedLabel]
  let exteriorDimensions: [ExteriorDimension]
  let droppedInteriorDimensions: Int

  public init(model: CaptureModel, options: Options = Options()) throws {
    let style = FloorPlanStyle()
    var geometry = try PlanGeometry(model: model)
    guard geometry.bounds != nil else { throw PlanExportError.noPlanGeometry }
    guard options.scaleDenominator.isFinite, options.scaleDenominator > 0 else {
      throw PlanExportError.invalidGeometry("the drawing scale is not a positive number")
    }
    let k = options.scaleDenominator / 1000
    let theta = options.alignToWalls ? FloorPlanDrawing.alignment(of: geometry) : 0
    if theta != 0 { geometry = geometry.rotated(by: -theta) }

    // Rooms, counter-clockwise, without repeated or straight-on corners.
    let modelRooms = model.rooms
    var rooms: [DrawnRoom] = []
    for room in geometry.rooms {
      let source = modelRooms.first { $0.id == room.id }
      var polygon = Geo.counterClockwise(Geo.clean(room.polygon))
      if polygon.count < 3 { polygon = Geo.counterClockwise(room.polygon) }
      rooms.append(
        DrawnRoom(
          id: room.id, label: room.label,
          type: source?.type ?? FloorPlanStyle.type(fromLabel: room.label), polygon: polygon,
          clear: polygon, areaM2: room.areaM2))
    }

    let walls = WallLayout(
      rooms: rooms.map(\.polygon), walls: geometry.walls.filter { $0.length > 0 },
      openings: geometry.openings, exterior: options.exteriorWallThicknessM,
      interior: options.interiorWallThicknessM)
    for index in rooms.indices {
      rooms[index].clear = FloorPlanDrawing.clearOutline(rooms[index].polygon, walls: walls)
    }

    // Symbols.
    var symbols: [PlacedSymbol] = []
    if options.symbols {
      let lines =
        rooms.flatMap { room in
          room.polygon.indices.map {
            (room.polygon[$0], room.polygon[($0 + 1) % room.polygon.count])
          }
        } + geometry.walls.map { ($0.start, $0.end) }
      let tables = geometry.objects.filter { $0.category == .table }
      for object in geometry.objects {
        let attributes = model.objects.first { $0.id == object.id }?.attributes ?? [:]
        if let symbol = FloorPlanSymbols.symbol(
          for: object, attributes: attributes, lines: lines, tables: tables)
        {
          symbols.append(symbol)
        }
      }
    }

    var items: [DrawingItem] = []
    // Room fills.
    for room in rooms {
      var path = PathBuilder()
      path.polygon(room.polygon)
      items.append(
        .shape(
          DrawingShape(
            path: path.path, fill: FloorPlanStyle.roomFill(room.type), layer: .roomFill)))
    }
    // Symbols: thin grey outlines, the outline dashed for a low-confidence detection.
    let symbolStroke = DrawingStroke(
      color: style.symbol, width: style.symbolWidth * k * 1000, cap: .round, join: .round)
    for symbol in symbols {
      var outlineStroke = symbolStroke
      if symbol.lowConfidence { outlineStroke.dash = [1.0 * k * 1000, 0.6 * k * 1000] }
      var group: [DrawingItem] = []
      if !symbol.details.isEmpty {
        group.append(
          .shape(DrawingShape(path: symbol.details.path, stroke: symbolStroke, layer: .symbol)))
      }
      if !symbol.outline.isEmpty {
        group.append(
          .shape(DrawingShape(path: symbol.outline.path, stroke: outlineStroke, layer: .symbol)))
      }
      items += group
    }
    // Walls: one path, nonzero winding, so overlapping pieces paint as their union.
    var wallPath = PathBuilder()
    for piece in walls.pieces { wallPath.polygon(piece) }
    if !wallPath.isEmpty {
      items.append(.shape(DrawingShape(path: wallPath.path, fill: style.wall, layer: .wall)))
    }
    let openings = FloorPlanDrawing.openingItems(walls: walls, rooms: rooms, style: style, k: k)
    items += openings.items

    // Annotations.
    let building = walls.loops.filter { $0.closed && Geo.signedArea($0.outer) > 0 }.map(\.outer)
    var layout = AnnotationLayout(
      style: style, units: options.units, scaleDenominator: options.scaleDenominator,
      symbols: symbols.map(\.footprint), building: building, wallPieces: walls.pieces,
      lines: openings.swings)
    if options.roomNames || options.roomAreas {
      for room in rooms {
        layout.placeRoomLabel(
          roomId: room.id, name: options.roomNames ? room.label : nil,
          area: options.roomAreas ? options.units.area(room.areaM2) : nil,
          polygon: room.clear.count >= 3 ? room.clear : room.polygon)
      }
    }
    if options.exteriorDimensions { layout.placeExteriorDimensions(walls: walls) }
    if options.interiorDimensions {
      layout.placeInteriorDimensions(rooms: rooms.map { ($0.id, $0.clear) })
    }
    for layer in [DrawingLayer.interiorDimension, .roomLabel, .exteriorDimension] {
      items += layout.items[layer] ?? []
    }

    // Compass (only when north is known) and scale bar, in free corners of the drawing.
    var extent = FloorPlanDrawing.extent(of: items)
    if let north = options.northDegrees {
      let direction = Point2(x: 0, y: 1).rotated(by: north * .pi / 180 - theta)
      let radius = style.compassRadius * k
      let corner = Point2(x: extent.maxX / 1000 - radius, y: extent.maxY / 1000 - radius)
      var center = corner
      let box = OrientedBox(
        center: corner, u: Point2(x: 1, y: 0), halfWidth: radius * 1.25,
        halfHeight: radius * 1.25)
      if layout.conflicts(box, padding: 0, outside: true) > 0 {
        center = Point2(x: corner.x, y: extent.maxY / 1000 + radius * 1.4)
      }
      items += FloorPlanDrawing.compassItems(
        center: center, radius: radius, north: direction, style: style, k: k)
      layout.labels.append(
        PlacedLabel(
          kind: .compass, text: "N",
          box: OrientedBox(
            center: center, u: Point2(x: 1, y: 0), halfWidth: radius * 1.25,
            halfHeight: radius * 1.25), roomId: nil))
      extent = FloorPlanDrawing.extent(of: items)
    }
    if options.scaleBar {
      let bar = options.units.scaleBar(scaleDenominator: options.scaleDenominator)
      let textSize = style.scaleBarTextSize * k
      let height = style.scaleBarHeight * k
      var origin = Point2(x: extent.minX / 1000, y: extent.minY / 1000 + textSize * 1.4)
      let box = OrientedBox(
        center: Point2(x: origin.x + bar.metres / 2, y: origin.y - textSize * 0.4),
        u: Point2(x: 1, y: 0), halfWidth: max(bar.metres, 0) / 2 + k,
        halfHeight: textSize * 1.2)
      if layout.conflicts(box, padding: 0, outside: true) > 0 {
        origin = Point2(x: origin.x, y: extent.minY / 1000 - 3 * k)
      }
      var barPath = PathBuilder()
      barPath.polygon([
        origin, Point2(x: origin.x + bar.metres, y: origin.y),
        Point2(x: origin.x + bar.metres, y: origin.y + height),
        Point2(x: origin.x, y: origin.y + height),
      ])
      items.append(.shape(DrawingShape(path: barPath.path, fill: style.ink, layer: .scaleBar)))
      let baseline = Point2(x: origin.x, y: origin.y - textSize * 1.1)
      items.append(
        .text(
          DrawingText(
            bar.label, position: PathBuilder.mm(baseline), size: textSize * 1000,
            anchor: .leading, color: style.ink, layer: .scaleBar)))
      layout.labels.append(
        PlacedLabel(
          kind: .scaleBar, text: bar.label,
          box: layout.textBox(
            bar.label,
            center: Point2(
              x: origin.x + FontMetrics.width(bar.label, size: textSize) / 2,
              y: baseline.y + textSize * 0.36), u: Point2(x: 1, y: 0), size: textSize),
          roomId: nil))
      extent = FloorPlanDrawing.extent(of: items)
    }

    self.options = options
    self.style = style
    self.items = items
    self.bounds = extent
    self.rotationDegrees = theta * 180 / .pi
    self.rooms = rooms
    self.walls = walls
    self.symbols = symbols
    self.labels = layout.labels
    self.exteriorDimensions = layout.exteriorDimensions
    self.droppedInteriorDimensions = layout.droppedInteriorDimensions
    self.grossAreaM2 = walls.grossAreaM2
    self.roomAreaM2 = rooms.map(\.areaM2).reduce(0, +)
  }

  /// The drawing at the largest whole-number scale (1:n) that fits `widthMM` by `heightMM` of
  /// paper; `options.scaleDenominator` is replaced.
  public static func fitted(
    model: CaptureModel, widthMM: Double, heightMM: Double, options: Options = Options()
  ) throws -> FloorPlanDrawing {
    guard widthMM > 0, heightMM > 0 else {
      throw PlanExportError.invalidGeometry("the drawing area is empty")
    }
    let geometry = try PlanGeometry(model: model)
    guard let planBounds = geometry.bounds else { throw PlanExportError.noPlanGeometry }
    let span = max(planBounds.width, planBounds.height, 0.5) * 1000
    // Start as if a quarter of the paper went to dimensions, then correct from the result.
    var denominator = max(1, (span / (min(widthMM, heightMM) * 0.75)).rounded(.up))
    var options = options
    var fits: FloorPlanDrawing?
    var last: FloorPlanDrawing?
    for _ in 0..<12 {
      options.scaleDenominator = denominator
      let candidate = try FloorPlanDrawing(model: model, options: options)
      last = candidate
      let needed = max(
        candidate.bounds.width / denominator / widthMM,
        candidate.bounds.height / denominator / heightMM)
      if needed <= 1 {
        // Fits: try the finer scale the margin allows; stop when there is none.
        fits = candidate
        let finer = max(1, (denominator * needed).rounded(.up))
        if finer >= denominator { break }
        denominator = finer
      } else {
        // Too big: the last scale that fitted, or a coarser one.
        if fits != nil { break }
        denominator = max(denominator + 1, (denominator * needed).rounded(.up))
      }
    }
    return fits ?? last!
  }

  // MARK: Pieces

  /// Wall direction (modulo 90 degrees) weighted by length, so the plan can be squared to the
  /// sheet; radians in (-45, 45] degrees.
  static func alignment(of geometry: PlanGeometry) -> Double {
    var c = 0.0
    var s = 0.0
    var segments = geometry.walls.map { ($0.start, $0.end) }
    if segments.isEmpty {
      segments = geometry.rooms.flatMap { room in
        room.polygon.indices.map { (room.polygon[$0], room.polygon[($0 + 1) % room.polygon.count]) }
      }
    }
    for (a, b) in segments {
      let d = b - a
      let length = d.length
      guard length > 0.05 else { continue }
      let angle = atan2(d.y, d.x)
      c += length * cos(4 * angle)
      s += length * sin(4 * angle)
    }
    guard c * c + s * s > 1e-12 else { return 0 }
    let theta = atan2(s, c) / 4
    // Snap tiny turns away so a square capture is drawn exactly as captured.
    return abs(theta) < 1e-6 ? 0 : theta
  }

  /// The room outline moved in off the interior walls that stand on its edges (by half their
  /// thickness), so inside dimensions measure between wall faces.
  static func clearOutline(_ polygon: [Point2], walls: WallLayout) -> [Point2] {
    let count = polygon.count
    guard count >= 3 else { return polygon }
    var insets: [Double] = []
    for i in 0..<count {
      let a = polygon[i]
      let b = polygon[(i + 1) % count]
      let d = (b - a).unit
      var inset = 0.0
      for segment in walls.segments where segment.kind == .interior {
        guard abs(segment.direction.cross(d)) < 0.02,
          abs((segment.a - a).cross(d)) < 0.02,
          min(max((segment.a - a).dot(d), (segment.b - a).dot(d)), a.distance(to: b))
            - max(min((segment.a - a).dot(d), (segment.b - a).dot(d)), 0) > 0.05
        else { continue }
        inset = max(inset, (segment.hi - segment.lo) / 2)
      }
      insets.append(inset)
    }
    var out: [Point2] = []
    for i in 0..<count {
      let previous = (i + count - 1) % count
      let a0 = polygon[previous]
      let a1 = polygon[i]
      let b1 = polygon[(i + 1) % count]
      let d0 = (a1 - a0).unit
      let d1 = (b1 - a1).unit
      let p0 = a0 + d0.leftNormal * insets[previous]
      let p1 = a1 + d1.leftNormal * insets[i]
      if let corner = Geo.lineIntersection(p0, d0, p1, d1),
        corner.distance(to: a1) <= 3 * max(insets[previous], insets[i]) + 1e-9
      {
        out.append(corner)
      } else {
        out.append(a1 + d1.leftNormal * insets[i])
      }
    }
    return Geo.signedArea(out) > 0 ? out : polygon
  }

  /// Door leaves and swings, window glazing and the jamb lines of each opening, and the door
  /// leaves and swings as short segments for label placement to keep clear of.
  static func openingItems(
    walls: WallLayout, rooms: [DrawnRoom], style: FloorPlanStyle, k: Double
  ) -> (items: [DrawingItem], swings: [(Point2, Point2)]) {
    var swings: [(Point2, Point2)] = []
    var doors = PathBuilder()
    var leaves = PathBuilder()
    var jambs = PathBuilder()
    var glazing = PathBuilder()
    let overhang = style.jambOverhang * k
    for gap in walls.gaps {
      let n = gap.normal
      let width = gap.a.distance(to: gap.b)
      guard width > 0.01 else { continue }
      switch gap.opening.kind {
      case .opening:
        continue
      case .window:
        for end in [gap.a, gap.b] {
          jambs.segment(end + n * (gap.lo - overhang), end + n * (gap.hi + overhang))
        }
        for f in [0.0, 0.38, 0.62, 1.0] {
          let offset = gap.lo + (gap.hi - gap.lo) * f
          glazing.segment(gap.a + n * offset, gap.b + n * offset)
        }
      case .door:
        for end in [gap.a, gap.b] {
          jambs.segment(end + n * (gap.lo - overhang), end + n * (gap.hi + overhang))
        }
        // Swing into the room the door belongs to, hinged at the end nearer a corner.
        let middle = (gap.a + gap.b) * 0.5
        let above = rooms.firstIndex {
          PlanGeometry.contains($0.polygon, middle + n * (gap.hi + 0.12))
        }
        let below = rooms.firstIndex {
          PlanGeometry.contains($0.polygon, middle + n * (gap.lo - 0.12))
        }
        var side = 1.0
        if let above, let below {
          side = FloorPlanDrawing.doorRoomOrder(rooms[above], rooms[below]) ? 1 : -1
        } else if below != nil {
          side = -1
        }
        let face = side > 0 ? gap.hi : gap.lo
        let hingeAtA = gap.distanceToStart <= gap.distanceToEnd
        let hinge = (hingeAtA ? gap.a : gap.b) + n * face
        let jamb = (hingeAtA ? gap.b : gap.a) + n * face
        let tip = hinge + n * (side * width)
        leaves.segment(hinge, tip)
        let start = atan2((tip - hinge).y, (tip - hinge).x) * 180 / .pi
        let target = atan2((jamb - hinge).y, (jamb - hinge).x) * 180 / .pi
        var sweep = target - start
        while sweep > 180 { sweep -= 360 }
        while sweep < -180 { sweep += 360 }
        doors.arc(
          in: DrawingFrame(origin: hinge, u: Point2(x: 1, y: 0), v: Point2(x: 0, y: 1)), cx: 0,
          cy: 0, rx: width, ry: width, start: start, end: start + sweep, move: true)
        swings.append((hinge, tip))
        var previous = tip
        for step in 1...8 {
          let angle = (start + sweep * Double(step) / 8) * .pi / 180
          let next = hinge + Point2(x: cos(angle), y: sin(angle)) * width
          swings.append((previous, next))
          previous = next
        }
      }
    }
    var items: [DrawingItem] = []
    let mm = k * 1000
    if !jambs.isEmpty {
      items.append(
        .shape(
          DrawingShape(
            path: jambs.path, stroke: DrawingStroke(color: style.wall, width: style.jambWidth * mm),
            layer: .opening)))
    }
    if !glazing.isEmpty {
      items.append(
        .shape(
          DrawingShape(
            path: glazing.path,
            stroke: DrawingStroke(color: style.wall, width: style.windowWidth * mm),
            layer: .window)))
    }
    if !leaves.isEmpty {
      items.append(
        .shape(
          DrawingShape(
            path: leaves.path,
            stroke: DrawingStroke(color: style.wall, width: style.leafWidth * mm, cap: .round),
            layer: .door)))
    }
    if !doors.isEmpty {
      items.append(
        .shape(
          DrawingShape(
            path: doors.path,
            stroke: DrawingStroke(color: style.wall, width: style.swingWidth * mm),
            layer: .door)))
    }
    return (items, swings)
  }

  /// True when a door between `a` and `b` belongs to (swings into) `a`: a bathroom, then a
  /// bedroom or office, before shared rooms; a closet door swings out of the closet; otherwise
  /// the smaller room.
  static func doorRoomOrder(_ a: DrawnRoom, _ b: DrawnRoom) -> Bool {
    func rank(_ room: DrawnRoom) -> Int {
      switch room.type {
      case .bathroom: return 0
      case .bedroom, .office: return 1
      case .laundry, .utility: return 2
      case .other, nil: return 3
      case .kitchen, .diningRoom, .livingRoom, .hallway: return 4
      case .closet: return 5
      }
    }
    let ra = rank(a)
    let rb = rank(b)
    if ra != rb { return ra < rb }
    return a.areaM2 <= b.areaM2
  }

  /// Compass rose turned to `north` (a unit vector on the sheet), with an N past its tip.
  static func compassItems(
    center: Point2, radius: Double, north: Point2, style: FloorPlanStyle, k: Double
  ) -> [DrawingItem] {
    let frame = DrawingFrame(origin: center, u: north.rightNormal, v: north)
    var filled = PathBuilder()
    var outline = PathBuilder()
    let inner = radius * 0.13
    // Four long points and four short ones, each split along its axis into a filled and an
    // open half.
    for index in 0..<8 {
      let angle = Double(index) * Double.pi / 4
      let length = index % 2 == 0 ? radius : radius * 0.5
      let tip = Point2(x: sin(angle) * length, y: cos(angle) * length)
      let left = Point2(x: sin(angle - .pi / 4) * inner, y: cos(angle - .pi / 4) * inner)
      let right = Point2(x: sin(angle + .pi / 4) * inner, y: cos(angle + .pi / 4) * inner)
      filled.polygon([frame.map(0, 0), frame.map(left), frame.map(tip)])
      outline.polygon([frame.map(0, 0), frame.map(tip), frame.map(right)])
    }
    var ring = PathBuilder()
    ring.circle(center: center, radius: radius * 0.6)
    var dot = PathBuilder()
    dot.circle(center: center, radius: inner * 0.6)
    let mm = k * 1000
    let line = DrawingStroke(color: style.ink, width: 0.14 * mm, join: .round)
    let textSize = style.compassTextSize * k
    let letter = center + north * (radius + textSize * 0.75)
    return [
      .shape(DrawingShape(path: ring.path, stroke: line, layer: .compass)),
      .shape(DrawingShape(path: outline.path, fill: .white, stroke: line, layer: .compass)),
      .shape(DrawingShape(path: filled.path, fill: style.ink, stroke: line, layer: .compass)),
      .shape(DrawingShape(path: dot.path, fill: .white, stroke: line, layer: .compass)),
      .text(
        DrawingText(
          "N", position: PathBuilder.mm(letter - Point2(x: 0, y: textSize * 0.36)),
          size: textSize * 1000, anchor: .center, bold: true, color: style.ink, layer: .compass)),
    ]
  }

  /// Extent of `items` in plan millimetres, counting stroke widths and text boxes.
  static func extent(of items: [DrawingItem]) -> Bounds {
    var bounds: Bounds?
    func grow(_ x: Double, _ y: Double, _ pad: Double) {
      if bounds == nil {
        bounds = Bounds(minX: x - pad, minY: y - pad, maxX: x + pad, maxY: y + pad)
      } else {
        bounds!.minX = min(bounds!.minX, x - pad)
        bounds!.minY = min(bounds!.minY, y - pad)
        bounds!.maxX = max(bounds!.maxX, x + pad)
        bounds!.maxY = max(bounds!.maxY, y + pad)
      }
    }
    func visit(_ item: DrawingItem) {
      switch item {
      case .shape(let shape):
        let pad = (shape.stroke?.width ?? 0) / 2
        for p in shape.path.points { grow(p.x, p.y, pad) }
      case .text(let text):
        for corner in FloorPlanDrawing.textCorners(text) { grow(corner.x, corner.y, 0) }
      case .clipped(_, let children):
        children.forEach(visit)
      }
    }
    items.forEach(visit)
    return bounds ?? Bounds(minX: 0, minY: 0, maxX: 0, maxY: 0)
  }

  /// Corners of the box a text item covers (descender to cap height), plan millimetres.
  static func textCorners(_ text: DrawingText) -> [Point2] {
    let width = FontMetrics.width(text.string, size: text.size, bold: text.bold)
    let shift: Double
    switch text.anchor {
    case .leading: shift = 0
    case .center: shift = -width / 2
    case .trailing: shift = -width
    }
    let angle = text.rotationDegrees * .pi / 180
    let u = Point2(x: cos(angle), y: sin(angle))
    let v = u.leftNormal
    let origin = Point2(x: text.position.x, y: text.position.y) + u * shift
    let low = -0.22 * text.size
    let high = 0.75 * text.size
    return [
      origin + v * low, origin + u * width + v * low, origin + u * width + v * high,
      origin + v * high,
    ]
  }
}

extension PlanGeometry {
  /// The same plan turned counter-clockwise by `radians` about the origin.
  func rotated(by radians: Double) -> PlanGeometry {
    var copy = self
    let r = { (p: Point2) in p.rotated(by: radians) }
    copy.walls = walls.map { wall in
      var w = wall
      w.start = r(wall.start)
      w.end = r(wall.end)
      return w
    }
    copy.openings = openings.map { opening in
      var o = opening
      o.from = r(opening.from)
      o.to = r(opening.to)
      return o
    }
    copy.rooms = rooms.map { room in
      var m = room
      m.polygon = room.polygon.map(r)
      m.labelPoint = r(room.labelPoint)
      return m
    }
    copy.objects = objects.map { object in
      var o = object
      o.corners = object.corners.map(r)
      o.center = r(object.center)
      return o
    }
    var bounds: PlanBounds?
    let points =
      copy.walls.flatMap { [$0.start, $0.end] } + copy.rooms.flatMap(\.polygon)
      + copy.objects.flatMap(\.corners)
    for p in points {
      if bounds == nil {
        bounds = PlanBounds(minX: p.x, minY: p.y, maxX: p.x, maxY: p.y)
      } else {
        bounds!.grow(p)
      }
    }
    copy.bounds = bounds
    return copy
  }
}
