import Foundation
import XCTest

@testable import PlanExport

/// The RGB rasteriser of plan.png (`RasterCanvas`): fill rules, curves, dashes, clipping and
/// deterministic bytes.
final class RasterCanvasTests: XCTestCase {
  private let black = DrawingColor(0, 0, 0)
  private let identity: (DrawingPoint) -> Point2 = { Point2(x: $0.x, y: $0.y) }

  private func path(_ polygons: [[(Double, Double)]]) -> DrawingPath {
    var elements: [DrawingPath.Element] = []
    for polygon in polygons {
      elements.append(.move(DrawingPoint(x: polygon[0].0, y: polygon[0].1)))
      for p in polygon.dropFirst() { elements.append(.line(DrawingPoint(x: p.0, y: p.1))) }
      elements.append(.close)
    }
    return DrawingPath(elements: elements)
  }

  /// Ink of a canvas: the sum over pixels of how far each is from white, in pixels.
  private func ink(_ canvas: RasterCanvas) -> Double {
    canvas.grayPixels.reduce(0) { $0 + Double(255 - Int($1)) / 255 }
  }

  func testNonzeroAndEvenOddFills() {
    // A square with a square inside, both wound the same way: nonzero fills the hole, even-odd
    // leaves it.
    let outer = [(10.0, 10.0), (50.0, 10.0), (50.0, 50.0), (10.0, 50.0)]
    let inner = [(20.0, 20.0), (40.0, 20.0), (40.0, 40.0), (20.0, 40.0)]
    for evenOdd in [false, true] {
      var canvas = RasterCanvas(width: 60, height: 60)
      canvas.draw(
        [.shape(DrawingShape(path: path([outer, inner]), fill: black, evenOdd: evenOdd, layer: .wall))],
        scale: 1, transform: identity)
      XCTAssertEqual(canvas.rgb(15, 15).0, 0)
      XCTAssertEqual(canvas.rgb(30, 30).0, evenOdd ? 255 : 0, "hole with even-odd: \(evenOdd)")
      XCTAssertEqual(ink(canvas), evenOdd ? 1600 - 400 : 1600, accuracy: 1)
    }
  }

  func testBezierCircleAreaIsWithinHalfAPercent() {
    var canvas = RasterCanvas(width: 120, height: 120)
    var builder = PathBuilder()
    // PathBuilder takes metres: a circle of radius 50 (units) about (60, 60).
    builder.circle(center: Point2(x: 0.06, y: 0.06), radius: 0.05)
    canvas.draw(
      [.shape(DrawingShape(path: builder.path, fill: black, layer: .symbol))], scale: 1,
      transform: identity)
    XCTAssertEqual(ink(canvas), .pi * 50 * 50, accuracy: .pi * 50 * 50 * 0.005)
  }

  func testDashesAreDrawnOnAndOffAtTheirLengths() {
    // A 100 px line dashed 10 on / 5 off: dashes at 0–10, 15–25, ... 90–100 (7 dashes).
    var canvas = RasterCanvas(width: 120, height: 20)
    let line = DrawingPath(elements: [
      .move(DrawingPoint(x: 10, y: 10)), .line(DrawingPoint(x: 110, y: 10)),
    ])
    canvas.draw(
      [
        .shape(
          DrawingShape(
            path: line, stroke: DrawingStroke(color: black, width: 4, dash: [10, 5]), layer: .door))
      ], scale: 1, transform: identity)
    let row = (0..<120).map { canvas.rgb($0, 10).0 < 128 }
    var runs: [(start: Int, length: Int)] = []
    var x = 0
    while x < row.count {
      if row[x] {
        let start = x
        while x < row.count, row[x] { x += 1 }
        runs.append((start, x - start))
      } else {
        x += 1
      }
    }
    XCTAssertEqual(runs.count, 7)
    for (index, run) in runs.enumerated() {
      XCTAssertEqual(Double(run.start), Double(10 + 15 * index), accuracy: 0.5)
      XCTAssertEqual(Double(run.length), index == 6 ? 10 : 10, accuracy: 0.5)
    }
  }

  func testClippingKeepsOnlyWhatIsInsideTheClip() {
    var canvas = RasterCanvas(width: 60, height: 60)
    let all = path([[(0, 0), (60, 0), (60, 60), (0, 60)]])
    let clip = path([[(20, 20), (40, 20), (40, 40), (20, 40)]])
    canvas.draw(
      [.clipped(clip, [.shape(DrawingShape(path: all, fill: black, layer: .wall))])], scale: 1,
      transform: identity)
    XCTAssertEqual(ink(canvas), 400, accuracy: 1)
    XCTAssertEqual(canvas.rgb(10, 10).0, 255)
    XCTAssertEqual(canvas.rgb(30, 30).0, 0)
    // After the clipped group, drawing is no longer clipped.
    canvas.draw(
      [.shape(DrawingShape(path: all, fill: black, layer: .wall))], scale: 1, transform: identity)
    XCTAssertEqual(canvas.rgb(10, 10).0, 0)
  }

  func testColoursBlendOverThePaper() {
    var canvas = RasterCanvas(width: 10, height: 10)
    let square = path([[(0, 0), (10, 0), (10, 10), (0, 10)]])
    canvas.draw(
      [.shape(DrawingShape(path: square, fill: DrawingColor(hex: 0xE8DDD0), layer: .roomFill))],
      scale: 1, transform: identity)
    XCTAssertTrue(canvas.rgb(5, 5) == (232, 221, 208))
  }

  func testSamePlanSameBytes() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    let a = try PNGWriter.write(model: capture.model, context: context)
    let b = try PNGWriter.write(model: capture.model, context: context)
    XCTAssertEqual(a.data, b.data)
  }
}
