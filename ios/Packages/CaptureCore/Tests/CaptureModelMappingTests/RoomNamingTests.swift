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
    let rooms = [(id: "room-1", derivedLabel: "Bedroom"), (id: "room-2", derivedLabel: "Room 2"),
                 (id: "room-3", derivedLabel: "Closet")]
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
