import CaptureContract
import Foundation

/// Result of writing a plan PDF.
public struct PlanPDFOutput: Sendable {
  public let file: ExportedFile
  /// Scale denominator, for example 50 for 1:50.
  public let scaleDenominator: Int
  /// Paper name, `Letter` or `A3`.
  public let paper: String
  public let landscape: Bool
  /// Length of the printed scale bar in metres of plan (2 at 1:50).
  public let scaleBarMetres: Double
}

/// Scaled vector plan PDF: walls, openings, room labels, object footprints, dimension strings,
/// scale bar, an orientation note and a title block (address, project, floor, capture id, date,
/// operator). Scale 1:50 or 1:100 on Letter or A3, whichever fits (see `PlanSheet`).
///
/// Wall centrelines are stroked 0.5 mm wide as straight `m`/`l`/`S` segments, so a 4.000 m wall
/// at 1:50 is exactly 80.0 mm long in the content stream.
public enum PlanPDFWriter {
  public static let fileName = "plan.pdf"

  private static let mmToPoints = 72.0 / 25.4

  public static func write(model: CaptureModel, context: PlanExportContext) throws
    -> PlanPDFOutput
  {
    let geometry = try PlanGeometry(model: model)
    guard let bounds = geometry.bounds else { throw PlanExportError.noPlanGeometry }
    let sheet = try PlanSheet.choose(bounds: bounds)
    let scene = try PlanScene.build(
      geometry: geometry, scaleDenominator: sheet.scaleDenominator, units: context.displayUnits,
      includeScaleBar: false)

    let page = PDFPage(width: sheet.widthMM * mmToPoints, height: sheet.heightMM * mmToPoints)
    func pt(_ mm: Double) -> Double { mm * mmToPoints }

    // Scene, centred in the drawing area.
    let area = sheet.drawingArea
    let originX = area.x + (area.width - scene.widthMM) / 2
    let originY = area.y + (area.height - scene.heightMM) / 2
    render(scene, on: page, originX: originX, originY: originY)

    // Header.
    let top = sheet.heightMM - PlanSheet.pageMargin
    page.setFillGray(0)
    page.text(
      "Floor plan - \(context.floorLabel)", x: pt(PlanSheet.pageMargin), y: pt(top - 6),
      size: 14, bold: true)
    page.setFillGray(0.3)
    page.text(
      "Reported areas are not verified construction quantities.",
      x: pt(sheet.widthMM - PlanSheet.pageMargin), y: pt(top - 6), size: 7,
      anchor: .trailing)

    // Title block.
    let blockX = PlanSheet.pageMargin
    let blockY = PlanSheet.pageMargin
    let blockW = sheet.widthMM - 2 * PlanSheet.pageMargin
    let blockH = PlanSheet.titleBlockHeight
    page.setStrokeGray(0)
    page.setLineWidth(0.7)
    page.rect(x: pt(blockX), y: pt(blockY), width: pt(blockW), height: pt(blockH), stroke: true, fill: false)
    let leftW = blockW * 0.62
    page.setLineWidth(0.4)
    page.line((pt(blockX + leftW), pt(blockY)), (pt(blockX + leftW), pt(blockY + blockH)))
    let rowH = blockH / 3
    page.line((pt(blockX), pt(blockY + rowH)), (pt(blockX + leftW), pt(blockY + rowH)))
    page.line((pt(blockX), pt(blockY + 2 * rowH)), (pt(blockX + leftW), pt(blockY + 2 * rowH)))

    func cell(_ caption: String, _ value: String, x: Double, row: Int, width: Double) {
      let top = blockY + blockH - Double(row) * rowH
      page.setFillGray(0.4)
      page.text(caption, x: pt(x + 1.5), y: pt(top - 3.2), size: 5)
      page.setFillGray(0)
      let available = pt(width - 3)
      var size = 9.0
      while size > 5, FontMetrics.width(value, size: size) > available { size -= 0.5 }
      page.text(fitted(value, size: size, width: available), x: pt(x + 1.5), y: pt(top - 9), size: size)
    }
    // Row 0 (top): address. Row 1: project, floor. Row 2: capture id, date, operator.
    cell("ADDRESS", context.address, x: blockX, row: 0, width: leftW)
    cell("PROJECT", context.projectLine, x: blockX, row: 1, width: leftW * 0.62)
    cell("FLOOR / AREA", context.floorLabel, x: blockX + leftW * 0.62, row: 1, width: leftW * 0.38)
    cell("CAPTURE ID", context.captureId, x: blockX, row: 2, width: leftW * 0.5)
    cell("DATE (UTC)", context.captureDate, x: blockX + leftW * 0.5, row: 2, width: leftW * 0.2)
    cell("OPERATOR", context.operatorName, x: blockX + leftW * 0.7, row: 2, width: leftW * 0.3)
    page.setLineWidth(0.4)
    page.setStrokeGray(0)
    page.line(
      (pt(blockX + leftW * 0.62), pt(blockY + 2 * rowH)),
      (pt(blockX + leftW * 0.62), pt(blockY + rowH)))
    page.line((pt(blockX + leftW * 0.5), pt(blockY)), (pt(blockX + leftW * 0.5), pt(blockY + rowH)))
    page.line((pt(blockX + leftW * 0.7), pt(blockY)), (pt(blockX + leftW * 0.7), pt(blockY + rowH)))

    // Right panel: scale, scale bar, orientation.
    let rightX = blockX + leftW
    let rightW = blockW - leftW
    page.setFillGray(0.4)
    page.text("SCALE", x: pt(rightX + 1.5), y: pt(blockY + blockH - 3.2), size: 5)
    page.setFillGray(0)
    page.text(
      "1:\(sheet.scaleDenominator)", x: pt(rightX + 1.5), y: pt(blockY + blockH - 9.5), size: 12,
      bold: true)
    page.text(
      "\(sheet.paper.rawValue) \(sheet.landscape ? "landscape" : "portrait")",
      x: pt(rightX + 22), y: pt(blockY + blockH - 9.5), size: 7)
    let barOrigin = Point2(x: rightX + 5, y: blockY + blockH - 17)
    let barScene = PlanScene(
      items: PlanScene.scaleBarItems(scaleDenominator: sheet.scaleDenominator, origin: .init(x: 0, y: 0)),
      widthMM: 0, heightMM: 0, scaleDenominator: sheet.scaleDenominator)
    render(barScene, on: page, originX: barOrigin.x, originY: barOrigin.y)
    page.setFillGray(0.4)
    page.text("ORIENTATION", x: pt(rightX + 1.5), y: pt(blockY + 13.5), size: 5)
    // Arrow pointing up the sheet.
    page.setStrokeGray(0)
    page.setFillGray(0)
    page.setLineWidth(0.8)
    let arrowX = rightX + 6
    page.line((pt(arrowX), pt(blockY + 3)), (pt(arrowX), pt(blockY + 11)))
    page.polyline(
      [
        (pt(arrowX), pt(blockY + 12)), (pt(arrowX - 1.5), pt(blockY + 9)),
        (pt(arrowX + 1.5), pt(blockY + 9)),
      ], closed: true, stroke: false, fill: true)
    page.setFillGray(0)
    page.text("UP", x: pt(arrowX + 3), y: pt(blockY + 6), size: 6, bold: true)
    let note = "True north was not captured. Sheet up is the -Z axis of the capture frame."
    var noteY = blockY + 9.0
    for line in wrap(note, size: 5.5, width: pt(rightW - 18)) {
      page.text(line, x: pt(rightX + 14), y: pt(noteY), size: 5.5)
      noteY -= 2.6
    }

    var document = PDFDocument(
      title: "Floor plan - \(context.floorLabel) - \(context.address)",
      author: context.operatorName,
      subject: "Plan 1:\(sheet.scaleDenominator), capture \(context.captureId)",
      creator: "\(PlanExportInfo.generator) \(PlanExportInfo.generatorVersion)",
      creationDate: context.pdfDate)
    document.pages = [page]
    let file = ExportedFile(
      fileName: fileName, role: .planPDF, mime: "application/pdf", data: document.render())
    return PlanPDFOutput(
      file: file, scaleDenominator: sheet.scaleDenominator, paper: sheet.paper.rawValue,
      landscape: sheet.landscape,
      scaleBarMetres: PlanScene.scaleBarMetres(scaleDenominator: sheet.scaleDenominator))
  }

  // MARK: Rendering

  /// Draws a scene with its origin at (`originX`, `originY`) paper millimetres on the page.
  static func render(_ scene: PlanScene, on page: PDFPage, originX: Double, originY: Double) {
    func pt(_ p: Point2) -> (Double, Double) {
      ((p.x + originX) * mmToPoints, (p.y + originY) * mmToPoints)
    }
    for item in scene.items {
      switch item {
      case .polyline(let points, let closed, let fillGray, let strokeGray, let widthMM, _):
        if let fillGray { page.setFillGray(fillGray) }
        if let strokeGray {
          page.setStrokeGray(strokeGray)
          page.setLineWidth(widthMM * mmToPoints)
        }
        let coordinates = points.map(pt)
        if points.count == 2, strokeGray != nil, fillGray == nil {
          page.line(coordinates[0], coordinates[1])
        } else {
          page.polyline(
            coordinates, closed: closed, stroke: strokeGray != nil, fill: fillGray != nil)
        }
      case .text(let value, let at, let sizeMM, let rotation, let anchor, let bold, let gray, _):
        page.setFillGray(gray)
        let position = pt(at)
        page.text(
          value, x: position.0, y: position.1, size: sizeMM * mmToPoints, bold: bold,
          anchor: anchor == .center ? .center : .leading, rotation: rotation)
      }
    }
  }

  /// `text` cut with an ellipsis when it is wider than `width` points at `size`.
  static func fitted(_ text: String, size: Double, width: Double) -> String {
    if FontMetrics.width(text, size: size) <= width { return text }
    var cut = Array(text)
    while !cut.isEmpty, FontMetrics.width(String(cut) + "...", size: size) > width {
      cut.removeLast()
    }
    return String(cut) + "..."
  }

  /// Greedy word wrap by measured width.
  static func wrap(_ text: String, size: Double, width: Double, bold: Bool = false) -> [String] {
    var lines: [String] = []
    for paragraph in text.components(separatedBy: "\n") {
      var current = ""
      for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
        var word = String(word)
        // Break a word that is wider than the line by characters.
        while FontMetrics.width(word, size: size, bold: bold) > width, word.count > 1 {
          var head = ""
          for character in word {
            if FontMetrics.width(head + String(character), size: size, bold: bold) > width,
              !head.isEmpty
            {
              break
            }
            head.append(character)
          }
          if !current.isEmpty {
            lines.append(current)
            current = ""
          }
          lines.append(head)
          word = String(word.dropFirst(head.count))
        }
        let candidate = current.isEmpty ? word : current + " " + word
        if FontMetrics.width(candidate, size: size, bold: bold) <= width || current.isEmpty {
          current = candidate
        } else {
          lines.append(current)
          current = word
        }
      }
      lines.append(current)
    }
    return lines
  }
}
