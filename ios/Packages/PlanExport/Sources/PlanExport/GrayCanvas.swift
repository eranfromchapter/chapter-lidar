import Foundation

/// 8-bit grayscale raster with anti-aliased strokes, polygon fills and text in Inter, the
/// Chapter sans.
struct GrayCanvas {
  let width: Int
  let height: Int
  private(set) var pixels: [UInt8]

  /// Sample lines per pixel row for anti-aliased fills; coverage along each line is exact.
  static let subrows = 5

  init(width: Int, height: Int) {
    self.width = width
    self.height = height
    pixels = [UInt8](repeating: 255, count: width * height)
  }

  private mutating func blend(_ x: Int, _ y: Int, gray: Double, coverage: Double) {
    guard x >= 0, x < width, y >= 0, y < height, coverage > 0 else { return }
    let index = y * width + x
    let current = Double(pixels[index])
    pixels[index] = UInt8(max(0, min(255, (current * (1 - coverage) + gray * 255 * coverage).rounded())))
  }

  /// Round-capped line from `a` to `b`, pixel coordinates with y down.
  mutating func stroke(from a: Point2, to b: Point2, width lineWidth: Double, gray: Double) {
    let radius = max(lineWidth, 1.4) / 2
    let minX = Int((min(a.x, b.x) - radius - 1).rounded(.down))
    let maxX = Int((max(a.x, b.x) + radius + 1).rounded(.up))
    let minY = Int((min(a.y, b.y) - radius - 1).rounded(.down))
    let maxY = Int((max(a.y, b.y) + radius + 1).rounded(.up))
    let ab = b - a
    let lengthSquared = ab.dot(ab)
    for y in max(0, minY)...min(height - 1, max(0, maxY)) {
      for x in max(0, minX)...min(width - 1, max(0, maxX)) {
        let p = Point2(x: Double(x) + 0.5, y: Double(y) + 0.5)
        let t = lengthSquared > 0 ? max(0, min(1, (p - a).dot(ab) / lengthSquared)) : 0
        let distance = p.distance(to: a + ab * t)
        blend(x, y, gray: gray, coverage: min(1, max(0, radius + 0.5 - distance)))
      }
    }
  }

  /// Even-odd polygon fill sampled at pixel centres.
  mutating func fill(_ polygon: [Point2], gray: Double) {
    guard polygon.count >= 3 else { return }
    let minY = max(0, Int((polygon.map(\.y).min() ?? 0).rounded(.down)))
    let maxY = min(height - 1, Int((polygon.map(\.y).max() ?? 0).rounded(.up)))
    guard minY <= maxY else { return }
    for y in minY...maxY {
      let sample = Double(y) + 0.5
      var crossings: [Double] = []
      for index in polygon.indices {
        let a = polygon[index]
        let b = polygon[(index + 1) % polygon.count]
        if (a.y > sample) != (b.y > sample) {
          crossings.append(a.x + (sample - a.y) / (b.y - a.y) * (b.x - a.x))
        }
      }
      crossings.sort()
      var index = 0
      while index + 1 < crossings.count {
        let start = max(0, Int((crossings[index] - 0.5).rounded(.up)))
        let end = min(width - 1, Int((crossings[index + 1] - 0.5).rounded(.down)))
        if start <= end {
          for x in start...end { blend(x, y, gray: gray, coverage: 1) }
        }
        index += 2
      }
    }
  }

  /// Anti-aliased nonzero fill of closed polygons (pixel coordinates, y down) as one shape, so
  /// overlapping contours, as in glyphs, are painted once. Each pixel's coverage is the mean
  /// covered length of its `subrows` sample lines.
  mutating func fillNonzero(_ polygons: [[Point2]], gray: Double) {
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
    let share = 1 / Double(GrayCanvas.subrows)
    var coverage = [Double](repeating: 0, count: right - left + 2)
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
      for index in coverage.indices { coverage[index] = 0 }
      for line in 0..<GrayCanvas.subrows {
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
          winding += crossing.winding
          if before == 0, winding != 0 {
            spanStart = crossing.x
          } else if before != 0, winding == 0 {
            // Add the covered part of each pixel from spanStart to crossing.x.
            let a = max(Double(left), spanStart)
            let b = min(Double(right + 1), crossing.x)
            guard b > a else { continue }
            let firstPixel = Int(a.rounded(.down))
            let lastPixel = Int(b.rounded(.down))
            if firstPixel == lastPixel {
              coverage[firstPixel - left] += (b - a) * share
            } else {
              coverage[firstPixel - left] += (Double(firstPixel + 1) - a) * share
              for pixel in (firstPixel + 1)..<lastPixel { coverage[pixel - left] += share }
              coverage[lastPixel - left] += (b - Double(lastPixel)) * share
            }
          }
        }
      }
      for x in left...right where coverage[x - left] > 0 {
        blend(x, row, gray: gray, coverage: min(1, coverage[x - left]))
      }
    }
  }

  /// Draws `value` in Inter (SemiBold when `bold`) as the PDFs set it: each glyph advanced by
  /// its PDF width (`FontMetrics`), characters WinAnsi lacks drawn as `?`. `origin` is the
  /// baseline start (or, when `centered`, the baseline centre) in pixels (y down), `emPixels`
  /// the font size, `rotation` degrees counter-clockwise on screen.
  mutating func text(
    _ value: String, origin: Point2, emPixels: Double, rotation: Double, centered: Bool,
    bold: Bool, gray: Double
  ) {
    let clean = Format.singleLine(value)
    guard !clean.isEmpty, emPixels > 0 else { return }
    let font = bold ? GlyphOutlines.interSemiBold : GlyphOutlines.interRegular
    let widths =
      bold ? ChapterBrandAssets.interSemiBold.widths : ChapterBrandAssets.interRegular.widths
    let radians = rotation * .pi / 180
    // Directions in screen coordinates (y down): along the text and up the glyphs.
    let along = Point2(x: cos(radians), y: -sin(radians))
    let up = Point2(x: -sin(radians), y: -cos(radians))
    let textWidth = FontMetrics.width(clean, size: emPixels, bold: bold)
    var pen = centered ? origin - along * (textWidth / 2) : origin
    let scale = emPixels / font.unitsPerEm
    var polygons: [[Point2]] = []
    for scalar in clean.unicodeScalars {
      let code = Int(PDFPage.winAnsi(scalar))
      let question = Int(UInt8(ascii: "?"))
      let glyph = font.glyph(for: code == question ? "?" : scalar)
      let start = pen
      // Curves within a twentieth of a pixel.
      polygons += font.polygons(glyph: glyph, tolerance: 0.05 / scale) { x, y in
        start + along * (x * scale) + up * (y * scale)
      }
      pen = pen + along * (Double(widths[(code >= 32 ? code : question) - 32]) * emPixels / 1000)
    }
    fillNonzero(polygons, gray: gray)
  }
}
