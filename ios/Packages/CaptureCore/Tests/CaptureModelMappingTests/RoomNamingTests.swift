import CaptureContract
import CaptureModelMapping
import CaptureTestSupport
import Foundation
import XCTest

/// The operator's room names (field report 2026-10-20: a 1.85 m2 room the splitter typed
/// "Closet" was a shower). Synthetic walk-throughs only; no real scan data.
final class RoomNamingTests: XCTestCase {
  /// The L-shaped walk-through of the splitter tests with a small enclosed room in the corner:
  /// Bedroom, Room 2 (unidentified) and Closet (the shape types it; no section, no object).
  private func bedroomRoomAndCloset() -> RoomPlanDocument {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape)
    builder.addWall((0, 4.6), (1.2, 4.6))
    builder.addWall((1.6, 4.6), (1.6, 6))
    builder.addSection("bedroom", at: (2, 3))
    builder.addSection("unidentified", at: (6, 1.5))
    return builder.document
  }

  private func map(_ names: [RoomName], label: String = "Room Mexico") throws -> NamedCaptureModel {
    try RoomNaming.map(
      bedroomRoomAndCloset(), context: try Walkthrough.context(label: label), names: names)
  }

  func testWithoutNamesTheModelIsTheMappersOwn() throws {
    let named = try map([])
    XCTAssertEqual(named.derivedLabels, ["Bedroom", "Room 2", "Closet"])
    XCTAssertEqual(
      named.model,
      try CaptureModelMapper.map(bedroomRoomAndCloset(), context: try Walkthrough.context(label: "Room Mexico")))
    XCTAssertEqual(named.model.rooms.map(\.type), [.bedroom, nil, .closet])
    XCTAssertEqual(named.model.rooms.map(\.typeSource), [.roomplanSection, nil, .inferred])
  }

  func testClosetRenamedShowerIsABathroomFromTheOperator() throws {
    let named = try map([RoomName(roomId: "room-3", derivedLabel: "Closet", name: "Shower")])
    XCTAssertEqual(named.model.rooms.map(\.label), ["Bedroom", "Room 2", "Shower"])
    XCTAssertEqual(named.model.rooms.map(\.type), [.bedroom, nil, .bathroom])
    XCTAssertEqual(named.model.rooms.map(\.typeSource), [.roomplanSection, nil, .operator])
    XCTAssertEqual(named.derivedLabels, ["Bedroom", "Room 2", "Closet"], "derived without the names")
    // Only labels and types change: the geometry is the same model.
    let plain = try map([]).model
    XCTAssertEqual(named.model.walls, plain.walls)
    XCTAssertEqual(named.model.rooms.map(\.polygon), plain.rooms.map(\.polygon))
    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
    XCTAssertEqual(validator.validate(try encodedJSON(named.model)), [])
  }

  /// Review of 2026-10-20: "Bedroom closet" made a bedroom (the first type word won), so the
  /// plan counted a bedroom more. The kind of room is the last type word.
  func testACompoundNameTypesTheRoomByItsLastTypeWord() throws {
    let named = try map([RoomName(roomId: "room-3", derivedLabel: "Closet", name: "Bedroom closet")])
    XCTAssertEqual(named.model.rooms.map(\.label), ["Bedroom", "Room 2", "Bedroom closet"])
    XCTAssertEqual(named.model.rooms.map(\.type), [.bedroom, nil, .closet])
    XCTAssertEqual(named.model.rooms.map(\.typeSource), [.roomplanSection, nil, .operator])
    let hall = try map([RoomName(roomId: "room-2", derivedLabel: "Room 2", name: "Bedroom hall")])
    XCTAssertEqual(hall.model.rooms.map(\.type), [.bedroom, .hallway, .closet])
    XCTAssertEqual(hall.model.rooms.filter { $0.type == .bedroom }.count, 1, "one bedroom, as scanned")
  }

  func testANameThatNamesNoTypeKeepsTheScansType() throws {
    let named = try map([
      RoomName(roomId: "room-1", derivedLabel: "Bedroom", name: "Eran's room"),
      RoomName(roomId: "room-2", derivedLabel: "Room 2", name: "Kitchenette"),
    ])
    XCTAssertEqual(named.model.rooms.map(\.label), ["Eran's room", "Kitchenette", "Closet"])
    XCTAssertEqual(named.model.rooms.map(\.type), [.bedroom, .kitchen, .closet])
    XCTAssertEqual(named.model.rooms.map(\.typeSource), [.roomplanSection, .operator, .inferred])
  }

  /// A name goes only on the room with that id that still has the derived label it was given
  /// for: after an app update splits the scan differently, a stale name is dropped instead of
  /// landing on another room.
  func testANameAppliesOnlyToTheSameRoomOfTheSameSplit() throws {
    let rooms = [
      ScannedRoom(id: "room-1", derivedLabel: "Bedroom"), ScannedRoom(id: "room-2", derivedLabel: "Room 2"),
      ScannedRoom(id: "room-3", derivedLabel: "Closet"),
    ]
    let shower = RoomName(roomId: "room-3", derivedLabel: "Closet", name: "Shower")
    XCTAssertEqual(RoomNaming.overrides(rooms: rooms, names: [shower]), ["", "", "Shower"])
    // The same id now has another derived label (a different split): ignored.
    XCTAssertEqual(
      RoomNaming.overrides(rooms: rooms, names: [RoomName(roomId: "room-2", derivedLabel: "Closet", name: "Shower")]),
      ["", "", ""])
    // The room is gone (two rooms now): ignored.
    XCTAssertEqual(RoomNaming.overrides(rooms: Array(rooms.prefix(2)), names: [shower]), ["", ""])
    // The derived label must match exactly.
    XCTAssertEqual(
      RoomNaming.overrides(rooms: rooms, names: [RoomName(roomId: "room-3", derivedLabel: "closet", name: "Shower")]),
      ["", "", ""])
    // The last entry for a room wins; a name the schema would refuse is ignored.
    let renamedTwice = [shower, RoomName(roomId: "room-3", derivedLabel: "Closet", name: "  Steam shower ")]
    XCTAssertEqual(RoomNaming.overrides(rooms: rooms, names: renamedTwice), ["", "", "Steam shower"])
    let tooLong = RoomName(roomId: "room-1", derivedLabel: "Bedroom", name: String(repeating: "a", count: 101))
    XCTAssertEqual(RoomNaming.overrides(rooms: rooms, names: [tooLong, shower]), ["", "", "Shower"])
    XCTAssertEqual(RoomNaming.applicable([tooLong, shower], rooms: rooms), [shower])

    // Through the mapper: the stale name changes nothing.
    let stale = try map([RoomName(roomId: "room-2", derivedLabel: "Closet", name: "Shower")])
    XCTAssertEqual(stale.model.rooms.map(\.label), ["Bedroom", "Room 2", "Closet"])
    XCTAssertEqual(stale.model, try map([]).model)
  }

  /// Review of 2026-10-20: an untyped room is "Room N" by its position, the same thing its id
  /// says, so id and label alone cannot tell another room of a different split. The footprint
  /// (area and centre of the outline) does.
  func testANameAppliesOnlyWhereTheRoomWas() throws {
    let plain = try map([])
    let scanned = plain.scannedRooms
    XCTAssertEqual(scanned.map(\.id), ["room-1", "room-2", "room-3"])
    XCTAssertEqual(scanned.map(\.derivedLabel), ["Bedroom", "Room 2", "Closet"])
    let room2 = try XCTUnwrap(scanned[1].footprint)
    let closet = try XCTUnwrap(scanned[2].footprint)
    XCTAssertGreaterThan(room2.areaM2, closet.areaM2)
    // The small room in the corner of the L (x 0 to 1.6, z 4.6 to 6).
    XCTAssertEqual(closet.centerX, 0.8, accuracy: 0.4)
    XCTAssertEqual(closet.centerZ, 5.3, accuracy: 0.4)

    // Saved with the footprint the room had: applied.
    let named = try map([
      RoomName(roomId: "room-2", derivedLabel: "Room 2", name: "Kitchenette", footprint: room2),
      RoomName(roomId: "room-3", derivedLabel: "Closet", name: "Shower", footprint: closet),
    ])
    XCTAssertEqual(named.model.rooms.map(\.label), ["Bedroom", "Kitchenette", "Shower"])

    // The same id and label but another room (elsewhere, or of another size): ignored.
    var elsewhere = room2
    elsewhere.centerX += 2
    var smaller = room2
    smaller.areaM2 *= 0.5
    for footprint in [elsewhere, smaller] {
      let stale = try map([RoomName(roomId: "room-2", derivedLabel: "Room 2", name: "Kitchenette", footprint: footprint)])
      XCTAssertEqual(stale.model.rooms.map(\.label), ["Bedroom", "Room 2", "Closet"], "\(footprint)")
    }
    // A slightly different outline of the same room still counts (rounding, a small fix to
    // the outline after an update).
    var nudged = closet
    nudged.centerX += 0.1
    nudged.areaM2 += 0.1
    XCTAssertTrue(nudged.matches(closet))
    XCTAssertEqual(
      RoomNaming.overrides(rooms: scanned, names: [RoomName(roomId: "room-3", derivedLabel: "Closet", name: "Shower", footprint: nudged)]),
      ["", "", "Shower"])
    // A saved footprint and a room without one (no outline area): not the same room.
    XCTAssertFalse(
      RoomNaming.applies(
        RoomName(roomId: "room-3", derivedLabel: "Closet", name: "Shower", footprint: closet),
        to: ScannedRoom(id: "room-3", derivedLabel: "Closet", footprint: nil)))
  }

  func testFootprintOfAnOutline() throws {
    // A 4 x 3 m rectangle from (1, 2): area 12, centre (3, 3.5), either winding.
    let corners: [(Double, Double)] = [(1, 2), (5, 2), (5, 5), (1, 5)]
    for polygon in [corners, corners.reversed()] {
      let footprint = try XCTUnwrap(RoomFootprint(polygon: polygon.map { Vec3(x: $0.0, y: 0, z: $0.1) }))
      XCTAssertEqual(footprint, RoomFootprint(areaM2: 12, centerX: 3, centerZ: 3.5))
    }
    // An L: the centre of the area, not of the corners.
    let l: [(Double, Double)] = [(0, 0), (4, 0), (4, 1), (1, 1), (1, 4), (0, 4)]
    let footprint = try XCTUnwrap(RoomFootprint(polygon: l.map { Vec3(x: $0.0, y: 0, z: $0.1) }))
    XCTAssertEqual(footprint.areaM2, 7)
    XCTAssertEqual(footprint.centerX, 1.36)  // (4 x 2 + 3 x 0.5) / 7, rounded to the centimetre
    XCTAssertEqual(footprint.centerZ, 1.36)
    XCTAssertNil(RoomFootprint(polygon: [Vec3(x: 0, y: 0, z: 0), Vec3(x: 1, y: 0, z: 0)]))
    XCTAssertNil(RoomFootprint(polygon: [Vec3(x: 0, y: 0, z: 0), Vec3(x: 1, y: 0, z: 0), Vec3(x: 2, y: 0, z: 0)]))
    // Saved and read back; a name saved without one decodes with none.
    let name = RoomName(roomId: "room-3", derivedLabel: "Closet", name: "Shower", footprint: footprint)
    XCTAssertEqual(try JSONDecoder().decode(RoomName.self, from: JSONEncoder().encode(name)), name)
    let old = try JSONDecoder().decode(
      RoomName.self, from: Data(#"{"roomId":"room-3","derivedLabel":"Closet","name":"Shower"}"#.utf8))
    XCTAssertNil(old.footprint)
  }

  func testCleanedNamesStayWithinTheSchemaLimit() {
    XCTAssertEqual(RoomNaming.cleaned("  Shower \n"), "Shower")
    XCTAssertNil(RoomNaming.cleaned("   "))
    XCTAssertNil(RoomNaming.cleaned(""))
    XCTAssertEqual(RoomNaming.cleaned(String(repeating: "a", count: 100)), String(repeating: "a", count: 100))
    XCTAssertNil(RoomNaming.cleaned(String(repeating: "a", count: 101)))
    // Counted in Unicode scalars, as the schema counts: 50 accented letters are 100 scalars.
    XCTAssertNotNil(RoomNaming.cleaned(String(repeating: "e\u{301}", count: 50)))
    XCTAssertNil(RoomNaming.cleaned(String(repeating: "e\u{301}", count: 51)))
  }

  /// Names follow the label rules: unique within the capture, and the others keep their
  /// numbers.
  func testNamesKeepLabelsUniqueAndNumbersStable() throws {
    let names = [RoomName(roomId: "room-2", derivedLabel: "Room 2", name: "Bedroom")]
    let named = try map(names)
    XCTAssertEqual(named.model.rooms.map(\.label), ["Bedroom 2", "Bedroom", "Closet"])
    XCTAssertEqual(Set(named.model.rooms.map { $0.label.lowercased() }).count, 3)
  }

  /// A one-room capture: the operator's area name, then a rename of the room.
  func testASingleRoomCaptureCanBeRenamed() throws {
    var mapped = try mapFixture("box-room")
    mapped.context.label = "Room Mexico"
    let plain = try RoomNaming.map(mapped.document, context: mapped.context, names: [])
    XCTAssertEqual(plain.derivedLabels, ["Room 1"])
    XCTAssertEqual(plain.model.rooms[0].label, "Room 1", "context.roomLabels is not used")
    let named = try RoomNaming.map(
      mapped.document, context: mapped.context,
      names: [RoomName(roomId: "room-1", derivedLabel: "Room 1", name: "Shower")])
    XCTAssertEqual(named.model.rooms.map(\.label), ["Shower"])
    XCTAssertEqual(named.model.rooms.map(\.type), [.bathroom])
    XCTAssertEqual(named.model.rooms.map(\.typeSource), [.operator])
  }
}
