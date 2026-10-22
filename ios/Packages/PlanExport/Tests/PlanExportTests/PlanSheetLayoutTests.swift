import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// The plan sheet's title block (plan-sheet §3.6–3.7): stacking, gaps, overflow and the
/// placement of its parts.
final class PlanSheetLayoutTests: XCTestCase {
  private let verified = NorthSymbol(state: .verified(heading: 212.4, accuracy: 8))
  private let unread = NorthSymbol(state: .notVerified(.noReading, accuracy: nil))

  private func context(_ edit: (inout CaptureRecord) -> Void = { _ in }) throws -> PlanExportContext
  {
    var capture = try XCTUnwrap(Fixtures.load("box-room").first)
    edit(&capture.record)
    return try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
  }

  private func layout(
    _ context: PlanExportContext, rooms: Int = 1, north: NorthSymbol? = nil
  ) -> PlanSheetLayout {
    PlanSheetLayout.make(
      context: context, summary: PlanSheetSummary(floorAreaM2: 12, scannedRooms: rooms),
      scaleDenominator: 50, north: north ?? unread, tooBig: false)
  }

  /// The texts of the layout's title block with their extents (points, y up).
  private typealias Placed = (text: DrawingText, minX: Double, maxX: Double, minY: Double, maxY: Double)

  private func texts(_ layout: PlanSheetLayout) -> [Placed] {
    layout.items.compactMap { item in
      guard case .text(let text) = item, text.position.x > 912 else { return nil }
      let corners = FloorPlanDrawing.textCorners(text)
      return (
        text, corners.map(\.x).min()!, corners.map(\.x).max()!, corners.map(\.y).min()!,
        corners.map(\.y).max()!
      )
    }
  }

  func testStackingFromTheTopWithTheFooterPinnedToTheBottom() throws {
    let layout = layout(try context())
    XCTAssertEqual(layout.blocks.map(\.name), ["A", "B", "C", "D", "F", "G"])
    XCTAssertEqual(layout.blocks.first?.top, 60)
    XCTAssertEqual(layout.footer.bottom, 732, accuracy: 1e-9)
    XCTAssertEqual(layout.footer.height, 86.25, accuracy: 1e-9)
    // Heights of plan-sheet §3.6: header 36, data rows 7 × 20.75, note card 63, legend 69,
    // scale and north 60.
    XCTAssertEqual(layout.block("A")?.height, 36)
    XCTAssertEqual(layout.block("C")?.height, 145.25)
    XCTAssertEqual(layout.block("D")?.height, 63)
    XCTAssertEqual(layout.block("F")?.height, 69)
    XCTAssertEqual(layout.block("G")?.height, 60)
    // Room to spare: the gap is the drawn 14 pt.
    XCTAssertEqual(layout.gap, 14)
    for (a, b) in zip(layout.blocks, layout.blocks.dropFirst()) {
      XCTAssertEqual(b.top - a.bottom, layout.gap, accuracy: 1e-9)
    }
    XCTAssertLessThanOrEqual(try XCTUnwrap(layout.blocks.last).bottom, layout.footer.top)
  }

  func testTheFourTwentyFourSampleCompressesTheGap() throws {
    // 424 West End: title on two lines, line 1 on one, line 2 on two (broken before " · "),
    // two rooms not scanned: A 36 + B 100 + C 145.25 + D 63 + E 48 + F 69 + G 60 = 521.25;
    // footer 86.25; 7 gaps share 64.5 pt.
    let sample = try Fixtures.sample424()
    let context = try PlanExportContext(record: sample.record, captureId: sample.model.captureId)
    let layout = layout(context, rooms: 12, north: verified)
    XCTAssertEqual(layout.blocks.map(\.name), ["A", "B", "C", "D", "E", "F", "G"])
    XCTAssertEqual(layout.block("B")?.height, 100)
    XCTAssertEqual(layout.block("E")?.height, 48)
    XCTAssertEqual(layout.gap, 64.5 / 7, accuracy: 1e-9)
    XCTAssertEqual(layout.gap, 9.21, accuracy: 0.01)
  }

  func testManyRoomsNotScannedAreCutShortWithTheOverflowLine() throws {
    let context = try context { record in
      record.captures[0].omittedRooms = (1...10).map {
        .init(name: "Locked room \($0)", reason: "locked")
      }
    }
    let layout = layout(context)
    XCTAssertEqual(layout.gap, 8)
    XCTAssertGreaterThan(layout.notScannedOverflow, 0)
    XCTAssertEqual(layout.notScannedShown.count + layout.notScannedOverflow, 10)
    let strings = texts(layout).map(\.text.string)
    XCTAssertTrue(
      strings.contains("+\(layout.notScannedOverflow) more, listed in the spatial report"))
    XCTAssertTrue(strings.contains("Rooms not scanned have no geometry and are not drawn."))
    XCTAssertLessThanOrEqual(try XCTUnwrap(layout.blocks.last).bottom, layout.footer.top + 1e-9)
  }

  func testLongLabelsAndAddressesStayInsideTheTitleBlock() throws {
    let label = String(repeating: "Mezzanine level ", count: 7).trimmingCharacters(in: .whitespaces)
    let address = Array(repeating: "1234 Extraordinarily Long Boulevard Name", count: 8)
      .joined(separator: ", ")
    XCTAssertGreaterThanOrEqual(label.count, 100)
    XCTAssertGreaterThanOrEqual(address.count, 300)
    for projectName in [Optional("A Very Long Project Name That Goes On And On, Phase 2"), nil] {
      let context = try context { record in
        record.captures[0].label = label
        record.address.formatted = address
        record.hub.projectName = projectName
        record.captures[0].inaccessibleRooms = (1...4).map {
          .init(name: "Storage room \($0) with a very long name indeed", reason: nil)
        }
      }
      let layout = layout(context)
      let footerTop = SheetItems.y(layout.footer.top)
      for text in texts(layout) {
        XCTAssertGreaterThanOrEqual(text.minX, 936 - 0.01, text.text.string)
        XCTAssertLessThanOrEqual(text.maxX, 1164 + 0.01, text.text.string)
        if text.text.position.y > footerTop {
          XCTAssertGreaterThan(text.minY, footerTop, text.text.string)
        }
      }
      XCTAssertLessThanOrEqual(try XCTUnwrap(layout.blocks.last).bottom, layout.footer.top + 1e-9)
      // The sheet id wraps onto its second line, then is cut.
      let ids = texts(layout).filter { $0.text.letterSpacing == 1.5 && $0.text.anchor == .trailing }
      XCTAssertEqual(ids.count, 2)
      XCTAssertTrue(ids[0].text.string.hasPrefix("SHEET 1"))
      XCTAssertTrue(ids[1].text.string.hasSuffix("..."))
      XCTAssertLessThanOrEqual(ids.map { $0.maxX - $0.minX }.max()!, 120.45)
    }
  }

  func testDataRowValuesAreRightAlignedAndRuled() throws {
    let layout = layout(try context())
    let strings = texts(layout)
    let value = try XCTUnwrap(strings.first { $0.text.string == "Oct 17, 2026 \u{B7} Test Operator" })
    XCTAssertEqual(value.text.anchor, .trailing)
    XCTAssertEqual(value.text.position.x, 1164)
    // Seven rules under the rows, 0.75 pt in the line colour.
    let rules = layout.items.filter {
      if case .shape(let shape) = $0, shape.fill == ChapterBrand.Sheet.line,
        let first = shape.path.points.first, first.x == 936
      {
        let ys = shape.path.points.map(\.y)
        return abs(ys.max()! - ys.min()! - 0.75) < 1e-9
      }
      return false
    }
    XCTAssertEqual(rules.count, 8, "seven rows and the footer")
  }

  func testLegendColumnsAndSwatches() throws {
    let layout = layout(try context())
    let strings = texts(layout)
    for (label, x) in [
      ("Wall, scanned", 967.0), ("Door, no swing", 967), ("Object, box", 967),
      ("Fixture symbol", 967), ("Window", 1075), ("Open passage", 1075), ("Low confidence", 1075),
      ("Habitable \u{B7} wet \u{B7} other", 1075),
    ] {
      let text = try XCTUnwrap(strings.first { $0.text.string == label }, label)
      XCTAssertEqual(text.text.position.x, x, label)
      XCTAssertLessThanOrEqual(text.maxX, 1164, label)
    }
    // The passage swatch is dashed 2 / 2, the low-confidence box 1.8 / 1.2.
    let dashes = layout.items.compactMap { item -> [Double]? in
      if case .shape(let shape) = item, let stroke = shape.stroke, !stroke.dash.isEmpty {
        return stroke.dash
      }
      return nil
    }
    XCTAssertTrue(dashes.contains([2, 2]))
    XCTAssertTrue(dashes.contains([1.8, 1.2]))
  }

  func testScaleAndNorthShareTheirRowBottomAligned() throws {
    for north in [verified, unread] {
      let layout = layout(try context(), north: north)
      let row = try XCTUnwrap(layout.block("G"))
      // The north block (40 pt): centred in its width, which ends at 1164; its caption's last
      // line box on the row's foot.
      let size = NorthArrow.blockSizeMM(symbol: north, boxMM: 40 * 25.4 / 72, caption: true)
      let captions = texts(layout).filter {
        $0.text.color == ChapterBrand.muted && $0.text.anchor == .center
          && abs($0.text.size - 7.5) < 1e-9 && $0.text.position.x > 1044
      }
      XCTAssertFalse(captions.isEmpty)
      for caption in captions {
        XCTAssertEqual(caption.text.position.x, 1164 - size.width * 72 / 25.4 / 2, accuracy: 1e-6)
      }
      // The lowest caption's line box ends on the row's foot.
      let lowest = try XCTUnwrap(captions.map(\.text.position.y).min())
      let lineBottom = lowest - (9.0 / 2 - 0.727 * 7.5 / 2)
      XCTAssertEqual(lineBottom, SheetItems.y(row.bottom), accuracy: 1e-6)
      // The scale block: its ratio line's box also ends on the foot.
      let ratio = try XCTUnwrap(texts(layout).first { $0.text.string == "1:50 at 11 x 17 in" })
      XCTAssertEqual(ratio.text.font, .courier)
      XCTAssertEqual(
        ratio.text.position.y - (9.0 / 2 - 0.562 * 7.5 / 2), SheetItems.y(row.bottom),
        accuracy: 1e-6)
    }
  }

  func testFootnoteWrapsAtFiveHundredSixtyPointsAndStacksUpFromTheBottom() throws {
    let lines = PlanSheetLayout.footnoteLines(tooBig: false, scaleDenominator: 50)
    XCTAssertEqual(lines.count, 2)
    for line in lines {
      XCTAssertLessThanOrEqual(FontMetrics.width(line, size: 7.5), 560)
    }
    let tooBig = PlanSheetLayout.footnoteLines(tooBig: true, scaleDenominator: 200)
    XCTAssertTrue(
      tooBig.joined(separator: " ").hasSuffix(
        "The plan is larger than this sheet at 1:200 and is cut at the frame. plan.dxf holds "
          + "the whole floor."))
    let layout = layout(try context())
    XCTAssertEqual(layout.footnoteTop, 736 - 18)
  }
}
