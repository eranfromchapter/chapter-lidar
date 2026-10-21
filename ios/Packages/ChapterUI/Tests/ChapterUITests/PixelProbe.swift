#if canImport(UIKit) && os(iOS)
  import ChapterUI
  import UIKit
  import XCTest

  // Shared by ChapterUITests and the app-hosted ChapterUIHostedSnapshotTests (ios/project.yml).

  /// An 8-bit sRGB colour read from a rendered image.
  struct RGB: Equatable, CustomStringConvertible {
    var r: Int
    var g: Int
    var b: Int

    init(_ r: Int, _ g: Int, _ b: Int) {
      self.r = r
      self.g = g
      self.b = b
    }

    init(_ swatch: ChapterTheme.Swatch) {
      let hex = Int(swatch.hex)
      self.init(hex >> 16 & 0xFF, hex >> 8 & 0xFF, hex & 0xFF)
    }

    /// The largest difference in any channel.
    func distance(to other: RGB) -> Int {
      max(abs(r - other.r), abs(g - other.g), abs(b - other.b))
    }

    var description: String { "(\(r), \(g), \(b))" }
  }

  /// The pixels of a rendered image, addressed in points (the image's scale applies).
  struct PixelProbe {
    let width: Int
    let height: Int
    let scale: CGFloat
    private let bytes: [UInt8]

    init?(_ image: UIImage) {
      guard let cgImage = image.cgImage else { return nil }
      let width = cgImage.width
      let height = cgImage.height
      self.width = width
      self.height = height
      scale = image.scale
      var bytes = [UInt8](repeating: 0, count: width * height * 4)
      let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard
          let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
      }
      guard drawn else { return nil }
      self.bytes = bytes
    }

    /// The pixel at (x, y) in pixels from the top left.
    func pixel(x: Int, y: Int) -> RGB {
      let i = (y * width + x) * 4
      return RGB(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    /// The pixel at the centre of `point`.
    func pixel(at point: CGPoint) -> RGB {
      pixel(x: Int(point.x * scale), y: Int(point.y * scale))
    }

    /// Every pixel inside `rect` (points).
    func pixels(in rect: CGRect) -> [RGB] {
      let x0 = max(0, Int(rect.minX * scale))
      let x1 = min(width, Int(rect.maxX * scale))
      let y0 = max(0, Int(rect.minY * scale))
      let y1 = min(height, Int(rect.maxY * scale))
      guard x0 < x1, y0 < y1 else { return [] }
      return (y0..<y1).flatMap { y in (x0..<x1).map { x in pixel(x: x, y: y) } }
    }
  }

  /// The back chevron of a pushed screen drawn by `SnapshotRenderer` (402 × 874 pt, the bar's
  /// 44 pt under the 62 pt safe area): asserts it is drawn, dark and not in the system blue. The
  /// iOS 26 glass pill renders an ink chevron a little warmer, (29, 25, 15), so its darkest
  /// pixel may be up to 40 from ink in a channel; a blue or white chevron is far further.
  @MainActor
  func assertBackChevronIsInk(
    in image: UIImage, file: StaticString = #filePath, line: UInt = #line
  ) {
    guard let probe = PixelProbe(image) else {
      return XCTFail("The image has no pixels", file: file, line: line)
    }
    // The leading 72 pt of the bar: the chevron (and on iOS 26 its 44 pt glass pill).
    let area = CGRect(x: 0, y: 62, width: 72, height: 44)
    let ink = RGB(.ink)
    // The chevron's own pixels: the darkest in the area, well away from the light background.
    let darkest = probe.pixels(in: area).min { $0.r + $0.g + $0.b < $1.r + $1.g + $1.b }
    guard let darkest else { return XCTFail("No pixels in the bar", file: file, line: line) }
    let marks = probe.pixels(in: area).filter { $0.r + $0.g + $0.b < 3 * 160 }
    XCTAssertGreaterThan(
      marks.count, 20, "No back chevron drawn (darkest pixel \(darkest))", file: file, line: line)
    XCTAssertLessThanOrEqual(
      darkest.distance(to: ink), 40, "The chevron's darkest pixel is \(darkest), not ink \(ink)",
      file: file, line: line)
    // System blue #007AFF and its anti-aliased edges have far more blue than red; ink does not.
    let bluest = marks.max { $0.b - $0.r < $1.b - $1.r }
    if let bluest {
      XCTAssertLessThan(
        bluest.b - bluest.r, 40, "The chevron is tinted blue: \(bluest)", file: file, line: line)
    }
  }
#endif
