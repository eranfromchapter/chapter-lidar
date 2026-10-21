#if canImport(UIKit) && os(iOS)
  import XCTest

  @testable import ChapterUI

  final class CompassGlyphTests: XCTestCase {
    /// Heading 359° → 1° between two 4 Hz ticks: the callers pass −359 and then −1. The glyph
    /// turns 2° (counterclockwise: the phone turned 2° clockwise), not 358° the other way.
    func testCrossingNorthTurnsTwoDegreesNotAFullTurn() {
      XCTAssertEqual(CompassRotation.shortestTurn(from: -359, to: -1), -2)
      XCTAssertEqual(CompassRotation.continuing(from: -359, to: -1), -361)
      // And back: heading 1° → 359°.
      XCTAssertEqual(CompassRotation.shortestTurn(from: -1, to: -359), 2)
      XCTAssertEqual(CompassRotation.continuing(from: -1, to: -359), 1)
      // Callers that pass headings in 0..<360 or in −180...180 get the same turns.
      XCTAssertEqual(CompassRotation.shortestTurn(from: 1, to: -1), -2)
      XCTAssertEqual(CompassRotation.shortestTurn(from: 179, to: -179), 2)
    }

    /// A heading that sweeps through north and back, tick by tick: every drawn angle equals
    /// −heading (modulo 360), and no step turns further than the heading did.
    func testSweepThroughNorthStaysContinuous() {
      let headings: [Double] = [350, 355, 359, 1, 5, 12, 3, 358, 340]
      var drawn = -headings[0]
      for (previous, heading) in zip(headings, headings.dropFirst()) {
        let next = CompassRotation.continuing(from: drawn, to: -heading)
        let headingChange = abs(CompassRotation.shortestTurn(from: previous, to: heading))
        XCTAssertEqual(
          abs(next - drawn), headingChange, accuracy: 1e-9, "\(previous)° → \(heading)°")
        XCTAssertEqual(
          (next + heading).truncatingRemainder(dividingBy: 360), 0, accuracy: 1e-9,
          "drawn \(next) for heading \(heading)°")
        drawn = next
      }
      // 350 → 355 → 359 → 1 → 5 → 12 → 3 → 358 → 340: −350, −355, −359, −361, −365, −372, −363,
      // −358, −340.
      XCTAssertEqual(drawn, -340, accuracy: 1e-9)
    }

    /// Turning round and round keeps counting: ten clockwise turns of the phone in 30° steps
    /// draw −3600, never a jump back.
    func testFullTurnsKeepCounting() {
      var drawn = 0.0
      for step in 1...120 {
        let heading = Double(step * 30).truncatingRemainder(dividingBy: 360)
        let next = CompassRotation.continuing(from: drawn, to: -heading)
        XCTAssertEqual(next - drawn, -30, accuracy: 1e-9)
        drawn = next
      }
      XCTAssertEqual(drawn, -3600, accuracy: 1e-9)
    }

    func testHalfATurnGoesClockwise() {
      XCTAssertEqual(CompassRotation.shortestTurn(from: 0, to: 180), 180)
      XCTAssertEqual(CompassRotation.shortestTurn(from: 0, to: -180), 180)
      XCTAssertEqual(CompassRotation.shortestTurn(from: 10, to: 550), 180)
      XCTAssertEqual(CompassRotation.shortestTurn(from: 0, to: 181), -179)
    }

    /// An angle the glyph has arrived at stays exactly where it is, so the glyph's
    /// remembered angle settles after one update.
    func testEqualAnglesTurnExactlyZero() {
      XCTAssertEqual(CompassRotation.shortestTurn(from: -360.3, to: -0.3), 0)
      XCTAssertEqual(CompassRotation.continuing(from: -360.3, to: -0.3), -360.3)
      XCTAssertEqual(CompassRotation.shortestTurn(from: 725, to: 5), 0)
      XCTAssertEqual(CompassRotation.shortestTurn(from: -32, to: -32), 0)
      let arrived = CompassRotation.continuing(from: 1000.1, to: -12.7)
      XCTAssertEqual(CompassRotation.continuing(from: arrived, to: -12.7), arrived)
    }

    func testValuesThatAreNotNumbersDoNotMoveTheGlyph() {
      XCTAssertEqual(CompassRotation.continuing(from: 10, to: .nan), 10)
      XCTAssertEqual(CompassRotation.continuing(from: 10, to: .infinity), 10)
      XCTAssertEqual(CompassRotation.continuing(from: .nan, to: 20), 20)
      XCTAssertEqual(CompassRotation.continuing(from: .nan, to: .nan), 0)
    }

    /// compass §5.1 draws the not-verified ring 2 / 2; critique R-20 changes only the
    /// approximate ring, to the north-arrow v2 vector's 1.6 / 1.6.
    func testRingDashPerState() {
      XCTAssertEqual(CompassGlyph.ringDash(.verified), [])
      XCTAssertEqual(CompassGlyph.ringDash(.approximate), [1.6, 1.6])
      XCTAssertEqual(CompassGlyph.ringDash(.notVerified), [2, 2])
    }
  }
#endif
