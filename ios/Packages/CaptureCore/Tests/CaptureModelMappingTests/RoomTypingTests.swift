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

  func testTwoSectionsOfOneTypeInOneRoomAreMixed() {
    // RoomPlan reports one section per room it recognises, so two bedroom sections inside one
    // outline are two bedrooms that a walk-through scan joined.
    XCTAssertEqual(
      RoomTyping.type(
        polygon: square, sections: [section("bedroom", at: inside), section("bedroom", at: Vector3(1, 0, 1))],
        objects: []), .mixed)
  }

  func testObjectsOfTwoKindsOfRoomAreMixed() {
    let none: [RoomPlanSection] = []
    XCTAssertEqual(
      RoomTyping.type(polygon: square, sections: none, objects: objects([.toilet, .bed, .stove], at: inside)),
      .mixed, "a walk-through scan with no usable section")
    XCTAssertEqual(
      RoomTyping.type(polygon: square, sections: none, objects: objects([.bathtub, .refrigerator], at: inside)),
      .mixed)
    XCTAssertEqual(
      RoomTyping.type(polygon: square, sections: none, objects: objects([.bed, .sofa, .television], at: inside)),
      .typed(.bedroom, .inferred), "a sofa or a television also stands in a bedroom")
    XCTAssertEqual(
      RoomTyping.type(
        polygon: square, sections: none, objects: objects([.stove, .table, .chair, .chair], at: inside)),
      .typed(.kitchen, .inferred), "a table and chairs also stand in a kitchen")
    XCTAssertEqual(
      RoomTyping.type(
        polygon: square, sections: [section("bathroom", at: inside)],
        objects: objects([.toilet, .bed, .stove], at: inside)),
      .typed(.bathroom, .roomplanSection), "a section wins over mixed objects")
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
      ([.chair, .table, .chair], nil),  // a desk and office chairs look the same
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

  func testAreaNamesThatNameARoom() {
    let cases: [(String, RoomType?)] = [
      ("Office", .office), ("Home study", .office), ("Kitchen", .kitchen),
      ("Primary bedroom", .bedroom), ("Guest Bath", .bathroom), ("Hall bath", .bathroom),
      ("Living / dining", .livingRoom), ("Dining room", .diningRoom), ("Front hall", .hallway),
      ("Laundry", .laundry), ("Coat closet", .closet), ("Floor 1", nil), ("Apartment", nil),
      ("", nil), ("Bedrooms wing", nil),
    ]
    for (label, type) in cases {
      XCTAssertEqual(RoomTyping.areaType(label), type, label)
    }
  }

  func testTheOperatorNamesASingleRoom() {
    let inferred = RoomTyping.Result.typed(.diningRoom, .inferred)
    XCTAssertEqual(RoomTyping.namedByOperator([inferred], captureLabel: "Office"), [.typed(.office, .operator)])
    XCTAssertEqual(
      RoomTyping.namedByOperator([.typed(.bedroom, .roomplanSection)], captureLabel: "Kitchen"),
      [.typed(.kitchen, .operator)], "the operator wins over RoomPlan's section")
    XCTAssertEqual(RoomTyping.namedByOperator([.unknown], captureLabel: "Floor 1"), [.unknown])
    XCTAssertEqual(
      RoomTyping.namedByOperator([inferred, .unknown], captureLabel: "Office"), [inferred, .unknown],
      "two or more rooms keep their own types")
    XCTAssertEqual(
      RoomTyping.labels(for: [.typed(.office, .operator)], captureLabel: "Eran's office"), ["Eran's office"])
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

  func testNumberedLabelsStayWithinTheSchemaLimit() {
    func a(_ count: Int) -> String { String(repeating: "a", count: count) }
    // A capture label can be 100 characters: the number takes the end of it.
    XCTAssertEqual(RoomTyping.labels(for: [.mixed, .mixed], captureLabel: a(100)), [a(98) + " 1", a(98) + " 2"])
    XCTAssertEqual(RoomTyping.labels(for: [.mixed], captureLabel: a(100)), [a(100)], "no number, not shortened")
    let ten = RoomTyping.labels(for: Array(repeating: .mixed, count: 10), captureLabel: a(100))
    XCTAssertEqual(ten.first, a(98) + " 1")
    XCTAssertEqual(ten.last, a(97) + " 10")
    XCTAssertEqual(Set(ten).count, 10)
    XCTAssertEqual(
      RoomTyping.labels(for: [.mixed, .mixed], captureLabel: a(97) + " bc"), [a(97) + " 1", a(97) + " 2"],
      "white space left at the end of the shortened label is dropped")
    // Counted in Unicode scalars as the schema counts them, dropping whole characters: e and a
    // combining accent are one character and two scalars.
    let accented = "a" + String(repeating: "e\u{301}", count: 49) + "b"
    XCTAssertEqual(
      RoomTyping.labels(for: [.mixed, .mixed], captureLabel: accented),
      ["a" + String(repeating: "e\u{301}", count: 48) + " 1", "a" + String(repeating: "e\u{301}", count: 48) + " 2"])
    // A label made unique gets its number the same way.
    XCTAssertEqual(
      RoomTyping.labels(for: [.unknown, .unknown], captureLabel: "Floor 1", overrides: [a(99), a(99)]),
      [a(99), a(98) + " 2"])
    // `<label> 1` taken by an override would become `<label> 1 2`; shortened, it is `<label> 2`,
    // so the next mixed room moves on to 3.
    let clash = RoomTyping.labels(
      for: [.mixed, .mixed, .unknown], captureLabel: a(100), overrides: ["", "", a(98) + " 1"])
    XCTAssertEqual(clash, [a(98) + " 2", a(98) + " 3", a(98) + " 1"])

    for labels in [ten, clash, RoomTyping.labels(for: [.mixed, .mixed], captureLabel: accented)] {
      for label in labels {
        XCTAssertLessThanOrEqual(label.unicodeScalars.count, RoomTyping.maximumLabelLength, label)
      }
    }
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

  /// A 100-character floor label and two mixed rooms, as a paused and resumed walk-through can
  /// give: the numbered labels stay within the schema's 100.
  func testTwoMixedRoomsWithALongCaptureLabelValidateAgainstTheSchema() throws {
    var mapped = try mapFixture("two-room-apartment")
    mapped.context.roomLabels = []
    mapped.context.label = String(repeating: "a", count: 100)
    for index in mapped.document.rooms.indices {
      let section = try XCTUnwrap(mapped.document.rooms[index].sections.first)
      mapped.document.rooms[index].sections.append(
        RoomPlanSection(label: "kitchen", story: section.story, center: section.center))
    }
    let model = try CaptureModelMapper.map(mapped.document, context: mapped.context)
    let shortened = String(repeating: "a", count: 98)
    XCTAssertEqual(model.rooms.map(\.label), [shortened + " 1", shortened + " 2"])
    XCTAssertEqual(model.rooms.map(\.type), [nil, nil])
    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
    XCTAssertEqual(validator.validate(try encodedJSON(model)), [])
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
      (["table", "chair", "chair"], nil, "Room 1"),
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
