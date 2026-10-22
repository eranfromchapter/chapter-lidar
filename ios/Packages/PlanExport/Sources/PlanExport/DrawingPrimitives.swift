import Foundation

// Vector primitives of a drawing: paths of lines and cubic Beziers, filled and/or stroked, and
// text. Coordinates are plan millimetres (x right, y up the sheet); line widths, dash lengths
// and text sizes are plan millimetres too, chosen for one print scale (see `FloorPlanDrawing`).
// The PDF and SVG writers draw these primitives as they are, scaled to paper.

/// A colour, red, green and blue from 0 to 1.
public struct DrawingColor: Hashable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double

  public init(_ red: Double, _ green: Double, _ blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// From `0xRRGGBB`.
  public init(hex: UInt32) {
    self.init(
      Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
  }

  /// `#rrggbb`, lower case.
  public var hexString: String {
    func pair(_ value: Double) -> String {
      let byte = Int((max(0, min(1, value)) * 255).rounded())
      let digits = String(byte, radix: 16)
      return digits.count == 1 ? "0" + digits : digits
    }
    return "#" + pair(red) + pair(green) + pair(blue)
  }

  public static let white = DrawingColor(1, 1, 1)
}

/// A point in plan millimetres.
public struct DrawingPoint: Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// One or more subpaths of straight lines and cubic Bezier curves.
public struct DrawingPath: Hashable, Sendable {
  public enum Element: Hashable, Sendable {
    case move(DrawingPoint)
    case line(DrawingPoint)
    /// First control point, second control point, end point.
    case curve(DrawingPoint, DrawingPoint, DrawingPoint)
    case close
  }

  public var elements: [Element]

  public init(elements: [Element] = []) {
    self.elements = elements
  }

  /// Every anchor and control point, in order. The curve control points bound the curve, so
  /// these also bound the path.
  public var points: [DrawingPoint] {
    elements.flatMap { element -> [DrawingPoint] in
      switch element {
      case .move(let p), .line(let p): return [p]
      case .curve(let a, let b, let c): return [a, b, c]
      case .close: return []
      }
    }
  }

  /// Appends another path's subpaths.
  mutating func append(_ other: DrawingPath) {
    elements += other.elements
  }
}

public enum DrawingLineCap: String, Hashable, Sendable {
  case butt
  case round
  case square
}

public enum DrawingLineJoin: String, Hashable, Sendable {
  case miter
  case round
  case bevel
}

public struct DrawingStroke: Hashable, Sendable {
  public var color: DrawingColor
  /// Plan millimetres.
  public var width: Double
  /// Alternating dash and gap lengths in plan millimetres; empty for a solid line.
  public var dash: [Double]
  public var cap: DrawingLineCap
  public var join: DrawingLineJoin

  public init(
    color: DrawingColor, width: Double, dash: [Double] = [], cap: DrawingLineCap = .butt,
    join: DrawingLineJoin = .miter
  ) {
    self.color = color
    self.width = width
    self.dash = dash
    self.cap = cap
    self.join = join
  }
}

/// What a primitive draws; the SVG writer groups by layer.
public enum DrawingLayer: String, Hashable, Sendable, CaseIterable {
  case roomFill = "room-fill"
  case symbol = "symbol"
  case wall = "wall"
  case door = "door"
  case window = "window"
  case opening = "opening"
  case interiorDimension = "dimension-interior"
  case exteriorDimension = "dimension-exterior"
  case roomLabel = "room-label"
  case compass = "compass"
  case scaleBar = "scale-bar"
  /// Title, address, notes and the logo around a drawing on a page.
  case sheet = "sheet"
}

public struct DrawingShape: Hashable, Sendable {
  public var path: DrawingPath
  public var fill: DrawingColor?
  /// Fill rule: even-odd when true, nonzero winding otherwise. Nonzero fills overlapping
  /// subpaths of the same orientation as their union.
  public var evenOdd: Bool
  public var stroke: DrawingStroke?
  public var layer: DrawingLayer

  public init(
    path: DrawingPath, fill: DrawingColor? = nil, evenOdd: Bool = false,
    stroke: DrawingStroke? = nil, layer: DrawingLayer
  ) {
    self.path = path
    self.fill = fill
    self.evenOdd = evenOdd
    self.stroke = stroke
    self.layer = layer
  }
}

public enum DrawingTextAnchor: String, Hashable, Sendable {
  case leading
  case center
  case trailing
}

/// The fonts of the plans: Inter (the Chapter sans, embedded in every PDF) in its two weights,
/// Times for titles and the tagline, and Courier for ids, dimensions and scale labels (PDF
/// base-14 fonts, WinAnsi).
public enum DrawingFont: String, CaseIterable, Hashable, Sendable {
  case interRegular
  case interSemiBold
  case timesRoman
  case timesItalic
  case courier

  /// Inter SemiBold when `bold`, Times-Roman when `serif` (whatever `bold`), else Inter Regular.
  init(bold: Bool, serif: Bool) {
    self = serif ? .timesRoman : bold ? .interSemiBold : .interRegular
  }

  var isSerif: Bool { self == .timesRoman || self == .timesItalic }
}

/// One line of text in one of the plan fonts (`DrawingFont`): Inter by default, Times for
/// titles, Courier for dimensions and ids.
public struct DrawingText: Hashable, Sendable {
  public var string: String
  /// Baseline point at the anchor, plan millimetres.
  public var position: DrawingPoint
  /// Font size (em), plan millimetres.
  public var size: Double
  /// Counter-clockwise turn about `position`, degrees.
  public var rotationDegrees: Double
  public var anchor: DrawingTextAnchor
  public var font: DrawingFont
  /// Extra space after each character, plan millimetres.
  public var letterSpacing: Double
  public var color: DrawingColor
  public var layer: DrawingLayer

  /// Inter SemiBold. Setting it switches between the two Inter weights; a Times or Courier
  /// text keeps its font.
  public var bold: Bool {
    get { font == .interSemiBold }
    set {
      if newValue, font == .interRegular { font = .interSemiBold }
      if !newValue, font == .interSemiBold { font = .interRegular }
    }
  }

  /// Times (Roman or Italic). Setting it true sets Times-Roman; false sets Inter Regular.
  public var serif: Bool {
    get { font.isSerif }
    set {
      if newValue, !font.isSerif { font = .timesRoman }
      if !newValue, font.isSerif { font = .interRegular }
    }
  }

  public init(
    _ string: String, position: DrawingPoint, size: Double, rotationDegrees: Double = 0,
    anchor: DrawingTextAnchor = .center, bold: Bool = false, serif: Bool = false,
    letterSpacing: Double = 0, color: DrawingColor, layer: DrawingLayer
  ) {
    self.init(
      string, position: position, size: size, rotationDegrees: rotationDegrees, anchor: anchor,
      font: DrawingFont(bold: bold, serif: serif), letterSpacing: letterSpacing, color: color,
      layer: layer)
  }

  public init(
    _ string: String, position: DrawingPoint, size: Double, rotationDegrees: Double = 0,
    anchor: DrawingTextAnchor = .center, font: DrawingFont, letterSpacing: Double = 0,
    color: DrawingColor, layer: DrawingLayer
  ) {
    self.string = string
    self.position = position
    self.size = size
    self.rotationDegrees = rotationDegrees
    self.anchor = anchor
    self.font = font
    self.letterSpacing = letterSpacing
    self.color = color
    self.layer = layer
  }

  /// Width from the first glyph's start to the last glyph's end, plan millimetres.
  var width: Double {
    FontMetrics.width(string, size: size, font: font)
      + letterSpacing * Double(max(0, string.unicodeScalars.count - 1))
  }
}

public indirect enum DrawingItem: Hashable, Sendable {
  case shape(DrawingShape)
  case text(DrawingText)
  /// `items` drawn inside the clipping path (nonzero rule).
  case clipped(DrawingPath, [DrawingItem])
}

// MARK: Path building

/// A local frame for building shapes: `origin` plus `u` and `v` (unit, perpendicular) in plan
/// coordinates. Local (x, y) maps to origin + u x + v y.
struct DrawingFrame {
  var origin: Point2
  var u: Point2
  var v: Point2

  func map(_ x: Double, _ y: Double) -> Point2 { origin + u * x + v * y }
  func map(_ p: Point2) -> Point2 { map(p.x, p.y) }
}

/// Paths in plan metres, turned into plan-millimetre `DrawingPath`s by `PathBuilder.path`.
struct PathBuilder {
  /// Points are metres; written as millimetres.
  private(set) var elements: [DrawingPath.Element] = []

  static func mm(_ p: Point2) -> DrawingPoint { DrawingPoint(x: p.x * 1000, y: p.y * 1000) }

  var path: DrawingPath { DrawingPath(elements: elements) }
  var isEmpty: Bool { elements.isEmpty }

  mutating func move(_ p: Point2) { elements.append(.move(PathBuilder.mm(p))) }
  mutating func line(_ p: Point2) { elements.append(.line(PathBuilder.mm(p))) }
  mutating func curve(_ c1: Point2, _ c2: Point2, _ end: Point2) {
    elements.append(.curve(PathBuilder.mm(c1), PathBuilder.mm(c2), PathBuilder.mm(end)))
  }
  mutating func close() { elements.append(.close) }

  mutating func polygon(_ points: [Point2]) {
    guard let first = points.first else { return }
    move(first)
    for p in points.dropFirst() { line(p) }
    close()
  }

  mutating func polyline(_ points: [Point2]) {
    guard let first = points.first else { return }
    move(first)
    for p in points.dropFirst() { line(p) }
  }

  mutating func segment(_ a: Point2, _ b: Point2) {
    move(a)
    line(b)
  }

  /// Elliptical arc of the frame's local circle of radii (rx, ry) about local (cx, cy), from
  /// `start` to `end` degrees, as Beziers of at most 90 degrees. Moves to the start when `move`
  /// is true, otherwise draws a line to it.
  mutating func arc(
    in frame: DrawingFrame, cx: Double, cy: Double, rx: Double, ry: Double, start: Double,
    end: Double, move: Bool
  ) {
    let first = frame.map(cx + rx * cos(start * .pi / 180), cy + ry * sin(start * .pi / 180))
    if move { self.move(first) } else { line(first) }
    // Unit-circle Beziers, mapped by the (affine) local ellipse.
    for s in PDFPage.arcBeziers(
      centerX: 0, centerY: 0, radius: 1, startDegrees: start, endDegrees: end)
    {
      curve(
        frame.map(cx + rx * s.0, cy + ry * s.1), frame.map(cx + rx * s.2, cy + ry * s.3),
        frame.map(cx + rx * s.4, cy + ry * s.5))
    }
  }

  mutating func ellipse(in frame: DrawingFrame, cx: Double, cy: Double, rx: Double, ry: Double) {
    arc(in: frame, cx: cx, cy: cy, rx: rx, ry: ry, start: 0, end: 360, move: true)
    close()
  }

  mutating func circle(center: Point2, radius: Double) {
    ellipse(
      in: DrawingFrame(origin: center, u: Point2(x: 1, y: 0), v: Point2(x: 0, y: 1)), cx: 0,
      cy: 0, rx: radius, ry: radius)
  }

  /// Local rectangle from (x0, y0) to (x1, y1) with corners rounded by `r` (clamped to fit).
  mutating func rect(
    in frame: DrawingFrame, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
    radius r: Double = 0
  ) {
    let (lx, hx) = (min(x0, x1), max(x0, x1))
    let (ly, hy) = (min(y0, y1), max(y0, y1))
    let radius = max(0, min(r, (hx - lx) / 2, (hy - ly) / 2))
    if radius < 1e-6 {
      polygon([frame.map(lx, ly), frame.map(hx, ly), frame.map(hx, hy), frame.map(lx, hy)])
      return
    }
    move(frame.map(lx + radius, ly))
    line(frame.map(hx - radius, ly))
    arc(
      in: frame, cx: hx - radius, cy: ly + radius, rx: radius, ry: radius, start: -90, end: 0,
      move: false)
    line(frame.map(hx, hy - radius))
    arc(
      in: frame, cx: hx - radius, cy: hy - radius, rx: radius, ry: radius, start: 0, end: 90,
      move: false)
    line(frame.map(lx + radius, hy))
    arc(
      in: frame, cx: lx + radius, cy: hy - radius, rx: radius, ry: radius, start: 90, end: 180,
      move: false)
    line(frame.map(lx, ly + radius))
    arc(
      in: frame, cx: lx + radius, cy: ly + radius, rx: radius, ry: radius, start: 180, end: 270,
      move: false)
    close()
  }
}
