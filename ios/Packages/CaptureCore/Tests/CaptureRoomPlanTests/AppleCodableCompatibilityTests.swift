// Runs on the macOS runner only (RoomPlan does not exist on Linux). On Linux this file is empty.
//
// The mapping code reads RoomPlan's Codable JSON through `RoomPlanDocument` (a mirror of Apple's
// shape) and the generated fixtures are written in that shape. These tests decode the same
// fixtures with Apple's real `CapturedRoom` / `CapturedStructure` and run Apple's own JSON back
// through the mapping, so a difference between the mirror and the real types fails here.
#if canImport(RoomPlan) && canImport(ARKit) && os(iOS)
  import CaptureCore
  import CaptureModelMapping
  import CaptureRoomPlan
  import CaptureTestSupport
  import Foundation
  import RoomPlan
  import XCTest

  final class AppleCodableCompatibilityTests: XCTestCase {
    func testBoxRoomFixtureDecodesAsCapturedRoom() throws {
      let data = try Fixtures.load("box-room").roomPlanData()
      let room = try JSONDecoder().decode(CapturedRoom.self, from: data)
      XCTAssertEqual(room.walls.count, 4)
      XCTAssertEqual(room.doors.count, 1)
      XCTAssertEqual(room.windows.count, 1)
      XCTAssertEqual(room.objects.count, 1)
    }

    func testApartmentFixtureDecodesAsCapturedStructure() throws {
      let data = try Fixtures.load("two-room-apartment").roomPlanData()
      let structure = try JSONDecoder().decode(CapturedStructure.self, from: data)
      XCTAssertEqual(structure.rooms.count, 2)
    }

    func testAppleEncodingOfTheFixtureMapsToTheSameModelAsTheFixtureJSON() throws {
      let fixture = try Fixtures.load("box-room")
      let original = try fixture.roomPlanData()
      let room = try JSONDecoder().decode(CapturedRoom.self, from: original)
      let appleDocument = try RoomPlanAdapter.document(room)
      let fixtureDocument = try RoomPlanDocument.decode(from: original)
      XCTAssertEqual(appleDocument.rooms.count, fixtureDocument.rooms.count)
      XCTAssertEqual(appleDocument.rooms[0].walls.count, fixtureDocument.rooms[0].walls.count)
      XCTAssertEqual(appleDocument.rooms[0].floors.first?.polygonCorners?.count, 4)
    }

    func testDeviceCapabilitiesAreReadable() async throws {
      let capabilities = await MainActor.run { DeviceCapabilities.current() }
      XCTAssertFalse(capabilities.model.isEmpty)
      _ = DeviceGate.evaluate(capabilities)
    }
  }
#endif
