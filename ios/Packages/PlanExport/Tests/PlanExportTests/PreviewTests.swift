import CaptureContract
import Foundation
import XCTest

#if canImport(FoundationXML)
  import FoundationXML
#endif

@testable import PlanExport

final class PreviewTests: XCTestCase {
  private final class WellFormedChecker: NSObject, XMLParserDelegate {
    var elements: [String] = []
    var texts: [String] = []
    var currentText = ""
    var attributes: [[String: String]] = []
    var inText = false

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
      elements.append(elementName)
      attributes.append(attributeDict)
      if elementName == "text" {
        inText = true
        currentText = ""
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      if inText { currentText += string }
    }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      if elementName == "text" {
        texts.append(currentText)
        inText = false
      }
    }
  }

  private func parseXML(_ data: Data) -> (ok: Bool, checker: WellFormedChecker) {
    let parser = XMLParser(data: data)
    let checker = WellFormedChecker()
    parser.delegate = checker
    return (parser.parse(), checker)
  }

  func testSVGIsWellFormedXMLWithLabelsAndTrueScaleWalls() throws {
    for capture in try Fixtures.all() {
      let file = try SVGWriter.write(model: capture.model)
      try Repo.write(file, folder: capture.outputFolder)
      let (ok, checker) = parseXML(file.data)
      XCTAssertTrue(ok, "\(capture.fixture) \(capture.truth.areaKey) is not well-formed")
      XCTAssertEqual(checker.elements.first, "svg")
      for room in capture.truth.rooms {
        XCTAssertTrue(checker.texts.contains(room.label), room.label)
      }
      XCTAssertEqual(file.fileName, "plan.svg")
      XCTAssertEqual(file.role, .planSVG)
      XCTAssertEqual(file.mime, "image/svg+xml")
    }
  }

  func testSVGIsDrawnInPaperMillimetresAtPlanScale() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let text = String(decoding: try SVGWriter.write(model: capture.model).data, as: UTF8.self)
    // 4 x 3 m at 1:50 is 80 x 60 mm plus a 16 mm margin on every side.
    XCTAssertTrue(text.contains("width=\"112.000mm\" height=\"92.000mm\" viewBox=\"0 0 112.000 92.000\""))
    // The 4 m wall: a polyline 80 mm long.
    var found = false
    for line in text.split(separator: "\n") where line.contains("stroke-width=\"0.500\"") {
      guard let start = line.range(of: "points=\"")?.upperBound,
        let end = line[start...].firstIndex(of: "\"")
      else { continue }
      let values = line[start..<end].split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
      if values.count == 4, abs(hypot(values[2] - values[0], values[3] - values[1]) - 80) < 0.01 {
        found = true
      }
    }
    XCTAssertTrue(found, "no 80 mm wall polyline")
    XCTAssertTrue(text.contains("<g class=\"A-WALL\">"))
    XCTAssertTrue(text.contains("Reported areas are not verified construction quantities."))
  }

  func testSVGEscapesMarkupAndStripsControlCharacters() throws {
    var model = Synthetic.room(width: 4, length: 3, label: "A & B <\"C\"> 'D'\u{1}x")
    model.label = "Floor <1>"
    let file = try SVGWriter.write(model: model)
    let (ok, checker) = parseXML(file.data)
    XCTAssertTrue(ok)
    XCTAssertTrue(checker.texts.contains("A & B <\"C\"> 'D' x"))
    XCTAssertEqual(SVGWriter.escape("\u{FFFE}a"), " a")
  }

  func testPNGDecodesAndIsThreeHundredDPI() throws {
    for capture in try Fixtures.all() {
      let file = try PNGWriter.write(model: capture.model)
      try Repo.write(file, folder: capture.outputFolder)
      let png = try PNGFile(file.data)
      XCTAssertEqual(png.chunks.map(\.type).first, "IHDR")
      XCTAssertEqual(png.chunks.map(\.type).last, "IEND")
      let ihdr = try XCTUnwrap(png.chunk("IHDR")).body
      XCTAssertEqual(Array(ihdr[8...12]), [8, 2, 0, 0, 0], "8-bit RGB")
      let phys = try XCTUnwrap(png.chunk("pHYs")).body
      XCTAssertEqual(Array(phys[0..<4]), [0, 0, 0x2E, 0x23], "11811 pixels per metre = 300 dpi")
      XCTAssertEqual(phys[8], 1)
      var ink = 0
      var paper = 0
      for index in 0..<(png.width * png.height) {
        let red = png.pixels[index * 3]
        // Red is the lightest channel of the warm tones, so a dark red is a dark pixel.
        if red < 128 { ink += 1 }
        if red == 255, png.pixels[index * 3 + 1] == 255, png.pixels[index * 3 + 2] == 255 {
          paper += 1
        }
      }
      XCTAssertGreaterThan(ink, 0, "has dark ink")
      XCTAssertGreaterThan(paper, png.width * png.height / 4, "has white paper")
      XCTAssertEqual(file.mime, "image/png")
      XCTAssertEqual(file.role, .planPNG)
    }
  }

  func testPNGSizeIsThePlanAtSheetScaleAndThreeHundredDPI() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let png = try PNGFile(try PNGWriter.write(model: capture.model).data)
    // 112 x 92 mm at 300 dpi.
    XCTAssertEqual(Double(png.width), 112 * 300 / 25.4, accuracy: 1)
    XCTAssertEqual(Double(png.height), 92 * 300 / 25.4, accuracy: 1)
    // The 4 m wall is a dark horizontal run about 80 mm = 945 px long.
    var longest = 0
    for row in 0..<png.height {
      var run = 0
      for column in 0..<png.width {
        if png.pixels[(row * png.width + column) * 3] < 100 {
          run += 1
          longest = max(longest, run)
        } else {
          run = 0
        }
      }
    }
    XCTAssertEqual(Double(longest), 80 * 300 / 25.4, accuracy: 20)
  }

  /// R, G, B bytes of a colour, rounded as the SVG's hex colours are.
  private func bytes(_ color: DrawingColor) -> [UInt8] {
    [color.red, color.green, color.blue].map { UInt8((max(0, min(1, $0)) * 255).rounded()) }
  }

  func testPNGPaintsPaperWhiteInkBrandBlackAndGraysInWarmTones() throws {
    // One 4 x 3 m room, no openings or objects: 112 x 92 mm at 1:50 with the room from 16 mm
    // in on the left and bottom, its labels in the middle and the scale bar at the bottom left.
    let png = try PNGFile(try PNGWriter.write(model: Synthetic.room(width: 4, length: 3)).data)
    XCTAssertEqual(png.colorType, 2)
    func row(_ yMM: Double) -> Int { Int((92 - yMM) * 300 / 25.4) }
    func column(_ xMM: Double) -> Int { Int(xMM * 300 / 25.4) }
    // Paper: the top right corner pixel.
    XCTAssertEqual(png.rgb(png.width - 1, 0), [255, 255, 255])
    // Ink: the middle of the 0.5 mm bottom wall line at y = 16 mm is the brand black #231F20.
    XCTAssertEqual(png.rgb(column(40), row(16)), [35, 31, 32])
    // Room fill, half a metre in from the lower left corner: the Chapter tone of its gray,
    // warm (red above blue) and not paper.
    let fill = png.rgb(column(26), row(26))
    XCTAssertEqual(fill, bytes(PNGWriter.colors[242]))
    for (channel, expected) in bytes(ChapterBrand.tone(PlanScene.roomFillGray)).enumerated() {
      XCTAssertEqual(Double(fill[channel]), Double(expected), accuracy: 1)
    }
    XCTAssertGreaterThan(fill[0], fill[2])
    XCTAssertNotEqual(fill, [255, 255, 255])
    // Up from the paper below the wall to its middle: white, warm anti-aliased edge pixels
    // that darken step by step, then the brand black.
    var previous: [UInt8] = [255, 255, 255]
    var edge = 0
    for y in stride(from: row(14), through: row(16), by: -1) {
      let pixel = png.rgb(column(40), y)
      for channel in 0..<3 { XCTAssertLessThanOrEqual(pixel[channel], previous[channel]) }
      if pixel != [255, 255, 255] && pixel != [35, 31, 32] {
        edge += 1
        XCTAssertGreaterThan(pixel[0], pixel[2], "warm edge pixel \(pixel)")
      }
      previous = pixel
    }
    XCTAssertGreaterThan(edge, 0, "anti-aliased edge")
    XCTAssertEqual(previous, [35, 31, 32])
  }

  func testPNGColoursAreTheChapterTonesAndRampSmoothlyToPaper() {
    let colors = PNGWriter.colors
    XCTAssertEqual(colors.count, 256)
    XCTAssertEqual(bytes(colors[0]), [35, 31, 32], "brand black")
    XCTAssertEqual(bytes(colors[255]), [255, 255, 255], "paper")
    // A mid gray is a warm gray between them.
    let middle = bytes(colors[128])
    XCTAssertGreaterThan(middle[0], middle[2])
    XCTAssertTrue((36..<255).contains(middle[0]), "\(middle)")
    // Every gray the scene paints is its ChapterBrand.tone, as in plan.pdf and plan.svg.
    for gray in [0, 0.25, 0.35, 0.45, 0.8, PlanScene.roomFillGray, 1] {
      let level = Int((gray * 255).rounded())
      for (channel, expected) in bytes(ChapterBrand.tone(gray)).enumerated() {
        XCTAssertEqual(
          Double(bytes(colors[level])[channel]), Double(expected), accuracy: 1, "gray \(gray)")
      }
    }
    // No step anywhere (anti-aliased edges against paper included): each level is at most a
    // few bytes lighter than the one below it, never darker.
    for level in 1..<256 {
      for channel in 0..<3 {
        let step = Int(bytes(colors[level])[channel]) - Int(bytes(colors[level - 1])[channel])
        XCTAssertTrue((0...3).contains(step), "level \(level) channel \(channel) step \(step)")
      }
    }
  }

  func testDeflateRoundTripsDifferentData() throws {
    var generator = SystemRandomNumberGenerator()
    let random = (0..<70_000).map { _ in UInt8.random(in: 0...255, using: &generator) }
    let runs = [UInt8](repeating: 255, count: 100_000) + [UInt8](repeating: 0, count: 5)
    let pattern = (0..<50_000).map { UInt8(($0 / 7) % 251) }
    for data in [[], [7], random, runs, pattern, Array("abcabcabcabc".utf8)] as [[UInt8]] {
      let packed = Deflate.zlibCompress(data)
      XCTAssertEqual(try TestInflate.zlib(packed), data)
    }
    XCTAssertLessThan(Deflate.zlibCompress(runs).count, 1000)
  }

  func testPNGHasValidCRCsAndKnownPixels() throws {
    let pixels: [UInt8] = [0, 255, 128, 64, 255, 0]
    let data = PNGEncoder.encodeGrayscale(width: 3, height: 2, pixels: pixels)
    let png = try PNGFile(data)
    XCTAssertEqual(png.width, 3)
    XCTAssertEqual(png.height, 2)
    XCTAssertEqual(png.pixels, pixels)
    XCTAssertNil(png.chunk("pHYs"))
  }

  func testRGBPNGPaintsEachGrayLevelInItsColour() throws {
    let pixels: [UInt8] = [0, 255, 128, 64, 255, 0]
    // Level g in (g, 255 - g, g / 2).
    let colors = (0...255).map { level in
      DrawingColor(hex: UInt32(level) << 16 | UInt32(255 - level) << 8 | UInt32(level / 2))
    }
    let data = PNGEncoder.encodeRGB(width: 3, height: 2, pixels: pixels, colors: colors, dpi: 300)
    let png = try PNGFile(data)
    XCTAssertEqual(png.width, 3)
    XCTAssertEqual(png.height, 2)
    XCTAssertEqual(png.colorType, 2)
    XCTAssertEqual(png.pixels, pixels.flatMap { [$0, 255 - $0, $0 / 2] })
    XCTAssertEqual(png.rgb(2, 0), [128, 127, 64])
    let phys = try XCTUnwrap(png.chunk("pHYs")).body
    XCTAssertEqual(Array(phys[0..<4]), [0, 0, 0x2E, 0x23])
  }

  func testPreviewsOfPlanWithNothingToDrawThrow() {
    var model = Synthetic.room(width: 4, length: 3)
    model.rooms = []
    model.walls = []
    XCTAssertThrowsError(try SVGWriter.write(model: model))
    XCTAssertThrowsError(try PNGWriter.write(model: model))
  }
}
