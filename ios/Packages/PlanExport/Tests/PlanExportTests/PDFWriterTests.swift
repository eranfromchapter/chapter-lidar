import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// PDF structure, text encoding, fonts and the compass state of every plan sheet (PS1, PS2).
final class PDFWriterTests: XCTestCase {
  /// The plan sheet of a capture, as exportAll writes it (`plan-sheet.pdf`, role `plan_pdf`).
  private func plan(_ capture: FixtureCapture) throws -> PDFFile {
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    let plan = try PlanSheetWriter.write(model: capture.model, context: context).file
    try Repo.write(plan, folder: capture.outputFolder)
    XCTAssertEqual(plan.fileName, "plan-sheet.pdf")
    XCTAssertEqual(plan.role, .planPDF)
    return PDFFile(plan.data)
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
      // The data, then at most one end-of-line before `endstream`.
      let body = after[streamStart..<streamEnd]
      XCTAssertTrue(
        body.count == length || (body.count == length + 1 && body.hasSuffix("\n")),
        "stream of \(body.count) bytes declares /Length \(length)", file: file, line: line)
      rest = after[streamEnd...]
    }
  }

  func testPlanSheetIsValidPDF17WithAddressCaptureIdAndRoomLabels() throws {
    // PS1, PS2: one Tabloid page per capture, the address, the capture id and every room
    // label in capitals as extractable text.
    for capture in try Fixtures.sheetCaptures() {
      let pdf = try plan(capture)
      try assertStructure(pdf)
      XCTAssertEqual(pdf.contentStreams.count, 1, "one page")
      XCTAssertEqual(pdf.mediaBoxes, [[0, 0, 1224, 792]])
      let shown = pdf.shownText()
      let context = "\(capture.fixture) \(capture.truth.areaKey)"
      XCTAssertTrue(shown.contains(capture.record.address.formatted), "address in \(context)")
      XCTAssertTrue(shown.contains(capture.truth.captureId), "capture id in \(context)")
      for room in capture.truth.rooms {
        let caps = room.label.uppercased(with: Locale(identifier: "en_US_POSIX"))
        XCTAssertTrue(shown.contains(caps), "room label \(caps) in \(context): \(shown)")
      }
    }
  }

  func testPlanSheetShowsTheCompassStateOfItsCapture() throws {
    // box-room: a 1.0.0 record, no reading. two-floor-house: Floor 1 verified 212.4 ±8 true,
    // Floor 2 no reading, the compass was not calibrated. two-room-apartment: magnetic ±12,
    // approximate. The verified caption prints the bearing of sheet-up: the heading less the
    // drawing's turn.
    let unread = ["Orientation: not verified", "No compass reading"]
    let notCalibrated = ["Orientation: not verified", "Compass not calibrated"]
    let approximate = [
      "N", "Approx. north \u{00B7} compass", "\u{00B1}12\u{00B0} \u{00B7} magnetic",
    ]
    let cases: [(fixture: String, floor: Int, texts: [String]?)] = [
      ("box-room", 0, unread), ("two-floor-house", 0, nil), ("two-floor-house", 1, notCalibrated),
      ("two-room-apartment", 0, approximate),
    ]
    for (fixture, floor, texts) in cases {
      let capture = try Fixtures.load(fixture)[floor]
      let context = try PlanExportContext(
        record: capture.record, captureId: capture.model.captureId)
      let output = try PlanSheetWriter.write(model: capture.model, context: context)
      let shown = PDFFile(output.file.data).shownText()
      let expected =
        texts ?? [
          "N", "True north \u{00B7} compass",
          "\u{00B1}8\u{00B0} \u{00B7} "
            + "\(CompassMath.wholeDegrees(212.4 - output.drawingRotationDegrees))\u{00B0}",
        ]
      for text in expected { XCTAssertTrue(shown.contains(text), "\(fixture) \(floor): \(text)") }
      XCTAssertFalse(shown.contains { $0.contains("True north was not captured") }, fixture)
    }
  }

  func testTextEncodingEscapesAndWinAnsi() {
    XCTAssertEqual(String(decoding: PDFPage.encode("a(b)c\\d"), as: UTF8.self), "a\\(b\\)c\\\\d")
    XCTAssertEqual(String(decoding: PDFPage.encode("Caf\u{00E9}"), as: UTF8.self), "Caf\\351")
    XCTAssertEqual(String(decoding: PDFPage.encode("\u{2013}\u{20AC}"), as: UTF8.self), "\\226\\200")
    XCTAssertEqual(String(decoding: PDFPage.encode("\u{4E2D}"), as: UTF8.self), "?")
    XCTAssertEqual(PDFFile.unescape("Caf\\351"), "Caf\u{00E9}")
  }

  func testFontWidths() {
    // Inter Regular advances (1/1000 em): "Hello" = 740 + 582 + 237 + 237 + 597.
    XCTAssertEqual(FontMetrics.width("Hello", size: 1000), 2393, accuracy: 0.001)
    XCTAssertEqual(FontMetrics.width("Hello", size: 10), 23.93, accuracy: 0.001)
    // SemiBold is wider; a character WinAnsi lacks counts as the "?" that replaces it.
    XCTAssertGreaterThan(
      FontMetrics.width("Hello", size: 10, bold: true), FontMetrics.width("Hello", size: 10))
    XCTAssertEqual(
      FontMetrics.width("\u{4E2D}", size: 10), FontMetrics.width("?", size: 10), accuracy: 1e-9)
    // Times-Roman for titles: "Hello" = 722 + 444 + 278 + 278 + 500.
    XCTAssertEqual(FontMetrics.width("Hello", size: 1000, serif: true), 2222, accuracy: 0.001)
    // Times-Italic (Adobe Core 14): "It's" = 333 + 278 + 214 + 389.
    XCTAssertEqual(FontMetrics.width("It's", size: 1000, font: .timesItalic), 1214, accuracy: 0.001)
    // Courier: 600 for every glyph; the 36 characters of a capture id at 7.5 pt are 162 pt.
    XCTAssertEqual(
      FontMetrics.width("22bfb513-226d-4eca-bde1-0b6cb0c84aad", size: 7.5, font: .courier), 162,
      accuracy: 1e-9)
    // The plan sheet's title is wider than the title block, so it wraps after "condition".
    XCTAssertGreaterThan(
      FontMetrics.width("Existing-condition plan", size: 25.5, font: .timesRoman), 228)
  }

  func testPDFsEmbedInterAndDeclareOnlyTheFontsTheyUse() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let pdf = try plan(capture)
    let fonts = pdf.baseFonts
    XCTAssertFalse(fonts.contains { $0.hasPrefix("Helvetica") })
    XCTAssertEqual(
      Set(fonts),
      [
        "CHAPRA+Inter-Regular", "CHAPSB+Inter-SemiBold", "Times-Roman", "Times-Italic", "Courier",
      ])
    // Each embedded Inter has a TrueType program, compressed, with its uncompressed length.
    XCTAssertEqual(
      pdf.text.components(separatedBy: "/FontFile2 ").count - 1,
      fonts.filter { $0.contains("+Inter-") }.count)
    XCTAssertTrue(pdf.text.contains("/Length1 \(ChapterBrandAssets.interRegular.data.count)"))
    // The standard fonts are declared with WinAnsi, never embedded.
    XCTAssertTrue(
      pdf.text.contains("/Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding"))
    XCTAssertTrue(
      pdf.text.contains("/Subtype /Type1 /BaseFont /Times-Italic /Encoding /WinAnsiEncoding"))
    // The program is a TrueType font (version 1.0 header) once inflated.
    let font = ChapterBrandAssets.interRegular.data
    XCTAssertEqual(Array(font.prefix(4)), [0, 1, 0, 0])
    XCTAssertEqual(ChapterBrandAssets.interRegular.widths.count, 224)
    XCTAssertEqual(ChapterBrandAssets.interSemiBold.widths.count, 224)
    // A page that uses no Courier or Times-Italic declares neither (the colour Floorplan).
    let floorplan = PDFFile(try FloorplanWriter.pdf(model: capture.model))
    XCTAssertFalse(floorplan.baseFonts.contains("Courier"))
    XCTAssertFalse(floorplan.baseFonts.contains("Times-Italic"))
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

  func testContextCarriesTheCompassStateOfItsCapture() throws {
    func compass(_ fixture: String, _ floor: Int) throws -> CompassState {
      let capture = try Fixtures.load(fixture)[floor]
      return try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
        .compass
    }
    XCTAssertEqual(try compass("box-room", 0), .notVerified(.noReading, accuracy: nil))
    XCTAssertEqual(try compass("two-floor-house", 0), .verified(heading: 212.4, accuracy: 8))
    XCTAssertEqual(try compass("two-floor-house", 1), .notVerified(.notCalibrated, accuracy: nil))
    XCTAssertEqual(
      try compass("two-room-apartment", 0),
      .approximate(heading: 87.5, accuracy: 12, source: .magnetic))
    // The state is the contract's evaluator on the record's capture.
    var capture = try Fixtures.load("two-floor-house")[0]
    capture.record.captures[0].headingAccuracy = 31
    XCTAssertEqual(
      try PlanExportContext(record: capture.record, captureId: capture.model.captureId).compass,
      .notVerified(.inaccurate, accuracy: 31))
  }

  func testContextCarriesTheSheetNumberDeviceAndPrintedDate() throws {
    let house = try Fixtures.load("two-floor-house")
    let second = try PlanExportContext(
      record: house[1].record, captureId: house[1].model.captureId)
    XCTAssertEqual(second.sheetNumber, 2)
    XCTAssertEqual(second.deviceName, "iPhone 16 Pro")
    XCTAssertTrue(second.hasLidar)
    XCTAssertEqual(second.appShortVersion, "1.0.0")
    // Printed dates are the America/New_York day (critique R-34): 01:30 UTC on Oct 18 is
    // Oct 17 in New York.
    XCTAssertEqual(PrintDate.text(UTCTimestamp(rawValue: "2026-10-18T01:30:00Z")!), "Oct 17, 2026")
    XCTAssertEqual(PrintDate.text(UTCTimestamp(rawValue: "2025-01-25T15:00:00Z")!), "Jan 25, 2025")
    XCTAssertEqual(PrintDate.text(UTCTimestamp(rawValue: "2026-03-01T04:59:59Z")!), "Feb 28, 2026")
    XCTAssertEqual(PrintDate.text(UTCTimestamp(rawValue: "2026-07-04T04:00:00Z")!), "Jul 4, 2026")
  }
}
