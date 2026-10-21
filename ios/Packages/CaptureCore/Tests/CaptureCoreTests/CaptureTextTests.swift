import CaptureContract
import CaptureCore
import Foundation
import XCTest

/// T-T1 (`CaptureTextTests`) and T-T2 (`DeviceNamesTests`) of phone-capture §10.1.
final class CaptureTextTests: XCTestCase {
  private let newYork = TimeZone(identifier: "America/New_York")!
  /// Oct 21, 2026 14:40:03 in New York.
  private let now = Date(timeIntervalSince1970: 1_792_608_003)

  func testRelativeAge() {
    XCTAssertEqual(CaptureText.relativeAge(from: now.addingTimeInterval(-59), now: now), "just now")
    XCTAssertEqual(
      CaptureText.relativeAge(from: now.addingTimeInterval(-120), now: now), "2 min ago",
      "never \"2 min.\"")
    XCTAssertEqual(
      CaptureText.relativeAge(from: now.addingTimeInterval(-3 * 3600 - 5), now: now), "3 h ago")
    XCTAssertEqual(
      CaptureText.relativeAge(from: now.addingTimeInterval(-86_400), now: now, timeZone: newYork),
      "on Oct 20")
  }

  func testDates() {
    let sealed = Date(timeIntervalSince1970: 1_737_820_800)  // Jan 25, 2025 16:00 UTC
    XCTAssertEqual(CaptureText.sealedDate(sealed, timeZone: newYork), "Jan 25, 2025")
    let saved = Date(timeIntervalSince1970: 1_792_519_920)  // Oct 20, 2026 14:12 New York
    XCTAssertEqual(CaptureText.offlineStamp(saved, timeZone: newYork), "Oct 20, 14:12")
  }

  func testCapturedWhen() {
    func when(_ seconds: Double) -> String {
      CaptureText.capturedWhen(
        visitedAt: now.addingTimeInterval(seconds), now: now, timeZone: newYork)
    }
    XCTAssertEqual(when(-3600), "today")
    XCTAssertEqual(when(-86_400), "yesterday")
    XCTAssertEqual(when(-2 * 86_400), "Oct 19")
    XCTAssertEqual(when(-366 * 86_400), "Oct 20, 2025")
  }

  func testCountsAndTimes() {
    XCTAssertEqual(CaptureText.plural(1, "floor", "floors"), "1 floor")
    XCTAssertEqual(CaptureText.plural(2, "floor", "floors"), "2 floors")
    XCTAssertEqual(CaptureText.elapsed(402), "06:42")
    XCTAssertEqual(CaptureText.elapsed(4325), "72:05", "minutes may pass 59")
    XCTAssertEqual(CaptureText.spokenElapsed(402), "Elapsed 6 minutes 42 seconds")
    XCTAssertEqual(CaptureText.spokenElapsed(60), "Elapsed 1 minute")
    XCTAssertEqual(CaptureText.spokenElapsed(1), "Elapsed 1 second")
    XCTAssertEqual(CompassText.heading(360), "0", "360 shows as 0")
  }

  func testWords() {
    XCTAssertEqual(CaptureText.modeTitle(.room), "One room")
    XCTAssertEqual(CaptureText.modeTitle(.floor), "Whole floor")
    XCTAssertEqual(CaptureText.modeTitle(.exterior), "Exterior")
    XCTAssertEqual(CaptureText.capitalizedFirst("locked"), "Locked")
    XCTAssertEqual(CaptureText.capitalizedFirst(""), "")
    XCTAssertEqual(CaptureText.withoutFinalPeriod("Choose the HUB project."), "Choose the HUB project")
  }

  func testDeviceNames() {
    XCTAssertEqual(DeviceNames.marketingName(for: "iPhone17,1"), "iPhone 16 Pro")
    XCTAssertEqual(DeviceNames.marketingName(for: "iPhone18,2"), "iPhone 17 Pro Max")
    XCTAssertEqual(DeviceNames.marketingName(for: "iPhone13,3"), "iPhone 12 Pro")
    XCTAssertEqual(DeviceNames.marketingName(for: "iPad16,5"), "iPad Pro 13-inch (M4)")
    XCTAssertNil(DeviceNames.marketingName(for: "iPhone99,9"), "unknown: the screen shows the id")
    XCTAssertEqual(DeviceNames.table.count, 36)
    XCTAssertTrue(DeviceNames.table.values.allSatisfy { $0.hasPrefix("iPhone") || $0.hasPrefix("iPad Pro") })
  }
}
