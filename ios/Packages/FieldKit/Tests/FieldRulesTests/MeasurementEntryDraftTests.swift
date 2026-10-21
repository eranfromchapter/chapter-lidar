import CaptureContract
import FieldRules
import Foundation
import XCTest

/// AC2 (phone-field §5.4): feet and inches typed as two fields are stored in mm exactly, with
/// `enteredText` and `enteredUnit` ft_in, and validate against field-controls.schema.json.
final class MeasurementEntryDraftTests: XCTestCase {
  private func feetInches(_ feet: String, _ inches: String) -> MeasurementEntryDraft {
    MeasurementEntryDraft(unit: .ftIn, feet: feet, inches: inches)
  }

  private func value(_ draft: MeasurementEntryDraft) throws -> Double {
    try draft.result.get().valueMm
  }

  // MARK: Composition and exact storage

  func testBothFieldsComposeFeetAndInches() throws {
    let draft = feetInches("10", "0.5")
    XCTAssertEqual(draft.enteredText, "10' 0.5\"")
    XCTAssertEqual(try value(draft), 3060.7, accuracy: 0)
    XCTAssertEqual(draft.storedText, "3,061 mm")
    XCTAssertNil(draft.errorMessage)

    XCTAssertEqual(try value(feetInches("24", "8")), 7518.4, accuracy: 0)
    XCTAssertEqual(try value(feetInches("36", "10.5")), 11239.5, accuracy: 0)
    XCTAssertEqual(try value(feetInches("0", "0.0625")), 1.5875, accuracy: 0)
    XCTAssertEqual(try value(feetInches("12", "4")), 3759.2, accuracy: 0)
    XCTAssertEqual(feetInches("12", "4").storedText, "3,759 mm")
  }

  func testFeetOnlyAndInchesOnly() throws {
    let feet = feetInches("10", "")
    XCTAssertEqual(feet.enteredText, "10'")
    XCTAssertEqual(try value(feet), 3048, accuracy: 0)
    let inches = feetInches(" ", "96")
    XCTAssertEqual(inches.enteredText, "96\"")
    XCTAssertEqual(try value(inches), 2438.4, accuracy: 0)
  }

  func testACommaIsADecimalPointAndSpacesAreTrimmed() throws {
    let draft = feetInches(" 10 ", "0,5")
    XCTAssertEqual(draft.enteredText, "10' 0.5\"")
    XCTAssertEqual(try value(draft), 3060.7, accuracy: 0)
    XCTAssertEqual(try value(MeasurementEntryDraft(unit: .m, value: "3,061")), 3061, accuracy: 0)
    XCTAssertEqual(try value(feetInches("0", ".5")), 12.7, accuracy: 0)
  }

  func testMillimetresAndMetresAreTheTypedNumber() throws {
    let mm = MeasurementEntryDraft(unit: .mm, value: "3061")
    XCTAssertEqual(mm.enteredText, "3061")
    XCTAssertEqual(try value(mm), 3061, accuracy: 0)
    let m = MeasurementEntryDraft(unit: .m, value: "3.061")
    XCTAssertEqual(m.enteredText, "3.061")
    XCTAssertEqual(try value(m), 3061, accuracy: 0)
    XCTAssertEqual(m.storedText, "3,061 mm")
  }

  // MARK: Refusals

  func testWholeFeetOnly() {
    XCTAssertEqual(
      feetInches("10.5", "").errorMessage, "Enter whole feet. Put the rest in inches.")
    XCTAssertEqual(feetInches("1e3", "2").errorMessage, "Enter whole feet. Put the rest in inches.")
  }

  func testInchesMustBeANumber() {
    XCTAssertEqual(
      feetInches("10", "1/2").errorMessage, "Enter inches as a number, for example 8 or 10.5.")
    XCTAssertEqual(
      feetInches("", "8 in").errorMessage, "Enter inches as a number, for example 8 or 10.5.")
  }

  func testTheParserMessagesAreKept() {
    XCTAssertEqual(
      feetInches("10", "12").errorMessage, "Inches must be less than 12 when feet are given.")
    XCTAssertEqual(
      feetInches("", "0.00001").errorMessage,
      "Too many decimal places. Enter what the tape or laser shows.")
    XCTAssertEqual(
      feetInches("0", "0").errorMessage, "The measurement must be greater than zero.")
    XCTAssertEqual(
      MeasurementEntryDraft(unit: .m, value: "201").errorMessage,
      "The measurement is larger than 200 m.")
  }

  func testEmptyAndHalfTypedValuesShowNoError() {
    XCTAssertTrue(feetInches("", "").isEmpty)
    XCTAssertNil(feetInches("", "").errorMessage)
    XCTAssertNil(feetInches("", "").storedText)
    // "10." on the way to "10.5": not saveable, not an error yet.
    let typing = feetInches("10", "0.")
    XCTAssertNil(typing.errorMessage)
    XCTAssertNil(typing.storedText)
    XCTAssertNil(MeasurementEntryDraft(unit: .mm, value: "3.").errorMessage)
  }

  func testChangingTheUnitClearsTheFieldsAndKeepsTheMethod() {
    let draft = MeasurementEntryDraft(unit: .ftIn, feet: "10", inches: "2", method: .laser)
    let cleared = draft.cleared(unit: .mm)
    XCTAssertEqual(cleared, MeasurementEntryDraft(unit: .mm, method: .laser))
    XCTAssertTrue(cleared.isEmpty)
  }

  // MARK: Editing a recorded measurement

  func testEditingRoundTrips() throws {
    let cases: [(String, EnteredUnit, MeasurementEntryDraft)] = [
      ("24' 8\"", .ftIn, feetInches("24", "8")),
      ("36' 10 1/2\"", .ftIn, feetInches("36", "10.5")),
      ("36-10 1/2", .ftIn, feetInches("36", "10.5")),
      ("10' 0.5\"", .ftIn, feetInches("10", "0.5")),
      ("96\"", .ftIn, feetInches("8", "0")),
      ("0' 0 1/16\"", .ftIn, feetInches("0", "0.0625")),
      ("3061", .mm, MeasurementEntryDraft(unit: .mm, value: "3061")),
      ("2 690 mm", .mm, MeasurementEntryDraft(unit: .mm, value: "2690")),
      ("3.061", .m, MeasurementEntryDraft(unit: .m, value: "3.061")),
      ("3.061 m", .m, MeasurementEntryDraft(unit: .m, value: "3.061")),
    ]
    for (text, unit, expected) in cases {
      let measurement = try FieldMeasurement.make(
        text: text, unit: unit, method: .laser, recordedAt: Fixtures.t0)
      var wanted = expected
      wanted.method = .laser
      let draft = MeasurementEntryDraft.editing(measurement)
      XCTAssertEqual(draft, wanted, text)
      // Saving again gives the same millimetres.
      XCTAssertEqual(
        try draft.measurement(recordedAt: Fixtures.t1).valueMm, measurement.valueMm, accuracy: 0,
        text)
    }
  }

  func testEditingAUnitTheAppDoesNotOfferStartsEmptyInTheDefaultUnit() throws {
    let centimetres = try FieldMeasurement.make(text: "295", unit: .cm, recordedAt: Fixtures.t0)
    XCTAssertEqual(
      MeasurementEntryDraft.editing(centimetres, defaultUnit: .mm),
      MeasurementEntryDraft(unit: .mm))
    let inches = try FieldMeasurement.make(text: "36", unit: .inches, recordedAt: Fixtures.t0)
    XCTAssertEqual(MeasurementEntryDraft.editing(inches), MeasurementEntryDraft(unit: .ftIn))
  }

  func testFeetAndInchesSplit() throws {
    XCTAssertEqual(try LengthParser.feetAndInches("36' 10 1/2\"").feet, 36)
    XCTAssertEqual(try LengthParser.feetAndInches("36' 10 1/2\"").inches, "10.5")
    XCTAssertEqual(try LengthParser.feetAndInches("1/16\"").inches, "0.0625")
    XCTAssertEqual(try LengthParser.feetAndInches("5'").inches, "0")
    XCTAssertThrowsError(try LengthParser.feetAndInches("24"))
  }

  // MARK: Contract

  func testSavedMeasurementsValidateAgainstTheSchema() throws {
    let drafts = [
      feetInches("10", "0.5"), feetInches("", "96"), feetInches("24", ""),
      MeasurementEntryDraft(unit: .mm, value: "3061", method: .laser),
      MeasurementEntryDraft(unit: .m, value: "3,061"),
    ]
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    for (index, draft) in drafts.enumerated() {
      let measurement = try draft.measurement(recordedAt: Fixtures.t0)
      try editor.setCeilingHeight(
        capture: Fixtures.floor1, room: "Room \(index)", measurement: measurement)
    }
    let data = try FieldControlsFile.encode(editor.controls)
    let schema = try JSONSchemaValidator.loadSchema(named: "field-controls.schema.json")
    XCTAssertEqual(try schema.validate(data: data), [])

    let first = editor.controls.ceilingHeights[0].measurement
    XCTAssertEqual(first.enteredUnit, .ftIn)
    XCTAssertEqual(first.enteredText, "10' 0.5\"")
    XCTAssertEqual(first.valueMm, 3060.7, accuracy: 0)
    XCTAssertEqual(first.method, .tape)
    XCTAssertEqual(editor.controls.ceilingHeights[4].measurement.enteredText, "3.061")
  }

  func testAnUnparsedDraftDoesNotMakeAMeasurement() {
    XCTAssertThrowsError(try feetInches("10", "12").measurement(recordedAt: Fixtures.t0)) {
      XCTAssertEqual($0 as? LengthParseError, .inchesOutOfRange)
    }
  }

  func testUnitsInTheSegmentedOrder() {
    XCTAssertEqual(UnitChoice.offered, [.mm, .m, .ftIn])
    XCTAssertEqual(UnitChoice.offered.map(UnitChoice.title), ["mm", "m", "ft-in"])
    XCTAssertEqual(UnitChoice.defaultUnit(for: .imperial), .ftIn)
    XCTAssertEqual(UnitChoice.defaultUnit(for: .metric), .mm)
  }

  func testRowAndSheetTitles() {
    XCTAssertEqual(
      ControlKind.allCases.map(\.rowTitle),
      [
        "Long distance A", "Long distance B \u{00B7} at a right angle to A", "Ceiling height",
        "Openings \u{00B7} optional", "Floor to floor", "Shared landmarks",
      ])
    XCTAssertEqual(
      ControlKind.allCases.map(\.entryTitle),
      [
        "Long distance A", "Long distance B", "Ceiling height", "Opening", "Floor to floor",
        "Shared landmark",
      ])
  }
}
