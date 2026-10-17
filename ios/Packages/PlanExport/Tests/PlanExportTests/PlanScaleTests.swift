import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

final class PlanScaleTests: XCTestCase {
  private let points = 72.0 / 25.4

  private func planPDF(_ capture: FixtureCapture) throws -> (PlanPDFOutput, PDFFile) {
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    let output = try PlanPDFWriter.write(model: capture.model, context: context)
    try Repo.write(output.file, folder: capture.outputFolder)
    return (output, PDFFile(output.file.data))
  }

  /// Wall centrelines are the 0.5 mm strokes.
  private func wallSegments(_ pdf: PDFFile) -> [PDFFile.Segment] {
    pdf.segments().filter { abs($0.widthPoints - 0.5 * points) < 0.002 }
  }

  /// The scale bar baseline is the 0.4 mm stroke.
  private func scaleBar(_ pdf: PDFFile) -> [PDFFile.Segment] {
    pdf.segments().filter { abs($0.widthPoints - 0.4 * points) < 0.002 }
  }

  func testFourMetreWallMeasuresEightyMillimetresAtOneToFifty() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)  // 4.000 x 3.000 m
    let (output, pdf) = try planPDF(capture)
    XCTAssertEqual(output.scaleDenominator, 50)
    let lengths = wallSegments(pdf).map(\.lengthMM)
    XCTAssertEqual(lengths.count, 4)
    XCTAssertTrue(lengths.contains { abs($0 - 80.0) <= 0.2 }, "4.000 m wall: \(lengths)")
    XCTAssertTrue(lengths.contains { abs($0 - 60.0) <= 0.2 }, "3.000 m wall: \(lengths)")
  }

  func testScaleBarMatchesTheScale() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let (output, pdf) = try planPDF(capture)
    let bars = scaleBar(pdf)
    XCTAssertEqual(bars.count, 1)
    let bar = try XCTUnwrap(bars.first)
    // 2 m at 1:50 is 40 mm on paper.
    XCTAssertEqual(output.scaleBarMetres, 2)
    XCTAssertEqual(bar.lengthMM, output.scaleBarMetres * 1000 / Double(output.scaleDenominator), accuracy: 0.2)
    XCTAssertEqual(bar.lengthMM, 40, accuracy: 0.2)
    XCTAssertEqual(bar.y1, bar.y2, accuracy: 0.001, "scale bar is horizontal")
    // The title block says the scale in words too.
    XCTAssertTrue(pdf.shownText().contains("1:50"))
  }

  func testEveryFixtureWallIsDrawnToScale() throws {
    for capture in try Fixtures.all() {
      let (output, pdf) = try planPDF(capture)
      XCTAssertTrue([50, 100].contains(output.scaleDenominator))
      let drawn = wallSegments(pdf).map(\.lengthMM)
      for wall in capture.truth.walls {
        let expected = wall.lengthM * 1000 / Double(output.scaleDenominator)
        XCTAssertTrue(
          drawn.contains { abs($0 - expected) <= 0.2 },
          "\(capture.fixture) \(capture.truth.areaKey) \(wall.id): expected \(expected) mm in \(drawn)")
      }
    }
  }

  func testLargerPlanUsesOneToOneHundred() throws {
    let model = Synthetic.room(width: 20, length: 9)
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    let output = try PlanPDFWriter.write(model: model, context: context)
    XCTAssertEqual(output.scaleDenominator, 100)
    XCTAssertEqual(output.scaleBarMetres, 4)
    let pdf = PDFFile(output.file.data)
    let lengths = wallSegments(pdf).map(\.lengthMM)
    XCTAssertTrue(lengths.contains { abs($0 - 200.0) <= 0.2 }, "20 m wall at 1:100: \(lengths)")
    XCTAssertEqual(scaleBar(pdf).first?.lengthMM ?? 0, 40, accuracy: 0.2)
    // 20 m at 1:50 is 400 mm, which does not fit Letter or A3, so 1:100 on Letter.
    XCTAssertEqual(output.paper, "Letter")
    XCTAssertTrue(output.landscape)
  }

  func testSheetChoice() throws {
    func choose(_ width: Double, _ height: Double) throws -> PlanSheet {
      try PlanSheet.choose(bounds: PlanBounds(minX: 0, minY: 0, maxX: width, maxY: height))
    }
    // Letter first, and the orientation that matches the plan's shape.
    var sheet = try choose(4, 3)
    XCTAssertEqual(sheet.scaleDenominator, 50)
    XCTAssertEqual(sheet.paper, .letter)
    XCTAssertTrue(sheet.landscape)
    sheet = try choose(3, 4)
    XCTAssertEqual(sheet.scaleDenominator, 50)
    XCTAssertEqual(sheet.paper, .letter)
    XCTAssertFalse(sheet.landscape)
    sheet = try choose(8, 4)
    XCTAssertEqual(sheet.scaleDenominator, 50)
    XCTAssertEqual(sheet.paper, .letter)
    // 1:50 needs 272 x 192 mm with margins: too big for Letter, fits A3.
    sheet = try choose(12, 8)
    XCTAssertEqual(sheet.scaleDenominator, 50)
    XCTAssertEqual(sheet.paper, .a3)
    // 1:50 does not fit A3 either; 1:100 does.
    sheet = try choose(30, 15)
    XCTAssertEqual(sheet.scaleDenominator, 100)
    XCTAssertEqual(sheet.paper, .a3)
    // Beyond 1:100 the plan falls back to the next scales and says so in the title block.
    sheet = try choose(60, 30)
    XCTAssertEqual(sheet.scaleDenominator, 200)
    XCTAssertThrowsError(try choose(1000, 1000)) { error in
      XCTAssertEqual(error as? PlanExportError, .planTooLarge)
    }
  }

  func testScaleBarLengthIsFortyMillimetresAtEveryScale() {
    for scale in PlanSheet.scales {
      XCTAssertEqual(
        PlanScene.scaleBarMetres(scaleDenominator: scale) * 1000 / Double(scale), 40, accuracy: 1e-9)
    }
  }

  func testPageIsLetterOrA3InPoints() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let (_, pdf) = try planPDF(capture)
    let box = try XCTUnwrap(pdf.mediaBoxes.first)
    // The box room is wider than tall: Letter landscape.
    XCTAssertEqual(box[2], 279.4 * points, accuracy: 0.01)
    XCTAssertEqual(box[3], 215.9 * points, accuracy: 0.01)
  }

  func testPlanWithNothingToDrawThrows() throws {
    var model = Synthetic.room(width: 4, length: 3)
    model.rooms = []
    model.walls = []
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    XCTAssertThrowsError(try PlanPDFWriter.write(model: model, context: context)) { error in
      XCTAssertEqual(error as? PlanExportError, .noPlanGeometry)
    }
  }
}
