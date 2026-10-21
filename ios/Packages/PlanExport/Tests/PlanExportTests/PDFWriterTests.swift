import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

final class PDFWriterTests: XCTestCase {
  /// The plan sheet of a capture, as exportAll writes it (`plan-sheet.pdf`, role `plan_pdf`).
  private func plan(_ capture: FixtureCapture) throws -> PDFFile {
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    let plan = try PlanPDFWriter.write(model: capture.model, context: context).file
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
    for capture in try Fixtures.all() {
      let pdf = try plan(capture)
      try assertStructure(pdf)
      XCTAssertEqual(pdf.contentStreams.count, 1, "one page")
      let shown = pdf.shownText()
      let context = "\(capture.fixture) \(capture.truth.areaKey)"
      XCTAssertTrue(shown.contains(capture.record.address.formatted), "address in \(context)")
      XCTAssertTrue(
        shown.contains { $0.contains(capture.truth.captureId) }, "capture id in \(context)")
      for room in capture.truth.rooms {
        XCTAssertTrue(
          shown.contains { $0.contains(room.label) }, "room label \(room.label) in \(context)")
      }
    }
  }

  func testPlanTitleBlockFields() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let shown = try plan(capture).shownText()
    XCTAssertTrue(shown.contains("Floor plan - Floor 1"))
    XCTAssertTrue(shown.contains(capture.record.address.formatted))
    XCTAssertTrue(shown.contains("Fixture box-room (deal fixture-deal-0001)"))
    XCTAssertTrue(shown.contains("Floor 1"))
    XCTAssertTrue(shown.contains(capture.truth.captureId))
    XCTAssertTrue(shown.contains("2026-10-17"))
    XCTAssertTrue(shown.contains("Test Operator"))
  }

  func testPlanSheetShowsTheCompassStateOfItsCapture() throws {
    // box-room: a 1.0.0 record, no reading. two-floor-house: Floor 1 verified 212.4 ±8 true,
    // Floor 2 no reading. two-room-apartment: magnetic ±12, approximate.
    let unread = ["Orientation: not verified", "No compass reading"]
    let verified = ["N", "True north \u{00B7} compass", "\u{00B1}8\u{00B0} \u{00B7} 212\u{00B0}"]
    let approximate = [
      "N", "Approx. north \u{00B7} compass", "\u{00B1}12\u{00B0} \u{00B7} magnetic",
    ]
    let cases: [(fixture: String, floor: Int, texts: [String])] = [
      ("box-room", 0, unread), ("two-floor-house", 0, verified), ("two-floor-house", 1, unread),
      ("two-room-apartment", 0, approximate),
    ]
    for (fixture, floor, texts) in cases {
      let capture = try Fixtures.load(fixture)[floor]
      let shown = try plan(capture).shownText()
      for text in texts { XCTAssertTrue(shown.contains(text), "\(fixture) \(floor): \(text)") }
      // The old note and its "UP" arrow are gone: the symbol says what is known.
      XCTAssertFalse(shown.contains { $0.contains("True north was not captured") }, fixture)
      XCTAssertFalse(shown.contains("UP"), fixture)
      XCTAssertFalse(shown.contains("ORIENTATION"), fixture)
    }
  }

  func testPlanSheetNorthSymbolSitsInTheRightPanelUnderTheScaleBar() throws {
    // Everything is read from the PDF as written: the title block (its frame, the one `re`),
    // its right panel (from the frame's one full-height divider to the frame's right edge),
    // the scale bar (the horizontal rules inside that panel; its baseline is the lowest) and
    // the north symbol (its strings, and the stroked paths drawn just before them: ring and
    // arrow, or the box's border). Every fixture plan and two synthetic ones (a long room on
    // Letter portrait, the narrowest panel, and a plan too large for Letter), in each state.
    let base = try XCTUnwrap(Fixtures.load("box-room").first)
    let models =
      try Fixtures.all().map(\.model)
      + [Synthetic.room(width: 3, length: 9), Synthetic.room(width: 60, length: 40)]
    let states: [CompassState] = [
      .verified(heading: 212.4, accuracy: 8),
      .approximate(heading: 87.5, accuracy: 12, source: .magnetic),
      .notVerified(.inaccurate, accuracy: 42), .notVerified(.noReading, accuracy: nil),
    ]
    var sheets = Set<String>()
    for (index, model) in models.enumerated() {
      for state in states {
        var context = try PlanExportContext(record: base.record, captureId: base.model.captureId)
        context.compass = state
        let output = try PlanPDFWriter.write(model: model, context: context)
        let sheet = "\(output.paper) \(output.landscape ? "landscape" : "portrait")"
        sheets.insert(sheet)
        let name = "plan \(index), \(sheet), \(state)"
        let pdf = PDFFile(output.file.data)
        let marks = pdf.marks()

        let frame = try XCTUnwrap(marks.first { $0.operators == ["re"] && $0.isStroked }, name)
        let inner = (
          minX: frame.minX + frame.lineWidth, minY: frame.minY + frame.lineWidth,
          maxX: frame.maxX - frame.lineWidth, maxY: frame.maxY - frame.lineWidth
        )
        let segments = pdf.segments()
        let divider = try XCTUnwrap(
          segments.first {
            abs($0.x1 - $0.x2) < 1e-6 && $0.x1 > inner.minX && $0.x1 < inner.maxX
              && abs(abs($0.y2 - $0.y1) - (frame.maxY - frame.minY - frame.lineWidth)) < 0.01
          }, name)
        let panel = (left: divider.x1 + divider.widthPoints / 2, right: inner.maxX)
        let rules = segments.filter {
          abs($0.y1 - $0.y2) < 1e-6 && min($0.x1, $0.x2) > panel.left
            && max($0.x1, $0.x2) < panel.right && $0.y1 > inner.minY && $0.y1 < inner.maxY
        }
        let baseline = try XCTUnwrap(rules.min { $0.y1 < $1.y1 }, "scale bar: \(name)")
        let barBottom = baseline.y1 - baseline.widthPoints / 2

        // The symbol's marks.
        let symbol: [PDFFile.Mark]
        switch NorthSymbol(state: state) {
        case .arrow(_, _, let line1, let line2):
          let start = try XCTUnwrap(
            marks.indices.first {
              $0 >= 2 && $0 + 2 < marks.count && marks[$0].string == "N"
                && marks[$0 + 1].string == line1 && marks[$0 + 2].string == line2
            }, name)
          symbol = Array(marks[(start - 2)...(start + 2)])
          XCTAssertEqual(symbol[0].kind, .path(paint: "S", curves: 4), "ring: \(name)")
          XCTAssertEqual(symbol[1].kind, .path(paint: "B", curves: 0), "arrow: \(name)")
        case .notVerified(let box, let reason):
          let start = try XCTUnwrap(
            marks.indices.first {
              $0 >= 1 && $0 + 1 < marks.count && marks[$0].string == box
                && marks[$0 + 1].string == reason
            }, name)
          symbol = Array(marks[(start - 1)...(start + 1)])
          XCTAssertEqual(symbol[0].kind, .path(paint: "S", curves: 4), "border: \(name)")
        }
        let extent = (
          minX: symbol.map(\.minX).min()!, minY: symbol.map(\.minY).min()!,
          maxX: symbol.map(\.maxX).max()!, maxY: symbol.map(\.maxY).max()!
        )
        // Inside the panel, above the frame's bottom edge and under the scale bar.
        XCTAssertGreaterThan(extent.minX, panel.left, name)
        XCTAssertLessThan(extent.maxX, panel.right, name)
        XCTAssertGreaterThan(extent.minY, inner.minY, name)
        XCTAssertLessThan(extent.maxY, barBottom, name)
      }
    }
    XCTAssertTrue(sheets.contains("Letter portrait"), "\(sheets)")
    XCTAssertGreaterThan(sheets.count, 2, "\(sheets)")
  }

  func testObjectsAndDimensionStringsAreTextOnThePlan() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let shown = try plan(capture).shownText()
    XCTAssertTrue(shown.contains("4000 mm"))
    XCTAssertTrue(shown.contains("3000 mm"))
    XCTAssertTrue(shown.contains("table"))
  }

  func testImperialDisplayUsesFeetInchesDimensions() throws {
    var capture = try XCTUnwrap(Fixtures.load("box-room").first)
    capture.record.captures[0].units.display = .imperial
    XCTAssertTrue(try plan(capture).shownText().contains("13' 1.48\""))
  }

  func testTextEncodingEscapesAndWinAnsi() {
    XCTAssertEqual(String(decoding: PDFPage.encode("a(b)c\\d"), as: UTF8.self), "a\\(b\\)c\\\\d")
    XCTAssertEqual(String(decoding: PDFPage.encode("Caf\u{00E9}"), as: UTF8.self), "Caf\\351")
    XCTAssertEqual(String(decoding: PDFPage.encode("\u{2013}\u{20AC}"), as: UTF8.self), "\\226\\200")
    XCTAssertEqual(String(decoding: PDFPage.encode("\u{4E2D}"), as: UTF8.self), "?")
    XCTAssertEqual(PDFFile.unescape("Caf\\351"), "Caf\u{00E9}")
  }

  func testInterWidths() {
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
  }

  func testPDFsEmbedInterAndDeclareOnlyTheFontsTheyUse() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let pdf = try plan(capture)
    let fonts = pdf.baseFonts
    XCTAssertFalse(fonts.contains { $0.hasPrefix("Helvetica") })
    XCTAssertTrue(fonts.contains("CHAPRA+Inter-Regular"), "\(fonts)")
    XCTAssertTrue(fonts.contains("Times-Roman"), "title in Times: \(fonts)")
    // Each embedded Inter has a TrueType program, compressed, with its uncompressed length.
    XCTAssertEqual(
      pdf.text.components(separatedBy: "/FontFile2 ").count - 1,
      fonts.filter { $0.contains("+Inter-") }.count)
    XCTAssertTrue(pdf.text.contains("/Length1 \(ChapterBrandAssets.interRegular.data.count)"))
    // The program is a TrueType font (version 1.0 header) once inflated.
    let font = ChapterBrandAssets.interRegular.data
    XCTAssertEqual(Array(font.prefix(4)), [0, 1, 0, 0])
    XCTAssertEqual(ChapterBrandAssets.interRegular.widths.count, 224)
    XCTAssertEqual(ChapterBrandAssets.interSemiBold.widths.count, 224)
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

  func testContextCarriesTheCompassStateOfItsCapture() throws {
    func compass(_ fixture: String, _ floor: Int) throws -> CompassState {
      let capture = try Fixtures.load(fixture)[floor]
      return try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
        .compass
    }
    XCTAssertEqual(try compass("box-room", 0), .notVerified(.noReading, accuracy: nil))
    XCTAssertEqual(try compass("two-floor-house", 0), .verified(heading: 212.4, accuracy: 8))
    XCTAssertEqual(try compass("two-floor-house", 1), .notVerified(.noReading, accuracy: nil))
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
}
