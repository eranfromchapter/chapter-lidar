import CaptureContract
import Foundation
import XCTest

@testable import AppCore

/// The Station card (phone-package §4.1, §5.1): every row in every state, publication claimed
/// only when the station says so, times across midnight. Replaces
/// `testStationStepsNeverClaimHubPublication`.
final class StationTimelineTests: XCTestCase {
  private let utc = Make.utc
  private let now = Make.time("2026-05-16T15:00:00Z").date

  private func timeline(
    registeredAt: UTCTimestamp? = nil, confirmed: Bool = false, station: StationPackageInfo? = nil,
    verdict: VerdictStatus? = nil, includeRegistered: Bool = true, now: Date? = nil
  ) -> StationTimeline {
    StationTimeline.make(
      registeredAt: registeredAt, isConfirmed: confirmed, station: station, verdict: verdict,
      includeRegistered: includeRegistered, now: now ?? self.now, timeZone: utc)
  }

  private func verdict(_ outcome: VerdictOutcome, at time: String = "2026-05-16T14:02:00Z")
    -> VerdictStatus
  {
    VerdictStatus(Make.verdict(outcome, evaluatedAt: Make.time(time)))
  }

  func testBeforeTheStationAnswered() {
    let rows = timeline().rows
    XCTAssertEqual(rows.map(\.id), [.registered, .checks, .verdict, .published])
    XCTAssertEqual(rows.map(\.title), ["Registered", "Checks", "Verdict", "Published to the HUB"])
    XCTAssertEqual(rows.map(\.detail), ["When online", "After upload", "\u{2014}", "\u{2014}"])
    XCTAssertEqual(rows.map(\.state), [.pending, .pending, .pending, .pending])
    XCTAssertEqual(rows.map(\.shape), [.ring, .ring, .ring, .ring])
    XCTAssertEqual(rows[0].accessibilityLabel, "Registered, not yet, when online")
    XCTAssertEqual(rows[1].accessibilityLabel, "Checks, not yet, after upload")
    XCTAssertEqual(rows[2].accessibilityLabel, "Verdict, not yet")
  }

  func testRegisteredWhileUploading() {
    let rows = timeline(registeredAt: Make.time("2026-05-16T14:02:00Z")).rows
    XCTAssertEqual(rows[0].state, .done)
    XCTAssertEqual(rows[0].shape, .filled)
    XCTAssertEqual(rows[0].detail, "14:02", "today: the time only")
    XCTAssertTrue(rows[0].isTime)
    XCTAssertEqual(rows[0].accessibilityLabel, "Registered, done, 14:02")
    XCTAssertEqual(rows[1].detail, "After upload")
  }

  func testChecksQueuedRunningAndDelayed() {
    let registered = Make.time("2026-05-16T14:02:00Z")
    XCTAssertEqual(
      timeline(registeredAt: registered, confirmed: true, station: Make.station(.checksQueued))
        .row(.checks),
      StationTimeline.Row(id: .checks, state: .inProgress, shape: .ring, title: "Checks", detail: "Queued"))
    XCTAssertEqual(
      timeline(registeredAt: registered, confirmed: true, station: Make.station(.checking))
        .row(.checks)?.detail, "Running")
    XCTAssertEqual(
      timeline(registeredAt: registered, confirmed: true).row(.checks)?.detail, "Queued",
      "sealed, the station not asked yet")
    let delayed = timeline(registeredAt: registered, confirmed: true, station: Make.station(.checkError))
      .row(.checks)
    XCTAssertEqual(delayed?.state, .problem)
    XCTAssertEqual(delayed?.shape, .triangle)
    XCTAssertEqual(delayed?.detail, "Delayed \u{00B7} the station retries")
    XCTAssertEqual(delayed?.accessibilityLabel, "Checks, delayed, the station retries")
  }

  func testVerdictReceivedRowsOnAnotherDay() {
    let station = Make.station(
      .verdictReady,
      checks: .init(status: .completed, finishedAt: Make.time("2026-05-16T14:01:00Z")),
      publication: .init(status: .published, publishedAt: Make.time("2026-05-16T14:03:00Z")))
    let rows = timeline(
      registeredAt: Make.time("2026-05-16T13:55:00Z"), confirmed: true, station: station,
      verdict: verdict(.limited), includeRegistered: false,
      now: Make.time("2026-05-20T09:00:00Z").date
    ).rows
    XCTAssertEqual(rows.map(\.id), [.checks, .verdict, .published], "no Registered row")
    XCTAssertEqual(rows.map(\.title), ["Checks run", "Verdict \u{00B7} Limited", "Published to the HUB"])
    XCTAssertEqual(rows.map(\.detail), ["May 16 \u{00B7} 14:01", "14:02", "14:03"])
    XCTAssertEqual(rows.map(\.state), [.done, .done, .done])
    XCTAssertEqual(rows.map(\.shape), [.filled, .triangle, .filled])
    XCTAssertEqual(rows[2].accessibilityLabel, "Published to the HUB, done, 14:03")
  }

  func testTimesAcrossMidnight() {
    let station = Make.station(
      .verdictReady,
      checks: .init(status: .completed, finishedAt: Make.time("2026-05-16T00:03:00Z")))
    let rows = timeline(
      registeredAt: Make.time("2026-05-15T23:58:00Z"), confirmed: true, station: station,
      verdict: verdict(.ready, at: "2026-05-16T00:04:00Z")
    ).rows
    XCTAssertEqual(
      rows.map(\.detail),
      ["May 15 \u{00B7} 23:58", "May 16 \u{00B7} 00:03", "00:04", "\u{2014}"])
  }

  func testTheVerdictCarriesItsShapeAndWord() {
    let station = Make.station(.verdictReady)
    for (outcome, shape, word) in [
      (VerdictOutcome.ready, StationTimeline.Shape.filled, "Ready"),
      (.limited, .triangle, "Limited"), (.blocked, .square, "Blocked"),
    ] {
      let row = timeline(confirmed: true, station: station, verdict: verdict(outcome)).row(.verdict)
      XCTAssertEqual(row?.shape, shape)
      XCTAssertEqual(row?.title, "Verdict \u{00B7} \(word)")
    }
  }

  /// "Published to the HUB" is done only when the station says `published`.
  func testPublicationIsNeverClaimed() {
    let ready = verdict(.ready)
    func published(_ publication: StationPackageInfo.Publication?, verdict: VerdictStatus? = nil)
      -> StationTimeline.Row?
    {
      timeline(
        confirmed: true, station: Make.station(.verdictReady, publication: publication),
        verdict: verdict
      ).row(.published)
    }
    XCTAssertEqual(published(nil, verdict: ready)?.state, .pending, "no publication state")
    XCTAssertEqual(published(nil, verdict: ready)?.detail, "\u{2014}")
    XCTAssertEqual(published(.init(status: .pending), verdict: ready)?.detail, "Publishing")
    XCTAssertEqual(published(.init(status: .publishing), verdict: ready)?.state, .inProgress)
    XCTAssertEqual(published(.init(status: .pending))?.detail, "\u{2014}", "no verdict yet")
    let failed = published(.init(status: .publishFailed), verdict: ready)
    XCTAssertEqual(failed?.state, .problem)
    XCTAssertEqual(failed?.detail, "Not yet")
    XCTAssertEqual(failed?.accessibilityLabel, "Published to the HUB, delayed, not yet")
    let unpublished: [StationPackageInfo.Publication.Status?] = [
      nil, .pending, .publishing, .publishFailed,
    ]
    for stage in StationPackageStage.allCases {
      for publication in unpublished {
        let row = timeline(
          registeredAt: Make.t1402, confirmed: true,
          station: Make.station(stage, publication: publication.map { .init(status: $0) }),
          verdict: ready
        ).row(.published)
        XCTAssertNotEqual(row?.state, .done, "\(stage) \(String(describing: publication))")
      }
    }
  }
}

/// Verdict received (phone-package §5.1): word and shape, one sentence, the next visit.
final class VerdictStatusTests: XCTestCase {
  func testTheThreeSentences() {
    let ready = VerdictStatus(Make.verdict(.ready))
    XCTAssertEqual(ready.word, "Ready")
    XCTAssertEqual(
      ready.sentence(published: true),
      "Ready for preliminary existing-condition plans. Details: spatial report in the HUB.")

    let limited = VerdictStatus(
      Make.verdict(.limited, limitations: ["a", "b"], nextActions: ["x"],
        findings: [Make.finding(.limitation, "m", nextAction: "x")]))
    XCTAssertEqual(
      limited.sentence(published: true),
      "Usable for preliminary existing-condition plans, with 2 limitations. Details: spatial "
        + "report in the HUB.")
    XCTAssertEqual(
      limited.sentence(published: false),
      "Usable for preliminary existing-condition plans, with 2 limitations. Details: spatial "
        + "report in the HUB once it is published.")

    let blocked = VerdictStatus(
      Make.verdict(.blocked, nextActions: ["x"],
        findings: [Make.finding(.blocker, "m", nextAction: "x"), Make.finding(.info, "i", nextAction: "None")]))
    XCTAssertEqual(blocked.blockerCount, 1)
    XCTAssertEqual(
      blocked.sentence(published: true),
      "Not usable yet for preliminary existing-condition plans: 1 blocker. Details: spatial report "
        + "in the HUB.")
    let one = VerdictStatus(Make.verdict(.limited, limitations: ["a"]))
    XCTAssertTrue(one.sentence(published: true).contains("with 1 limitation."))
  }

  func testTheNextVisitIsTheStationsWordsWithTheirReason() {
    let actions = [
      "Scan or measure Primary closet on the next visit if it is in scope.",
      "Tape-measure the Room 4 ceiling height.", "Photograph the panel.", "Read the compass.",
    ]
    let status = VerdictStatus(
      Make.verdict(
        .limited, limitations: ["a"], nextActions: actions,
        findings: [
          Make.finding(.limitation, "Primary closet was not scanned", measured: "Primary closet: inaccessible", nextAction: actions[0]),
          Make.finding(.limitation, "Room 4 ceiling height is approximate", nextAction: actions[1]),
          Make.finding(.limitation, "later finding", measured: "ignored", nextAction: actions[0]),
        ]))
    XCTAssertEqual(status.nextVisit.map(\.action), actions, "verbatim, station order")
    XCTAssertEqual(
      status.nextVisit.map(\.reason),
      ["Primary closet: inaccessible", "Room 4 ceiling height is approximate", nil, nil])
    XCTAssertEqual(status.shownNextVisit.count, 3)
    XCTAssertEqual(status.moreNextVisitText, "1 more in the spatial report.")
    XCTAssertNil(VerdictStatus(Make.verdict(.ready)).moreNextVisitText)
    XCTAssertTrue(VerdictStatus(Make.verdict(.ready)).shownNextVisit.isEmpty)
  }

  func testATaskStartingWithAnAcronymKeepsItsCase() {
    let status = VerdictStatus(Make.verdict(.ready, task: "BIM model of the ground floor"))
    XCTAssertEqual(
      status.sentence(published: true),
      "Ready for BIM model of the ground floor. Details: spatial report in the HUB.")
  }

  func testTheNotificationText() {
    let status = VerdictStatus(Make.verdict(.limited))
    let packageId = LowercaseUUID()
    let notification = VerdictNotification(
      packageId: packageId, verdict: status, projectTitle: "424 West End Ave, Apt 4K", revision: 1)
    XCTAssertEqual(notification.title, "Verdict: Limited")
    XCTAssertEqual(
      notification.body, "424 West End Ave, Apt 4K \u{00B7} revision 1. Details: spatial report in the HUB.")
    XCTAssertEqual(notification.threadIdentifier, packageId.rawValue)
    XCTAssertEqual(notification.requestIdentifier, "verdict-\(status.verdictId.rawValue)")
    XCTAssertEqual(VerdictNotification.packageId(from: notification.userInfo), packageId)
    XCTAssertNil(VerdictNotification.packageId(from: ["packageId": "not-a-uuid"]))
  }
}
