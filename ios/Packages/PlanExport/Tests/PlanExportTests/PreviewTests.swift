import CaptureContract
import Foundation
import XCTest

#if canImport(FoundationXML)
  import FoundationXML
#endif

@testable import PlanExport

/// plan.svg and plan.png: the plan sheet's drawing (plan-sheet §7, PS7).
final class PreviewTests: XCTestCase {
  private final class WellFormedChecker: NSObject, XMLParserDelegate {
    var elements: [String] = []
    var texts: [String] = []
    var textAttributes: [[String: String]] = []
    var currentText = ""
    var attributes: [[String: String]] = []
    var inText = false

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
      elements.append(elementName)
      attributes.append(attributeDict)
      if elementName == "text" || elementName == "title" {
        inText = true
        currentText = ""
        textAttributes.append(attributeDict)
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      if inText { currentText += string }
    }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      if elementName == "text" || elementName == "title" {
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

  private func sheet(_ capture: FixtureCapture) throws -> (PlanSheetOutput, PlanExportContext) {
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    return (try PlanSheetWriter.write(model: capture.model, context: context), context)
  }

  func testSVGIsTheSheetDrawingWithCapitalisedLabelsAndCourierDimensions() throws {
    for capture in try Fixtures.sheetCaptures() {
      let (output, context) = try sheet(capture)
      let file = SVGWriter.write(sheet: output, label: context.floorLabel)
      try Repo.write(file, folder: capture.outputFolder)
      let name = "\(capture.fixture) \(capture.truth.areaKey)"
      let (ok, checker) = parseXML(file.data)
      XCTAssertTrue(ok, "\(name) is not well-formed")
      XCTAssertEqual(checker.elements.first, "svg")
      XCTAssertEqual(
        checker.texts.first, "Floor plan - \(capture.truth.label) (1:\(output.scaleDenominator))")
      for room in capture.truth.rooms {
        XCTAssertTrue(
          checker.texts.contains(room.label.uppercased()), "\(name) \(room.label)")
      }
      // Room names Inter SemiBold with their letter spacing; dimensions in Courier.
      let names = zip(checker.texts, checker.textAttributes).filter { $0.1["font-weight"] == "600" }
      XCTAssertFalse(names.isEmpty, name)
      XCTAssertTrue(names.allSatisfy { $0.1["letter-spacing"] != nil }, name)
      let dimensions = output.drawing.sheetDimensions.map(\.text)
      XCTAssertFalse(dimensions.isEmpty, name)
      for text in dimensions {
        let index = try XCTUnwrap(checker.texts.firstIndex(of: text), "\(name) \(text)")
        XCTAssertEqual(
          checker.textAttributes[index]["font-family"], ChapterBrand.monoFamily, "\(name) \(text)")
      }
      // No north symbol or scale bar on a preview.
      let svg = String(decoding: file.data, as: UTF8.self)
      XCTAssertFalse(svg.contains("class=\"compass\""), name)
      XCTAssertFalse(svg.contains("class=\"scale-bar\""), name)
    }
  }

  func testSVGIsDrawnInPaperMillimetresAtTheSheetScaleWithASixMillimetreMargin() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let (output, context) = try sheet(capture)
    let text = String(
      decoding: SVGWriter.write(sheet: output, label: context.floorLabel).data, as: UTF8.self)
    let extent = FloorPlanDrawing.extent(of: PlanPreview.items(output.drawing, dimensions: true))
    let n = Double(output.scaleDenominator)
    XCTAssertEqual(output.scaleDenominator, 50)
    let width = Format.fixed(extent.width / n + 12, 2)
    let height = Format.fixed(extent.height / n + 12, 2)
    XCTAssertTrue(text.contains("width=\"\(width)mm\" height=\"\(height)mm\""), text)
    XCTAssertTrue(
      text.contains(
        "viewBox=\"0 0 \(Format.fixed(extent.width + 12 * n, 2)) "
          + "\(Format.fixed(extent.height + 12 * n, 2))\""))
    XCTAssertTrue(text.contains("<rect x=\"0\" y=\"0\""))
    XCTAssertTrue(text.contains("fill=\"#ffffff\"/>"))
    // Window clears are white on the preview (the sheet's page colour on the sheet).
    let windows = PlanPreview.items(output.drawing, dimensions: true).compactMap {
      item -> DrawingShape? in
      if case .shape(let shape) = item, shape.layer == .window, shape.fill != nil { return shape }
      return nil
    }
    XCTAssertFalse(windows.isEmpty)
    XCTAssertTrue(windows.allSatisfy { $0.fill == .white })
    XCTAssertTrue(
      text.contains(
        "Plan millimetres, drawn for 1:50. Wall thickness is assumed (4.5 in inside, 6 in "
          + "outside); measurements are scan estimates."))
  }

  func testSVGEscapesMarkupAndStripsControlCharacters() throws {
    var capture = try XCTUnwrap(Fixtures.load("box-room").first)
    capture.record.captures[0].label = "A&B <x> \"q\"\u{1}"
    let (output, context) = try sheet(capture)
    let file = SVGWriter.write(sheet: output, label: context.floorLabel)
    XCTAssertTrue(parseXML(file.data).ok)
    XCTAssertTrue(String(decoding: file.data, as: UTF8.self).contains("A&amp;B &lt;x&gt; &quot;q&quot; "))
    XCTAssertEqual(SVGWriter.escape("\u{FFFE}a"), " a")
  }

  func testPNGIsRGBAtThreeHundredDPIWithoutDimensions() throws {
    for capture in try Fixtures.sheetCaptures() {
      let (output, _) = try sheet(capture)
      let file = PNGWriter.write(sheet: output)
      try Repo.write(file, folder: capture.outputFolder)
      let png = try PNGFile(file.data)
      let name = "\(capture.fixture) \(capture.truth.areaKey)"
      XCTAssertEqual(png.colorType, 2, name)
      let phys = try XCTUnwrap(png.chunk("pHYs"), name).body
      // 11811 pixels per metre both ways, unit metre.
      XCTAssertEqual(phys, [0, 0, 0x2E, 0x23, 0, 0, 0x2E, 0x23, 1], name)
      // Size: the drawing without its dimension strings, + 6 mm each side, at 300 px per
      // paper inch.
      let items = PlanPreview.items(output.drawing, dimensions: false)
      XCTAssertFalse(
        items.contains {
          if case .text(let t) = $0 { return t.layer == .exteriorDimension }
          if case .shape(let s) = $0 { return s.layer == .exteriorDimension }
          return false
        }, name)
      let extent = FloorPlanDrawing.extent(of: items)
      let n = Double(output.scaleDenominator)
      XCTAssertEqual(
        Double(png.width), ((extent.width / n + 12) * 300 / 25.4).rounded(.up), accuracy: 0, name)
      XCTAssertEqual(
        Double(png.height), ((extent.height / n + 12) * 300 / 25.4).rounded(.up), accuracy: 0,
        name)
      XCTAssertEqual(png.rgb(0, 0), [255, 255, 255], "white paper \(name)")
    }
  }

  func testPNGPaintsInkWallsAndRoomFillsByClass() throws {
    // two-room-apartment: Living Room and Bedroom, both habitable (nude #E8DDD0); walls in the
    // sheet ink #1F2429.
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let (output, _) = try sheet(capture)
    let png = try PNGFile(PNGWriter.write(sheet: output).data)
    let drawing = output.drawing
    let items = PlanPreview.items(drawing, dimensions: false)
    let extent = FloorPlanDrawing.extent(of: items)
    let n = drawing.options.scaleDenominator
    let scale = 300 / 25.4 / n
    let margin = 6 * n
    func pixel(_ p: Point2) -> [UInt8] {
      png.rgb(
        Int(((p.x * 1000 - extent.minX + margin) * scale).rounded(.down)),
        Int(((extent.maxY + margin - p.y * 1000) * scale).rounded(.down)))
    }
    func close(_ a: [UInt8], _ b: [Int], _ name: String) {
      for (x, y) in zip(a, b) { XCTAssertLessThanOrEqual(abs(Int(x) - y), 2, "\(name): \(a)") }
    }
    // The middle of a wall piece.
    let piece = try XCTUnwrap(drawing.walls.pieces.first)
    let middle = piece.reduce(Point2(x: 0, y: 0), +) * (1 / Double(piece.count))
    close(pixel(middle), [31, 36, 41], "wall")
    // A point of the bedroom away from its label and furniture: near a corner inside.
    let bedroom = try XCTUnwrap(drawing.rooms.first { $0.label == "Bedroom" })
    XCTAssertEqual(drawing.fillClasses[bedroom.id], .habitable)
    let xs = bedroom.polygon.map(\.x)
    let ys = bedroom.polygon.map(\.y)
    close(pixel(Point2(x: xs.min()! + 0.15, y: ys.min()! + 0.15)), [232, 221, 208], "bedroom")
  }

  func testPNGRoomLabelIsInterSemiBoldSpacedAtItsPDFWidth() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let (output, _) = try sheet(capture)
    let png = try PNGFile(PNGWriter.write(sheet: output).data)
    let drawing = output.drawing
    let items = PlanPreview.items(drawing, dimensions: false)
    let extent = FloorPlanDrawing.extent(of: items)
    let n = drawing.options.scaleDenominator
    let scale = 300 / 25.4 / n
    let margin = 6 * n
    let label = try XCTUnwrap(
      items.compactMap { item -> DrawingText? in
        if case .text(let text) = item, text.font == .interSemiBold { return text }
        return nil
      }.first)
    XCTAssertEqual(label.string, "TEST ROOM")
    XCTAssertEqual(label.letterSpacing, 0.9 * 25.4 / 72 * n, accuracy: 1e-9)
    let left = (label.position.x - label.width / 2 - extent.minX + margin) * scale
    let right = (label.position.x + label.width / 2 - extent.minX + margin) * scale
    let baseline = Int(((extent.maxY + margin - label.position.y) * scale).rounded(.down))
    let capPixels = Int((label.size * 0.727 * scale).rounded(.down))
    var minX = Int.max
    var maxX = Int.min
    for y in (baseline - capPixels + 1)...baseline {
      for x in Int(left - 20)...Int(right + 20) where png.rgb(x, y)[0] < 128 {
        minX = min(minX, x)
        maxX = max(maxX, x)
      }
    }
    // Ink starts within T's side bearing and ends within M's.
    XCTAssertEqual(Double(minX), left, accuracy: 4)
    XCTAssertEqual(Double(maxX + 1), right, accuracy: 4)
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

  func testRGBPNGKeepsItsBytes() throws {
    let rgb: [UInt8] = [0, 255, 128, 64, 255, 0, 1, 2, 3, 250, 251, 252, 9, 8, 7, 100, 101, 102]
    let data = PNGEncoder.encodeRGB(width: 3, height: 2, rgb: rgb, dpi: 300)
    let png = try PNGFile(data)
    XCTAssertEqual(png.width, 3)
    XCTAssertEqual(png.height, 2)
    XCTAssertEqual(png.colorType, 2)
    XCTAssertEqual(png.pixels, rgb)
    XCTAssertEqual(png.rgb(2, 0), [1, 2, 3])
    let phys = try XCTUnwrap(png.chunk("pHYs")).body
    XCTAssertEqual(Array(phys[0..<4]), [0, 0, 0x2E, 0x23])
  }

  func testPreviewsOfPlanWithNothingToDrawThrow() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    var model = capture.model
    model.rooms = []
    model.walls = []
    model.doors = []
    model.windows = []
    model.openings = []
    model.objects = []
    let context = try PlanExportContext(record: capture.record, captureId: model.captureId)
    XCTAssertThrowsError(try SVGWriter.write(model: model, context: context)) { error in
      XCTAssertEqual(error as? PlanExportError, .noPlanGeometry)
    }
    XCTAssertThrowsError(try PNGWriter.write(model: model, context: context))
  }
}
