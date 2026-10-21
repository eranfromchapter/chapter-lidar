import FieldRules
import XCTest

/// Review of 2026-10-20: "Take photo" on "Closet has no photo" preselected the Closet, but with
/// more rooms than chips its chip was behind "More", so no chip showed which room the photo
/// would be filed under. Design v2 (2d-1) shows 4 rooms before More, and the selected room stays
/// on screen because it stays selected for the next photo.
final class RoomChipsTests: XCTestCase {
  private let walkthrough = [
    "Bedroom 1", "Kitchen", "Living Room", "Bedroom 2", "Bathroom", "Hallway", "Closet",
  ]

  func testFourRoomsAreShownBeforeMore() {
    XCTAssertEqual(RoomChips.shownBeforeMore, 4)
    XCTAssertEqual(
      RoomChips.primary(walkthrough, target: nil),
      ["Bedroom 1", "Kitchen", "Living Room", "Bedroom 2"])
    XCTAssertEqual(RoomChips.more(walkthrough, target: nil), ["Bathroom", "Hallway", "Closet"])
  }

  func testTheSelectedRoomBeyondFourIsAppended() {
    XCTAssertEqual(
      RoomChips.primary(walkthrough, target: "Closet"),
      ["Bedroom 1", "Kitchen", "Living Room", "Bedroom 2", "Closet"])
    XCTAssertEqual(RoomChips.more(walkthrough, target: "Closet"), ["Bathroom", "Hallway"])
    // Compared as the checklist compares rooms.
    XCTAssertEqual(RoomChips.primary(walkthrough, target: " closet ").last, "Closet")
  }

  func testATargetAlreadyShownOrNotARoomChangesNothing() {
    let first = ["Bedroom 1", "Kitchen", "Living Room", "Bedroom 2"]
    XCTAssertEqual(RoomChips.primary(walkthrough, target: "Kitchen"), first)
    XCTAssertEqual(
      RoomChips.primary(walkthrough, target: "Garage"), first, "not a room of the capture")
    XCTAssertEqual(
      RoomChips.primary(["Bedroom", "Bathroom", "Closet"], target: "Closet"),
      ["Bedroom", "Bathroom", "Closet"])
    XCTAssertEqual(RoomChips.more(["Bedroom", "Bathroom", "Closet"], target: "Closet"), [])
    XCTAssertEqual(RoomChips.primary([], target: "Closet"), [])
  }
}
