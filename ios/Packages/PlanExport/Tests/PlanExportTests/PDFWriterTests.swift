import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

final class PDFWriterTests: XCTestCase {
  private func both(_ capture: FixtureCapture) throws -> (plan: PDFFile, report: PDFFile) {
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    let plan = try PlanPDFWriter.write(model: capture.model, context: context).file
    let report = try SpatialReportWriter.write(model: capture.model, context: context)
    try Repo.write(plan, folder: capture.outputFolder)
    try Repo.write(report, folder: capture.outputFolder)
    XCTAssertEqual(plan.fileName, "plan.pdf")
    XCTAssertEqual(report.fileName, "spatial-report.pdf")
    XCTAssertEqual(plan.role, .planPDF)
    XCTAssertEqual(report.role, .spatialReportPDF)
    return (PDFFile(plan.data), PDFFile(report.data))
  }

  /// Checks header, trailer and that every xref entry points at its object.
  private func assertStructure(_ pdf: PDFFile, file: StaticString = #filePath, line: UInt = #line) throws {
    XCTAssertEqual(pdf.header, "%PDF-1.7", file: file, line: line)
    XCTAssertTrue(pdf.text.hasSuffix("%%EOF\n"), file: file, line: line)
    let text = pdf.text
    let startxrefRange = try XCTUnwrap(text.range(of: "startxref\n", options: .backwards))
    let offsetText = text[startxrefRange.upperBound...].prefix { $0.isNumber }
    let xrefOffset = try XCTUnwrap(Int(offsetText))
    let bytes = Array(pdf.data)
    XCTAssertEqual(String(decoding: bytes[xrefOffset..<(xrefOffset + 4)], as: UTF8.self), "xref")
    let table = String(decoding: bytes[xrefOffset...], as: UTF8.self).split(separator: "\n")
    let countLine = table[1].split(separator: " ")
    let count = try XCTUnwrap(Int(countLine[1]))
    XCTAssertEqual(table[2], "0000000000 65535 f ")
    for number in 1..<count {
      let entry = table[2 + number].split(separator: " ")
      let offset = try XCTUnwrap(Int(entry[0]))
      let prefix = "\(number) 0 obj"
      XCTAssertEqual(
        String(decoding: bytes[offset..<(offset + prefix.count)], as: UTF8.self), prefix,
        "xref entry \(number)", file: file, line: line)
    }
    // Stream lengths are right.
    var rest = Substring(text)
    while let lengthRange = rest.range(of: "/Length ") {
      let after = rest[lengthRange.upperBound...]
      let length = try XCTUnwrap(Int(after.prefix { $0.isNumber }))
      let streamStart = try XCTUnwrap(after.range(of: "stream\n")).upperBound
      let streamEnd = try XCTUnwrap(after[streamStart...].range(of: "endstream")).lowerBound
      XCTAssertEqual(after[streamStart..<streamEnd].count, length, file: file, line: line)
      rest = after[streamEnd...]
    }
  }

  func testBothPDFsAreValidPDF17WithAddressCaptureIdAndRoomLabels() throws {
    for capture in try Fixtures.all() {
      let (plan, report) = try both(capture)
      for (name, pdf) in [("plan", plan), ("report", report)] {
        try assertStructure(pdf)
        let shown = pdf.shownText()
        let joined = shown.joined(separator: "\n")
        let context = "\(capture.fixture) \(capture.truth.areaKey) \(name)"
        XCTAssertTrue(shown.contains(capture.record.address.formatted), "address in \(context)")
        XCTAssertTrue(shown.contains { $0.contains(capture.truth.captureId) }, "capture id in \(context)")
        for room in capture.truth.rooms {
          XCTAssertTrue(
            shown.contains { $0.contains(room.label) }, "room label \(room.label) in \(context)")
        }
        XCTAssertFalse(joined.isEmpty)
      }
    }
  }

  func testSpatialReportStatesItIsNotAPhotoSurvey() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let (_, report) = try both(capture)
    let shown = report.shownText().joined(separator: " ")
    XCTAssertTrue(shown.contains("not a photo survey"))
    XCTAssertTrue(shown.contains("not verified construction quantities"))
  }

  func testSpatialReportTableHasDimensionsAreaHeightOpeningsAndObjects() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let (_, report) = try both(capture)
    let shown = report.shownText()
    for expected in [
      "Room", "Width", "Length", "Height", "Floor area", "Doors", "Windows", "Openings",
      "Recognized objects",
      "5000 mm", "4000 mm", "2700 mm", "16' 4.85\"", "20.00 m\u{00B2}", "12.00 m\u{00B2}",
      "sofa", "bed", "Test Operator", "iPhone 16 Pro (iPhone17,1), iOS 26.0.1",
      "Total reported floor area: 32.00 m\u{00B2} (344.4 sq ft).",
    ] {
      XCTAssertTrue(
        shown.contains { $0.contains(expected) }, "report lacks \(expected)\n\(shown)")
    }
  }

  func testSpatialReportObjectFootprintHasOneLinePerUnit() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let (_, report) = try both(capture)
    let shown = report.shownText()
    // The sofa is 2000 mm wide and 900 mm deep, the bed 1600 mm by 2000 mm.
    for (metric, imperial) in [
      ("2000 x 900 mm", "6' 6.74\" x 2' 11.43\""), ("1600 x 2000 mm", "5' 2.99\" x 6' 6.74\""),
    ] {
      let line = try XCTUnwrap(shown.firstIndex(of: metric), "report lacks \(metric)\n\(shown)")
      XCTAssertEqual(shown[line + 1], imperial)
    }
    // Not the two dimension cells joined, which mixed the units on one line.
    XCTAssertFalse(shown.contains("6' 6.74\" x 900 mm"))
  }

  func testPlanTitleBlockFields() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let (plan, _) = try both(capture)
    let shown = plan.shownText()
    XCTAssertTrue(shown.contains("Floor plan - Floor 1"))
    XCTAssertTrue(shown.contains(capture.record.address.formatted))
    XCTAssertTrue(shown.contains("Fixture box-room (deal fixture-deal-0001)"))
    XCTAssertTrue(shown.contains("Floor 1"))
    XCTAssertTrue(shown.contains(capture.truth.captureId))
    XCTAssertTrue(shown.contains("2026-10-17"))
    XCTAssertTrue(shown.contains("Test Operator"))
    XCTAssertTrue(shown.contains { $0.contains("True north was not captured") || $0.contains("True north") })
  }

  func testObjectsAndDimensionStringsAreTextOnThePlan() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let (plan, _) = try both(capture)
    let shown = plan.shownText()
    XCTAssertTrue(shown.contains("4000 mm"))
    XCTAssertTrue(shown.contains("3000 mm"))
    XCTAssertTrue(shown.contains("table"))
  }

  func testImperialDisplayUsesFeetInchesDimensions() throws {
    var capture = try XCTUnwrap(Fixtures.load("box-room").first)
    capture.record.captures[0].units.display = .imperial
    let (plan, _) = try both(capture)
    XCTAssertTrue(plan.shownText().contains("13' 1.48\""))
  }

  func testLongReportContinuesOnNewPagesWithRepeatedHeaderAndFooters() throws {
    var model = Synthetic.room(width: 4, length: 3)
    model.rooms = (1...60).map { index in
      CaptureModel.Room(
        id: "room-\(index)", label: "Room number \(index)",
        polygon: model.rooms[0].polygon, heightM: 2.5)
    }
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    let file = try SpatialReportWriter.write(model: model, context: context)
    let pdf = PDFFile(file.data)
    try assertStructure(pdf)
    let pageCount = pdf.contentStreams.count
    XCTAssertGreaterThan(pageCount, 2)
    for page in 0..<pageCount {
      let shown = pdf.shownText(page: page)
      XCTAssertTrue(shown.contains { $0.contains("page \(page + 1) of \(pageCount)") })
      XCTAssertTrue(shown.contains { $0.contains(capture.truth.captureId) })
      // 60 rooms span at least three pages: the table header repeats on the second.
      if page == 1 { XCTAssertTrue(shown.contains("Floor area"), "table header repeats") }
    }
    let all = pdf.shownText().joined(separator: "\n")
    XCTAssertTrue(all.contains("Room number 60"))
  }

  func testTextEncodingEscapesAndWinAnsi() {
    XCTAssertEqual(String(decoding: PDFPage.encode("a(b)c\\d"), as: UTF8.self), "a\\(b\\)c\\\\d")
    XCTAssertEqual(String(decoding: PDFPage.encode("Caf\u{00E9}"), as: UTF8.self), "Caf\\351")
    XCTAssertEqual(String(decoding: PDFPage.encode("\u{2013}\u{20AC}"), as: UTF8.self), "\\226\\200")
    XCTAssertEqual(String(decoding: PDFPage.encode("\u{4E2D}"), as: UTF8.self), "?")
    XCTAssertEqual(PDFFile.unescape("Caf\\351"), "Caf\u{00E9}")
  }

  func testHelveticaWidths() {
    // From the Adobe Helvetica AFM: "Hello" = 722 + 556 + 222 + 222 + 556.
    XCTAssertEqual(FontMetrics.width("Hello", size: 1000), 2278, accuracy: 0.001)
    XCTAssertEqual(FontMetrics.width("Hello", size: 10), 22.78, accuracy: 0.001)
  }

  func testLongAddressIsShrunkOrCutToFit() {
    let long = String(repeating: "Very Long Street Name ", count: 12)
    let cut = PlanPDFWriter.fitted(long, size: 5, width: 200)
    XCTAssertTrue(cut.hasSuffix("..."))
    XCTAssertLessThanOrEqual(FontMetrics.width(cut, size: 5), 200)
  }

  func testWrapBreaksLongWords() {
    let lines = PlanPDFWriter.wrap(String(repeating: "W", count: 100), size: 8, width: 100)
    XCTAssertGreaterThan(lines.count, 1)
    XCTAssertEqual(lines.joined().count, 100)
    for line in lines { XCTAssertLessThanOrEqual(FontMetrics.width(line, size: 8), 100) }
  }

  func testCaptureMissingFromRecordThrows() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-floor-house").first)
    var record = capture.record
    record.captures.removeAll()
    XCTAssertThrowsError(
      try PlanExportContext(record: record, captureId: capture.model.captureId)
    ) { error in
      XCTAssertEqual(
        error as? PlanExportError,
        .captureNotInRecord(captureId: capture.model.captureId.rawValue))
    }
  }
}
