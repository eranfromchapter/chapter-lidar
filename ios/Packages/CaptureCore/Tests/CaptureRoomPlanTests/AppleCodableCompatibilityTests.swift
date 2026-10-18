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
      // Apple and the mirror must read the 16 numbers in the same order: same translations.
      let document = try RoomPlanDocument.decode(from: data)
      for (apple, mirror) in zip(room.walls + room.doors, document.rooms[0].walls + document.rooms[0].doors) {
        let t = apple.transform.columns.3
        let expected = mirror.transform.translation
        XCTAssertEqual(Double(t.x), expected.x, accuracy: 1e-5)
        XCTAssertEqual(Double(t.y), expected.y, accuracy: 1e-5)
        XCTAssertEqual(Double(t.z), expected.z, accuracy: 1e-5)
      }
    }

    func testApartmentFixtureDecodesAsCapturedStructure() throws {
      let data = try Fixtures.load("two-room-apartment").roomPlanData()
      let structure = try JSONDecoder().decode(CapturedStructure.self, from: data)
      XCTAssertEqual(structure.rooms.count, 2)
    }

    func testWalkthroughFixtureDecodesAsCapturedRoom() throws {
      // The RoomPlan-only walk-through: a whole apartment as one CapturedRoom, with sections,
      // object attributes and doors seen open and closed, like a real device export.
      let fixture = try Fixtures.roomPlanOnly("apartment-walkthrough")
      let data = try fixture.roomPlanData()
      let expected = fixture.expected
      let room = try JSONDecoder().decode(CapturedRoom.self, from: data)
      XCTAssertEqual(room.walls.count, expected.totals.walls)
      XCTAssertEqual(room.doors.count, expected.totals.doors)
      XCTAssertEqual(room.windows.count, expected.totals.windows)
      XCTAssertEqual(room.openings.count, expected.totals.openings)
      XCTAssertEqual(room.objects.count, expected.totals.objects)
      XCTAssertEqual(room.floors.count, 1)
      XCTAssertEqual(room.floors.first?.polygonCorners.count, expected.totals.outlineCorners)
      XCTAssertEqual(room.sections.map(\.label.rawValue), expected.sections.map(\.label))
      XCTAssertEqual(room.version, 2)

      let isOpen = room.doors.map { door -> Bool? in
        if case .door(let isOpen) = door.category { return isOpen }
        return nil
      }
      XCTAssertEqual(isOpen, expected.openings.filter { $0.kind == "door" }.map(\.isOpen))
      let storage = room.objects.filter { $0.category == .storage }
      XCTAssertEqual(Set(storage.compactMap { $0.attribute(of: StorageType.self)?.rawValue }), ["cabinet", "shelf"])
      let parents = try XCTUnwrap(JSON.parse(data)["objects"]?.array).compactMap { $0["parentIdentifier"]?.string }
      XCTAssertFalse(parents.isEmpty)
      XCTAssertEqual(room.objects.compactMap { $0.parentIdentifier?.uuidString }, parents)
      for (object, listed) in zip(room.objects, expected.rooms.flatMap(\.objects).sorted { $0.index < $1.index }) {
        XCTAssertEqual(object.identifier.uuidString, listed.identifier)
      }

      // Apple and the mirror read the same walls, in the same order, at the same places.
      let document = try RoomPlanDocument.decode(from: data)
      XCTAssertFalse(document.isStructure)
      XCTAssertEqual(document.rooms[0].walls.count, room.walls.count)
      for (apple, mirror) in zip(room.walls + room.doors, document.rooms[0].walls + document.rooms[0].doors) {
        XCTAssertEqual(apple.identifier.uuidString, mirror.identifier)
        let t = apple.transform.columns.3
        let expectedTranslation = mirror.transform.translation
        XCTAssertEqual(Double(t.x), expectedTranslation.x, accuracy: 1e-5)
        XCTAssertEqual(Double(t.y), expectedTranslation.y, accuracy: 1e-5)
        XCTAssertEqual(Double(t.z), expectedTranslation.z, accuracy: 1e-5)
      }
      // Apple's own encoding reads back through the mirror with every element.
      let appleDocument = try RoomPlanAdapter.document(room)
      XCTAssertEqual(appleDocument.rooms[0].walls.count, expected.totals.walls)
      XCTAssertEqual(appleDocument.rooms[0].objects.count, expected.totals.objects)
      XCTAssertEqual(appleDocument.rooms[0].floors.first?.polygonCorners?.count, expected.totals.outlineCorners)

      // Apple and the mirror read the same story, sections, object attributes and parents, and
      // Apple's own encoding reads back the same.
      let mirrorRoom = document.rooms[0]
      XCTAssertEqual(mirrorRoom.story, room.story)
      XCTAssertEqual(mirrorRoom.sections.map(\.label), room.sections.map(\.label.rawValue))
      XCTAssertEqual(mirrorRoom.sections.map(\.story), room.sections.map(\.story))
      for (apple, mirror) in zip(room.sections, mirrorRoom.sections) {
        let center = try XCTUnwrap(mirror.center)
        XCTAssertEqual(Double(apple.center.x), center.x, accuracy: 1e-5)
        XCTAssertEqual(Double(apple.center.y), center.y, accuracy: 1e-5)
        XCTAssertEqual(Double(apple.center.z), center.z, accuracy: 1e-5)
      }
      XCTAssertEqual(mirrorRoom.objects.map(\.parentIdentifier), room.objects.map { $0.parentIdentifier?.uuidString })
      XCTAssertEqual(
        mirrorRoom.objects.filter { $0.category.name == "storage" }.map { $0.attributes["StorageType"] },
        storage.map { $0.attribute(of: StorageType.self)?.rawValue })
      let appleRoom = appleDocument.rooms[0]
      XCTAssertEqual(appleRoom.story, mirrorRoom.story)
      XCTAssertEqual(appleRoom.sections.map(\.label), mirrorRoom.sections.map(\.label))
      XCTAssertEqual(appleRoom.objects.map(\.attributes), mirrorRoom.objects.map(\.attributes))
      XCTAssertEqual(appleRoom.objects.map(\.parentIdentifier), mirrorRoom.objects.map(\.parentIdentifier))
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
