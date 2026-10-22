import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// Scale of the plan sheet (plan-sheet §3.3, AC5, PS3): the ladder 1:50 → 1:100 → 1:200 (→
/// 1:500 for an exterior capture), never fitted to the page; true lengths at that scale; the
/// scale bar.
final class PlanSheetScaleTests: XCTestCase {
  /// A rectangular room `width` × `length` metres with the box room's record, in `mode`.
  private func sheet(width: Double, length: Double, mode: CaptureMode = .floor) throws
    -> PlanSheetOutput
  {
    let box = try XCTUnwrap(Fixtures.load("box-room").first)
    var model = Synthetic.room(width: width, length: length, label: "Hall")
    model.visitId = box.model.visitId
    model.captureId = box.model.captureId
    var record = box.record
    record.captures[0].mode = mode
    return try PlanSheetWriter.write(
      model: model, context: PlanExportContext(record: record, captureId: model.captureId))
  }

  private func shapes(_ output: PlanSheetOutput, layer: DrawingLayer) -> [DrawingShape] {
    func collect(_ items: [DrawingItem]) -> [DrawingShape] {
      items.flatMap { item -> [DrawingShape] in
        switch item {
        case .shape(let shape): return shape.layer == layer ? [shape] : []
        case .text: return []
        case .clipped(_, let children): return collect(children)
        }
      }
    }
    return collect(output.items)
  }

  private func extent(_ shape: DrawingShape) -> (width: Double, height: Double) {
    let xs = shape.path.points.map(\.x)
    let ys = shape.path.points.map(\.y)
    return (xs.max()! - xs.min()!, ys.max()! - ys.min()!)
  }

  /// 0.2 mm in points.
  private let tolerance = 0.2 * 72 / 25.4

  func testFourMetreRoomIsEightyMillimetresAtOneToFifty() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let output = try PlanSheetWriter.write(
      model: capture.model,
      context: PlanExportContext(record: capture.record, captureId: capture.model.captureId))
    XCTAssertEqual(output.scaleDenominator, 50)
    XCTAssertEqual(output.quarterTurns, 0)
    XCTAssertFalse(output.isClipped)
    // The room's fill: 4.000 × 3.000 m = 80.0 × 60.0 mm = 226.77 × 170.08 pt.
    let fill = try XCTUnwrap(
      shapes(output, layer: .roomFill).first { $0.fill == ChapterBrand.Sheet.ground })
    XCTAssertEqual(extent(fill).width, 226.77, accuracy: tolerance)
    XCTAssertEqual(extent(fill).height, 170.08, accuracy: tolerance)
    // The room dimensions span the same 4.000 m.
    let top = try XCTUnwrap(
      output.drawing.sheetDimensions.first { $0.side == .top && $0.tier == 1 })
    XCTAssertEqual(top.spanM * 1000 / 50 * 72 / 25.4, 226.77, accuracy: tolerance)
    // The scale bar: 86.4 pt (5 ft at 1:50, 30.48 mm on paper), its first half solid.
    let shown = PDFFile(output.file.data).shownText()
    for text in ["0", "2.5", "5 ft", "1:50 at 11 x 17 in"] { XCTAssertTrue(shown.contains(text)) }
    let bar = output.layout.items.compactMap { item -> DrawingShape? in
      if case .shape(let shape) = item, shape.stroke?.width == 0.6, shape.fill == nil,
        shape.stroke?.color == ChapterBrand.Sheet.ink, shape.path.elements.contains(.close)
      {
        return shape
      }
      return nil
    }
    XCTAssertEqual(bar.count, 1)
    XCTAssertEqual(extent(try XCTUnwrap(bar.first)).width, 86.4, accuracy: 1e-9)
    XCTAssertEqual(86.4 * 25.4 / 72 * 50 / 304.8, 5, accuracy: 1e-9, "5 ft at 1:50")
  }

  func testEveryFixtureWallIsDrawnToScale() throws {
    // Each room's fill spans its truth width or length at the sheet's scale.
    for capture in try Fixtures.all() {
      let output = try PlanSheetWriter.write(
        model: capture.model,
        context: PlanExportContext(record: capture.record, captureId: capture.model.captureId))
      let n = Double(output.scaleDenominator)
      let fills = shapes(output, layer: .roomFill).filter { $0.fill != nil }.map(extent)
      for room in capture.truth.rooms {
        let pts = [room.widthM, room.lengthM].map { $0 * 1000 / n * 72 / 25.4 }
        XCTAssertTrue(
          fills.contains { fill in
            pts.contains { abs(fill.width - $0) <= tolerance }
              || pts.contains { abs(fill.height - $0) <= tolerance }
          }, "\(capture.fixture) \(room.label)")
      }
    }
  }

  func testLargerPlansTakeTheNextRungOfTheLadder() throws {
    // The plan frame holds 13.76 × 11.0 m at 1:50, 27.5 × 22.0 m at 1:100, 55.0 × 44.0 m at
    // 1:200, 137.6 × 110.1 m at 1:500.
    let hundred = try sheet(width: 20, length: 9)
    XCTAssertEqual(hundred.scaleDenominator, 100)
    let shown = PDFFile(hundred.file.data).shownText()
    for text in ["1:100 at 11 x 17 in", "0", "5", "10 ft"] {
      XCTAssertTrue(shown.contains(text), text)
    }
    XCTAssertEqual(try sheet(width: 50, length: 40).scaleDenominator, 200)
    let exterior = try sheet(width: 120, length: 90, mode: .exterior)
    XCTAssertEqual(exterior.scaleDenominator, 500)
    XCTAssertTrue(PDFFile(exterior.file.data).shownText().contains("1:500 at 11 x 17 in"))
    XCTAssertTrue(PDFFile(exterior.file.data).shownText().contains("50 ft"))
    // A room that only fits turned a quarter is turned, at the first rung.
    let turned = try sheet(width: 9, length: 13)
    XCTAssertEqual(turned.scaleDenominator, 50)
    XCTAssertEqual(turned.quarterTurns, 3)
    // Three quarter turns counter-clockwise: one clockwise.
    XCTAssertEqual(turned.drawingRotationDegrees, -270, accuracy: 1e-9)
  }

  func testAFloorBiggerThanTheLastRungIsCutAtTheFrame() throws {
    let output = try sheet(width: 70, length: 50)
    XCTAssertEqual(output.scaleDenominator, 200)
    XCTAssertTrue(output.isClipped)
    let stream = PDFFile(output.file.data).contentStreams[0]
    XCTAssertTrue(stream.contains("36.750 36.750 m 911.250 36.750 l 911.250 755.250 l"), "clip")
    XCTAssertTrue(stream.contains(" W n\n"))
    XCTAssertTrue(
      output.layout.footnoteLines.joined(separator: " ").contains(
        "The plan is larger than this sheet at 1:200 and is cut at the frame. plan.dxf holds "
          + "the whole floor."))
    // An exterior capture cuts at 1:500.
    let exterior = try sheet(width: 200, length: 150, mode: .exterior)
    XCTAssertEqual(exterior.scaleDenominator, 500)
    XCTAssertTrue(exterior.isClipped)
  }

  func testDenominatorIsAlwaysOnTheLadder() throws {
    for capture in try Fixtures.sheetCaptures() {
      let output = try PlanSheetWriter.write(
        model: capture.model,
        context: PlanExportContext(record: capture.record, captureId: capture.model.captureId))
      XCTAssertTrue([50, 100, 200].contains(output.scaleDenominator), capture.fixture)
      XCTAssertFalse(output.isClipped, capture.fixture)
    }
  }

  func testPlanWithNothingToDrawThrows() throws {
    var capture = try XCTUnwrap(Fixtures.load("box-room").first)
    capture.model.rooms = []
    capture.model.walls = []
    capture.model.doors = []
    capture.model.windows = []
    capture.model.openings = []
    capture.model.objects = []
    XCTAssertThrowsError(
      try PlanSheetWriter.write(
        model: capture.model,
        context: PlanExportContext(record: capture.record, captureId: capture.model.captureId))
    ) { error in
      XCTAssertEqual(error as? PlanExportError, .noPlanGeometry)
    }
  }
}
