import CaptureContract
import CaptureCore
import Foundation
import XCTest

/// Every compass string of the phone's capture screens (compass §5.1–5.2, critique R-20).
final class CompassPhoneTextTests: XCTestCase {
  private let readAt = Date(timeIntervalSince1970: 1_792_245_500)

  private func row(
    heading: Double = 212.4, accuracy: Int, source: HeadingSource = .trueNorth, after seconds: Double
  ) -> CompassPhoneText.Row {
    CompassPhoneText.row(
      .result(heading: heading, accuracy: accuracy, source: source, readAt: readAt),
      now: readAt.addingTimeInterval(seconds))
  }

  func testReading() {
    let row = CompassPhoneText.row(.reading, now: readAt)
    XCTAssertEqual(row.line1, "Compass")
    XCTAssertEqual(row.line2, "Reading the compass…")
    XCTAssertEqual(row.status, .none)
    XCTAssertEqual(row.glyph, .none)
    XCTAssertTrue(row.showsReadAgain)
    XCTAssertFalse(row.readAgainEnabled, "disabled while reading")
  }

  func testVerifiedAsDrawn() {
    let verified = row(accuracy: 8, after: 12)
    XCTAssertEqual(verified.line1, "North 212° true · ±8°")
    XCTAssertEqual(verified.line2, "Verified · read 12 s ago")
    XCTAssertEqual(verified.status, .verified)
    XCTAssertEqual(verified.glyph, .verified)
    XCTAssertEqual(verified.rotation, -212.4, accuracy: 1e-9)
    XCTAssertTrue(verified.readAgainEnabled)
    XCTAssertEqual(
      verified.accessibilityLabel,
      "Compass. North 212 degrees true, plus or minus 8 degrees. Verified, read 12 seconds ago.")
    XCTAssertEqual(row(accuracy: 8, after: 3).line2, "Verified · read just now")
  }

  func testApproximate() {
    let magnetic = row(accuracy: 12, source: .magnetic, after: 90)
    XCTAssertEqual(magnetic.line1, "North 212° magnetic · ±12°")
    XCTAssertEqual(magnetic.line2, "Approximate · read 1 min ago")
    XCTAssertEqual(magnetic.status, .limited)
    XCTAssertEqual(magnetic.glyph, .approximate)
    XCTAssertEqual(row(accuracy: 18, after: 30).line1, "North 212° true · ±18°")
    XCTAssertEqual(row(accuracy: 18, after: 30).line2, "Approximate · read 30 s ago")
  }

  func testInaccurate() {
    let inaccurate = row(heading: 359.6, accuracy: 42, after: 4000)
    XCTAssertEqual(inaccurate.line1, "North 0° true · ±42°", "359.6 rounds to 0, never 360")
    XCTAssertEqual(inaccurate.line2, "Not verified · accuracy too low · read over an hour ago")
    XCTAssertEqual(inaccurate.status, .limited, "▲, never ■")
    XCTAssertEqual(inaccurate.glyph, .none, "no arrow, ever")
  }

  func testNotCalibratedAndUnavailable() {
    let notCalibrated = CompassPhoneText.row(.notCalibrated, now: readAt)
    XCTAssertEqual(notCalibrated.line1, "No compass reading")
    XCTAssertEqual(
      notCalibrated.line2, "Not verified · move the phone in a figure 8, then read again")
    XCTAssertEqual(notCalibrated.status, .limited)
    XCTAssertTrue(notCalibrated.showsReadAgain)

    let unavailable = CompassPhoneText.row(.unavailable, now: readAt)
    XCTAssertEqual(unavailable.line1, "No compass on this phone")
    XCTAssertEqual(unavailable.line2, "Not verified · the plans will say so")
    XCTAssertFalse(unavailable.showsReadAgain, "hidden when the phone has no compass")
  }

  func testChip() {
    XCTAssertEqual(CompassPhoneText.chip(.reading).text, "N · reading…")
    XCTAssertEqual(CompassPhoneText.chip(.reading).glyph, .none)
    XCTAssertEqual(CompassPhoneText.chip(.notVerified).text, "N · not verified")
    XCTAssertEqual(CompassPhoneText.chip(.notVerified).accessibilityLabel, "Compass not verified")

    let verified = CompassPhoneText.chip(
      .result(.verified(heading: 212.4, accuracy: 8), cameraBearing: 300))
    XCTAssertEqual(verified.text, "N · true · ±8°")
    XCTAssertEqual(verified.glyph, .verified)
    XCTAssertEqual(verified.rotation, -300)
    XCTAssertEqual(
      verified.accessibilityLabel, "Compass verified, true north, plus or minus 8 degrees")

    let approximateTrue = CompassPhoneText.chip(
      .result(.approximate(heading: 1, accuracy: 18, source: .trueNorth), cameraBearing: nil))
    XCTAssertEqual(approximateTrue.text, "N · approx. · ±18°")
    XCTAssertEqual(approximateTrue.glyph, .approximate)
    XCTAssertNil(approximateTrue.rotation, "the chip keeps its last angle")

    let magnetic = CompassPhoneText.chip(
      .result(.approximate(heading: 1, accuracy: 12, source: .magnetic), cameraBearing: 10))
    XCTAssertEqual(magnetic.text, "N · magnetic · ±12°")
    XCTAssertEqual(
      magnetic.accessibilityLabel, "Compass approximate, magnetic north, plus or minus 12 degrees")
  }

  func testNoCompassTextUsesForbiddenCharacters() {
    let states: [CompassPrecheckState] = [
      .reading, .notCalibrated, .unavailable,
      .result(heading: 212.4, accuracy: 8, source: .trueNorth, readAt: readAt),
      .result(heading: 212.4, accuracy: 42, source: .magnetic, readAt: readAt),
    ]
    let texts =
      states.flatMap { state -> [String] in
        let row = CompassPhoneText.row(state, now: readAt)
        return [row.line1, row.line2]
      } + [CompassPhoneText.footnote, CompassPhoneText.locationOffNote]
    for text in texts {
      for forbidden in ["\u{2212}", "\u{2032}", "\u{2033}", "\u{2248}"] {
        XCTAssertFalse(text.contains(forbidden), text)
      }
    }
  }

  func testSpokenAgo() {
    XCTAssertEqual(CompassPhoneText.spokenAgo(seconds: 4), "just now")
    XCTAssertEqual(CompassPhoneText.spokenAgo(seconds: 12), "12 seconds ago")
    XCTAssertEqual(CompassPhoneText.spokenAgo(seconds: 61), "1 minute ago")
    XCTAssertEqual(CompassPhoneText.spokenAgo(seconds: 600), "10 minutes ago")
    XCTAssertEqual(CompassPhoneText.spokenAgo(seconds: 3600), "over an hour ago")
  }
}

@MainActor
final class FakeCompassTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_792_245_500)

  func testScripts() async {
    let clock: @Sendable () -> Date = { [now] in now }
    let verified = FakeCompass(.verified, clock: clock)
    let verifiedPrecheck = await verified.precheck()
    XCTAssertEqual(
      verifiedPrecheck, .result(heading: 212.4, accuracy: 8, source: .trueNorth, readAt: now))
    XCTAssertEqual(verified.precheckCount, 1)
    XCTAssertEqual(verified.cameraSample()?.azimuth, 85)
    XCTAssertEqual(verified.cameraSample().map { CompassMath.cardinal($0.azimuth) }, .east)
    XCTAssertEqual(
      verified.replayCompass.reading,
      ReplayCompass.Reading(heading: 212.4, accuracy: 8, source: .trueNorth))

    let approximate = FakeCompass(.approximate, clock: clock)
    let approximatePrecheck = await approximate.precheck()
    XCTAssertEqual(
      approximatePrecheck, .result(heading: 212.4, accuracy: 12, source: .magnetic, readAt: now))
    XCTAssertEqual(approximate.cameraSample()?.source, .magnetic)

    let none = FakeCompass(.none, clock: clock)
    let nonePrecheck = await none.precheck()
    XCTAssertEqual(nonePrecheck, .notCalibrated)
    XCTAssertNil(none.cameraSample())
    XCTAssertNil(none.replayCompass.reading)

    let noCompass = FakeCompass(.verified, isAvailable: false)
    let unavailable = await noCompass.precheck()
    XCTAssertEqual(unavailable, .unavailable)
  }

  func testLaunchArgument() {
    XCTAssertEqual(FakeCompass(launchArgument: "approximate")?.script, .approximate)
    XCTAssertNil(FakeCompass(launchArgument: "sideways"))
  }

  func testAuthorizationAndSettings() {
    let compass = FakeCompass(.verified, authorization: .notDetermined)
    compass.requestAuthorization()
    XCTAssertEqual(compass.authorization, .authorized)
    compass.openSettings()
    XCTAssertEqual(compass.settingsOpened, 1)
    compass.startCameraHeading()
    XCTAssertTrue(compass.isCameraHeadingRunning)
    compass.stopCameraHeading()
    XCTAssertFalse(compass.isCameraHeadingRunning)
  }

  func testReplayResultsClassifyAsScripted() {
    let start = now
    let captured = UTCTimestamp(start)
    let finished = UTCTimestamp(start.addingTimeInterval(400))
    XCTAssertEqual(
      FakeCompass(.verified).replayCompass.result(startedAt: start)
        .state(capturedAt: captured, finishedAt: finished),
      .verified(heading: 212.4, accuracy: 8))
    XCTAssertEqual(
      FakeCompass(.approximate).replayCompass.result(startedAt: start)
        .state(capturedAt: captured, finishedAt: finished),
      .approximate(heading: 212.4, accuracy: 12, source: .magnetic))
    XCTAssertEqual(
      FakeCompass(.none).replayCompass.result(startedAt: start)
        .state(capturedAt: captured, finishedAt: finished),
      .notVerified(.noReading, accuracy: nil))
  }
}
