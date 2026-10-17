import CaptureContract
import CaptureModelMapping
import CaptureTestSupport
import Foundation
import XCTest

/// AC2: every door and window of the two-room fixture is assigned to exactly one parent wall.
final class OpeningAssignmentTests: XCTestCase {
  private func openings(_ model: CaptureModel) -> [CaptureModel.WallOpening] {
    model.doors + model.windows + model.openings
  }

  func testEveryDoorAndWindowHasExactlyOneExistingParentWall() throws {
    let mapped = try mapFixture("two-room-apartment")
    let model = mapped.model
    let rawDoorsAndWindows = mapped.document.rooms.reduce(0) { $0 + $1.doors.count + $1.windows.count }
    XCTAssertEqual(rawDoorsAndWindows, 3)
    XCTAssertEqual(model.doors.count + model.windows.count, rawDoorsAndWindows, "none lost, none doubled")
    XCTAssertEqual(Set(openings(model).map(\.id)).count, openings(model).count, "opening ids are unique")

    for opening in model.doors + model.windows {
      let parents = model.walls.filter { $0.id == opening.wallId }
      XCTAssertEqual(parents.count, 1, "\(opening.id) has exactly one parent wall")
    }
  }

  func testAssignmentsMatchTruth() throws {
    let mapped = try mapFixture("two-room-apartment")
    let all = openings(mapped.model)
    for truth in try XCTUnwrap(mapped.truth["openings"]?.array) {
      let id = try XCTUnwrap(truth["id"]?.string)
      let opening = try XCTUnwrap(all.first { $0.id == id })
      XCTAssertEqual(opening.wallId, truth["wallId"]?.string, id)
    }
    // The partition between the rooms is listed once per room; the door is in the living-room side.
    XCTAssertEqual(mapped.model.doors.first?.wallId, "wall-3")
  }

  func testOpeningsFitInsideTheirWall() throws {
    for (name, index) in allGeneratedCaptures {
      let model = try mapFixture(name, capture: index).model
      for opening in openings(model) {
        let wall = try XCTUnwrap(model.walls.first { $0.id == opening.wallId })
        let length = ((wall.end.x - wall.start.x) * (wall.end.x - wall.start.x)
          + (wall.end.z - wall.start.z) * (wall.end.z - wall.start.z)).squareRoot()
        XCTAssertGreaterThanOrEqual(opening.offsetM - opening.widthM / 2, -0.001, "\(name) \(opening.id)")
        XCTAssertLessThanOrEqual(opening.offsetM + opening.widthM / 2, length + 0.001, "\(name) \(opening.id)")
        XCTAssertLessThanOrEqual(opening.bottomM + opening.heightM, wall.heightM + 0.001, "\(name) \(opening.id)")
      }
    }
  }

  func testRoomPlanParentIdentifierIsUsedWhenPresent() throws {
    let mapped = try mapFixture("two-room-apartment")
    let walls = placements(of: mapped.document)
    for (roomIndex, room) in mapped.document.rooms.enumerated() {
      for surface in room.doors + room.windows + room.openings {
        let result = try XCTUnwrap(OpeningAssignment.assign(surface, roomIndex: roomIndex, walls: walls))
        XCTAssertEqual(result.method, .parentIdentifier, surface.identifier)
        XCTAssertEqual(result.wall.surfaceIdentifier, surface.parentIdentifier)
      }
    }
  }

  func testGeometryAloneGivesTheSameWalls() throws {
    let mapped = try mapFixture("two-room-apartment")
    var withoutParents = mapped.document
    for roomIndex in withoutParents.rooms.indices {
      for index in withoutParents.rooms[roomIndex].doors.indices { withoutParents.rooms[roomIndex].doors[index].parentIdentifier = nil }
      for index in withoutParents.rooms[roomIndex].windows.indices { withoutParents.rooms[roomIndex].windows[index].parentIdentifier = nil }
      for index in withoutParents.rooms[roomIndex].openings.indices { withoutParents.rooms[roomIndex].openings[index].parentIdentifier = nil }
    }
    let model = try CaptureModelMapper.map(withoutParents, context: mapped.context)
    XCTAssertEqual(model.doors, mapped.model.doors)
    XCTAssertEqual(model.windows, mapped.model.windows)
    XCTAssertEqual(model.openings, mapped.model.openings)

    let walls = placements(of: withoutParents)
    for (roomIndex, room) in withoutParents.rooms.enumerated() {
      for surface in room.doors + room.windows + room.openings {
        XCTAssertEqual(
          OpeningAssignment.assign(surface, roomIndex: roomIndex, walls: walls)?.method, .geometry)
      }
    }
  }

  func testUnknownParentIdentifierFallsBackToGeometry() throws {
    let mapped = try mapFixture("box-room")
    var document = mapped.document
    document.rooms[0].doors[0].parentIdentifier = "00000000-0000-0000-0000-000000000000"
    let model = try CaptureModelMapper.map(document, context: mapped.context)
    XCTAssertEqual(model.doors, mapped.model.doors)
  }

  func testOpeningThatLiesOnNoWallFailsInsteadOfGuessing() throws {
    let mapped = try mapFixture("box-room")
    var document = mapped.document
    document.rooms[0].windows[0].parentIdentifier = nil
    // Move the window 2 m into the room.
    document.rooms[0].windows[0].transform.columns[3][2] = 1
    XCTAssertThrowsError(try CaptureModelMapper.map(document, context: mapped.context)) {
      guard case .openingHasNoWall = $0 as? MappingError else { return XCTFail("\($0)") }
    }
  }

  func testGeometryPrefersTheOpeningsOwnRoomOverACoincidentWall() throws {
    // wall-3 (living room) and wall-5 (bedroom) lie on the same line; the door is listed in the
    // living room, so it belongs to wall-3 even without a parent identifier.
    let mapped = try mapFixture("two-room-apartment")
    var document = mapped.document
    document.rooms[0].doors[0].parentIdentifier = nil
    let walls = placements(of: document)
    let result = try XCTUnwrap(OpeningAssignment.assign(document.rooms[0].doors[0], roomIndex: 0, walls: walls))
    XCTAssertEqual(result.wall.id, "wall-3")
    let coincident = walls.filter { abs($0.start.x - 5) < 1e-6 && abs($0.end.x - 5) < 1e-6 }
    XCTAssertEqual(coincident.map(\.id).sorted(), ["wall-3", "wall-5"])
  }

  private func placements(of document: RoomPlanDocument) -> [WallPlacement] {
    var result: [WallPlacement] = []
    var counter = 0
    for (roomIndex, room) in document.rooms.enumerated() {
      for surface in room.walls {
        counter += 1
        result.append(
          try! CaptureModelMapper.wallPlacement(surface, id: "wall-\(counter)", roomIndex: roomIndex))
      }
    }
    return result
  }
}
