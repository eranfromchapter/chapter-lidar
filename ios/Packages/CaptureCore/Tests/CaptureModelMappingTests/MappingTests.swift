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
      // reports it and the mapper keeps it (the schema allows it). Nothing else may differ.
      let problems = differences(try encodedJSON(mapped.model), mapped.expected, tolerance: oneMillimetre)
        .filter { problem in
          let isOpeningConfidence =
            ["/doors/", "/windows/", "/openings/"].contains { problem.hasPrefix($0.dropLast()) }
            && problem.hasSuffix("/confidence: not expected")
          return !isOpeningConfidence
        }
      XCTAssertEqual(problems, [], "\(name) capture \(index)")
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
  }

  func testRoomLabelsDefaultWhenNoneAreGiven() throws {
    var mapped = try mapFixture("two-room-apartment")
    mapped.context.roomLabels = ["Kitchen"]
    let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.rooms.map(\.label), ["Kitchen", "Room 2"])
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
