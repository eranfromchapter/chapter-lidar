import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// The north symbol of compass §6.1 / §6.3 and plan-sheet §4 (PS4): its states and captions
/// follow contract/test-vectors/compass-states.json, and its geometry the artboard's 32 × 32 box.
final class NorthArrowTests: XCTestCase {
  private let point = 25.4 / 72
  private let center = DrawingPoint(x: 100, y: 100)

  private func parts(_ items: [DrawingItem]) -> (shapes: [DrawingShape], texts: [DrawingText]) {
    var shapes: [DrawingShape] = []
    var texts: [DrawingText] = []
    for item in items {
      switch item {
      case .shape(let shape): shapes.append(shape)
      case .text(let text): texts.append(text)
      case .clipped: XCTFail("the symbol is never clipped")
      }
    }
    return (shapes, texts)
  }

  private func bounds(_ shape: DrawingShape)
    -> (minX: Double, minY: Double, maxX: Double, maxY: Double)
  {
    let xs = shape.path.points.map(\.x)
    let ys = shape.path.points.map(\.y)
    return (xs.min()!, ys.min()!, xs.max()!, ys.max()!)
  }

  /// The corners of a polygon path, in order.
  private func corners(_ shape: DrawingShape) -> [DrawingPoint] {
    shape.path.elements.compactMap { element in
      switch element {
      case .move(let p), .line(let p): return p
      default: return nil
      }
    }
  }

  private func assertClose(
    _ a: DrawingPoint, _ b: DrawingPoint, _ message: String = "",
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(a.x, b.x, accuracy: 1e-9, message, file: file, line: line)
    XCTAssertEqual(a.y, b.y, accuracy: 1e-9, message, file: file, line: line)
  }

  // MARK: Shared vectors

  private struct Vector: Decodable {
    struct Fields: Decodable {
      var capturedAt: UTCTimestamp
      var finishedAt: UTCTimestamp?
      var heading: Double?
      var headingAccuracy: Int?
      var headingSource: HeadingSource?
      var headingRecordedAt: UTCTimestamp?
      var headingIssue: HeadingIssue?
    }
    struct Symbol: Decodable {
      var kind: String
      var angleCcw: Double?
      var approximate: Bool?
      var lines: [String]?
      var box: String?
      var caption: String?
    }
    struct Expected: Decodable {
      var symbol: Symbol
    }
    var name: String
    var capture: Fields
    var rotationCcw: Double
    var expected: Expected
  }

  func testEveryCompassVectorDrawsItsSymbolAndCaptions() throws {
    let url = Repo.root.appendingPathComponent("contract/test-vectors/compass-states.json")
    let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
    XCTAssertGreaterThanOrEqual(vectors.count, 30)
    for vector in vectors {
      let fields = vector.capture
      let capture = CaptureRecord.Capture(
        captureId: LowercaseUUID(rawValue: "3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35")!,
        areaKey: "floor-1", label: "Floor 1", mode: .floor, units: .init(display: .imperial),
        capturedAt: fields.capturedAt, finishedAt: fields.finishedAt, heading: fields.heading,
        headingAccuracy: fields.headingAccuracy, headingSource: fields.headingSource,
        headingRecordedAt: fields.headingRecordedAt, headingIssue: fields.headingIssue)
      let symbol = NorthSymbol(state: CompassState(capture), drawingRotationCCW: vector.rotationCcw)
      let boxMM = 40 * point
      let (shapes, texts) = parts(
        NorthArrow.items(
          symbol: symbol, centerMM: center, boxMM: boxMM, page: .white, caption: true))
      let expected = vector.expected.symbol
      if expected.kind == "arrow" {
        XCTAssertEqual(texts.map(\.string), ["N"] + (expected.lines ?? []), vector.name)
        XCTAssertEqual(shapes.count, 2, "ring and arrow: \(vector.name)")
        // The tip points `angleCcw` counter-clockwise from up.
        let tip = try XCTUnwrap(corners(shapes[1]).first, vector.name)
        let angle = try XCTUnwrap(expected.angleCcw, vector.name) * .pi / 180
        let reach = (16 - 6.5) * boxMM / 32
        assertClose(
          tip, DrawingPoint(x: center.x - sin(angle) * reach, y: center.y + cos(angle) * reach),
          vector.name)
        XCTAssertEqual(shapes[0].stroke?.dash.isEmpty, expected.approximate != true, vector.name)
      } else {
        XCTAssertEqual(
          texts.map(\.string), [expected.box ?? "", expected.caption ?? ""], vector.name)
        // The box's border only: never a ring or an arrow.
        XCTAssertEqual(shapes.count, 1, vector.name)
        XCTAssertNil(shapes[0].fill, vector.name)
      }
    }
  }

  // MARK: Geometry

  func testVerifiedGeometryAtTheArtboardSize() throws {
    let boxMM = 32 * point
    let s = boxMM / 32
    let symbol = NorthSymbol(state: .verified(heading: 0, accuracy: 8))
    let (shapes, texts) = parts(
      NorthArrow.items(symbol: symbol, centerMM: center, boxMM: boxMM, page: .white, caption: true))
    XCTAssertEqual(shapes.count, 2)
    // Ring: circle (16, 18) r 10.5, stroke 0.75, solid, no fill, in ink.
    let ring = bounds(shapes[0])
    XCTAssertEqual((ring.minX + ring.maxX) / 2, center.x, accuracy: 1e-9)
    XCTAssertEqual((ring.minY + ring.maxY) / 2, center.y - 2 * s, accuracy: 1e-9)
    XCTAssertEqual((ring.maxX - ring.minX) / 2, 10.5 * s, accuracy: 1e-9)
    XCTAssertNil(shapes[0].fill)
    XCTAssertEqual(shapes[0].stroke?.width ?? 0, 0.75 * s, accuracy: 1e-12)
    XCTAssertEqual(shapes[0].stroke?.dash, [])
    XCTAssertEqual(shapes[0].stroke?.color, ChapterBrand.ink)
    // Arrow: (16, 6.5) (20.5, 25.5) (16, 22) (11.5, 25.5), filled and stroked in ink, round joins.
    let expected = [(16.0, 6.5), (20.5, 25.5), (16.0, 22.0), (11.5, 25.5)].map {
      DrawingPoint(x: center.x + s * ($0.0 - 16), y: center.y + s * (16 - $0.1))
    }
    for (corner, want) in zip(corners(shapes[1]), expected) { assertClose(corner, want) }
    XCTAssertEqual(shapes[1].fill, ChapterBrand.ink)
    XCTAssertEqual(shapes[1].stroke?.join, .round)
    XCTAssertEqual(shapes[1].stroke?.width ?? 0, 0.75 * s, accuracy: 1e-12)
    // N: Inter SemiBold 6, centred on x 16, baseline y 4.6.
    let letter = texts[0]
    XCTAssertEqual(letter.string, "N")
    XCTAssertTrue(letter.bold)
    XCTAssertEqual(letter.anchor, .center)
    XCTAssertEqual(letter.size, 6 * s, accuracy: 1e-12)
    XCTAssertEqual(letter.rotationDegrees, 0)
    assertClose(letter.position, DrawingPoint(x: center.x, y: center.y + s * (16 - 4.6)))
    // Caption: two centred lines, Inter 7.5 on 9 pt lines in the muted colour, 2 pt under the
    // box, capitals centred in each line box.
    XCTAssertEqual(
      texts.map(\.string).dropFirst(),
      ["True north \u{00B7} compass", "\u{00B1}8\u{00B0} \u{00B7} 0\u{00B0}"])
    let firstTop = center.y - boxMM / 2 - 2 * point
    for (index, line) in texts.dropFirst().enumerated() {
      XCTAssertEqual(line.size, 7.5 * point, accuracy: 1e-12)
      XCTAssertFalse(line.bold)
      XCTAssertEqual(line.color, ChapterBrand.muted)
      XCTAssertEqual(line.anchor, .center)
      XCTAssertEqual(line.position.x, center.x, accuracy: 1e-12)
      XCTAssertEqual(line.rotationDegrees, 0, "captions do not turn")
      let top = firstTop - Double(index) * 9 * point
      XCTAssertEqual(line.position.y, top - (4.5 + 0.727 * 7.5 / 2) * point, accuracy: 1e-9)
    }
    // Without the caption: the box alone.
    let bare = parts(
      NorthArrow.items(
        symbol: symbol, centerMM: center, boxMM: boxMM, page: .white, caption: false))
    XCTAssertEqual(bare.texts.map(\.string), ["N"])
    XCTAssertEqual(bare.shapes, shapes)
  }

  func testTheSymbolTurnsAboutTheBoxCentreAndEveryPointStaysInItsCircle() throws {
    let boxMM = 40 * point
    for (heading, rho, want) in [(90.0, 0.0, 90.0), (212.4, 0.0, 212.4), (90.0, -30.0, 60.0)] {
      let symbol = NorthSymbol(
        state: .verified(heading: heading, accuracy: 8), drawingRotationCCW: rho)
      let (shapes, texts) = parts(
        NorthArrow.items(
          symbol: symbol, centerMM: center, boxMM: boxMM, page: .white, caption: false))
      let radians = want * .pi / 180
      let reach = 9.5 * boxMM / 32
      let tip = try XCTUnwrap(corners(shapes[1]).first)
      assertClose(
        tip, DrawingPoint(x: center.x - sin(radians) * reach, y: center.y + cos(radians) * reach),
        "\(heading) \(rho)")
      XCTAssertEqual(texts[0].rotationDegrees, want, accuracy: 1e-9)
      // Nothing leaves the box's circle at any angle.
      for shape in shapes {
        for p in shape.path.points {
          let distance = hypot(p.x - center.x, p.y - center.y)
          XCTAssertLessThanOrEqual(distance, boxMM / 2 + 0.75 * boxMM / 64 + 1e-9)
        }
      }
    }
    // h = 90 on an unturned plan: the scan's -Z points east, so north is to the left.
    let east = NorthSymbol(state: .verified(heading: 90, accuracy: 8))
    let tip = try XCTUnwrap(
      corners(
        parts(
          NorthArrow.items(
            symbol: east, centerMM: center, boxMM: boxMM, page: .white, caption: false)
        ).shapes[1]
      ).first)
    XCTAssertLessThan(tip.x, center.x - 1)
  }

  func testApproximateIsADashedRingAndAHollowArrow() throws {
    let page = DrawingColor(hex: 0xFAF5EE)
    let ink = DrawingColor(hex: 0x1F2429)
    for size in [26.0, 32.0, 40.0] {
      let boxMM = size * point
      let s = boxMM / 32
      let symbol = NorthSymbol(
        state: .approximate(heading: 87.5, accuracy: 12, source: .magnetic))
      let (shapes, texts) = parts(
        NorthArrow.items(
          symbol: symbol, centerMM: center, boxMM: boxMM, page: page, caption: true, ink: ink))
      XCTAssertEqual(shapes[0].stroke?.dash, [1.6 * s, 1.6 * s], "\(size)")
      XCTAssertEqual(shapes[0].stroke?.cap, .butt)
      XCTAssertEqual(shapes[1].fill, page, "hollow: the page colour")
      XCTAssertEqual(shapes[1].stroke?.color, ink, "the host's ink")
      XCTAssertEqual(texts[0].color, ink)
      XCTAssertEqual(
        texts.map(\.string),
        ["N", "Approx. north \u{00B7} compass", "\u{00B1}12\u{00B0} \u{00B7} magnetic"])
    }
    // At 40 pt (the plan sheet) the dash is 2 pt on, 2 pt off.
    let sheet = parts(
      NorthArrow.items(
        symbol: NorthSymbol(state: .approximate(heading: 0, accuracy: 20, source: .trueNorth)),
        centerMM: center, boxMM: 40 * point, page: .white, caption: false))
    XCTAssertEqual(sheet.shapes[0].stroke?.dash[0] ?? 0, 2 * point, accuracy: 1e-12)
  }

  func testTheRingStartsAtItsRightmostPointAndRunsClockwiseAsTheArtboardCircle() throws {
    // An SVG circle starts at (cx + r, cy) and runs clockwise on the page; the dashes of an
    // approximate reading start there, so the ring is drawn the same way, turned with the box.
    let boxMM = 32 * point
    let s = boxMM / 32
    for angle in [0.0, 32.0, 212.4] {
      let symbol = NorthSymbol(state: .approximate(heading: angle, accuracy: 12, source: .magnetic))
      let ring = parts(
        NorthArrow.items(
          symbol: symbol, centerMM: center, boxMM: boxMM, page: .white, caption: false)
      ).shapes[0]
      let ends = ring.path.elements.compactMap { element -> DrawingPoint? in
        switch element {
        case .move(let p), .curve(_, _, let p): return p
        default: return nil
        }
      }
      XCTAssertEqual(ends.count, 5, "four quarter arcs, back to the start")
      let a = angle * .pi / 180
      // View box (x, y down) about the box centre (16, 16), turned counter-clockwise by A.
      func onPage(_ x: Double, _ y: Double) -> DrawingPoint {
        let dx = (x - 16) * s
        let dy = (16 - y) * s
        return DrawingPoint(
          x: center.x + dx * cos(a) - dy * sin(a), y: center.y + dx * sin(a) + dy * cos(a))
      }
      // (26.5, 18), then (16, 28.5), (5.5, 18), (16, 7.5): right, bottom, left, top.
      let expected = [(26.5, 18.0), (16.0, 28.5), (5.5, 18.0), (16.0, 7.5), (26.5, 18.0)]
      for (end, want) in zip(ends, expected) {
        assertClose(end, onPage(want.0, want.1), "A \(angle)")
      }
    }
  }

  func testNotVerifiedIsATextBoxThatDoesNotScale() throws {
    let symbol = NorthSymbol(state: .notVerified(.inaccurate, accuracy: 42))
    let text = "Orientation: not verified"
    let width = FontMetrics.width(text, size: 7.5 * point) + 12 * point
    var drawn: [[DrawingItem]] = []
    for size in [26.0, 32.0, 40.0] {
      let items = NorthArrow.items(
        symbol: symbol, centerMM: center, boxMM: size * point, page: .white, caption: true)
      drawn.append(items)
      let (shapes, texts) = parts(items)
      XCTAssertEqual(texts.map(\.string), [text, "Compass accuracy \u{00B1}42\u{00B0}"])
      XCTAssertEqual(shapes.count, 1)
      // The border: 15 pt tall (padding 3 + line 9 + 3), text width + 12 pt wide, stroked
      // 0.75 pt on its edge in the muted colour, 3 pt corners, no fill.
      let box = bounds(shapes[0])
      XCTAssertEqual(box.maxX - box.minX, width, accuracy: 1e-9)
      XCTAssertEqual(box.maxY - box.minY, 15 * point, accuracy: 1e-9)
      XCTAssertEqual((box.minX + box.maxX) / 2, center.x, accuracy: 1e-9)
      XCTAssertNil(shapes[0].fill)
      XCTAssertEqual(shapes[0].stroke?.width ?? 0, 0.75 * point, accuracy: 1e-12)
      XCTAssertEqual(shapes[0].stroke?.color, ChapterBrand.muted)
      let curves = shapes[0].path.elements.filter {
        if case .curve = $0 { return true }
        return false
      }
      XCTAssertEqual(curves.count, 4, "rounded corners")
      let corner = try XCTUnwrap(
        shapes[0].path.elements.first.flatMap { element -> DrawingPoint? in
          if case .move(let p) = element { return p }
          return nil
        })
      XCTAssertEqual(corner.x - box.minX, 3 * point, accuracy: 1e-9, "radius 3 pt")
      // The box text in ink, the reason in the muted colour 2 pt under the box.
      XCTAssertEqual(texts[0].color, ChapterBrand.ink)
      XCTAssertEqual(texts[0].size, 7.5 * point, accuracy: 1e-12)
      XCTAssertEqual(texts[1].color, ChapterBrand.muted)
      let boxTop = box.maxY
      XCTAssertEqual(
        texts[0].position.y, boxTop - (3 + 4.5 + 0.727 * 7.5 / 2) * point, accuracy: 1e-9)
      XCTAssertEqual(
        texts[1].position.y, box.minY - (2 + 4.5 + 0.727 * 7.5 / 2) * point, accuracy: 1e-9)
      // The block (26 pt) is centred where the arrow block would be: 10 pt under the box
      // centre (half its 2 + 18 pt caption).
      let blockMiddle = (boxTop + box.minY - (2 + 9) * point) / 2
      XCTAssertEqual(blockMiddle, center.y - 10 * point, accuracy: 1e-9)
    }
    XCTAssertEqual(drawn[0], drawn[2], "the box does not scale with the symbol size")
    // Without the caption the box alone, centred on the centre.
    let bare = parts(
      NorthArrow.items(
        symbol: symbol, centerMM: center, boxMM: 40 * point, page: .white, caption: false))
    XCTAssertEqual(bare.texts.map(\.string), [text])
    let box = bounds(bare.shapes[0])
    XCTAssertEqual((box.minY + box.maxY) / 2, center.y, accuracy: 1e-9)
  }

  func testBlockSizes() {
    let boxMM = 40 * point
    let caption = (2 + 18) * point
    let verified = NorthSymbol(state: .verified(heading: 212.4, accuracy: 8))
    guard case .arrow(_, _, let line1, _) = verified else { return XCTFail("arrow") }
    let line1Width = FontMetrics.width(line1, size: 7.5 * point)
    let size = NorthArrow.blockSizeMM(symbol: verified, boxMM: boxMM, caption: true)
    XCTAssertEqual(size.width, max(boxMM, line1Width), accuracy: 1e-12)
    XCTAssertEqual(size.height, boxMM + caption, accuracy: 1e-12)
    let bare = NorthArrow.blockSizeMM(symbol: verified, boxMM: boxMM, caption: false)
    XCTAssertEqual(bare.width, boxMM)
    XCTAssertEqual(bare.height, boxMM)
    // The not-verified block: 26 pt with its reason, 15 pt without; as wide as the wider line.
    let unread = NorthSymbol(state: .notVerified(.noReading, accuracy: nil))
    let box = FontMetrics.width("Orientation: not verified", size: 7.5 * point) + 12 * point
    let block = NorthArrow.blockSizeMM(symbol: unread, boxMM: boxMM, caption: true)
    XCTAssertEqual(block.width, box, accuracy: 1e-12)
    XCTAssertEqual(block.height, 26 * point, accuracy: 1e-12)
    XCTAssertEqual(
      NorthArrow.blockSizeMM(symbol: unread, boxMM: boxMM, caption: false).height, 15 * point,
      accuracy: 1e-12)
    // The extent of the block about the box centre agrees with its size.
    for symbol in [verified, unread] {
      for withCaption in [true, false] {
        let extent = NorthArrow.blockExtentMM(symbol: symbol, boxMM: boxMM, caption: withCaption)
        let size = NorthArrow.blockSizeMM(symbol: symbol, boxMM: boxMM, caption: withCaption)
        XCTAssertEqual(extent.top - extent.bottom, size.height, accuracy: 1e-12)
      }
    }
  }

  func testLayerAndDefaultInk() {
    let items = NorthArrow.items(
      symbol: NorthSymbol(state: .verified(heading: 0, accuracy: 8)), centerMM: center,
      boxMM: 32 * point, page: .white, caption: true, layer: .sheet)
    let (shapes, texts) = parts(items)
    XCTAssertTrue(shapes.allSatisfy { $0.layer == .sheet })
    XCTAssertTrue(texts.allSatisfy { $0.layer == .sheet })
    XCTAssertEqual(shapes[1].fill, ChapterBrand.ink, "the Floorplan's brand black by default")
  }
}
