import CaptureContract
import CaptureCore
import CaptureTestSupport
import Foundation
import XCTest

/// AC4: a capture record cannot be saved without project, confirmed address, floor label and mode.
final class CaptureRecordValidationTests: XCTestCase {
  private let project = HubProjectSummary(
    dealId: "fixture-deal-0001", projectName: "Fixture project",
    address: "100 Example Street, Testville, NY 00000")
  private let confirmTime = UTCTimestamp(secondsSince1970: 1_792_245_500)  // 2026-10-17T13:58:20Z
  private let visitTime = UTCTimestamp(secondsSince1970: 1_792_245_300)

  private func emptyDraft() -> CaptureRecordDraft {
    CaptureRecordDraft(
      operatorName: "Test Operator", operatorUserId: "00000000-0000-4000-8000-000000000001",
      device: DeviceInfo(
        model: "iPhone17,1", marketingName: "iPhone 16 Pro", osName: .iOS, osVersion: "26.0.1", hasLidar: true),
      app: CaptureRecord.AppInfo(version: "1.0.0", build: "1"))
  }

  private func completeDraft() -> CaptureRecordDraft {
    var draft = emptyDraft()
    draft.select(project)
    draft.setAddressConfirmed(true, at: confirmTime)
    draft.floorLabel = "Floor 1"
    draft.mode = .floor
    return draft
  }

  func testCompleteDraftCanBeSavedAndBuildsTheRecord() throws {
    let draft = completeDraft()
    XCTAssertEqual(draft.validate(), [])
    XCTAssertTrue(draft.canSave)
    let record = try draft.build(visitedAt: visitTime)
    XCTAssertEqual(record.hub.dealId, "fixture-deal-0001")
    XCTAssertEqual(record.address.formatted, project.address)
    XCTAssertTrue(record.address.confirmedOnSite)
    XCTAssertEqual(record.address.confirmedAt, confirmTime)
    XCTAssertEqual(record.captures.count, 1)
    XCTAssertEqual(record.captures[0].areaKey, "floor-1")
    XCTAssertEqual(record.captures[0].label, "Floor 1")
    XCTAssertEqual(record.captures[0].mode, .floor)
    XCTAssertEqual(record.device.osVersion, "26.0.1")
    XCTAssertEqual(record.app.version, "1.0.0")
  }

  func testEmptyDraftReportsAllFourRequiredFields() {
    let errors = emptyDraft().validate()
    XCTAssertTrue(errors.contains(.missingProject))
    XCTAssertTrue(errors.contains(.addressNotConfirmed))
    XCTAssertTrue(errors.contains(.missingFloorLabel))
    XCTAssertTrue(errors.contains(.missingMode))
    XCTAssertThrowsError(try emptyDraft().build(visitedAt: visitTime)) { error in
      let failure = error as? CaptureRecordValidationFailure
      XCTAssertEqual(
        Set(failure?.errors ?? []), [.missingProject, .addressNotConfirmed, .missingFloorLabel, .missingMode])
    }
  }

  func testCannotSaveWithoutProject() {
    var draft = emptyDraft()
    draft.floorLabel = "Floor 1"
    draft.mode = .room
    draft.setAddressConfirmed(true, at: confirmTime)  // no project, so this cannot confirm anything
    XCTAssertEqual(Set(draft.validate()), [.missingProject, .addressNotConfirmed])
    XCTAssertThrowsError(try draft.build(visitedAt: visitTime))
  }

  func testCannotSaveWithoutConfirmedAddress() {
    var draft = completeDraft()
    draft.setAddressConfirmed(false, at: confirmTime)
    XCTAssertEqual(draft.validate(), [.addressNotConfirmed])
    XCTAssertFalse(draft.canSave)
    XCTAssertThrowsError(try draft.build(visitedAt: visitTime)) {
      XCTAssertEqual(($0 as? CaptureRecordValidationFailure)?.errors, [.addressNotConfirmed])
    }
  }

  func testCannotSaveWithoutFloorLabel() {
    for label in ["", "   ", "\n"] {
      var draft = completeDraft()
      draft.floorLabel = label
      XCTAssertEqual(draft.validate(), [.missingFloorLabel], "label \"\(label)\"")
      XCTAssertThrowsError(try draft.build(visitedAt: visitTime))
    }
    var draft = completeDraft()
    draft.floorLabel = "★ ✕"
    XCTAssertEqual(draft.validate(), [.floorLabelHasNoKey], "a label with no letters or digits has no area key")
  }

  func testCannotSaveWithoutMode() {
    var draft = completeDraft()
    draft.mode = nil
    XCTAssertEqual(draft.validate(), [.missingMode])
    XCTAssertThrowsError(try draft.build(visitedAt: visitTime)) {
      XCTAssertEqual(($0 as? CaptureRecordValidationFailure)?.errors, [.missingMode])
    }
  }

  func testChoosingAnotherProjectClearsTheAddressConfirmation() {
    var draft = completeDraft()
    draft.select(project)  // same project: stays confirmed
    XCTAssertTrue(draft.isAddressConfirmed)
    draft.select(HubProjectSummary(dealId: "fixture-deal-0002", projectName: "Other", address: "1 Other Road, Testville, NY 00000"))
    XCTAssertFalse(draft.isAddressConfirmed)
    XCTAssertEqual(draft.validate(), [.addressNotConfirmed])
  }

  func testAreaKeyIsPathSafe() {
    XCTAssertEqual(CaptureRecordDraft.areaKey(for: "Floor 1"), "floor-1")
    XCTAssertEqual(CaptureRecordDraft.areaKey(for: "  Basement / Utility!! "), "basement-utility")
    XCTAssertEqual(CaptureRecordDraft.areaKey(for: "2nd floor"), "2nd-floor")
    XCTAssertEqual(CaptureRecordDraft.areaKey(for: "Étage 1"), "tage-1")
    XCTAssertNil(CaptureRecordDraft.areaKey(for: "---"))
    let long = CaptureRecordDraft.areaKey(for: String(repeating: "a ", count: 80))
    XCTAssertLessThanOrEqual(long?.count ?? 0, 64)
    XCTAssertFalse(long?.hasSuffix("-") ?? true)
  }

  func testLimitsFromTheSchemaAreEnforced() {
    var draft = completeDraft()
    draft.floorLabel = String(repeating: "a", count: 101)
    XCTAssertEqual(draft.validate(), [.floorLabelTooLong])
    draft = completeDraft()
    draft.coverageNotes = String(repeating: "n", count: 2001)
    XCTAssertEqual(draft.validate(), [.coverageNotesTooLong])
    draft = completeDraft()
    draft.omittedRooms = [CaptureRecord.RoomNote(name: "", reason: nil)]
    XCTAssertEqual(draft.validate(), [.roomNoteInvalid])
    draft.omittedRooms = [CaptureRecord.RoomNote(name: "Closet", reason: "")]
    XCTAssertEqual(draft.validate(), [.roomNoteInvalid])
    draft.omittedRooms = [CaptureRecord.RoomNote(name: "Closet", reason: "locked")]
    XCTAssertEqual(draft.validate(), [])
  }

  func testAutomaticDeviceAndAppFieldsAreChecked() {
    var draft = completeDraft()
    draft.device.osVersion = "26.0.1-beta"
    XCTAssertEqual(draft.validate(), [.deviceInvalid])
    draft = completeDraft()
    draft.app = CaptureRecord.AppInfo(version: "1.0", build: "1")
    XCTAssertEqual(draft.validate(), [.appInvalid])
    draft = completeDraft()
    draft.operatorName = " "
    XCTAssertEqual(draft.validate(), [.missingOperator])
  }

  func testBuiltRecordValidatesAgainstTheCaptureRecordSchema() throws {
    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-record.schema.json"))
    var draft = completeDraft()
    draft.coverageNotes = "Furniture covers the south wall of the living room."
    draft.omittedRooms = [CaptureRecord.RoomNote(name: "Primary closet", reason: "locked")]
    draft.inaccessibleRooms = [CaptureRecord.RoomNote(name: "Attic")]
    let record = try draft.build(visitedAt: visitTime)
    let json = try JSON.parse(CaptureContractJSON.makeEncoder().encode(record))
    XCTAssertEqual(validator.validate(json), [])

    // The decoded record is the same record.
    let decoded = try JSONDecoder().decode(CaptureRecord.self, from: CaptureContractJSON.makeEncoder().encode(record))
    XCTAssertEqual(decoded, record)
  }

  func testSchemaValidatorWouldRejectAnUnconfirmedAddressWithATimestamp() throws {
    // Guards the draft's design: confirmedAt exists exactly when confirmedOnSite is true.
    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-record.schema.json"))
    var record = try completeDraft().build(visitedAt: visitTime)
    record.address.confirmedOnSite = false
    let json = try JSON.parse(CaptureContractJSON.makeEncoder().encode(record))
    XCTAssertFalse(validator.validate(json).isEmpty)
  }

  func testSecondCaptureOfTheSameVisitNeedsItsOwnIdAndAreaKey() throws {
    let record = try completeDraft().build(visitedAt: visitTime)
    var second = completeDraft()
    second.floorLabel = "Floor 2"
    second.mode = .room
    let secondCapture = try second.build(visitId: record.visitId, visitedAt: visitTime).captures[0]
    let both = try record.appending(secondCapture)
    XCTAssertEqual(both.captures.map(\.areaKey), ["floor-1", "floor-2"])
    XCTAssertThrowsError(try both.appending(secondCapture))
  }

  func testProjectProviderIsInjected() async throws {
    let provider: HubProjectProvider = StaticHubProjectProvider([project])
    let projects = try await provider.projects()
    XCTAssertEqual(projects, [project])
  }
}
