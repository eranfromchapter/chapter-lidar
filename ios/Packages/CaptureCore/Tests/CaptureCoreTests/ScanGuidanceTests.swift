import CaptureContract
import CaptureCore
import XCTest

final class ScanGuidanceTests: XCTestCase {
  private func guide(_ counts: ScanCounts, mode: CaptureMode = .room, paused: Bool = false,
                     instruction: ScanInstruction = .normal) -> ScanGuidance {
    ScanGuidance.next(counts: counts, mode: mode, isPaused: paused, instruction: instruction)
  }

  func testStepsFollowWhatRoomPlanHasFound() {
    XCTAssertEqual(guide(ScanCounts()).step, 1)
    XCTAssertEqual(guide(ScanCounts(walls: 2)).step, 2)
    XCTAssertEqual(guide(ScanCounts(walls: 4)).step, 3)
    XCTAssertEqual(guide(ScanCounts(walls: 4, doors: 1)).step, 4)
  }

  func testWholeFloorPointsToTheNextRoom() {
    XCTAssertTrue(guide(ScanCounts(walls: 5, windows: 1), mode: .floor).detail.contains("next room"))
  }

  func testWarningsAndPauseOverrideTheStep() {
    let warning = guide(ScanCounts(walls: 2), instruction: .slowDown)
    XCTAssertNil(warning.step)
    XCTAssertTrue(warning.isWarning)
    XCTAssertEqual(warning.title, "Slow down")
    let paused = guide(ScanCounts(walls: 2), paused: true, instruction: .slowDown)
    XCTAssertEqual(paused.title, "Paused")
  }

  func testExteriorHasItsOwnDirection() {
    XCTAssertEqual(guide(ScanCounts(), mode: .exterior).title, "Walk the outside slowly")
  }
}
