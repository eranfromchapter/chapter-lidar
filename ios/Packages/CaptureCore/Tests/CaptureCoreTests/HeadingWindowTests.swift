import CaptureContract
import CaptureCore
import Foundation
import XCTest

/// The scan-start reading (compass §3.3, test plan §13.1 `HeadingWindowTests`).
final class HeadingWindowTests: XCTestCase {
  private func feed(_ pairs: [CompassPair], into window: inout HeadingWindow) {
    for pair in pairs { window.add(pair) }
  }

  func testSyntheticPosesGiveTheConstructedWorldHeading() {
    for yaw in [0.0, 40, 135, 271] {
      for pitch in [0.0, 30, -60] {
        let camera = CompassPoses.worldFromCamera(yaw: yaw, pitch: pitch)
        let motion = CompassPoses.motion(worldHeading: 212.4, worldFromCamera: camera, timestamp: 0)
        let pair = CompassPair(
          timestamp: 0, runningTime: 0, date: CompassPoses.start, trackingNormal: true,
          worldFromCamera: camera, motion: motion,
          heading: CompassHeadingSample(
            date: CompassPoses.start, trueHeading: 1, magneticHeading: 1, accuracy: 5))
        XCTAssertEqual(pair.worldHeading, 212.4, accuracy: 0.01, "yaw \(yaw) pitch \(pitch)")
        XCTAssertNil(pair.dropReason, "yaw \(yaw) pitch \(pitch)")
      }
    }
  }

  func testEightConsistentPairsAreAccepted() throws {
    var window = HeadingWindow()
    feed(CompassPoses.window(from: 0), into: &window)
    let best = try XCTUnwrap(window.best)
    XCTAssertEqual(best.worldHeading, 212.4, accuracy: 0.01)
    XCTAssertEqual(best.accuracy, 8)
    XCTAssertEqual(best.source, .trueNorth)
    XCTAssertEqual(best.recordedAt, UTCTimestamp(CompassPoses.start.addingTimeInterval(1.75)))
    XCTAssertEqual(best.state, .verified(heading: 212.4, accuracy: 8), "stored to 0.1°")
    XCTAssertTrue(window.isDone, "a verified window ends the attempt")
    XCTAssertEqual(window.diagnostics.windowsAccepted, 1)
    XCTAssertEqual(
      window.result(),
      .reading(
        heading: 212.4, accuracy: 8, source: .trueNorth,
        recordedAt: UTCTimestamp(CompassPoses.start.addingTimeInterval(1.75))))
  }

  func testSevenPairsAreNotAWindow() {
    var window = HeadingWindow()
    feed(Array(CompassPoses.window(from: 0).prefix(7)), into: &window)
    XCTAssertNil(window.best)
    XCTAssertEqual(
      window.result(), .none(issue: .rejected),
      "samples came, but too few in a row to be matched to the scan")
  }

  func testASpreadAboveTheAccuracyIsRejected() {
    // Spread 6° with accuracy 4: limit max(5, 4) = 5.
    var window = HeadingWindow()
    let headings = [206.0, 212, 212, 212, 212, 212, 212, 218]
    feed(CompassPoses.window(from: 0, compassHeadings: headings, accuracy: 4), into: &window)
    XCTAssertNil(window.best)
    XCTAssertEqual(window.diagnostics.windowsRejected, 1)
    XCTAssertEqual(window.result(), .none(issue: .rejected))
  }

  func testASpreadWithinAWideAccuracyIsAccepted() throws {
    // Spread 6° with accuracy 12: limit 12.
    var window = HeadingWindow()
    let headings = [206.0, 212, 212, 212, 212, 212, 212, 218]
    feed(CompassPoses.window(from: 0, compassHeadings: headings, accuracy: 12), into: &window)
    let best = try XCTUnwrap(window.best)
    XCTAssertEqual(best.accuracy, 12)
    XCTAssertEqual(best.state.rank, 1, "true ±12 is approximate")
  }

  func testPairsWhileTurningAreDropped() {
    var window = HeadingWindow()
    for index in 0..<16 {
      window.add(CompassPoses.pair(at: Double(index) * 0.25, rotationRate: 0.5))
    }
    XCTAssertNil(window.best)
    XCTAssertEqual(window.diagnostics.dropped[.turning], 16)
    XCTAssertEqual(window.result(), .none(issue: .rejected))
  }

  func testPairsNeverTrackedNormallyAreRejected() {
    var window = HeadingWindow()
    for index in 0..<40 {
      window.add(CompassPoses.pair(at: Double(index) * 0.25, trackingNormal: false))
    }
    XCTAssertEqual(window.diagnostics.dropped[.trackingNotNormal], 40)
    XCTAssertEqual(window.result(), .none(issue: .rejected))
  }

  func testEachGateDropsThePair() {
    XCTAssertEqual(CompassPoses.pair(at: 0, trackingNormal: false).dropReason, .trackingNotNormal)
    XCTAssertEqual(CompassPoses.pair(at: 0, rotationRate: 0.35).dropReason, .turning)
    XCTAssertEqual(CompassPoses.pair(at: 0, accuracy: -1).dropReason, .noHeading)
    XCTAssertEqual(CompassPoses.pair(at: 0, headingAge: 2.5).dropReason, .noHeading)
    XCTAssertEqual(CompassPoses.pair(at: 0, calibrated: false).dropReason, .uncalibrated)
    XCTAssertNil(CompassPoses.pair(at: 0, rotationRate: 0.34).dropReason)
  }

  func testATransposedAttitudeFailsTheGravityCheck() {
    var pair = CompassPoses.pair(at: 0, cameraYaw: 40)
    pair.motion.attitude = pair.motion.attitude.transposed
    XCTAssertEqual(pair.dropReason, .gravity)
  }

  func testAMostlyFailingGravityCheckFlagsTheConventions() {
    var window = HeadingWindow()
    for index in 0..<44 {
      var pair = CompassPoses.pair(at: Double(index) * 0.25)
      pair.motion.attitude = pair.motion.attitude.transposed
      window.add(pair)
    }
    XCTAssertTrue(window.diagnostics.conventionMismatch)
    XCTAssertEqual(window.diagnostics.dropped[.gravity], 44)

    var healthy = HeadingWindow()
    for index in 0..<44 {
      healthy.add(CompassPoses.pair(at: Double(index) * 0.25, rotationRate: 0.5))
    }
    XCTAssertFalse(healthy.diagnostics.conventionMismatch, "turning pairs say nothing")
  }

  func testAnInvalidPairRestartsTheWindow() {
    var window = HeadingWindow()
    var pairs = CompassPoses.window(from: 0)
    pairs[4] = CompassPoses.pair(at: 1.0, trackingNormal: false)
    feed(pairs, into: &window)
    XCTAssertNil(window.best, "only 3 valid pairs after the invalid one")
    feed(CompassPoses.window(from: 2.25), into: &window)
    XCTAssertNotNil(window.best)
  }

  func testAGapOverOneSecondRestartsTheWindow() {
    var window = HeadingWindow()
    let first = Array(CompassPoses.window(from: 0).prefix(4))
    let second = Array(CompassPoses.window(from: 2.5).prefix(4))
    feed(first + second, into: &window)
    XCTAssertNil(window.best)
  }

  func testInvalidAccuracyThroughoutIsNotCalibrated() {
    var window = HeadingWindow()
    for index in 0..<40 {
      window.add(CompassPoses.pair(at: Double(index) * 0.25, accuracy: -1))
    }
    XCTAssertEqual(window.result(), .none(issue: .notCalibrated))
  }

  func testAnUncalibratedFieldThroughoutIsNotCalibrated() {
    var window = HeadingWindow()
    for index in 0..<40 {
      window.add(CompassPoses.pair(at: Double(index) * 0.25, calibrated: false))
    }
    XCTAssertEqual(window.result(), .none(issue: .notCalibrated))
  }

  func testUnavailableWinsOverEveryOtherIssue() {
    var window = HeadingWindow()
    window.markUnavailable()
    for index in 0..<40 {
      window.add(CompassPoses.pair(at: Double(index) * 0.25, accuracy: -1))
    }
    XCTAssertEqual(window.result(), .none(issue: .unavailable))
  }

  func testARejectedWindowIsNotHiddenByLaterUncalibratedPairs() {
    var window = HeadingWindow()
    let headings = [200.0, 212, 212, 212, 212, 212, 212, 224]
    feed(CompassPoses.window(from: 0, compassHeadings: headings, accuracy: 4), into: &window)
    for index in 0..<8 {
      window.add(CompassPoses.pair(at: 3 + Double(index) * 0.25, calibrated: false))
    }
    XCTAssertEqual(window.diagnostics.windowsRejected, 1)
    XCTAssertEqual(window.result(), .none(issue: .rejected), "the field was calibrated at first")
  }

  func testNoPairedSampleIsUnavailable() {
    var window = HeadingWindow()
    window.addUnpaired()
    XCTAssertEqual(
      window.result(), .none(issue: .unavailable), "Core Motion delivered nothing near a frame")
    XCTAssertEqual(window.diagnostics.unpaired, 1)
  }

  func testAWindowNeverFedIsUnavailable() {
    // LiveCaptureSession without a compass service feeds nothing.
    XCTAssertEqual(HeadingWindow().result(), .none(issue: .unavailable))
  }

  /// A capture record 1.1.0 capture with neither a reading nor an issue is one scanned before the
  /// app read the compass (station orientation.compass): every result names one or the other.
  func testEveryResultHasAReadingOrAnIssue() {
    var scenarios: [String: HeadingWindow] = ["never fed": HeadingWindow()]
    func scenario(_ name: String, _ pairs: [CompassPair]) {
      var window = HeadingWindow()
      for pair in pairs { window.add(pair) }
      scenarios[name] = window
    }
    scenario("accepted", CompassPoses.window(from: 0))
    scenario("seven pairs", Array(CompassPoses.window(from: 0).prefix(7)))
    scenario(
      "turning", (0..<16).map { CompassPoses.pair(at: Double($0) * 0.25, rotationRate: 0.5) })
    scenario(
      "not calibrated", (0..<16).map { CompassPoses.pair(at: Double($0) * 0.25, accuracy: -1) })
    scenario(
      "inconsistent",
      CompassPoses.window(
        from: 0, compassHeadings: [206.0, 212, 212, 212, 212, 212, 212, 218], accuracy: 4))
    for (name, window) in scenarios {
      switch window.result() {
      case .reading: XCTAssertEqual(name, "accepted")
      case .none(let issue): XCTAssertNotNil(issue, name)
      }
    }
  }

  func testABetterWindowLaterWins() throws {
    // Approximate (true ±18) at 5 s, then verified (±6) at 50 s.
    var window = HeadingWindow()
    feed(CompassPoses.window(from: 5, accuracy: 18), into: &window)
    XCTAssertEqual(window.best?.state.rank, 1)
    XCTAssertFalse(window.isDone)
    feed(CompassPoses.window(from: 50, accuracy: 6), into: &window)
    let best = try XCTUnwrap(window.best)
    XCTAssertEqual(best.accuracy, 6)
    XCTAssertEqual(best.state.rank, 2)
    XCTAssertEqual(best.recordedAt, UTCTimestamp(CompassPoses.start.addingTimeInterval(51.75)))
  }

  func testAWorseWindowLaterDoesNotReplaceTheBest() throws {
    var window = HeadingWindow()
    feed(CompassPoses.window(from: 0, accuracy: 15), into: &window)
    feed(CompassPoses.window(from: 3, accuracy: 25), into: &window)
    XCTAssertEqual(try XCTUnwrap(window.best).accuracy, 15)
    feed(CompassPoses.window(from: 6, accuracy: 15), into: &window)
    XCTAssertEqual(
      try XCTUnwrap(window.best).recordedAt,
      UTCTimestamp(CompassPoses.start.addingTimeInterval(7.75)), "the later of two equals wins")
  }

  func testNothingIsTakenAfterAVerifiedWindow() throws {
    var window = HeadingWindow()
    feed(CompassPoses.window(from: 0, accuracy: 9), into: &window)
    feed(CompassPoses.window(from: 3, accuracy: 3), into: &window)
    XCTAssertEqual(try XCTUnwrap(window.best).accuracy, 9)
    XCTAssertEqual(window.diagnostics.windowsAccepted, 1)
  }

  func testTheStartPeriodCountsRunningTimeOnly() {
    var window = HeadingWindow()
    // 60 s of wall clock, but the scan was paused for 40 of them: 20 s of running time.
    let pair = CompassPoses.pair(at: 60, accuracy: -1, runningTime: 20)
    window.add(pair)
    XCTAssertTrue(window.isInStartPeriod)
    XCTAssertEqual(window.liveState(worldFromCamera: nil), .reading)
    XCTAssertFalse(window.advance(runningTime: 29.9))
    XCTAssertTrue(window.advance(runningTime: 30), "the start period ends once")
    XCTAssertFalse(window.advance(runningTime: 31))
    XCTAssertEqual(window.liveState(worldFromCamera: nil), .notVerified)
  }

  func testAttemptsGoOnSilentlyAfterTheStartPeriod() throws {
    var window = HeadingWindow()
    window.advance(runningTime: 45)
    XCTAssertEqual(window.liveState(worldFromCamera: nil), .notVerified)
    feed(CompassPoses.window(from: 45), into: &window)
    XCTAssertEqual(window.best?.state.rank, 2)
    guard case .result(let state, let bearing) = window.liveState(
      worldFromCamera: CompassPoses.worldFromCamera(yaw: 90))
    else { return XCTFail("a usable reading shows on the chip") }
    XCTAssertTrue(state.isUsable)
    XCTAssertEqual(try XCTUnwrap(bearing), CompassMath.normalized(212.4 + 90), accuracy: 0.01)
  }

  func testTheCameraBearingIsNilWhenTheCameraPointsUp() {
    var window = HeadingWindow()
    feed(CompassPoses.window(from: 0), into: &window)
    let state = window.liveState(worldFromCamera: CompassPoses.worldFromCamera(yaw: 0, pitch: 80))
    XCTAssertEqual(state.cameraBearing, nil)
    XCTAssertNotNil(state.state)
  }

  func testAnApproximateWindowShowsDuringTheStartPeriodAndANotVerifiedOneDoesNot() {
    var approximate = HeadingWindow()
    feed(CompassPoses.window(from: 0, accuracy: 20), into: &approximate)
    XCTAssertNotNil(approximate.liveState(worldFromCamera: nil).state)

    var inaccurate = HeadingWindow()
    feed(CompassPoses.window(from: 0, accuracy: 40), into: &inaccurate)
    XCTAssertEqual(inaccurate.best?.state.rank, 0)
    XCTAssertEqual(inaccurate.liveState(worldFromCamera: nil), .reading)
    XCTAssertEqual(
      inaccurate.result().state(capturedAt: UTCTimestamp(CompassPoses.start), finishedAt: nil),
      .notVerified(.inaccurate, accuracy: 40))
  }

  func testTheMagneticFrameGivesAMagneticReading() throws {
    var window = HeadingWindow()
    feed(CompassPoses.window(from: 0, accuracy: 6, source: .magnetic), into: &window)
    let best = try XCTUnwrap(window.best)
    XCTAssertEqual(best.source, .magnetic)
    XCTAssertEqual(best.state, .approximate(heading: 212.4, accuracy: 6, source: .magnetic))
    XCTAssertFalse(window.isDone, "magnetic is never verified")
  }

  func testAChangeOfNorthRestartsTheWindow() {
    var window = HeadingWindow()
    let trueHalf = Array(CompassPoses.window(from: 0).prefix(4))
    let magneticHalf = Array(CompassPoses.window(from: 1, source: .magnetic).prefix(4))
    feed(trueHalf + magneticHalf, into: &window)
    XCTAssertNil(window.best)
  }

  func testTheFrameYawTurnsTheStoredHeading() {
    var window = HeadingWindow()
    feed(CompassPoses.window(from: 0), into: &window)
    guard case .reading(let heading, _, _, _) = window.result(frameYaw: 150) else {
      return XCTFail("a reading")
    }
    XCTAssertEqual(heading, 2.4, accuracy: 0.001)
  }

  func testAMeanAcrossNorth() throws {
    var window = HeadingWindow()
    let headings = [358.0, 359, 0, 1, 2, 359, 0, 1]
    feed(CompassPoses.window(from: 0, compassHeadings: headings), into: &window)
    let best = try XCTUnwrap(window.best)
    XCTAssertEqual(CompassMath.wrap180(best.worldHeading), 0, accuracy: 0.01)
    XCTAssertEqual(best.spread, 2, accuracy: 0.01)
  }
}
