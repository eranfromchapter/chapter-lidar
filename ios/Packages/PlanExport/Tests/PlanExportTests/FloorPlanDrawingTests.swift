import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

#if canImport(FoundationXML)
  import FoundationXML
#endif

final class FloorPlanDrawingTests: XCTestCase {
  /// Every fixture capture and the walk-through, with a name for messages.
  private func allModels() throws -> [(name: String, model: CaptureModel)] {
    try Fixtures.all().map { ("\($0.fixture)/\($0.truth.areaKey)", $0.model) }
      + [("apartment-walkthrough", WalkthroughFixture.model)]
  }

  private func drawing(
    _ model: CaptureModel, _ configure: (inout FloorPlanDrawing.Options) -> Void = { _ in }
  )
    throws -> FloorPlanDrawing
  {
    var options = FloorPlanDrawing.Options()
    configure(&options)
    return try FloorPlanDrawing(model: model, options: options)
  }

  private func covered(_ p: Point2, by pieces: [[Point2]]) -> Bool {
    pieces.contains { PlanGeometry.contains($0, p) }
  }

  private func texts(_ drawing: FloorPlanDrawing) -> [DrawingText] {
    func collect(_ items: [DrawingItem]) -> [DrawingText] {
      items.flatMap { item -> [DrawingText] in
        switch item {
        case .text(let text): return [text]
        case .shape: return []
        case .clipped(_, let children): return collect(children)
        }
      }
    }
    return collect(drawing.items)
  }

  private func shapes(_ drawing: FloorPlanDrawing, _ layer: DrawingLayer) -> [DrawingShape] {
    drawing.items.compactMap { item in
      if case .shape(let shape) = item, shape.layer == layer { return shape }
      return nil
    }
  }

  // MARK: Walls

  func testExteriorWallsAreMitredBandsOutsideTheRoom() throws {
    // A 4 m by 3 m room without openings: the band is the 6 in ring outside the outline.
    let model = Synthetic.room(width: 4, length: 3)
    let drawing = try drawing(model)
    let t = drawing.options.exteriorWallThicknessM
    let pieces = drawing.walls.pieces
    XCTAssertEqual(drawing.walls.loops.count, 1)
    XCTAssertTrue(drawing.walls.loops[0].closed)
    XCTAssertEqual(drawing.walls.segments.filter { $0.kind == .exterior }.count, 4)
    XCTAssertTrue(drawing.walls.segments.allSatisfy { $0.kind == .exterior })
    // Four mitred quadrilaterals tile the ring exactly: no gaps, no overlaps.
    let area = pieces.map { Geo.signedArea($0) }.reduce(0, +)
    XCTAssertEqual(area, (4 + 2 * t) * (3 + 2 * t) - 12, accuracy: 1e-9)
    XCTAssertTrue(pieces.allSatisfy { Geo.signedArea($0) > 0 }, "all counter-clockwise")
    // Plan: x from 0 to 4, y from -3 to 0 (plan y is -z).
    let room = drawing.rooms[0].polygon
    XCTAssertEqual(room.map(\.x).min()!, 0, accuracy: 1e-9)
    XCTAssertEqual(room.map(\.y).min()!, -3, accuracy: 1e-9)
    for corner in [
      Point2(x: 0, y: 0), Point2(x: 4, y: 0), Point2(x: 4, y: -3), Point2(x: 0, y: -3),
    ] {
      // The outside corner square is filled (mitred), the inside is the room.
      let out = Point2(
        x: corner.x == 0 ? -t / 2 : corner.x + t / 2, y: corner.y == 0 ? t / 2 : corner.y - t / 2)
      XCTAssertTrue(covered(out, by: pieces), "corner \(corner)")
      let inside = Point2(
        x: corner.x == 0 ? 0.01 : corner.x - 0.01, y: corner.y == 0 ? -0.01 : corner.y + 0.01)
      XCTAssertFalse(covered(inside, by: pieces))
    }
    // The outside face loop is the outline grown by the thickness.
    let outer = drawing.walls.loops[0].outer
    XCTAssertEqual(outer.map(\.x).min()!, -t, accuracy: 1e-9)
    XCTAssertEqual(outer.map(\.x).max()!, 4 + t, accuracy: 1e-9)
    XCTAssertEqual(outer.map(\.y).min()!, -3 - t, accuracy: 1e-9)
    XCTAssertEqual(outer.map(\.y).max()!, t, accuracy: 1e-9)
    XCTAssertEqual(drawing.grossAreaM2, (4 + 2 * t) * (3 + 2 * t), accuracy: 1e-9)
    // All wall pieces are one shape filled with the nonzero rule, so they paint as a union.
    let walls = shapes(drawing, .wall)
    XCTAssertEqual(walls.count, 1)
    XCTAssertFalse(walls[0].evenOdd)
    XCTAssertEqual(walls[0].fill, DrawingColor(0.36, 0.37, 0.42))
  }

  func testDoorsAndWindowsCutTheirWall() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let drawing = try drawing(capture.model)
    let pieces = drawing.walls.pieces
    XCTAssertEqual(
      drawing.walls.gaps.count, capture.model.doors.count + capture.model.windows.count)
    for gap in drawing.walls.gaps {
      XCTAssertNotNil(gap.segment, "\(gap.opening.id) lies on a wall band")
      let middle = (gap.a + gap.b) * 0.5 + gap.normal * ((gap.lo + gap.hi) / 2)
      XCTAssertFalse(covered(middle, by: pieces), "\(gap.opening.id) cuts its band")
      // Wall stays just beyond each side of the opening.
      let along = (gap.b - gap.a).unit
      for end in [gap.a - along * 0.05, gap.b + along * 0.05] {
        XCTAssertTrue(covered(end + gap.normal * ((gap.lo + gap.hi) / 2), by: pieces))
      }
      XCTAssertEqual(gap.a.distance(to: gap.b), gap.opening.widthM, accuracy: 1e-9)
    }
    // A window is drawn as two glass lines between the wall's two faces.
    let window = try XCTUnwrap(shapes(drawing, .window).first)
    let moves = window.path.elements.filter {
      if case .move = $0 { return true } else { return false }
    }
    XCTAssertEqual(moves.count, 4 * capture.model.windows.count)
  }

  func testInteriorWallIsCentredOnTheSharedEdge() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let drawing = try drawing(capture.model)
    let interior = drawing.walls.segments.filter { $0.kind == .interior }
    XCTAssertEqual(interior.count, 1)
    let wall = try XCTUnwrap(interior.first)
    XCTAssertEqual(wall.lo, -drawing.options.interiorWallThicknessM / 2, accuracy: 1e-12)
    XCTAssertEqual(wall.hi, drawing.options.interiorWallThicknessM / 2, accuracy: 1e-12)
    // On the partition between the two rooms (x = 5 in the fixture).
    XCTAssertEqual(wall.a.x, 5, accuracy: 1e-6)
    XCTAssertEqual(wall.b.x, 5, accuracy: 1e-6)
    XCTAssertEqual(drawing.walls.loops.count, 1, "one outline around both rooms")
  }

  func testRoomsWithoutAWallBetweenThemAreOpenToEachOther() throws {
    // Two rooms side by side; the walls only run round the outside.
    func model(partition: Bool) -> CaptureModel {
      var model = Synthetic.room(width: 6, length: 3)
      let left = [(0.0, 0.0), (0.0, 3.0), (3.0, 3.0), (3.0, 0.0)].map {
        Vec3(x: $0.0, y: 0, z: $0.1)
      }
      let right = [(3.0, 0.0), (3.0, 3.0), (6.0, 3.0), (6.0, 0.0)].map {
        Vec3(x: $0.0, y: 0, z: $0.1)
      }
      model.rooms = [
        CaptureModel.Room(
          id: "room-1", label: "Kitchen", polygon: left, heightM: 2.7, type: .kitchen,
          typeSource: .operator),
        CaptureModel.Room(
          id: "room-2", label: "Living Room", polygon: right, heightM: 2.7, type: .livingRoom,
          typeSource: .operator),
      ]
      if partition {
        model.walls.append(
          CaptureModel.Wall(
            id: "wall-p", start: Vec3(x: 3, y: 0, z: 0.3), end: Vec3(x: 3, y: 0, z: 2.6),
            heightM: 2.7,
            thicknessM: 0))
      }
      return model
    }
    let open = try drawing(model(partition: false))
    XCTAssertTrue(open.walls.segments.allSatisfy { $0.kind == .exterior })
    XCTAssertFalse(covered(Point2(x: 3, y: -1.5), by: open.walls.pieces))
    // A partition stopping 0.3 m and 0.4 m short of the outside walls is carried to them.
    let closed = try drawing(model(partition: true))
    let interior = closed.walls.segments.filter { $0.kind == .interior }
    XCTAssertEqual(interior.count, 1)
    XCTAssertTrue(covered(Point2(x: 3, y: -1.5), by: closed.walls.pieces))
    XCTAssertTrue(covered(Point2(x: 3, y: -0.05), by: closed.walls.pieces))
    XCTAssertTrue(covered(Point2(x: 3, y: -2.95), by: closed.walls.pieces))
  }

  func testDoorSwingsIntoTheRoomItBelongsTo() throws {
    // A door in the partition between a hall and a bathroom swings into the bathroom; the
    // arc runs from the open leaf to the far jamb.
    var model = Synthetic.room(width: 6, length: 3)
    let left = [(0.0, 0.0), (0.0, 3.0), (3.0, 3.0), (3.0, 0.0)].map { Vec3(x: $0.0, y: 0, z: $0.1) }
    let right = [(3.0, 0.0), (3.0, 3.0), (6.0, 3.0), (6.0, 0.0)].map {
      Vec3(x: $0.0, y: 0, z: $0.1)
    }
    for (rooms, inside) in [
      ((RoomType.hallway, RoomType.bathroom), 4.0), ((.bathroom, .hallway), 2.0),
    ] {
      model.rooms = [
        CaptureModel.Room(
          id: "room-1", label: "A", polygon: left, heightM: 2.7, type: rooms.0,
          typeSource: .operator),
        CaptureModel.Room(
          id: "room-2", label: "B", polygon: right, heightM: 2.7, type: rooms.1,
          typeSource: .operator),
      ]
      model.walls =
        Array(model.walls.prefix(4)) + [
          CaptureModel.Wall(
            id: "wall-p", start: Vec3(x: 3, y: 0, z: 0), end: Vec3(x: 3, y: 0, z: 3), heightM: 2.7,
            thicknessM: 0)
        ]
      model.doors = [
        CaptureModel.WallOpening(
          id: "door-1", wallId: "wall-p", offsetM: 1.5, bottomM: 0, widthM: 0.8, heightM: 2)
      ]
      let drawing = try drawing(model)
      let door = try XCTUnwrap(shapes(drawing, .door).last, "swing arc")
      for p in door.path.points {
        // Plan millimetres; the bathroom is on the side of x = `inside` metres.
        XCTAssertEqual((p.x / 1000 - 3).sign, (inside - 3).sign, "swing into the bathroom")
      }
    }
  }

  // MARK: Symbols

  func testEverySymbolStaysInsideItsFootprint() throws {
    var models = try allModels()
    models.append(("every-category", Self.everyCategory()))
    for (name, model) in models {
      let drawing = try drawing(model)
      XCTAssertEqual(drawing.symbols.count, model.objects.count, name)
      for symbol in drawing.symbols {
        let footprint = symbol.footprint
        var path = symbol.outline.path
        path.append(symbol.details.path)
        XCTAssertFalse(path.elements.isEmpty)
        for p in path.points {
          let point = Point2(x: p.x / 1000, y: p.y / 1000)
          XCTAssertGreaterThanOrEqual(
            Geo.signedDistance(footprint, point), -1e-6,
            "\(name) \(symbol.objectId) \(symbol.kind) point \(point) outside its footprint")
        }
      }
    }
  }

  func testSymbolKindsFollowCategoryAndAttributes() throws {
    let drawing = try drawing(Self.everyCategory())
    let kinds = Dictionary(uniqueKeysWithValues: drawing.symbols.map { ($0.objectId, $0.kind) })
    XCTAssertEqual(kinds["bed"], "bed")
    XCTAssertEqual(kinds["sofa"], "sofa")
    XCTAssertEqual(kinds["armchair"], "armchair")
    XCTAssertEqual(kinds["chair"], "chair")
    XCTAssertEqual(kinds["arm-chair"], "armchair")
    XCTAssertEqual(kinds["stool"], "stool")
    XCTAssertEqual(kinds["table"], "table")
    XCTAssertEqual(kinds["round-table"], "round-table")
    XCTAssertEqual(kinds["cabinet"], "cabinet")
    XCTAssertEqual(kinds["shelf"], "shelf")
    for category in [
      "toilet", "bathtub", "sink", "stove", "oven", "refrigerator", "dishwasher", "television",
      "fireplace", "stairs",
    ] {
      XCTAssertEqual(kinds[category], category)
    }
    XCTAssertEqual(kinds["washer"], "washer-dryer")
    XCTAssertEqual(kinds["other"], "other")
  }

  func testSymbolBacksFaceTheNearestWall() throws {
    let drawing = try drawing(Self.everyCategory())
    let backs = Dictionary(uniqueKeysWithValues: drawing.symbols.map { ($0.objectId, $0.back) })
    // Room x 0...8, plan y -6...0 (z 0...6). The bed's head is at the top wall (plan y = 0),
    // the sofa's back at the bottom wall, the toilet's tank and the stove at the left and
    // right walls.
    func assertBack(_ id: String, _ x: Double, _ y: Double, line: UInt = #line) {
      let back = backs[id]!
      XCTAssertEqual(back.x, x, accuracy: 1e-9, id, line: line)
      XCTAssertEqual(back.y, y, accuracy: 1e-9, id, line: line)
    }
    assertBack("bed", 0, 1)
    assertBack("sofa", 0, -1)
    assertBack("toilet", -1, 0)
    assertBack("stove", 1, 0)
    // A chair at a table turns its back to the table (the chair is nearer the top wall).
    assertBack("chair", 0, 1)
  }

  /// One room 8 m by 6 m with an object of every category, placed against known walls.
  static func everyCategory() -> CaptureModel {
    var model = Synthetic.room(width: 8, length: 6, label: "Room")
    func object(
      _ id: String, _ category: ObjectCategory, x: Double, z: Double, size: (Double, Double),
      turned: Bool = false, attributes: [String: String]? = nil
    ) -> CaptureModel.DetectedObject {
      let half = (2.0).squareRoot() / 2
      return CaptureModel.DetectedObject(
        id: id, category: category,
        box: CaptureModel.OrientedBox(
          center: Vec3(x: x, y: 0.4, z: z), sizeM: Vec3(x: size.0, y: 0.8, z: size.1),
          rotation: turned ? Quaternion(x: 0, y: half, z: 0, w: half) : .identity),
        attributes: attributes)
    }
    model.objects = [
      // Bed 1.6 wide, 2.0 long, head against the wall at z = 0 (plan y = 0).
      object("bed", .bed, x: 1.2, z: 1.05, size: (1.6, 2.0)),
      // Sofa against the wall at z = 6 (plan y = -6).
      object("sofa", .sofa, x: 4, z: 5.5, size: (2.2, 0.9)),
      object(
        "armchair", .sofa, x: 6.6, z: 5.5, size: (0.9, 0.9),
        attributes: ["SofaType": "singleSeat"]),
      // Toilet against the wall at x = 0, tank on the wall: 0.4 across, 0.7 deep (along x).
      object("toilet", .toilet, x: 0.4, z: 3.5, size: (0.7, 0.4)),
      // Stove against the wall at x = 8.
      object("stove", .stove, x: 7.7, z: 3.0, size: (0.6, 0.76)),
      object("table", .table, x: 4, z: 2.5, size: (1.4, 0.9)),
      // Chair just in front of the table (towards z = 0).
      object("chair", .chair, x: 4, z: 1.6, size: (0.45, 0.45)),
      object(
        "arm-chair", .chair, x: 5.8, z: 1.0, size: (0.7, 0.7),
        attributes: ["ChairArmType": "existing"]),
      object("stool", .chair, x: 2.6, z: 3.0, size: (0.4, 0.4), attributes: ["ChairType": "stool"]),
      object(
        "round-table", .table, x: 2.6, z: 4.2, size: (0.9, 0.9),
        attributes: ["TableShapeType": "circularElliptic"]),
      object(
        "cabinet", .storage, x: 7.75, z: 1.2, size: (0.5, 1.2),
        attributes: ["StorageType": "cabinet"]),
      object(
        "shelf", .storage, x: 7.8, z: 5.0, size: (1.0, 0.35), turned: true,
        attributes: ["StorageType": "shelf"]),
      object("bathtub", .bathtub, x: 0.4, z: 5.0, size: (0.75, 1.6)),
      object("sink", .sink, x: 1.5, z: 5.75, size: (0.6, 0.45)),
      object("oven", .oven, x: 6.5, z: 0.35, size: (0.6, 0.6)),
      object("refrigerator", .refrigerator, x: 5.0, z: 0.4, size: (0.9, 0.75)),
      object("dishwasher", .dishwasher, x: 3.0, z: 0.35, size: (0.6, 0.6)),
      object("washer", .washerDryer, x: 6.0, z: 4.2, size: (0.6, 0.6)),
      object("television", .television, x: 4.0, z: 0.05, size: (1.2, 0.08)),
      object("fireplace", .fireplace, x: 2.6, z: 0.3, size: (1.2, 0.5)),
      object("stairs", .stairs, x: 5.5, z: 3.0, size: (0.9, 2.4)),
      object("other", .other, x: 6.6, z: 2.4, size: (0.4, 0.4)),
    ]
    return model
  }

  // MARK: Fills, labels and dimensions

  func testRoomFillsByType() throws {
    var model = Synthetic.room(width: 4, length: 3)
    var fills: [DrawingColor] = []
    for type in RoomType.allCases {
      model.rooms[0].type = type
      model.rooms[0].typeSource = .operator
      let fill = try XCTUnwrap(shapes(try drawing(model), .roomFill).first?.fill)
      XCTAssertEqual(fill, FloorPlanStyle.roomFill(type))
      // Subtle: every fill is light.
      XCTAssertGreaterThan(min(fill.red, fill.green, fill.blue), 0.9)
      fills.append(fill)
    }
    for (type, other) in [
      (RoomType.bedroom, RoomType.livingRoom), (.kitchen, .bathroom), (.closet, .hallway),
    ] {
      XCTAssertNotEqual(FloorPlanStyle.roomFill(type), FloorPlanStyle.roomFill(other))
    }
    // Older models without a type: from the label.
    model.rooms[0].type = nil
    model.rooms[0].typeSource = nil
    model.rooms[0].label = "Bedroom 2"
    XCTAssertEqual(
      shapes(try drawing(model), .roomFill).first?.fill, FloorPlanStyle.roomFill(.bedroom))
  }

  func testNoLabelOverlapsAnotherLabelASymbolOrAWall() throws {
    for (name, model) in try allModels() {
      for scale in [50.0, 100.0] {
        let drawing = try drawing(model) {
          $0.scaleDenominator = scale
          $0.northDegrees = 20
        }
        let boxes = texts(drawing).map {
          (text: $0.string, corners: FloorPlanDrawing.textCorners($0))
        }
        XCTAssertFalse(boxes.isEmpty)
        for i in boxes.indices {
          for j in boxes.indices where j > i {
            XCTAssertFalse(
              Geo.convexOverlap(boxes[i].corners, boxes[j].corners),
              "\(name) 1:\(scale): '\(boxes[i].text)' overlaps '\(boxes[j].text)'")
          }
        }
        for label in drawing.labels where label.kind != .room && label.kind != .compass {
          for symbol in drawing.symbols {
            XCTAssertFalse(
              label.box.overlaps(convex: symbol.footprint),
              "\(name) 1:\(scale): '\(label.text)' overlaps \(symbol.kind)")
          }
          for piece in drawing.walls.pieces {
            XCTAssertFalse(
              label.box.overlaps(convex: piece), "\(name) 1:\(scale): '\(label.text)' on a wall")
          }
        }
        // Room names sit inside their rooms.
        for room in drawing.rooms {
          let label = try XCTUnwrap(
            drawing.labels.first { $0.roomId == room.id && $0.kind == .room })
          XCTAssertTrue(label.box.isInside(room.polygon), "\(name) \(room.label)")
        }
      }
    }
  }

  func testEveryOuterWallSegmentIsDimensioned() throws {
    for (name, model) in try allModels() {
      for scale in [50.0, 100.0] {
        let drawing = try drawing(model) { $0.scaleDenominator = scale }
        let segments = drawing.walls.loops.map(\.segments.count).reduce(0, +)
        XCTAssertGreaterThanOrEqual(segments, 4, name)
        XCTAssertEqual(drawing.exteriorDimensions.count, segments, "\(name) 1:\(scale)")
        let shown = Set(texts(drawing).filter { $0.layer == .exteriorDimension }.map(\.string))
        for dimension in drawing.exteriorDimensions {
          XCTAssertTrue(shown.contains(dimension.label))
          XCTAssertFalse(
            dimension.crowded, "\(name) 1:\(scale): \(dimension.label) found no free place")
        }
      }
    }
  }

  func testOutsideDimensionsMeasureTheOutsideFaces() throws {
    let drawing = try drawing(Synthetic.room(width: 4, length: 3))
    let t = drawing.options.exteriorWallThicknessM
    let lengths = drawing.exteriorDimensions.map(\.lengthM).sorted()
    XCTAssertEqual(lengths.count, 4)
    XCTAssertEqual(lengths[0], 3 + 2 * t, accuracy: 1e-9)
    XCTAssertEqual(lengths[3], 4 + 2 * t, accuracy: 1e-9)
    // 4 m + 12 in = 14' 1.5" (to a tenth of an inch); inside, 13' 1.5".
    let shown = texts(drawing)
    XCTAssertTrue(shown.contains { $0.string == "14' 1.5\"" && $0.layer == .exteriorDimension })
    XCTAssertTrue(shown.contains { $0.string == "13' 1.5\"" && $0.layer == .interiorDimension })
    XCTAssertTrue(shown.contains { $0.string == "Room" && $0.layer == .roomLabel })
    XCTAssertTrue(shown.contains { $0.string == "129.2 ft\u{00B2}" && $0.layer == .roomLabel })
    // Inside dimensions in light purple, outside ones in ink.
    let inside = try XCTUnwrap(shown.first { $0.layer == .interiorDimension })
    XCTAssertGreaterThan(inside.color.blue, inside.color.red + 0.2)
    let outside = try XCTUnwrap(shown.first { $0.layer == .exteriorDimension })
    XCTAssertEqual(outside.color, DrawingColor(hex: 0x1F2429))
  }

  func testLabelsUseTheSharedUnitFormatter() throws {
    let model = Synthetic.room(width: 4, length: 3)
    // Metric: lengths in metres and areas in square metres, both to two decimals.
    let metric = texts(try drawing(model) { $0.units = UnitFormatter(system: .metric) })
    XCTAssertTrue(metric.contains { $0.string == "4.30 m" && $0.layer == .exteriorDimension })
    XCTAssertTrue(metric.contains { $0.string == "4.00 m" && $0.layer == .interiorDimension })
    XCTAssertTrue(metric.contains { $0.string == "12.00 m\u{00B2}" && $0.layer == .roomLabel })
    // Whole feet-inches for lengths; areas stay square feet to one decimal.
    let feetInches = UnitFormatter(system: .imperial, lengthStyle: .feetInches)
    let whole = texts(try drawing(model) { $0.units = feetInches })
    XCTAssertTrue(whole.contains { $0.string == "14' 1\"" && $0.layer == .exteriorDimension })
    XCTAssertTrue(whole.contains { $0.string == "13' 1\"" && $0.layer == .interiorDimension })
    XCTAssertTrue(whole.contains { $0.string == "129.2 ft\u{00B2}" && $0.layer == .roomLabel })
  }

  func testScaleBarInFeetOrMetres() throws {
    let model = Synthetic.room(width: 4, length: 3)
    let feet = texts(try drawing(model)).filter { $0.layer == .scaleBar }.map(\.string)
    XCTAssertEqual(feet, ["3 ft"])
    let metric = UnitFormatter(system: .metric)
    let metres = texts(try drawing(model) { $0.units = metric }).filter { $0.layer == .scaleBar }
    XCTAssertEqual(metres.map(\.string), ["1 m"])
    XCTAssertEqual(
      texts(try drawing(model) { $0.scaleBar = false }).filter { $0.layer == .scaleBar }.count, 0)
    // The bar is as long as it says: 3 ft = 914.4 plan millimetres.
    let bar = try XCTUnwrap(shapes(try drawing(model), .scaleBar).first)
    let xs = bar.path.points.map(\.x)
    XCTAssertEqual(xs.max()! - xs.min()!, 914.4, accuracy: 1e-6)
  }

  func testCompassOnlyWhenNorthIsKnown() throws {
    let model = Synthetic.room(width: 4, length: 3)
    let unknown = try drawing(model)
    XCTAssertFalse(unknown.hasCompass)
    XCTAssertTrue(
      unknown.items.allSatisfy {
        if case .shape(let s) = $0 { return s.layer != .compass }
        if case .text(let t) = $0 { return t.layer != .compass }
        return true
      })
    for north in [0.0, 90.0] {
      let known = try drawing(model) { $0.northDegrees = north }
      XCTAssertTrue(known.hasCompass)
      let letter = try XCTUnwrap(texts(known).first { $0.layer == .compass })
      XCTAssertEqual(letter.string, "N")
      // The N is past the rose's tip in the north direction (counter-clockwise from up).
      let ring = try XCTUnwrap(shapes(known, .compass).first)
      let xs = ring.path.points.map(\.x)
      let ys = ring.path.points.map(\.y)
      let center = Point2(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
      let direction = (Point2(x: letter.position.x, y: letter.position.y) - center).unit
      let expected = Point2(x: 0, y: 1).rotated(by: north * .pi / 180)
      XCTAssertGreaterThan(direction.dot(expected), 0.95, "north \(north)")
    }
  }

  func testWalkThroughApartment() throws {
    let model = WalkthroughFixture.model
    XCTAssertEqual(model.rooms.count, 7)
    let drawing = try drawing(model) { $0.scaleDenominator = 75 }
    // The plan is squared to the sheet (the fixture is turned 14.2 degrees in its frame).
    XCTAssertEqual(abs(drawing.rotationDegrees), 14.2, accuracy: 0.5)
    XCTAssertGreaterThanOrEqual(drawing.walls.segments.filter { $0.kind == .interior }.count, 6)
    XCTAssertEqual(drawing.walls.loops.filter(\.closed).count, 1)
    // The living room and the kitchen share an edge with no wall on it: open plan.
    let living = try XCTUnwrap(drawing.rooms.first { $0.type == .livingRoom })
    let kitchen = try XCTUnwrap(drawing.rooms.first { $0.type == .kitchen })
    var openEdge = false
    for i in living.polygon.indices {
      let a = living.polygon[i]
      let b = living.polygon[(i + 1) % living.polygon.count]
      let middle = (a + b) * 0.5
      guard PlanGeometry.distanceToBoundary(of: kitchen.polygon, from: middle) < 0.01 else {
        continue
      }
      openEdge = openEdge || !covered(middle, by: drawing.walls.pieces)
    }
    XCTAssertTrue(openEdge)
    // Every door has a leaf and a swing; the gross area is more than the rooms' floor area.
    XCTAssertEqual(drawing.walls.gaps.filter { $0.opening.kind == .door }.count, 5)
    XCTAssertGreaterThan(drawing.grossAreaM2, drawing.roomAreaM2)
    XCTAssertLessThan(drawing.grossAreaM2, drawing.roomAreaM2 * 1.2)
    try Repo.write(
      ExportedFile(
        fileName: "floor-plan-drawing.svg", role: .planSVG, mime: "image/svg+xml",
        data: Data(drawing.svg(title: "Apartment").utf8)), folder: "apartment-walkthrough")
  }

  // MARK: Writers

  func testSVGIsWellFormedAndLayered() throws {
    let drawing = try drawing(WalkthroughFixture.model) { $0.northDegrees = 10 }
    let svg = drawing.svg(title: "Apartment & plan")
    let parser = XMLParser(data: Data(svg.utf8))
    XCTAssertTrue(parser.parse(), "well-formed")
    for layer in [
      DrawingLayer.roomFill, .symbol, .wall, .door, .window, .interiorDimension, .exteriorDimension,
      .roomLabel, .compass, .scaleBar,
    ] {
      XCTAssertTrue(svg.contains("<g class=\"\(layer.rawValue)\">"), layer.rawValue)
    }
    XCTAssertTrue(svg.contains("Apartment &amp; plan"))
    XCTAssertTrue(svg.contains("fill=\"#5c5e6b\""), "slate walls")
    XCTAssertTrue(svg.contains(">Living Room</text>"))
    // Printed size: plan millimetres over the scale.
    XCTAssertTrue(svg.contains("width=\"\(Format.fixed(drawing.bounds.width / 50, 2))mm\""))
  }

  func testDrawingAndWritersAreByteStable() throws {
    let model = WalkthroughFixture.model
    let first = try drawing(model) { $0.northDegrees = 33 }
    let second = try drawing(model) { $0.northDegrees = 33 }
    XCTAssertEqual(first.items, second.items)
    XCTAssertEqual(first.svg(title: "a"), second.svg(title: "a"))
    XCTAssertEqual(first.pdf(title: "a"), second.pdf(title: "a"))
  }

  func testSVGStartsAtTheViewBoxOrigin() throws {
    // Coordinates are moved so the drawing's lower-left corner is the view box origin.
    let drawing = try drawing(WalkthroughFixture.model)
    let svg = drawing.svg(title: "a")
    var numbers: [Double] = []
    for match in svg.split(separator: "\"") where match.first == "M" {
      let tokens = match.split(whereSeparator: { " MLCZ".contains($0) })
      numbers += tokens.compactMap { Double($0) }
    }
    XCTAssertFalse(numbers.isEmpty)
    let side = max(drawing.bounds.width, drawing.bounds.height)
    XCTAssertGreaterThanOrEqual(numbers.min() ?? -1, -0.01)
    XCTAssertLessThanOrEqual(numbers.max() ?? .infinity, side + 0.01)
  }
}
