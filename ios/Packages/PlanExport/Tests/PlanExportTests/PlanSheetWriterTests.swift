import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// The plan sheet (plan-sheet §3, §13.1): page and frame, title block strings, fonts, logo,
/// rooms not scanned, document properties, and the sheets written for the visual checks (PS1,
/// PS2).
final class PlanSheetWriterTests: XCTestCase {
  static func context(_ capture: FixtureCapture) throws -> PlanExportContext {
    try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
  }

  static func sheet(_ capture: FixtureCapture) throws -> PlanSheetOutput {
    try PlanSheetWriter.write(model: capture.model, context: context(capture))
  }

  static func boxRoom() throws -> FixtureCapture {
    try XCTUnwrap(Fixtures.load("box-room").first)
  }

  /// The walk-through apartment with the box room's record, as one whole-floor capture.
  static func walkthrough() throws -> (model: CaptureModel, context: PlanExportContext) {
    let box = try boxRoom()
    var record = box.record
    let model = WalkthroughFixture.model
    record.captures[0].captureId = model.captureId
    record.captures[0].label = "Apartment"
    record.captures[0].areaKey = model.areaKey
    record.captures[0].mode = .floor
    return (model, try PlanExportContext(record: record, captureId: model.captureId))
  }

  /// Every string shown on a sheet.
  private func shown(_ output: PlanSheetOutput) -> [String] {
    PDFFile(output.file.data).shownText()
  }

  /// The text runs of a page with their font resource and size, from its content stream.
  private func runs(_ output: PlanSheetOutput) -> [(text: String, font: String, size: Double)] {
    let stream = PDFFile(output.file.data).contentStreams[0]
    return stream.split(separator: "\n").compactMap { line in
      guard line.hasPrefix("BT "), line.hasSuffix(") Tj ET"),
        let open = line.firstIndex(of: "(")
      else { return nil }
      let head = line[..<open].split(separator: " ")
      guard let tf = head.firstIndex(of: "Tf"), let size = Double(head[tf - 1]) else { return nil }
      let body = line[line.index(after: open)..<line.index(line.endIndex, offsetBy: -7)]
      return (PDFFile.unescape(String(body)), String(head[tf - 2]), size)
    }
  }

  // MARK: Page

  func testPageAndFrame() throws {
    let output = try Self.sheet(Self.boxRoom())
    let pdf = PDFFile(output.file.data)
    XCTAssertEqual(pdf.mediaBoxes, [[0, 0, 1224, 792]])
    XCTAssertEqual(pdf.contentStreams.count, 1)
    let marks = pdf.marks()
    // The page colour first, over the whole page.
    let page = try XCTUnwrap(marks.first)
    XCTAssertEqual(page.kind, .path(paint: "f", curves: 0))
    XCTAssertEqual(page.fill, "0.9804 0.9608 0.9333")
    XCTAssertEqual([page.minX, page.minY, page.maxX, page.maxY], [0, 0, 1224, 792])
    // The border: 0.75 pt muted, drawn inside the 36 pt margin.
    let border = marks[1]
    XCTAssertTrue(border.isStroked)
    XCTAssertEqual(border.stroke, "0.4196 0.3961 0.3412")
    XCTAssertEqual(border.lineWidth, 0.75)
    XCTAssertEqual(border.minX, 36, accuracy: 1e-6)
    XCTAssertEqual(border.minY, 36, accuracy: 1e-6)
    XCTAssertEqual(border.maxX, 1188, accuracy: 1e-6)
    XCTAssertEqual(border.maxY, 756, accuracy: 1e-6)
    // The rule between the drawing and the title block.
    let rule = marks[2]
    XCTAssertEqual(rule.fill, "0.4196 0.3961 0.3412")
    XCTAssertEqual([rule.minX, rule.maxX], [912, 912.75])
    XCTAssertEqual([rule.minY, rule.maxY], [36, 756])
  }

  func testTitleBlockStrings() throws {
    let output = try Self.sheet(Self.boxRoom())
    let shown = shown(output)
    let expected = [
      "SHEET 1 \u{B7} FLOOR 1", "Existing-condition", "plan", "Floor 1 \u{B7} Fixture box-room",
      "100 Example Street, Testville, NY 00000", "address confirmed on site", "HUB deal",
      "fixture-deal-0001", "Capture id", "22bfb513-226d-4eca-bde1-0b6cb0c84aad", "Captured",
      "Oct 17, 2026 \u{B7} Test Operator", "Device", "iPhone 16 Pro \u{B7} LiDAR \u{B7} app 1.0.0",
      "Mode", "One room", "Floor area, sum of rooms", "129.2 sq ft \u{B7} 12.0 m\u{B2}", "Rooms",
      "1 scanned", "Made on site, before the station checks", "LEGEND", "Wall, scanned", "Window",
      "Door, no swing", "Open passage", "Object, box", "Low confidence", "Fixture symbol",
      "Habitable \u{B7} wet \u{B7} other", "SCALE", "0", "2.5", "5 ft", "1:50 at 11 x 17 in",
      "Orientation: not verified", "No compass reading", "It's about time.", "hellochapter.com",
      "TEST ROOM", "129.2 sq ft",
    ]
    for text in expected { XCTAssertTrue(shown.contains(text), "\(text) in \(shown)") }
    XCTAssertFalse(shown.contains("NOT SCANNED"))
    // The statement, wrapped to five lines of the title block.
    let statement = shown.filter { PlanSheetLayout.statement.contains($0) && $0.count > 20 }
    XCTAssertEqual(statement.count, 5)
    XCTAssertEqual(statement.joined(separator: " "), PlanSheetLayout.statement)
    // The note card's body, three lines, and the production footnote, two.
    XCTAssertEqual(
      shown.filter { PlanSheetLayout.noteBody.contains($0) && $0.count > 10 }.joined(
        separator: " "), PlanSheetLayout.noteBody)
    XCTAssertEqual(output.layout.footnoteLines.count, 2)
    XCTAssertEqual(output.layout.footnoteLines.joined(separator: " "), PlanSheetLayout.footnote)
  }

  func testAddressAndProjectVariants() throws {
    var capture = try Self.boxRoom()
    // A short address with its confirmation on one line: the address is its own text run.
    capture.record.address.formatted = "1 Elm St, NY"
    var shown = shown(try Self.sheet(capture))
    XCTAssertTrue(shown.contains("1 Elm St, NY"))
    XCTAssertTrue(shown.contains(" \u{B7} address confirmed on site"))
    // Not confirmed on site.
    capture.record.address.confirmedOnSite = false
    shown = self.shown(try Self.sheet(capture))
    XCTAssertTrue(shown.contains(" \u{B7} address not confirmed on site"))
    // No project name: the address on line 1, the confirmation alone on line 2.
    capture.record.hub.projectName = nil
    shown = self.shown(try Self.sheet(capture))
    XCTAssertTrue(shown.contains("Floor 1 \u{B7} 1 Elm St, NY"), "\(shown)")
    XCTAssertTrue(shown.contains("Address not confirmed on site"))
  }

  func testNoPlaceholdersOrForbiddenGlyphs() throws {
    var outputs = try Fixtures.sheetCaptures().map(Self.sheet)
    let sample = try Fixtures.sample424()
    for variant in CompassVariant.allCases {
      let context = try PlanExportContext(
        record: variant.apply(to: sample.record), captureId: sample.model.captureId)
      outputs.append(try PlanSheetWriter.write(model: sample.model, context: context))
    }
    for output in outputs {
      for text in shown(output) {
        for forbidden in ["[", "]", "\u{2032}", "\u{2033}", "\u{2248}", "\u{25B2}", "\u{25CF}",
          "\u{25A0}", "ft\u{B2}", "Gross", "\u{2212}"]
        {
          XCTAssertFalse(text.contains(forbidden), "\(forbidden) in \(text)")
        }
      }
    }
  }

  func testFonts() throws {
    let output = try Self.sheet(Self.boxRoom())
    let pdf = PDFFile(output.file.data)
    XCTAssertEqual(
      Set(pdf.baseFonts),
      [
        "CHAPRA+Inter-Regular", "CHAPSB+Inter-SemiBold", "Times-Roman", "Times-Italic", "Courier",
      ])
    let runs = runs(output)
    func run(_ text: String) throws -> (text: String, font: String, size: Double) {
      try XCTUnwrap(runs.first { $0.text == text }, text)
    }
    XCTAssertEqual(try run("Existing-condition").font, "/F3")
    XCTAssertEqual(try run("Existing-condition").size, 25.5)
    XCTAssertEqual(try run("It's about time.").font, "/F5")
    XCTAssertEqual(try run("It's about time.").size, 11.25)
    // Ids, dimensions and the scale in Courier.
    XCTAssertEqual(try run("22bfb513-226d-4eca-bde1-0b6cb0c84aad").font, "/F4")
    XCTAssertEqual(try run("22bfb513-226d-4eca-bde1-0b6cb0c84aad").size, 7.5)
    XCTAssertEqual(try run("fixture-deal-0001").font, "/F4")
    XCTAssertEqual(try run("fixture-deal-0001").size, 9)
    XCTAssertEqual(try run("13' 1.5\"").font, "/F4")
    XCTAssertEqual(try run("13' 1.5\"").size, 8.25)
    XCTAssertEqual(try run("1:50 at 11 x 17 in").font, "/F4")
    // Room names Inter SemiBold 7.5, areas Inter 7.5; the rest Inter.
    XCTAssertEqual(try run("TEST ROOM").font, "/F2")
    XCTAssertEqual(try run("TEST ROOM").size, 7.5, accuracy: 1e-3)
    XCTAssertEqual(try run("129.2 sq ft").font, "/F1")
    XCTAssertEqual(try run("Made on site, before the station checks").font, "/F2")
    XCTAssertEqual(try run("HUB deal").font, "/F1")
  }

  func testLogoIsTheRealLogo() throws {
    let output = try Self.sheet(Self.boxRoom())
    // The logo's filled paths, 36 pt tall with its top-left corner at (936, 60).
    let logo = ChapterLogo.items(x: 936, y: 792 - 60 - 36, height: 36)
    XCTAssertEqual(logo.count, ChapterLogo.paths.count)
    let start = try XCTUnwrap(output.items.firstIndex(of: logo[0]))
    XCTAssertEqual(Array(output.items[start..<(start + logo.count)]), logo)
    XCTAssertEqual(ChapterLogo.width(height: 36), 99.56, accuracy: 0.01)
    // Never typed.
    let shown = shown(output)
    XCTAssertFalse(shown.contains { $0.lowercased() == "chapter" || $0 == "RENOVATION" })
  }

  func testNotScannedBlock() throws {
    var capture = try Self.boxRoom()
    capture.record.captures[0].omittedRooms = [.init(name: "Primary closet", reason: "locked")]
    capture.record.captures[0].inaccessibleRooms = [.init(name: "Storage room", reason: nil)]
    let output = try Self.sheet(capture)
    let shown = shown(output)
    for text in [
      "NOT SCANNED", "Primary closet \u{B7} locked", "Storage room \u{B7} could not enter",
      "Rooms not scanned have no geometry and are not drawn.", "1 scanned \u{B7} 2 not scanned",
    ] {
      XCTAssertTrue(shown.contains(text), "\(text) in \(shown)")
    }
    XCTAssertEqual(output.layout.block("E")?.height, 48)
    // An omitted room without a reason was skipped.
    capture.record.captures[0].omittedRooms = [.init(name: "Attic", reason: nil)]
    XCTAssertTrue(self.shown(try Self.sheet(capture)).contains("Attic \u{B7} skipped"))
  }

  func testRoomsAndAreaWithoutRooms() throws {
    // Walls only: no rooms recognized, no floor area, no labels and no room dimensions.
    var capture = try Self.boxRoom()
    capture.model.rooms = []
    capture.model.objects = []
    capture.record.captures[0].inaccessibleRooms = [.init(name: "Storage room", reason: nil)]
    let output = try Self.sheet(capture)
    let shown = shown(output)
    XCTAssertTrue(shown.contains("not captured"))
    XCTAssertTrue(shown.contains("none recognized \u{B7} 1 not scanned"))
    XCTAssertTrue(output.drawing.sheetDimensions.allSatisfy { $0.tier == 2 })
    XCTAssertFalse(
      output.drawing.items.contains {
        if case .text(let text) = $0 { return text.layer == .roomLabel }
        return false
      })
  }

  func testDocumentProperties() throws {
    let capture = try Self.boxRoom()
    let pdf = PDFFile(try Self.sheet(capture).file.data)
    XCTAssertTrue(pdf.text.contains("/Title (Existing-condition plan - Floor 1 - Fixture box-room)"))
    XCTAssertTrue(pdf.text.contains("/Author (Test Operator)"))
    XCTAssertTrue(
      pdf.text.contains(
        "/Subject (Plan sheet 1:50 at 11 x 17 in, capture 22bfb513-226d-4eca-bde1-0b6cb0c84aad)"))
    XCTAssertTrue(pdf.text.contains("/Creator (chapter-capture-ios/PlanExport 2.0.0)"))
    XCTAssertTrue(pdf.text.contains("/CreationDate (D:20261017140211Z)"))
  }

  func testByteStableAndBoundedInTime() throws {
    let sample = try Fixtures.sample424()
    let start = Date()
    let first = try Self.sheet(sample).file
    let elapsed = Date().timeIntervalSince(start)
    XCTAssertEqual(first, try Self.sheet(sample).file)
    // A debug build on a laptop; the release budget on an iPhone is 2 s for the walk-through.
    XCTAssertLessThan(elapsed, 20, "sample-424 sheet took \(elapsed) s")
  }

  func testMultiFloorVisitNumbersItsSheets() throws {
    let house = try Fixtures.load("two-floor-house")
    XCTAssertTrue(shown(try Self.sheet(house[0])).contains("SHEET 1 \u{B7} FLOOR 1"))
    XCTAssertTrue(shown(try Self.sheet(house[1])).contains("SHEET 2 \u{B7} FLOOR 2"))
  }

  /// Writes every sheet the snapshot goldens cover into .build/test-output: each fixture
  /// capture (ExportAllTests writes them too), the walk-through, and the 424 sample in each
  /// north state (`sample-424-{state}`); scripts/verify/plan-sheet-snapshot.sh renders them in
  /// colour and grey scale and compares them with their goldens (PS8).
  func testWritesTheSheetsOfTheSnapshotGoldens() throws {
    for capture in try Fixtures.all() {
      try Repo.write(Self.sheet(capture).file, folder: capture.outputFolder)
    }
    let walk = try Self.walkthrough()
    try Repo.write(
      PlanSheetWriter.write(model: walk.model, context: walk.context).file,
      folder: "walkthrough/apartment")
    let sample = try Fixtures.sample424()
    for variant in CompassVariant.allCases {
      let record = variant.apply(to: sample.record)
      let context = try PlanExportContext(record: record, captureId: sample.model.captureId)
      let output = try PlanSheetWriter.write(model: sample.model, context: context)
      try Repo.write(output.file, folder: "sample-424-\(variant.rawValue)/\(sample.truth.areaKey)")
      let shown = shown(output)
      switch variant {
      case .verified:
        XCTAssertTrue(shown.contains("True north \u{B7} compass"))
      case .approximate:
        XCTAssertTrue(shown.contains("\u{B1}12\u{B0} \u{B7} magnetic"))
      case .notVerified:
        XCTAssertTrue(shown.contains("No compass reading"))
      }
    }
  }
}
