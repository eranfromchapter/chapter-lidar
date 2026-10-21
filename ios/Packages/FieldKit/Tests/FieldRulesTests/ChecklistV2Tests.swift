import CaptureContract
import FieldRules
import Foundation
import XCTest

/// AC1 (phone-field §6): Before you leave v2 blocks only on blocking items, lists them in the
/// order of the Field controls list with the v2 wording, and the compass item never blocks.
final class ChecklistV2Tests: XCTestCase {
  private let f1 = Fixtures.floor1
  private let f2 = Fixtures.floor2

  /// The artboard (2d-4): two floors; Primary closet locked; Bath 2 without a photo; Floor 1's
  /// controls complete, one landmark, nothing on Floor 2; Floor 1's compass verified.
  private func artboardInput() throws -> ChecklistInput {
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    try editor.setDistance(
      capture: f1, axis: .a, from: "Kitchen east wall", to: "Living west wall",
      measurement: Fixtures.measurement("7520", .mm))
    try editor.setDistance(
      capture: f1, axis: .b, from: "Entry", to: "Rear wall",
      measurement: Fixtures.measurement("11240", .mm))
    try editor.setCeilingHeight(
      capture: f1, room: "Kitchen", measurement: Fixtures.measurement("2690", .mm))
    try editor.setLandmark(label: "Stair newel post", captures: [f1, f2])

    var floor1 = Fixtures.capture(
      f1.captureId, areaKey: "floor-1", label: "Floor 1",
      inaccessible: [CaptureRecord.RoomNote(name: "Primary closet", reason: "locked")])
    floor1.setCompass(
      .reading(heading: 212.4, accuracy: 8, source: .trueNorth, recordedAt: Fixtures.t0))
    let floor2 = Fixtures.capture(f2.captureId, areaKey: "floor-2", label: "Floor 2", at: Fixtures.t1)
    return ChecklistInput(
      record: Fixtures.record(captures: [floor1, floor2]),
      capturedRooms: [f1.captureId: ["Kitchen"], f2.captureId: ["Bath 2"]],
      photos: [Fixtures.photo(capture: f1, room: "Kitchen")],
      controls: editor.controls)
  }

  // MARK: Titles, order, wording

  func testRowsInOrderWithTheV2Titles() throws {
    let report = ChecklistRules.evaluate(try artboardInput(), policy: .manualControls)
    XCTAssertEqual(
      report.items.map(\.title),
      [
        "Every floor and area labeled", "Rooms not scanned recorded", "A photo for every room",
        "Minimum field controls", "Compass reading", "Device, mode, date, operator",
      ])
    XCTAssertEqual(
      report.items.map(\.id),
      [.floorsLabeled, .skippedRoomsRecorded, .photoPerRoom, .minimumControls, .compass, .visitDetails])
  }

  func testTheArtboardState() throws {
    let report = ChecklistRules.evaluate(try artboardInput(), policy: .manualControls)
    XCTAssertEqual(report.item(.floorsLabeled).detail, "Floor 1, Floor 2")
    XCTAssertEqual(report.item(.skippedRoomsRecorded).detail, "Primary closet \u{00B7} locked")
    XCTAssertEqual(report.item(.photoPerRoom).detail, "Bath 2 has no photo")
    XCTAssertEqual(
      report.item(.minimumControls).detail,
      "Floor to floor \u{00B7} 1 of 2 landmarks \u{00B7} Floor 2 set")
    XCTAssertEqual(
      report.item(.compass).detail,
      "Floor 1 verified \u{00B7} Floor 2 not read: its plan will say \"not verified\"")
    XCTAssertFalse(report.item(.compass).passed)
    XCTAssertEqual(report.item(.compass).severity, .advisory)
    XCTAssertEqual(report.item(.visitDetails).detail, "Filled automatically")
    // Two blocking failures; the compass is not counted.
    XCTAssertEqual(report.blockingItems.map(\.id), [.photoPerRoom, .minimumControls])
    XCTAssertEqual(report.failedItems.map(\.id), [.photoPerRoom, .minimumControls, .compass])
    XCTAssertEqual(report.finishButtonTitle, "Fix 2 items to finish")
    XCTAssertFalse(report.canFinish)
    XCTAssertEqual(report.firstCaptureWithoutVerifiedCompass, f2.captureId)
  }

  func testTheControlsGapsAreInListOrder() throws {
    let report = ChecklistRules.evaluate(try artboardInput(), policy: .manualControls)
    XCTAssertEqual(
      report.item(.minimumControls).gaps,
      [
        .missingFloorToFloor(lower: "Floor 1", upper: "Floor 2"),
        .missingLandmarks(lower: "Floor 1", upper: "Floor 2", have: 1, need: 2),
        .missingDistance(capture: "Floor 2", axis: .a),
        .missingDistance(capture: "Floor 2", axis: .b),
        .missingCeilingHeight(capture: "Floor 2"),
      ])
  }

  func testCompactWordingWithOneFloor() throws {
    let record = Fixtures.record(captures: [
      Fixtures.capture(f1.captureId, areaKey: "floor-1", label: "Floor 1")
    ])
    var input = ChecklistInput(
      record: record, controls: FieldControls(visitId: Fixtures.visitId),
      noRoomsSkippedConfirmed: true)
    XCTAssertEqual(
      ChecklistRules.evaluate(input, policy: .manualControls).item(.minimumControls).detail,
      "Floor 1 set")

    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    try editor.setDistance(
      capture: f1, axis: .b, from: "A", to: "B", measurement: Fixtures.measurement("3", .m))
    input.controls = editor.controls
    XCTAssertEqual(
      ChecklistRules.evaluate(input, policy: .manualControls).item(.minimumControls).detail,
      "Long distance A \u{00B7} Ceiling height")
  }

  func testCompactWordingWithMoreFloors() throws {
    let f3 = FieldControls.CaptureRef(captureId: LowercaseUUID(), areaKey: "floor-3")
    var editor = FieldControlsEditor(visitId: Fixtures.visitId)
    for floor in [f1, f2, f3] {
      try editor.setDistance(
        capture: floor, axis: .b, from: "A", to: "B", measurement: Fixtures.measurement("3", .m))
      try editor.setCeilingHeight(
        capture: floor, room: "Hall", measurement: Fixtures.measurement("2.5", .m))
    }
    try editor.setDistance(
      capture: f1, axis: .a, from: "A", to: "B", measurement: Fixtures.measurement("3", .m))
    try editor.setDistance(
      capture: f3, axis: .a, from: "A", to: "B", measurement: Fixtures.measurement("3", .m))
    try editor.setFloorToFloor(
      lower: f1, upper: f2, location: "Stair", measurement: Fixtures.measurement("3", .m))
    for label in ["Newel", "Chimney"] { try editor.setLandmark(label: label, captures: [f1, f2]) }
    try editor.setLandmark(label: "Window", captures: [f2, f3])
    let record = Fixtures.record(captures: [
      Fixtures.capture(f1.captureId, areaKey: "floor-1", label: "Floor 1"),
      Fixtures.capture(f2.captureId, areaKey: "floor-2", label: "Floor 2", at: Fixtures.t1),
      Fixtures.capture(
        f3.captureId, areaKey: "floor-3", label: "Floor 3",
        at: UTCTimestamp(rawValue: "2026-10-17T16:00:00Z")!),
    ])
    let input = ChecklistInput(
      record: record, controls: editor.controls, noRoomsSkippedConfirmed: true)
    XCTAssertEqual(
      ChecklistRules.evaluate(input, policy: .manualControls).item(.minimumControls).detail,
      "Long distance A on Floor 2 \u{00B7} Floor to floor between Floor 2 and Floor 3 \u{00B7} "
        + "1 of 2 landmarks between Floor 2 and Floor 3")
  }

  func testAllRoomsScannedAndRoomsNotScannedWording() throws {
    var input = try artboardInput()
    input.record.captures[0].inaccessibleRooms = []
    var item = ChecklistRules.evaluate(input).item(.skippedRoomsRecorded)
    XCTAssertEqual(item.detail, "Record rooms not scanned, or confirm there are none")
    input.noRoomsSkippedConfirmed = true
    item = ChecklistRules.evaluate(input).item(.skippedRoomsRecorded)
    XCTAssertTrue(item.passed)
    XCTAssertEqual(item.detail, "All rooms scanned")
    input.record.captures[1].omittedRooms = [CaptureRecord.RoomNote(name: " ", reason: "owner")]
    XCTAssertEqual(
      ChecklistRules.evaluate(input).item(.skippedRoomsRecorded).detail,
      "A room not scanned has no name")
  }

  func testStandardPolicyIsUnchanged() throws {
    let report = ChecklistRules.evaluate(try artboardInput(), policy: .standard)
    let item = report.item(.minimumControls)
    XCTAssertTrue(item.passed)
    XCTAssertEqual(item.detail, "Measured by the LiDAR scan \u{00B7} 4 tape or laser checks")
    XCTAssertEqual(report.finishButtonTitle, "Fix 1 item to finish")
    XCTAssertEqual(ChecklistPolicy.shipping, .standard, "owner question Q-A default")
  }

  // MARK: Compass

  private func compassInput(_ statuses: [CaptureCompassStatus?]) throws -> ChecklistInput {
    var input = try artboardInput()
    input.record.captures[0].heading = nil  // only the overrides decide
    input.record.captures[0].headingAccuracy = nil
    input.record.captures[0].headingSource = nil
    input.record.captures[0].headingRecordedAt = nil
    var overrides: [LowercaseUUID: CaptureCompassStatus] = [:]
    for (capture, status) in zip(input.record.captures, statuses) {
      if let status { overrides[capture.captureId] = status }
    }
    input.compass = overrides
    return input
  }

  private func compassDetail(_ statuses: [CaptureCompassStatus?]) throws -> ChecklistItem {
    ChecklistRules.evaluate(try compassInput(statuses)).item(.compass)
  }

  func testCompassDetails() throws {
    let allVerified = try compassDetail([.verified, .verified])
    XCTAssertTrue(allVerified.passed)
    XCTAssertEqual(allVerified.detail, "Floor 1 verified \u{00B7} Floor 2 verified")

    XCTAssertEqual(
      try compassDetail([.verified, nil]).detail,
      "Floor 1 verified \u{00B7} Floor 2 not read: its plan will say \"not verified\"")
    XCTAssertEqual(
      try compassDetail([.notRead, .notVerified]).detail,
      "Floor 1 not read \u{00B7} Floor 2 not verified: their plans will say \"not verified\"")
    XCTAssertEqual(
      try compassDetail([.verified, .approximate]).detail,
      "Floor 1 verified \u{00B7} Floor 2 approximate: its plan will say \"approx. north\"")
    XCTAssertEqual(
      try compassDetail([.approximate, .approximate]).detail,
      "Floor 1 approximate \u{00B7} Floor 2 approximate: their plans will say \"approx. north\"")
    // Mixed: what is not verified wins over approximate.
    XCTAssertEqual(
      try compassDetail([.approximate, .notRead]).detail,
      "Floor 1 approximate \u{00B7} Floor 2 not read: its plan will say \"not verified\"")
    // Advisory: the item names the captures in its detail and carries no gaps.
    XCTAssertEqual(try compassDetail([.notRead, .notRead]).gaps, [])
  }

  func testWithoutAReadingEveryCaptureIsNotRead() throws {
    var input = try artboardInput()
    input.record.captures[0] = Fixtures.capture(
      f1.captureId, areaKey: "floor-1", label: "Floor 1",
      inaccessible: [CaptureRecord.RoomNote(name: "Primary closet", reason: "locked")])
    let record = Fixtures.record(captures: [input.record.captures[0]])
    input.record = record
    XCTAssertEqual(
      ChecklistRules.evaluate(input).item(.compass).detail,
      "Floor 1 not read: its plan will say \"not verified\"")
  }

  func testTheCompassNeverBlocks() throws {
    var input = try compassInput([.notRead, .notVerified])
    input.photos.append(Fixtures.photo(capture: f2, room: "Bath 2"))
    var editor = FieldControlsEditor(controls: input.controls)
    for floor in [f2] {
      try editor.setDistance(
        capture: floor, axis: .a, from: "A", to: "B", measurement: Fixtures.measurement("3", .m))
      try editor.setDistance(
        capture: floor, axis: .b, from: "A", to: "B", measurement: Fixtures.measurement("3", .m))
      try editor.setCeilingHeight(
        capture: floor, room: "Bath 2", measurement: Fixtures.measurement("2.5", .m))
    }
    try editor.setFloorToFloor(
      lower: f1, upper: f2, location: "Stair", measurement: Fixtures.measurement("3", .m))
    try editor.setLandmark(label: "Chimney", captures: [f1, f2])
    input.controls = editor.controls
    let report = ChecklistRules.evaluate(input, policy: .manualControls)
    XCTAssertFalse(report.item(.compass).passed)
    XCTAssertTrue(report.canFinish)
    XCTAssertEqual(report.finishButtonTitle, "Finish capture")
    XCTAssertNoThrow(try report.requireCanFinish())
    XCTAssertEqual(report.gaps, [])
  }

  func testTheStoredReadingIsEvaluatedByTheContract() throws {
    var input = try artboardInput()
    input.record.captures[1].setCompass(
      .reading(heading: 90, accuracy: 18, source: .trueNorth, recordedAt: Fixtures.t1))
    XCTAssertEqual(
      ChecklistRules.evaluate(input).item(.compass).detail,
      "Floor 1 verified \u{00B7} Floor 2 approximate: its plan will say \"approx. north\"")
    input.record.captures[1].setCompass(.none(issue: .notCalibrated))
    XCTAssertEqual(
      ChecklistRules.evaluate(input).compass.map(\.status), [.verified, .notRead])
  }

  func testCompassStatusMapping() {
    func status(_ state: CompassState) -> CaptureCompassStatus { CaptureCompassStatus(state) }
    XCTAssertEqual(status(.verified(heading: 1, accuracy: 8)), .verified)
    XCTAssertEqual(status(.approximate(heading: 1, accuracy: 20, source: .magnetic)), .approximate)
    XCTAssertEqual(status(.notVerified(.inaccurate, accuracy: 40)), .notVerified)
    XCTAssertEqual(status(.notVerified(.rejected, accuracy: nil)), .notVerified)
    XCTAssertEqual(status(.notVerified(.noReading, accuracy: nil)), .notRead)
    XCTAssertEqual(status(.notVerified(.notCalibrated, accuracy: nil)), .notRead)
    XCTAssertEqual(status(.notVerified(.unavailable, accuracy: nil)), .notRead)
    XCTAssertEqual(
      CaptureCompassStatus.allCases.map(\.word),
      ["verified", "approximate", "not verified", "not read"])
  }

  func testOverviewWordsAndShortSummary() {
    func entries(_ statuses: [CaptureCompassStatus]) -> [CompassSummary.Entry] {
      statuses.enumerated().map {
        CompassSummary.Entry(captureId: LowercaseUUID(), label: "Floor \($0.offset + 1)", status: $0.element)
      }
    }
    XCTAssertEqual(CompassSummary.overview(entries([.verified, .verified])).word, "Verified")
    XCTAssertEqual(CompassSummary.overview(entries([.verified, .approximate])).word, "Approx.")
    XCTAssertEqual(CompassSummary.overview(entries([.verified, .notRead])).word, "Partly")
    XCTAssertEqual(CompassSummary.overview(entries([.notVerified, .notRead])).word, "Not verified")
    XCTAssertEqual(
      CompassSummary.short(entries([.verified, .notRead])),
      "Floor 1 verified \u{00B7} Floor 2 not read")
  }

  func testThePropertyCaption() throws {
    var record = try artboardInput().record
    record.address.formatted = "618 Valley Street, Philadelphia, PA 19123"
    XCTAssertEqual(ChecklistRules.propertyCaption(record), "618 Valley Street")
    record.hub.projectName = " Valley Street rowhouse "
    XCTAssertEqual(ChecklistRules.propertyCaption(record), "Valley Street rowhouse")
    record.hub.projectName = "  "
    record.address.formatted = "Unit 4"
    XCTAssertEqual(ChecklistRules.propertyCaption(record), "Unit 4")
  }

  // MARK: NoRoomsSkippedConfirmation in visit.json

  func testTheConfirmationIsCodableAndByteStable() throws {
    let record = try artboardInput().record
    var confirmation = NoRoomsSkippedConfirmation()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    XCTAssertEqual(String(decoding: try encoder.encode(confirmation), as: UTF8.self), "{}")
    XCTAssertEqual(
      try JSONDecoder().decode(NoRoomsSkippedConfirmation.self, from: Data("{}".utf8)),
      confirmation)

    confirmation.confirm(for: record)
    let data = try encoder.encode(confirmation)
    let ids = [f1.captureId.rawValue, f2.captureId.rawValue].sorted()
    XCTAssertEqual(
      String(decoding: data, as: UTF8.self),
      "{\"confirmedCaptureIds\":[\"\(ids[0])\",\"\(ids[1])\"]}")
    let decoded = try JSONDecoder().decode(NoRoomsSkippedConfirmation.self, from: data)
    XCTAssertEqual(decoded, confirmation)
    XCTAssertEqual(try encoder.encode(decoded), data)
  }
}
