import CaptureContract
import FieldRules
import Foundation
import XCTest

/// AC2: field controls entered in ft-in and m are stored in mm exactly and validate against
/// contract/schema/field-controls.schema.json.
final class ControlsUnitTests: XCTestCase {
  // MARK: Exact conversion

  func testFeetAndInchesAreStoredInMillimetresExactly() throws {
    let cases: [(String, Double)] = [
      ("24' 8\"", 7518.4),
      ("24'8\"", 7518.4),
      ("24 8", 7518.4),
      ("24-8", 7518.4),
      ("24 ft 8 in", 7518.4),
      ("24\u{2032} 8\u{2033}", 7518.4),
      ("36' 10 1/2\"", 11239.5),
      ("36 10 1/2", 11239.5),
      ("3 05", 1041.4),
      ("5'", 1524),
      ("96\"", 2438.4),
      ("10 1/2\"", 266.7),
      ("0' 0 1/16\"", 1.5875),
      ("0 0 15/16", 23.8125),
      ("8' 0 3/8\"", 2438.4 + 9.525),
    ]
    for (text, expected) in cases {
      let parsed = try LengthParser.parse(text, unit: .ftIn)
      XCTAssertEqual(parsed.valueMm, expected, accuracy: 0, "\(text) in ft-in")
      XCTAssertEqual(parsed.unit, .ftIn)
      XCTAssertEqual(parsed.enteredText, text)
    }
  }

  func testMetresAndOtherUnitsAreStoredInMillimetresExactly() throws {
    let cases: [(String, EnteredUnit, Double)] = [
      ("2.69", .m, 2690),
      ("3.05", .m, 3050),
      ("7.5184", .m, 7518.4),
      ("0.0254", .m, 25.4),
      ("11.2395 m", .m, 11239.5),
      ("2690", .mm, 2690),
      ("2 690 mm", .mm, 2690),
      ("914.4", .mm, 914.4),
      ("295", .cm, 2950),
      ("36", .inches, 914.4),
      ("80\"", .inches, 2032),
      ("10 1/2", .inches, 266.7),
    ]
    for (text, unit, expected) in cases {
      let parsed = try LengthParser.parse(text, unit: unit)
      XCTAssertEqual(parsed.valueMm, expected, accuracy: 0, "\(text) \(unit)")
    }
    XCTAssertEqual(try LengthParser.parse("5", unit: .ft).valueMm, 1524, accuracy: 0)
    XCTAssertEqual(try LengthParser.parse("1.5 ft", unit: .ft).valueMm, 457.2, accuracy: 0)
  }

  func testStoredValueIsAWholeNumberOfTenThousandthsOfAMillimetre() throws {
    // No floating-point drift: value * 10 000 is an integer for every accepted entry.
    for (text, unit) in [("24' 8\"", EnteredUnit.ftIn), ("36' 10 1/2\"", .ftIn), ("3.05", .m)] {
      let value = try LengthParser.parse(text, unit: unit).valueMm
      XCTAssertEqual((value * 10_000).rounded(), value * 10_000, accuracy: 1e-6)
    }
  }

  func testValuesMatchTheContractExample() throws {
    let url = Fixtures.repositoryRoot
      .appendingPathComponent("contract/examples/field-controls/valid/two-captures.json")
    let example = try CaptureContractJSON.makeDecoder().decode(
      FieldControls.self, from: Data(contentsOf: url))
    var measurements = example.distances.map(\.measurement)
    measurements += example.ceilingHeights.map(\.measurement)
    measurements += example.openings.flatMap { [$0.width, $0.height].compactMap { $0 } }
    measurements += example.floorToFloor.map(\.measurement)
    XCTAssertEqual(measurements.count, 6)
    for expected in measurements {
      let parsed = try LengthParser.parse(expected.enteredText, unit: expected.enteredUnit)
      XCTAssertEqual(parsed.valueMm, expected.valueMm, accuracy: 0, expected.enteredText)
    }
  }

  func testUnusableEntriesAreRefusedWithAReason() {
    func failure(_ text: String, _ unit: EnteredUnit) -> LengthParseError? {
      do {
        _ = try LengthParser.parse(text, unit: unit)
        return nil
      } catch { return error as? LengthParseError }
    }
    XCTAssertEqual(failure("", .m), .empty)
    XCTAssertEqual(failure("   ", .ftIn), .empty)
    XCTAssertEqual(failure("0", .mm), .notPositive)
    XCTAssertEqual(failure("-5", .mm), .notPositive)
    XCTAssertEqual(failure("0' 0\"", .ftIn), .notPositive)
    XCTAssertEqual(failure("300", .m), .tooLarge)
    XCTAssertEqual(failure("1.23456789", .m), .tooPrecise)
    XCTAssertEqual(failure("0 0 1/3", .ftIn), .unsupportedFraction)
    XCTAssertEqual(failure("0 0 3/2", .ftIn), .unsupportedFraction)
    XCTAssertEqual(failure("24' 14\"", .ftIn), .inchesOutOfRange)
    XCTAssertEqual(failure(String(repeating: "1", count: 41), .mm), .textTooLong)
    for text in ["abc", "2,5", "2.", "1e3", "2.5.1"] {
      XCTAssertNotNil(failure(text, .m), text)
    }
    // A bare number in ft-in is ambiguous (feet or inches), so it is refused.
    if case .invalidFormat? = failure("24", .ftIn) {
    } else {
      XCTFail("bare number must be refused")
    }
    XCTAssertFalse(LengthParseError.tooPrecise.message.isEmpty)
  }

  // The two-field entry draft is tested in MeasurementEntryDraftTests and the v2 number formats
  // in LengthFormatterV2Tests.

  // MARK: Controls model and schema

  /// Two floors, one of every control, entered in ft-in, m, mm and cm.
  private func twoFloorControls() throws -> FieldControls {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    try editor.setDistance(
      capture: Fixtures.floor1, axis: .a, from: "Kitchen east wall", to: "Living west wall",
      measurement: Fixtures.measurement("24' 8\"", .ftIn))
    try editor.setDistance(
      capture: Fixtures.floor1, axis: .b, from: "Entry", to: "Rear wall",
      measurement: Fixtures.measurement("11.2395", .m))
    try editor.setCeilingHeight(
      capture: Fixtures.floor1, room: "Kitchen", location: "Centre of room",
      measurement: Fixtures.measurement("2690", .mm))
    try editor.setOpening(
      capture: Fixtures.floor1, room: "Kitchen", label: "Entry door",
      width: Fixtures.measurement("36", .inches), height: Fixtures.measurement("80", .inches))
    try editor.setFloorToFloor(
      lower: Fixtures.floor1, upper: Fixtures.floor2, location: "At stair",
      measurement: Fixtures.measurement("9' 8 1/8\"", .ftIn))
    try editor.setLandmark(
      label: "Stair newel post", description: "Top of the newel post.",
      captures: [Fixtures.floor1, Fixtures.floor2],
      photoPaths: ["Site Photos/floor-1/\(Fixtures.floor1Id.rawValue)/photo-0014.jpg"])
    return editor.controls
  }

  func testWrittenFieldControlsValidateAgainstTheSchema() throws {
    let controls = try twoFloorControls()
    let data = try FieldControlsFile.encode(
      controls, knownCaptures: [Fixtures.floor1, Fixtures.floor2])
    let schema = try JSONSchemaValidator.loadSchema(named: "field-controls.schema.json")
    XCTAssertEqual(try schema.validate(data: data), [])

    // The values in the file are the exact millimetres.
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let distances = try XCTUnwrap(json["distances"] as? [[String: Any]])
    let a = try XCTUnwrap(distances.first?["measurement"] as? [String: Any])
    XCTAssertEqual(a["valueMm"] as? Double, 7518.4)
    XCTAssertEqual(a["enteredUnit"] as? String, "ft_in")
    XCTAssertEqual(a["enteredText"] as? String, "24' 8\"")
    let b = try XCTUnwrap(distances.last?["measurement"] as? [String: Any])
    XCTAssertEqual(b["valueMm"] as? Double, 11239.5)
    XCTAssertEqual(b["enteredUnit"] as? String, "m")
    let text = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertTrue(text.contains("\"valueMm\" : 7518.4"), "7518.4 is written without drift")
    XCTAssertTrue(text.contains("\"valueMm\" : 11239.5"))
  }

  func testEmptyControlsStillValidateAndEveryListIsPresent() throws {
    let controls = FieldControls(visitId: Fixtures.visitId)
    let data = try FieldControlsFile.encode(controls)
    XCTAssertEqual(
      try JSONSchemaValidator.loadSchema(named: "field-controls.schema.json").validate(data: data),
      [])
  }

  func testSchemaValidatorRejectsTheInvalidContractExamples() throws {
    let schema = try JSONSchemaValidator.loadSchema(named: "field-controls.schema.json")
    let directory = Fixtures.repositoryRoot.appendingPathComponent(
      "contract/examples/field-controls")
    for name in ["valid/two-captures.json"] {
      XCTAssertEqual(
        try schema.validate(data: Data(contentsOf: directory.appendingPathComponent(name))), [])
    }
    for name in ["invalid/landmark-in-one-capture.json", "invalid/measured-from-scan.json"] {
      XCTAssertFalse(
        try schema.validate(data: Data(contentsOf: directory.appendingPathComponent(name))).isEmpty,
        "\(name) must fail, otherwise the test validator is too weak")
    }
  }

  func testFileIsWrittenAtThePackagePath() throws {
    let controls = try twoFloorControls()
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("field-controls-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let url = try FieldControlsFile.write(controls, intoPackageRoot: root)
    XCTAssertEqual(
      FieldControlsFile.relativePath(visitId: Fixtures.visitId),
      "Field Measurements/7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5/field-controls.json")
    XCTAssertTrue(url.path.hasSuffix(FieldControlsFile.relativePath(visitId: Fixtures.visitId)))
    let decoded = try CaptureContractJSON.makeDecoder().decode(
      FieldControls.self, from: Data(contentsOf: url))
    XCTAssertEqual(decoded, controls)
  }

  func testMeasuringAgainReplacesTheEarlierValue() throws {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    for text in ["24' 8\"", "24' 9\""] {
      try editor.setDistance(
        capture: Fixtures.floor1, axis: .a, from: "A", to: "B",
        measurement: Fixtures.measurement(text, .ftIn))
    }
    XCTAssertEqual(editor.controls.distances.count, 1)
    XCTAssertEqual(editor.controls.distances[0].measurement.enteredText, "24' 9\"")
    XCTAssertTrue(editor.remove(id: "floor-1-distance-a"))
    XCTAssertTrue(editor.controls.distances.isEmpty)
    XCTAssertFalse(editor.remove(id: "floor-1-distance-a"))
  }

  func testLandmarkNeedsTwoDifferentCapturesAndFloorToFloorNeedsTwo() throws {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    XCTAssertThrowsError(
      try editor.setLandmark(label: "Newel", captures: [Fixtures.floor1, Fixtures.floor1])
    ) { XCTAssertEqual($0 as? FieldControlsEditError, .landmarkNeedsTwoCaptures) }
    XCTAssertThrowsError(
      try editor.setFloorToFloor(
        lower: Fixtures.floor1, upper: Fixtures.floor1, location: "At stair",
        measurement: Fixtures.measurement("2950", .mm))
    ) { XCTAssertEqual($0 as? FieldControlsEditError, .floorToFloorNeedsTwoCaptures) }
    XCTAssertThrowsError(
      try editor.setDistance(
        capture: Fixtures.floor1, axis: .a, from: "  ", to: "B",
        measurement: Fixtures.measurement("1", .m))
    ) { XCTAssertEqual($0 as? FieldControlsEditError, .emptyText(field: "From")) }
    XCTAssertEqual(editor.controls, FieldControls(visitId: Fixtures.visitId))
  }

  func testValidatorRefusesWhatTheSchemaRefuses() throws {
    var controls = try twoFloorControls()
    controls.distances[0].measurement.valueMm = 0
    controls.distances[1].id = controls.distances[0].id
    controls.landmarks[0].captures = [Fixtures.floor1]
    let issues = FieldControlsValidator.issues(for: controls)
    XCTAssertTrue(issues.contains { $0.contains("valueMm") })
    XCTAssertTrue(issues.contains { $0.contains("used more than once") })
    XCTAssertTrue(issues.contains { $0.contains("two or more different captures") })
    XCTAssertThrowsError(try FieldControlsFile.encode(controls))

    let unknown = FieldControls.CaptureRef(captureId: LowercaseUUID(), areaKey: "floor-9")
    var other = FieldControlsEditor(visitId: Fixtures.visitId)
    try other.setCeilingHeight(
      capture: unknown, room: "Kitchen", measurement: Fixtures.measurement("2690", .mm))
    XCTAssertFalse(
      FieldControlsValidator.issues(for: other.controls, knownCaptures: [Fixtures.floor1]).isEmpty)
  }

  func testIdsAreStableAndUniqueAcrossKinds() throws {
    let controls = try twoFloorControls()
    let ids =
      controls.distances.map(\.id) + controls.ceilingHeights.map(\.id)
      + controls.openings.map(\.id) + controls.floorToFloor.map(\.id)
      + controls.landmarks.map(\.id)
    XCTAssertEqual(Set(ids).count, ids.count)
    XCTAssertEqual(
      ids,
      [
        "floor-1-distance-a", "floor-1-distance-b", "floor-1-ceiling-kitchen-centre-of-room",
        "floor-1-opening-kitchen-entry-door", "floor-to-floor-floor-1-floor-2-at-stair",
        "landmark-stair-newel-post",
      ])
  }

  func testEveryEditReturnsTheIdItWroteTo() throws {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    XCTAssertEqual(
      try editor.setCeilingHeight(
        capture: Fixtures.floor1, room: "Kitchen", location: "By the window",
        measurement: Fixtures.measurement("2690", .mm)),
      "floor-1-ceiling-kitchen-by-the-window")
    XCTAssertEqual(
      try editor.setFloorToFloor(
        lower: Fixtures.floor1, upper: Fixtures.floor2, location: "At the stair",
        measurement: Fixtures.measurement("3061", .mm)),
      "floor-to-floor-floor-1-floor-2-at-the-stair")
    XCTAssertEqual(
      try editor.setLandmark(label: "Newel post", captures: [Fixtures.floor1, Fixtures.floor2]),
      "landmark-newel-post")
  }
}
