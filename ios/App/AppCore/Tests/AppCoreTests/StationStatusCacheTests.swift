import CaptureContract
import Foundation
import PackageCore
import XCTest

@testable import AppCore

/// `<packageId>.station-status.json` (critique R-27) and the background refresh that keeps it
/// current and finds the verdicts to notify (phone-package §7).
final class StationStatusCacheTests: XCTestCase {
  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDownWithError() throws {
    if let base { Fixtures.removeTemporaryDirectory(base) }
  }

  func testTheCacheSitsNextToTheUploadState() throws {
    let fixture = try SealedFixture(in: base)
    let store = StationStatusStore(packageRoot: fixture.sealed.root)
    let id = fixture.sealed.packageId.rawValue
    XCTAssertEqual(store.url.lastPathComponent, "\(id).station-status.json")
    XCTAssertEqual(
      store.url.deletingLastPathComponent(),
      UploadStateStore.defaultURL(forPackageAt: fixture.sealed.root).deletingLastPathComponent())
    XCTAssertNil(try store.load())

    let verdict = VerdictStatus(Make.verdict(.limited, limitations: ["a"]))
    let station = Make.station(
      .verdictReady, checks: .init(status: .completed, finishedAt: Make.t1402),
      publication: .init(status: .publishing), verdictId: verdict.verdictId)
    let saved = try store.record(
      packageId: fixture.sealed.packageId, station: station, verdict: verdict, at: Make.t1402.date)
    XCTAssertEqual(try store.load(), saved)
    XCTAssertEqual(saved.formatVersion, 1)
    XCTAssertEqual(saved.stage, .verdictReady)
    XCTAssertEqual(saved.fetchedAt, Make.t1402)
    XCTAssertEqual(saved.station, station)
    XCTAssertTrue(saved.needsVerdictNotification)
    XCTAssertFalse(saved.isSettled, "publishing")
    let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

    // Notified once; a later answer without a verdict keeps both.
    try store.markNotified(verdict.verdictId)
    var published = station
    published.publication = .init(status: .published, publishedAt: Make.t1402)
    let later = try store.record(
      packageId: fixture.sealed.packageId, station: published, verdict: nil, at: Make.t1402.date)
    XCTAssertEqual(later.verdict, verdict)
    XCTAssertEqual(later.notifiedVerdictId, verdict.verdictId)
    XCTAssertFalse(later.needsVerdictNotification)
    XCTAssertTrue(later.isSettled)
  }

  func testTheCacheSchemaIsTheOneTheCapturesHomeReads() throws {
    let fixture = try SealedFixture(in: base)
    let store = StationStatusStore(packageRoot: fixture.sealed.root)
    let verdict = VerdictStatus(Make.verdict(.limited, limitations: ["a"], nextActions: ["x"]))
    try store.record(
      packageId: fixture.sealed.packageId,
      station: Make.station(.verdictReady, verdictId: verdict.verdictId), verdict: verdict,
      at: Make.t1402.date)
    let json = try JSON.parse(try Data(contentsOf: store.url))
    XCTAssertEqual(json["formatVersion"]?.number, 1)
    XCTAssertEqual(json["packageId"]?.string, fixture.sealed.packageId.rawValue)
    XCTAssertEqual(json["stage"]?.string, "verdict_ready")
    XCTAssertEqual(json["verdict"]?["outcome"]?.string, "limited")
    XCTAssertEqual(json["fetchedAt"]?.string, "2026-05-16T14:02:00Z")
    XCTAssertEqual(json["links"]?["review"]?.string, "https://review.test/packages/1")
  }

  func testAnUnknownFormatIsNotRead() throws {
    let fixture = try SealedFixture(in: base)
    let store = StationStatusStore(packageRoot: fixture.sealed.root)
    var cache = StationStatusCache(
      packageId: fixture.sealed.packageId, station: Make.station(.checking), verdict: nil,
      fetchedAt: Make.t1402)
    cache.formatVersion = 2
    try store.save(cache)
    XCTAssertThrowsError(try store.load()) { error in
      guard case .unreadable = error as? StationStatusCacheError else { return XCTFail("\(error)") }
    }
  }

  // MARK: Background refresh

  private func confirm(_ sealed: SealedPackage) throws {
    var state = UploadState(package: sealed, dealId: "D")
    for index in state.files.indices { state.files[index].phase = .verified }
    state.sealResult = PackageSealResult(
      packageId: sealed.packageId, visitId: sealed.visitId, dealId: "D", revision: 1,
      status: .checksQueued, createdAt: Make.t1402, files: [])
    try UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: sealed.root)).save(state)
  }

  func testOnlyConfirmedUnsettledPackagesAreFollowed() throws {
    let fixture = try SealedFixture(in: base)
    XCTAssertTrue(StationStatusRefresh.followed(visitsRoot: base).isEmpty, "not confirmed yet")
    try confirm(fixture.sealed)
    XCTAssertEqual(StationStatusRefresh.followed(visitsRoot: base).map(\.package.packageId), [fixture.sealed.packageId])

    let store = StationStatusStore(packageRoot: fixture.sealed.root)
    let verdict = VerdictStatus(Make.verdict(.ready))
    try store.record(
      packageId: fixture.sealed.packageId,
      station: Make.station(
        .verdictReady, publication: .init(status: .publishFailed), verdictId: verdict.verdictId),
      verdict: verdict, at: Make.t1402.date)
    XCTAssertTrue(StationStatusRefresh.followed(visitsRoot: base).isEmpty, "settled")
  }

  func testARefreshCachesTheVerdictAndNotifiesItOnce() async throws {
    let fixture = try SealedFixture(in: base)
    try confirm(fixture.sealed)
    let verdict = VerdictStatus(Make.verdict(.limited, limitations: ["a", "b"]))
    let source = ScriptedStatusSource(
      [.success(Make.station(.verdictReady, publication: .init(status: .publishing), verdictId: verdict.verdictId))],
      verdicts: [verdict])

    let first = await StationStatusRefresh.refresh(
      StationStatusRefresh.followed(visitsRoot: base), source: source, now: { Make.t1402.date })
    XCTAssertEqual(first.notifications.map(\.title), ["Verdict: Limited"])
    XCTAssertEqual(
      first.notifications.first?.body, "Fixture box-room \u{00B7} revision 1. Details: spatial report in the HUB.")
    XCTAssertTrue(first.stillFollowing, "publication not final")
    XCTAssertEqual(first.failed, 0)
    let store = StationStatusStore(packageRoot: fixture.sealed.root)
    XCTAssertEqual(try store.load()?.verdict, verdict)
    try store.markNotified(verdict.verdictId)

    let second = await StationStatusRefresh.refresh(
      StationStatusRefresh.followed(visitsRoot: base), source: source, now: { Make.t1402.date })
    XCTAssertTrue(second.notifications.isEmpty, "never twice for one verdict")
    XCTAssertEqual(source.calls.verdict, 1, "a known verdict is not fetched again")
  }

  func testARefreshThatCannotReachTheStationKeepsFollowing() async throws {
    let fixture = try SealedFixture(in: base)
    try confirm(fixture.sealed)
    let source = ScriptedStatusSource([.failure(StationAPIError.offline)])
    let outcome = await StationStatusRefresh.refresh(
      StationStatusRefresh.followed(visitsRoot: base), source: source)
    XCTAssertEqual(outcome.failed, 1)
    XCTAssertTrue(outcome.stillFollowing)
    XCTAssertTrue(outcome.notifications.isEmpty)
    XCTAssertNil(try StationStatusStore(packageRoot: fixture.sealed.root).load())
  }
}

/// The next-revision notice is debounced, best effort and stops at sealing (§10.4).
final class NextRevisionNotifierTests: XCTestCase {
  final class Recorder: NextRevisionNoticeSending, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [(NextRevisionNoticeDraft, LowercaseUUID)] = []
    var fails = false

    func send(_ notice: NextRevisionNoticeDraft, basePackageId: LowercaseUUID) async throws {
      try lock.withLock {
        if fails { throw StationAPIError.offline }
        sent.append((notice, basePackageId))
      }
    }

    var all: [(NextRevisionNoticeDraft, LowercaseUUID)] { lock.withLock { sent } }
  }

  private func notice(_ title: String) -> NextRevisionNoticeDraft {
    NextRevisionNoticeDraft(
      revision: 2, updatedAt: Make.t1402,
      rows: [.init(kind: .added, subject: .photos, title: title, detail: "d")])
  }

  func testChangesAreSentOnceTheyStop() async {
    let recorder = Recorder()
    let gate = Gate()
    let notifier = NextRevisionNotifier(sender: recorder, delay: 10, sleep: { _ in await gate.wait() })
    let baseId = LowercaseUUID()
    await notifier.changed(notice("1 photo"), basePackageId: baseId)
    await notifier.changed(notice("2 photos"), basePackageId: baseId)
    gate.open()
    await notifier.waitUntilIdle()
    XCTAssertEqual(recorder.all.map(\.0.rows.first?.title), ["2 photos"], "the latest only")
    XCTAssertEqual(recorder.all.first?.1, baseId)
  }

  func testFlushSendsNowAndFailuresAreIgnored() async {
    let recorder = Recorder()
    let notifier = NextRevisionNotifier(
      sender: recorder, delay: 10, sleep: { _ in try await Task.sleep(nanoseconds: 60_000_000_000) })
    await notifier.changed(notice("1 photo"), basePackageId: LowercaseUUID())
    recorder.fails = true
    await notifier.flush()
    let failedCount = await notifier.sentCount
    XCTAssertEqual(failedCount, 0)
    recorder.fails = false
    await notifier.flush()
    XCTAssertEqual(recorder.all.count, 1)
    await notifier.stop()
    await notifier.flush()
    XCTAssertEqual(recorder.all.count, 1, "nothing after sealing")
  }
}

/// Lets a test decide when a sleep ends.
final class Gate: @unchecked Sendable {
  private let lock = NSLock()
  private var isOpen = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    await withCheckedContinuation { continuation in
      let resume = lock.withLock { () -> Bool in
        if isOpen { return true }
        waiting.append(continuation)
        return false
      }
      if resume { continuation.resume() }
    }
  }

  func open() {
    let continuations = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
      isOpen = true
      defer { waiting = [] }
      return waiting
    }
    continuations.forEach { $0.resume() }
  }
}
