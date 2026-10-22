import Foundation

@testable import PlanExport

/// Grey-scale render of drawing primitives for the visual checks (compass §13.3), on Linux as
/// on macOS: the items drawn in colour by PlanExport's `RasterCanvas` (fills with their rule,
/// strokes with width, caps, joins and dashes, text in Inter as the PDFs set it), read back as
/// luminance (Rec. 709), so a render reads as the page prints in grey scale.
struct DrawingRaster {
  /// The area drawn, in the items' millimetres (y up): its top-left corner is pixel (0, 0).
  let minX: Double
  let maxY: Double
  /// Pixels per millimetre.
  let scale: Double
  private(set) var raster: RasterCanvas

  /// The grey levels of the render, one byte per pixel.
  struct Gray {
    let pixels: [UInt8]
  }

  /// A raster of the area from (`minX`, `minY`) to (`maxX`, `maxY`), filled with `background`.
  init(
    minX: Double, minY: Double, maxX: Double, maxY: Double, pixelsPerMM: Double,
    background: DrawingColor = .white
  ) {
    self.minX = minX
    self.maxY = maxY
    scale = pixelsPerMM
    raster = RasterCanvas(
      width: Int(((maxX - minX) * pixelsPerMM).rounded(.up)),
      height: Int(((maxY - minY) * pixelsPerMM).rounded(.up)), background: background)
  }

  var width: Int { raster.width }
  var height: Int { raster.height }
  var canvas: Gray { Gray(pixels: raster.grayPixels) }

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
    let (r, g, b) = raster.rgb(column, row)
    return DrawingRaster.gray(
      DrawingColor(Double(r) / 255, Double(g) / 255, Double(b) / 255))
  }

  mutating func draw(_ items: [DrawingItem]) {
    let (minX, maxY, scale) = (self.minX, self.maxY, self.scale)
    raster.draw(items, scale: scale) { p in
      Point2(x: (p.x - minX) * scale, y: (maxY - p.y) * scale)
    }
  }
}
