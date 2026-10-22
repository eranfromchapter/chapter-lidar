import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// The plan sheet rendition of `FloorPlanDrawing` (plan-sheet §3.4): palette, line weights,
/// openings, objects and symbols, labels.
final class PlanSheetRenditionTests: XCTestCase {
  private let palette = ChapterBrand.Sheet.self

  private func drawing(_ model: CaptureModel, n: Double = 50, mode: CaptureMode? = nil) throws
    -> FloorPlanDrawing
  {
    try FloorPlanDrawing(
      model: model,
      options: .init(
        scaleDenominator: n, interiorDimensions: false, scaleBar: false, rendition: .planSheet,
        captureMode: mode))
  }

  /// Plan millimetres of `points` paper points at 1:`n`.
  private func pt(_ points: Double, _ n: Double = 50) -> Double { points * 25.4 / 72 * n }

  private func shapes(_ drawing: FloorPlanDrawing, _ layer: DrawingLayer) -> [DrawingShape] {
    drawing.items.compactMap { item in
      if case .shape(let shape) = item, shape.layer == layer { return shape }
      return nil
    }
  }

  /// The dash pattern of `shape`, in points at 1:50.
  private func assertDash(
    _ shape: DrawingShape, _ points: [Double], file: StaticString = #filePath, line: UInt = #line
  ) {
    let dash = shape.stroke?.dash ?? []
    XCTAssertEqual(dash.count, points.count, file: file, line: line)
    for (a, b) in zip(dash, points) {
      XCTAssertEqual(a, pt(b), accuracy: 1e-9, file: file, line: line)
    }
  }

  private func curves(_ shape: DrawingShape) -> Int {
    shape.path.elements.filter {
      if case .curve = $0 { return true }
      return false
    }.count
  }

  func testWallsAreInkAndNeverThinnerThanTwoPoints() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    for n in [50.0, 200, 500] {
      let drawing = try drawing(capture.model, n: n)
      let walls = shapes(drawing, .wall)
      XCTAssertEqual(walls.count, 1)
      XCTAssertEqual(walls[0].fill, palette.ink)
      XCTAssertNil(walls[0].stroke)
      for segment in drawing.walls.segments {
        XCTAssertGreaterThanOrEqual(segment.hi - segment.lo, 2 * 25.4 / 72 * n / 1000 - 1e-12)
      }
    }
    // At 1:50 the assumed thicknesses are drawn (4.5 in and 6 in are more than 2 pt).
    let fifty = try drawing(capture.model)
    XCTAssertEqual(fifty.walls.exteriorThickness, 0.1524)
    XCTAssertEqual(fifty.walls.interiorThickness, 0.1143)
    // At 1:200 the interior walls are widened to 2 pt; the dimensions keep 4.5 in / 6 in.
    let coarse = try drawing(capture.model, n: 200)
    XCTAssertEqual(coarse.walls.interiorThickness, 2 * 25.4 / 72 * 200 / 1000, accuracy: 1e-12)
    XCTAssertEqual(
      try XCTUnwrap(coarse.sheetFrame).width, try XCTUnwrap(fifty.sheetFrame).width,
      accuracy: 1e-9)
  }

  func testOpeningsAreThresholdsAndWindowLines() throws {
    // two-room-apartment: a door between the rooms, two windows and a passage.
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let drawing = try drawing(capture.model)
    let doors = shapes(drawing, .door)
    XCTAssertEqual(doors.count, 1)
    XCTAssertEqual(curves(doors[0]), 0, "no swing")
    XCTAssertNil(doors[0].fill, "no leaf")
    XCTAssertEqual(doors[0].stroke?.color, palette.muted)
    XCTAssertEqual(doors[0].stroke?.width ?? 0, pt(0.4), accuracy: 1e-9)
    XCTAssertEqual(doors[0].stroke?.dash, [])
    let passages = shapes(drawing, .opening)
    XCTAssertEqual(passages.count, 1)
    assertDash(passages[0], [2, 2])
    XCTAssertEqual(passages[0].stroke?.color, palette.muted)
    // Windows: the clear in the page colour, then two 0.6 pt ink lines 2 pt apart.
    let windows = shapes(drawing, .window)
    XCTAssertEqual(windows.count, 2)
    XCTAssertEqual(windows[0].fill, palette.surface)
    XCTAssertNil(windows[0].stroke)
    XCTAssertEqual(windows[1].stroke?.color, palette.ink)
    XCTAssertEqual(windows[1].stroke?.width ?? 0, pt(0.6), accuracy: 1e-9)
    let lines = windows[1].path.elements.compactMap { element -> DrawingPoint? in
      if case .move(let p) = element { return p }
      return nil
    }
    let ends = windows[1].path.elements.compactMap { element -> DrawingPoint? in
      if case .line(let p) = element { return p }
      return nil
    }
    XCTAssertEqual(lines.count, 4, "two lines per window")
    // The two lines of the first window are parallel, 2 pt apart.
    let d = (ends[0].x - lines[0].x, ends[0].y - lines[0].y)
    let length = hypot(d.0, d.1)
    let apart = abs((lines[1].x - lines[0].x) * d.1 - (lines[1].y - lines[0].y) * d.0) / length
    XCTAssertEqual(apart, pt(2), accuracy: 1e-6)
    // No jamb lines and nothing on the floorplan's opening layers but thresholds.
    XCTAssertTrue(shapes(drawing, .compass).isEmpty)
    XCTAssertTrue(shapes(drawing, .scaleBar).isEmpty)
  }

  func testObjectsAreBoxesWithFourFixtureSymbols() throws {
    let drawing = try drawing(WalkthroughFixture.model)
    let symbols = shapes(drawing, .symbol)
    XCTAssertFalse(symbols.isEmpty)
    for shape in symbols {
      XCTAssertEqual(shape.stroke?.color, palette.muted)
      XCTAssertEqual(shape.stroke?.width ?? 0, pt(0.6), accuracy: 1e-9)
      XCTAssertEqual(shape.stroke?.cap, .butt)
      XCTAssertEqual(shape.stroke?.join, .miter)
      if let fill = shape.fill { XCTAssertEqual(fill, palette.surface) }
    }
    // Every symbol of the walk-through: a plain 4-corner box for every category but the four
    // fixtures, which draw their symbol (curves for the toilet bowl, sink basin, tub corners
    // and burners).
    for symbol in drawing.symbols where !symbol.overhead {
      let outline = symbol.outline.path
      let curved = outline.elements.contains {
        if case .curve = $0 { return true }
        return false
      }
      switch symbol.category {
      case .toilet:
        XCTAssertTrue(curved, "toilet bowl")
        XCTAssertTrue(symbol.details.isEmpty)
      case .sink, .bathtub, .stove:
        XCTAssertFalse(curved, "\(symbol.category) box")
        XCTAssertFalse(symbol.details.isEmpty, "\(symbol.category) symbol")
      default:
        XCTAssertFalse(curved, "\(symbol.category)")
        XCTAssertEqual(outline.elements.count, 5, "\(symbol.category): a box (4 corners, close)")
        XCTAssertTrue(symbol.details.isEmpty, "\(symbol.category)")
      }
    }
    for category in [ObjectCategory.toilet, .sink, .bathtub, .stove] {
      XCTAssertTrue(drawing.symbols.contains { $0.category == category }, "\(category)")
    }
  }

  func testLowConfidenceAndOverheadObjects() throws {
    var model = Synthetic.room(width: 4, length: 3)
    func box(_ id: String, _ category: ObjectCategory, x: Double, y: Double, height: Double)
      -> CaptureModel.DetectedObject
    {
      CaptureModel.DetectedObject(
        id: id, category: category,
        box: CaptureModel.OrientedBox(
          center: Vec3(x: x, y: y, z: 1.5), sizeM: Vec3(x: 0.6, y: height, z: 0.5)))
    }
    model.objects = [
      box("object-1", .storage, x: 1, y: 0.45, height: 0.9),
      box("object-2", .storage, x: 2.5, y: 1.8, height: 0.6),
      box("object-3", .chair, x: 3.2, y: 0.4, height: 0.8),
    ]
    model.objects[2].confidence = .low
    let drawing = try drawing(model)
    let symbols = shapes(drawing, .symbol)
    XCTAssertEqual(symbols.count, 3)
    // Standing objects first; the low-confidence one dashed 1.8 / 1.2; the overhead cabinet
    // (underside 1.5 m above the floor) last, unfilled and solid.
    let dashed = symbols.filter { !($0.stroke?.dash.isEmpty ?? true) }
    XCTAssertEqual(dashed.count, 1)
    let dash = dashed[0].stroke?.dash ?? []
    XCTAssertEqual(dash.count, 2)
    XCTAssertEqual(dash[0], pt(1.8), accuracy: 1e-9)
    XCTAssertEqual(dash[1], pt(1.2), accuracy: 1e-9)
    XCTAssertEqual(dashed[0].fill, palette.surface)
    let overhead = try XCTUnwrap(symbols.last)
    XCTAssertNil(overhead.fill)
    XCTAssertEqual(overhead.stroke?.dash, [])
  }

  func testRoomFillsByClassAndOutdoorEdges() throws {
    let model = Synthetic.rooms([
      ("Bedroom", .bedroom, [(0, 0), (0, 3), (3, 3), (3, 0)]),
      ("Bathroom", .bathroom, [(3, 0), (3, 3), (5, 3), (5, 0)]),
      ("Balcony", .other, [(5, 0), (5, 3), (7, 3), (7, 0)]),
      ("Hall", .hallway, [(0, 3), (0, 4), (7, 4), (7, 3)]),
    ])
    let drawing = try drawing(model)
    let fills = shapes(drawing, .roomFill)
    XCTAssertEqual(
      fills.compactMap(\.fill), [palette.nude, palette.wet, palette.ground])
    let outdoor = try XCTUnwrap(fills.first { $0.fill == nil })
    XCTAssertEqual(outdoor.stroke?.color, palette.muted)
    XCTAssertEqual(outdoor.stroke?.width ?? 0, pt(0.6), accuracy: 1e-9)
    assertDash(outdoor, [4, 3])
    XCTAssertEqual(drawing.fillClasses["room-3"], .outdoor)
    // An exterior capture: every room outdoor.
    let exterior = try self.drawing(model, mode: .exterior)
    XCTAssertTrue(shapes(exterior, .roomFill).allSatisfy { $0.fill == nil })
  }

  func testRoomLabelsAreCapitalisedSemiBoldWithTheirAreaBelow() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let drawing = try drawing(capture.model)
    let texts = drawing.items.compactMap { item -> DrawingText? in
      if case .text(let text) = item, text.layer == .roomLabel { return text }
      return nil
    }
    let names = texts.filter { $0.font == .interSemiBold }
    let areas = texts.filter { $0.font == .interRegular }
    XCTAssertEqual(Set(names.map(\.string)), ["LIVING ROOM", "BEDROOM"])
    for name in names {
      XCTAssertEqual(name.size, pt(7.5), accuracy: 1e-9)
      XCTAssertEqual(name.letterSpacing, pt(0.9), accuracy: 1e-9)
      XCTAssertEqual(name.color, palette.ink)
      XCTAssertEqual(name.anchor, .center)
      // Its area 11.25 pt below, same centre, muted, "sq ft" with one decimal.
      let area = try XCTUnwrap(areas.first { abs($0.position.x - name.position.x) < 1e-9 })
      XCTAssertEqual(name.position.y - area.position.y, pt(11.25), accuracy: 1e-9)
      XCTAssertEqual(area.color, palette.muted)
      XCTAssertEqual(area.size, pt(7.5), accuracy: 1e-9)
      XCTAssertTrue(area.string.hasSuffix(" sq ft"), area.string)
    }
    XCTAssertTrue(areas.map(\.string).contains("215.3 sq ft"), "\(areas.map(\.string))")
    // No patch behind a label.
    XCTAssertTrue(shapes(drawing, .roomLabel).isEmpty)
  }

  func testALongNameWrapsThenIsCutNeverSmaller() throws {
    let model = Synthetic.rooms([
      ("Walk-in wardrobe and dressing area for guests", .closet, [(0, 0), (0, 1.2), (1.4, 1.2), (1.4, 0)])
    ])
    let drawing = try drawing(model)
    let names = drawing.items.compactMap { item -> DrawingText? in
      if case .text(let text) = item, text.font == .interSemiBold { return text }
      return nil
    }
    XCTAssertFalse(names.isEmpty)
    XCTAssertLessThanOrEqual(names.count, 2)
    for name in names { XCTAssertEqual(name.size, pt(7.5), accuracy: 1e-9) }
    XCTAssertTrue(names.last!.string.hasSuffix("..."), "\(names.map(\.string))")
  }

  func testTheColourFloorplanIsUntouchedByTheRendition() throws {
    // The default rendition is the colour Floorplan; the sheet's parts stay empty for it.
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let colour = try FloorPlanDrawing(model: capture.model)
    XCTAssertEqual(colour.options.rendition, .floorplan)
    XCTAssertTrue(colour.sheetDimensions.isEmpty)
    XCTAssertNil(colour.sheetFrame)
    XCTAssertFalse(shapes(colour, .door).isEmpty)
    XCTAssertTrue(shapes(colour, .door).contains { curves($0) > 0 }, "swings on the Floorplan")
  }
}
