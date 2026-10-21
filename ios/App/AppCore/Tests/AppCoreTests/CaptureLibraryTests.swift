import CaptureContract
import CaptureCore
import Foundation
import PackageCore
import XCTest

@testable import AppCore

/// The Captures home from disk (phone-capture §10.1 T-L1, critique R-28): every row case of the
/// table, the sections, titles, subtitles and statuses, from `visit.json`, the packages, their
/// upload states, their station status caches and the live upload snapshots.
final class CaptureLibraryTests: XCTestCase {
  private var base: URL!
  private let utc = TimeZone(identifier: "UTC")!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDown() {
    Fixtures.removeTemporaryDirectory(base)
  }

  /// A visit with `visit.json` and no package.
  @discardableResult
  private func visit(
    _ record: CaptureRecord, updatedAt: String = "2026-10-21T14:00:00Z",
    revision: VisitFile.Revision? = nil
  ) throws -> VisitWorkspace {
    let workspace = VisitWorkspace.allocate(in: base)
    try VisitStore.save(
      VisitFile(
        createdAt: Make.time("2026-10-21T13:00:00Z"), updatedAt: Make.time(updatedAt),
        record: record, isSealed: false, revision: revision),
      to: workspace)
    return workspace
  }

  private func confirmed(_ sealed: SealedPackage) -> UploadState {
    var state = UploadState(package: sealed, dealId: "D")
    for index in state.files.indices { state.files[index].phase = .verified }
    state.sealResult = PackageSealResult(
      packageId: sealed.packageId, visitId: sealed.visitId, dealId: "D", revision: 1,
      status: .checksQueued, createdAt: Make.t1402, files: [])
    return state
  }

  private func snapshot(
    _ sealed: SealedPackage, state: UploadState? = nil, activity: UploadActivity,
    verdict: VerdictStatus? = nil
  ) -> UploadSnapshot {
    UploadSnapshot(
      packageId: sealed.packageId, package: SealedPackageSummary.make(sealed),
      state: state ?? UploadState(package: sealed, dealId: "D"), activity: activity,
      verdict: verdict, manifest: sealed.manifest)
  }

  private func row(
    _ workspace: VisitWorkspace, live: [LowercaseUUID: UploadSnapshot] = [:]
  ) throws -> CapturesHomeState.Row {
    let visit = try XCTUnwrap(CaptureLibrary.visit(workspace))
    return try XCTUnwrap(CaptureLibrary.row(for: visit, live: live, timeZone: utc))
  }

  // MARK: In progress

  func testNotSealed() throws {
    let workspace = try visit(
      Make.record([Make.capture("Floor 1"), Make.capture("Floor 2")], projectName: ""))
    let row = try row(workspace)
    XCTAssertEqual(row.id, workspace.id)
    XCTAssertEqual(row.title, "618 Valley Street", "no project name: the address (R-29)")
    XCTAssertEqual(row.subtitle, "2 floors · not sealed yet")
    XCTAssertNil(row.status)
    XCTAssertNil(row.progress)
    XCTAssertEqual(row.destination, .overview)
  }

  func testCountTextAndProjectName() throws {
    let workspace = try visit(
      Make.record(
        [Make.capture("Floor 1"), Make.capture("Primary closet", mode: .room)],
        projectName: "Valley Street renovation"))
    let row = try row(workspace)
    XCTAssertEqual(row.title, "Valley Street renovation")
    XCTAssertEqual(row.subtitle, "1 floor and 1 room · not sealed yet")
  }

  func testUploadingFromTheStateOnDisk() throws {
    let fixture = try SealedFixture(in: base)
    let row = try row(fixture.visit.workspace)
    let summary = UploadProgressSummary.make(
      state: UploadState(package: fixture.sealed, dealId: "D"), manifest: fixture.sealed.manifest)
    XCTAssertEqual(row.title, "Fixture box-room")
    XCTAssertEqual(row.subtitle, "1 room · uploading · \(summary.bytesText)")
    XCTAssertEqual(row.progress, 0)
    XCTAssertNil(row.status)
    XCTAssertEqual(row.destination, .overview)
  }

  func testUploadingAndPausedFromTheLiveSnapshot() throws {
    let fixture = try SealedFixture(in: base)
    var state = UploadState(package: fixture.sealed, dealId: "D")
    state.files[0].phase = .verified
    let uploading = snapshot(fixture.sealed, state: state, activity: .uploading)
    var row = try row(fixture.visit.workspace, live: [fixture.sealed.packageId: uploading])
    XCTAssertEqual(row.subtitle, "1 room · uploading · \(uploading.progress.bytesText)")
    XCTAssertEqual(row.progress, uploading.progress.fraction)
    XCTAssertGreaterThan(row.progress ?? 0, 0)

    let paused = snapshot(fixture.sealed, state: state, activity: .waitingToRetry(.offline))
    row = try self.row(fixture.visit.workspace, live: [fixture.sealed.packageId: paused])
    XCTAssertEqual(row.subtitle, "1 room · upload paused · \(paused.progress.bytesText)")
    XCTAssertNotNil(row.progress)

    let station = snapshot(fixture.sealed, activity: .waitingToRetry(.stationUnavailable))
    row = try self.row(fixture.visit.workspace, live: [fixture.sealed.packageId: station])
    XCTAssertTrue(row.subtitle.contains("upload paused"))
  }

  func testSignInRequiredAndUploadStopped() throws {
    let fixture = try SealedFixture(in: base)
    var row = try row(
      fixture.visit.workspace,
      live: [fixture.sealed.packageId: snapshot(fixture.sealed, activity: .signInRequired)])
    XCTAssertEqual(row.subtitle, "1 room · sign in to upload")
    XCTAssertNil(row.progress)

    row = try self.row(
      fixture.visit.workspace,
      live: [
        fixture.sealed.packageId: snapshot(
          fixture.sealed, activity: .failed("The station refused the upload (409 package_conflict)."))
      ])
    XCTAssertEqual(row.subtitle, "1 room · upload stopped")
    XCTAssertEqual(row.status, RowStatusValue(.missing, "Stopped"), "not \"Failed\" (R-28)")
    XCTAssertEqual(row.destination, .overview, "stays In progress")
  }

  func testConfirmedWithoutAVerdictIsChecking() throws {
    let fixture = try SealedFixture(in: base)
    try UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: fixture.sealed.root))
      .save(confirmed(fixture.sealed))
    var row = try row(fixture.visit.workspace)
    XCTAssertEqual(row.subtitle, "1 room · uploaded · checks running")
    XCTAssertEqual(row.status, RowStatusValue(.waiting, "Checking"))
    XCTAssertEqual(row.destination, .overview)

    // A check error at the station is still "checks running" until a verdict exists.
    try StationStatusStore(packageRoot: fixture.sealed.root).record(
      packageId: fixture.sealed.packageId, station: Make.station(.checkError), verdict: nil,
      at: Make.t1402.date)
    row = try self.row(fixture.visit.workspace)
    XCTAssertEqual(row.subtitle, "1 room · uploaded · checks running")

    // Live: Uploaded and Checks delayed are both "checking".
    let live = snapshot(fixture.sealed, state: confirmed(fixture.sealed), activity: .confirmed)
    row = try self.row(fixture.visit.workspace, live: [fixture.sealed.packageId: live])
    XCTAssertEqual(row.status, RowStatusValue(.waiting, "Checking"))
  }

  func testRevisionStartedAfterAVerdict() throws {
    let fixture = try SealedFixture(in: base)
    try StationStatusStore(packageRoot: fixture.sealed.root).record(
      packageId: fixture.sealed.packageId, station: Make.station(.verdictReady),
      verdict: VerdictStatus(Make.verdict(.limited)), at: Make.t1402.date)
    try VisitStore.save(
      VisitFile(
        createdAt: Make.time("2026-01-25T14:00:00Z"), updatedAt: Make.time("2026-10-21T09:00:00Z"),
        record: fixture.visit.record, isSealed: false,
        revision: .init(
          number: 2, basePackageId: fixture.sealed.packageId,
          startedAt: Make.time("2026-10-21T09:00:00Z"))),
      to: fixture.visit.workspace)
    let row = try row(fixture.visit.workspace)
    XCTAssertEqual(row.subtitle, "1 room · revision 2 not sealed yet")
    XCTAssertEqual(row.destination, .overview, "In progress until revision 2 has a verdict")
    XCTAssertNil(row.status)
  }

  // MARK: Sealed

  func testVerdictsAreSealedRows() throws {
    for (outcome, subtitle, status) in [
      (VerdictOutcome.ready, "Revision 1 · sealed Jan 25, 2026", RowStatusValue(.done, "Ready")),
      (.limited, "Revision 1 · sealed Jan 25, 2026", RowStatusValue(.partly, "Limited")),
      (.blocked, "Revision 1 · re-seal needed", RowStatusValue(.missing, "Blocked")),
    ] {
      let folder = base.appendingPathComponent(outcome.rawValue, isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let fixture = try SealedFixture(in: folder)
      try StationStatusStore(packageRoot: fixture.sealed.root).record(
        packageId: fixture.sealed.packageId, station: Make.station(.verdictReady),
        verdict: VerdictStatus(Make.verdict(outcome)), at: Make.t1402.date)
      let row = try row(fixture.visit.workspace)
      XCTAssertEqual(row.subtitle, subtitle, outcome.rawValue)
      XCTAssertEqual(row.status, status)
      XCTAssertEqual(row.destination, .verdict)
      XCTAssertEqual(row.sortDate, Make.time("2026-01-25T15:00:00Z").date)
    }
  }

  func testLiveVerdictWinsOverTheFiles() throws {
    let fixture = try SealedFixture(in: base)
    let live = snapshot(
      fixture.sealed, state: confirmed(fixture.sealed), activity: .confirmed,
      verdict: VerdictStatus(Make.verdict(.ready)))
    let row = try row(fixture.visit.workspace, live: [fixture.sealed.packageId: live])
    XCTAssertEqual(row.status, RowStatusValue(.done, "Ready"))
    XCTAssertEqual(row.destination, .verdict)
  }

  // MARK: The whole home

  func testHomeSectionsSortingAndEmptyFolders() throws {
    try visit(Make.record([Make.capture("Floor 1")], projectName: "Older"), updatedAt: "2026-10-20T10:00:00Z")
    try visit(Make.record([Make.capture("Floor 1")], projectName: "Newer"), updatedAt: "2026-10-21T10:00:00Z")
    let fixture = try SealedFixture(in: base)
    try StationStatusStore(packageRoot: fixture.sealed.root).record(
      packageId: fixture.sealed.packageId, station: Make.station(.verdictReady),
      verdict: VerdictStatus(Make.verdict(.limited)), at: Make.t1402.date)
    // Empty folders (the v1 app made one at every launch) and stray files are not visits.
    _ = try VisitWorkspace.create(in: base)
    try Data("x".utf8).write(to: base.appendingPathComponent(".DS_Store"))

    let state = CaptureLibrary.load(
      visitsRoot: base, operatorName: "Dana Ruiz", hasPendingUploads: true, timeZone: utc)
    XCTAssertEqual(state.inProgress.map(\.title), ["Newer", "Older"])
    XCTAssertEqual(state.sealed.map(\.title), ["Fixture box-room"])
    XCTAssertEqual(state.operatorName, "Dana Ruiz")
    XCTAssertEqual(state.accountTitle, "Signed in as Dana Ruiz")
    XCTAssertEqual(state.accountMessage, "Uploads resume after you sign in again.")
    XCTAssertFalse(state.isEmpty)
  }

  func testEmptyHome() {
    let state = CaptureLibrary.load(visitsRoot: base, operatorName: "Dana Ruiz", timeZone: utc)
    XCTAssertTrue(state.isEmpty)
    XCTAssertNil(state.accountMessage)
    let missing = CaptureLibrary.load(
      visitsRoot: base.appendingPathComponent("absent"), operatorName: "x", timeZone: utc)
    XCTAssertTrue(missing.isEmpty)
  }

  // MARK: v1 workspaces (the owner's visits on the phone)

  func testV1VisitsShowUpAfterTheUpdate() throws {
    // A v1 visit that reached Package ready (a draft) but was never sealed.
    let drafted = try FixtureVisit("box-room", in: base)
    _ = try VisitPackageBuilder(workspace: drafted.workspace, appVersion: "1.0.0")
      .plan(record: drafted.record, photos: drafted.photos, controls: drafted.controls)
    // A v1 visit sealed and confirmed by the station.
    let sealed = try SealedFixture(in: base)
    try UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: sealed.sealed.root))
      .save(confirmed(sealed.sealed))
    // A v1 visit with a scan and nothing else.
    let scansOnly = try VisitWorkspace.create(in: base)
    let folder = scansOnly.originalsRoot.appendingPathComponent(
      "Original Exports/floor-1/\(LowercaseUUID().rawValue)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: folder.appendingPathComponent("roomplan.json"))
    let scanDate = try XCTUnwrap(
      try folder.appendingPathComponent("roomplan.json")
        .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

    let state = CaptureLibrary.load(visitsRoot: base, operatorName: "Field test", timeZone: utc)
    let rows = Dictionary(uniqueKeysWithValues: state.inProgress.map { ($0.id, $0) })
    XCTAssertEqual(rows[drafted.workspace.id]?.subtitle, "1 room · not sealed yet")
    XCTAssertEqual(rows[sealed.visit.workspace.id]?.subtitle, "1 room · uploaded · checks running")
    let legacy = try XCTUnwrap(rows[scansOnly.id])
    XCTAssertEqual(legacy.title, CaptureLibrary.legacyTitle(scanDate, timeZone: utc))
    XCTAssertTrue(legacy.title.hasPrefix("Scan of "))
    XCTAssertEqual(legacy.subtitle, "1 scan · no HUB project recorded")
    XCTAssertEqual(state.inProgress.count, 3)
    XCTAssertTrue(try XCTUnwrap(CaptureLibrary.visit(scansOnly)).isLegacyScansOnly)
  }
}
