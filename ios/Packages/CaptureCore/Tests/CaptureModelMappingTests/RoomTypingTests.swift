import CaptureContract
import CaptureModelMapping
import CaptureTestSupport
import Foundation
import XCTest

/// Room types and labels from RoomPlan sections and objects (floorplan plan, phase 2).
final class RoomTypingTests: XCTestCase {
  /// A 4 x 3 m room in plan, counter-clockwise from +Y.
  private let square = [Vector3(0, 0, 0), Vector3(0, 0, 3), Vector3(4, 0, 3), Vector3(4, 0, 0)]
  private let inside = Vector3(2, 0, 1.5)
  private let outside = Vector3(6, 0, 1.5)

  private func section(_ label: String, at point: Vector3?) -> RoomPlanSection {
    RoomPlanSection(label: label, story: 0, center: point)
  }

  private func objects(_ categories: [ObjectCategory], at point: Vector3) -> [RoomTyping.Object] {
    categories.map { RoomTyping.Object(category: $0, center: point) }
  }

  // MARK: Pure rules

  func testPlanContainment() {
    XCTAssertTrue(PolygonMath.contains(square, inside))
    XCTAssertFalse(PolygonMath.contains(square, outside))
    XCTAssertTrue(PolygonMath.contains(square.reversed(), inside), "winding does not matter")
    XCTAssertTrue(PolygonMath.contains(square, Vector3(2, 50, 1.5)), "height does not matter")
    // L shape: the notch at the top right is outside.
    let lShape = [
      Vector3(0, 0, 0), Vector3(0, 0, 4), Vector3(4, 0, 4), Vector3(4, 0, 2), Vector3(2, 0, 2),
      Vector3(2, 0, 0),
    ]
    XCTAssertTrue(PolygonMath.contains(lShape, Vector3(1, 0, 1)))
    XCTAssertTrue(PolygonMath.contains(lShape, Vector3(3, 0, 3)))
    XCTAssertFalse(PolygonMath.contains(lShape, Vector3(3, 0, 1)))
    XCTAssertFalse(PolygonMath.contains(Array(square.prefix(2)), inside), "not a polygon")
  }

  func testOneSectionTypeInsideTheRoomGivesTheType() {
    let bedroom = RoomTyping.Result.typed(.bedroom, .roomplanSection)
    XCTAssertEqual(RoomTyping.type(polygon: square, sections: [section("bedroom", at: inside)], objects: []), bedroom)
    XCTAssertEqual(
      RoomTyping.type(
        polygon: square, sections: [section("bedroom", at: inside), section("bedroom", at: Vector3(1, 0, 1))],
        objects: []), bedroom, "two sections of one type")
    XCTAssertEqual(
      RoomTyping.type(
        polygon: square, sections: [section("unidentified", at: inside), section("bedroom", at: inside)],
        objects: []), bedroom, "unidentified is ignored")
    XCTAssertEqual(
      RoomTyping.type(
        polygon: square, sections: [section("bedroom", at: inside), section("kitchen", at: outside)],
        objects: []), bedroom, "a section outside the room is ignored")
    XCTAssertEqual(
      RoomTyping.type(
        polygon: square, sections: [section("bedroom", at: inside)], objects: objects([.toilet], at: inside)),
      bedroom, "a section wins over the objects")
  }

  func testSectionsOfTwoTypesInOneRoomAreMixed() {
    XCTAssertEqual(
      RoomTyping.type(
        polygon: square, sections: [section("bedroom", at: inside), section("kitchen", at: Vector3(1, 0, 1))],
        objects: objects([.bed], at: inside)), .mixed)
  }

  func testWithoutAUsableSectionTheObjectsInsideTellTheType() {
    let unusable = [
      section("unidentified", at: inside), section("garage", at: inside), section("bedroom", at: nil),
      section("kitchen", at: outside),
    ]
    XCTAssertEqual(
      RoomTyping.type(polygon: square, sections: unusable, objects: objects([.toilet], at: inside)),
      .typed(.bathroom, .inferred))
    XCTAssertEqual(
      RoomTyping.type(polygon: square, sections: unusable, objects: objects([.toilet], at: outside)), .unknown,
      "an object outside the room does not count")
    XCTAssertEqual(RoomTyping.type(polygon: square, sections: [], objects: []), .unknown)
  }

  func testInferenceRulesInOrder() {
    let cases: [([ObjectCategory], RoomType?)] = [
      ([.toilet], .bathroom),
      ([.bathtub], .bathroom),
      ([.stove], .kitchen),
      ([.oven], .kitchen),
      ([.refrigerator], .kitchen),
      ([.dishwasher], .kitchen),
      ([.bed], .bedroom),
      ([.washerDryer], .laundry),
      ([.sofa], .livingRoom),
      ([.television], .livingRoom),
      ([.fireplace], .livingRoom),
      ([.chair, .table, .chair], .diningRoom),
      ([.table, .chair], nil),
      ([.chair, .chair], nil),
      ([.sink, .storage, .stairs, .other], nil),
      ([], nil),
      // The first matching rule wins.
      ([.bed, .bathtub], .bathroom),
      ([.sofa, .refrigerator], .kitchen),
      ([.washerDryer, .bed], .bedroom),
      ([.television, .washerDryer], .laundry),
      ([.table, .chair, .chair, .sofa], .livingRoom),
    ]
    for (categories, type) in cases {
      XCTAssertEqual(RoomTyping.inferredType(from: categories), type, "\(categories)")
    }
  }

  func testLabelsOfEveryType() {
    let labels = RoomType.allCases.map { RoomTyping.label(of: $0) }
    XCTAssertEqual(
      labels,
      [
        "Living Room", "Dining Room", "Kitchen", "Bedroom", "Bathroom", "Closet", "Hallway", "Laundry", "Office",
        "Utility", nil,
      ])
  }

  func testLabelsAreNumberedWhenATypeRepeats() {
    let results: [RoomTyping.Result] = [
      .typed(.bedroom, .roomplanSection), .unknown, .typed(.bedroom, .inferred), .typed(.kitchen, .roomplanSection),
      .typed(.other, .operator), .typed(.bedroom, .roomplanSection),
    ]
    XCTAssertEqual(
      RoomTyping.labels(for: results, captureLabel: "Floor 1"),
      ["Bedroom 1", "Room 2", "Bedroom 2", "Kitchen", "Room 5", "Bedroom 3"])
  }

  func testMixedRoomsTakeTheCaptureLabel() {
    XCTAssertEqual(RoomTyping.labels(for: [.mixed], captureLabel: "Apartment"), ["Apartment"])
    XCTAssertEqual(
      RoomTyping.labels(for: [.mixed, .typed(.bedroom, .inferred), .mixed], captureLabel: "Apartment"),
      ["Apartment 1", "Bedroom", "Apartment 2"])
    XCTAssertEqual(RoomTyping.labels(for: [.mixed], captureLabel: " "), ["Room 1"])
  }

  func testOverridesReplaceLabelsWithoutRenumberingTheOthers() {
    let bedrooms: [RoomTyping.Result] = [.typed(.bedroom, .roomplanSection), .typed(.bedroom, .roomplanSection)]
    XCTAssertEqual(
      RoomTyping.labels(for: bedrooms, captureLabel: "Floor 1", overrides: ["Primary Bedroom"]),
      ["Primary Bedroom", "Bedroom 2"])
    XCTAssertEqual(
      RoomTyping.labels(for: bedrooms, captureLabel: "Floor 1", overrides: ["", "Guest Room"]),
      ["Bedroom 1", "Guest Room"], "a blank override keeps the derived label")
  }

  func testLabelsAreUniqueWithinACapture() {
    // A derived label gives way to an override, compared ignoring case and repeated spaces.
    XCTAssertEqual(
      RoomTyping.labels(
        for: [.typed(.kitchen, .roomplanSection), .unknown], captureLabel: "Floor 1", overrides: ["", "KITCHEN "]),
      ["Kitchen 2", "KITCHEN "])
    XCTAssertEqual(
      RoomTyping.labels(for: [.unknown, .unknown], captureLabel: "Floor 1", overrides: ["Den", "den"]),
      ["Den", "den 2"])
    XCTAssertEqual(
      RoomTyping.labels(for: [.mixed, .typed(.kitchen, .inferred)], captureLabel: "Kitchen"),
      ["Kitchen 1", "Kitchen 2"])
    XCTAssertEqual(
      RoomTyping.labels(
        for: [.unknown, .typed(.bedroom, .inferred), .typed(.bedroom, .inferred)], captureLabel: "Floor 1",
        overrides: ["Bedroom 2"]),
      ["Bedroom 2", "Bedroom 1", "Bedroom 2 2"])
  }

  // MARK: Through the mapper

  func testTwoRoomApartmentIsALivingRoomAndABedroomFromItsSections() throws {
    var mapped = try mapFixture("two-room-apartment")
    mapped.context.roomLabels = []
    let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.rooms.map(\.label), ["Living Room", "Bedroom"])
    XCTAssertEqual(model.rooms.map(\.type), [.livingRoom, .bedroom])
    XCTAssertEqual(model.rooms.map(\.typeSource), [.roomplanSection, .roomplanSection])
    // The same labels the generator gave the rooms.
    XCTAssertEqual(
      model.rooms.map(\.label), try XCTUnwrap(mapped.expected["rooms"]?.array).compactMap { $0["label"]?.string })
  }

  func testTwoBedroomsAreNumbered() throws {
    var mapped = try mapFixture("two-room-apartment")
    mapped.context.roomLabels = []
    mapped.document.rooms[0].sections[0].label = "bedroom"
    let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.rooms.map(\.label), ["Bedroom 1", "Bedroom 2"])
    XCTAssertEqual(model.rooms.map(\.type), [.bedroom, .bedroom])
  }

  func testStructureSectionsOnTheSameStoryAreUsedWhenARoomHasNone() throws {
    var mapped = try mapFixture("two-room-apartment")
    mapped.context.roomLabels = []
    for index in mapped.document.rooms.indices { mapped.document.rooms[index].sections = [] }
    var model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.rooms.map(\.type), [.livingRoom, .bedroom])
    XCTAssertEqual(model.rooms.map(\.typeSource), [.roomplanSection, .roomplanSection])

    // Sections of another story do not count; the sofa and the bed then tell the types.
    for index in mapped.document.sections.indices { mapped.document.sections[index].story = 1 }
    model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.rooms.map(\.type), [.livingRoom, .bedroom])
    XCTAssertEqual(model.rooms.map(\.typeSource), [.inferred, .inferred])
    XCTAssertEqual(model.rooms.map(\.label), ["Living Room", "Bedroom"])
  }

  func testSectionsOfTwoTypesInOneRoomGiveTheCaptureLabelAndNoType() throws {
    var mapped = try mapFixture("two-room-apartment")
    mapped.context.roomLabels = []
    let living = try XCTUnwrap(mapped.document.rooms[0].sections.first)
    mapped.document.rooms[0].sections.append(
      RoomPlanSection(label: "kitchen", story: 0, center: try XCTUnwrap(living.center) + Vector3(1, 0, 0)))
    let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    XCTAssertEqual(model.rooms.map(\.label), [mapped.context.label, "Bedroom"])
    XCTAssertEqual(model.rooms.map(\.type), [nil, .bedroom])
    XCTAssertEqual(model.rooms.map(\.typeSource), [nil, .roomplanSection])
  }

  func testUnidentifiedSectionFallsBackToTheObjects() throws {
    // The box room has an unidentified section and one table.
    func room(_ categories: [String], moved offset: Vector3 = .zero) throws -> CaptureModel.Room {
      var mapped = try mapFixture("box-room")
      mapped.context.roomLabels = []
      XCTAssertEqual(mapped.document.rooms[0].sections.map(\.label), ["unidentified"])
      let table = mapped.document.rooms[0].objects[0]
      mapped.document.rooms[0].objects = categories.enumerated().map { index, name in
        var object = table
        object.identifier = "OBJECT-\(index)"
        object.category = RoomPlanCategory(name: name)
        object.transform.columns[3][0] += offset.x
        object.transform.columns[3][2] += offset.z
        return object
      }
      return try CaptureModelMapper.map(mapped.document, context: mapped.context).rooms[0]
    }
    let cases: [([String], RoomType?, String)] = [
      (["table"], nil, "Room 1"),
      (["toilet"], .bathroom, "Bathroom"),
      (["oven"], .kitchen, "Kitchen"),
      (["bed"], .bedroom, "Bedroom"),
      (["washerDryer"], .laundry, "Laundry"),
      (["television"], .livingRoom, "Living Room"),
      (["table", "chair", "chair"], .diningRoom, "Dining Room"),
      (["table", "chair"], nil, "Room 1"),
    ]
    for (categories, type, label) in cases {
      let mapped = try room(categories)
      XCTAssertEqual(mapped.type, type, "\(categories)")
      XCTAssertEqual(mapped.typeSource, type == nil ? nil : .inferred, "\(categories)")
      XCTAssertEqual(mapped.label, label, "\(categories)")
    }
    XCTAssertNil(try room(["toilet"], moved: Vector3(10, 0, 0)).type, "an object outside the room does not count")
  }
}
