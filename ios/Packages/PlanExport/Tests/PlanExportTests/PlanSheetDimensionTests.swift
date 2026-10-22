import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// The plan sheet's dimension strings (plan-sheet §3.4.2): room dimensions 12 pt outside the
/// building on every side, overall width and depth 33 pt outside on the top and left, Courier
/// 8.25 pt, 0.4 pt lines with 5 pt ticks.
final class PlanSheetDimensionTests: XCTestCase {
  private func output(_ capture: FixtureCapture) throws -> PlanSheetOutput {
    try PlanSheetWriter.write(
      model: capture.model,
      context: PlanExportContext(record: capture.record, captureId: capture.model.captureId))
  }

  /// The texts of the dimension layer, in points on the page.
  private func texts(_ output: PlanSheetOutput) -> [DrawingText] {
    output.items.compactMap { item in
      if case .text(let text) = item, text.layer == .exteriorDimension { return text }
      return nil
    }
  }

  func testBoxRoomRoomAndOverallDimensions() throws {
    let output = try output(try XCTUnwrap(Fixtures.load("box-room").first))
    let dimensions = output.drawing.sheetDimensions
    func values(side: SheetDimension.Side, tier: Int) -> [String] {
      dimensions.filter { $0.side == side && $0.tier == tier }.map(\.text)
    }
    // 4.000 × 3.000 m inside; 6 in exterior walls outside it on every side.
    XCTAssertEqual(values(side: .top, tier: 1), ["13' 1.5\""])
    XCTAssertEqual(values(side: .bottom, tier: 1), ["13' 1.5\""])
    XCTAssertEqual(values(side: .left, tier: 1), ["9' 10.1\""])
    XCTAssertEqual(values(side: .right, tier: 1), ["9' 10.1\""])
    XCTAssertEqual(values(side: .top, tier: 2), ["14' 1.5\""])
    XCTAssertEqual(values(side: .left, tier: 2), ["10' 10.1\""])
    XCTAssertTrue(values(side: .bottom, tier: 2).isEmpty)
    XCTAssertTrue(values(side: .right, tier: 2).isEmpty)
    // The overall box is the walls' outside faces at the assumed 6 in.
    let frame = try XCTUnwrap(output.drawing.sheetFrame)
    XCTAssertEqual(frame.width, 4 + 2 * 0.1524, accuracy: 1e-6)
    XCTAssertEqual(frame.height, 3 + 2 * 0.1524, accuracy: 1e-6)

    // On the page: Courier 8.25 pt, left and right turned +90° (reading up), 12 and 33 pt out.
    let page = texts(output)
    XCTAssertEqual(page.count, 6)
    for text in page {
      XCTAssertEqual(text.font, .courier)
      XCTAssertEqual(text.size, 8.25, accuracy: 1e-9)
      XCTAssertEqual(text.color, ChapterBrand.Sheet.ink)
    }
    let scale = output.pointsPerMM * 1000
    XCTAssertEqual(page.map(\.string), dimensions.map(\.text), "drawn in order")
    for (dimension, text) in zip(dimensions, page) {
      let horizontal = dimension.side == .top || dimension.side == .bottom
      XCTAssertEqual(text.rotationDegrees, horizontal ? 0 : 90, dimension.text)
      let offset = dimension.tier == 1 ? 12.0 : 33.0
      switch dimension.side {
      case .top: XCTAssertEqual((dimension.line - frame.maxY) * scale, offset, accuracy: 1e-6)
      case .bottom: XCTAssertEqual((frame.minY - dimension.line) * scale, offset, accuracy: 1e-6)
      case .left: XCTAssertEqual((frame.minX - dimension.line) * scale, offset, accuracy: 1e-6)
      case .right: XCTAssertEqual((dimension.line - frame.maxX) * scale, offset, accuracy: 1e-6)
      }
    }
    // Lines 0.4 pt ink, ticks 0.6 pt, 5 pt long.
    let shapes = output.items.compactMap { item -> DrawingShape? in
      if case .shape(let shape) = item, shape.layer == .exteriorDimension { return shape }
      return nil
    }
    XCTAssertEqual(shapes.map { $0.stroke?.width ?? 0 }.map { ($0 * 1000).rounded() / 1000 }, [0.4, 0.6])
    XCTAssertTrue(shapes.allSatisfy { $0.stroke?.color == ChapterBrand.Sheet.ink && $0.fill == nil })
    let ticks = shapes[1].path.elements.compactMap { element -> DrawingPoint? in
      if case .move(let p) = element { return p }
      return nil
    }
    let ends = shapes[1].path.elements.compactMap { element -> DrawingPoint? in
      if case .line(let p) = element { return p }
      return nil
    }
    XCTAssertEqual(ticks.count, 12)
    for (a, b) in zip(ticks, ends) {
      XCTAssertEqual(hypot(b.x - a.x, b.y - a.y), 5, accuracy: 1e-6)
    }
    // No inside-room dimensions on the sheet.
    XCTAssertFalse(
      output.drawing.items.contains {
        if case .shape(let shape) = $0 { return shape.layer == .interiorDimension }
        if case .text(let text) = $0 { return text.layer == .interiorDimension }
        return false
      })
  }

  func testTextSitsOnTheSideAwayFromTheBuilding() throws {
    let output = try output(try XCTUnwrap(Fixtures.load("box-room").first))
    let scale = output.pointsPerMM * 1000
    for (dimension, text) in zip(output.drawing.sheetDimensions, texts(output)) {
      let corners = FloorPlanDrawing.textCorners(text)
      let line = dimension.line * scale
        + ((dimension.side == .top || dimension.side == .bottom)
          ? output.offsetY : output.offsetX)
      switch dimension.side {
      case .top: XCTAssertGreaterThan(corners.map(\.y).min()!, line)
      case .bottom: XCTAssertLessThan(corners.map(\.y).max()!, line)
      case .left: XCTAssertLessThan(corners.map(\.x).max()!, line)
      case .right: XCTAssertGreaterThan(corners.map(\.x).min()!, line)
      }
    }
  }

  func testRoomValuesAreTheirBoundingBoxesAndAgreeWithTheDrawnSpans() throws {
    for capture in try Fixtures.sheetCaptures() {
      let output = try output(capture)
      let metrics = try PlanMetrics(capture.model)
      // The generated rooms are rectangles on the axes; the 424 sample has slanted walls, where
      // the room frame and the squared drawing part by more.
      let tolerance = capture.fixture == "sample-424" ? 0.0508 : 0.0254
      for dimension in output.drawing.sheetDimensions where dimension.tier == 1 {
        let room = try XCTUnwrap(metrics.rooms.first { $0.roomId == dimension.roomId })
        let box = room.boundingBox
        XCTAssertTrue(
          dimension.valueM == box.alongM || dimension.valueM == box.acrossM,
          "\(capture.fixture) \(dimension.text)")
        XCTAssertEqual(
          dimension.text, UnitFormatter(system: .imperial).dimension(dimension.valueM))
        // Measured value and drawn span within an inch (squaring moves walls by millimetres).
        XCTAssertEqual(
          dimension.valueM, dimension.spanM, accuracy: tolerance,
          "\(capture.fixture) \(dimension.text)")
      }
    }
  }

  func testWalkThroughDimensionsNeitherOverlapNorLeaveTheFrame() throws {
    let walk = try PlanSheetWriterTests.walkthrough()
    let output = try PlanSheetWriter.write(model: walk.model, context: walk.context)
    let page = texts(output)
    XCTAssertGreaterThan(page.count, 4)
    let boxes = page.map { text -> (String, Double, Double, Double, Double) in
      let corners = FloorPlanDrawing.textCorners(text)
      return (
        text.string, corners.map(\.x).min()!, corners.map(\.x).max()!, corners.map(\.y).min()!,
        corners.map(\.y).max()!
      )
    }
    for (i, a) in boxes.enumerated() {
      for b in boxes[(i + 1)...] {
        let overlaps = a.1 < b.2 && b.1 < a.2 && a.3 < b.4 && b.3 < a.4
        XCTAssertFalse(overlaps, "\(a.0) overlaps \(b.0)")
      }
      // Inside the annotation frame (x 42–906, y 42 to the footnote's top - 6 from the top).
      XCTAssertGreaterThanOrEqual(a.1, 42)
      XCTAssertLessThanOrEqual(a.2, 906)
      XCTAssertLessThanOrEqual(a.4, SheetItems.y(42))
      XCTAssertGreaterThanOrEqual(a.3, SheetItems.y(output.layout.footnoteTop - 6))
    }
    // Spans too short for their text are left out; none overlap on a side.
    for side in SheetDimension.Side.allCases {
      let spans = output.drawing.sheetDimensions.filter { $0.side == side && $0.tier == 1 }
      for (a, b) in zip(spans, spans.dropFirst()) {
        XCTAssertLessThanOrEqual(min(a.to, b.to) - max(a.from, b.from), 0.05)
      }
      for span in spans {
        XCTAssertGreaterThanOrEqual(span.spanM, 0.6)
      }
    }
  }

  func testValueFollowsTheRoomFrameTurnedIntoTheDrawing() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let room = try XCTUnwrap(try PlanMetrics(capture.model).rooms.first)
    // Unturned: along (4.000 m) is horizontal; a quarter turn makes it vertical.
    XCTAssertEqual(PlanSheetDimensions.value(of: room, side: .top, rotation: 0), 4, accuracy: 1e-9)
    XCTAssertEqual(PlanSheetDimensions.value(of: room, side: .left, rotation: 0), 3, accuracy: 1e-9)
    XCTAssertEqual(
      PlanSheetDimensions.value(of: room, side: .top, rotation: -3 * .pi / 2), 3, accuracy: 1e-9)
    XCTAssertEqual(
      PlanSheetDimensions.value(of: room, side: .right, rotation: -3 * .pi / 2), 4,
      accuracy: 1e-9)
  }
}
