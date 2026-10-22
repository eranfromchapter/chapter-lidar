import Foundation

/// 8-bit RGB raster of drawing primitives, pure Swift, the same on Linux and iOS: anti-aliased
/// nonzero and even-odd fills (each pixel's coverage is the mean covered length of `subrows`
/// sample lines), Bezier curves flattened to within `flatness` pixels, strokes with their width,
/// caps, joins and dashes (each subpath starts the dash pattern again, as in PDF and SVG),
/// clipping to a path, and text drawn from the outlines of the Inter fonts the PDFs embed, with
/// letter spacing, advanced by the PDF widths. Text in Times or Courier, which have no outlines
/// here, is drawn in Inter Regular at the font's own advance; plan.png draws none.
struct RasterCanvas {
  let width: Int
  let height: Int
  /// Row-major R, G, B bytes.
  private(set) var pixels: [UInt8]
  /// Coverage (0–1) of the clipping path, per pixel; nil when nothing is clipped.
  private var clipMask: [Float]?

  /// Sample lines per pixel row for anti-aliased fills.
  static let subrows = 5
  /// Largest distance between a curve and the lines that stand for it, pixels.
  static let flatness = 0.25

  init(width: Int, height: Int, background: DrawingColor = .white) {
    self.width = width
    self.height = height
    let rgb = RasterCanvas.bytes(background)
    pixels = [UInt8](repeating: 0, count: width * height * 3)
    for index in 0..<(width * height) {
      pixels[index * 3] = rgb.0
      pixels[index * 3 + 1] = rgb.1
      pixels[index * 3 + 2] = rgb.2
    }
  }

  static func bytes(_ color: DrawingColor) -> (UInt8, UInt8, UInt8) {
    func byte(_ v: Double) -> UInt8 { UInt8((max(0, min(1, v)) * 255).rounded()) }
    return (byte(color.red), byte(color.green), byte(color.blue))
  }

  /// R, G, B of the pixel at column `x`, row `y` (from the top).
  func rgb(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
    let index = (y * width + x) * 3
    return (pixels[index], pixels[index + 1], pixels[index + 2])
  }

  /// Luminance (Rec. 709) of each pixel, one byte per pixel: how the raster prints in grey.
  var grayPixels: [UInt8] {
    var out = [UInt8](repeating: 0, count: width * height)
    for index in 0..<(width * height) {
      let r = Double(pixels[index * 3])
      let g = Double(pixels[index * 3 + 1])
      let b = Double(pixels[index * 3 + 2])
      out[index] = UInt8(max(0, min(255, (0.2126 * r + 0.7152 * g + 0.0722 * b).rounded())))
    }
    return out
  }

  /// Paints `color` over pixel (x, y) of `buffer` with `alpha` coverage.
  private static func blend(
    _ buffer: inout [UInt8], index: Int, color: (Double, Double, Double), alpha: Double
  ) {
    guard alpha > 0 else { return }
    let at = index * 3
    for (channel, value) in [color.0, color.1, color.2].enumerated() {
      let current = Double(buffer[at + channel])
      buffer[at + channel] = UInt8(
        max(0, min(255, (current * (1 - alpha) + value * 255 * alpha).rounded())))
    }
  }

  // MARK: Fills

  /// Anti-aliased fill of closed polygons (pixel coordinates, y down) taken together, nonzero
  /// (overlapping contours of one direction paint once) or even-odd.
  mutating func fill(_ polygons: [[Point2]], color: DrawingColor, evenOdd: Bool = false) {
    let rgb = (color.red, color.green, color.blue)
    // The pixels move out of `self` while the scan paints them (no copy).
    var buffer = pixels
    pixels = []
    let mask = clipMask
    let columns = width
    RasterCanvas.coverage(of: polygons, evenOdd: evenOdd, width: width, height: height) {
      x, y, value in
      let index = y * columns + x
      let alpha = min(1, value) * Double(mask?[index] ?? 1)
      RasterCanvas.blend(&buffer, index: index, color: rgb, alpha: alpha)
    }
    pixels = buffer
  }

  /// Calls `body` with every pixel the polygons cover and its coverage.
  static func coverage(
    of polygons: [[Point2]], evenOdd: Bool, width: Int, height: Int,
    _ body: (Int, Int, Double) -> Void
  ) {
    struct Edge {
      var top: Point2
      var bottom: Point2
      var winding: Int
    }
    var edges: [Edge] = []
    var minX = Double.infinity
    var maxX = -Double.infinity
    for polygon in polygons where polygon.count >= 3 {
      for index in polygon.indices {
        let a = polygon[index]
        let b = polygon[(index + 1) % polygon.count]
        guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { continue }
        minX = min(minX, a.x)
        maxX = max(maxX, a.x)
        if a.y < b.y {
          edges.append(Edge(top: a, bottom: b, winding: 1))
        } else if a.y > b.y {
          edges.append(Edge(top: b, bottom: a, winding: -1))
        }
      }
    }
    guard !edges.isEmpty, minX.isFinite, maxX.isFinite else { return }
    edges.sort { $0.top.y < $1.top.y }
    let left = max(0, Int(minX.rounded(.down)))
    let right = min(width - 1, Int(maxX.rounded(.down)))
    let first = max(0, Int(edges[0].top.y.rounded(.down)))
    let last = min(height - 1, Int((edges.map(\.bottom.y).max() ?? 0).rounded(.down)))
    guard left <= right, first <= last else { return }
    let share = 1 / Double(RasterCanvas.subrows)
    var cover = [Double](repeating: 0, count: right - left + 2)
    var active: [Edge] = []
    var next = 0
    var crossings: [(x: Double, winding: Int)] = []
    for row in first...last {
      let rowTop = Double(row)
      while next < edges.count, edges[next].top.y < rowTop + 1 {
        active.append(edges[next])
        next += 1
      }
      active.removeAll { $0.bottom.y <= rowTop }
      guard !active.isEmpty else { continue }
      for index in cover.indices { cover[index] = 0 }
      for line in 0..<RasterCanvas.subrows {
        let y = rowTop + (Double(line) + 0.5) * share
        crossings.removeAll(keepingCapacity: true)
        for edge in active where edge.top.y <= y && y < edge.bottom.y {
          let t = (y - edge.top.y) / (edge.bottom.y - edge.top.y)
          crossings.append((edge.top.x + (edge.bottom.x - edge.top.x) * t, edge.winding))
        }
        crossings.sort { $0.x < $1.x }
        var winding = 0
        var spanStart = 0.0
        for crossing in crossings {
          let before = winding
          winding += evenOdd ? (winding == 0 ? 1 : -1) : crossing.winding
          if before == 0, winding != 0 {
            spanStart = crossing.x
          } else if before != 0, winding == 0 {
            let a = max(Double(left), spanStart)
            let b = min(Double(right + 1), crossing.x)
            guard b > a else { continue }
            let firstPixel = Int(a.rounded(.down))
            let lastPixel = min(right, Int(b.rounded(.down)))
            if firstPixel >= lastPixel {
              cover[firstPixel - left] += (b - a) * share
            } else {
              cover[firstPixel - left] += (Double(firstPixel + 1) - a) * share
              for pixel in (firstPixel + 1)..<lastPixel { cover[pixel - left] += share }
              cover[lastPixel - left] += (b - Double(lastPixel)) * share
            }
          }
        }
      }
      for x in left...right where cover[x - left] > 0 {
        body(x, row, min(1, cover[x - left]))
      }
    }
  }

  // MARK: Drawing primitives

  /// Draws `items` (plan millimetres, y up) with `transform` taking a point to pixels (y down)
  /// and `scale` pixels per millimetre for widths, dashes and text sizes.
  mutating func draw(
    _ items: [DrawingItem], scale: Double, transform: (DrawingPoint) -> Point2
  ) {
    for item in items {
      switch item {
      case .shape(let shape):
        let subpaths = flatten(shape.path, transform: transform)
        if let fill = shape.fill {
          let polygons = subpaths.map(\.points).filter { $0.count >= 3 }
          self.fill(
            shape.evenOdd ? polygons : polygons.map(RasterCanvas.counterClockwise), color: fill,
            evenOdd: shape.evenOdd)
        }
        if let stroke = shape.stroke {
          var outlines: [[Point2]] = []
          for subpath in subpaths {
            for piece in dashed(subpath, dash: stroke.dash.map { $0 * scale }) {
              outlines += strokeOutlines(piece, stroke: stroke, scale: scale)
            }
          }
          fill(outlines, color: stroke.color)
        }
      case .text(let text):
        let radians = text.rotationDegrees * .pi / 180
        let along = Point2(x: cos(radians), y: -sin(radians))
        var origin = transform(text.position)
        let width = text.width * scale
        switch text.anchor {
        case .leading: break
        case .center: origin = origin - along * (width / 2)
        case .trailing: origin = origin - along * width
        }
        self.text(
          text.string, origin: origin, emPixels: text.size * scale,
          rotation: text.rotationDegrees, font: text.font,
          letterSpacing: text.letterSpacing * scale, color: text.color)
      case .clipped(let clip, let children):
        let saved = clipMask
        var mask = [Float](repeating: 0, count: width * height)
        let polygons = flatten(clip, transform: transform).map(\.points).filter { $0.count >= 3 }
        let columns = width
        RasterCanvas.coverage(
          of: polygons.map(RasterCanvas.counterClockwise), evenOdd: false, width: width,
          height: height
        ) { x, y, value in
          mask[y * columns + x] = Float(value)
        }
        if let saved {
          for index in mask.indices { mask[index] *= saved[index] }
        }
        clipMask = mask
        draw(children, scale: scale, transform: transform)
        clipMask = saved
      }
    }
  }

  /// Draws `value` from the Inter outlines (SemiBold for `.interSemiBold`), as the PDFs set it:
  /// each glyph advanced by its PDF width (`FontMetrics`) plus `letterSpacing` pixels,
  /// characters WinAnsi lacks drawn as `?`. `origin` is the baseline start in pixels (y down),
  /// `emPixels` the font size, `rotation` degrees counter-clockwise on screen.
  mutating func text(
    _ value: String, origin: Point2, emPixels: Double, rotation: Double, font: DrawingFont,
    letterSpacing: Double = 0, color: DrawingColor
  ) {
    let clean = Format.composed(Format.singleLine(value))
    guard !clean.isEmpty, emPixels > 0, origin.x.isFinite, origin.y.isFinite else { return }
    let bold = font == .interSemiBold
    let outlines = bold ? GlyphOutlines.interSemiBold : GlyphOutlines.interRegular
    let radians = rotation * .pi / 180
    let along = Point2(x: cos(radians), y: -sin(radians))
    let up = Point2(x: -sin(radians), y: -cos(radians))
    var pen = origin
    let scale = emPixels / outlines.unitsPerEm
    var polygons: [[Point2]] = []
    let question = Int(UInt8(ascii: "?"))
    for scalar in clean.unicodeScalars {
      let code = Int(PDFPage.winAnsi(scalar))
      let glyph = outlines.glyph(for: code == question ? "?" : scalar)
      let start = pen
      polygons += outlines.polygons(glyph: glyph, tolerance: 0.05 / scale) { x, y in
        start + along * (x * scale) + up * (y * scale)
      }
      let advance = FontMetrics.width(String(scalar), size: emPixels, font: font)
      pen = pen + along * (advance + letterSpacing)
    }
    fill(polygons, color: color)
  }

  // MARK: Paths

  struct Subpath {
    var points: [Point2]
    var closed: Bool
  }

  /// The path's subpaths as polylines in pixels, each curve cut into pieces within `flatness`.
  func flatten(_ path: DrawingPath, transform: (DrawingPoint) -> Point2) -> [Subpath] {
    var out: [Subpath] = []
    var current: Subpath?
    for element in path.elements {
      switch element {
      case .move(let p):
        if let current, current.points.count > 1 { out.append(current) }
        current = Subpath(points: [transform(p)], closed: false)
      case .line(let p):
        current?.points.append(transform(p))
      case .curve(let c1, let c2, let end):
        guard let start = current?.points.last else { continue }
        let (a, b, c) = (transform(c1), transform(c2), transform(end))
        // Segments so the flattening error stays under `flatness` (Wang's bound).
        let ddx = max(abs(start.x - 2 * a.x + b.x), abs(a.x - 2 * b.x + c.x))
        let ddy = max(abs(start.y - 2 * a.y + b.y), abs(a.y - 2 * b.y + c.y))
        let dd = (ddx * ddx + ddy * ddy).squareRoot()
        let segments = (3 * dd / (4 * RasterCanvas.flatness)).squareRoot().rounded(.up)
        let count = max(2, min(512, Int(segments)))
        for step in 1...count {
          let t = Double(step) / Double(count)
          let u = 1 - t
          current?.points.append(
            start * (u * u * u) + a * (3 * u * u * t) + b * (3 * u * t * t) + c * (t * t * t))
        }
      case .close:
        if var closed = current {
          closed.closed = true
          if let first = closed.points.first, let last = closed.points.last,
            first.distance(to: last) < 1e-9, closed.points.count > 1
          {
            closed.points.removeLast()
          }
          if closed.points.count > 1 { out.append(closed) }
          current = Subpath(points: [closed.points.first ?? Point2(x: 0, y: 0)], closed: false)
        }
      }
    }
    if let current, current.points.count > 1 { out.append(current) }
    return out
  }

  /// The "on" pieces of `subpath` for a dash pattern in pixels, from the subpath's start; the
  /// whole subpath when the pattern is empty.
  func dashed(_ subpath: Subpath, dash: [Double]) -> [Subpath] {
    guard !dash.isEmpty, dash.reduce(0, +) > 0 else { return [subpath] }
    var points = subpath.points
    if subpath.closed, let first = points.first { points.append(first) }
    var pieces: [Subpath] = []
    var index = 0
    var left = dash[0]
    var on = true
    var piece: [Point2] = [points[0]]
    for segment in 0..<(points.count - 1) {
      var a = points[segment]
      let b = points[segment + 1]
      var length = a.distance(to: b)
      while length > left {
        let cut = a + (b - a).unit * left
        if on {
          piece.append(cut)
          pieces.append(Subpath(points: piece, closed: false))
          piece = []
        } else {
          piece = [cut]
        }
        on.toggle()
        length -= left
        a = cut
        index = (index + 1) % dash.count
        left = dash[index]
      }
      left -= length
      if on { piece.append(b) }
    }
    if on, piece.count > 1 { pieces.append(Subpath(points: piece, closed: false)) }
    return pieces
  }

  /// Polygons (all counter-clockwise on screen) whose nonzero union is the stroke of
  /// `subpath`: a quadrilateral per segment, the joins and the caps.
  func strokeOutlines(_ subpath: Subpath, stroke: DrawingStroke, scale: Double) -> [[Point2]] {
    let half = stroke.width * scale / 2
    var points = subpath.points
    if subpath.closed, let first = points.first { points.append(first) }
    var outlines: [[Point2]] = []
    var directions: [Point2] = []
    var starts: [Int] = []
    for index in 0..<(points.count - 1) {
      let a = points[index]
      let b = points[index + 1]
      guard a.distance(to: b) > 1e-12 else { continue }
      let d = (b - a).unit
      let n = d.leftNormal * half
      outlines.append(RasterCanvas.counterClockwise([a + n, b + n, b - n, a - n]))
      directions.append(d)
      starts.append(index)
    }
    guard !directions.isEmpty else { return outlines }
    // Joins between consecutive segments, and where a closed subpath meets its start.
    var joins: [(corner: Point2, incoming: Point2, outgoing: Point2)] = []
    for index in 1..<directions.count {
      joins.append((points[starts[index]], directions[index - 1], directions[index]))
    }
    if subpath.closed, directions.count > 1 {
      joins.append((points[0], directions[directions.count - 1], directions[0]))
    }
    for join in joins {
      switch stroke.join {
      case .round:
        outlines.append(RasterCanvas.disc(join.corner, radius: half))
      case .miter, .bevel:
        let turn = join.incoming.x * join.outgoing.y - join.incoming.y * join.outgoing.x
        guard abs(turn) > 1e-9 else { continue }
        let side: Double = turn > 0 ? -1 : 1
        let p = join.corner + join.incoming.leftNormal * (half * side)
        let q = join.corner + join.outgoing.leftNormal * (half * side)
        let bisector = (join.incoming.leftNormal + join.outgoing.leftNormal).unit * side
        let cosine = max(1e-9, bisector.dot(join.incoming.leftNormal * side))
        let miter = join.corner + bisector * (half / cosine)
        let wedge =
          stroke.join == .miter && 1 / cosine <= 10
          ? [join.corner, p, miter, q] : [join.corner, p, q]
        outlines.append(RasterCanvas.counterClockwise(wedge))
      }
    }
    if !subpath.closed, let first = directions.first, let last = directions.last,
      let start = points.first, let end = points.last
    {
      switch stroke.cap {
      case .butt:
        break
      case .round:
        outlines.append(RasterCanvas.disc(start, radius: half))
        outlines.append(RasterCanvas.disc(end, radius: half))
      case .square:
        for (point, d) in [(start, first * -1), (end, last)] {
          let n = d.leftNormal * half
          outlines.append(
            RasterCanvas.counterClockwise([
              point + n, point + n + d * half, point - n + d * half, point - n,
            ]))
        }
      }
    }
    return outlines
  }

  /// A 48-sided disc.
  static func disc(_ center: Point2, radius: Double) -> [Point2] {
    (0..<48).map { step in
      let angle = Double(step) / 48 * 2 * .pi
      return center + Point2(x: cos(angle), y: -sin(angle)) * radius
    }
  }

  /// `polygon` in one winding direction (counter-clockwise on screen, y down), so overlapping
  /// pieces add up under the nonzero rule instead of cancelling.
  static func counterClockwise(_ polygon: [Point2]) -> [Point2] {
    var area = 0.0
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      area += a.x * b.y - b.x * a.y
    }
    return area > 0 ? polygon.reversed() : polygon
  }
}
