import FieldRules
import XCTest

/// AC4 (phone-field §8): numbers read `7,520 mm`, `2,690–2,740 mm` and `36' 10.5"`, ASCII marks
/// and comma thousands, locale independent, rounded half away from zero without drift.
final class LengthFormatterV2Tests: XCTestCase {
  func testMillimetresHaveCommaThousandsAndWholeMillimetres() {
    XCTAssertEqual(LengthFormatter.millimetres(7520), "7,520 mm")
    XCTAssertEqual(LengthFormatter.millimetres(3060.7), "3,061 mm")
    XCTAssertEqual(LengthFormatter.millimetres(914.4), "914 mm")
    XCTAssertEqual(LengthFormatter.millimetres(200_000), "200,000 mm")
    XCTAssertEqual(LengthFormatter.millimetres(2690), "2,690 mm")
    XCTAssertEqual(LengthFormatter.millimetres(999.5), "1,000 mm", "half away from zero")
    XCTAssertEqual(LengthFormatter.millimetres(1.5875), "2 mm")
  }

  func testRangeUsesAnEnDashWithoutSpaces() {
    XCTAssertEqual(LengthFormatter.millimetreRange(2690, 2740), "2,690\u{2013}2,740 mm")
    XCTAssertEqual(LengthFormatter.millimetreRange(2690, 2690.2), "2,690 mm")
  }

  func testFeetAndInchesToATenthWithASCIIMarks() {
    XCTAssertEqual(LengthFormatter.feetInches(7518.4), "24' 8\"")
    XCTAssertEqual(LengthFormatter.feetInches(11239.5), "36' 10.5\"")
    XCTAssertEqual(LengthFormatter.feetInches(3060.7), "10' 0.5\"")
    XCTAssertEqual(LengthFormatter.feetInches(7520), "24' 8.1\"")
    XCTAssertEqual(LengthFormatter.feetInches(2490), "8' 2\"")
    XCTAssertEqual(LengthFormatter.feetInches(1524), "5' 0\"")
    XCTAssertEqual(LengthFormatter.feetInches(1.5875), "0' 0.1\"")
    XCTAssertEqual(LengthFormatter.feetInches(2690), "8' 9.9\"")
  }

  func testInchesCarryIntoFeetBeforeTheSplit() {
    // 303.8 mm is 11.96 in: rounded as a whole it is 12.0 in, so one foot, never 0' 12".
    XCTAssertEqual(LengthFormatter.feetInches(303.8), "1' 0\"")
    // 143.96 in (3656.584 mm): 11' 11.96" rounds to 12' 0".
    XCTAssertEqual(LengthFormatter.feetInches(3656.584), "12' 0\"")
  }

  func testBothUnitsOnOneLine() {
    XCTAssertEqual(LengthFormatter.both(7520), "7,520 mm \u{00B7} 24' 8.1\"")
  }

  func testNoPrimeOrFractionGlyphs() {
    for value in [7518.4, 11239.5, 1.5875, 2690, 303.8] {
      let text = LengthFormatter.both(value)
      for glyph in ["\u{2032}", "\u{2033}", "\u{00BD}", "\u{215B}", "/"] {
        XCTAssertFalse(text.contains(glyph), "\(text) contains \(glyph)")
      }
    }
  }

  func testSpokenForms() {
    XCTAssertEqual(LengthFormatter.spokenMillimetres(7520), "7,520 millimetres")
    XCTAssertEqual(LengthFormatter.spokenFeetInches(7520), "24 feet 8.1 inches")
  }
}
