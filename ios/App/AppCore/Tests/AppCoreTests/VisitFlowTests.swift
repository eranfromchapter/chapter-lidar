import CaptureContract
import FieldRules
import Foundation
import XCTest

@testable import AppCore

/// VisitFlow v2 (critique R-25, phone-capture §10.1 T-V1, phone-package §13.1 additions): the
/// overview is the hub, the checklist gate holds in revision mode too, nothing changes after
/// sealing, later floors join the same visit.
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

  /// A new visit with its first floor finished and its photos done: at the overview.
  private func visitAtOverview(_ full: CaptureRecord) throws -> VisitFlow {
    var flow = VisitFlow()
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(full, 0))
    try flow.photosDone()
    return flow
  }

  private func assertRefused(
    _ expected: VisitFlowError, file: StaticString = #filePath, line: UInt = #line,
    _ event: () throws -> Void
  ) {
    XCTAssertThrowsError(try event(), file: file, line: line) {
      XCTAssertEqual($0 as? VisitFlowError, expected, file: file, line: line)
    }
  }

  // MARK: The hub

  func testFirstFloorGoesFromPhotosToTheOverview() throws {
    let full = try record()
    var flow = VisitFlow()
    XCTAssertEqual(flow.step, .captureRecord)
    XCTAssertEqual(flow.revision, 1)
    XCTAssertFalse(flow.isSealed)
    XCTAssertFalse(flow.isRevisionMode)
    try flow.scanStarted()
    XCTAssertEqual(flow.step, .scan)
    try flow.floorFinished(floorRecord(full, 0))
    XCTAssertEqual(flow.step, .photos(captureId: full.captures[0].captureId, initialRoom: nil))
    try flow.photosDone()
    XCTAssertEqual(flow.step, .overview, "Done with photos returns to the overview (v1: controls)")
  }

  func testOverviewOpensEachFieldScreenAndComesBack() throws {
    let full = try record()
    var flow = try visitAtOverview(full)
    let floor1 = full.captures[0].captureId

    try flow.openPhotos(captureId: floor1, room: "Kitchen")
    XCTAssertEqual(flow.step, .photos(captureId: floor1, initialRoom: "Kitchen"))
    try flow.photosDone()
    XCTAssertEqual(flow.step, .overview)

    try flow.openControls()
    XCTAssertEqual(flow.step, .controls)
    try flow.controlsDone()
    XCTAssertEqual(flow.step, .overview, "v1 went on to the checklist")

    try flow.openChecklist(focus: .compass)
    XCTAssertEqual(flow.step, .checklist(focus: .compass))
    try flow.backToOverview()
    XCTAssertEqual(flow.step, .overview)

    try flow.openChecklist(focus: nil)
    XCTAssertEqual(flow.step, .checklist(focus: nil))
    XCTAssertThrowsError(try flow.openPhotos(captureId: LowercaseUUID(), room: nil))
  }

  func testFieldScreensOpenedFromTheChecklistReturnToIt() throws {
    let full = try record()
    var flow = try visitAtOverview(full)
    let floor1 = full.captures[0].captureId
    try flow.openChecklist(focus: .skippedRoomsRecorded)

    // "Take photo" on Before you leave: the photo step, then back to Before you leave.
    try flow.openPhotos(captureId: floor1, room: "Shower")
    XCTAssertEqual(flow.step, .photos(captureId: floor1, initialRoom: "Shower"))
    XCTAssertTrue(flow.returnsToChecklist)
    try flow.photosDone()
    XCTAssertEqual(flow.step, .checklist(focus: nil))
    XCTAssertFalse(flow.returnsToChecklist)

    // "Add" on Before you leave: Field controls, then back to Before you leave.
    try flow.openControls()
    try flow.controlsDone()
    XCTAssertEqual(flow.step, .checklist(focus: nil))

    // Opened from the overview, they go back to the overview.
    try flow.backToOverview()
    try flow.openControls()
    XCTAssertFalse(flow.returnsToChecklist)
    try flow.controlsDone()
    XCTAssertEqual(flow.step, .overview)
  }

  func testBackToOverviewFromEveryScreenItOpens() throws {
    let full = try record()
    var flow = try visitAtOverview(full)
    try flow.openPhotos(captureId: full.captures[0].captureId, room: nil)
    try flow.backToOverview()
    XCTAssertEqual(flow.step, .overview)
    try flow.reviewPackage(canFinish: true)
    XCTAssertEqual(flow.step, .packageReady)
    try flow.backToOverview()
    XCTAssertEqual(flow.step, .overview)
    XCTAssertThrowsError(try flow.backToOverview(), "already there")
  }

  // MARK: Checklist gate

  func testReviewPackageOnlyWhenTheChecklistPasses() throws {
    let full = try record()
    var flow = try visitAtOverview(full)
    assertRefused(.checklistIncomplete) { try flow.reviewPackage(canFinish: false) }
    XCTAssertEqual(flow.step, .overview)
    try flow.openChecklist(focus: nil)
    assertRefused(.checklistIncomplete) { try flow.reviewPackage(canFinish: false) }
    XCTAssertEqual(flow.step, .checklist(focus: nil))
    // "Finish capture" on Before you leave leads to Package ready.
    try flow.reviewPackage(canFinish: true)
    XCTAssertEqual(flow.step, .packageReady)
  }

  func testCannotSkipAheadOrSealTwice() throws {
    var flow = VisitFlow()
    XCTAssertThrowsError(try flow.sealed(packageId: LowercaseUUID()))
    XCTAssertThrowsError(try flow.reviewPackage(canFinish: true))
    XCTAssertThrowsError(try flow.photosDone())
    XCTAssertThrowsError(try flow.openChecklist(focus: nil))
    XCTAssertThrowsError(try flow.addFloor())
    XCTAssertEqual(flow.step, .captureRecord)

    let full = try record()
    flow = try visitAtOverview(full)
    try flow.reviewPackage(canFinish: true)
    let packageId = LowercaseUUID()
    try flow.sealed(packageId: packageId)
    XCTAssertEqual(flow.step, .packageStatus(packageId))
    XCTAssertTrue(flow.isSealed)
    XCTAssertTrue(flow.isReadOnly)
    assertRefused(.alreadySealed) { try flow.sealed(packageId: LowercaseUUID()) }
  }

  // MARK: After sealing

  func testNothingChangesAfterSealing() throws {
    let full = try record()
    var flow = try visitAtOverview(full)
    try flow.reviewPackage(canFinish: true)
    let packageId = LowercaseUUID()
    try flow.sealed(packageId: packageId)
    try flow.backToOverview()

    assertRefused(.alreadySealed) { try flow.addFloor() }
    assertRefused(.alreadySealed) {
      try flow.openPhotos(captureId: full.captures[0].captureId, room: nil)
    }
    assertRefused(.alreadySealed) { try flow.reviewPackage(canFinish: true) }
    // Read-only screens still open: Field controls and Before you leave (phone-field B4).
    try flow.openControls()
    try flow.controlsDone()
    try flow.openChecklist(focus: .photoPerRoom)
    assertRefused(.alreadySealed) { try flow.confirmNoRoomsSkipped() }
    try flow.backToOverview()

    // "Upload status" / "Open the verdict".
    try flow.showPackage(packageId)
    XCTAssertEqual(flow.step, .packageStatus(packageId))
  }

  func testShowPackageOnlyWhenSealed() throws {
    var flow = try visitAtOverview(try record())
    XCTAssertThrowsError(try flow.showPackage(LowercaseUUID()))
    XCTAssertEqual(flow.step, .overview)
  }

  // MARK: Floors

  func testSecondFloorJoinsTheFirstFloorsVisit() throws {
    let full = try record()
    var flow = try visitAtOverview(full)
    try flow.addFloor()
    XCTAssertEqual(flow.step, .captureRecord)
    XCTAssertTrue(flow.isAddingFloor)
    try flow.scanStarted()
    XCTAssertTrue(flow.isAddingFloor)
    try flow.floorFinished(floorRecord(full, 1))
    XCTAssertEqual(flow.record?.visitId, full.visitId, "later floors keep the first visit id")
    XCTAssertEqual(flow.captures.map(\.areaKey), ["floor-1", "floor-2"])
    XCTAssertEqual(flow.step, .photos(captureId: full.captures[1].captureId, initialRoom: nil))
    XCTAssertFalse(flow.isAddingFloor)
  }

  func testAddFloorFromPackageReadyAndBackOutOfStepTwo() throws {
    let full = try record()
    var flow = try visitAtOverview(full)
    try flow.reviewPackage(canFinish: true)
    // Package ready's "Scan another floor or room".
    try flow.addFloor()
    XCTAssertEqual(flow.step, .captureRecord)
    // Back from "What are you scanning?": the overview, nothing added.
    try flow.cancelAddFloor()
    XCTAssertEqual(flow.step, .overview)
    XCTAssertEqual(flow.captures.count, 1)
    // A new visit has no overview to go back to.
    var fresh = VisitFlow()
    XCTAssertThrowsError(try fresh.cancelAddFloor())
  }

  func testRefusesAnotherProjectOrTheSameFloorTwice() throws {
    let full = try record()
    var flow = try visitAtOverview(full)
    try flow.addFloor()
    try flow.scanStarted()

    var other = floorRecord(full, 1)
    other.hub.dealId = "another-deal"
    assertRefused(.differentProject) { try flow.floorFinished(other) }
    var moved = floorRecord(full, 1)
    moved.address.formatted = "1 Other Street"
    assertRefused(.differentProject) { try flow.floorFinished(moved) }
    assertRefused(.duplicateCapture(areaKey: "floor-1")) {
      try flow.floorFinished(floorRecord(full, 0))
    }
    XCTAssertEqual(flow.step, .scan)
  }

  func testScanCancelReturnsToTheCaptureRecord() throws {
    var flow = VisitFlow()
    try flow.scanStarted()
    try flow.scanCancelled()
    XCTAssertEqual(flow.step, .captureRecord)
    XCTAssertThrowsError(try flow.scanCancelled())
  }

  // MARK: Revision mode (phone-package §5.2, §6)

  func testRevisionModeStartsAtTheOverviewAndGoesToRevisionN() throws {
    let full = try record()
    let base = LowercaseUUID()
    var flow = VisitFlow(revisionOf: full, base: base, baseRevision: 1)
    XCTAssertEqual(flow.step, .overview)
    XCTAssertEqual(flow.revision, 2)
    XCTAssertEqual(flow.basePackageId, base)
    XCTAssertTrue(flow.isRevisionMode)
    XCTAssertFalse(flow.isSealed)
    XCTAssertFalse(flow.isReadOnly)
    XCTAssertEqual(flow.captures, full.captures, "the base revision's captures are the visit's")

    // The checklist gate holds in revision mode too (critique G-5).
    assertRefused(.checklistIncomplete) { try flow.reviewPackage(canFinish: false) }
    try flow.reviewPackage(canFinish: true)
    XCTAssertEqual(flow.step, .revisionReady)

    // "Keep editing", then a photo and a new floor (addFloor works from Revision n too).
    try flow.backToOverview()
    try flow.openPhotos(captureId: full.captures[0].captureId, room: nil)
    try flow.photosDone()
    try flow.reviewPackage(canFinish: true)
    try flow.addFloor()
    XCTAssertEqual(flow.step, .captureRecord)
    try flow.scanStarted()
    var closet = floorRecord(full, 1)
    closet.captures[0].areaKey = "primary-closet"
    closet.captures[0].captureId = LowercaseUUID()
    try flow.floorFinished(closet)
    try flow.photosDone()
    XCTAssertEqual(flow.captures.count, full.captures.count + 1)

    // Seal revision 2.
    try flow.reviewPackage(canFinish: true)
    let sealed = LowercaseUUID()
    try flow.sealed(packageId: sealed)
    XCTAssertEqual(flow.step, .packageStatus(sealed))
    XCTAssertEqual(flow.revision, 2)
    XCTAssertTrue(flow.isSealed)
    XCTAssertFalse(flow.isRevisionMode)
    assertRefused(.alreadySealed) { try flow.sealed(packageId: LowercaseUUID()) }
  }

  func testRevisionKeepsTheBaseRevisionsAllRoomsScannedTap() throws {
    let full = try record()
    var confirmation = NoRoomsSkippedConfirmation()
    confirmation.confirm(for: full)
    var flow = VisitFlow(
      revisionOf: full, base: LowercaseUUID(), baseRevision: 1, noRoomsSkipped: confirmation)
    XCTAssertTrue(flow.noRoomsSkippedConfirmed, "the same captures as at the tap")
    // A new floor in revision 2 asks again.
    try flow.addFloor()
    try flow.scanStarted()
    var closet = floorRecord(full, 1)
    closet.captures[0].areaKey = "attic"
    closet.captures[0].captureId = LowercaseUUID()
    try flow.floorFinished(closet)
    XCTAssertFalse(flow.noRoomsSkippedConfirmed)
  }

  // MARK: Upload stopped (phone-package §4.2)

  func testResealAfterFailureIsRevisionNPlusOne() throws {
    let full = try record()
    var flow = try visitAtOverview(full)
    try flow.reviewPackage(canFinish: true)
    let stopped = LowercaseUUID()
    try flow.sealed(packageId: stopped)
    let resealed = LowercaseUUID()
    try flow.resealAfterFailure(newPackageId: resealed)
    XCTAssertEqual(flow.step, .packageStatus(resealed))
    XCTAssertEqual(flow.revision, 2)
    XCTAssertEqual(flow.basePackageId, stopped)
    XCTAssertTrue(flow.isSealed)

    // Only from a sealed package's status.
    var open = try visitAtOverview(full)
    XCTAssertThrowsError(try open.resealAfterFailure(newPackageId: LowercaseUUID()))
  }

  // MARK: Resume (visit.json)

  func testResumingStartsAtTheOverview() throws {
    let full = try record()
    var confirmation = NoRoomsSkippedConfirmation()
    confirmation.confirm(for: full)
    let flow = VisitFlow(resuming: full, noRoomsSkipped: confirmation, isSealed: false)
    XCTAssertEqual(flow.step, .overview)
    XCTAssertTrue(flow.noRoomsSkippedConfirmed)
    XCTAssertFalse(flow.isReadOnly)

    let sealed = VisitFlow(resuming: full, isSealed: true, revision: 3)
    XCTAssertTrue(sealed.isReadOnly)
    XCTAssertEqual(sealed.revision, 3)

    let revision = VisitFlow(
      resuming: full, isSealed: true, revision: 2, basePackageId: LowercaseUUID(),
      isRevisionMode: true)
    XCTAssertFalse(revision.isSealed, "a revision draft is not sealed")
    XCTAssertFalse(revision.isReadOnly)
  }

  // MARK: "All rooms scanned"

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
    var flow = try visitAtOverview(full)
    try flow.openChecklist(focus: .skippedRoomsRecorded)

    XCTAssertFalse(flow.noRoomsSkippedConfirmed)
    var row = try skippedRoomsRow(flow)
    XCTAssertFalse(row.passed)
    XCTAssertEqual(row.gaps, [.skippedRoomsNotRecorded])

    try flow.confirmNoRoomsSkipped()
    XCTAssertTrue(flow.noRoomsSkippedConfirmed)
    XCTAssertEqual(flow.step, .checklist(focus: .skippedRoomsRecorded), "the screen stays")
    row = try skippedRoomsRow(flow)
    XCTAssertTrue(row.passed)

    // A new floor joins the visit: the tap no longer covers it.
    try flow.backToOverview()
    try flow.addFloor()
    try flow.scanStarted()
    try flow.floorFinished(floorRecord(full, 1))
    try flow.photosDone()
    XCTAssertFalse(flow.noRoomsSkippedConfirmed)
    row = try skippedRoomsRow(flow)
    XCTAssertEqual(row.gaps, [.skippedRoomsNotRecorded])

    try flow.openChecklist(focus: nil)
    try flow.confirmNoRoomsSkipped()
    XCTAssertTrue(try skippedRoomsRow(flow).passed)
  }

  func testNoRoomsSkippedOnlyFromTheChecklist() throws {
    var flow = VisitFlow()
    assertRefused(.invalidTransition(from: .captureRecord, event: "confirm no rooms skipped")) {
      try flow.confirmNoRoomsSkipped()
    }
    flow = try visitAtOverview(try record())
    XCTAssertThrowsError(try flow.confirmNoRoomsSkipped())
    XCTAssertFalse(flow.noRoomsSkippedConfirmed)
  }

  func testNewVisitStartsUnconfirmed() {
    XCTAssertFalse(VisitFlow().noRoomsSkippedConfirmed)
    XCTAssertEqual(VisitFlow().noRoomsSkipped, NoRoomsSkippedConfirmation())
  }

  // MARK: A tapped verdict notification (PackageOpening)

  func testANotificationNeverReplacesAVisitWithWorkToLose() {
    // A live scan of a new capture, an unsaved New capture, a photo not saved: the package of
    // yesterday's capture goes on top, the visit stays.
    XCTAssertEqual(
      PackageOpening.decide(
        hasOpenVisit: true, openVisitHoldsIt: false, openVisitShowsIt: false,
        openVisitHasWorkToLose: true),
      .onTop)
    XCTAssertEqual(
      PackageOpening.decide(
        hasOpenVisit: true, openVisitHoldsIt: true, openVisitShowsIt: true,
        openVisitHasWorkToLose: true),
      .onTop)
  }

  func testANotificationOpensItsPackageWhereNothingIsLost() {
    // Nothing open: the visit that holds it.
    XCTAssertEqual(
      PackageOpening.decide(
        hasOpenVisit: false, openVisitHoldsIt: false, openVisitShowsIt: false,
        openVisitHasWorkToLose: false),
      .openItsVisit)
    // Another visit open with everything on disk: replaced by the package's visit.
    XCTAssertEqual(
      PackageOpening.decide(
        hasOpenVisit: true, openVisitHoldsIt: false, openVisitShowsIt: false,
        openVisitHasWorkToLose: false),
      .openItsVisit)
    // The open sealed visit's own package: in its flow.
    XCTAssertEqual(
      PackageOpening.decide(
        hasOpenVisit: true, openVisitHoldsIt: true, openVisitShowsIt: true,
        openVisitHasWorkToLose: false),
      .inOpenVisit)
    // The base revision while revision n is edited: on top, the revision stays open.
    XCTAssertEqual(
      PackageOpening.decide(
        hasOpenVisit: true, openVisitHoldsIt: true, openVisitShowsIt: false,
        openVisitHasWorkToLose: false),
      .onTop)
  }
}
