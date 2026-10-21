import CaptureContract
import Foundation
import PackageCore
import XCTest

@testable import AppCore

/// UploadCoordinator v2 (phone-package §4, §7, §9.1): paused offline, Upload stopped and the
/// re-seal, following the station after the verdict, and the UI-test station's options.
final class UploadCoordinatorTests: XCTestCase {
  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDownWithError() throws {
    if let base { Fixtures.removeTemporaryDirectory(base) }
  }

  /// A station that refuses every request with `error`.
  struct RefusingService: PackageUploadService {
    let error: any Error & Sendable
    func openSession(_ request: UploadSessionRequest) async throws -> UploadSession { throw error }
    func completeFile(packageId: UUID, path: String) async throws -> FileCheckResult { throw error }
    func seal(packageId: UUID, manifestJSON: Data) async throws -> PackageSealResult { throw error }
  }

  struct NoTransport: BlobTransport {
    func putBlob(_ upload: BlobUpload) async throws {}
    func putBlock(_ upload: BlobUpload, blockId: String, offset: Int64, length: Int) async throws {}
    func putBlockList(_ upload: BlobUpload, blockIds: [String]) async throws {}
  }

  struct StopSleeping: Error {}

  private func coordinator(
    _ sealed: SealedPackage, service: any PackageUploadService,
    status: any PackageStatusSource = ScriptedStatusSource([.failure(StationAPIError.offline)]),
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in throw StopSleeping() }
  ) -> UploadCoordinator {
    UploadCoordinator(
      package: sealed, dealId: "D", service: service, transport: NoTransport(),
      statusSource: status, sleep: sleep)
  }

  func testOfflineIsAPauseWithItsCaption() async throws {
    let fixture = try SealedFixture(in: base)
    let coordinator = coordinator(fixture.sealed, service: RefusingService(error: StationAPIError.offline))
    coordinator.start()
    await coordinator.waitUntilIdle()
    let snapshot = coordinator.snapshot
    XCTAssertEqual(snapshot.activity, .waitingToRetry(.offline))
    XCTAssertEqual(snapshot.phase, .paused(.offline))
    XCTAssertEqual(snapshot.title, "Uploading")
    XCTAssertEqual(snapshot.caption, "Paused: no connection. Resumes on its own. You can close the app.")
  }

  func testAStationErrorIsAPauseToo() async throws {
    let fixture = try SealedFixture(in: base)
    let coordinator = coordinator(
      fixture.sealed, service: RefusingService(error: StationProblem(status: 503, code: "storage_unavailable")))
    coordinator.start()
    await coordinator.waitUntilIdle()
    XCTAssertEqual(coordinator.snapshot.activity, .waitingToRetry(.stationUnavailable))
  }

  func testARefusalStopsTheUploadAndTheReSealSupersedesIt() async throws {
    let fixture = try SealedFixture(in: base)
    let coordinator = coordinator(
      fixture.sealed, service: RefusingService(error: StationProblem(status: 409, code: "package_conflict")))
    coordinator.start()
    await coordinator.waitUntilIdle()
    var snapshot = coordinator.snapshot
    XCTAssertEqual(snapshot.phase, .stopped("The station refused the upload (409 package_conflict)."))
    XCTAssertEqual(snapshot.title, "Upload stopped")
    XCTAssertEqual(snapshot.progress.rows.filter { $0.status == .stopped }.count, 1)
    XCTAssertEqual(PendingUploads.find(visitsRoot: base).count, 1, "nothing deleted, still pending")

    // "Re-seal as revision 2": the new revision is sealed, this one is superseded.
    let next = LowercaseUUID()
    try coordinator.supersede(by: next)
    snapshot = coordinator.snapshot
    XCTAssertEqual(snapshot.state.supersededBy, next)
    XCTAssertTrue(snapshot.isSuperseded)
    let saved = try UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: fixture.sealed.root)).load()
    XCTAssertEqual(saved?.supersededBy, next)
    XCTAssertTrue(PendingUploads.find(visitsRoot: base).isEmpty, "never resumed")
    XCTAssertTrue(fixture.sealed.verify().isEmpty, "revision 1 stays on the phone, unchanged")
    coordinator.start()
    await coordinator.waitUntilIdle()
    XCTAssertEqual(coordinator.snapshot.state.supersededBy, next, "a superseded package does not start")
  }

  /// After the verdict the publication is followed at most `verdictFollowLimit`.
  func testThePublicationIsFollowedForAtMostHalfAnHour() async throws {
    let fixture = try SealedFixture(in: base)
    let (client, storage) = try uiTestStation()
    // Upload for real against the stub, then follow a scripted station that never publishes.
    let verdict = VerdictStatus(Make.verdict(.ready))
    let script = ScriptedStatusSource(
      [.success(Make.station(.verdictReady, publication: .init(status: .publishing), verdictId: verdict.verdictId))],
      verdicts: [verdict])
    let clock = TestClock()
    let coordinator = UploadCoordinator(
      package: fixture.sealed, dealId: "D", service: StationUploadService(client: client),
      transport: UITestBlobTransport(storage: storage), statusSource: script,
      sleep: { seconds in clock.advance(seconds) }, now: { clock.now }, pollInterval: 15,
      verdictFollowLimit: 30 * 60)
    coordinator.start()
    await coordinator.waitUntilIdle()
    XCTAssertEqual(coordinator.snapshot.verdict, verdict)
    XCTAssertEqual(script.calls.verdict, 1)
    // One read, then one every 15 s for 30 minutes.
    XCTAssertEqual(script.calls.package, 1 + 30 * 60 / 15)
    XCTAssertEqual(
      coordinator.snapshot.timeline(now: clock.now, timeZone: Make.utc).row(.published)?.detail,
      "Publishing")
  }

  /// Through a check error the station retries, so the phone keeps asking; a later verdict id
  /// (the checks ran again) replaces the first verdict.
  func testCheckErrorsAreFollowedAndANewerVerdictReplacesTheOld() async throws {
    let fixture = try SealedFixture(in: base)
    let (client, storage) = try uiTestStation()
    let first = VerdictStatus(Make.verdict(.blocked))
    let second = VerdictStatus(Make.verdict(.ready))
    let published = StationPackageInfo.Publication(status: .published, publishedAt: Make.t1402)
    let script = ScriptedStatusSource(
      [
        .success(Make.station(.checkError)), .failure(StationAPIError.offline),
        .success(Make.station(.verdictReady, publication: .init(status: .pending), verdictId: first.verdictId)),
        .success(Make.station(.verdictReady, publication: published, verdictId: second.verdictId)),
      ], verdicts: [first, second])
    let snapshots = SnapshotLog()
    let coordinator = UploadCoordinator(
      package: fixture.sealed, dealId: "D", service: StationUploadService(client: client),
      transport: UITestBlobTransport(storage: storage), statusSource: script, sleep: { _ in },
      onChange: { snapshots.append($0) })
    coordinator.start()
    await coordinator.waitUntilIdle()
    XCTAssertTrue(snapshots.all.contains { $0.phase == .checksDelayed })
    XCTAssertTrue(snapshots.all.contains { $0.verdict == first })
    XCTAssertEqual(coordinator.snapshot.verdict, second)
    XCTAssertEqual(coordinator.snapshot.station?.publication, published)
    XCTAssertEqual(try StationStatusStore(packageRoot: fixture.sealed.root).load()?.verdict, second)
  }

  private func uiTestStation(_ options: UITestStationOptions = UITestStationOptions()) throws -> (
    StationAPI, UITestBlobStorage
  ) {
    let storage = UITestBlobStorage(offlineSeconds: options.offlineSeconds)
    return (
      StationAPI(
        configuration: try .init(stationURL: UITestStationTransport.stationURL),
        tokenProvider: UITestTokenProvider(),
        transport: UITestStationTransport(storage: storage, options: options)),
      storage
    )
  }

  // MARK: UI-test station (Debug only)

  func testUITestOptionsFromLaunchArguments() {
    XCTAssertEqual(
      UITestStationOptions(arguments: ["app", "-ChapterUITestVerdict", "limited"]),
      UITestStationOptions(verdict: .limited))
    XCTAssertEqual(
      UITestStationOptions(arguments: ["-ChapterUITestOffline", "-ChapterUITestRefuse"]),
      UITestStationOptions(offlineSeconds: 20, refuseFirstSession: true))
    XCTAssertEqual(
      UITestStationOptions(arguments: ["-ChapterUITestOffline", "5"]),
      UITestStationOptions(offlineSeconds: 5))
    XCTAssertEqual(UITestStationOptions(arguments: ["-ChapterUITestVerdict", "maybe"]), UITestStationOptions())
  }

  func testTheUITestStationRefusesTheFirstSessionThenAcceptsATryAgain() async throws {
    let fixture = try SealedFixture(in: base)
    let (client, storage) = try uiTestStation(UITestStationOptions(refuseFirstSession: true))
    let coordinator = UploadCoordinator(
      package: fixture.sealed, dealId: "D", service: StationUploadService(client: client),
      transport: UITestBlobTransport(storage: storage),
      statusSource: StationStatusSource(client: client), sleep: { _ in throw StopSleeping() })
    coordinator.start()
    await coordinator.waitUntilIdle()
    XCTAssertEqual(coordinator.snapshot.phase, .stopped("The station refused the upload (409 package_conflict)."))
    coordinator.retry()
    await coordinator.waitUntilIdle()
    XCTAssertTrue(coordinator.snapshot.isConfirmedByStation, "Try again goes through")
  }

  func testTheUITestBlobStorageIsOfflineForItsWindow() throws {
    let storage = UITestBlobStorage(offlineSeconds: 20)
    let start = Date(timeIntervalSince1970: 1_000)
    XCTAssertThrowsError(try storage.checkConnection(now: start)) { error in
      XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
    }
    XCTAssertThrowsError(try storage.checkConnection(now: start.addingTimeInterval(19)))
    XCTAssertNoThrow(try storage.checkConnection(now: start.addingTimeInterval(20)))
    XCTAssertNoThrow(try UITestBlobStorage().checkConnection())
  }

  func testTheUITestStationKeepsTheNextRevisionNotice() async throws {
    let fixture = try SealedFixture(in: base)
    let (client, storage) = try uiTestStation()
    let coordinator = UploadCoordinator(
      package: fixture.sealed, dealId: "D", service: StationUploadService(client: client),
      transport: UITestBlobTransport(storage: storage),
      statusSource: StationStatusSource(client: client), sleep: { _ in throw StopSleeping() })
    coordinator.start()
    await coordinator.waitUntilIdle()
    XCTAssertTrue(coordinator.snapshot.isConfirmedByStation)

    let draft = NextRevisionNoticeDraft(
      revision: 2, updatedAt: Make.t1402,
      rows: [.init(kind: .added, subject: .photos, title: "1 photo", detail: "Room 1 \u{00B7} ceiling")])
    try await StationNextRevisionNotices(client: client).send(
      draft, basePackageId: fixture.sealed.packageId)
    let package = try await client.getPackage(packageId: fixture.sealed.packageId.uuid)
    XCTAssertEqual(package.nextRevision?.changes.map(\.title), ["1 photo"])
    XCTAssertEqual(package.nextRevision?.updatedBy, UITestTokenProvider.operatorName)
    do {
      try await StationNextRevisionNotices(client: client).send(
        NextRevisionNoticeDraft(revision: 3, updatedAt: Make.t1402, rows: []),
        basePackageId: fixture.sealed.packageId)
      XCTFail("revision 3 is not the next revision of revision 1")
    } catch let error as StationAPIError {
      XCTAssertEqual(error.problem?.code, "revision_mismatch")
    }
  }
}
