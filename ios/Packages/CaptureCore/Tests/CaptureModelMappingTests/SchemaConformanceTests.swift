import CaptureContract
import CaptureModelMapping
import CaptureTestSupport
import Foundation
import XCTest

/// AC3: the CaptureModel the mapping emits validates against capture-model.schema.json.
/// Swift has no JSON Schema library, so `SchemaValidator` (in CaptureTestSupport) checks the
/// keywords the schema uses, and the tests below check the schema's enums and required keys
/// directly as well.
final class SchemaConformanceTests: XCTestCase {
  private func validator() throws -> SchemaValidator {
    try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
  }

  func testMappedModelsValidateAgainstTheSchema() throws {
    let validator = try validator()
    for (name, index) in allGeneratedCaptures {
      let json = try encodedJSON(try mapFixture(name, capture: index).model)
      XCTAssertEqual(validator.validate(json), [], "\(name) capture \(index)")
    }
  }

  func testMappedModelsRoundTripThroughTheContractTypes() throws {
    let encoder = CaptureContractJSON.makeEncoder()
    for (name, index) in allGeneratedCaptures {
      let model = try mapFixture(name, capture: index).model
      let data = try encoder.encode(model)
      let decoded = try CaptureContractJSON.makeDecoder().decode(CaptureModel.self, from: data)
      XCTAssertEqual(decoded, model, "\(name) capture \(index)")
      XCTAssertEqual(try encoder.encode(decoded), data, "\(name) re-encodes to the same bytes")
      XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("null"), "optional fields are omitted, never null")
    }
  }

  func testEmittedKeysCoverTheSchemasRequiredKeysAndNothingElse() throws {
    let schema = try JSON.parse(contentsOf: Fixtures.schemaURL("capture-model.schema.json"))
    let required = try XCTUnwrap(schema["required"]?.array?.compactMap(\.string))
    let allowed = try XCTUnwrap({ () -> [String]? in
      if case .object(let properties)? = schema["properties"] { return Array(properties.keys) }
      return nil
    }())
    let json = try encodedJSON(try mapFixture("two-room-apartment").model)
    guard case .object(let members) = json else { return XCTFail("model is not an object") }
    for key in required { XCTAssertNotNil(members[key], "required key \(key)") }
    for key in members.keys { XCTAssertTrue(allowed.contains(key), "unexpected key \(key)") }

    // Nested required keys of walls, rooms, openings and objects.
    let defs = try XCTUnwrap(schema["$defs"])
    for (collection, def) in [("rooms", "room"), ("walls", "wall"), ("doors", "wallOpening"), ("windows", "wallOpening"), ("objects", "object")] {
      let requiredKeys = try XCTUnwrap(defs[def]?["required"]?.array?.compactMap(\.string))
      for item in try XCTUnwrap(json[collection]?.array) {
        guard case .object(let itemMembers) = item else { return XCTFail("\(collection) item") }
        for key in requiredKeys { XCTAssertNotNil(itemMembers[key], "\(collection) required key \(key)") }
      }
    }
  }

  func testEnumsInTheSchemaMatchTheTypesTheMapperUses() throws {
    let schema = try JSON.parse(contentsOf: Fixtures.schemaURL("capture-model.schema.json"))
    let defs = try XCTUnwrap(schema["$defs"])
    func strings(_ json: JSON?) throws -> Set<String> {
      Set(try XCTUnwrap(json?.array?.compactMap(\.string)))
    }
    XCTAssertEqual(try strings(defs["confidence"]?["enum"]), Set(DetectionConfidence.allCases.map(\.rawValue)))
    XCTAssertEqual(try strings(defs["object"]?["properties"]?["category"]?["enum"]), Set(ObjectCategory.allCases.map(\.rawValue)))
    XCTAssertEqual(try strings(defs["sourceRole"]?["enum"]), Set(GeometrySourceRole.allCases.map(\.rawValue)))
    XCTAssertEqual(schema["properties"]?["coordinateSystem"]?["properties"]?["up"]?["const"]?.string, UpAxis.positiveY.rawValue)
  }

  func testRoomPlanCategoriesAllMapToSchemaCategories() throws {
    let schema = try JSON.parse(contentsOf: Fixtures.schemaURL("capture-model.schema.json"))
    let allowed = Set(try XCTUnwrap(schema["$defs"]?["object"]?["properties"]?["category"]?["enum"]?.array?.compactMap(\.string)))
    let appleCategories = [
      "storage", "refrigerator", "stove", "bed", "sink", "washerDryer", "toilet", "bathtub", "oven",
      "dishwasher", "table", "sofa", "chair", "fireplace", "television", "stairs", "unknownFutureCase",
    ]
    for name in appleCategories {
      let mapped = RoomPlanCategory(name: name)
      var model = try mapFixture("box-room").model
      let document = try mapFixture("box-room").document
      var changed = document
      changed.rooms[0].objects[0].category = mapped
      model = try CaptureModelMapper.map(changed, context: try mapFixture("box-room").context)
      XCTAssertTrue(allowed.contains(model.objects[0].category.rawValue), name)
    }
  }

  func testValidatorAcceptsTheContractExampleAndRejectsTheInvalidOne() throws {
    let validator = try validator()
    let examples = Fixtures.repositoryRoot.appendingPathComponent("contract/examples/capture-model")
    let valid = try FileManager.default.contentsOfDirectory(atPath: examples.appendingPathComponent("valid").path)
    XCTAssertFalse(valid.isEmpty)
    for name in valid where name.hasSuffix(".json") {
      let problems = try validator.validate(jsonData: Data(contentsOf: examples.appendingPathComponent("valid/\(name)")))
      XCTAssertEqual(problems, [], name)
    }
    let invalid = try FileManager.default.contentsOfDirectory(atPath: examples.appendingPathComponent("invalid").path)
    XCTAssertFalse(invalid.isEmpty)
    for name in invalid where name.hasSuffix(".json") {
      let problems = try validator.validate(jsonData: Data(contentsOf: examples.appendingPathComponent("invalid/\(name)")))
      XCTAssertFalse(problems.isEmpty, "\(name) must fail the schema")
    }
  }

  /// The schema 1.1.0 rules on the 1.1.0 contract example: each change breaks exactly one rule.
  func testValidatorChecksTheCaptureModel1_1Rules() throws {
    let validator = try validator()
    let url = Fixtures.repositoryRoot.appendingPathComponent("contract/examples/capture-model/valid/floor-2.json")
    let text = try String(contentsOf: url, encoding: .utf8)
    XCTAssertEqual(try validator.validate(jsonData: Data(text.utf8)), [])
    func problems(replacing target: String, with replacement: String) throws -> [String] {
      XCTAssertTrue(text.contains(target), "floor-2.json has no \(target)")
      return try validator.validate(jsonData: Data(text.replacingOccurrences(of: target, with: replacement).utf8))
    }
    XCTAssertFalse(try problems(replacing: "\"1.1.0\"", with: "\"1.0.0\"").isEmpty, "1.1.0 fields in a 1.0.0 document")
    XCTAssertFalse(try problems(replacing: ",\n      \"typeSource\": \"inferred\"", with: "").isEmpty, "type without typeSource")
    XCTAssertFalse(try problems(replacing: "\"id\": \"f2-window-1\",", with: "\"id\": \"f2-window-1\", \"isOpen\": true,").isEmpty, "isOpen on a window")
    XCTAssertFalse(try problems(replacing: "\"StorageType\": \"cabinet\"", with: "\"StorageType\": 3").isEmpty, "attribute that is not a string")
  }

  func testValidatorCatchesDefectsInAMappedModel() throws {
    let validator = try validator()
    var model = try mapFixture("box-room").model
    model.coordinateSystem.up = .positiveY
    var json = try encodedJSON(model)

    func mutated(_ change: (inout [String: JSON]) -> Void) -> JSON {
      guard case .object(var members) = json else { return json }
      change(&members)
      return .object(members)
    }
    XCTAssertFalse(validator.validate(mutated { $0["rooms"] = .array([]); $0["extra"] = .bool(true) }).isEmpty, "unexpected property")
    XCTAssertFalse(validator.validate(mutated { $0.removeValue(forKey: "walls") }).isEmpty, "missing required")
    XCTAssertFalse(validator.validate(mutated { $0["areaKey"] = .string("Floor 1") }).isEmpty, "pattern")
    XCTAssertFalse(validator.validate(mutated { $0["coordinateSystem"] = .object(["units": .string("m"), "handedness": .string("right"), "up": .string("+Z")]) }).isEmpty, "const")
    json = try encodedJSON(model)
    XCTAssertEqual(validator.validate(json), [])
  }

  func testIdsAreUniqueAndReferencesResolve() throws {
    for (name, index) in allGeneratedCaptures {
      let model = try mapFixture(name, capture: index).model
      let ids = model.rooms.map(\.id) + model.walls.map(\.id) + (model.doors + model.windows + model.openings).map(\.id) + model.objects.map(\.id)
      XCTAssertEqual(Set(ids).count, ids.count, "\(name) ids are unique within the file")
      let roomIds = Set(model.rooms.map(\.id))
      let wallIds = Set(model.walls.map(\.id))
      for wall in model.walls { XCTAssertTrue(Set(wall.roomIds ?? []).isSubset(of: roomIds), "\(name) \(wall.id)") }
      for opening in model.doors + model.windows + model.openings { XCTAssertTrue(wallIds.contains(opening.wallId), "\(name) \(opening.id)") }
      for object in model.objects { XCTAssertTrue(object.roomId.map(roomIds.contains) ?? true, "\(name) \(object.id)") }
    }
  }
}
