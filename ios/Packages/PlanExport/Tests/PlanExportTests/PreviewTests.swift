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
      XCTAssertEqual(Array(ihdr[8...12]), [8, 0, 0, 0, 0], "8-bit grayscale")
      let phys = try XCTUnwrap(png.chunk("pHYs")).body
      XCTAssertEqual(Array(phys[0..<4]), [0, 0, 0x2E, 0x23], "11811 pixels per metre = 300 dpi")
      XCTAssertEqual(phys[8], 1)
      XCTAssertTrue(png.pixels.contains { $0 < 128 }, "has dark ink")
      XCTAssertGreaterThan(png.pixels.filter { $0 == 255 }.count, png.pixels.count / 4, "has paper")
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
        if png.pixels[row * png.width + column] < 100 {
          run += 1
          longest = max(longest, run)
        } else {
          run = 0
        }
      }
    }
    XCTAssertEqual(Double(longest), 80 * 300 / 25.4, accuracy: 20)
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

  func testPreviewsOfPlanWithNothingToDrawThrow() {
    var model = Synthetic.room(width: 4, length: 3)
    model.rooms = []
    model.walls = []
    XCTAssertThrowsError(try SVGWriter.write(model: model))
    XCTAssertThrowsError(try PNGWriter.write(model: model))
  }
}
