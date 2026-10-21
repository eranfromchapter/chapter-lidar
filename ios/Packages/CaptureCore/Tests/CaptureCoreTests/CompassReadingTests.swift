import CaptureContract
import CaptureCore
import Foundation
import XCTest

/// The frame check (compass §3.4, `FrameCheckTests`), the pre-check arithmetic (§3.2) and the
/// evaluator bridge of CaptureCore.
final class FrameCheckTests: XCTestCase {
  private func surfaces(_ yaws: [Double]) -> [String: Double] {
    Dictionary(uniqueKeysWithValues: yaws.enumerated().map { ("wall-\($0.offset)", $0.element) })
  }

  func testIdenticalSurfacesGiveZero() {
    let live = surfaces([0, 90, 33, -45])
    let outcome = FrameCheck.frameYaw(live: live, final: live)
    XCTAssertEqual(outcome.frameYaw, 0, accuracy: 1e-9)
    XCTAssertEqual(outcome.matches, 4)
    XCTAssertTrue(outcome.consensus)
  }

  func testSurfacesTurnedTogetherGiveTheTurn() {
    let live = surfaces([0, 90, 10, -45, 60])
    let final = surfaces([37, 127, 47, -8, 97])
    XCTAssertEqual(FrameCheck.frameYaw(live: live, final: final).frameYaw, 37, accuracy: 1e-9)
  }

  func testAWallRefittedEndForEndStillAgrees() {
    let live = surfaces([0, 90, 10, -45, 60])
    // The last wall's axis was re-fitted the other way round: 60 + 37 + 180.
    let final = surfaces([37, 127, 47, -8, 277])
    let outcome = FrameCheck.frameYaw(live: live, final: final)
    XCTAssertEqual(outcome.frameYaw, 37, accuracy: 1e-9)
    XCTAssertTrue(outcome.consensus)
  }

  func testTwoMatchesUseTheD1Convention() {
    let outcome = FrameCheck.frameYaw(
      live: ["a": 0, "b": 90, "c": 4], final: ["a": 37, "b": 127, "z": 40])
    XCTAssertEqual(outcome.matches, 2)
    XCTAssertFalse(outcome.consensus)
    XCTAssertEqual(outcome.frameYaw, CompassMath.captureFrameYaw)
  }

  func testNoConsensusUsesTheD1Convention() {
    let live = surfaces([0, 0, 0, 0])
    let final = surfaces([5, 20, -30, 60])
    let outcome = FrameCheck.frameYaw(live: live, final: final, fallback: 1.5)
    XCTAssertFalse(outcome.consensus)
    XCTAssertEqual(outcome.frameYaw, 1.5)
  }

  func testSurfaceYawFromItsXAxis() {
    XCTAssertEqual(FrameCheck.yaw(columnX: 1, z: 0), 0, accuracy: 1e-9)
    XCTAssertEqual(FrameCheck.yaw(columnX: 0, z: -1), 90, accuracy: 1e-9)
    XCTAssertEqual(FrameCheck.yaw(columnX: 0, z: 1), -90, accuracy: 1e-9)
  }
}

final class PrecheckReadingTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_792_245_500)

  private func sample(_ seconds: Double, true trueHeading: Double = 212.4, accuracy: Double)
    -> CompassHeadingSample
  {
    CompassHeadingSample(
      date: start.addingTimeInterval(seconds), trueHeading: trueHeading, magneticHeading: 199.6,
      accuracy: accuracy)
  }

  func testTwoSecondsFromTheFirstValidUpdate() {
    var reading = PrecheckReading(startedAt: start)
    XCTAssertNil(reading.add(sample(0.5, accuracy: -1)))
    XCTAssertNil(reading.add(sample(1.0, accuracy: 6)))
    XCTAssertNil(reading.add(sample(2.0, accuracy: 7.2)))
    XCTAssertNil(reading.add(sample(2.9, true: 213.1, accuracy: 5)))
    XCTAssertNil(reading.poll(now: start.addingTimeInterval(2.99)))
    XCTAssertEqual(
      reading.add(sample(3.0, true: 250, accuracy: 30)),
      .result(heading: 213.1, accuracy: 8, source: .trueNorth, readAt: start.addingTimeInterval(3)),
      "the last valid heading inside the window, its largest accuracy rounded up")
  }

  func testWithoutTrueHeadingTheReadingIsMagnetic() {
    var reading = PrecheckReading(startedAt: start)
    _ = reading.add(sample(0.2, true: -1, accuracy: 12))
    XCTAssertEqual(
      reading.poll(now: start.addingTimeInterval(2.2)),
      .result(heading: 199.6, accuracy: 12, source: .magnetic, readAt: start.addingTimeInterval(2.2)))
  }

  func testNoValidAccuracyWithinFiveSecondsIsNotCalibrated() {
    var reading = PrecheckReading(startedAt: start)
    XCTAssertNil(reading.add(sample(1, accuracy: -1)))
    XCTAssertNil(reading.poll(now: start.addingTimeInterval(4.9)))
    XCTAssertEqual(reading.poll(now: start.addingTimeInterval(5)), .notCalibrated)
  }

  func testThePrecheckStateUsesTheSharedThresholds() {
    let at = start
    XCTAssertEqual(
      CompassPrecheckState.result(heading: 212.4, accuracy: 10, source: .trueNorth, readAt: at)
        .state, .verified(heading: 212.4, accuracy: 10))
    XCTAssertEqual(
      CompassPrecheckState.result(heading: 212.4, accuracy: 11, source: .trueNorth, readAt: at)
        .state, .approximate(heading: 212.4, accuracy: 11, source: .trueNorth))
    XCTAssertEqual(
      CompassPrecheckState.result(heading: 212.4, accuracy: 30, source: .magnetic, readAt: at)
        .state, .approximate(heading: 212.4, accuracy: 30, source: .magnetic))
    XCTAssertEqual(
      CompassPrecheckState.result(heading: 212.4, accuracy: 31, source: .trueNorth, readAt: at)
        .state, .notVerified(.inaccurate, accuracy: 31))
    XCTAssertNil(CompassPrecheckState.notCalibrated.state)
    XCTAssertNil(CompassPrecheckState.reading.state)
  }

  /// T-C5 of phone-capture through the contract evaluator.
  func testClassificationBoundaries() {
    func state(_ source: HeadingSource, _ accuracy: Int) -> CompassState {
      CompassState(reading: 100, accuracy: accuracy, source: source, at: start)
    }
    XCTAssertEqual(state(.trueNorth, 8).rank, 2)
    XCTAssertEqual(state(.trueNorth, 10).rank, 2)
    XCTAssertEqual(state(.trueNorth, 11).rank, 1)
    XCTAssertEqual(state(.trueNorth, 30).rank, 1)
    XCTAssertEqual(state(.trueNorth, 31), .notVerified(.inaccurate, accuracy: 31))
    XCTAssertEqual(state(.magnetic, 8).rank, 1)
    XCTAssertEqual(state(.magnetic, 31).rank, 0)
  }

  func testAResultOutsideTheScanIsRejected() {
    let captured = UTCTimestamp(start)
    let early = CompassResult.reading(
      heading: 10, accuracy: 5, source: .trueNorth,
      recordedAt: UTCTimestamp(start.addingTimeInterval(-7200)))
    XCTAssertEqual(
      early.state(capturedAt: captured, finishedAt: nil), .notVerified(.rejected, accuracy: nil))
    XCTAssertEqual(
      CompassResult.none(issue: nil).state(capturedAt: captured, finishedAt: nil),
      .notVerified(.noReading, accuracy: nil))
  }

  /// What Finish floor records: a reading or an issue, never neither (a capture record 1.1.0
  /// capture with neither is one scanned before the app read the compass).
  func testTheRecordedResultAlwaysHasAReadingOrAnIssue() {
    let reading = CompassResult.reading(
      heading: 212.4, accuracy: 8, source: .trueNorth, recordedAt: UTCTimestamp(start))
    XCTAssertEqual(reading.recorded, reading)
    for issue in HeadingIssue.allCases {
      XCTAssertEqual(CompassResult.none(issue: issue).recorded, .none(issue: issue))
    }
    XCTAssertEqual(
      CompassResult.none(issue: nil).recorded, .none(issue: .unavailable),
      "a session that read no compass had none to read")
    let recorded = CompassResult.none(issue: nil).recorded
    XCTAssertEqual(
      recorded.state(capturedAt: UTCTimestamp(start), finishedAt: nil),
      .notVerified(.unavailable, accuracy: nil))
  }
}

final class TrackingMonitorTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_792_245_500)

  private func update(
    _ monitor: inout TrackingMonitor, _ quality: TrackingQuality, at time: Double
  ) -> TrackingStatus? {
    monitor.update(quality, at: time, date: start.addingTimeInterval(time))
  }

  func testRelocalizingForOneSecondIsLost() {
    var monitor = TrackingMonitor()
    XCTAssertNil(update(&monitor, .normal, at: 0))
    XCTAssertNil(update(&monitor, .relocalizing, at: 1))
    XCTAssertFalse(monitor.isSampling, "sampling stops at once")
    XCTAssertNil(update(&monitor, .relocalizing, at: 1.75))
    XCTAssertEqual(update(&monitor, .relocalizing, at: 2), .lost(since: start.addingTimeInterval(1)))
  }

  func testNotAvailableForOneSecondIsLost() {
    var monitor = TrackingMonitor()
    XCTAssertNil(update(&monitor, .notAvailable, at: 0))
    XCTAssertEqual(update(&monitor, .notAvailable, at: 1), .lost(since: start))
  }

  func testOtherLimitedReasonsNeedThreeSeconds() {
    var monitor = TrackingMonitor()
    XCTAssertNil(update(&monitor, .limited, at: 0))
    XCTAssertNil(update(&monitor, .limited, at: 2.75))
    XCTAssertEqual(update(&monitor, .limited, at: 3), .lost(since: start))
  }

  func testAShortHiccupIsNotLost() {
    var monitor = TrackingMonitor()
    XCTAssertNil(update(&monitor, .relocalizing, at: 0))
    XCTAssertNil(update(&monitor, .normal, at: 0.5))
    XCTAssertTrue(monitor.isSampling)
    XCTAssertNil(update(&monitor, .relocalizing, at: 0.75))
    XCTAssertNil(update(&monitor, .relocalizing, at: 1.5))
    XCTAssertEqual(monitor.status, .normal)
  }

  func testNormalForHalfASecondClearsIt() {
    var monitor = TrackingMonitor()
    _ = update(&monitor, .notAvailable, at: 0)
    _ = update(&monitor, .notAvailable, at: 1)
    XCTAssertTrue(monitor.status.isLost)
    XCTAssertNil(update(&monitor, .normal, at: 2))
    XCTAssertTrue(monitor.isSampling)
    XCTAssertNil(update(&monitor, .limited, at: 2.25), "a not-normal frame restarts the 0.5 s")
    XCTAssertNil(update(&monitor, .normal, at: 2.5))
    XCTAssertNil(update(&monitor, .normal, at: 2.75))
    XCTAssertEqual(update(&monitor, .normal, at: 3), .normal)
  }
}
