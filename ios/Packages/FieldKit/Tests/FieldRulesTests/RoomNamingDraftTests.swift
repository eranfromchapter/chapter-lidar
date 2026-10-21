import CaptureContract
import FieldRules
import Foundation
import XCTest

/// The "Rename rooms" sheet's checks: what can be saved and what changes.
final class RoomNamingDraftTests: XCTestCase {
  private let mexico = Fixtures.floor1Id
  private let porch = Fixtures.floor2Id

  private func draft() -> RoomNamingDraft {
    RoomNamingDraft(captures: [
      RoomNamingDraft.Capture(
        captureId: mexico, label: "Room Mexico",
        rooms: [
          RoomNamingDraft.Room(
            captureId: mexico, roomId: "room-1", scannedLabel: "Bedroom", currentLabel: "Bedroom",
            detail: "21.8 m²"),
          RoomNamingDraft.Room(
            captureId: mexico, roomId: "room-2", scannedLabel: "Bathroom", currentLabel: "Bathroom"),
          RoomNamingDraft.Room(
            captureId: mexico, roomId: "room-3", scannedLabel: "Closet", currentLabel: "Closet",
            detail: "1.9 m²"),
        ]),
      RoomNamingDraft.Capture(
        captureId: porch, label: "Porch",
        rooms: [
          RoomNamingDraft.Room(
            captureId: porch, roomId: "room-1", scannedLabel: "Room 1", currentLabel: "Closet")
        ]),
    ])
  }

  private func id(_ capture: LowercaseUUID, _ room: String) -> String { "\(capture.rawValue)/\(room)" }

  func testNamesStartAsTheCurrentLabelsAndNothingToSave() {
    let draft = draft()
    XCTAssertEqual(draft.rooms.map(\.name), ["Bedroom", "Bathroom", "Closet", "Closet"])
    XCTAssertEqual(draft.changes, [])
    XCTAssertFalse(draft.canSave)
    XCTAssertFalse(draft.hasIssues, "the same name on two floors is fine")
    XCTAssertEqual(draft.rooms[2].caption, "Scanned as Closet \u{00B7} 1.9 m²")
    XCTAssertEqual(draft.rooms[3].caption, "Scanned as Room 1", "renamed before")
    XCTAssertEqual(draft.rooms[3].name, "Closet", "the field starts with the current name")
    XCTAssertEqual(draft.rooms[1].caption, "Scanned as Bathroom")
  }

  func testClosetToShower() {
    var draft = draft()
    draft.setName("  Shower ", room: id(mexico, "room-3"))
    XCTAssertNil(draft.issue(room: id(mexico, "room-3")))
    XCTAssertTrue(draft.canSave)
    XCTAssertEqual(
      draft.changes,
      [RoomRename(captureId: mexico, roomId: "room-3", scannedLabel: "Closet", from: "Closet", to: "Shower")])
    XCTAssertEqual(draft.rooms[2].caption, "Scanned as Closet \u{00B7} 1.9 m²")
    XCTAssertTrue(RoomNamingDraft.suggestions.contains("Shower"))
    XCTAssertEqual(
      RoomNamingDraft.suggestions,
      ["Shower", "Closet", "Bathroom", "Half bath", "Hallway", "Entry", "Pantry", "Laundry", "Storage"])
  }

  func testBlankTooLongAndRepeatedNamesCannotBeSaved() {
    var draft = draft()
    draft.setName("   ", room: id(mexico, "room-3"))
    XCTAssertEqual(draft.issue(room: id(mexico, "room-3")), .empty)
    XCTAssertFalse(draft.canSave)

    draft.setName(String(repeating: "a", count: 101), room: id(mexico, "room-3"))
    XCTAssertEqual(draft.issue(room: id(mexico, "room-3")), .tooLong)
    draft.setName(String(repeating: "a", count: 100), room: id(mexico, "room-3"))
    XCTAssertNil(draft.issue(room: id(mexico, "room-3")))

    // Another room of the same capture: compared ignoring case and repeated spaces.
    draft.setName("bath room", room: id(mexico, "room-3"))
    XCTAssertNil(draft.issue(room: id(mexico, "room-3")))
    draft.setName(" BATHROOM", room: id(mexico, "room-3"))
    XCTAssertEqual(draft.issue(room: id(mexico, "room-3")), .duplicate("BATHROOM"))
    XCTAssertEqual(draft.issue(room: id(mexico, "room-2")), .duplicate("Bathroom"))
    XCTAssertEqual(draft.issue(room: id(mexico, "room-3"))?.text, "Another room is already called BATHROOM")
    XCTAssertFalse(draft.canSave)

    // Swapping two names in one save is fine.
    draft.setName("Closet", room: id(mexico, "room-2"))
    XCTAssertFalse(draft.hasIssues)
    XCTAssertEqual(draft.changes.map(\.from), ["Bathroom", "Closet"])
    XCTAssertEqual(draft.changes.map(\.to), ["Closet", "BATHROOM"])
  }

  func testAnEmptyCaptureIsLeftOut() {
    let draft = RoomNamingDraft(captures: [
      RoomNamingDraft.Capture(captureId: mexico, label: "Room Mexico", rooms: [])
    ])
    XCTAssertTrue(draft.isEmpty)
    XCTAssertFalse(draft.canSave)
  }
}
