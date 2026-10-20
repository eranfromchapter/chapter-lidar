import Foundation

/// Chapter's colours, type and logo for every plan and report this package writes.
///
/// Colours come from hellochapter.com (the brand black #231F20, the warm sand, blush and stone
/// tints) and the Chapter Capture design tokens (muted #6B6557, line #D9CCBC, surface #FAF5EE).
/// Type is the brand pair: Times for titles and Inter for everything else. PDFs embed Inter
/// (`ChapterBrandAssets`) and use the standard Times-Roman; SVGs name the fonts with fallbacks.
enum ChapterBrand {
  /// Brand black: logo, titles, outside dimensions.
  static let ink = DrawingColor(hex: 0x231F20)
  /// Secondary text: notes, captions.
  static let muted = DrawingColor(hex: 0x6B6557)
  /// Hairlines and table rules.
  static let line = DrawingColor(hex: 0xD9CCBC)
  /// Warm off-white: table headers and panels.
  static let surface = DrawingColor(hex: 0xFAF5EE)
  /// Warm nude: table header fill.
  static let nude = DrawingColor(hex: 0xE8DDD0)
  /// Warm charcoal walls.
  static let wall = DrawingColor(hex: 0x4D4744)
  /// Furniture, fixture and appliance outlines, and the lighter outline of overhead or
  /// low-confidence ones.
  static let symbol = DrawingColor(hex: 0x8E8781)
  static let faintSymbol = DrawingColor(hex: 0xBDB8B8)
  /// Bronze accent: inside dimensions (text, then the paler line).
  static let accent = DrawingColor(hex: 0x7A6347)
  static let accentLine = DrawingColor(hex: 0xB39F87)

  /// The Chapter tone for a gray level of the plain plan drawings (0 black, 1 white): the
  /// brand black at 0, white at 1, and warm grays from the brand black to the surface colour
  /// between, so their gray scheme reads in Chapter's warm palette.
  static func tone(_ gray: Double) -> DrawingColor {
    let g = max(0, min(1, gray))
    if g >= 0.999 { return .white }
    func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * g }
    return DrawingColor(
      mix(ink.red, surface.red), mix(ink.green, surface.green), mix(ink.blue, surface.blue))
  }

  /// SVG font families: the brand fonts first, then close system fonts.
  static let sansFamily = "Inter, 'Helvetica Neue', Helvetica, Arial, sans-serif"
  static let serifFamily = "Times, 'Times New Roman', serif"
  /// SVG weight of bold sans text (Inter SemiBold, as the PDFs embed).
  static let boldWeight = "600"
}

/// The Chapter logo, "chapter" over "RENOVATION", as filled vector paths.
enum ChapterLogo {
  enum Element: Sendable {
    case move(Double, Double)
    case curve(Double, Double, Double, Double, Double, Double)
    case close
  }

  /// Width over height of the logo.
  static var aspect: Double { ChapterBrandAssets.logoWidth / ChapterBrandAssets.logoHeight }

  /// The logo's paths in logo units, y up from the lower left (parsed once).
  static let paths: [[Element]] = ChapterBrandAssets.logoPaths.map(parse)

  static func parse(_ text: String) -> [Element] {
    var elements: [Element] = []
    var command: Character = "M"
    var numbers: [Double] = []
    func flush() {
      switch command {
      case "M":
        var i = 0
        while i + 1 < numbers.count {
          elements.append(.move(numbers[i], numbers[i + 1]))
          i += 2
        }
      case "C":
        var i = 0
        while i + 5 < numbers.count {
          elements.append(
            .curve(
              numbers[i], numbers[i + 1], numbers[i + 2], numbers[i + 3], numbers[i + 4],
              numbers[i + 5]))
          i += 6
        }
      default:
        break
      }
      numbers.removeAll(keepingCapacity: true)
    }
    for token in text.split(whereSeparator: \.isWhitespace) {
      if let value = Double(token) {
        numbers.append(value)
      } else if let letter = token.first {
        flush()
        command = letter
        if letter == "Z" { elements.append(.close) }
      }
    }
    flush()
    return elements
  }

  /// Width of the logo drawn `height` tall.
  static func width(height: Double) -> Double { height * aspect }

  /// The logo as drawing shapes, `height` tall with its lower left corner at (`x`, `y`), in
  /// the drawing's units (y up). One shape per path, each filled nonzero, as the logo is drawn.
  static func items(
    x: Double, y: Double, height: Double, color: DrawingColor = ChapterBrand.ink,
    layer: DrawingLayer = .sheet
  ) -> [DrawingItem] {
    let s = height / ChapterBrandAssets.logoHeight
    func point(_ px: Double, _ py: Double) -> DrawingPoint {
      DrawingPoint(x: x + px * s, y: y + py * s)
    }
    return paths.map { elements in
      let path = DrawingPath(
        elements: elements.map { element in
          switch element {
          case .move(let px, let py): return .move(point(px, py))
          case .curve(let a, let b, let c, let d, let e, let f):
            return .curve(point(a, b), point(c, d), point(e, f))
          case .close: return .close
          }
        })
      return .shape(DrawingShape(path: path, fill: color, layer: layer))
    }
  }

  /// Draws the logo on a PDF page in the brand black, `height` points tall with its lower left
  /// corner at (`x`, `y`) points. Leaves the fill colour set to the brand black.
  static func draw(on page: PDFPage, x: Double, y: Double, height: Double) {
    let s = height / ChapterBrandAssets.logoHeight
    let ink = ChapterBrand.ink
    page.setFillRGB(ink.red, ink.green, ink.blue)
    for elements in paths {
      var path = PDFPage.Path()
      for element in elements {
        switch element {
        case .move(let px, let py): path.move(x + px * s, y + py * s)
        case .curve(let a, let b, let c, let d, let e, let f):
          path.curve(x + a * s, y + b * s, x + c * s, y + d * s, x + e * s, y + f * s)
        case .close: path.close()
        }
      }
      page.path(path, paint: .fill)
    }
  }
}

extension PDFPage {
  /// Fill colour (text is painted in it).
  func setFill(_ color: DrawingColor) { setFillRGB(color.red, color.green, color.blue) }
  func setStroke(_ color: DrawingColor) { setStrokeRGB(color.red, color.green, color.blue) }
}
