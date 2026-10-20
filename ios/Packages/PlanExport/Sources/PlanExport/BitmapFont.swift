import Foundation

/// 5 x 7 pixel capital letters, digits and common punctuation, used to label the PNG preview.
/// Lowercase letters draw as capitals; characters without a glyph draw as `?`.
enum BitmapFont {
  static let columns = 5
  static let rows = 7

  /// Seven rows, top to bottom, five bits each (bit 4 is the leftmost pixel).
  static func glyph(for scalar: Unicode.Scalar) -> [UInt8]? {
    var character = Character(scalar)
    if scalar.value == 0xB2 { character = "2" }
    let upper = Character(String(character).uppercased())
    if upper == " " { return nil }
    return glyphs[upper] ?? glyphs["?"]
  }

  private static let glyphs: [Character: [UInt8]] = [
    "A": [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
    "B": [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
    "C": [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110],
    "D": [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110],
    "E": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
    "F": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000],
    "G": [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111],
    "H": [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
    "I": [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
    "J": [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100],
    "K": [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001],
    "L": [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
    "M": [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001],
    "N": [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001],
    "O": [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
    "P": [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
    "Q": [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101],
    "R": [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
    "S": [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
    "T": [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
    "U": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
    "V": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100],
    "W": [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010],
    "X": [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001],
    "Y": [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100],
    "Z": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111],
    "0": [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
    "1": [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
    "2": [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111],
    "3": [0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110],
    "4": [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
    "5": [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110],
    "6": [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110],
    "7": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
    "8": [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
    "9": [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100],
    ".": [0, 0, 0, 0, 0, 0b00110, 0b00110],
    ",": [0, 0, 0, 0, 0b00110, 0b00100, 0b01000],
    "-": [0, 0, 0, 0b11111, 0, 0, 0],
    "+": [0, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0],
    "/": [0b00001, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b10000],
    ":": [0, 0b00110, 0b00110, 0, 0b00110, 0b00110, 0],
    "'": [0b00100, 0b00100, 0b01000, 0, 0, 0, 0],
    "\"": [0b01010, 0b01010, 0, 0, 0, 0, 0],
    "(": [0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010],
    ")": [0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000],
    "_": [0, 0, 0, 0, 0, 0, 0b11111],
    "?": [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0, 0b00100],
  ]
}

/// 8-bit grayscale raster with anti-aliased strokes, polygon fills and bitmap-font text.
struct GrayCanvas {
  let width: Int
  let height: Int
  private(set) var pixels: [UInt8]

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
    guard [a.x, a.y, b.x, b.y, lineWidth].allSatisfy(\.isFinite) else { return }
    let radius = max(lineWidth, 1.4) / 2
    let minX = Int((min(a.x, b.x) - radius - 1).rounded(.down))
    let maxX = Int((max(a.x, b.x) + radius + 1).rounded(.up))
    let minY = Int((min(a.y, b.y) - radius - 1).rounded(.down))
    let maxY = Int((max(a.y, b.y) + radius + 1).rounded(.up))
    // Clipped to the canvas; nothing to draw when the line lies wholly off it.
    let x0 = max(0, minX)
    let x1 = min(width - 1, maxX)
    let y0 = max(0, minY)
    let y1 = min(height - 1, maxY)
    guard x0 <= x1, y0 <= y1 else { return }
    let ab = b - a
    let lengthSquared = ab.dot(ab)
    for y in y0...y1 {
      for x in x0...x1 {
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

  /// Draws text with the 5 x 7 bitmap font. `origin` is the baseline start in pixels (y down),
  /// `emPixels` the font size, `rotation` degrees counter-clockwise on screen.
  mutating func text(
    _ value: String, origin: Point2, emPixels: Double, rotation: Double, centered: Bool,
    bold: Bool, gray: Double
  ) {
    let scalars = Array(Format.composed(Format.singleLine(value)).unicodeScalars)
    guard !scalars.isEmpty else { return }
    let cell = emPixels * 0.72 / Double(BitmapFont.rows)  // pixels per font pixel
    let advance = Double(BitmapFont.columns + 1) * cell
    let textWidth = Double(scalars.count) * advance - cell
    let radians = rotation * .pi / 180
    // Directions in screen coordinates (y down): along the text and up the glyphs.
    let along = Point2(x: cos(radians), y: -sin(radians))
    let up = Point2(x: -sin(radians), y: -cos(radians))
    let start = centered ? origin - along * (textWidth / 2) : origin
    let glyphHeight = Double(BitmapFont.rows) * cell
    // Bounding box of the text rectangle.
    var minX = Double.infinity, minY = Double.infinity
    var maxX = -Double.infinity, maxY = -Double.infinity
    for (u, v) in [(0.0, 0.0), (textWidth, 0.0), (0.0, glyphHeight), (textWidth, glyphHeight)] {
      let p = start + along * u + up * v
      minX = min(minX, p.x)
      maxX = max(maxX, p.x)
      minY = min(minY, p.y)
      maxY = max(maxY, p.y)
    }
    // Clipped to the canvas; nothing to draw when the text lies wholly off it.
    guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return }
    let x0 = max(0, Int(minX.rounded(.down)) - 1)
    let x1 = min(width - 1, Int(maxX.rounded(.up)) + 1)
    let y0 = max(0, Int(minY.rounded(.down)) - 1)
    let y1 = min(height - 1, Int(maxY.rounded(.up)) + 1)
    guard x0 <= x1, y0 <= y1 else { return }
    let glyphs = scalars.map { BitmapFont.glyph(for: $0) }
    let samples = 2
    let weight = bold ? 0.35 * cell : 0
    for y in y0...y1 {
      for x in x0...x1 {
        var lit = 0
        for sy in 0..<samples {
          for sx in 0..<samples {
            let p = Point2(
              x: Double(x) + (Double(sx) + 0.5) / Double(samples),
              y: Double(y) + (Double(sy) + 0.5) / Double(samples))
            let offset = p - start
            let u = offset.dot(along)
            let v = offset.dot(up)
            // Bold widens each lit font pixel a little horizontally.
            guard v >= 0, v < glyphHeight, u >= -weight, u < textWidth + weight else { continue }
            let row = BitmapFont.rows - 1 - Int(v / cell)
            let slot = Int(((u + 0) / advance).rounded(.down))
            for candidate in [slot, slot - 1] where candidate >= 0 && candidate < glyphs.count {
              guard let glyph = glyphs[candidate] else { continue }
              let local = u - Double(candidate) * advance
              let column = Int(((local + weight) / cell).rounded(.down))
              let inner = Int((local / cell).rounded(.down))
              var on = false
              for c in Set([column, inner]) where c >= 0 && c < BitmapFont.columns {
                if glyph[row] & (1 << UInt8(BitmapFont.columns - 1 - c)) != 0 {
                  on = true
                }
              }
              if on {
                lit += 1
                break
              }
            }
          }
        }
        if lit > 0 {
          blend(x, y, gray: gray, coverage: Double(lit) / Double(samples * samples))
        }
      }
    }
  }
}
