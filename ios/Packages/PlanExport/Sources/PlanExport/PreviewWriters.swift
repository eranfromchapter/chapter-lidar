import CaptureContract
import Foundation

/// SVG plan preview. The drawing is in paper millimetres at the chosen plan scale (1:50, 1:100,
/// ...), so the `width` and `height` attributes in `mm` print at true scale. One `<g>` per run
/// of one layer, named after the DXF layer where one exists.
public enum SVGWriter {
  public static let fileName = "plan.svg"

  public static func write(model: CaptureModel, displayUnits: DisplayUnitSystem = .metric) throws
    -> ExportedFile
  {
    let geometry = try PlanGeometry(model: model)
    guard let bounds = geometry.bounds else { throw PlanExportError.noPlanGeometry }
    let sheet = try PlanSheet.choose(bounds: bounds)
    let scene = try PlanScene.build(
      geometry: geometry, scaleDenominator: sheet.scaleDenominator, units: displayUnits,
      includeScaleBar: true)
    let text = render(scene: scene, model: model)
    return ExportedFile(
      fileName: fileName, role: .planSVG, mime: "image/svg+xml", data: Data(text.utf8))
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

  /// The Chapter tone of a scene gray (`ChapterBrand.tone`).
  private static func hex(_ gray: Double) -> String {
    ChapterBrand.tone(gray).hexString
  }

  private static func render(scene: PlanScene, model: CaptureModel) -> String {
    let width = scene.widthMM
    let height = scene.heightMM
    func n(_ value: Double) -> String { Format.fixed(value, 3) }
    func x(_ p: Point2) -> String { n(p.x) }
    func y(_ p: Point2) -> String { n(height - p.y) }
    var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    out +=
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(width))mm\" height=\"\(n(height))mm\" "
      + "viewBox=\"0 0 \(n(width)) \(n(height))\">\n"
    out += "  <title>\(escape("Floor plan - \(model.label)")) (1:\(scene.scaleDenominator))</title>\n"
    out +=
      "  <desc>\(escape("Capture \(model.captureId.rawValue). Plan at 1:\(scene.scaleDenominator); units are paper millimetres. Reported areas are not verified construction quantities."))</desc>\n"
    out += "  <rect x=\"0\" y=\"0\" width=\"\(n(width))\" height=\"\(n(height))\" fill=\"#ffffff\"/>\n"
    var openLayer: SceneLayer?
    func open(_ layer: SceneLayer) {
      if openLayer == layer { return }
      if openLayer != nil { out += "  </g>\n" }
      out += "  <g class=\"\(layer.rawValue)\">\n"
      openLayer = layer
    }
    for item in scene.items {
      switch item {
      case .polyline(let points, let closed, let fillGray, let strokeGray, let widthMM, let layer):
        open(layer)
        let pointList = points.map { "\(x($0)),\(y($0))" }.joined(separator: " ")
        let fill = fillGray.map { hex($0) } ?? "none"
        let stroke = strokeGray.map { hex($0) } ?? "none"
        let tag = closed ? "polygon" : "polyline"
        out +=
          "    <\(tag) points=\"\(pointList)\" fill=\"\(fill)\" stroke=\"\(stroke)\" "
          + "stroke-width=\"\(n(widthMM))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
      case .text(let value, let at, let sizeMM, let rotation, let anchor, let bold, let gray, let layer):
        open(layer)
        let transform =
          rotation == 0 ? "" : " transform=\"rotate(\(n(-rotation)) \(x(at)) \(y(at)))\""
        out +=
          "    <text x=\"\(x(at))\" y=\"\(y(at))\" font-family=\"\(ChapterBrand.sansFamily)\" "
          + "font-size=\"\(n(sizeMM))\" text-anchor=\"\(anchor == .center ? "middle" : "start")\" "
          + "fill=\"\(hex(gray))\"\(bold ? " font-weight=\"\(ChapterBrand.boldWeight)\"" : "")\(transform)>"
          + "\(escape(value))</text>\n"
      }
    }
    if openLayer != nil { out += "  </g>\n" }
    out += "</svg>\n"
    return out
  }
}

/// PNG plan preview at 300 dpi: the plan at its sheet scale (1:50, 1:100, ...) rasterised at
/// 300 pixels per paper inch, 8-bit RGB in the Chapter tones of plan.pdf and plan.svg, with a
/// `pHYs` chunk. Labels use a built-in 5 x 7 capital-letter font.
public enum PNGWriter {
  public static let fileName = "plan.png"
  public static let dpi = 300

  /// The colour of each gray level of the raster: `ChapterBrand.tone` of the level, as the PDF
  /// and SVG paint the scene grays. `tone` steps from the warm surface colour to white at
  /// paper, so the levels lighter than the room fill (which only anti-aliased edges against
  /// paper or a wall gap produce) run straight from the room fill tone to white instead.
  static let colors: [DrawingColor] = (0...255).map { level in
    let gray = Double(level) / 255
    let knee = PlanScene.roomFillGray
    guard gray > knee else { return ChapterBrand.tone(gray) }
    let from = ChapterBrand.tone(knee)
    let t = (gray - knee) / (1 - knee)
    func mix(_ a: Double) -> Double { a + (1 - a) * t }
    return DrawingColor(mix(from.red), mix(from.green), mix(from.blue))
  }

  public static func write(model: CaptureModel, displayUnits: DisplayUnitSystem = .metric) throws
    -> ExportedFile
  {
    let geometry = try PlanGeometry(model: model)
    guard let bounds = geometry.bounds else { throw PlanExportError.noPlanGeometry }
    let sheet = try PlanSheet.choose(bounds: bounds)
    let scene = try PlanScene.build(
      geometry: geometry, scaleDenominator: sheet.scaleDenominator, units: displayUnits,
      includeScaleBar: true)
    let pixelsPerMM = Double(dpi) / 25.4
    let width = max(1, Int((scene.widthMM * pixelsPerMM).rounded(.up)))
    let height = max(1, Int((scene.heightMM * pixelsPerMM).rounded(.up)))
    var canvas = GrayCanvas(width: width, height: height)
    func px(_ p: Point2) -> Point2 {
      Point2(x: p.x * pixelsPerMM, y: (scene.heightMM - p.y) * pixelsPerMM)
    }
    for item in scene.items {
      switch item {
      case .polyline(let points, let closed, let fillGray, let strokeGray, let widthMM, _):
        let pixelPoints = points.map(px)
        if let fillGray, closed { canvas.fill(pixelPoints, gray: fillGray) }
        if let strokeGray {
          let count = closed ? pixelPoints.count : pixelPoints.count - 1
          for index in 0..<max(0, count) {
            canvas.stroke(
              from: pixelPoints[index], to: pixelPoints[(index + 1) % pixelPoints.count],
              width: widthMM * pixelsPerMM, gray: strokeGray)
          }
        }
      case .text(let value, let at, let sizeMM, let rotation, let anchor, let bold, let gray, _):
        canvas.text(
          value, origin: px(at), emPixels: sizeMM * pixelsPerMM, rotation: rotation,
          centered: anchor == .center, bold: bold, gray: gray)
      }
    }
    let data = PNGEncoder.encodeRGB(
      width: width, height: height, pixels: canvas.pixels, colors: colors, dpi: dpi)
    return ExportedFile(fileName: fileName, role: .planPNG, mime: "image/png", data: data)
  }
}

/// Everything PlanExport writes for one capture.
public enum PlanExporter {
  /// DXF, CSV, plan PDF, Spatial Report PDF, PNG and SVG for one capture (one floor or area),
  /// in that order. `record` supplies the title-block metadata; the capture is found in it by
  /// the model's `captureId`.
  public static func exportAll(model: CaptureModel, record: CaptureRecord) throws
    -> [ExportedFile]
  {
    let context = try PlanExportContext(record: record, captureId: model.captureId)
    return [
      try DXFWriter.write(model: model),
      try CSVWriter.write(model: model),
      try PlanPDFWriter.write(model: model, context: context).file,
      try SpatialReportWriter.write(model: model, context: context),
      try PNGWriter.write(model: model, displayUnits: context.displayUnits),
      try SVGWriter.write(model: model, displayUnits: context.displayUnits),
    ]
  }
}
