import CaptureContract
import Foundation

/// The plan sheet of one capture as written.
public struct PlanSheetOutput: Sendable {
  public let file: ExportedFile
  /// Scale denominator from the ladder: 50, 100, 200 (500 for an exterior capture).
  public let scaleDenominator: Int
  /// Quarter turns counter-clockwise after squaring: 0, or 3 (one clockwise).
  public let quarterTurns: Int
  /// How far the drawing turns the capture's plan clockwise (degrees): squaring and quarter
  /// turn. The north arrow's angle is the heading minus it (ρ = −this, compass §2.5).
  public let drawingRotationDegrees: Double
  /// The north symbol in the title block: angle and captions for this drawing.
  public let north: NorthSymbol
  /// True when the plan is larger than the sheet at the last rung and is cut at the frame.
  public let isClipped: Bool
  /// The page's title block and footnote.
  let layout: PlanSheetLayout
  /// The drawing on the sheet (plan.svg and plan.png draw the same one).
  let drawing: FloorPlanDrawing
  /// The drawing moved onto the page: points = plan millimetres × `pointsPerMM` + offset.
  let pointsPerMM: Double
  let offsetX: Double
  let offsetY: Double
  /// Every item of the page in points (y up), in drawing order.
  let items: [DrawingItem]
}

/// The plan sheet (plan-sheet §3): one Tabloid landscape page, 1224 × 792 pt (11 × 17 in), per
/// capture, written on the phone when the package is built, with no verdict. The capture's
/// plan, drawn by `FloorPlanDrawing` in its `.planSheet` rendition at the first rung of the
/// scale ladder at which it fits (1:50, 1:100, 1:200, and 1:500 for an exterior capture; never
/// fitted to the page), beside a title block: the Chapter logo, sheet number, title, project
/// and address, the data rows, the note that the verdict is in the station's spatial report,
/// the rooms not scanned, the legend, the scale bar, the north arrow of the capture's compass
/// reading in its three states, and the statement. Fonts: Inter (embedded), Times-Roman and
/// Times-Italic for the title and tagline, Courier for ids, dimensions and the scale.
///
/// Output is a pure function of the model and the capture record: the PDF's creation date is
/// the capture's `capturedAt`.
public enum PlanSheetWriter {
  public static let fileName = "plan-sheet.pdf"

  /// Scale ladders: room and floor captures, and exterior captures.
  static let ladder = [50, 100, 200]
  static let exteriorLadder = [50, 100, 200, 500]
  /// Quarter turns tried at each rung: none, then one clockwise.
  static let turns = [0, 3]

  /// The plan frame (x 84–864, y 84–708): walls and rooms must fit it; its centre.
  static let planFrameWidth = 780.0
  static let planFrameHeight = 624.0
  static let planCenterX = 474.0
  static let planCenterTop = 396.0
  /// The annotation frame (x 42–906, y 42 to the footnote's top − 6): the whole drawing with
  /// its dimensions and labels must fit it.
  static let annotationLeft = 42.0
  static let annotationRight = 906.0
  static let annotationTop = 42.0
  /// The drawing area (x 36–912, y 36–756) inside the border, where a plan too big for the
  /// sheet is cut.
  static let clipLeft = 36.75
  static let clipRight = 911.25
  static let clipTop = 36.75
  static let clipBottom = 755.25

  static let pointsPerMM = 72 / 25.4

  public static func write(model: CaptureModel, context: PlanExportContext) throws
    -> PlanSheetOutput
  {
    let metrics = try PlanMetrics(model)
    let choice = try choose(model: model, context: context, metrics: metrics)
    let drawing = choice.drawing
    let n = Int(drawing.options.scaleDenominator.rounded())
    let north = NorthSymbol(
      state: context.compass, drawingRotationCCW: -drawing.rotationDegrees)
    let layout = PlanSheetLayout.make(
      context: context, summary: PlanSheetSummary(metrics: metrics), scaleDenominator: n,
      north: north, tooBig: choice.clipped)

    // Place the plan's centre on the plan frame's, then move the drawing the least distance
    // that brings its annotations into the annotation frame.
    let scale = pointsPerMM / drawing.options.scaleDenominator
    let plan = drawing.planBoundsMM ?? drawing.bounds
    var dx = planCenterX - (plan.minX + plan.maxX) / 2 * scale
    var dy = SheetItems.y(planCenterTop) - (plan.minY + plan.maxY) / 2 * scale
    if !choice.clipped {
      let bounds = drawing.bounds
      let left = bounds.minX * scale + dx
      let right = bounds.maxX * scale + dx
      let bottom = bounds.minY * scale + dy
      let top = bounds.maxY * scale + dy
      let frameBottom = SheetItems.y(layout.footnoteTop - 6)
      let frameTop = SheetItems.y(annotationTop)
      if left < annotationLeft { dx += annotationLeft - left }
      if right > annotationRight { dx -= right - annotationRight }
      if bottom < frameBottom { dy += frameBottom - bottom }
      if top > frameTop { dy -= top - frameTop }
    }
    let place = SheetTransform(scale: scale, dx: dx, dy: dy)
    var drawn = drawing.items.map(place.apply)
    if choice.clipped {
      drawn = [
        .clipped(
          SheetItems.rectPath(
            x: clipLeft, top: clipTop, width: clipRight - clipLeft, height: clipBottom - clipTop),
          drawn)
      ]
    }
    // Page furniture first (the page colour under everything), then the drawing, then the
    // footnote and the title block.
    let furniture = Array(layout.items.prefix(3))
    let items = furniture + drawn + layout.items.dropFirst(3)

    let page = PDFPage(width: SheetItems.pageWidth, height: SheetItems.pageHeight)
    var renderer = PDFDrawingRenderer(page: page, scale: 1, offsetX: 0, offsetY: 0)
    renderer.draw(items)
    var document = PDFDocument(
      title: "Existing-condition plan - \(context.floorLabel) - \(context.projectTitle)",
      author: context.operatorName,
      subject: "Plan sheet 1:\(n) at 11 x 17 in, capture \(context.captureId)",
      creator: "\(PlanExportInfo.generator) \(PlanExportInfo.generatorVersion)",
      creationDate: context.pdfDate)
    document.pages = [page]
    let file = ExportedFile(
      fileName: fileName, role: .planPDF, mime: "application/pdf", data: document.render())
    return PlanSheetOutput(
      file: file, scaleDenominator: n, quarterTurns: drawing.options.quarterTurns,
      drawingRotationDegrees: drawing.rotationDegrees, north: north, isClipped: choice.clipped,
      layout: layout, drawing: drawing, pointsPerMM: scale, offsetX: dx, offsetY: dy,
      items: items)
  }

  /// The drawing options of the sheet at 1:`n` with `turns` quarter turns.
  static func options(context: PlanExportContext, n: Int, turns: Int, annotations: Bool)
    -> FloorPlanDrawing.Options
  {
    FloorPlanDrawing.Options(
      scaleDenominator: Double(n), units: UnitFormatter(system: .imperial),
      exteriorDimensions: annotations, interiorDimensions: false, roomNames: annotations,
      roomAreas: annotations, symbols: true, scaleBar: false, north: nil, quarterTurns: turns,
      rendition: .planSheet, captureMode: context.mode)
  }

  /// The first rung of the ladder (and the first turn, none before one clockwise) at which the
  /// drawing fits: its plan (walls and rooms) within the 780 × 624 pt plan frame, and its
  /// whole extent with dimensions and labels within the annotation frame. A plan too big for
  /// every rung is drawn at the last one, not turned, and cut at the frame (`clipped`).
  static func choose(model: CaptureModel, context: PlanExportContext, metrics: PlanMetrics)
    throws -> (drawing: FloorPlanDrawing, clipped: Bool)
  {
    let rungs = context.mode == .exterior ? exteriorLadder : ladder
    let footnote = PlanSheetLayout.footnoteLines(tooBig: false, scaleDenominator: rungs[0])
    let footnoteTop =
      PlanSheetLayout.footnoteBottom - PlanSheetLayout.footnoteLine * Double(footnote.count)
    let frameWidth = annotationRight - annotationLeft
    let frameHeight = footnoteTop - 6 - annotationTop
    for n in rungs {
      let toPoints = pointsPerMM / Double(n)
      for turns in turns {
        // The plan alone first: cheap, and most rungs fail on it.
        let bare = try FloorPlanDrawing(
          model: model, options: options(context: context, n: n, turns: turns, annotations: false),
          metrics: metrics)
        let plan = bare.planExtentMM
        guard plan.width * toPoints <= planFrameWidth + 1e-9,
          plan.height * toPoints <= planFrameHeight + 1e-9
        else { continue }
        let drawing = try FloorPlanDrawing(
          model: model, options: options(context: context, n: n, turns: turns, annotations: true),
          metrics: metrics)
        if drawing.bounds.width * toPoints <= frameWidth + 1e-9,
          drawing.bounds.height * toPoints <= frameHeight + 1e-9
        {
          return (drawing, false)
        }
      }
    }
    let drawing = try FloorPlanDrawing(
      model: model,
      options: options(context: context, n: rungs.last!, turns: 0, annotations: true),
      metrics: metrics)
    return (drawing, true)
  }
}
