import CaptureContract
import FieldRules
import Foundation
import XCTest

@testable import AppCore

final class VisitFlowTests: XCTestCase {
  private func record(_ name: String = "two-floor-house") throws -> CaptureRecord {
    let register = Fixtures.package(name).appendingPathComponent("Source Register")
    let visit = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: register.path).first)
    return try CaptureContractJSON.makeDecoder().decode(
      CaptureRecord.self,
      from: Data(contentsOf: register.appendingPathComponent("\(visit)/capture-record.json")))
  }

  /// The record CaptureFlowModel hands over for one floor: a new visit with that one capture.
  private func floorRecord(_ full: CaptureRecord, _ index: Int) -> CaptureRecord {
    var copy = full
    copy.visitId = index == 0 ? full.visitId : LowercaseUUID()
    copy.captures = [full.captures[index]]
    return copy
  }

  func testWalksEveryScreenInTheDesignOrder() throws {
    let full = try record()
    var flow = VisitFlow()
    XCTAssertEqual(flow.step, .captureRecord)
    try flow.scanStarted()
    XCTAssertEqual(flow.step, .scan)
    try flow.floorFinished(floorRecord(full, 0))
    XCTAssertEqual(flow.step, .photos(captureId: full.captures[0].captureId, initialRoom: nil))
    try flow.photosDone()
    XCTAssertEqual(flow.step, .controls)
    try flow.controlsDone()
    XCTAssertEqual(flow.step, .checklist)
    try flow.checklistFinished(canFinish: true)
    XCTAssertEqual(flow.step, .packageReady)
    try flow.sealed()
    XCTAssertEqual(flow.step, .uploading)
    XCTAssertTrue(flow.isSealed)
  }

  func testChecklistGateBlocksPackageReady() throws {
    var flow = VisitFlow()
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(try record(), 0))
    try flow.photosDone()
    try flow.controlsDone()
    XCTAssertThrowsError(try flow.checklistFinished(canFinish: false)) {
      XCTAssertEqual($0 as? VisitFlowError, .checklistIncomplete)
    }
    XCTAssertEqual(flow.step, .checklist)
  }

  func testCannotSkipAheadOrSealTwice() throws {
    var flow = VisitFlow()
    XCTAssertThrowsError(try flow.sealed())
    XCTAssertThrowsError(try flow.checklistFinished(canFinish: true))
    XCTAssertThrowsError(try flow.photosDone())
    XCTAssertEqual(flow.step, .captureRecord)

    try flow.scanStarted()
    try flow.floorFinished(floorRecord(try record(), 0))
    try flow.photosDone()
    try flow.controlsDone()
    try flow.checklistFinished(canFinish: true)
    try flow.sealed()
    XCTAssertThrowsError(try flow.sealed()) { XCTAssertEqual($0 as? VisitFlowError, .alreadySealed) }
    XCTAssertThrowsError(try flow.addMoreRooms()) {
      XCTAssertEqual($0 as? VisitFlowError, .alreadySealed)
    }
  }

  func testSecondFloorJoinsTheFirstFloorsVisit() throws {
    let full = try record()
    var flow = VisitFlow()
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(full, 0))
    try flow.photosDone()
    try flow.controlsDone()
    try flow.checklistFinished(canFinish: true)
    try flow.addMoreRooms()
    XCTAssertTrue(flow.isAddingFloor)
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(full, 1))
    XCTAssertEqual(flow.record?.visitId, full.visitId, "later floors keep the first visit id")
    XCTAssertEqual(flow.captures.map(\.areaKey), ["floor-1", "floor-2"])
    XCTAssertEqual(flow.step, .photos(captureId: full.captures[1].captureId, initialRoom: nil))
  }

  func testRefusesAnotherProjectOrTheSameFloorTwice() throws {
    let full = try record()
    var flow = VisitFlow()
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(full, 0))
    try flow.photosDone()
    try flow.controlsDone()
    try flow.checklistFinished(canFinish: true)
    try flow.addMoreRooms()
    try flow.scanStarted()

    var other = floorRecord(full, 1)
    other.hub.dealId = "another-deal"
    XCTAssertThrowsError(try flow.floorFinished(other)) {
      XCTAssertEqual($0 as? VisitFlowError, .differentProject)
    }
    XCTAssertThrowsError(try flow.floorFinished(floorRecord(full, 0))) {
      XCTAssertEqual($0 as? VisitFlowError, .duplicateCapture(areaKey: "floor-1"))
    }
    XCTAssertEqual(flow.step, .scan)
  }

  func testChecklistActionsLeadToPhotosAndControls() throws {
    let full = try record()
    var flow = VisitFlow()
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(full, 0))
    try flow.photosDone()
    try flow.controlsDone()
    try flow.takePhoto(captureId: full.captures[0].captureId, room: "Kitchen")
    XCTAssertEqual(flow.step, .photos(captureId: full.captures[0].captureId, initialRoom: "Kitchen"))
    try flow.photosDone()
    try flow.controlsDone()
    XCTAssertThrowsError(try flow.takePhoto(captureId: LowercaseUUID(), room: nil))
    try flow.addControls()
    XCTAssertEqual(flow.step, .controls)
  }

  func testScanCancelReturnsToTheCaptureRecord() throws {
    var flow = VisitFlow()
    try flow.scanStarted()
    try flow.scanCancelled()
    XCTAssertEqual(flow.step, .captureRecord)
  }

  // MARK: "No rooms skipped"

  /// The checklist's skipped-rooms row for the flow's record, as VisitModel evaluates it.
  private func skippedRoomsRow(_ flow: VisitFlow) throws -> ChecklistItem {
    let record = try XCTUnwrap(flow.record)
    let report = ChecklistRules.evaluate(
      ChecklistInput(
        record: record, controls: FieldControlsEditor(visitId: record.visitId).controls,
        noRoomsSkippedConfirmed: flow.noRoomsSkippedConfirmed))
    return report.item(.skippedRoomsRecorded)
  }

  func testNoRoomsSkippedCoversOnlyTheCapturesAtTheTap() throws {
    let full = try record()
    XCTAssertTrue(
      full.captures.allSatisfy { $0.omittedRooms.isEmpty && $0.inaccessibleRooms.isEmpty },
      "the fixture records no skipped room")
    var flow = VisitFlow()
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(full, 0))
    try flow.photosDone()
    try flow.controlsDone()

    // Unconfirmed: the row fails and asks for the tap.
    XCTAssertFalse(flow.noRoomsSkippedConfirmed)
    var row = try skippedRoomsRow(flow)
    XCTAssertFalse(row.passed)
    XCTAssertEqual(row.gaps, [.skippedRoomsNotRecorded])

    // After "No rooms skipped": passes.
    try flow.confirmNoRoomsSkipped()
    XCTAssertTrue(flow.noRoomsSkippedConfirmed)
    row = try skippedRoomsRow(flow)
    XCTAssertTrue(row.passed)
    XCTAssertEqual(row.gaps, [])

    // A new floor joins the visit: the tap no longer covers it, so the row fails again.
    try flow.checklistFinished(canFinish: true)
    try flow.addMoreRooms()
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(full, 1))
    try flow.photosDone()
    try flow.controlsDone()
    XCTAssertFalse(flow.noRoomsSkippedConfirmed)
    row = try skippedRoomsRow(flow)
    XCTAssertFalse(row.passed)
    XCTAssertEqual(row.gaps, [.skippedRoomsNotRecorded])

    try flow.confirmNoRoomsSkipped()
    XCTAssertTrue(try skippedRoomsRow(flow).passed)
  }

  func testNoRoomsSkippedOnlyFromTheChecklist() throws {
    var flow = VisitFlow()
    XCTAssertThrowsError(try flow.confirmNoRoomsSkipped()) {
      XCTAssertEqual(
        $0 as? VisitFlowError,
        .invalidTransition(from: .captureRecord, event: "confirm no rooms skipped"))
    }
    XCTAssertFalse(flow.noRoomsSkippedConfirmed)
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(try record(), 0))
    XCTAssertThrowsError(try flow.confirmNoRoomsSkipped())
    XCTAssertFalse(flow.noRoomsSkippedConfirmed)
  }

  func testNewVisitStartsUnconfirmed() {
    XCTAssertFalse(VisitFlow().noRoomsSkippedConfirmed)
    XCTAssertEqual(VisitFlow().noRoomsSkipped, NoRoomsSkippedConfirmation())
  }

  // MARK: Sign-out

  func testSignOutOnlyBeforeTheFirstCapture() throws {
    let full = try record()
    var flow = VisitFlow()
    XCTAssertTrue(flow.allowsSignOut)
    try flow.scanStarted()
    XCTAssertFalse(flow.allowsSignOut, "not during a scan")
    try flow.scanCancelled()
    XCTAssertTrue(flow.allowsSignOut, "a cancelled scan leaves no capture")
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(full, 0))
    XCTAssertFalse(flow.allowsSignOut)
    try flow.photosDone()
    try flow.controlsDone()
    try flow.checklistFinished(canFinish: true)
    try flow.addMoreRooms()
    XCTAssertTrue(flow.isAddingFloor)
    XCTAssertFalse(flow.allowsSignOut, "unsealed originals must not be abandoned")
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(full, 1))
    try flow.photosDone()
    try flow.controlsDone()
    try flow.checklistFinished(canFinish: true)
    try flow.sealed()
    XCTAssertFalse(flow.allowsSignOut)
  }
}
