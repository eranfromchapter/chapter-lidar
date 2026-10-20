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
    XCTAssertEqual(walls[0].fill, ChapterBrand.wall)
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
    // A window is a white frame inside the wall thickness, outlined in the light symbol grey,
    // with a heavier glass line along its middle; nothing of it runs past the wall faces.
    let windows = shapes(drawing, .window)
    XCTAssertEqual(windows.count, 2)
    func moves(_ shape: DrawingShape) -> Int {
      shape.path.elements.filter {
        if case .move = $0 { return true } else { return false }
      }.count
    }
    XCTAssertEqual(moves(windows[0]), capture.model.windows.count)
    XCTAssertEqual(windows[0].fill, .white)
    XCTAssertEqual(windows[0].stroke?.color, drawing.style.symbol)
    XCTAssertEqual(moves(windows[1]), capture.model.windows.count)
    XCTAssertEqual(windows[1].stroke?.color, drawing.style.wall)
    XCTAssertGreaterThan(windows[1].stroke!.width, windows[0].stroke!.width)
    let windowGaps = drawing.walls.gaps.filter { $0.opening.kind == .window }
    for p in windows.flatMap(\.path.points) {
      let point = Point2(x: p.x / 1000, y: p.y / 1000)
      XCTAssertTrue(
        windowGaps.contains { gap in
          let offset = (point - gap.a).dot(gap.normal)
          return offset >= gap.lo - 1e-6 && offset <= gap.hi + 1e-6
        }, "window line past the wall face")
    }
    // A door has a jamb line at each end, a little past both wall faces, drawn under the walls
    // so it never crosses one; its open leaf is a white panel outlined in the wall colour.
    let doorGaps = drawing.walls.gaps.filter { $0.opening.kind != .window }
    let jambs = try XCTUnwrap(shapes(drawing, .opening).first)
    XCTAssertEqual(moves(jambs), 2 * doorGaps.count)
    let jambIndex = try XCTUnwrap(drawing.items.firstIndex { $0 == .shape(jambs) })
    let wallIndex = try XCTUnwrap(
      drawing.items.firstIndex {
        if case .shape(let shape) = $0 { return shape.layer == .wall }
        return false
      })
    XCTAssertLessThan(jambIndex, wallIndex)
    let leaf = try XCTUnwrap(shapes(drawing, .door).first)
    XCTAssertEqual(leaf.fill, .white)
    XCTAssertEqual(leaf.stroke?.color, drawing.style.wall)
  }

  func testAnOpeningWiderThanItsWallStopsAtTheWallsThatMeetIt() throws {
    // A 1 m corridor between two rooms, its end a door scanned the full 1 m wide: the cut
    // stops at the faces of the partitions either side, so they keep their ends and the
    // jambs are straight, not stepped.
    let model = Synthetic.rooms(
      [
        ("Bedroom", .bedroom, [(0, 0), (0, 3), (2, 3), (2, 0)]),
        ("Hallway", .hallway, [(2, 0), (2, 3), (3, 3), (3, 0)]),
        ("Bathroom", .bathroom, [(3, 0), (3, 3), (5, 3), (5, 0)]),
      ], door: (from: (2, 3), to: (3, 3)))
    let drawing = try drawing(model) { $0.alignToWalls = false }
    let gap = try XCTUnwrap(drawing.walls.gaps.first { $0.opening.kind == .door })
    XCTAssertEqual(
      gap.a.distance(to: gap.b), 1 - drawing.options.interiorWallThicknessM, accuracy: 1e-6)
    // Wall right beside each jamb, across the whole thickness: no notch.
    let along = (gap.b - gap.a).unit
    for end in [gap.a - along * 0.01, gap.b + along * 0.01] {
      for offset in [gap.lo + 0.01, (gap.lo + gap.hi) / 2, gap.hi - 0.01] {
        XCTAssertTrue(covered(end + gap.normal * offset, by: drawing.walls.pieces))
      }
    }
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
      // Subtle: every fill is a light Chapter tint.
      XCTAssertGreaterThan(min(fill.red, fill.green, fill.blue), 0.85)
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
        // Room names and inside dimensions may sit over furniture (on a patch of the room's
        // colour); outside dimensions and the scale bar stay clear of it. None is on a wall.
        for label in drawing.labels where label.kind != .room && label.kind != .compass {
          for symbol in drawing.symbols where label.kind != .interiorDimension {
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

  func testOuterWallsAreDimensionedWithoutClashes() throws {
    for (name, model) in try allModels() {
      for scale in [50.0, 100.0] {
        let drawing = try drawing(model) { $0.scaleDenominator = scale }
        let style = drawing.style
        XCTAssertGreaterThanOrEqual(drawing.exteriorDimensions.count, 2, name)
        // Every run of a metre and a quarter or more has its dimension (the far side of a
        // plain rectangle once), none under two feet has, and a long run stands next to its
        // own wall.
        let layout = AnnotationLayout(
          style: style, units: drawing.options.units, scaleDenominator: scale, symbols: [],
          building: [], wallPieces: [])
        let items = layout.exteriorItems(walls: drawing.walls, minimum: style.exteriorMinimumM)
        for item in items where item.length >= style.exteriorOptionalM + 1e-6 {
          let shown = drawing.exteriorDimensions.filter {
            $0.loop == item.loop && $0.run == item.run
          }
          XCTAssertFalse(shown.isEmpty, "\(name) 1:\(scale): run of \(item.length) m")
          XCTAssertEqual(
            shown.map(\.lengthM).reduce(0, +), item.length, accuracy: 1e-6,
            "\(name): the pieces of a run add up to it")
          if item.length >= 2 {
            XCTAssertTrue(shown.allSatisfy { $0.tier <= 2 }, "\(name): \(shown.map(\.label))")
          }
        }
        for dimension in drawing.exteriorDimensions where !dimension.overall {
          XCTAssertGreaterThanOrEqual(dimension.lengthM, style.exteriorMinimumM - 1e-9, name)
        }
        // Each in a free place: no label covered, no line crossing another dimension's.
        let shown = Set(texts(drawing).filter { $0.layer == .exteriorDimension }.map(\.string))
        for dimension in drawing.exteriorDimensions {
          XCTAssertTrue(shown.contains(dimension.label))
          XCTAssertFalse(
            dimension.crowded, "\(name) 1:\(scale): \(dimension.label) found no free place")
        }
      }
    }
  }

  func testOutsideChainsBreakWherePartitionsMeetTheOutsideWall() throws {
    // Two rooms side by side, 4 m and 2.5 m, under one 6.5 m outside wall: the wall's
    // dimension is a chain of the two rooms' lengths, to the partition's centre line, each
    // next to its own wall. The far side, the same chain, is given once.
    let drawing = try drawing(Synthetic.twoRooms(widths: [4, 2.5], length: 3)) {
      $0.alignToWalls = false
    }
    let t = drawing.options.exteriorWallThicknessM
    let pieces = drawing.exteriorDimensions.filter { !$0.overall }
    let depth = 3 + 2 * t
    let along = pieces.map(\.lengthM).filter { $0 > 2 && $0 < 5 && abs($0 - depth) > 0.01 }
      .sorted()
    XCTAssertEqual(along.count, 2, "\(pieces.map(\.label))")
    XCTAssertEqual(along[0], 2.5 + t, accuracy: 1e-6)
    XCTAssertEqual(along[1], 4 + t, accuracy: 1e-6)
    XCTAssertTrue(pieces.allSatisfy { $0.tier == 1 }, "\(pieces.map(\.tier))")
    // The overall width once, outside the chain.
    let overall = drawing.exteriorDimensions.filter(\.overall)
    XCTAssertEqual(overall.map(\.lengthM), [6.5 + 2 * t])
    let chain = try XCTUnwrap(pieces.first { abs($0.lengthM - (4 + t)) < 1e-6 })
    XCTAssertEqual(overall.first?.side, chain.side)
    XCTAssertGreaterThan(overall.first?.position ?? 0, chain.position)
  }

  func testShortStepsAndTheSecondSideOfABayGetNoDimension() throws {
    // A 6 m by 4 m room with a 10 cm step in one wall and a bay 0.9 m deep in another.
    var model = Synthetic.room(width: 6, length: 4)
    let outline = [
      (0.0, 0.0), (0.0, 4.0), (2.0, 4.0), (2.0, 4.9), (4.0, 4.9), (4.0, 4.0), (6.0, 4.0),
      (6.0, 0.0), (3.0, 0.0), (3.0, 0.1), (0.0, 0.1),
    ]
    model.rooms[0].polygon = outline.map { Vec3(x: $0.0, y: 0, z: $0.1) }
    model.walls = []
    for index in outline.indices {
      let a = outline[index]
      let b = outline[(index + 1) % outline.count]
      model.walls.append(
        CaptureModel.Wall(
          id: "w\(index)", start: Vec3(x: a.0, y: 0, z: a.1), end: Vec3(x: b.0, y: 0, z: b.1),
          heightM: 2.7, thicknessM: 0))
    }
    let drawing = try drawing(model) { $0.alignToWalls = false }
    let labels = drawing.exteriorDimensions.map(\.label)
    // The 10 cm step has none, nor any "0'" length; the bay's depth is given once.
    XCTAssertFalse(labels.contains { $0.hasPrefix("0' ") || $0 == "3.9\"" }, "\(labels)")
    XCTAssertEqual(labels.filter { $0 == "2' 11.4\"" }.count, 1, "\(labels)")
    XCTAssertFalse(drawing.exteriorDimensions.contains(where: \.crowded))
  }

  func testOutsideDimensionsMeasureTheOutsideFaces() throws {
    let drawing = try drawing(Synthetic.room(width: 4, length: 3))
    let t = drawing.options.exteriorWallThicknessM
    // The far sides of a plain rectangle repeat these and are left out.
    let lengths = drawing.exteriorDimensions.map(\.lengthM).sorted()
    XCTAssertEqual(lengths.count, 2)
    XCTAssertEqual(lengths[0], 3 + 2 * t, accuracy: 1e-9)
    XCTAssertEqual(lengths[1], 4 + 2 * t, accuracy: 1e-9)
    // 4 m + 12 in = 14' 1.5" (to a tenth of an inch); inside, 13' 1.5".
    let shown = texts(drawing)
    XCTAssertTrue(shown.contains { $0.string == "14' 1.5\"" && $0.layer == .exteriorDimension })
    XCTAssertTrue(shown.contains { $0.string == "13' 1.5\"" && $0.layer == .interiorDimension })
    XCTAssertTrue(shown.contains { $0.string == "Room" && $0.layer == .roomLabel })
    XCTAssertTrue(shown.contains { $0.string == "129 ft\u{00B2}" && $0.layer == .roomLabel })
    // Inside dimensions in the Chapter bronze, outside ones in the brand black.
    let inside = try XCTUnwrap(shown.first { $0.layer == .interiorDimension })
    XCTAssertEqual(inside.color, ChapterBrand.accent)
    let outside = try XCTUnwrap(shown.first { $0.layer == .exteriorDimension })
    XCTAssertEqual(outside.color, ChapterBrand.ink)
  }

  func testLabelsUseTheSharedUnitFormatter() throws {
    let model = Synthetic.room(width: 4, length: 3)
    // Metric: lengths in metres to two decimals, room areas in square metres to one.
    let metric = texts(try drawing(model) { $0.units = UnitFormatter(system: .metric) })
    XCTAssertTrue(metric.contains { $0.string == "4.30 m" && $0.layer == .exteriorDimension })
    XCTAssertTrue(metric.contains { $0.string == "4.00 m" && $0.layer == .interiorDimension })
    XCTAssertTrue(metric.contains { $0.string == "12.0 m\u{00B2}" && $0.layer == .roomLabel })
    // Whole feet-inches for lengths; room areas in whole square feet from 100 ft².
    let feetInches = UnitFormatter(system: .imperial, lengthStyle: .feetInches)
    let whole = texts(try drawing(model) { $0.units = feetInches })
    XCTAssertTrue(whole.contains { $0.string == "14' 1\"" && $0.layer == .exteriorDimension })
    XCTAssertTrue(whole.contains { $0.string == "13' 1\"" && $0.layer == .interiorDimension })
    XCTAssertTrue(whole.contains { $0.string == "129 ft\u{00B2}" && $0.layer == .roomLabel })
  }

  func testPlanDimensionAndRoomAreaFormats() {
    let imperial = UnitFormatter(system: .imperial)
    let metric = UnitFormatter(system: .metric)
    // Under a foot in inches alone; a foot and more in feet-inches.
    XCTAssertEqual(imperial.dimension(5.1 * 0.0254), "5.1\"")
    XCTAssertEqual(imperial.dimension(11.96 * 0.0254), "1' 0.0\"")
    XCTAssertEqual(imperial.dimension(25.0 * 0.0254), "2' 1.0\"")
    XCTAssertEqual(UnitFormatter(system: .imperial, lengthStyle: .feetInches).dimension(0.2), "8\"")
    XCTAssertEqual(metric.dimension(0.13), "0.13 m")
    // Whole square feet from 100 ft², one decimal below; square metres to one decimal.
    let foot = UnitFormatter.squareMetresPerSquareFoot
    XCTAssertEqual(imperial.roomArea(192.4 * foot), "192 ft\u{00B2}")
    XCTAssertEqual(imperial.roomArea(99.96 * foot), "100 ft\u{00B2}")
    XCTAssertEqual(imperial.roomArea(43.84 * foot), "43.8 ft\u{00B2}")
    XCTAssertEqual(metric.roomArea(18.48), "18.5 m\u{00B2}")
    XCTAssertEqual(metric.roomArea(.nan), "-")
  }

  // MARK: Squaring

  func testWallsAFewDegreesOffAreSquaredAndTrueDiagonalsKept() throws {
    // A room whose far wall runs 2 degrees off, and one with a 45 degree corner.
    var tilted = Synthetic.room(width: 4, length: 3)
    tilted.rooms[0].polygon = [(0.0, 0.0), (0.0, 3.0), (4.0, 3.14), (4.0, 0.0)].map {
      Vec3(x: $0.0, y: 0, z: $0.1)
    }
    let squared = try drawing(tilted)
    let room = try XCTUnwrap(squared.rooms.first)
    for i in room.polygon.indices {
      let d = room.polygon[(i + 1) % room.polygon.count] - room.polygon[i]
      XCTAssertLessThan(min(abs(d.x), abs(d.y)), 1e-9, "edge \(i) runs along an axis")
    }
    XCTAssertEqual(PlanGeometry.area(of: room.polygon), 12.28, accuracy: 0.1)
    var cut = Synthetic.room(width: 4, length: 3)
    cut.rooms[0].polygon = [(0.0, 0.0), (0.0, 3.0), (3.0, 3.0), (4.0, 2.0), (4.0, 0.0)].map {
      Vec3(x: $0.0, y: 0, z: $0.1)
    }
    let kept = try XCTUnwrap(try drawing(cut).rooms.first)
    XCTAssertEqual(kept.polygon.count, 5)
    XCTAssertEqual(PlanGeometry.area(of: kept.polygon), 11.5, accuracy: 1e-6)
  }

  func testWalkThroughIsSquaredAndVerticalTextReadsUp() throws {
    let drawing = try drawing(WalkthroughFixture.model)
    for room in drawing.rooms {
      for i in room.polygon.indices {
        let d = room.polygon[(i + 1) % room.polygon.count] - room.polygon[i]
        XCTAssertLessThan(min(abs(d.x), abs(d.y)), 1e-9, "\(room.label) edge \(i)")
      }
    }
    // Text runs left to right or bottom to top (read from the right-hand edge of the sheet).
    let turned = texts(drawing).filter { $0.rotationDegrees != 0 }
    XCTAssertFalse(turned.isEmpty)
    for text in turned { XCTAssertEqual(text.rotationDegrees, 90, accuracy: 1e-9, text.string) }
    let svg = drawing.svg(title: "a")
    XCTAssertTrue(svg.contains("rotate(-90.00 "))
    XCTAssertFalse(svg.contains("rotate(90.00 "))
    // No dimension is written with a zero foot.
    XCTAssertFalse(texts(drawing).contains { $0.string.hasPrefix("0' ") })
  }

  // MARK: Doors, symbols and floor

  func testDoorSwingsDoNotCrossEachOther() throws {
    // Two doors facing each other across a 1.2 m bathroom: both would swing into it and cross.
    var model = Synthetic.room(width: 6, length: 3)
    let spans = [(0.0, 2.4, RoomType.bedroom), (2.4, 3.6, .bathroom), (3.6, 6.0, .bedroom)]
    model.rooms = spans.enumerated().map { index, span in
      CaptureModel.Room(
        id: "room-\(index)", label: "Room \(index)",
        polygon: [(span.0, 0.0), (span.0, 3.0), (span.1, 3.0), (span.1, 0.0)].map {
          Vec3(x: $0.0, y: 0, z: $0.1)
        }, heightM: 2.7, type: span.2, typeSource: .operator)
    }
    for x in [2.4, 3.6] {
      model.walls.append(
        CaptureModel.Wall(
          id: "wall-\(x)", start: Vec3(x: x, y: 0, z: 0), end: Vec3(x: x, y: 0, z: 3),
          heightM: 2.7, thicknessM: 0))
      model.doors.append(
        CaptureModel.WallOpening(
          id: "door-\(x)", wallId: "wall-\(x)", offsetM: 1.5, bottomM: 0, widthM: 0.8,
          heightM: 2))
    }
    let drawing = try drawing(model)
    let swings = FloorPlanDrawing.openingItems(
      walls: drawing.walls, wallPieces: drawing.walls.pieces, rooms: drawing.rooms, floor: [],
      symbols: [], style: drawing.style, k: 0.05
    ).swings
    XCTAssertEqual(swings.count, 2)
    XCTAssertFalse(Geo.convexOverlap(swings[0], swings[1], margin: 0.02))
  }

  func testALeafNeverLiesOnAWallFace() throws {
    // A door hard against a corner: hinged at the corner its open leaf would lie along the
    // side wall's face and vanish into it, so it is hinged at the other end.
    var model = Synthetic.room(width: 3, length: 3)
    model.doors = [
      CaptureModel.WallOpening(
        id: "door", wallId: "wall-1", offsetM: 0.45, bottomM: 0, widthM: 0.8, heightM: 2)
    ]
    let drawing = try drawing(model) { $0.alignToWalls = false }
    let gap = try XCTUnwrap(drawing.walls.gaps.first)
    let leaf = try XCTUnwrap(shapes(drawing, .door).first)
    let origin = Point2(x: 0, y: 0)
    let corner = [gap.a, gap.b].min { $0.distance(to: origin) < $1.distance(to: origin) }!
    for p in leaf.path.points {
      let point = Point2(x: p.x / 1000, y: p.y / 1000)
      XCTAssertGreaterThan(
        abs((point - corner).dot((gap.b - gap.a).unit)), 0.1, "leaf along the side wall")
    }
  }

  func testRoomNamesKeepOffFixturesAndInsideDimensionsOffSwings() throws {
    for (name, model) in try allModels() {
      let drawing = try drawing(model)
      let fixtures = drawing.symbols.filter { !$0.overhead && $0.isFixture }
      for label in drawing.labels where label.kind == .room {
        let room = drawing.rooms.first { $0.id == label.roomId }!
        // Unless the room is too small to hold its name clear of them.
        guard room.areaM2 > 6 else { continue }
        for fixture in fixtures {
          XCTAssertFalse(
            label.box.overlaps(convex: fixture.footprint),
            "\(name): \(room.label) on a \(fixture.kind)")
        }
      }
      let swings = FloorPlanDrawing.openingItems(
        walls: drawing.walls, wallPieces: drawing.walls.pieces, rooms: drawing.rooms, floor: [],
        symbols: drawing.symbols.filter { !$0.overhead }.map(\.footprint),
        style: drawing.style, k: drawing.options.scaleDenominator / 1000
      ).swings
      for label in drawing.labels where label.kind == .interiorDimension {
        for swing in swings {
          XCTAssertFalse(label.box.overlaps(convex: swing), "\(name): \(label.text) on a swing")
        }
      }
    }
  }

  func testSymbolsAreSolidAndOverheadOnesDashed() throws {
    var model = Synthetic.room(width: 4, length: 3)
    func cabinet(_ id: String, x: Double, bottom: Double, confidence: DetectionConfidence)
      -> CaptureModel.DetectedObject
    {
      CaptureModel.DetectedObject(
        id: id, category: .storage,
        box: CaptureModel.OrientedBox(
          center: Vec3(x: x, y: bottom + 0.35, z: 0.3), sizeM: Vec3(x: 1.0, y: 0.7, z: 0.6)),
        confidence: confidence, attributes: ["StorageType": "cabinet"])
    }
    model.objects = [
      cabinet("base", x: 1, bottom: 0, confidence: .high),
      cabinet("upper", x: 1, bottom: 1.45, confidence: .high),
      cabinet("faint", x: 3, bottom: 0, confidence: .low),
    ]
    let drawing = try drawing(model)
    let overhead = Dictionary(
      uniqueKeysWithValues: drawing.symbols.map { ($0.objectId, $0.overhead) })
    XCTAssertEqual(overhead, ["base": false, "upper": true, "faint": false])
    let symbols = shapes(drawing, .symbol)
    XCTAssertEqual(symbols.count, 3, "each object drawn once")
    let dashed = symbols.filter { !($0.stroke?.dash.isEmpty ?? true) }
    XCTAssertEqual(dashed.count, 1, "overhead")
    // Overhead: a light outline only, drawn after the rest. The rest: filled with the floor
    // colour, so where pieces overlap the upper one hides the lower.
    XCTAssertNil(dashed.first?.fill)
    XCTAssertEqual(dashed.first?.stroke?.color, drawing.style.faintSymbol)
    XCTAssertEqual(symbols.last, dashed.first)
    for symbol in symbols.dropLast() {
      XCTAssertEqual(symbol.fill, FloorPlanStyle.roomFill(drawing.rooms[0].type))
    }
    XCTAssertTrue(symbols.contains { $0.stroke?.color == drawing.style.faintSymbol })
  }

  func testLowerFurnitureIsDrawnFirst() throws {
    // A coffee table pushed under the front of a sofa: the sofa, taller, is drawn over it.
    var model = Synthetic.room(width: 4, length: 3)
    func object(
      _ id: String, _ category: ObjectCategory, z: Double, height: Double, depth: Double
    ) -> CaptureModel.DetectedObject {
      CaptureModel.DetectedObject(
        id: id, category: category,
        box: CaptureModel.OrientedBox(
          center: Vec3(x: 2, y: height / 2, z: z), sizeM: Vec3(x: 1.6, y: height, z: depth)),
        confidence: .high)
    }
    model.objects = [
      object("sofa", .sofa, z: 0.5, height: 0.8, depth: 0.9),
      object("table", .table, z: 1.1, height: 0.4, depth: 0.6),
    ]
    let drawing = try drawing(model)
    let tops = Dictionary(uniqueKeysWithValues: drawing.symbols.map { ($0.objectId, $0.top) })
    XCTAssertEqual(tops["sofa"] ?? 0, 0.8, accuracy: 1e-9)
    let symbols = shapes(drawing, .symbol)
    XCTAssertEqual(symbols.count, 2)
    // The table's outline reaches further from the wall than the sofa's.
    func reach(_ shape: DrawingShape) -> Double {
      let ys = shape.path.points.map(\.y)
      return ys.max()! - ys.min()!
    }
    let table = drawing.symbols.first { $0.objectId == "table" }!
    let tableDepth = Extent(table.footprint)
    XCTAssertEqual(
      reach(symbols[0]) / 1000, tableDepth.maxY - tableDepth.minY, accuracy: 0.01,
      "the table first")
  }

  func testFloorLeftOutBetweenRoomsIsFilledWhereADoorLeadsIn() throws {
    // Two rooms 0.6 m apart; a door in the first opens onto the strip between them.
    var model = Synthetic.room(width: 6.6, length: 3)
    model.rooms = [(0.0, 3.0), (3.6, 6.6)].enumerated().map { index, span in
      CaptureModel.Room(
        id: "room-\(index)", label: "Room \(index)",
        polygon: [(span.0, 0.0), (span.0, 3.0), (span.1, 3.0), (span.1, 0.0)].map {
          Vec3(x: $0.0, y: 0, z: $0.1)
        }, heightM: 2.7, type: .bedroom, typeSource: .operator)
    }
    model.walls = [
      CaptureModel.Wall(
        id: "wall-a", start: Vec3(x: 3, y: 0, z: 0), end: Vec3(x: 3, y: 0, z: 3), heightM: 2.7,
        thicknessM: 0)
    ]
    model.doors = [
      CaptureModel.WallOpening(
        id: "door", wallId: "wall-a", offsetM: 1.5, bottomM: 0, widthM: 0.8, heightM: 2)
    ]
    let plan = try drawing(model)
    let fills = shapes(plan, .roomFill)
    XCTAssertEqual(fills.count, 3, "two rooms and the strip")
    let strip = try XCTUnwrap(fills.first)
    // From the outside face of one room's wall to the other's (6 in walls, plan metres).
    let xs = strip.path.points.map { $0.x / 1000 }
    XCTAssertLessThanOrEqual(xs.min()!, 3.16)
    XCTAssertGreaterThanOrEqual(xs.max()!, 3.44)
    XCTAssertEqual(strip.fill, FloorPlanStyle.roomFill(.bedroom), "the colour of the room")
    // Its ends meet unscanned ground: a thin line across each closes the floor.
    let ys = strip.path.points.map { $0.y / 1000 }
    let closing = shapes(plan, .opening).filter {
      $0.stroke?.color == plan.style.symbol && $0.fill == nil
    }
    for y in [ys.min()!, ys.max()!] {
      XCTAssertTrue(
        closing.contains { shape in
          shape.path.points.contains { abs($0.y / 1000 - y) < 1e-6 && $0.x / 1000 > 3.1 }
        }, "closing line at \(y)")
    }
    // Without the door the strip is outside.
    model.doors = []
    XCTAssertEqual(shapes(try drawing(model), .roomFill).count, 2)
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
    XCTAssertTrue(svg.contains("fill=\"\(ChapterBrand.wall.hexString)\""), "Chapter walls")
    XCTAssertTrue(svg.contains("font-family=\"\(ChapterBrand.sansFamily)\""), "Inter")
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
