/// The compass reading of one capture (capture record 1.1.0): its state, the north symbol drawn on
/// plans and the shared texts. One evaluator for the phone, the plan sheet and (in TypeScript,
/// contract/ts/src/compass.ts) the station and the web; both run
/// contract/test-vectors/compass-states.json.
///
/// Rules, in order:
///   1-4. no heading: `headingIssue` rejected / not_calibrated / unavailable, else no reading
///   5.   `headingRecordedAt` outside [capturedAt − 60 s, (finishedAt ?? capturedAt + 24 h) + 60 s]: rejected
///   6.   `headingAccuracy` > 30: inaccurate
///   7.   true north and `headingAccuracy` ≤ 10: verified
///   8.   otherwise (true 11–30, magnetic ≤ 30): approximate
/// A heading without its accuracy, source or time (not a valid 1.1.0 record) is rejected.

/// Accuracy limits of the three states, whole degrees, inclusive.
public enum CompassThresholds {
  /// Highest accuracy of a verified reading (true north only).
  public static let verifiedMax = 10
  /// Highest accuracy of a usable (verified or approximate) reading.
  public static let approximateMax = 30
  /// How far the reading time may lie outside the scan (rule 5).
  public static let readingSlackSeconds: Int64 = 60
  /// End of the scan when the capture has no `finishedAt`, after `capturedAt` (rule 5).
  public static let openScanSeconds: Int64 = 24 * 60 * 60
}

/// Why an orientation is not verified.
public enum CompassReason: String, CaseIterable, Sendable {
  case noReading = "no_reading"
  case rejected
  case inaccurate
  case notCalibrated = "not_calibrated"
  case unavailable
}

/// The orientation state of one capture.
public enum CompassState: Hashable, Sendable {
  /// True north, accuracy ±10° or better.
  case verified(heading: Double, accuracy: Int)
  /// True north ±11° to ±30°, or magnetic north ±30° or better.
  case approximate(heading: Double, accuracy: Int, source: HeadingSource)
  /// No usable reading. `accuracy` is set for `.inaccurate` only.
  case notVerified(CompassReason, accuracy: Int?)

  /// The state of a capture's stored reading (rules 1–8 above).
  public init(_ capture: CaptureRecord.Capture) {
    guard let heading = capture.heading else {
      switch capture.headingIssue {
      case .rejected: self = .notVerified(.rejected, accuracy: nil)
      case .notCalibrated: self = .notVerified(.notCalibrated, accuracy: nil)
      case .unavailable: self = .notVerified(.unavailable, accuracy: nil)
      case nil: self = .notVerified(.noReading, accuracy: nil)
      }
      return
    }
    guard let accuracy = capture.headingAccuracy, let source = capture.headingSource,
      let recordedAt = capture.headingRecordedAt
    else {
      self = .notVerified(.rejected, accuracy: nil)
      return
    }
    let start = capture.capturedAt.secondsSince1970
    let end = capture.finishedAt?.secondsSince1970 ?? start + CompassThresholds.openScanSeconds
    let slack = CompassThresholds.readingSlackSeconds
    let read = recordedAt.secondsSince1970
    guard read >= start - slack, read <= end + slack else {
      self = .notVerified(.rejected, accuracy: nil)
      return
    }
    if accuracy > CompassThresholds.approximateMax {
      self = .notVerified(.inaccurate, accuracy: accuracy)
    } else if source == .trueNorth, accuracy <= CompassThresholds.verifiedMax {
      self = .verified(heading: heading, accuracy: accuracy)
    } else {
      self = .approximate(heading: heading, accuracy: accuracy, source: source)
    }
  }

  /// Verified or approximate: the plans carry an arrow.
  public var isUsable: Bool {
    if case .notVerified = self { return false }
    return true
  }

  /// The stored heading of a usable state.
  public var heading: Double? {
    switch self {
    case .verified(let heading, _), .approximate(let heading, _, _): return heading
    case .notVerified: return nil
    }
  }

  /// The accuracy of a usable or inaccurate state.
  public var accuracy: Int? {
    switch self {
    case .verified(_, let accuracy), .approximate(_, let accuracy, _): return accuracy
    case .notVerified(_, let accuracy): return accuracy
    }
  }

  /// North of a usable state.
  public var source: HeadingSource? {
    switch self {
    case .verified: return .trueNorth
    case .approximate(_, _, let source): return source
    case .notVerified: return nil
    }
  }

  /// Why a state is not verified; nil for a usable state.
  public var reason: CompassReason? {
    if case .notVerified(let reason, _) = self { return reason }
    return nil
  }

  /// The summary word of the state ("Floor 1 verified · Floor 2 not read").
  public var word: CompassWord {
    switch self {
    case .verified: return .verified
    case .approximate: return .approximate
    case .notVerified(let reason, _):
      return reason == .inaccurate || reason == .rejected ? .notVerified : .notRead
    }
  }
}

/// Words of a capture's state in summaries: `not verified` when a reading was taken but is not
/// usable (inaccurate, rejected), `not read` when there was none.
public enum CompassWord: String, CaseIterable, Sendable {
  case verified
  case approximate
  case notVerified = "not verified"
  case notRead = "not read"
}

/// The symbol drawn on a plan: an arrow for a usable reading, the text box otherwise. Geometry
/// and placement belong to each output; this carries the angle and the texts.
public enum NorthSymbol: Hashable, Sendable {
  /// `angleCCW`: counter-clockwise from "up" on the page, degrees in `0 ..< 360`. `approximate`:
  /// dashed ring and hollow arrow.
  case arrow(angleCCW: Double, approximate: Bool, line1: String, line2: String)
  /// The box `Orientation: not verified` with the reason caption under it. Never an arrow.
  case notVerified(box: String, caption: String)

  /// The symbol of a drawing that shows the plan turned counter-clockwise by `rho` degrees. The
  /// arrow angle and the caption's `{HDG}` are both A = (heading + rho) mod 360, the bearing of
  /// "up" on that drawing.
  public init(state: CompassState, drawingRotationCCW rho: Double = 0) {
    switch state {
    case .verified(let heading, let accuracy):
      let angle = CompassMath.arrowAngle(heading: heading, drawingRotationCCW: rho)
      self = .arrow(
        angleCCW: angle, approximate: false, line1: CompassText.verifiedLine1,
        line2: "±\(CompassText.accuracy(accuracy))° · \(CompassText.heading(angle))°")
    case .approximate(let heading, let accuracy, let source):
      self = .arrow(
        angleCCW: CompassMath.arrowAngle(heading: heading, drawingRotationCCW: rho),
        approximate: true, line1: CompassText.approximateLine1,
        line2: "±\(CompassText.accuracy(accuracy))° · \(source.rawValue)")
    case .notVerified(let reason, let accuracy):
      self = .notVerified(
        box: CompassText.notVerifiedBox, caption: CompassText.caption(reason, accuracy: accuracy))
    }
  }
}

/// The result of a floor's compass reading, as the phone records it (`Capture.setCompass`).
public enum CompassResultValue: Hashable, Sendable {
  /// A reading: heading of the capture's −Z axis, accuracy in whole degrees, north, when.
  case reading(heading: Double, accuracy: Int, source: HeadingSource, recordedAt: UTCTimestamp)
  /// No reading; `issue` says why when the app knows.
  case none(issue: HeadingIssue?)
}

/// The compass texts shared by the phone, the plans, the station and the web. Never U+2212
/// minus, primes or ≈: the phone PDF writer has no glyphs for them.
public enum CompassText {
  public static let notVerifiedBox = "Orientation: not verified"
  public static let verifiedLine1 = "True north · compass"
  public static let approximateLine1 = "Approx. north · compass"
  /// The verdict limitation of a not-verified capture.
  public static let limitation = "Plan orientation is not verified; north is not shown."

  /// `{HDG}`: a bearing rounded half up to a whole degree, mod 360 ("212", never "360").
  public static func heading(_ degrees: Double) -> String {
    String(CompassMath.wholeDegrees(degrees))
  }

  /// `{ACC}`: the stored accuracy.
  public static func accuracy(_ accuracy: Int) -> String {
    String(accuracy)
  }

  /// Caption under the not-verified box.
  public static func caption(_ reason: CompassReason, accuracy: Int?) -> String {
    switch reason {
    case .noReading: return "No compass reading"
    case .rejected: return "Reading rejected"
    case .inaccurate: return "Compass accuracy ±\(Self.accuracy(accuracy ?? 0))°"
    case .notCalibrated: return "Compass not calibrated"
    case .unavailable: return "Compass unavailable"
    }
  }

  /// Station detail and web phrase of a state; `{HDG}` is the stored heading.
  public static func detail(_ state: CompassState) -> String {
    switch state {
    case .verified(let heading, let accuracy):
      return "True heading \(Self.heading(heading))°, accuracy ±\(Self.accuracy(accuracy))°"
    case .approximate(let heading, let accuracy, let source):
      return "Approximate north: \(source.rawValue) heading \(Self.heading(heading))°, "
        + "accuracy ±\(Self.accuracy(accuracy))°"
    case .notVerified(let reason, let accuracy):
      switch reason {
      case .noReading: return "No compass reading recorded; orientation not verified"
      case .rejected: return "Compass reading rejected; orientation not verified"
      case .inaccurate:
        return "Compass accuracy ±\(Self.accuracy(accuracy ?? 0))°; orientation not verified"
      case .notCalibrated: return "Compass not calibrated; orientation not verified"
      case .unavailable: return "No compass on the device; orientation not verified"
      }
    }
  }

  /// `{AGO}` for a reading taken `seconds` ago: `just now` under 5 s, `{n} s ago` under a
  /// minute, `{n} min ago` under an hour, else `over an hour ago`.
  public static func ago(seconds: Double) -> String {
    let elapsed = max(0, seconds)
    if elapsed < 5 { return "just now" }
    if elapsed < 60 { return "\(Int(elapsed)) s ago" }
    if elapsed < 3600 { return "\(Int(elapsed / 60)) min ago" }
    return "over an hour ago"
  }
}
