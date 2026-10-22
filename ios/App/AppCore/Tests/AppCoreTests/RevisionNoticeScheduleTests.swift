import CaptureContract
import Foundation
import XCTest

@testable import AppCore

/// The next-revision notice follows every change of revision n (phone-package §10.4, addendum
/// C8): one build once the changes stop, at once on the review, again on the foreground, never
/// after sealing, and still when the visit has left the screen.
final class RevisionNoticeScheduleTests: XCTestCase {
  /// What the station was sent: each notice's first row title and its base package.
  final class Station: NextRevisionNoticeSending, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [(title: String, base: LowercaseUUID)] = []

    func send(_ notice: NextRevisionNoticeDraft, basePackageId: LowercaseUUID) async throws {
      lock.withLock { sent.append((notice.rows.first?.title ?? "", basePackageId)) }
    }

    var titles: [String] { lock.withLock { sent.map(\.title) } }
    var bases: [LowercaseUUID] { lock.withLock { sent.map(\.base) } }
  }

  /// A visit in revision mode as the app holds it: it hands the schedule a build made from what
  /// it has now (the build keeps no reference to the visit).
  final class Visit {
    let base = LowercaseUUID()
    var photos = 0

    @MainActor
    func photoSaved(_ schedule: RevisionNoticeSchedule) {
      photos += 1
      schedule.changed(
        basePackageId: base, build: RevisionNoticeScheduleTests.build("\(photos) photo"))
    }
  }

  static func notice(_ title: String) -> NextRevisionNoticeDraft {
    NextRevisionNoticeDraft(
      revision: 2, updatedAt: Make.t1402,
      rows: [.init(kind: .added, subject: .photos, title: title, detail: "d")])
  }

  static func build(_ title: String) -> RevisionNoticeSchedule.Build {
    { notice(title) }
  }

  /// A sleep that never ends by itself (cancelled or not): only `flush`, `built` and `stop` act.
  private static let never: @Sendable (TimeInterval) async throws -> Void = { _ in
    try await Task.sleep(nanoseconds: 600_000_000_000)
  }

  @MainActor
  func testOneBuildRunsOnceTheChangesStopAndItsNoticeIsSent() async {
    let station = Station()
    let gate = Gate()
    let schedule = RevisionNoticeSchedule(
      sender: station, delay: 10,
      sleep: { _ in await gate.wait() })
    let base = LowercaseUUID()
    schedule.changed(basePackageId: base, build: Self.build("1 photo"))
    schedule.changed(basePackageId: base, build: Self.build("2 photos"))
    schedule.changed(basePackageId: base, build: Self.build("3 photos"))
    await Task.yield()
    XCTAssertEqual(schedule.buildCount, 0, "nothing is built while the changes come")
    XCTAssertEqual(station.titles, [])
    gate.open()
    await schedule.waitUntilIdle()
    XCTAssertEqual(schedule.buildCount, 1, "one build for the three changes")
    XCTAssertEqual(station.titles, ["3 photos"])
    XCTAssertEqual(station.bases, [base])
  }

  @MainActor
  func testTheNoticeIsStillSentAfterTheVisitLeftTheScreen() async {
    let station = Station()
    let gate = Gate()
    let schedule = RevisionNoticeSchedule(
      sender: station, delay: 10,
      sleep: { _ in await gate.wait() })
    var visit: Visit? = Visit()
    let base = visit!.base
    visit?.photoSaved(schedule)
    weak let gone = visit
    visit = nil
    XCTAssertNil(gone, "the visit's model is gone before the 10 s")
    gate.open()
    await schedule.waitUntilIdle()
    XCTAssertEqual(station.titles, ["1 photo"])
    XCTAssertEqual(station.bases, [base])
  }

  @MainActor
  func testForegroundBuildsNowOrSendsTheLastNoticeAgain() async {
    let station = Station()
    let schedule = RevisionNoticeSchedule(
      sender: station, delay: 10, sleep: Self.never)
    let base = LowercaseUUID()
    await schedule.flush()
    XCTAssertEqual(station.titles, [], "nothing to send yet")
    schedule.changed(basePackageId: base, build: Self.build("1 photo"))
    await schedule.flush()
    XCTAssertEqual(station.titles, ["1 photo"], "the waiting build runs at once")
    await schedule.flush()
    XCTAssertEqual(station.titles, ["1 photo", "1 photo"], "again, the station may have missed it")
    XCTAssertEqual(schedule.buildCount, 1, "without building again")
  }

  @MainActor
  func testTheReviewSendsAtOnceAndSealingStopsEverything() async {
    let station = Station()
    let schedule = RevisionNoticeSchedule(
      sender: station, delay: 10, sleep: Self.never)
    let base = LowercaseUUID()
    schedule.changed(basePackageId: base, build: Self.build("waiting"))
    await schedule.built(Self.notice("reviewed"), basePackageId: base)
    XCTAssertEqual(station.titles, ["reviewed"])
    await schedule.flush()
    XCTAssertEqual(station.titles, ["reviewed", "reviewed"])
    XCTAssertEqual(schedule.buildCount, 0, "the review's own build made the waiting one useless")

    schedule.changed(basePackageId: base, build: Self.build("after"))
    await schedule.stop(basePackageId: base)
    await schedule.flush()
    await schedule.waitUntilIdle()
    XCTAssertEqual(station.titles, ["reviewed", "reviewed"], "nothing after sealing")
    XCTAssertEqual(schedule.buildCount, 0)
  }

  @MainActor
  func testAChangeDuringABuildDropsTheOutOfDateNotice() async {
    let station = Station()
    let schedule = RevisionNoticeSchedule(
      sender: station, delay: 0, sleep: { _ in })
    let base = LowercaseUUID()
    let building = Gate()
    schedule.changed(basePackageId: base) {
      await building.wait()
      return Self.notice("old")
    }
    for _ in 0..<200 where schedule.buildCount == 0 {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTAssertEqual(schedule.buildCount, 1, "the first build is running")
    schedule.changed(basePackageId: base, build: Self.build("new"))
    await schedule.waitUntilIdle()
    building.open()
    // Let the old build finish.
    for _ in 0..<20 { try? await Task.sleep(nanoseconds: 5_000_000) }
    XCTAssertEqual(station.titles, ["new"], "the notice of the earlier state is never sent")
  }

  @MainActor
  func testAnotherVisitsWaitingBuildRunsInsteadOfBeingReplaced() async {
    let station = Station()
    let gate = Gate()
    let schedule = RevisionNoticeSchedule(
      sender: station, delay: 10,
      sleep: { _ in await gate.wait() })
    let first = LowercaseUUID()
    let second = LowercaseUUID()
    schedule.changed(basePackageId: first, build: Self.build("first visit"))
    schedule.changed(basePackageId: second, build: Self.build("second visit"))
    gate.open()
    await schedule.waitUntilIdle()
    XCTAssertEqual(Set(station.titles), ["first visit", "second visit"])
    XCTAssertEqual(Set(station.bases), [first, second])
  }

  @MainActor
  func testAFailedBuildIsDroppedAndTheNextChangeTriesAgain() async {
    let station = Station()
    let schedule = RevisionNoticeSchedule(
      sender: station, delay: 0, sleep: { _ in })
    let base = LowercaseUUID()
    schedule.changed(basePackageId: base) { throw CocoaError(.fileReadNoSuchFile) }
    await schedule.waitUntilIdle()
    XCTAssertEqual(station.titles, [], "never shown, never blocking")
    schedule.changed(basePackageId: base, build: Self.build("1 photo"))
    await schedule.waitUntilIdle()
    XCTAssertEqual(station.titles, ["1 photo"])
    XCTAssertEqual(schedule.buildCount, 2)
  }
}
