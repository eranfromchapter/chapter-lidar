import CaptureContract
import CaptureCore
import Foundation
import XCTest

/// T-H1 (`CapturesHomeStateTests`): the rows of critique R-28 with exact subtitles, sorting and
/// the empty state.
final class CapturesHomeStateTests: XCTestCase {
  private let newYork = TimeZone(identifier: "America/New_York")!
  private let base = Date(timeIntervalSince1970: 1_792_608_003)

  private func inProgress(_ progress: CapturesHomeState.Row.Progress, count: String = "2 floors")
    -> CapturesHomeState.Row
  {
    .inProgress(id: "v", title: "618 Valley Street", count: count, progress, activity: base)
  }

  func testInProgressRows() {
    XCTAssertEqual(inProgress(.notSealed).subtitle, "2 floors · not sealed yet")
    XCTAssertNil(inProgress(.notSealed).status)
    XCTAssertNil(inProgress(.notSealed).progress)

    let uploading = inProgress(.uploading(bytes: "512 of 768 MB", fraction: 0.67))
    XCTAssertEqual(uploading.subtitle, "2 floors · uploading · 512 of 768 MB")
    XCTAssertEqual(uploading.progress, 0.67)

    let paused = inProgress(.paused(bytes: "512 of 768 MB", fraction: 0.67), count: "1 floor and 1 room")
    XCTAssertEqual(paused.subtitle, "1 floor and 1 room · upload paused · 512 of 768 MB")
    XCTAssertEqual(paused.progress, 0.67)

    XCTAssertEqual(inProgress(.signInRequired).subtitle, "2 floors · sign in to upload")

    let stopped = inProgress(.uploadStopped)
    XCTAssertEqual(stopped.subtitle, "2 floors · upload stopped")
    XCTAssertEqual(stopped.status, RowStatusValue(.missing, "Stopped"))

    let checking = inProgress(.checking)
    XCTAssertEqual(checking.subtitle, "2 floors · uploaded · checks running")
    XCTAssertEqual(checking.status, RowStatusValue(.waiting, "Checking"))

    XCTAssertEqual(
      inProgress(.revisionStarted(next: 2)).subtitle, "2 floors · revision 2 not sealed yet")
    XCTAssertEqual(inProgress(.notSealed).destination, .overview)
  }

  func testSealedRows() {
    let sealedAt = Date(timeIntervalSince1970: 1_737_820_800)
    func sealed(_ verdict: CapturesHomeState.Row.Verdict) -> CapturesHomeState.Row {
      .sealed(
        id: "s", title: "424 West End Ave, Apt 4K", revision: 1, sealedAt: sealedAt,
        verdict: verdict, timeZone: newYork)
    }
    XCTAssertEqual(sealed(.limited).subtitle, "Revision 1 · sealed Jan 25, 2025")
    XCTAssertEqual(sealed(.limited).status, RowStatusValue(.partly, "Limited"))
    XCTAssertEqual(sealed(.ready).status, RowStatusValue(.done, "Ready"))
    XCTAssertEqual(sealed(.blocked).subtitle, "Revision 1 · re-seal needed")
    XCTAssertEqual(sealed(.blocked).status, RowStatusValue(.missing, "Blocked"))
    XCTAssertEqual(sealed(.ready).destination, .verdict)
  }

  func testSectionsAreNewestFirst() {
    let rows: [CapturesHomeState.Row] = [
      .inProgress(id: "a", title: "A", count: "1 floor", .notSealed, activity: base),
      .sealed(id: "b", title: "B", revision: 1, sealedAt: base.addingTimeInterval(-10), verdict: .ready),
      .inProgress(id: "c", title: "C", count: "1 floor", .checking, activity: base.addingTimeInterval(60)),
      .sealed(id: "d", title: "D", revision: 2, sealedAt: base, verdict: .limited),
    ]
    let state = CapturesHomeState(rows: rows, operatorName: "Dana Ruiz")
    XCTAssertEqual(state.inProgress.map(\.id), ["c", "a"])
    XCTAssertEqual(state.sealed.map(\.id), ["d", "b"])
    XCTAssertFalse(state.isEmpty)
  }

  func testEmptyStateAndAccount() {
    let state = CapturesHomeState(rows: [], operatorName: "Dana Ruiz", hasPendingUploads: true)
    XCTAssertTrue(state.isEmpty)
    XCTAssertEqual(CapturesHomeState.emptyText, "No captures on this phone yet.")
    XCTAssertEqual(CapturesHomeState.emptyFootnote, "Tap New capture to scan a floor or room.")
    XCTAssertEqual(
      CapturesHomeState.footnote,
      "Files stay on this phone until the station confirms each one. Verdict details are in the HUB.")
    XCTAssertEqual(state.accountTitle, "Signed in as Dana Ruiz")
    XCTAssertEqual(state.accountMessage, "Uploads resume after you sign in again.")
    XCTAssertNil(CapturesHomeState(rows: [], operatorName: "Dana Ruiz").accountMessage)
  }
}

/// The words of the Capture overview's own rows (phone-capture §3.5, addendum A4, A6).
final class CaptureOverviewStateTests: XCTestCase {
  func testFloorRows() {
    let floor1 = CaptureOverviewState.FloorRow.scanned(
      areaKey: "floor-1", label: "Floor 1", mode: .floor, rooms: 12, photos: 42,
      controls: "complete", isDone: true)
    XCTAssertEqual(floor1.subtitle, "Whole floor · 12 rooms · 42 photos · controls complete")
    XCTAssertEqual(floor1.status, RowStatusValue(.done, "Done"))

    let floor2 = CaptureOverviewState.FloorRow.scanned(
      areaKey: "floor-2", label: "Floor 2", mode: .floor, rooms: 9, photos: 0,
      controls: "missing", isDone: false)
    XCTAssertEqual(floor2.subtitle, "Whole floor · 9 rooms · no photos yet · controls missing")
    XCTAssertEqual(floor2.status, RowStatusValue(.missing, "Open"))

    let room = CaptureOverviewState.FloorRow.scanned(
      areaKey: "bath", label: "Bath", mode: .room, rooms: 1, photos: 1,
      controls: "from the scan", isDone: true)
    XCTAssertEqual(room.subtitle, "One room · 1 room · 1 photo · controls from the scan")

    let outside = CaptureOverviewState.FloorRow.scanned(
      areaKey: "yard", label: "Yard", mode: .exterior, rooms: 0, photos: 3,
      controls: "optional", isDone: true)
    XCTAssertEqual(outside.subtitle, "Exterior · 3 photos · controls optional", "R = 0: no rooms part")

    XCTAssertEqual(
      CaptureOverviewState.FloorRow.loading(areaKey: "floor-1", label: "Floor 1").subtitle,
      "Loading…")
    XCTAssertNil(CaptureOverviewState.FloorRow.loading(areaKey: "floor-1", label: "Floor 1").status)
    let unreadable = CaptureOverviewState.FloorRow.unreadable(
      areaKey: "floor-1", label: "Floor 1", mode: .floor)
    XCTAssertEqual(unreadable.subtitle, "Whole floor · the scan could not be read")
    XCTAssertEqual(unreadable.status, RowStatusValue(.missing, "Open"))
  }

  func testButton() {
    XCTAssertEqual(CaptureOverviewState.ReviewButton.fix(items: 2).title, "Fix 2 items to review the package")
    XCTAssertEqual(CaptureOverviewState.ReviewButton.fix(items: 1).title, "Fix 1 item to review the package")
    XCTAssertFalse(CaptureOverviewState.ReviewButton.fix(items: 2).isEnabled)
    XCTAssertEqual(CaptureOverviewState.ReviewButton.reviewPackage.title, "Review the package")
    XCTAssertEqual(CaptureOverviewState.ReviewButton.reviewRevision(2).title, "Review revision 2")
    XCTAssertEqual(CaptureOverviewState.ReviewButton.uploadStatus.title, "Upload status")
    XCTAssertEqual(CaptureOverviewState.ReviewButton.openVerdict.title, "Open the verdict")
    XCTAssertTrue(CaptureOverviewState.ReviewButton.openVerdict.isEnabled)
  }

  func testSubtitleAndChecks() {
    let newYork = TimeZone(identifier: "America/New_York")!
    let now = Date(timeIntervalSince1970: 1_792_608_003)
    XCTAssertEqual(
      CaptureOverviewState.subtitle(
        visitedAt: now.addingTimeInterval(-3600), now: now, operatorName: "Dana Ruiz",
        sealState: .notSealed, timeZone: newYork),
      "Captured today by Dana Ruiz · not sealed yet")
    XCTAssertEqual(
      CaptureOverviewState.subtitle(
        visitedAt: now.addingTimeInterval(-86_400), now: now, operatorName: "Dana Ruiz",
        sealState: .sealed(revision: 1), timeZone: newYork),
      "Captured yesterday by Dana Ruiz · revision 1 sealed")
    XCTAssertEqual(
      CaptureOverviewState.SealState.revisionDraft(revision: 2).text, "revision 2 not sealed yet")
    XCTAssertEqual(
      CaptureOverviewState.CheckID.allCases.map(\.title),
      ["Photos", "Field controls", "Compass", "Rooms not scanned"])
    XCTAssertEqual(
      CaptureOverviewState.CheckID.allCases.map(\.accessibilityIdentifier),
      ["overview.photos", "overview.controls", "overview.compass", "overview.skippedRooms"])
    let state = CaptureOverviewState(
      title: "618 Valley Street", dealId: "4821", subtitle: "s", floors: [], canAddFloor: true,
      checks: [], button: .reviewPackage)
    XCTAssertEqual(state.dealCaption, "Deal 4821")
    XCTAssertEqual(CaptureOverviewState.footer, "Photos and controls cannot be recovered later.")
  }
}
