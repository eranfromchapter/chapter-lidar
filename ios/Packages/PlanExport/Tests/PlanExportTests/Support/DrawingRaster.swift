import Foundation

@testable import PlanExport

/// Grey-scale render of drawing primitives for the visual checks (compass §13.3), on Linux as
/// on macOS: paths filled with their rule and stroked with their width, caps, joins and dashes
/// (each subpath starts the dash pattern again, as in PDF and SVG), text in Inter as the PDFs
/// set it (`GrayCanvas.text`). A colour becomes its luminance (Rec. 709), so a render reads as
/// the page prints in grey scale. Clipping paths and letter spacing are not drawn; nothing the
/// visual checks render uses them.
struct DrawingRaster {
  /// The area drawn, in the items' millimetres (y up): its top-left corner is pixel (0, 0).
  let minX: Double
  let maxY: Double
  /// Pixels per millimetre.
  let scale: Double
  private(set) var canvas: GrayCanvas

  /// A raster of the area from (`minX`, `minY`) to (`maxX`, `maxY`), filled with `background`.
  init(
    minX: Double, minY: Double, maxX: Double, maxY: Double, pixelsPerMM: Double,
    background: DrawingColor = .white
  ) {
    self.minX = minX
    self.maxY = maxY
    scale = pixelsPerMM
    canvas = GrayCanvas(
      width: Int(((maxX - minX) * pixelsPerMM).rounded(.up)),
      height: Int(((maxY - minY) * pixelsPerMM).rounded(.up)))
    let w = Double(canvas.width)
    let h = Double(canvas.height)
    canvas.fillNonzero(
      [[Point2(x: 0, y: 0), Point2(x: w, y: 0), Point2(x: w, y: h), Point2(x: 0, y: h)]],
      gray: DrawingRaster.gray(background))
  }

  var width: Int { canvas.width }
  var height: Int { canvas.height }

  /// Luminance of `color`, 0 black to 1 white.
  static func gray(_ color: DrawingColor) -> Double {
    0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
  }

  /// Pixel coordinates (y down) of a point in millimetres.
  func pixel(_ x: Double, _ y: Double) -> Point2 {
    Point2(x: (x - minX) * scale, y: (maxY - y) * scale)
  }

  /// Grey level, 0 to 1, of the pixel under (`x`, `y`) millimetres.
  func gray(atMM x: Double, _ y: Double) -> Double {
    let p = pixel(x, y)
    let column = min(max(Int(p.x.rounded(.down)), 0), width - 1)
    let row = min(max(Int(p.y.rounded(.down)), 0), height - 1)
    return Double(canvas.pixels[row * width + column]) / 255
  }

  mutating func draw(_ items: [DrawingItem]) {
    for item in items {
      switch item {
      case .shape(let shape):
        let subpaths = flatten(shape.path)
        if let fill = shape.fill {
          let polygons = subpaths.map(\.points).filter { $0.count >= 3 }
          if shape.evenOdd {
            fillEvenOdd(polygons, gray: DrawingRaster.gray(fill))
          } else {
            canvas.fillNonzero(
              polygons.map(DrawingRaster.counterClockwise), gray: DrawingRaster.gray(fill))
          }
        }
        if let stroke = shape.stroke {
          var outlines: [[Point2]] = []
          for subpath in subpaths {
            for piece in dashed(subpath, dash: stroke.dash.map { $0 * scale }) {
              outlines += strokeOutlines(piece, stroke: stroke)
            }
          }
          canvas.fillNonzero(outlines, gray: DrawingRaster.gray(stroke.color))
        }
      case .text(let text):
        let along = Point2(
          x: cos(text.rotationDegrees * .pi / 180), y: -sin(text.rotationDegrees * .pi / 180))
        var origin = pixel(text.position.x, text.position.y)
        if text.anchor == .trailing { origin = origin - along * (text.width * scale) }
        canvas.text(
          text.string, origin: origin, emPixels: text.size * scale, rotation: text.rotationDegrees,
          centered: text.anchor == .center, bold: text.bold, gray: DrawingRaster.gray(text.color))
      case .clipped(_, let children):
        draw(children)
      }
    }
  }

  // MARK: Paths

  private struct Subpath {
    var points: [Point2]
    var closed: Bool
  }

  /// The path's subpaths as polylines in pixels, each curve cut into pieces of about half a
  /// pixel.
  private func flatten(_ path: DrawingPath) -> [Subpath] {
    var out: [Subpath] = []
    var current: Subpath?
    func px(_ p: DrawingPoint) -> Point2 { pixel(p.x, p.y) }
    for element in path.elements {
      switch element {
      case .move(let p):
        if let current, current.points.count > 1 { out.append(current) }
        current = Subpath(points: [px(p)], closed: false)
      case .line(let p):
        current?.points.append(px(p))
      case .curve(let c1, let c2, let end):
        guard let start = current?.points.last else { continue }
        let (a, b, c) = (px(c1), px(c2), px(end))
        let hull = start.distance(to: a) + a.distance(to: b) + b.distance(to: c)
        let count = max(4, Int((hull * 2).rounded(.up)))
        for step in 1...count {
          let t = Double(step) / Double(count)
          let u = 1 - t
          let point =
            start * (u * u * u) + a * (3 * u * u * t) + b * (3 * u * t * t) + c * (t * t * t)
          current?.points.append(point)
        }
      case .close:
        if var closed = current {
          closed.closed = true
          if let first = closed.points.first, let last = closed.points.last,
            first.distance(to: last) < 1e-9
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
  private func dashed(_ subpath: Subpath, dash: [Double]) -> [Subpath] {
    guard !dash.isEmpty, dash.reduce(0, +) > 0 else { return [subpath] }
    var points = subpath.points
    if subpath.closed, let first = points.first { points.append(first) }
    var pieces: [Subpath] = []
    var index = 0
    var left = dash[0]
    var on = true
    var piece: [Point2] = on ? [points[0]] : []
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

  /// Polygons (all counter-clockwise on screen) whose nonzero union is the stroke of `subpath`:
  /// a quadrilateral per segment, the joins and the caps.
  private func strokeOutlines(_ subpath: Subpath, stroke: DrawingStroke) -> [[Point2]] {
    let half = stroke.width * scale / 2
    var points = subpath.points
    if subpath.closed, let first = points.first { points.append(first) }
    var outlines: [[Point2]] = []
    var directions: [Point2] = []
    for index in 0..<(points.count - 1) {
      let a = points[index]
      let b = points[index + 1]
      guard a.distance(to: b) > 1e-12 else { continue }
      let d = (b - a).unit
      let n = d.leftNormal * half
      outlines.append(DrawingRaster.counterClockwise([a + n, b + n, b - n, a - n]))
      directions.append(d)
    }
    // Joins at the inner corners, and where a closed subpath meets its start.
    let corners =
      subpath.closed ? Array(0..<(points.count - 1)) : Array(1..<max(1, points.count - 1))
    for index in corners where directions.count > 1 {
      let corner = points[index]
      let incoming = directions[(index - 1 + directions.count) % directions.count]
      let outgoing = directions[index % directions.count]
      switch stroke.join {
      case .round:
        outlines.append(DrawingRaster.disc(corner, radius: half))
      case .miter, .bevel:
        // The wedge between the two segments' outer edges, out to the miter point when it is
        // within the miter limit (10, the PDF default).
        let turn = incoming.x * outgoing.y - incoming.y * outgoing.x
        guard abs(turn) > 1e-9 else { continue }
        let side: Double = turn > 0 ? -1 : 1
        let p = corner + incoming.leftNormal * (half * side)
        let q = corner + outgoing.leftNormal * (half * side)
        let bisector = (incoming.leftNormal + outgoing.leftNormal).unit * side
        let cosine = max(1e-9, bisector.dot(incoming.leftNormal * side))
        let miter = corner + bisector * (half / cosine)
        let wedge =
          stroke.join == .miter && 1 / cosine <= 10 ? [corner, p, miter, q] : [corner, p, q]
        outlines.append(DrawingRaster.counterClockwise(wedge))
      }
    }
    if !subpath.closed, let first = directions.first, let last = directions.last,
      let start = points.first, let end = points.last
    {
      switch stroke.cap {
      case .butt:
        break
      case .round:
        outlines.append(DrawingRaster.disc(start, radius: half))
        outlines.append(DrawingRaster.disc(end, radius: half))
      case .square:
        for (point, d) in [(start, first * -1), (end, last)] {
          let n = d.leftNormal * half
          outlines.append(
            DrawingRaster.counterClockwise([
              point + n, point + n + d * half, point - n + d * half, point - n,
            ]))
        }
      }
    }
    return outlines
  }

  /// Even-odd fill of `polygons` taken together, sampled at pixel centres.
  private mutating func fillEvenOdd(_ polygons: [[Point2]], gray: Double) {
    for row in 0..<height {
      let y = Double(row) + 0.5
      var crossings: [Double] = []
      for polygon in polygons {
        for index in polygon.indices {
          let a = polygon[index]
          let b = polygon[(index + 1) % polygon.count]
          if (a.y > y) != (b.y > y) {
            crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
          }
        }
      }
      crossings.sort()
      var index = 0
      while index + 1 < crossings.count {
        let start = max(0, Double(crossings[index]))
        let end = min(Double(width), Double(crossings[index + 1]))
        if end > start {
          canvas.fillNonzero(
            [
              [
                Point2(x: start, y: Double(row)), Point2(x: end, y: Double(row)),
                Point2(x: end, y: Double(row + 1)), Point2(x: start, y: Double(row + 1)),
              ]
            ],
            gray: gray)
        }
        index += 2
      }
    }
  }

  /// A 48-sided disc.
  private static func disc(_ center: Point2, radius: Double) -> [Point2] {
    (0..<48).map { step in
      let angle = Double(step) / 48 * 2 * .pi
      return center + Point2(x: cos(angle), y: -sin(angle)) * radius
    }
  }

  /// `polygon` in one winding direction (counter-clockwise on screen, y down), so overlapping
  /// pieces add up under the nonzero rule instead of cancelling.
  private static func counterClockwise(_ polygon: [Point2]) -> [Point2] {
    var area = 0.0
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      area += a.x * b.y - b.x * a.y
    }
    return area > 0 ? polygon.reversed() : polygon
  }
}
