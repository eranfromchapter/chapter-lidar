import CaptureContract
import FieldRules
import Foundation
import XCTest

/// "Still needs a photo" on the photo step is the checklist's "A photo for every room" rule.
final class PhotoCoverageTests: XCTestCase {
  private let f1 = Fixtures.floor1
  private let f2 = Fixtures.floor2

  func testRoomsWithoutAPhotoInRoomOrder() {
    let photos = [
      Fixtures.photo(capture: f1, room: "Bedroom", sequence: 1),
      Fixtures.photo(capture: f1, room: " bathroom ", sequence: 2),
    ]
    let status = PhotoCoverage.status(rooms: ["Bedroom", "Bathroom", "Shower"], photos: photos)
    XCTAssertEqual(status.rooms, ["Bedroom", "Bathroom", "Shower"])
    XCTAssertEqual(status.roomsWithoutPhoto, ["Shower"])
    XCTAssertFalse(status.isComplete)
    XCTAssertEqual(status.text, "Still needs a photo: Shower")
    XCTAssertTrue(status.needsPhoto("shower "))
    XCTAssertFalse(status.needsPhoto("Bathroom"))

    let none = PhotoCoverage.status(rooms: ["Bedroom", "Shower"], photos: [])
    XCTAssertEqual(none.text, "Still needs a photo: Bedroom, Shower")

    let done = PhotoCoverage.status(
      rooms: ["Bedroom", "Bathroom"], photos: photos)
    XCTAssertTrue(done.isComplete)
    XCTAssertEqual(done.text, "Every room has a photo")
  }

  func testBlankAndRepeatedRoomsCountOnce() {
    XCTAssertEqual(PhotoCoverage.rooms(["Kitchen", " ", "kitchen ", "Bath", ""]), ["Kitchen", "Bath"])
    XCTAssertEqual(PhotoCoverage.key("  Half Bath \n"), "half bath")
  }

  func testACaptureWithoutRoomsNeedsAPhotoOfAnyKind() {
    let empty = PhotoCoverage.status(rooms: [], photos: [])
    XCTAssertTrue(empty.needsAnyPhoto)
    XCTAssertEqual(empty.text, "Still needs a photo")
    let one = PhotoCoverage.status(rooms: [" "], photos: [Fixtures.photo(capture: f1, room: "Porch")])
    XCTAssertTrue(one.isComplete)
    XCTAssertEqual(one.text, "Every room has a photo")
  }

  /// The checklist row and the photo step agree, room for room, on every capture.
  func testTheChecklistUsesTheSameRule() {
    let record = Fixtures.record(captures: [
      Fixtures.capture(f1.captureId, areaKey: "floor-1", label: "Room Mexico"),
      Fixtures.capture(f2.captureId, areaKey: "floor-2", label: "Porch", at: Fixtures.t1),
    ])
    let rooms: [LowercaseUUID: [String]] = [
      f1.captureId: ["Bedroom", "Bathroom", "Closet"], f2.captureId: [],
    ]
    let photos = [
      Fixtures.photo(capture: f1, room: "Bedroom", sequence: 1),
      Fixtures.photo(capture: f1, room: "BATHROOM", sequence: 2),
      // A photo of another capture never covers this one's rooms.
      Fixtures.photo(capture: f2, room: "Closet", sequence: 1),
    ]
    let report = ChecklistRules.evaluate(
      ChecklistInput(
        record: record, capturedRooms: rooms, photos: photos,
        controls: FieldControlsEditor(visitId: Fixtures.visitId).controls))
    let coverage = PhotoCoverage.status(
      rooms: rooms[f1.captureId]!, photos: photos.filter { $0.captureId == f1.captureId })
    XCTAssertEqual(coverage.roomsWithoutPhoto, ["Closet"])
    XCTAssertEqual(
      report.item(.photoPerRoom).gaps,
      coverage.roomsWithoutPhoto.map { .roomWithoutPhoto(capture: "Room Mexico", room: $0) })
    XCTAssertEqual(report.item(.photoPerRoom).detail, "Closet has no photo")
  }
}
