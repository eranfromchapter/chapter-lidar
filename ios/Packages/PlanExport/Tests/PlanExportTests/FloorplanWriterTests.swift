import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

#if canImport(FoundationXML)
  import FoundationXML
#endif

final class FloorplanWriterTests: XCTestCase {
  private let address = "1 Test Street, Springfield"

  private func write(
    _ model: CaptureModel, _ configure: (inout FloorplanWriter.Options) -> Void = { _ in }
  ) throws -> FloorplanWriter.Floorplan {
    var options = FloorplanWriter.Options(address: address)
    configure(&options)
    return try FloorplanWriter.write(model: model, options: options)
  }

  private func sheet(
    _ model: CaptureModel, _ configure: (inout FloorplanWriter.Options) -> Void = { _ in }
  ) throws -> FloorplanWriter.Sheet {
    var options = FloorplanWriter.Options(address: address)
    configure(&options)
    return try FloorplanWriter.Sheet(model: model, options: options)
  }

  private func layers(_ sheet: FloorplanWriter.Sheet) -> Set<DrawingLayer> {
    func collect(_ items: [DrawingItem]) -> [DrawingLayer] {
      items.flatMap { item -> [DrawingLayer] in
        switch item {
        case .shape(let shape): return [shape.layer]
        case .text(let text): return [text.layer]
        case .clipped(_, let children): return collect(children)
        }
      }
    }
    return Set(collect(sheet.items))
  }

  // MARK: The page

  func testWalkThroughIsOnePageWithTitleAddressTotalAndEveryRoom() throws {
    let model = WalkthroughFixture.model
    let plan = try write(model) { $0.northDegrees = 0 }
    try Repo.write(
      ExportedFile(
        fileName: "floorplan.pdf", role: .planPDF, mime: "application/pdf", data: plan.pdf),
      folder: "apartment-walkthrough")
    try Repo.write(
      ExportedFile(
        fileName: "floorplan.svg", role: .planSVG, mime: "image/svg+xml",
        data: Data(plan.svg.utf8)), folder: "apartment-walkthrough")

    let pdf = PDFFile(plan.pdf)
    XCTAssertEqual(pdf.header, "%PDF-1.7")
    XCTAssertTrue(pdf.text.hasSuffix("%%EOF\n"))
    XCTAssertEqual(pdf.mediaBoxes.count, 1, "one page")
    XCTAssertTrue(pdf.text.contains("/Count 1 "))
    XCTAssertEqual(pdf.contentStreams.count, 1)
    let shown = pdf.shownText()
    for expected in ["Floorplan", address, plan.totalText, "chapter", "RENOVATION", "N"] {
      XCTAssertTrue(shown.contains(expected), expected)
    }
    XCTAssertTrue(plan.totalText.hasPrefix("Approximately "))
    XCTAssertTrue(plan.totalText.hasSuffix(" ft\u{00B2} total"))
    // Every room by name, with its area.
    XCTAssertEqual(model.rooms.count, 7)
    let units = UnitFormatter(system: .imperial)
    for room in model.rooms {
      XCTAssertTrue(shown.contains(room.label), room.label)
    }
    let drawing = try FloorplanWriter.Sheet(
      model: model, options: .init(address: address, northDegrees: 0)
    ).drawing
    for room in drawing.rooms {
      XCTAssertTrue(shown.contains(units.roomArea(room.areaM2)), "area of \(room.label)")
    }
    // Feet-inch dimensions, the scale bar and the note.
    XCTAssertGreaterThan(shown.filter { $0.contains("' ") && $0.hasSuffix("\"") }.count, 20)
    XCTAssertTrue(shown.contains { $0.hasSuffix(" ft") && $0.count <= 6 }, "scale bar")
    XCTAssertTrue(shown.contains("Measurements are approximate."))
    XCTAssertFalse(shown.contains { $0.contains("1:") }, "no print scale in words")
    // Colour: slate walls, ink outside dimensions, purple inside dimensions.
    let stream = try XCTUnwrap(pdf.contentStreams.first)
    XCTAssertTrue(stream.contains("0.3600 0.3700 0.4200 rg"), "slate walls")
    XCTAssertTrue(stream.contains("0.5412 0.5098 0.9020 RG"), "purple inside dimensions")
    XCTAssertTrue(stream.contains("1.0000 1.0000 1.0000 rg"), "white paper")
  }

  func testTotalIsTheExteriorEstimateRoundedForAHeadline() throws {
    let model = WalkthroughFixture.model
    let totals = try PlanTotals(model)
    let plan = try write(model)
    XCTAssertEqual(plan.totalAreaM2, totals.exteriorAreaEstimateM2, accuracy: 1e-9)
    XCTAssertGreaterThan(plan.totalAreaM2, totals.livableAreaM2)
    let feet = Int(
      (totals.exteriorAreaEstimateM2 / UnitFormatter.squareMetresPerSquareFoot)
        .rounded())
    XCTAssertEqual(plan.totalText, "Approximately \(feet) ft\u{00B2} total")
    let metric = try write(model) { $0.units = UnitFormatter(system: .metric) }
    let metres = UnitFormatter.decimals(totals.exteriorAreaEstimateM2, places: 1)!
    XCTAssertEqual(metric.totalText, "Approximately \(metres) m\u{00B2} total")
    // The total follows the assumed exterior wall thickness.
    let room = Synthetic.room(width: 4, length: 3)
    let thick = try write(room)
    let thin = try write(room) { $0.exteriorWallThicknessM = 0.05 }
    XCTAssertEqual(thick.totalAreaM2, (4 + 2 * 0.1524) * (3 + 2 * 0.1524), accuracy: 0.02)
    XCTAssertEqual(thin.totalAreaM2, 4.1 * 3.1, accuracy: 0.02)
  }

  func testApproximateAreaFormat() {
    let imperial = UnitFormatter(system: .imperial)
    let metric = UnitFormatter(system: .metric)
    XCTAssertEqual(imperial.approximateArea(859.4 * 0.092_903_04), "859 ft\u{00B2}")
    XCTAssertEqual(imperial.approximateArea(859.5 * 0.092_903_04), "860 ft\u{00B2}")
    XCTAssertEqual(metric.approximateArea(80.44), "80.4 m\u{00B2}")
    XCTAssertEqual(metric.approximateArea(.nan), "-")
  }

  func testMetricPlanWritesMetresAndAMetreScaleBar() throws {
    let plan = try write(WalkthroughFixture.model) { $0.units = UnitFormatter(system: .metric) }
    let shown = PDFFile(plan.pdf).shownText()
    XCTAssertTrue(shown.contains { $0.hasSuffix(" m\u{00B2}") && !$0.hasPrefix("Approx") })
    XCTAssertTrue(shown.contains { $0.hasSuffix(" m") && $0.first?.isNumber == true })
    XCTAssertFalse(shown.contains { $0.hasSuffix("\"") }, "no feet-inches")
  }

  func testOptionsLeaveOutWhatIsTurnedOff() throws {
    let model = WalkthroughFixture.model
    let full = try sheet(model) { $0.northDegrees = 30 }
    XCTAssertEqual(
      layers(full),
      [
        .sheet, .roomFill, .symbol, .wall, .door, .window, .opening, .interiorDimension,
        .exteriorDimension, .roomLabel, .compass, .scaleBar,
      ])
    let bare = try sheet(model) {
      $0.northDegrees = 30
      $0.compass = false
      $0.roomNames = false
      $0.roomAreas = false
      $0.interiorDimensions = false
      $0.exteriorDimensions = false
      $0.furniture = false
      $0.scaleBar = false
    }
    XCTAssertEqual(layers(bare), [.sheet, .roomFill, .wall, .door, .window, .opening])
    // Names without areas, and another title.
    let kitchen = Synthetic.room(width: 4, length: 3, label: "Kitchen")
    let names = PDFFile(
      try write(kitchen) {
        $0.roomAreas = false
        $0.title = "Floor 1"
      }.pdf
    ).shownText()
    XCTAssertTrue(names.contains("Floor 1"))
    XCTAssertFalse(names.contains("Floorplan"))
    XCTAssertTrue(names.contains("Kitchen"))
    XCTAssertFalse(names.contains { $0.hasSuffix(" ft\u{00B2}") })
    // No address: no address line, and the title alone names the document.
    let anonymous = try write(kitchen) { $0.address = "  " }
    let addressed = try write(kitchen)
    XCTAssertEqual(
      PDFFile(anonymous.pdf).shownText().count, PDFFile(addressed.pdf).shownText().count - 1)
    XCTAssertTrue(PDFFile(anonymous.pdf).text.contains("/Title (Floorplan)"))
    XCTAssertTrue(PDFFile(addressed.pdf).text.contains("/Title (Floorplan - \(address))"))
  }

  func testCompassOnlyWhenNorthIsKnownAndTurnsWithThePlan() throws {
    let model = WalkthroughFixture.model
    XCTAssertFalse(layers(try sheet(model)).contains(.compass))
    let sheet = try sheet(model) { $0.northDegrees = 0 }
    XCTAssertTrue(layers(sheet).contains(.compass))
    // The compass sits in the header, above the drawing.
    let compass = sheet.items.filter {
      if case .shape(let s) = $0 { return s.layer == .compass }
      if case .text(let t) = $0 { return t.layer == .compass }
      return false
    }
    let extent = FloorPlanDrawing.extent(of: compass)
    let area = FloorplanWriter.Layout.drawingArea(
      width: sheet.widthMM, height: sheet.heightMM, hasAddress: true)
    XCTAssertGreaterThan(extent.minY, area.y + area.height)
    XCTAssertLessThan(extent.maxY, sheet.heightMM)
    XCTAssertGreaterThan(extent.minX, sheet.widthMM / 2)
    // N points where north is on the turned plan.
    let letter = try XCTUnwrap(
      compass.compactMap { item -> DrawingText? in
        if case .text(let t) = item { return t }
        return nil
      }.first)
    // The rose's ring is the first compass shape.
    let ring = try XCTUnwrap(
      compass.compactMap { item -> DrawingShape? in
        if case .shape(let s) = item { return s }
        return nil
      }.first)
    let xs = ring.path.points.map(\.x)
    let ys = ring.path.points.map(\.y)
    let center = Point2(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
    let direction = (Point2(x: letter.position.x, y: letter.position.y) - center).unit
    let expected = Point2(x: 0, y: 1).rotated(by: -sheet.drawing.rotationDegrees * .pi / 180)
    XCTAssertGreaterThan(direction.dot(expected), 0.9)
  }

  // MARK: Fitting

  func testPageIsChosenToFitThePlan() throws {
    // A long, narrow room prints larger on Letter landscape; a square room on the square page.
    let long = try write(Synthetic.room(width: 14, length: 4))
    XCTAssertEqual(long.page, .letterLandscape)
    XCTAssertEqual(PDFFile(long.pdf).mediaBoxes.first ?? [], [0, 0, 792, 612])
    let square = try write(Synthetic.room(width: 5, length: 5))
    XCTAssertEqual(square.page, .square)
    XCTAssertEqual(PDFFile(square.pdf).mediaBoxes.first ?? [], [0, 0, 720, 720])
    // A page can be forced.
    let forced = try write(Synthetic.room(width: 5, length: 5)) { $0.page = .letterLandscape }
    XCTAssertEqual(forced.page, .letterLandscape)
    XCTAssertGreaterThan(forced.scaleDenominator, square.scaleDenominator)
    // A tall room is turned a quarter round on Letter landscape.
    let tall = try sheet(Synthetic.room(width: 3, length: 9)) { $0.page = .letterLandscape }
    XCTAssertEqual(tall.drawing.options.quarterTurns, 3)
    XCTAssertGreaterThan(tall.drawing.bounds.width, tall.drawing.bounds.height)
    let upright = try sheet(Synthetic.room(width: 3, length: 9)) {
      $0.page = .letterLandscape
      $0.turnToFit = false
    }
    XCTAssertEqual(upright.drawing.options.quarterTurns, 0)
    XCTAssertGreaterThan(
      upright.drawing.options.scaleDenominator, tall.drawing.options.scaleDenominator)
  }

  func testEverythingIsOnThePageAndThePlanInItsArea() throws {
    // Every capture on the page chosen for it, and the walk-through on both pages.
    let cases: [(CaptureModel, FloorplanWriter.Page)] =
      try Fixtures.all().map { ($0.model, .automatic) }
      + [.letterLandscape, .square].map { (WalkthroughFixture.model, $0) }
    for (model, page) in cases {
      let sheet = try sheet(model) {
        $0.page = page
        $0.northDegrees = 45
      }
      let extent = FloorPlanDrawing.extent(of: sheet.items)
      XCTAssertGreaterThanOrEqual(extent.minX, -1e-6, model.label)
      XCTAssertGreaterThanOrEqual(extent.minY, -1e-6, model.label)
      XCTAssertLessThanOrEqual(extent.maxX, sheet.widthMM + 1e-6, model.label)
      XCTAssertLessThanOrEqual(extent.maxY, sheet.heightMM + 1e-6, model.label)
      let area = FloorplanWriter.Layout.drawingArea(
        width: sheet.widthMM, height: sheet.heightMM, hasAddress: true)
      let drawing = sheet.drawing
      let denominator = drawing.options.scaleDenominator
      let width = drawing.bounds.width / denominator
      let height = drawing.bounds.height / denominator
      XCTAssertLessThanOrEqual(width, area.width + 1e-6)
      XCTAssertLessThanOrEqual(height, area.height + 1e-6)
      // And fills it in one direction.
      XCTAssertGreaterThan(
        max(width / area.width, height / area.height), 0.85,
        "\(model.label) \(page) 1:\(denominator)")
    }
  }

  func testEstimateIsCloseToTheFittedScale() throws {
    let model = WalkthroughFixture.model
    let probe = try FloorPlanDrawing(model: model)
    let estimate = try XCTUnwrap(probe.estimatedDenominator(widthMM: 230, heightMM: 190))
    let fitted = try FloorPlanDrawing.fitted(model: model, widthMM: 230, heightMM: 190)
    let denominator = fitted.options.scaleDenominator
    XCTAssertEqual(estimate, denominator, accuracy: denominator * 0.1)
    XCTAssertNil(probe.estimatedDenominator(widthMM: 5, heightMM: 5), "annotations alone")
  }

  func testQuarterTurnsTurnTheDrawing() throws {
    let model = Synthetic.room(width: 6, length: 3)
    let flat = try FloorPlanDrawing(model: model, options: .init(northDegrees: 0))
    let turned = try FloorPlanDrawing(
      model: model, options: .init(northDegrees: 0, quarterTurns: 1))
    XCTAssertEqual(turned.rotationDegrees, flat.rotationDegrees - 90, accuracy: 1e-9)
    let room = try XCTUnwrap(turned.rooms.first)
    let xs = room.polygon.map(\.x)
    let ys = room.polygon.map(\.y)
    XCTAssertEqual(xs.max()! - xs.min()!, 3, accuracy: 1e-9)
    XCTAssertEqual(ys.max()! - ys.min()!, 6, accuracy: 1e-9)
    XCTAssertEqual(turned.roomAreaM2, flat.roomAreaM2, accuracy: 1e-9)
  }

  // MARK: Writers

  func testSVGIsTheSamePage() throws {
    let model = WalkthroughFixture.model
    let plan = try write(model) { $0.northDegrees = 12 }
    let parser = XMLParser(data: Data(plan.svg.utf8))
    XCTAssertTrue(parser.parse(), "well-formed")
    let size = "\(Format.fixed(plan.widthMM, 2))mm\" height=\"\(Format.fixed(plan.heightMM, 2))mm"
    XCTAssertTrue(plan.svg.contains("width=\"\(size)\""))
    XCTAssertTrue(plan.svg.contains("<title>Floorplan - \(address)</title>"))
    for text in PDFFile(plan.pdf).shownText() {
      XCTAssertTrue(plan.svg.contains(">\(SVGWriter.escape(text))</text>"), text)
    }
    XCTAssertTrue(plan.svg.contains("font-family=\"Times New Roman, Times, serif\""), "wordmark")
    XCTAssertTrue(plan.svg.contains("letter-spacing=\""))
    for layer in [DrawingLayer.sheet, .wall, .roomLabel, .compass, .scaleBar] {
      XCTAssertTrue(plan.svg.contains("<g class=\"\(layer.rawValue)\">"), layer.rawValue)
    }
  }

  func testWordmarkUsesTimesOnlyInThisDocument() throws {
    let pdf = PDFFile(try write(WalkthroughFixture.model).pdf)
    XCTAssertTrue(pdf.text.contains("/BaseFont /Times-Roman"))
    XCTAssertTrue(pdf.text.contains("/F1 3 0 R /F2 4 0 R /F3 8 0 R >>"))
    let stream = try XCTUnwrap(pdf.contentStreams.first)
    XCTAssertTrue(stream.contains("BT /F3 "))
    // Letter spacing is set inside a saved state so it ends with the word.
    XCTAssertTrue(stream.contains("q\nBT /F1 "))
    XCTAssertTrue(stream.contains(" Tc "))
    XCTAssertTrue(stream.contains("(RENOVATION) Tj ET\nQ\n"))
    // Today's plan PDF declares no third font.
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let today = try PlanExporter.exportAll(model: capture.model, record: capture.record)
    for file in today where file.fileName.hasSuffix(".pdf") {
      XCTAssertFalse(PDFFile(file.data).text.contains("Times-Roman"), file.fileName)
    }
  }

  func testByteStable() throws {
    let model = WalkthroughFixture.model
    let first = try write(model) { $0.northDegrees = 33 }
    let second = try write(model) { $0.northDegrees = 33 }
    XCTAssertEqual(first.pdf, second.pdf)
    XCTAssertEqual(first.svg, second.svg)
    // The one-format writers write the same page.
    let room = Synthetic.room(width: 4, length: 3)
    let options = FloorplanWriter.Options(address: address)
    let both = try FloorplanWriter.write(model: room, options: options)
    XCTAssertEqual(try FloorplanWriter.pdf(model: room, options: options), both.pdf)
    XCTAssertEqual(try FloorplanWriter.svg(model: room, options: options), both.svg)
  }

  func testEveryFixtureCaptureWritesAFloorplan() throws {
    for capture in try Fixtures.all() {
      let plan = try write(capture.model)
      let shown = PDFFile(plan.pdf).shownText()
      for room in capture.model.rooms {
        XCTAssertTrue(shown.contains(room.label), "\(capture.outputFolder) \(room.label)")
      }
      try Repo.write(
        ExportedFile(
          fileName: "floorplan.pdf", role: .planPDF, mime: "application/pdf", data: plan.pdf),
        folder: "floorplan/\(capture.outputFolder)")
    }
  }
}
