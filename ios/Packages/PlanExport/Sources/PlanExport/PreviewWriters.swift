import CaptureContract
import Foundation

/// The previews of the plan sheet (plan-sheet §7): the sheet's own drawing (same rendition,
/// scale and quarter turn as the chosen sheet layout) without the title block, north arrow,
/// scale bar or footnote, on white, with a 6 mm margin.
enum PlanPreview {
  /// Margin around the drawing, paper millimetres.
  static let marginMM = 6.0

  /// The drawing's items with the window clears in the preview's white paper instead of the
  /// sheet's page colour.
  static func items(_ drawing: FloorPlanDrawing, dimensions: Bool) -> [DrawingItem] {
    drawing.items.compactMap { item in
      switch item {
      case .shape(var shape):
        if shape.layer == .exteriorDimension, !dimensions { return nil }
        if shape.layer == .window, shape.fill != nil { shape.fill = .white }
        return .shape(shape)
      case .text(let text):
        if text.layer == .exteriorDimension, !dimensions { return nil }
        return item
      case .clipped:
        return item
      }
    }
  }
}

/// SVG plan preview `plan.svg` (`plan_svg`): the plan sheet's drawing with its dimension
/// strings, in paper millimetres at the sheet's scale (`width` and `height` in mm print at true
/// scale; the view box is in plan millimetres), on white. Room names in Inter (weight 600 for
/// SemiBold, with their letter spacing), dimensions in Courier. One `<g>` per run of one layer.
public enum SVGWriter {
  public static let fileName = "plan.svg"

  /// The preview of `model`, laid out as its plan sheet is (`PlanSheetWriter`).
  public static func write(model: CaptureModel, context: PlanExportContext) throws -> ExportedFile
  {
    let sheet = try PlanSheetWriter.write(model: model, context: context)
    return write(sheet: sheet, label: context.floorLabel)
  }

  /// The preview of a written plan sheet's drawing.
  public static func write(sheet: PlanSheetOutput, label: String) -> ExportedFile {
    let drawing = sheet.drawing
    let n = drawing.options.scaleDenominator
    let items = PlanPreview.items(drawing, dimensions: true)
    let extent = FloorPlanDrawing.extent(of: items)
    let margin = PlanPreview.marginMM * n
    let minX = extent.minX - margin
    let maxY = extent.maxY + margin
    let widthMM = extent.width + 2 * margin
    let heightMM = extent.height + 2 * margin
    func p(_ value: Double) -> String { Format.fixed(value, 2) }
    var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    out +=
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(p(widthMM / n))mm\" "
      + "height=\"\(p(heightMM / n))mm\" viewBox=\"0 0 \(p(widthMM)) \(p(heightMM))\">\n"
    out += "  <title>\(escape("Floor plan - \(label) (1:\(sheet.scaleDenominator))"))</title>\n"
    let note =
      "Plan millimetres, drawn for 1:\(sheet.scaleDenominator). Wall thickness is assumed "
      + "(4.5 in inside, 6 in outside); measurements are scan estimates."
    out += "  <desc>\(escape(note))</desc>\n"
    out +=
      "  <rect x=\"0\" y=\"0\" width=\"\(p(widthMM))\" height=\"\(p(heightMM))\" "
      + "fill=\"#ffffff\"/>\n"
    out += DrawingSVG.elements(items, minX: minX, maxY: maxY)
    out += "</svg>\n"
    return ExportedFile(
      fileName: fileName, role: .planSVG, mime: "image/svg+xml", data: Data(out.utf8))
  }

  /// XML text with the five predefined entities; control characters become spaces.
  static func escape(_ text: String) -> String {
    var out = ""
    for scalar in Format.singleLine(text).unicodeScalars {
      switch scalar {
      case "&": out += "&amp;"
      case "<": out += "&lt;"
      case ">": out += "&gt;"
      case "\"": out += "&quot;"
      case "'": out += "&apos;"
      default:
        // Not valid in XML 1.0.
        if scalar.value == 0xFFFE || scalar.value == 0xFFFF
          || (0xD800...0xDFFF).contains(scalar.value)
        {
          out += " "
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    return out
  }
}

/// PNG plan preview `plan.png` (`plan_png`, the HUB web preview): the plan sheet's drawing
/// without its dimension strings (there are no Courier outlines in pure Swift, and the preview
/// shows none), rasterised at 300 pixels per paper inch at the sheet's scale with a 6 mm
/// margin, 8-bit RGB on white, labels from the outlines of the Inter fonts the PDFs embed,
/// with a `pHYs` chunk (300 dpi). Same bytes for the same capture.
public enum PNGWriter {
  public static let fileName = "plan.png"
  public static let dpi = 300

  /// The preview of `model`, laid out as its plan sheet is (`PlanSheetWriter`).
  public static func write(model: CaptureModel, context: PlanExportContext) throws -> ExportedFile
  {
    try write(sheet: PlanSheetWriter.write(model: model, context: context))
  }

  /// The preview of a written plan sheet's drawing.
  public static func write(sheet: PlanSheetOutput) -> ExportedFile {
    let drawing = sheet.drawing
    let n = drawing.options.scaleDenominator
    let items = PlanPreview.items(drawing, dimensions: false)
    let extent = FloorPlanDrawing.extent(of: items)
    let margin = PlanPreview.marginMM * n
    // Pixels per plan millimetre: 300 per paper inch at 1:n.
    let scale = Double(dpi) / 25.4 / n
    let width = max(1, Int(((extent.width + 2 * margin) * scale).rounded(.up)))
    let height = max(1, Int(((extent.height + 2 * margin) * scale).rounded(.up)))
    var canvas = RasterCanvas(width: width, height: height, background: .white)
    let minX = extent.minX - margin
    let maxY = extent.maxY + margin
    canvas.draw(items, scale: scale) { p in
      Point2(x: (p.x - minX) * scale, y: (maxY - p.y) * scale)
    }
    let data = PNGEncoder.encodeRGB(
      width: width, height: height, rgb: canvas.pixels, dpi: dpi)
    return ExportedFile(fileName: fileName, role: .planPNG, mime: "image/png", data: data)
  }
}

/// Everything PlanExport writes for one capture.
public enum PlanExporter {
  /// The five files of one capture (one floor or area), in this order: `plan.dxf`, `rooms.csv`,
  /// the plan sheet `plan-sheet.pdf` (role `plan_pdf`), `plan.png` and `plan.svg` (the sheet's
  /// drawing). `record` supplies the title-block metadata and the compass reading; the capture
  /// is found in it by the model's `captureId`. No spatial report: the station makes it after
  /// its checks.
  public static func exportAll(model: CaptureModel, record: CaptureRecord) throws
    -> [ExportedFile]
  {
    let context = try PlanExportContext(record: record, captureId: model.captureId)
    let sheet = try PlanSheetWriter.write(model: model, context: context)
    return [
      try DXFWriter.write(model: model),
      try CSVWriter.write(model: model),
      sheet.file,
      PNGWriter.write(sheet: sheet),
      SVGWriter.write(sheet: sheet, label: context.floorLabel),
    ]
  }
}
