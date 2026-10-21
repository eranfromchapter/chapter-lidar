import FieldRules
import XCTest

/// Review of 2026-10-20: "Take photo" on "Closet has no photo" preselected the Closet, but with
/// more than three rooms its chip was behind "More…", so no chip showed which room the photo
/// would be filed under.
final class RoomChipsTests: XCTestCase {
  private let walkthrough = [
    "Bedroom 1", "Kitchen", "Living Room", "Bedroom 2", "Bathroom", "Hallway", "Closet",
  ]

  func testTheRoomTheOperatorCameForIsShownBeforeMore() {
    XCTAssertEqual(
      RoomChips.primary(walkthrough, target: "Closet"), ["Bedroom 1", "Kitchen", "Living Room", "Closet"])
    XCTAssertEqual(
      RoomChips.more(walkthrough, target: "Closet"), ["Bedroom 2", "Bathroom", "Hallway"])
    // Compared as the checklist compares rooms.
    XCTAssertEqual(RoomChips.primary(walkthrough, target: " closet ").last, "Closet")
  }

  func testWithoutATargetOrWithOneAlreadyShownTheFirstThree() {
    let first = ["Bedroom 1", "Kitchen", "Living Room"]
    XCTAssertEqual(RoomChips.primary(walkthrough, target: nil), first)
    XCTAssertEqual(RoomChips.primary(walkthrough, target: "Kitchen"), first)
    XCTAssertEqual(RoomChips.primary(walkthrough, target: "Garage"), first, "not a room of the capture")
    XCTAssertEqual(RoomChips.more(walkthrough, target: nil).count, 4)
    XCTAssertEqual(RoomChips.primary(["Bedroom", "Bathroom", "Closet"], target: "Closet"), ["Bedroom", "Bathroom", "Closet"])
    XCTAssertEqual(RoomChips.more(["Bedroom", "Bathroom", "Closet"], target: "Closet"), [])
    XCTAssertEqual(RoomChips.primary([], target: "Closet"), [])
  }
}
