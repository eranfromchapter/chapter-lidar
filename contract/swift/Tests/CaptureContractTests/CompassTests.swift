import CaptureContract
import Foundation
import XCTest

/// Compass spec 13.1 / AC2: every vector in contract/test-vectors/compass-states.json gives its
/// expected state, north symbol, detail and word. contract/ts/test/compass.test.ts runs the same
/// file, so the phone and the station classify every reading identically.
final class CompassTests: XCTestCase {
  private struct Vector: Decodable {
    struct Fields: Decodable {
      var capturedAt: UTCTimestamp
      var finishedAt: UTCTimestamp?
      var heading: Double?
      var headingAccuracy: Int?
      var headingSource: HeadingSource?
      var headingRecordedAt: UTCTimestamp?
      var headingIssue: HeadingIssue?
    }

    struct Symbol: Decodable {
      var kind: String
      var angleCcw: Double?
      var approximate: Bool?
      var lines: [String]?
      var box: String?
      var caption: String?
    }

    struct Expected: Decodable {
      var kind: String
      var reason: String?
      var accuracy: Int?
      var word: String
      var symbol: Symbol
      var detail: String
    }

    var name: String
    var capture: Fields
    var rotationCcw: Double
    var expected: Expected
  }

  private func vectors() throws -> [Vector] {
    let url = ContractFiles.testVectorsDirectory.appendingPathComponent("compass-states.json")
    return try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
  }

  private func capture(_ fields: Vector.Fields) -> CaptureRecord.Capture {
    CaptureRecord.Capture(
      captureId: LowercaseUUID(rawValue: "3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35")!,
      areaKey: "floor-1", label: "Floor 1", mode: .floor, units: .init(display: .imperial),
      capturedAt: fields.capturedAt, finishedAt: fields.finishedAt, heading: fields.heading,
      headingAccuracy: fields.headingAccuracy, headingSource: fields.headingSource,
      headingRecordedAt: fields.headingRecordedAt, headingIssue: fields.headingIssue)
  }

  private func kind(_ state: CompassState) -> String {
    switch state {
    case .verified: return "verified"
    case .approximate: return "approximate"
    case .notVerified: return "not_verified"
    }
  }

  func testEveryVector() throws {
    let all = try vectors()
    XCTAssertGreaterThanOrEqual(all.count, 30)
    for vector in all {
      let name = vector.name
      let state = CompassState(capture(vector.capture))
      let expected = vector.expected
      XCTAssertEqual(kind(state), expected.kind, name)
      XCTAssertEqual(state.reason?.rawValue, expected.reason, name)
      XCTAssertEqual(state.isUsable, expected.kind != "not_verified", name)
      if state.isUsable {
        XCTAssertEqual(state.heading, vector.capture.heading, name)
        XCTAssertEqual(state.accuracy, vector.capture.headingAccuracy, name)
        XCTAssertEqual(state.source, vector.capture.headingSource, name)
      } else {
        XCTAssertEqual(state.accuracy, expected.accuracy, name)
      }
      XCTAssertEqual(state.word.rawValue, expected.word, name)
      XCTAssertEqual(CompassText.detail(state), expected.detail, name)

      switch NorthSymbol(state: state, drawingRotationCCW: vector.rotationCcw) {
      case .arrow(let angle, let approximate, let line1, let line2):
        XCTAssertEqual(expected.symbol.kind, "arrow", name)
        XCTAssertEqual(angle, try XCTUnwrap(expected.symbol.angleCcw, name), accuracy: 1e-9, name)
        XCTAssertEqual(approximate, expected.symbol.approximate, name)
        XCTAssertEqual([line1, line2], expected.symbol.lines, name)
      case .notVerified(let box, let caption):
        XCTAssertEqual(expected.symbol.kind, "box", name)
        XCTAssertEqual(box, expected.symbol.box, name)
        XCTAssertEqual(caption, expected.symbol.caption, name)
      }
    }
  }

  func testEveryStateAndReasonIsCovered() throws {
    let seen = Set(try vectors().map { $0.expected.reason ?? $0.expected.kind })
    let wanted = Set(["verified", "approximate"] + CompassReason.allCases.map(\.rawValue))
    XCTAssertEqual(seen, wanted)
  }

  func testThresholds() {
    XCTAssertEqual(CompassThresholds.verifiedMax, 10)
    XCTAssertEqual(CompassThresholds.approximateMax, 30)
  }

  func testAHeadingWithoutItsAccuracySourceOrTimeIsRejected() {
    let read = UTCTimestamp(rawValue: "2026-10-17T14:02:20Z")!
    let base = capture(
      .init(
        capturedAt: UTCTimestamp(rawValue: "2026-10-17T14:02:11Z")!, heading: 212.4,
        headingAccuracy: 8, headingSource: .trueNorth, headingRecordedAt: read))
    XCTAssertEqual(CompassState(base), .verified(heading: 212.4, accuracy: 8))
    var noAccuracy = base
    noAccuracy.headingAccuracy = nil
    var noSource = base
    noSource.headingSource = nil
    var noTime = base
    noTime.headingRecordedAt = nil
    for broken in [noAccuracy, noSource, noTime] {
      XCTAssertEqual(CompassState(broken), .notVerified(.rejected, accuracy: nil))
    }
    var withIssue = base
    withIssue.headingIssue = .unavailable
    XCTAssertEqual(CompassState(withIssue), .verified(heading: 212.4, accuracy: 8))
  }

  func testTheExampleRecordIsVerifiedThenRejected() throws {
    let url = ContractFiles.examplesDirectory.appendingPathComponent(
      "capture-record/valid/compass-two-captures.json")
    let record = try CaptureContractJSON.makeDecoder().decode(
      CaptureRecord.self, from: Data(contentsOf: url))
    XCTAssertEqual(record.captures.map { CompassState($0).word }, [.verified, .notVerified])
  }

  func testAgoTexts() {
    XCTAssertEqual(CompassText.ago(seconds: -3), "just now")
    XCTAssertEqual(CompassText.ago(seconds: 0), "just now")
    XCTAssertEqual(CompassText.ago(seconds: 4.9), "just now")
    XCTAssertEqual(CompassText.ago(seconds: 5), "5 s ago")
    XCTAssertEqual(CompassText.ago(seconds: 12.7), "12 s ago")
    XCTAssertEqual(CompassText.ago(seconds: 59.9), "59 s ago")
    XCTAssertEqual(CompassText.ago(seconds: 60), "1 min ago")
    XCTAssertEqual(CompassText.ago(seconds: 3599), "59 min ago")
    XCTAssertEqual(CompassText.ago(seconds: 3600), "over an hour ago")
  }

  func testHeadingAndAccuracyTokens() {
    XCTAssertEqual(CompassText.heading(212.4), "212")
    XCTAssertEqual(CompassText.heading(212.5), "213")
    XCTAssertEqual(CompassText.heading(359.6), "0")
    XCTAssertEqual(CompassText.heading(-0.6), "359")
    XCTAssertEqual(CompassText.accuracy(8), "8")
    XCTAssertEqual(CompassText.limitation, "Plan orientation is not verified; north is not shown.")
  }

  func testTextsAvoidCharactersThePhonePDFWriterCannotPrint() throws {
    var texts: [String] = []
    for vector in try vectors() {
      let state = CompassState(capture(vector.capture))
      texts.append(CompassText.detail(state))
      switch NorthSymbol(state: state, drawingRotationCCW: vector.rotationCcw) {
      case .arrow(_, _, let line1, let line2): texts += [line1, line2]
      case .notVerified(let box, let caption): texts += [box, caption]
      }
    }
    for text in texts {
      for forbidden in ["\u{2212}", "\u{2032}", "\u{2033}", "\u{2248}"] {
        XCTAssertFalse(text.contains(forbidden), text)
      }
    }
  }
}
