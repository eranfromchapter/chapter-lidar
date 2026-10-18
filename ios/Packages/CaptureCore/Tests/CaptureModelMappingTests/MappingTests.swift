import CaptureContract
import CaptureModelMapping
import CaptureTestSupport
import Foundation
import XCTest

/// AC1: the recorded-format fixture (RoomPlan Codable JSON) becomes a CaptureModel within 1 mm
/// of truth.json. The box room is the 4.000 x 3.000 m room.
final class MappingTests: XCTestCase {
  private let oneMillimetre = 0.001

  func testBoxRoomMatchesTruthWithinOneMillimetre() throws {
    let mapped = try mapFixture("box-room")
    let model = mapped.model
    let truth = mapped.truth

    // Room: outline area, perimeter, bounds and height.
    let room = try XCTUnwrap(model.rooms.first)
    XCTAssertEqual(model.rooms.count, 1)
    let truthRoom = try XCTUnwrap(truth["rooms"]?[0])
    let polygon = room.polygon.map { Vector3($0.x, $0.y, $0.z) }
    XCTAssertEqual(PolygonMath.area(polygon), try XCTUnwrap(truthRoom["areaM2"]?.number), accuracy: 0.001)
    XCTAssertEqual(PolygonMath.perimeter(polygon), try XCTUnwrap(truthRoom["perimeterM"]?.number), accuracy: 0.001)
    XCTAssertEqual(room.heightM, try XCTUnwrap(truthRoom["heightM"]?.number), accuracy: oneMillimetre)
    XCTAssertEqual(room.polygon.count, 4)
    XCTAssertEqual(room.label, "Test Room")

    let xs = room.polygon.map(\.x)
    let zs = room.polygon.map(\.z)
    XCTAssertEqual(try XCTUnwrap(xs.max()) - xs.min()!, try XCTUnwrap(truthRoom["widthM"]?.number), accuracy: oneMillimetre)
    XCTAssertEqual(try XCTUnwrap(zs.max()) - zs.min()!, try XCTUnwrap(truthRoom["lengthM"]?.number), accuracy: oneMillimetre)
    let bounds = try XCTUnwrap(truth["boundsM"])
    XCTAssertEqual(xs.min()!, try XCTUnwrap(bounds["min"]?.numbers)[0], accuracy: oneMillimetre)
    XCTAssertEqual(xs.max()!, try XCTUnwrap(bounds["max"]?.numbers)[0], accuracy: oneMillimetre)
    XCTAssertEqual(zs.min()!, try XCTUnwrap(bounds["min"]?.numbers)[2], accuracy: oneMillimetre)
    XCTAssertEqual(zs.max()!, try XCTUnwrap(bounds["max"]?.numbers)[2], accuracy: oneMillimetre)
    XCTAssertTrue(room.polygon.allSatisfy { $0.y == 0 }, "polygon is at floor level")

    // Walls: same ids, lengths and heights as the truth.
    let truthWalls = try XCTUnwrap(truth["walls"]?.array)
    XCTAssertEqual(model.walls.count, truthWalls.count)
    for truthWall in truthWalls {
      let id = try XCTUnwrap(truthWall["id"]?.string)
      let wall = try XCTUnwrap(model.walls.first { $0.id == id }, "wall \(id)")
      let length = ((wall.end.x - wall.start.x) * (wall.end.x - wall.start.x)
        + (wall.end.z - wall.start.z) * (wall.end.z - wall.start.z)).squareRoot()
      XCTAssertEqual(length, try XCTUnwrap(truthWall["lengthM"]?.number), accuracy: oneMillimetre, id)
      XCTAssertEqual(wall.heightM, try XCTUnwrap(truthWall["heightM"]?.number), accuracy: oneMillimetre, id)
      XCTAssertEqual(wall.start.y, 0, accuracy: oneMillimetre, "wall base is at floor level")
      XCTAssertEqual(wall.roomIds, ["room-1"])
    }

    // Openings: wall, offset, bottom, size.
    let openings = model.doors + model.windows + model.openings
    for truthOpening in try XCTUnwrap(truth["openings"]?.array) {
      let id = try XCTUnwrap(truthOpening["id"]?.string)
      let opening = try XCTUnwrap(openings.first { $0.id == id }, "opening \(id)")
      XCTAssertEqual(opening.wallId, truthOpening["wallId"]?.string, id)
      XCTAssertEqual(opening.offsetM, try XCTUnwrap(truthOpening["offsetM"]?.number), accuracy: oneMillimetre, id)
      XCTAssertEqual(opening.bottomM, try XCTUnwrap(truthOpening["bottomM"]?.number), accuracy: oneMillimetre, id)
      XCTAssertEqual(opening.widthM, try XCTUnwrap(truthOpening["widthM"]?.number), accuracy: oneMillimetre, id)
      XCTAssertEqual(opening.heightM, try XCTUnwrap(truthOpening["heightM"]?.number), accuracy: oneMillimetre, id)
    }
    XCTAssertEqual(openings.count, try XCTUnwrap(truth["openings"]?.array).count)
    XCTAssertEqual(model.doors.map(\.id), ["door-1"])
    XCTAssertEqual(model.windows.map(\.id), ["window-1"])

    // Object: the table.
    let object = try XCTUnwrap(model.objects.first)
    let truthObject = try XCTUnwrap(truth["objects"]?[0])
    XCTAssertEqual(object.category, .table)
    let centre = try XCTUnwrap(truthObject["centerM"]?.numbers)
    let size = try XCTUnwrap(truthObject["sizeM"]?.numbers)
    XCTAssertEqual(object.box.center.x, centre[0], accuracy: oneMillimetre)
    XCTAssertEqual(object.box.center.y, centre[1], accuracy: oneMillimetre)
    XCTAssertEqual(object.box.center.z, centre[2], accuracy: oneMillimetre)
    XCTAssertEqual(object.box.sizeM.x, size[0], accuracy: oneMillimetre)
    XCTAssertEqual(object.box.sizeM.y, size[1], accuracy: oneMillimetre)
    XCTAssertEqual(object.box.sizeM.z, size[2], accuracy: oneMillimetre)
  }

  func testMappedModelEqualsTheGeneratorsCaptureModelWithinOneMillimetre() throws {
    for (name, index) in allGeneratedCaptures {
      let mapped = try mapFixture(name, capture: index)
      // The generator leaves the confidence of doors, windows and openings out; real RoomPlan
      // reports it and the mapper keeps it (the schema allows it). The generator writes schema
      // 1.0.0 and the app the current version, whose added fields (room type, door isOpen,
      // object attributes and parent) testGeneratedFixturesGetTheFieldsOf1_1 checks. The room
      // labels come from the generator's model (see mapFixture). Nothing else may differ.
      let json = try encodedJSON(mapped.model)
      let problems = differences(json, mapped.expected, tolerance: oneMillimetre)
        .filter { problem in
          let isOpeningConfidence =
            ["/doors/", "/windows/", "/openings/"].contains { problem.hasPrefix($0.dropLast()) }
            && problem.hasSuffix("/confidence: not expected")
          let isAddedIn1_1 =
            problem.range(
              of: #"^/(rooms/\d+/(type|typeSource)|doors/\d+/isOpen|objects/\d+/(attributes|parentId)): not expected$"#,
              options: .regularExpression) != nil
          return !isOpeningConfidence && !isAddedIn1_1 && !problem.hasPrefix("/schemaVersion:")
        }
      XCTAssertEqual(problems, [], "\(name) capture \(index)")
      XCTAssertEqual(json["schemaVersion"]?.string, CaptureModelSchemaVersion.current.rawValue)
    }
  }

  /// The 1.1.0 fields the generator's 1.0.0 models do not carry: room types from the RoomPlan
  /// sections, and door isOpen as RoomPlan reports it (closed in every generated capture).
  func testGeneratedFixturesGetTheFieldsOf1_1() throws {
    let expectedTypes: [String: [RoomType?]] = [
      // An unidentified section, and a table without chairs says nothing.
      "box-room 0": [nil],
      "l-shaped-room 0": [nil],
      "two-room-apartment 0": [.livingRoom, .bedroom],
      "two-floor-house 0": [.livingRoom],
      // An unidentified section and no objects.
      "two-floor-house 1": [nil],
    ]
    for (name, index) in allGeneratedCaptures {
      let model = try mapFixture(name, capture: index).model
      let key = "\(name) \(index)"
      XCTAssertEqual(model.rooms.map(\.type), try XCTUnwrap(expectedTypes[key]), key)
      XCTAssertEqual(
        model.rooms.map(\.typeSource), model.rooms.map { $0.type == nil ? nil : .roomplanSection }, key)
      XCTAssertTrue(model.doors.allSatisfy { $0.isOpen == false }, key)
      XCTAssertTrue((model.windows + model.openings).allSatisfy { $0.isOpen == nil }, key)
      XCTAssertTrue(model.objects.allSatisfy { $0.attributes == nil && $0.parentId == nil }, key)
    }
  }

  func testLShapeAndStairVoidKeepTheirOutlines() throws {
    let lShape = try mapFixture("l-shaped-room").model.rooms[0]
    XCTAssertEqual(lShape.polygon.count, 6)
    XCTAssertEqual(PolygonMath.area(lShape.polygon.map { Vector3($0.x, $0.y, $0.z) }), 18, accuracy: 0.001)

    let upper = try mapFixture("two-floor-house", capture: 1)
    let truthArea = try XCTUnwrap(upper.truth["rooms"]?[0]?["areaM2"]?.number)
    XCTAssertEqual(
      PolygonMath.area(upper.model.rooms[0].polygon.map { Vector3($0.x, $0.y, $0.z) }), truthArea, accuracy: 0.001)
  }

  func testRoomPolygonsAreCounterClockwiseAndOpen() throws {
    for (name, index) in allGeneratedCaptures {
      for room in try mapFixture(name, capture: index).model.rooms {
        let points = room.polygon.map { Vector3($0.x, $0.y, $0.z) }
        XCTAssertLessThan(PolygonMath.signedArea(points), 0, "\(name) \(room.id) is counter-clockwise from +Y")
        XCTAssertNotEqual(room.polygon.first, room.polygon.last, "\(name) \(room.id) first point not repeated")
      }
    }
  }

  func testClockwiseFloorOutlineIsReversedToCounterClockwise() throws {
    var mapped = try mapFixture("box-room")
    mapped.document.rooms[0].floors[0].polygonCorners?.reverse()
    let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    let points = model.rooms[0].polygon.map { Vector3($0.x, $0.y, $0.z) }
    XCTAssertLessThan(PolygonMath.signedArea(points), 0)
    XCTAssertEqual(PolygonMath.area(points), 12, accuracy: 0.001)
    XCTAssertEqual(model.rooms[0].polygon.count, 4)
  }

  func testClosingPointOfAFloorOutlineIsDropped() throws {
    var mapped = try mapFixture("box-room")
    let first = try XCTUnwrap(mapped.document.rooms[0].floors[0].polygonCorners?.first)
    mapped.document.rooms[0].floors[0].polygonCorners?.append(first)
    let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.rooms[0].polygon.count, 4)
  }

  func testOutlineIsBuiltFromWallsWhenThereIsNoFloorSurface() throws {
    for (name, area) in [("box-room", 12.0), ("l-shaped-room", 18.0)] {
      var mapped = try mapFixture(name)
      mapped.document.rooms[0].floors = []
      let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
      let points = model.rooms[0].polygon.map { Vector3($0.x, $0.y, $0.z) }
      XCTAssertEqual(PolygonMath.area(points), area, accuracy: 0.001, name)
      XCTAssertLessThan(PolygonMath.signedArea(points), 0, name)
    }
  }

  func testRoomWithoutFloorAndOpenWallsHasNoOutline() throws {
    var mapped = try mapFixture("box-room")
    mapped.document.rooms[0].floors = []
    mapped.document.rooms[0].walls.removeLast()
    XCTAssertThrowsError(try CaptureModelMapper.map(mapped.document, context: mapped.context)) {
      XCTAssertEqual($0 as? MappingError, .roomHasNoOutline(roomIndex: 0))
    }
  }

  func testStructureAndSingleRoomAreBothDecoded() throws {
    let single = try RoomPlanDocument.decode(from: Fixtures.load("box-room").roomPlanData())
    XCTAssertFalse(single.isStructure)
    XCTAssertEqual(single.rooms.count, 1)
    let structure = try RoomPlanDocument.decode(from: Fixtures.load("two-room-apartment").roomPlanData())
    XCTAssertTrue(structure.isStructure)
    XCTAssertEqual(structure.rooms.count, 2)
    XCTAssertEqual(structure.rooms[0].doors.first?.category, RoomPlanCategory(name: "door", isOpen: false))
    XCTAssertEqual(structure.rooms[0].walls.first?.confidence, .high)

    // Sections sit in each room and, for a structure, at the top level too.
    XCTAssertEqual(single.rooms[0].sections.map(\.label), ["unidentified"])
    XCTAssertEqual(single.sections, [], "one CapturedRoom keeps its sections in the room")
    XCTAssertEqual(structure.rooms.map { $0.sections.map(\.label) }, [["livingRoom"], ["bedroom"]])
    XCTAssertEqual(structure.sections.map(\.label), ["livingRoom", "bedroom"])
    XCTAssertEqual(structure.rooms[1].sections.first?.center, Vector3(6.5, 0, 2))
    XCTAssertEqual(structure.rooms.map(\.story), [0, 0])
  }

  func testSectionsDecodeWithUnknownLabelsAndMissingCentres() throws {
    let json = #"""
      [{"story": 0, "label": "livingRoom", "center": [1, 2, 3]},
       {"story": 0, "label": "diningRoom", "center": [1, 2, 3]},
       {"story": 0, "label": "kitchen", "center": [1, 2, 3]},
       {"story": 0, "label": "bedroom", "center": [1, 2, 3]},
       {"story": 0, "label": "bathroom", "center": [1, 2, 3]},
       {"story": 0, "label": "unidentified", "center": [1, 2, 3]},
       {"label": "garage", "center": [4, 5, 6]},
       {"story": 1, "label": "bedroom"},
       {"story": "upstairs", "center": [7, 8]}]
      """#
    let sections = try JSONDecoder().decode([RoomPlanSection].self, from: Data(json.utf8))
    XCTAssertEqual(
      sections.map(\.label),
      ["livingRoom", "diningRoom", "kitchen", "bedroom", "bathroom", "unidentified", "garage", "bedroom", "unidentified"])
    XCTAssertEqual(
      sections.map(\.roomType), [.livingRoom, .diningRoom, .kitchen, .bedroom, .bathroom, nil, nil, .bedroom, nil])
    XCTAssertEqual(sections.map(\.story), [0, 0, 0, 0, 0, 0, nil, 1, nil])
    XCTAssertEqual(sections[6].center, Vector3(4, 5, 6))
    XCTAssertNil(sections[7].center)
    XCTAssertNil(sections[8].center)
  }

  func testRoomWithSectionsOfAnUnexpectedShapeStillDecodes() throws {
    let data = try Fixtures.load("box-room").roomPlanData()
    guard var room = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return XCTFail("box-room is not a JSON object")
    }
    room["sections"] = "living room"
    room["story"] = "ground"
    let document = try RoomPlanDocument.decode(from: try JSONSerialization.data(withJSONObject: room))
    XCTAssertEqual(document.rooms[0].sections, [])
    XCTAssertNil(document.rooms[0].story)
    XCTAssertEqual(document.rooms[0].walls.count, 4)
  }

  func testRoomLabelsOverrideTheDerivedLabelsAndKeepTheTypes() throws {
    var mapped = try mapFixture("two-room-apartment")
    mapped.context.roomLabels = ["Kitchen"]
    let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.rooms.map(\.label), ["Kitchen", "Bedroom"])
    XCTAssertEqual(model.rooms.map(\.type), [.livingRoom, .bedroom])
    XCTAssertEqual(model.rooms.map(\.typeSource), [.roomplanSection, .roomplanSection])
  }

  func testDoorsKeepIsOpenAndOnlyDoorsCarryIt() throws {
    var mapped = try mapFixture("box-room")
    XCTAssertEqual(try CaptureModelMapper.map(mapped.document, context: mapped.context).doors.map(\.isOpen), [false])
    mapped.document.rooms[0].doors[0].category = RoomPlanCategory(name: "door", isOpen: true)
    // RoomPlan writes isOpen on doors only; a window that carried it would still not get it.
    mapped.document.rooms[0].windows[0].category = RoomPlanCategory(name: "window", isOpen: true)
    var model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.doors.map(\.isOpen), [true])
    XCTAssertEqual(model.windows.map(\.isOpen), [nil])
    mapped.document.rooms[0].doors[0].category = RoomPlanCategory(name: "door")
    model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.doors.map(\.isOpen), [nil], "not reported, not written")
  }

  func testObjectAttributesAndParentsAreMapped() throws {
    var mapped = try mapFixture("box-room")
    let table = mapped.document.rooms[0].objects[0]
    var sink = table
    sink.identifier = "SINK"
    sink.category = RoomPlanCategory(name: "sink")
    sink.parentIdentifier = "CABINET"  // listed after the sink
    var cabinet = table
    cabinet.identifier = "CABINET"
    cabinet.category = RoomPlanCategory(name: "storage")
    cabinet.attributes = ["StorageType": "cabinet", "Empty": ""]
    var chair = table
    chair.identifier = "CHAIR"
    chair.category = RoomPlanCategory(name: "chair")
    chair.parentIdentifier = "NOT-IN-THIS-CAPTURE"
    chair.attributes = ["ChairType": ""]
    var shelf = table
    shelf.identifier = "SHELF"
    shelf.category = RoomPlanCategory(name: "storage")
    shelf.parentIdentifier = "SHELF"
    mapped.document.rooms[0].objects = [table, sink, cabinet, chair, shelf]
    let objects = try CaptureModelMapper.map(mapped.document, context: mapped.context).objects
    XCTAssertEqual(objects.map(\.id), ["object-1", "object-2", "object-3", "object-4", "object-5"])
    XCTAssertEqual(objects.map(\.parentId), [nil, "object-3", nil, nil, nil])
    XCTAssertEqual(objects.map(\.attributes), [nil, nil, ["StorageType": "cabinet"], nil, nil])
  }

  func testAttributeValuesOutsideTheSchemaLengthAreLeftOut() throws {
    var mapped = try mapFixture("box-room")
    var table = mapped.document.rooms[0].objects[0]
    let longest = String(repeating: "a", count: 100)
    table.attributes = ["TableType": longest, "TableShapeType": longest + "a"]
    mapped.document.rooms[0].objects = [table]
    let objects = try CaptureModelMapper.map(mapped.document, context: mapped.context).objects
    XCTAssertEqual(objects.map(\.attributes), [["TableType": longest]])
  }

  func testParentsResolveAcrossTheRoomsOfAStructure() throws {
    var mapped = try mapFixture("two-room-apartment")
    XCTAssertGreaterThanOrEqual(mapped.document.rooms.count, 2)
    let template = try XCTUnwrap(mapped.document.rooms.flatMap(\.objects).first)
    var cabinet = template
    cabinet.identifier = "CABINET"
    cabinet.category = RoomPlanCategory(name: "storage")
    var sink = template
    sink.identifier = "SINK"
    sink.category = RoomPlanCategory(name: "sink")
    sink.parentIdentifier = "CABINET"  // in the first room; the sink is in the second
    mapped.document.rooms[0].objects.append(cabinet)
    mapped.document.rooms[1].objects.append(sink)
    let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    let cabinetIndex = mapped.document.rooms[0].objects.count - 1
    let sinkIndex = mapped.document.rooms[0].objects.count + mapped.document.rooms[1].objects.count - 1
    XCTAssertEqual(model.objects[sinkIndex].parentId, model.objects[cabinetIndex].id)
    XCTAssertEqual(model.objects[cabinetIndex].category, .storage)
    XCTAssertEqual(model.objects[sinkIndex].category, .sink)
  }

  func testObjectDetailsAreDecoded() throws {
    let json = #"""
      {"identifier": "A", "parentIdentifier": "B", "category": {"storage": {}},
       "dimensions": [1, 1, 1], "transform": [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
       "attributes": {"StorageType": "cabinet", "Future": {"kind": 1}}}
      """#
    let object = try JSONDecoder().decode(RoomPlanObject.self, from: Data(json.utf8))
    XCTAssertEqual(object.parentIdentifier, "B")
    XCTAssertEqual(object.attributes, ["StorageType": "cabinet"], "values that are not strings are left out")
    let bare = try JSONDecoder().decode(
      RoomPlanObject.self,
      from: Data(#"{"identifier": "A", "category": {"bed": {}}, "dimensions": [1, 1, 1], "transform": [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]}"#.utf8))
    XCTAssertEqual(bare.attributes, [:])
    XCTAssertNil(bare.parentIdentifier)
  }

  func testCaptureWithoutRoomsFails() throws {
    let mapped = try mapFixture("box-room")
    let empty = RoomPlanDocument(rooms: [], isStructure: true)
    XCTAssertThrowsError(try CaptureModelMapper.map(empty, context: mapped.context)) {
      XCTAssertEqual($0 as? MappingError, .noRooms)
    }
    var noWalls = mapped.document
    noWalls.rooms[0].walls = []
    XCTAssertThrowsError(try CaptureModelMapper.map(noWalls, context: mapped.context)) {
      XCTAssertEqual($0 as? MappingError, .roomHasNoWalls(roomIndex: 0))
    }
  }

  func testWallWithoutLengthFails() throws {
    var mapped = try mapFixture("box-room")
    mapped.document.rooms[0].walls[0].dimensions[0] = 0
    XCTAssertThrowsError(try CaptureModelMapper.map(mapped.document, context: mapped.context)) {
      guard case .wallHasNoLength = $0 as? MappingError else { return XCTFail("\($0)") }
    }
  }

  func testUnknownObjectCategoryBecomesOther() throws {
    var mapped = try mapFixture("box-room")
    mapped.document.rooms[0].objects[0].category = RoomPlanCategory(name: "somethingNew")
    let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.objects[0].category, .other)
    mapped.document.rooms[0].objects[0].category = RoomPlanCategory(name: "washerDryer")
    XCTAssertEqual(try CaptureModelMapper.map(mapped.document, context: mapped.context).objects[0].category, .washerDryer)
  }

  func testRotationOfARotatedFrameIsAUnitQuaternion() throws {
    // Quarter turn about +Y: columns x = (0,0,-1), y = (0,1,0), z = (1,0,0).
    let quarter = try XCTUnwrap(Matrix4(columns: [[0, 0, -1, 0], [0, 1, 0, 0], [1, 0, 0, 0], [0, 0, 0, 1]]))
    let q = quarter.rotation
    XCTAssertEqual(q.y, 0.707107, accuracy: 1e-6)
    XCTAssertEqual(q.w, 0.707107, accuracy: 1e-6)
    XCTAssertEqual(q.x, 0, accuracy: 1e-9)
    XCTAssertEqual(Matrix4.identity.rotation, Quaternion.identity)
    // Half turn about +Y has w = 0; the result is still unit length.
    let half = try XCTUnwrap(Matrix4(columns: [[-1, 0, 0, 0], [0, 1, 0, 0], [0, 0, -1, 0], [0, 0, 0, 1]]))
    let h = half.rotation
    XCTAssertEqual((h.x * h.x + h.y * h.y + h.z * h.z + h.w * h.w), 1, accuracy: 1e-6)
    XCTAssertEqual(abs(h.y), 1, accuracy: 1e-6)
  }

  func testPointsMapThroughATransform() throws {
    let matrix = try XCTUnwrap(Matrix4(columns: [[0, 0, -1, 0], [0, 1, 0, 0], [1, 0, 0, 0], [5, 1, 2, 1]]))
    let p = matrix.apply(to: Vector3(2, 0, 3))
    XCTAssertEqual(p, Vector3(2 * 0 + 3 * 1 + 5, 1, 2 * -1 + 2))
  }
}
