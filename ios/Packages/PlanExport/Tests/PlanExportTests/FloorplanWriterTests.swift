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
    for expected in ["Floorplan", address, plan.totalText, "N"] {
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
    // The print scale beside the bar, as the page is printed at full size.
    XCTAssertTrue(shown.contains("1:\(Format.compact(plan.scaleDenominator))"), "print scale")
    XCTAssertGreaterThanOrEqual(plan.scaleDenominator, 50)
    // Chapter colours: warm charcoal walls, bronze inside dimensions on paler lines, brand
    // black text.
    let stream = try XCTUnwrap(pdf.contentStreams.first)
    func rgb(_ color: DrawingColor, _ op: String) -> String {
      [color.red, color.green, color.blue].map { Format.fixed($0, 4) }.joined(separator: " ")
        + " \(op)"
    }
    XCTAssertTrue(stream.contains(rgb(ChapterBrand.wall, "rg")), "Chapter walls")
    XCTAssertTrue(stream.contains(rgb(ChapterBrand.accent, "rg")), "bronze inside dimensions")
    XCTAssertTrue(stream.contains(rgb(ChapterBrand.accentLine, "RG")), "paler dimension lines")
    XCTAssertTrue(stream.contains(rgb(ChapterBrand.ink, "rg")), "brand black")
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
    let rooms = Synthetic.twoRooms(widths: [4, 2], length: 3)
    let thick = try write(rooms)
    let thin = try write(rooms) { $0.exteriorWallThicknessM = 0.05 }
    XCTAssertEqual(thick.totalAreaM2, (6 + 2 * 0.1524) * (3 + 2 * 0.1524), accuracy: 0.02)
    XCTAssertEqual(thin.totalAreaM2, 6.1 * 3.1, accuracy: 0.02)
    // One room: its own floor area, the same as its label, not a total to walls assumed.
    let single = try write(Synthetic.room(width: 4, length: 3))
    XCTAssertEqual(single.totalAreaM2, 12, accuracy: 1e-9)
    XCTAssertEqual(single.totalText, "Approximately 129 ft\u{00B2} total")
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
    let square = try write(Synthetic.room(width: 11, length: 11))
    XCTAssertEqual(square.page, .square)
    XCTAssertEqual(PDFFile(square.pdf).mediaBoxes.first ?? [], [0, 0, 720, 720])
    // A page can be forced.
    let forced = try write(Synthetic.room(width: 11, length: 11)) { $0.page = .letterLandscape }
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
      // And fills it in one direction, unless it is small enough to print at 1:50, the
      // largest scale used; then it sits in the middle.
      if denominator > FloorplanWriter.Layout.largestScaleDenominator {
        XCTAssertGreaterThan(
          max(width / area.width, height / area.height), 0.85,
          "\(model.label) \(page) 1:\(denominator)")
      } else {
        XCTAssertEqual(denominator, FloorplanWriter.Layout.largestScaleDenominator)
      }
    }
  }

  func testASmallPlanIsDrawnAtOneToFiftyInTheMiddle() throws {
    let sheet = try sheet(Synthetic.room(width: 4, length: 3))
    XCTAssertEqual(sheet.drawing.options.scaleDenominator, 50)
    let area = FloorplanWriter.Layout.drawingArea(
      width: sheet.widthMM, height: sheet.heightMM, hasAddress: true)
    let walls = sheet.items.compactMap { item -> DrawingShape? in
      if case .shape(let shape) = item, shape.layer == .wall { return shape }
      return nil
    }
    let xs = walls.flatMap(\.path.points).map(\.x)
    XCTAssertEqual(
      (xs.min()! + xs.max()!) / 2, area.x + area.width / 2, accuracy: 0.25 * area.width)
  }

  func testScreenVersionIsThePlanAloneWithLargerType() throws {
    let model = WalkthroughFixture.model
    let screen = PDFFile(try FloorplanWriter.screenPDF(model: model))
    let sheet = PDFFile(try write(model).pdf)
    let shown = screen.shownText()
    // No title, total or footer; every room by name.
    for absent in ["Floorplan", "Measurements are approximate.", "chapter"] {
      XCTAssertFalse(shown.contains(absent), absent)
    }
    for room in model.rooms { XCTAssertTrue(shown.contains(room.label), room.label) }
    // A page about a phone's width, so names print larger against the plan than on the sheet.
    let box = try XCTUnwrap(screen.mediaBoxes.first)
    XCTAssertLessThan(box[2] / 72 * 25.4, 130)
    let sheetBox = try XCTUnwrap(sheet.mediaBoxes.first)
    XCTAssertLessThan(box[2], sheetBox[2] / 2)
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
    XCTAssertTrue(plan.svg.contains("font-family=\"\(ChapterBrand.serifFamily)\""), "title")
    XCTAssertTrue(plan.svg.contains("font-family=\"\(ChapterBrand.sansFamily)\""), "Inter")
    for layer in [DrawingLayer.sheet, .wall, .roomLabel, .compass, .scaleBar] {
      XCTAssertTrue(plan.svg.contains("<g class=\"\(layer.rawValue)\">"), layer.rawValue)
    }
  }

  func testTitleIsTimesTextIsInterAndTheLogoIsDrawn() throws {
    let model = WalkthroughFixture.model
    let pdf = PDFFile(try write(model).pdf)
    XCTAssertEqual(
      pdf.baseFonts.sorted(), ["CHAPRA+Inter-Regular", "Times-Roman"], "only the fonts used")
    let stream = try XCTUnwrap(pdf.contentStreams.first)
    XCTAssertTrue(stream.contains("BT /F3 "))
    XCTAssertTrue(pdf.shownText().contains("Floorplan"))
    // The logo: one filled path per logo path, in the brand black, at the bottom right.
    let sheet = try FloorplanWriter.Sheet(model: model, options: .init(address: address))
    let logo = sheet.items.compactMap { item -> DrawingShape? in
      guard case .shape(let shape) = item, shape.layer == .sheet, shape.fill == ChapterBrand.ink
      else { return nil }
      return shape
    }
    XCTAssertEqual(logo.count, ChapterLogo.paths.count)
    let xs = logo.flatMap { $0.path.points.map(\.x) }
    let ys = logo.flatMap { $0.path.points.map(\.y) }
    let margin = FloorplanWriter.Layout.margin
    XCTAssertEqual(xs.max()!, sheet.widthMM - margin, accuracy: 0.05)
    XCTAssertEqual(
      xs.max()! - xs.min()!, ChapterLogo.width(height: FloorplanWriter.Layout.logoHeight),
      accuracy: 0.05)
    XCTAssertEqual(ys.min()!, margin + 0.6, accuracy: 0.05)
    // Every PDF the app exports carries the Chapter type and logo too.
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let today = try PlanExporter.exportAll(model: capture.model, record: capture.record)
    for file in today where file.fileName.hasSuffix(".pdf") {
      let exported = PDFFile(file.data)
      XCTAssertTrue(exported.baseFonts.contains("CHAPRA+Inter-Regular"), file.fileName)
      XCTAssertTrue(exported.baseFonts.contains("Times-Roman"), file.fileName)
      XCTAssertFalse(exported.baseFonts.contains { $0.hasPrefix("Helvetica") }, file.fileName)
      let first = try XCTUnwrap(exported.contentStreams.first)
      XCTAssertGreaterThanOrEqual(
        first.components(separatedBy: " f\n").count - 1, ChapterLogo.paths.count,
        "logo in \(file.fileName)")
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

  // MARK: Long text

  /// `count` characters of capitals and spaces, the widest a room name usually gets.
  private func capitals(_ count: Int) -> String {
    String(String(repeating: "WIDE ROOM NAME ", count: count / 15 + 1).prefix(count))
      .trimmingCharacters(in: .whitespaces)
  }

  func testLongRoomNamesAreFittedToTheirRooms() throws {
    // A 6 x 3 m plan of two rooms, named with 100 capitals (the longest label the capture
    // model allows) and with 240.
    let reference = Synthetic.twoRooms(widths: [4, 2], length: 3)
    let referencePage = try write(reference)
    let referenceScreen = try XCTUnwrap(
      PDFFile(try FloorplanWriter.screenPDF(model: reference)).mediaBoxes.first)
    for length in [75, 100, 240] {
      var model = reference
      for index in model.rooms.indices { model.rooms[index].label = capitals(length) }
      // The page keeps its scale; the names stay inside their rooms.
      let page = try write(model)
      XCTAssertEqual(page.scaleDenominator, referencePage.scaleDenominator, "\(length)")
      let sheet = try sheet(model)
      let drawing = sheet.drawing
      let labels = drawing.labels.filter { $0.kind == .room }
      XCTAssertEqual(labels.count, 2)
      for label in labels {
        let room = try XCTUnwrap(drawing.rooms.first { $0.id == label.roomId })
        XCTAssertTrue(label.box.isInside(room.polygon), "\(length) \(room.id)")
        XCTAssertLessThanOrEqual(label.text.split(separator: "\n").count, 3, "two lines and area")
        if length == 240 { XCTAssertTrue(label.text.contains("\u{2026}"), label.text) }
      }
      // Every item of the page is on it.
      let extent = FloorPlanDrawing.extent(of: sheet.items)
      XCTAssertLessThanOrEqual(extent.maxX, sheet.widthMM + 1e-6)
      XCTAssertGreaterThanOrEqual(extent.minX, -1e-6)
      // The screen version keeps its size and scale.
      let screen = try XCTUnwrap(
        PDFFile(try FloorplanWriter.screenPDF(model: model)).mediaBoxes.first)
      XCTAssertEqual(screen[2], referenceScreen[2], accuracy: referenceScreen[2] * 0.05)
      XCTAssertEqual(screen[3], referenceScreen[3], accuracy: referenceScreen[3] * 0.05)
    }
  }

  func testNamesWrapThenShrinkBeforeTheyAreCut() throws {
    // At 1:50 the 2 x 3 m room is 40 mm across.
    let k = 0.05
    let style = FloorPlanStyle()
    let room = [
      Point2(x: 0, y: 0), Point2(x: 2, y: 0), Point2(x: 2, y: 3), Point2(x: 0, y: 3),
    ]
    let layout = AnnotationLayout(
      style: style, units: UnitFormatter(system: .imperial), scaleDenominator: 1000 * k,
      symbols: [], building: [], wallPieces: [])
    func fitted(_ name: String) -> [(text: String, size: Double)] {
      layout.fittedRoomLabel(name: name, area: "64.6 ft\u{00B2}", polygon: room).block
    }
    let nameSize = style.roomNameSize * k
    let areaSize = style.roomAreaSize * k
    // The room's width less the space kept round a label.
    let clear = 2 - 2 * 0.6 * k
    // Fits: one line at the name size.
    let short = fitted("Bedroom")
    XCTAssertEqual(short.map(\.text), ["Bedroom", "64.6 ft\u{00B2}"])
    XCTAssertEqual(short[0].size, nameSize, accuracy: 1e-12)
    // Words too wide together: two lines at the name size.
    let words = "Primary Bedroom With Ensuite"
    XCTAssertGreaterThan(FontMetrics.width(words, size: nameSize), clear)
    let two = fitted(words)
    XCTAssertEqual(two.count, 3)
    XCTAssertEqual(two[0].text + " " + two[1].text, words)
    XCTAssertEqual(two[0].size, nameSize, accuracy: 1e-12)
    // One word too wide: smaller, but no smaller than the area.
    var word = "Pantry-"
    while FontMetrics.width(word, size: nameSize) <= clear { word += "a" }
    XCTAssertLessThanOrEqual(FontMetrics.width(word, size: areaSize), clear)
    let small = fitted(word)
    XCTAssertEqual(small.first?.text, word)
    XCTAssertLessThan(small[0].size, nameSize)
    XCTAssertGreaterThanOrEqual(small[0].size, areaSize - 1e-12)
    // Too wide at the area size on two lines: cut short with an ellipsis, as wide as fits.
    let cut = fitted(capitals(100))
    XCTAssertEqual(cut.count, 3)
    XCTAssertTrue(cut[1].text.hasSuffix("\u{2026}"))
    for line in cut.prefix(2) {
      XCTAssertEqual(line.size, areaSize, accuracy: 1e-12)
      XCTAssertLessThanOrEqual(FontMetrics.width(line.text, size: line.size), clear)
      XCTAssertGreaterThan(FontMetrics.width(line.text, size: line.size), 0.7 * clear)
    }
    // A room too small even for its area line: the name kept to a few characters, at the
    // middle.
    let closet = room.map { $0 * 0.1 }
    let tiny = layout.fittedRoomLabel(
      name: capitals(100), area: "0.6 ft\u{00B2}", polygon: closet)
    XCTAssertNil(tiny.place)
    XCTAssertEqual(
      tiny.block.first?.text.count, AnnotationLayout.minimumNameCharacters + 1, "and …")
  }

  func testALongAddressIsFittedToTheHeader() throws {
    // 300 characters, the longest address the capture record allows.
    let long = String(
      String(
        repeating: "Unit 1204, The Residences at Harbour Point, 1500 South Harbour Boulevard, ",
        count: 5
      ).prefix(300))
    // The 136-character address of the review.
    let review =
      "Unit 1204, The Residences at Harbour Point, 1500 South Harbour Boulevard North, "
      + "Fort Lauderdale-by-the-Sea, FL 33308-1234, United States"
    let model = Synthetic.room(width: 4, length: 3)
    for address in [review, long] {
      for page in [FloorplanWriter.Page.letterLandscape, .square] {
        for north in [nil, 30.0] {
          let sheet = try sheet(model) {
            $0.address = address
            $0.page = page
            $0.northDegrees = north
          }
          let name = "\(address.count) \(page) \(north.map { "\($0)" } ?? "no north")"
          let layout = try XCTUnwrap(sheet.addressLayout)
          XCTAssertLessThanOrEqual(layout.lines.count, 2, name)
          XCTAssertGreaterThanOrEqual(
            layout.size, FloorplanWriter.Layout.addressMinimumSize - 1e-9, name)
          if address == long {
            // On two lines, cut short when they would not hold it all.
            XCTAssertEqual(layout.lines.count, 2, name)
            let whole = address.trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(
              layout.lines.joined(separator: " ") == whole
                || layout.lines[1].hasSuffix("\u{2026}"), name)
          }
          let width = FloorplanWriter.Layout.addressWidth(
            pageWidth: sheet.widthMM, compass: north != nil)
          for line in layout.lines {
            XCTAssertLessThanOrEqual(
              FontMetrics.width(line, size: layout.size), width + 1e-9, name)
          }
          // Every address line on the page and clear of the compass.
          let texts = sheet.items.compactMap { item -> DrawingText? in
            guard case .text(let text) = item, layout.lines.contains(text.string) else {
              return nil
            }
            return text
          }
          XCTAssertEqual(texts.count, layout.lines.count, name)
          let compass = sheet.items.filter {
            if case .shape(let s) = $0 { return s.layer == .compass }
            if case .text(let t) = $0 { return t.layer == .compass }
            return false
          }
          for text in texts {
            let xs = FloorPlanDrawing.textCorners(text).map(\.x)
            XCTAssertGreaterThanOrEqual(xs.min()!, FloorplanWriter.Layout.margin - 1e-6, name)
            XCTAssertLessThanOrEqual(
              xs.max()!, sheet.widthMM - FloorplanWriter.Layout.margin + 1e-6, name)
            if !compass.isEmpty {
              XCTAssertLessThan(xs.max()!, FloorPlanDrawing.extent(of: compass).minX, name)
            }
          }
          // The total stays below the address and above the drawing.
          let total = try XCTUnwrap(
            sheet.items.compactMap { item -> DrawingText? in
              guard case .text(let text) = item, text.string == sheet.totalText else {
                return nil
              }
              return text
            }.first, name)
          XCTAssertLessThan(total.position.y, texts.map(\.position.y).min()!, name)
          XCTAssertGreaterThan(
            total.position.y - 0.22 * total.size,
            sheet.drawingArea.y + sheet.drawingArea.height, name)
        }
      }
    }
    // The review's address fits one line on Letter landscape, set smaller.
    let letter = try sheet(model) {
      $0.address = review
      $0.page = .letterLandscape
    }
    XCTAssertEqual(letter.addressLayout?.lines, [review])
    XCTAssertLessThan(letter.addressLayout!.size, FloorplanWriter.Layout.addressSize)
  }

  // MARK: Document information

  /// The document information string `key`: a literal, or UTF-16BE hex with a byte order mark.
  private func info(_ pdf: PDFFile, _ key: String) -> String? {
    if let range = pdf.text.range(of: "/\(key) (") {
      let rest = pdf.text[range.upperBound...]
      guard let end = rest.range(of: ") /") else { return nil }
      return PDFFile.unescape(String(rest[..<end.lowerBound]))
    }
    guard let range = pdf.text.range(of: "/\(key) <FEFF") else { return nil }
    let rest = pdf.text[range.upperBound...]
    guard let end = rest.firstIndex(of: ">") else { return nil }
    let hex = Array(rest[..<end])
    var units: [UInt16] = []
    var index = 0
    while index + 4 <= hex.count {
      units.append(UInt16(String(hex[index..<index + 4]), radix: 16) ?? 0)
      index += 4
    }
    return String(decoding: units, as: UTF16.self)
  }

  func testCreationDateIsTheCaptureTime() throws {
    // 2026-10-17 14:02:11 UTC.
    let captured = Date(timeIntervalSince1970: 1_792_245_731)
    XCTAssertEqual(FloorplanWriter.pdfDate(captured), "D:20261017140211Z")
    let model = Synthetic.room(width: 4, length: 3)
    let plan = try write(model) { $0.creationDate = FloorplanWriter.pdfDate(captured) }
    XCTAssertTrue(PDFFile(plan.pdf).text.contains("/CreationDate (D:20261017140211Z)"))
    let screen = try FloorplanWriter.screenPDF(
      model: model, options: .init(creationDate: FloorplanWriter.pdfDate(captured)))
    XCTAssertTrue(PDFFile(screen).text.contains("/CreationDate (D:20261017140211Z)"))
  }

  func testDocumentTitleKeepsEveryCharacterOfTheAddress() throws {
    // Brackets, a backslash, curly quotes, a decomposed e-acute, dashes, an ellipsis, a
    // curly apostrophe and a no-break space.
    let address =
      "12 (Main) St \\ Apt <4> & \u{201C}Co\u{201D} Cafe\u{0301} \u{2014} \u{2026} "
      + "O\u{2019}Connell\u{00A0}St"
    let composed = address.precomposedStringWithCanonicalMapping
    let plan = try write(Synthetic.room(width: 4, length: 3)) { $0.address = address }
    let pdf = PDFFile(plan.pdf)
    XCTAssertTrue(pdf.text.contains("/Title <FEFF"), "UTF-16 for text beyond ASCII")
    XCTAssertEqual(info(pdf, "Title"), "Floorplan - \(composed)")
    XCTAssertEqual(info(pdf, "Author"), "Chapter")
    // Plain titles stay literal strings.
    let plain = PDFFile(try write(Synthetic.room(width: 4, length: 3)).pdf)
    XCTAssertEqual(info(plain, "Title"), "Floorplan - \(self.address)")
    XCTAssertTrue(plain.text.contains("/Title (Floorplan - \(self.address))"))
    // On the page the decomposed e-acute is drawn as the one WinAnsi character.
    let line = try XCTUnwrap(pdf.shownText().first { $0.hasPrefix("12 (Main)") })
    XCTAssertTrue(line.contains("Caf\u{00E9}"), line)
    XCTAssertFalse(line.contains("?"), line)
    XCTAssertEqual(
      FontMetrics.width("Cafe\u{0301}", size: 10), FontMetrics.width("Caf\u{00E9}", size: 10))
  }

  // MARK: Golden bytes

  /// SHA-256 of the colour Floorplan without a north symbol (`north` nil, the default), recorded
  /// before the north symbol of compass §6.3 replaced the compass rose. `tools/plan-render` and
  /// the scan browser draw with `north` nil, so their pages must stay byte for byte the same.
  private static let goldenWithoutNorth: [String: String] = [
    "box-room/floor-1 pdf": "f3e94b9f45a74d4b4b6af360dd011dba172a710d60ec7d93b0a57a8f2bfc8c05",
    "box-room/floor-1 svg": "1a9d53d6272b2590bb93b69b4442178034c3dfff6d4f0dd6ceec13147f003dfa",
    "l-shaped-room/floor-1 pdf": "482922835ce7ab77fe556861f8ba068f0fa34fe6c229b68cf18b1f210ec559dd",
    "l-shaped-room/floor-1 svg": "c16881c2d362cfed4c4d5420b44c9c0d5c5439db47292ffa76a32708d3c52031",
    "two-floor-house/floor-1 pdf":
      "d750555e226b6bb5e40c1ce32c4fa067e0425dc3c1814c91315992d53d134f84",
    "two-floor-house/floor-1 svg":
      "1b5e686dfe282979eca165a60579bf7b18ee53e2f4ee7a2afbed53d77f595960",
    "two-floor-house/floor-2 pdf":
      "39105e0adc285e4ef1b2397727df2198f8f57e9ebabacdcc8270cd3706ddf596",
    "two-floor-house/floor-2 svg":
      "b099d33a8949e56be8d7f80bba12128bce22f20cca038271cdedabbb9537fd1e",
    "two-room-apartment/floor-1 pdf":
      "1883d760a4f1500783ce875a91531c3e102499c28c91cd8255dbc903810aef05",
    "two-room-apartment/floor-1 svg":
      "528686c4044acec0d83aecda9fcb9d87b23b0f100812534e12d9472b29b48407",
    "walkthrough automatic pdf": "fa31fbf7e437ba0821272e4d0849f30b9f82480928f258a4e033642404eebb73",
    "walkthrough automatic svg": "aba9635d43c1b3b0cb48aae617f4c1e0817f2c0e79c5ad50f2c4bb0bff7ef07e",
    "walkthrough letterLandscape pdf":
      "365b977abdc1715abc275ef01ce51404bd8d61899f3b96696b87d5c53020a4e3",
    "walkthrough letterLandscape svg":
      "a14bd5243697337d35a23584c325ac8c79bbd6a6fd2dae83401125a725e5e710",
    "walkthrough square pdf": "fa31fbf7e437ba0821272e4d0849f30b9f82480928f258a4e033642404eebb73",
    "walkthrough square svg": "aba9635d43c1b3b0cb48aae617f4c1e0817f2c0e79c5ad50f2c4bb0bff7ef07e",
    "walkthrough screen": "db216f1fb63ddfabb869c11c87bdb0bf323a96745a874c832d731ffe7bdbde30",
    "walkthrough drawing svg": "623933d4243a0ee82bbf1d1069bce984870c04c9131e549761f38be29135200f",
    "walkthrough drawing pdf": "732bd6f82f7742b176d83c0c2309cd5e5d04a0e07336ffc032efc9b8683c0df3",
  ]

  func testColourFloorplanUnchangedWithoutNorth() throws {
    var outputs: [(name: String, data: Data)] = []
    for capture in try Fixtures.all() {
      let plan = try FloorplanWriter.write(
        model: capture.model,
        options: .init(address: capture.record.address.formatted))
      outputs.append(("\(capture.outputFolder) pdf", plan.pdf))
      outputs.append(("\(capture.outputFolder) svg", Data(plan.svg.utf8)))
    }
    let walkthrough = WalkthroughFixture.model
    for page in FloorplanWriter.Page.allCases {
      let plan = try write(walkthrough) { $0.page = page }
      outputs.append(("walkthrough \(page.rawValue) pdf", plan.pdf))
      outputs.append(("walkthrough \(page.rawValue) svg", Data(plan.svg.utf8)))
    }
    outputs.append(("walkthrough screen", try FloorplanWriter.screenPDF(model: walkthrough)))
    let drawing = try FloorPlanDrawing(model: walkthrough)
    outputs.append(("walkthrough drawing svg", Data(drawing.svg(title: "Apartment").utf8)))
    outputs.append(("walkthrough drawing pdf", drawing.pdf(title: "Apartment")))
    var actual: [String: String] = [:]
    for output in outputs { actual[output.name] = SHA256.hexDigest(of: output.data) }
    for name in actual.keys.sorted() {
      XCTAssertEqual(actual[name], Self.goldenWithoutNorth[name], name)
    }
    XCTAssertEqual(Set(actual.keys), Set(Self.goldenWithoutNorth.keys))
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
