import CaptureContract
import FieldRules
import XCTest

/// phone-field §3.5: the strip under the labels counts the room's photos with the one being
/// labeled and shows the last 4 as thumbnails.
final class PhotoStripTests: XCTestCase {
  private let f1 = Fixtures.floor1

  private func photos(_ rooms: [String]) -> [PhotoRecord] {
    rooms.enumerated().map {
      Fixtures.photo(capture: f1, room: $0.element, sequence: $0.offset + 1)
    }
  }

  func testFourKitchenPhotosAndThePendingOneMakeFive() {
    let strip = PhotoStrip(
      photos: photos(["Kitchen", "Living", "Kitchen", "kitchen ", "Kitchen", "Bath 1"]),
      room: "Kitchen")
    XCTAssertEqual(strip.count, 5)
    XCTAssertEqual(
      strip.text, "5 photos in Kitchen \u{00B7} keep people and personal items out of the frame")
    XCTAssertEqual(strip.thumbnails.map(\.sequence), [1, 3, 4, 5])
  }

  func testOnlyTheLastFourAreThumbnailsOldestFirst() {
    let strip = PhotoStrip(photos: photos(Array(repeating: "Kitchen", count: 6)), room: "Kitchen")
    XCTAssertEqual(strip.thumbnails.map(\.sequence), [3, 4, 5, 6])
    XCTAssertEqual(strip.count, 7)
  }

  func testTheFirstPhotoOfARoom() {
    let strip = PhotoStrip(photos: photos(["Living"]), room: " Shower ")
    XCTAssertEqual(strip.count, 1)
    XCTAssertEqual(strip.thumbnails, [])
    XCTAssertEqual(
      strip.text, "1 photo in Shower \u{00B7} keep people and personal items out of the frame")
  }

  func testNoRoomSelected() {
    for room in [nil, "  "] {
      let strip = PhotoStrip(photos: photos(["Kitchen"]), room: room)
      XCTAssertEqual(strip.text, "Keep people and personal items out of the frame.")
      XCTAssertEqual(strip.thumbnails, [])
    }
  }
}
