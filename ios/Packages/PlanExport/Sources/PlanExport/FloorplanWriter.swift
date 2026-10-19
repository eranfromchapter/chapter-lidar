import CaptureContract
import Foundation

/// The floor plan as one page: "Floorplan", the address and the approximate total area at the
/// top, a compass at the top right when true north is known, the fully dimensioned colour plan
/// (`FloorPlanDrawing`: outside dimensions in ink, inside dimensions in purple, room names and
/// areas, furniture, fixture and appliance symbols) fitted to the page, a scale bar at the
/// bottom left, a note that the measurements are approximate, and the Chapter wordmark at the
/// bottom right.
///
/// One layout feeds both writers, so the PDF and the SVG show the same page. The page is Letter
/// landscape or a 10 in square, whichever prints the plan larger (`Page.automatic`). The total
/// is the exterior floor area estimate of `PlanTotals` (RoomPlan measures no wall thickness, so
/// it is always "approximately"). A pure function of the model and the options: the same input
/// writes the same bytes. Not part of `PlanExporter.exportAll` yet.
public enum FloorplanWriter {
  public enum Page: String, CaseIterable, Hashable, Sendable {
    /// Letter landscape or the square page, whichever prints the plan at the larger scale;
    /// Letter landscape when both print it the same.
    case automatic
    /// 11 x 8.5 in.
    case letterLandscape
    /// 10 x 10 in.
    case square

    /// Paper size, millimetres; nil for `automatic`.
    var sizeMM: (width: Double, height: Double)? {
      switch self {
      case .automatic: return nil
      case .letterLandscape: return (279.4, 215.9)
      case .square: return (254, 254)
      }
    }

    /// How the page is named in the footer note.
    var name: String {
      switch self {
      case .automatic, .letterLandscape: return "Letter"
      case .square: return "a 10 x 10 in page"
      }
    }
  }

  public struct Options: Hashable, Sendable {
    public var title: String
    /// Property address under the title; no line when nil or blank.
    public var address: String?
    /// How lengths and areas are written (imperial feet-inches to 0.1 in by default).
    public var units: UnitFormatter
    public var roomNames: Bool
    public var roomAreas: Bool
    /// Outside dimensions (ink, outside the walls) and inside dimensions (purple, per room).
    public var exteriorDimensions: Bool
    public var interiorDimensions: Bool
    /// Furniture, fixture and appliance symbols.
    public var furniture: Bool
    /// Draws a compass when `northDegrees` is known.
    public var compass: Bool
    /// True north in the capture's plan frame, degrees counter-clockwise from the plan's +y
    /// axis (the capture's -Z). Nil when north was not captured.
    public var northDegrees: Double?
    public var scaleBar: Bool
    public var page: Page
    /// Lets the plan be laid on the page a quarter turn round when it then prints larger (a
    /// RoomPlan capture has no preferred orientation; the compass turns with it).
    public var turnToFit: Bool
    /// Assumed wall thicknesses, metres (RoomPlan measures none). The exterior one also sets
    /// the total area estimate.
    public var interiorWallThicknessM: Double
    public var exteriorWallThicknessM: Double
    /// PDF date string written into the document information.
    public var creationDate: String

    public init(
      title: String = "Floorplan", address: String? = nil,
      units: UnitFormatter = UnitFormatter(system: .imperial), roomNames: Bool = true,
      roomAreas: Bool = true, exteriorDimensions: Bool = true, interiorDimensions: Bool = true,
      furniture: Bool = true, compass: Bool = true, northDegrees: Double? = nil,
      scaleBar: Bool = true, page: Page = .automatic, turnToFit: Bool = true,
      interiorWallThicknessM: Double = 0.1143,
      exteriorWallThicknessM: Double = MeasurementSettings.defaultExteriorWallThicknessM,
      creationDate: String = "D:20260101000000Z"
    ) {
      self.title = title
      self.address = address
      self.units = units
      self.roomNames = roomNames
      self.roomAreas = roomAreas
      self.exteriorDimensions = exteriorDimensions
      self.interiorDimensions = interiorDimensions
      self.furniture = furniture
      self.compass = compass
      self.northDegrees = northDegrees
      self.scaleBar = scaleBar
      self.page = page
      self.turnToFit = turnToFit
      self.interiorWallThicknessM = interiorWallThicknessM
      self.exteriorWallThicknessM = exteriorWallThicknessM
      self.creationDate = creationDate
    }
  }

  /// The written page.
  public struct Floorplan: Sendable {
    public let pdf: Data
    public let svg: String
    /// The page used (never `automatic`).
    public let page: Page
    public let widthMM: Double
    public let heightMM: Double
    /// The plan is printed at 1:`scaleDenominator`.
    public let scaleDenominator: Double
    /// Exterior floor area estimate, square metres.
    public let totalAreaM2: Double
    /// The total as printed, for example `Approximately 866 ft² total`.
    public let totalText: String
  }

  /// Writes the page as PDF and SVG.
  public static func write(model: CaptureModel, options: Options = Options()) throws -> Floorplan {
    let sheet = try Sheet(model: model, options: options)
    return Floorplan(
      pdf: sheet.pdf(), svg: sheet.svg(), page: sheet.page, widthMM: sheet.widthMM,
      heightMM: sheet.heightMM, scaleDenominator: sheet.drawing.options.scaleDenominator,
      totalAreaM2: sheet.totalAreaM2, totalText: sheet.totalText)
  }

  /// The page as a one-page PDF.
  public static func pdf(model: CaptureModel, options: Options = Options()) throws -> Data {
    try Sheet(model: model, options: options).pdf()
  }

  /// The page as SVG, in paper millimetres.
  public static func svg(model: CaptureModel, options: Options = Options()) throws -> String {
    try Sheet(model: model, options: options).svg()
  }

  // MARK: Layout

  /// Page layout, paper millimetres.
  enum Layout {
    static let margin = 12.0
    static let titleSize = 20.0 * 25.4 / 72
    static let addressSize = 12.0 * 25.4 / 72
    static let totalSize = 10.0 * 25.4 / 72
    static let noteSize = 6.5 * 25.4 / 72
    static let scaleBarTextSize = 8.0 * 25.4 / 72
    static let scaleBarHeight = 0.9
    static let wordmarkSize = 14.0 * 25.4 / 72
    /// Space between the header and the drawing, and between the drawing and the footer.
    static let gap = 4.0
    static let footerHeight = 8.0
    static let compassRadius = 6.5

    /// Header height below the top margin: title, address (when given) and total.
    static func headerHeight(hasAddress: Bool) -> Double { hasAddress ? 21.5 : 15.0 }

    /// Where the drawing goes on a page: x, y (lower left), width, height.
    static func drawingArea(width: Double, height: Double, hasAddress: Bool)
      -> (x: Double, y: Double, width: Double, height: Double)
    {
      let bottom = margin + footerHeight + gap
      let top = height - margin - headerHeight(hasAddress: hasAddress) - gap
      return (margin, bottom, width - 2 * margin, top - bottom)
    }
  }

  /// The page as drawing primitives in paper millimetres (y up from the bottom left), shared by
  /// the PDF and SVG writers.
  struct Sheet {
    let options: Options
    let page: Page
    let widthMM: Double
    let heightMM: Double
    let drawing: FloorPlanDrawing
    let totalAreaM2: Double
    let totalText: String
    let address: String?
    let items: [DrawingItem]

    init(model: CaptureModel, options: Options) throws {
      let address = options.address
        .map { Format.singleLine($0).trimmingCharacters(in: .whitespaces) }
        .flatMap { $0.isEmpty ? nil : $0 }
      // The compass and the scale bar are drawn on the page, not in the drawing.
      let drawingOptions = FloorPlanDrawing.Options(
        units: options.units, exteriorDimensions: options.exteriorDimensions,
        interiorDimensions: options.interiorDimensions, roomNames: options.roomNames,
        roomAreas: options.roomAreas, symbols: options.furniture, scaleBar: false,
        northDegrees: nil, alignToWalls: true,
        interiorWallThicknessM: options.interiorWallThicknessM,
        exteriorWallThicknessM: options.exteriorWallThicknessM)

      // The page and quarter turn (none, or one clockwise) that print the plan largest, judged
      // from one drawing per turn; on a tie Letter landscape, then the plan as squared. Only
      // that choice is then fitted.
      let pages: [Page] =
        options.page == .automatic ? [.letterLandscape, .square] : [options.page]
      let turns = options.turnToFit ? [0, 3] : [0]
      var probes: [Int: FloorPlanDrawing] = [:]
      for turn in turns {
        var turned = drawingOptions
        turned.quarterTurns = turn
        probes[turn] = try FloorPlanDrawing(model: model, options: turned)
      }
      var best: (page: Page, turn: Int, estimate: Double?)?
      for page in pages {
        let size = page.sizeMM!
        let area = Layout.drawingArea(
          width: size.width, height: size.height, hasAddress: address != nil)
        for turn in turns {
          let estimate = probes[turn]!.estimatedDenominator(
            widthMM: area.width, heightMM: area.height)
          let better: Bool
          switch (best?.estimate, estimate) {
          case (_, nil): better = best == nil
          case (nil, _): better = true
          case (let previous?, let next?): better = next < previous
          }
          if better { best = (page, turn, estimate) }
        }
      }
      let page = best!.page
      let size = page.sizeMM!
      let area = Layout.drawingArea(
        width: size.width, height: size.height, hasAddress: address != nil)
      var turned = drawingOptions
      turned.quarterTurns = best!.turn
      let drawing = try FloorPlanDrawing.fitted(
        model: model, widthMM: area.width, heightMM: area.height, options: turned,
        start: best!.estimate)

      // Total: the exterior estimate, as the report states it.
      let settings = MeasurementSettings(exteriorWallThicknessM: options.exteriorWallThicknessM)
      var total = (try? PlanTotals(model, settings: settings))?.exteriorAreaEstimateM2 ?? 0
      if !(total > 0) {
        total = drawing.grossAreaM2 > 0 ? drawing.grossAreaM2 : drawing.roomAreaM2
      }
      let totalText = "Approximately \(options.units.approximateArea(total)) total"

      self.options = options
      self.page = page
      self.widthMM = size.width
      self.heightMM = size.height
      self.drawing = drawing
      self.totalAreaM2 = total
      self.totalText = totalText
      self.address = address
      self.items = Sheet.items(
        width: size.width, height: size.height, page: page, drawing: drawing, options: options,
        address: address, totalText: totalText)
    }

    static func items(
      width: Double, height: Double, page: Page, drawing: FloorPlanDrawing, options: Options,
      address: String?, totalText: String
    ) -> [DrawingItem] {
      let style = drawing.style
      let ink = style.ink
      let muted = DrawingColor(hex: 0x6B6557)
      let margin = Layout.margin
      let top = height - margin
      var items: [DrawingItem] = []
      func text(
        _ string: String, _ x: Double, _ y: Double, size: Double, anchor: DrawingTextAnchor,
        color: DrawingColor, serif: Bool = false, spacing: Double = 0
      ) {
        items.append(
          .text(
            DrawingText(
              string, position: DrawingPoint(x: x, y: y), size: size, anchor: anchor,
              serif: serif, letterSpacing: spacing, color: color, layer: .sheet)))
      }

      // White paper, so a page drawn on any background reads the same.
      var paper = PathBuilder()
      paper.polygon([
        Point2(x: 0, y: 0), Point2(x: width / 1000, y: 0),
        Point2(x: width / 1000, y: height / 1000), Point2(x: 0, y: height / 1000),
      ])
      items.append(.shape(DrawingShape(path: paper.path, fill: .white, layer: .sheet)))

      // Header.
      let title = Format.singleLine(options.title)
      text(title, width / 2, top - 6.5, size: Layout.titleSize, anchor: .center, color: ink)
      var line = top - 6.5
      if let address {
        line -= 7
        text(address, width / 2, line, size: Layout.addressSize, anchor: .center, color: ink)
      }
      line -= 6
      text(totalText, width / 2, line, size: Layout.totalSize, anchor: .center, color: ink)

      // Compass at the top right, turned with the plan.
      if options.compass, let north = options.northDegrees {
        let direction = Point2(x: 0, y: 1).rotated(
          by: north * .pi / 180 - drawing.rotationDegrees * .pi / 180)
        let radius = Layout.compassRadius
        let center = Point2(x: (width - margin - radius - 2) / 1000, y: (top - 10) / 1000)
        // Built as a 1:1 drawing: plan metres are paper metres, k is 1/1000.
        items += FloorPlanDrawing.compassItems(
          center: center, radius: radius / 1000, north: direction, style: style, k: 0.001)
      }

      // The plan, centred in its area at its own scale.
      let area = Layout.drawingArea(width: width, height: height, hasAddress: address != nil)
      let denominator = drawing.options.scaleDenominator
      let bounds = drawing.bounds
      let x = area.x + (area.width - bounds.width / denominator) / 2
      let y = area.y + (area.height - bounds.height / denominator) / 2
      let transform = SheetTransform(
        scale: 1 / denominator, dx: x - bounds.minX / denominator,
        dy: y - bounds.minY / denominator)
      items += drawing.items.map(transform.apply)

      // Footer: scale bar at the left, note in the middle, wordmark at the right.
      if options.scaleBar {
        let bar = options.units.scaleBar(scaleDenominator: denominator)
        let length = bar.metres * 1000 / denominator
        let barY = margin + 3.6
        var path = PathBuilder()
        path.polygon([
          Point2(x: margin / 1000, y: barY / 1000),
          Point2(x: (margin + length) / 1000, y: barY / 1000),
          Point2(x: (margin + length) / 1000, y: (barY + Layout.scaleBarHeight) / 1000),
          Point2(x: margin / 1000, y: (barY + Layout.scaleBarHeight) / 1000),
        ])
        items.append(.shape(DrawingShape(path: path.path, fill: ink, layer: .scaleBar)))
        items.append(
          .text(
            DrawingText(
              bar.label, position: DrawingPoint(x: margin, y: margin + 0.6),
              size: Layout.scaleBarTextSize, anchor: .leading, color: ink, layer: .scaleBar)))
      }
      let note =
        "Drawn at 1:\(Format.compact(denominator)) on \(page.name). Measurements are "
        + "approximate; wall thicknesses are assumed."
      text(note, width / 2, margin + 0.6, size: Layout.noteSize, anchor: .center, color: muted)

      // Wordmark: "chapter" in the serif, "RENOVATION" letter-spaced beneath, centred on each
      // other and set against the right margin.
      let word = DrawingText(
        "chapter", position: DrawingPoint(x: 0, y: 0), size: Layout.wordmarkSize, serif: true,
        color: ink, layer: .sheet)
      let lineSize = Layout.wordmarkSize * 0.3
      let line2 = DrawingText(
        "RENOVATION", position: DrawingPoint(x: 0, y: 0), size: lineSize,
        letterSpacing: lineSize * 0.5, color: ink, layer: .sheet)
      let blockWidth = max(word.width, line2.width)
      let middle = width - margin - blockWidth / 2
      text(
        word.string, middle - word.width / 2, margin + 3.4, size: word.size, anchor: .leading,
        color: ink, serif: true)
      text(
        line2.string, middle - line2.width / 2, margin + 0.6, size: lineSize, anchor: .leading,
        color: ink, spacing: line2.letterSpacing)
      return items
    }

    func pdf() -> Data {
      let points = 72.0 / 25.4
      let pdfPage = PDFPage(width: widthMM * points, height: heightMM * points)
      var renderer = PDFDrawingRenderer(page: pdfPage, scale: points, offsetX: 0, offsetY: 0)
      renderer.draw(items)
      var document = PDFDocument(
        title: documentTitle, author: "Chapter", subject: "Floor plan",
        creator: "\(PlanExportInfo.generator) \(PlanExportInfo.generatorVersion)",
        creationDate: options.creationDate)
      document.pages = [pdfPage]
      return document.render()
    }

    func svg() -> String {
      func n(_ value: Double) -> String { Format.fixed(value, 2) }
      var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      out +=
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(widthMM))mm\" "
        + "height=\"\(n(heightMM))mm\" viewBox=\"0 0 \(n(widthMM)) \(n(heightMM))\">\n"
      out += "  <title>\(SVGWriter.escape(documentTitle))</title>\n"
      let note =
        "Paper millimetres. The plan is drawn at 1:"
        + "\(Format.compact(drawing.options.scaleDenominator)). Wall thicknesses are assumed; "
        + "measurements are approximate."
      out += "  <desc>\(SVGWriter.escape(note))</desc>\n"
      out += DrawingSVG.elements(items, minX: 0, maxY: heightMM)
      out += "</svg>\n"
      return out
    }

    private var documentTitle: String {
      let title = Format.singleLine(options.title)
      return address.map { "\(title) - \($0)" } ?? title
    }
  }
}

/// Moves drawing primitives from plan millimetres onto a page: every coordinate, line width,
/// dash, text size and letter spacing is multiplied by `scale`, then coordinates are shifted.
struct SheetTransform {
  let scale: Double
  let dx: Double
  let dy: Double

  func point(_ p: DrawingPoint) -> DrawingPoint {
    DrawingPoint(x: p.x * scale + dx, y: p.y * scale + dy)
  }

  func path(_ path: DrawingPath) -> DrawingPath {
    DrawingPath(
      elements: path.elements.map { element in
        switch element {
        case .move(let p): return .move(point(p))
        case .line(let p): return .line(point(p))
        case .curve(let a, let b, let c): return .curve(point(a), point(b), point(c))
        case .close: return .close
        }
      })
  }

  func apply(_ item: DrawingItem) -> DrawingItem {
    switch item {
    case .shape(var shape):
      shape.path = path(shape.path)
      if var stroke = shape.stroke {
        stroke.width *= scale
        stroke.dash = stroke.dash.map { $0 * scale }
        shape.stroke = stroke
      }
      return .shape(shape)
    case .text(var text):
      text.position = point(text.position)
      text.size *= scale
      text.letterSpacing *= scale
      return .text(text)
    case .clipped(let clip, let children):
      return .clipped(path(clip), children.map(apply))
    }
  }
}
