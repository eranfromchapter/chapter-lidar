import CaptureContract
import Foundation

// Writers for `FloorPlanDrawing`: onto a PDF page and as SVG. The one-page floor plan with its
// title, address and total area is `FloorplanWriter`.

extension FloorPlanDrawing {
  /// Draws the drawing on `page` with its bounds' lower-left corner at (`x`, `y`) points, at
  /// its own scale (1:`options.scaleDenominator`).
  func render(on page: PDFPage, x: Double, y: Double) {
    let scale = 72.0 / 25.4 / options.scaleDenominator
    var renderer = PDFDrawingRenderer(
      page: page, scale: scale, offsetX: x - bounds.minX * scale,
      offsetY: y - bounds.minY * scale)
    renderer.draw(items)
  }

  /// One-page PDF of the drawing alone, printed at its scale with a `marginMM` margin.
  public func pdf(
    title: String, creationDate: String = "D:20260101000000Z", marginMM: Double = 10
  ) -> Data {
    let mm = 72.0 / 25.4
    let margin = marginMM
    let width = bounds.width / options.scaleDenominator + 2 * margin
    let height = bounds.height / options.scaleDenominator + 2 * margin
    let page = PDFPage(width: width * mm, height: height * mm)
    render(on: page, x: margin * mm, y: margin * mm)
    var document = PDFDocument(
      title: title, author: "Chapter", subject: "Floor plan",
      creator: "\(PlanExportInfo.generator) \(PlanExportInfo.floorplanVersion)",
      creationDate: creationDate)
    document.pages = [page]
    return document.render()
  }

  /// SVG document of the drawing. The view box is in plan millimetres; `width` and `height`
  /// are paper millimetres at 1:`options.scaleDenominator`, so it prints to scale.
  public func svg(title: String) -> String {
    let b = bounds
    func n(_ value: Double) -> String { Format.fixed(value, 2) }
    let denominator = options.scaleDenominator
    var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    out +=
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(b.width / denominator))mm\" "
      + "height=\"\(n(b.height / denominator))mm\" viewBox=\"0 0 \(n(b.width)) \(n(b.height))\">\n"
    out += "  <title>\(SVGWriter.escape(title))</title>\n"
    let note =
      "Plan millimetres, drawn for 1:\(Format.compact(denominator)). Wall thicknesses are "
      + "assumed; measurements are estimates."
    out += "  <desc>\(SVGWriter.escape(note))</desc>\n"
    out +=
      "  <rect x=\"0\" y=\"0\" width=\"\(n(b.width))\" height=\"\(n(b.height))\" "
      + "fill=\"#ffffff\"/>\n"
    out += DrawingSVG.elements(items, minX: b.minX, maxY: b.maxY)
    out += "</svg>\n"
    return out
  }
}

/// SVG elements for drawing primitives: one `<g class="layer">` per run of items on the same
/// layer, paths with their fill and stroke, text in Inter (Times for serif text), and
/// clipped groups. Coordinates are moved so `minX` is 0 and flipped so `maxY` is the top (SVG
/// y runs down), two decimals.
enum DrawingSVG {
  static func elements(_ items: [DrawingItem], minX: Double, maxY: Double) -> String {
    func n(_ value: Double) -> String { Format.fixed(value, 2) }
    func point(_ p: DrawingPoint) -> String { "\(n(p.x - minX)) \(n(maxY - p.y))" }
    func path(_ path: DrawingPath) -> String {
      path.elements.map { element -> String in
        switch element {
        case .move(let p): return "M\(point(p))"
        case .line(let p): return "L\(point(p))"
        case .curve(let c1, let c2, let p): return "C\(point(c1)) \(point(c2)) \(point(p))"
        case .close: return "Z"
        }
      }.joined(separator: " ")
    }
    var out = ""
    var openLayer: DrawingLayer?
    var clipCount = 0
    func open(_ layer: DrawingLayer, indent: String) {
      if openLayer == layer { return }
      if openLayer != nil { out += "\(indent)</g>\n" }
      out += "\(indent)<g class=\"\(layer.rawValue)\">\n"
      openLayer = layer
    }
    func emit(_ item: DrawingItem, indent: String) {
      switch item {
      case .shape(let shape):
        open(shape.layer, indent: indent)
        var attributes = "d=\"\(path(shape.path))\""
        attributes += " fill=\"\(shape.fill?.hexString ?? "none")\""
        if shape.fill != nil && shape.evenOdd { attributes += " fill-rule=\"evenodd\"" }
        if let stroke = shape.stroke {
          attributes +=
            " stroke=\"\(stroke.color.hexString)\" stroke-width=\"\(n(stroke.width))\""
            + " stroke-linecap=\"\(stroke.cap.rawValue)\""
            + " stroke-linejoin=\"\(stroke.join.rawValue)\""
          if !stroke.dash.isEmpty {
            attributes += " stroke-dasharray=\"\(stroke.dash.map(n).joined(separator: " "))\""
          }
        }
        out += "\(indent)  <path \(attributes)/>\n"
      case .text(let text):
        open(text.layer, indent: indent)
        let x = n(text.position.x - minX)
        let y = n(maxY - text.position.y)
        let anchor: String
        switch text.anchor {
        case .leading: anchor = "start"
        case .center: anchor = "middle"
        case .trailing: anchor = "end"
        }
        let rotate =
          text.rotationDegrees == 0
          ? "" : " transform=\"rotate(\(n(-text.rotationDegrees)) \(x) \(y))\""
        let family: String
        // Weight of SemiBold, or the italic of Times-Italic.
        var weight = ""
        switch text.font {
        case .interRegular: family = ChapterBrand.sansFamily
        case .interSemiBold:
          family = ChapterBrand.sansFamily
          weight = " font-weight=\"\(ChapterBrand.boldWeight)\""
        case .timesRoman: family = ChapterBrand.serifFamily
        case .timesItalic:
          family = ChapterBrand.serifFamily
          weight = " font-style=\"italic\""
        case .courier: family = ChapterBrand.monoFamily
        }
        let spacing = text.letterSpacing == 0 ? "" : " letter-spacing=\"\(n(text.letterSpacing))\""
        out +=
          "\(indent)  <text x=\"\(x)\" y=\"\(y)\" font-family=\"\(family)\" "
          + "font-size=\"\(n(text.size))\" text-anchor=\"\(anchor)\" "
          + "fill=\"\(text.color.hexString)\"\(weight)\(spacing)"
          + "\(rotate)>\(SVGWriter.escape(text.string))</text>\n"
      case .clipped(let clip, let children):
        if openLayer != nil {
          out += "\(indent)</g>\n"
          openLayer = nil
        }
        clipCount += 1
        out += "\(indent)<clipPath id=\"clip\(clipCount)\"><path d=\"\(path(clip))\"/></clipPath>\n"
        out += "\(indent)<g clip-path=\"url(#clip\(clipCount))\">\n"
        for child in children { emit(child, indent: indent + "  ") }
        if openLayer != nil {
          out += "\(indent)  </g>\n"
          openLayer = nil
        }
        out += "\(indent)</g>\n"
      }
    }
    for item in items { emit(item, indent: "  ") }
    if openLayer != nil { out += "  </g>\n" }
    return out
  }
}

/// Writes drawing primitives into a PDF page, setting colour and line state only when it
/// changes.
struct PDFDrawingRenderer {
  let page: PDFPage
  /// Points per plan millimetre.
  let scale: Double
  let offsetX: Double
  let offsetY: Double

  private var fill: DrawingColor?
  private var stroke: DrawingColor?
  private var width: Double?
  private var dash: [Double]?
  private var cap: DrawingLineCap?
  private var join: DrawingLineJoin?

  init(page: PDFPage, scale: Double, offsetX: Double, offsetY: Double) {
    self.page = page
    self.scale = scale
    self.offsetX = offsetX
    self.offsetY = offsetY
  }

  private func x(_ p: DrawingPoint) -> Double { offsetX + p.x * scale }
  private func y(_ p: DrawingPoint) -> Double { offsetY + p.y * scale }

  func pdfPath(_ path: DrawingPath) -> PDFPage.Path {
    var out = PDFPage.Path()
    for element in path.elements {
      switch element {
      case .move(let p): out.move(x(p), y(p))
      case .line(let p): out.line(x(p), y(p))
      case .curve(let a, let b, let c): out.curve(x(a), y(a), x(b), y(b), x(c), y(c))
      case .close: out.close()
      }
    }
    return out
  }

  private mutating func setFill(_ color: DrawingColor) {
    guard fill != color else { return }
    page.setFillRGB(color.red, color.green, color.blue)
    fill = color
  }

  private mutating func setStroke(_ value: DrawingStroke) {
    if stroke != value.color {
      page.setStrokeRGB(value.color.red, value.color.green, value.color.blue)
      stroke = value.color
    }
    if width != value.width {
      page.setLineWidth(value.width * scale)
      width = value.width
    }
    if dash != value.dash {
      page.setDash(value.dash.map { $0 * scale })
      dash = value.dash
    }
    if cap != value.cap {
      switch value.cap {
      case .butt: page.setLineCap(.butt)
      case .round: page.setLineCap(.round)
      case .square: page.setLineCap(.square)
      }
      cap = value.cap
    }
    if join != value.join {
      switch value.join {
      case .miter: page.setLineJoin(.miter)
      case .round: page.setLineJoin(.round)
      case .bevel: page.setLineJoin(.bevel)
      }
      join = value.join
    }
  }

  mutating func draw(_ items: [DrawingItem]) {
    for item in items {
      switch item {
      case .shape(let shape):
        guard !shape.path.elements.isEmpty else { continue }
        if let color = shape.fill { setFill(color) }
        if let value = shape.stroke { setStroke(value) }
        let paint: PDFPage.Paint
        switch (shape.fill != nil, shape.stroke != nil) {
        case (true, true): paint = shape.evenOdd ? .fillEvenOddStroke : .fillStroke
        case (true, false): paint = shape.evenOdd ? .fillEvenOdd : .fill
        case (false, true): paint = .stroke
        case (false, false): continue
        }
        page.path(pdfPath(shape.path), paint: paint)
      case .text(let text):
        setFill(text.color)
        let anchor: PDFPage.Anchor
        switch text.anchor {
        case .leading: anchor = .leading
        case .center: anchor = .center
        case .trailing: anchor = .trailing
        }
        page.text(
          text.string, x: x(text.position), y: y(text.position), size: text.size * scale,
          font: text.font, anchor: anchor, rotation: text.rotationDegrees,
          letterSpacing: text.letterSpacing * scale)
      case .clipped(let clip, let children):
        page.saveState()
        page.clip(pdfPath(clip))
        var inner = self
        inner.draw(children)
        page.restoreState()
      }
    }
  }
}
