import CaptureContract
import Foundation

/// What one floor's scan found (compass §3.3 step 9): the heading of the capture's −Z axis with
/// its accuracy, north and time, or none, with the issue when the phone knows why (§1.5). The
/// cases of the contract's `CompassResultValue`, which `CaptureRecord.Capture.setCompass(_:)`
/// writes; `CaptureFlowModel.finishFloor()` is the only caller on the phone.
public typealias CompassResult = CompassResultValue

extension CompassResultValue {
  /// The state the shared evaluator gives this result on a capture scanned from `capturedAt` to
  /// `finishedAt` (rules 1–8 of the contract, rule 5 included).
  public func state(capturedAt: UTCTimestamp, finishedAt: UTCTimestamp?) -> CompassState {
    var capture = CompassState.probeCapture(capturedAt: capturedAt)
    capture.finishedAt = finishedAt
    capture.setCompass(self)
    return CompassState(capture)
  }
}

extension CompassState {
  /// The state of a reading the phone has just taken (the pre-check, or one window of the scan):
  /// the contract's evaluator on a capture holding only that reading, so the thresholds (±10°
  /// verified with true north, ±30° usable) live in one place.
  public init(reading heading: Double, accuracy: Int, source: HeadingSource, at date: Date) {
    let time = UTCTimestamp(date)
    var capture = CompassState.probeCapture(capturedAt: time)
    capture.setCompass(
      .reading(heading: heading, accuracy: accuracy, source: source, recordedAt: time))
    self.init(capture)
  }

  /// Order of the states when the best reading is chosen: verified > approximate > not verified
  /// (compass §3.3 step 6).
  public var rank: Int {
    switch self {
    case .verified: return 2
    case .approximate: return 1
    case .notVerified: return 0
    }
  }

  /// A capture that carries nothing but a reading, for the evaluator.
  static func probeCapture(capturedAt: UTCTimestamp) -> CaptureRecord.Capture {
    CaptureRecord.Capture(
      captureId: LowercaseUUID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))),
      areaKey: "compass", label: "Compass", mode: .room,
      units: CaptureRecord.Units(display: .imperial), capturedAt: capturedAt)
  }
}
