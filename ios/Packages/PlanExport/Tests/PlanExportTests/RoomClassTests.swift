import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// The room fill rule shared by the plan sheet and the spatial report (plan-sheet §3.4.1,
/// critique R-35).
final class RoomClassTests: XCTestCase {
  private func fill(
    _ label: String, _ type: RoomType? = nil, objects: [ObjectCategory] = [],
    mode: CaptureMode = .floor
  ) -> RoomFillClass {
    RoomFillClass.of(label: label, type: type, objects: objects, mode: mode)
  }

  func testTypesLabelsAndObjects() {
    XCTAssertEqual(fill("Bedroom 2", .bedroom), .habitable)
    XCTAssertEqual(fill("Living Room", .livingRoom), .habitable)
    XCTAssertEqual(fill("Dining", .diningRoom), .habitable)
    XCTAssertEqual(fill("Study", nil), .habitable)
    for type in [RoomType.bathroom, .kitchen, .laundry] {
      XCTAssertEqual(fill("Room", type), .wet, "\(type)")
    }
    XCTAssertEqual(fill("Closet", .closet), .other)
    XCTAssertEqual(fill("Hallway", .hallway), .other)
    XCTAssertEqual(fill("Utility", .utility), .other)
    XCTAssertEqual(fill("Room 3", nil), .other)
    XCTAssertEqual(fill("Room 3", .other), .other)
    // Unlabeled rooms by what they hold.
    XCTAssertEqual(fill("Room 3", nil, objects: [.bed]), .habitable)
    XCTAssertEqual(fill("Room 3", .other, objects: [.toilet]), .wet)
    XCTAssertEqual(fill("Room 3", nil, objects: [.washerDryer, .bed]), .wet)
    XCTAssertEqual(fill("Room 3", nil, objects: [.storage, .sofa]), .other)
    // A typed room keeps its class whatever it holds.
    XCTAssertEqual(fill("Closet", .closet, objects: [.toilet]), .other)
    // Outdoor by label, and every room of an exterior capture.
    XCTAssertEqual(fill("Balcony"), .outdoor)
    XCTAssertEqual(fill("Back porch", .other), .outdoor)
    XCTAssertEqual(fill("Roof terrace", .livingRoom), .outdoor)
    XCTAssertEqual(fill("Bedroom", .bedroom, mode: .exterior), .outdoor)
  }

  func testARenamedShowerIsWet() {
    // The Oct 18 rename (a closet the operator calls "Shower"): wet whether the model typed it
    // a bathroom (1.1.0, `RoomTyping.renamedByOperator`) or has no type (1.0.0).
    XCTAssertEqual(fill("Shower", nil), .wet)
    XCTAssertEqual(fill("Shower", .bathroom), .wet)
    XCTAssertEqual(fill("Shower", .closet), .wet, "the label wins over a closet type")
    XCTAssertEqual(fill("WC"), .wet)
    XCTAssertEqual(fill("Guest toilet"), .wet)
  }

  func testTheSheetFillsEachClassWithItsToken() {
    XCTAssertEqual(RoomFillClass.habitable.fill, DrawingColor(hex: 0xE8DDD0))
    XCTAssertEqual(RoomFillClass.wet.fill, DrawingColor(hex: 0xEFE6DA))
    XCTAssertEqual(RoomFillClass.other.fill, DrawingColor(hex: 0xF5EFE6))
    XCTAssertNil(RoomFillClass.outdoor.fill)
    // The three fills print as three greys at least 3 points apart (Rec. 709 luma).
    let greys = [RoomFillClass.habitable, .wet, .other].map { DrawingRaster.gray($0.fill!) * 100 }
    XCTAssertEqual(greys[0], 87.2, accuracy: 0.1)
    XCTAssertEqual(greys[1], 90.6, accuracy: 0.1)
    XCTAssertEqual(greys[2], 94.0, accuracy: 0.1)
    XCTAssertGreaterThanOrEqual(greys[1] - greys[0], 3)
    XCTAssertGreaterThanOrEqual(greys[2] - greys[1], 3)
  }

  func testTheFourTwentyFourSampleRooms() throws {
    let sample = try Fixtures.sample424()
    let drawing = try FloorPlanDrawing(
      model: sample.model,
      options: .init(roomNames: false, roomAreas: false, rendition: .planSheet))
    let byLabel = Dictionary(
      uniqueKeysWithValues: sample.model.rooms.map { ($0.label, drawing.fillClasses[$0.id]) })
    for label in ["Bedroom 1", "Bedroom 2", "Living Room"] {
      XCTAssertEqual(byLabel[label], .habitable, label)
    }
    for label in ["Bathroom 1", "Bathroom 2", "Kitchen"] {
      XCTAssertEqual(byLabel[label], .wet, label)
    }
    for label in ["Closet", "Room 1", "Room 2", "Room 3", "Room 4", "Room 5"] {
      XCTAssertEqual(byLabel[label], .other, label)
    }
  }
}
