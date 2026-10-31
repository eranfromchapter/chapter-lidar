import CaptureContract
import Foundation

/// The compass of one capture as the field screens word it (phone-field §6.4, compass §5.3),
/// mapped from the contract's evaluator (`CompassState`, north-arrow v2 thresholds; nothing is
/// re-decided here).
public enum CaptureCompassStatus: String, CaseIterable, Hashable, Sendable {
  /// True north, ±10° or better.
  case verified
  /// True north ±11–30°, or magnetic north.
  case approximate
  /// A reading was taken but cannot be used (inaccurate, rejected).
  case notVerified
  /// No reading (none recorded, compass not calibrated, no compass on the phone).
  case notRead

  public init(_ state: CompassState) {
    switch state.word {
    case .verified: self = .verified
    case .approximate: self = .approximate
    case .notVerified: self = .notVerified
    case .notRead: self = .notRead
    }
  }

  /// The status of a capture's stored reading (a 1.0.0 record has none: `notRead`).
  public init(capture: CaptureRecord.Capture) {
    self.init(CompassState(capture))
  }

  /// `verified`, `approximate`, `not verified`, `not read`.
  public var word: String {
    switch self {
    case .verified: return CompassWord.verified.rawValue
    case .approximate: return CompassWord.approximate.rawValue
    case .notVerified: return CompassWord.notVerified.rawValue
    case .notRead: return CompassWord.notRead.rawValue
    }
  }

  /// Verified or approximate: the plans carry an arrow.
  public var isUsable: Bool { self == .verified || self == .approximate }
}

/// The compass of a visit in one line, for Before you leave's "Compass reading" and the
/// capture overview's Compass row.
public enum CompassSummary {
  /// One capture and its status, in record order.
  public struct Entry: Hashable, Sendable {
    public var captureId: LowercaseUUID
    public var label: String
    public var status: CaptureCompassStatus

    public init(captureId: LowercaseUUID, label: String, status: CaptureCompassStatus) {
      self.captureId = captureId
      self.label = label
      self.status = status
    }
  }

  /// The right side of the overview's Compass row (critique R-21).
  public enum OverviewStatus: String, CaseIterable, Sendable {
    /// ● `Verified`: every capture verified.
    case verified
    /// ▲ `Approx.`: every capture usable, at least one approximate.
    case approximate
    /// ▲ `Partly`: some usable, some not.
    case partly
    /// ▲ `Not verified`: none usable.
    case notVerified

    public var word: String {
      switch self {
      case .verified: return "Verified"
      case .approximate: return "Approx."
      case .partly: return "Partly"
      case .notVerified: return "Not verified"
      }
    }

    /// True for ● Verified; the other three are drawn ▲ (advisory, never blocking).
    public var isVerified: Bool { self == .verified }
  }

  /// The compass detail of a visit whose captures are all sketches (spec F14 1.7): nothing is
  /// read, nothing is asked.
  public static let sketchOnlyDetail = "Sketch capture: the plan is oriented as drawn"
  /// The same for a visit of AR walkthroughs only (spec F15 5): the walk has no compass frame.
  public static let walkthroughOnlyDetail = "AR walkthrough: the plan is oriented as walked"
  /// The same for a visit of sketches and walkthroughs, no scan.
  public static let measuredOnlyDetail = "No floor was scanned: the plans are oriented as measured"

  /// The compass detail of a visit without a scanned capture: the words of its one source, or
  /// `measuredOnlyDetail` for a mix.
  public static func noScanDetail(_ captures: [CaptureRecord.Capture]) -> String {
    if captures.allSatisfy({ $0.source == .sketch }) { return sketchOnlyDetail }
    if captures.allSatisfy({ $0.source == .walkthrough }) { return walkthroughOnlyDetail }
    return measuredOnlyDetail
  }

  /// Every scanned capture of the record (exterior included), in record order, with its
  /// status: `overrides[captureId]` when given, else the capture's stored reading. A sketch or
  /// AR walkthrough capture has no scan frame to read a heading into (spec F14 1.7, F15 5) and
  /// is left out.
  public static func entries(
    record: CaptureRecord, overrides: [LowercaseUUID: CaptureCompassStatus] = [:]
  ) -> [Entry] {
    record.captures.filter { !$0.source.isMeasuredPlan }.map { capture in
      Entry(
        captureId: capture.captureId,
        label: capture.label.trimmingCharacters(in: .whitespaces),
        status: overrides[capture.captureId] ?? CaptureCompassStatus(capture: capture))
    }
  }

  /// `Floor 1 verified · Floor 2 not read` (the overview's per-floor subtitle).
  public static func short(_ entries: [Entry]) -> String {
    entries.map { "\($0.label) \($0.status.word)" }.joined(separator: " \u{00B7} ")
  }

  /// The detail of Before you leave's "Compass reading" (phone-field §6.4): `short`, then what
  /// the plans will say about the captures that are not verified: `Floor 1 verified · Floor 2
  /// not read: its plan will say "not verified"`. Nothing is added when all are verified.
  public static func detail(_ entries: [Entry]) -> String {
    let unusable = entries.filter { !$0.status.isUsable }.count
    let approximate = entries.filter { $0.status == .approximate }.count
    let suffix: String
    if unusable > 0 {
      suffix = unusable == 1
        ? ": its plan will say \"not verified\"" : ": their plans will say \"not verified\""
    } else if approximate > 0 {
      suffix = approximate == 1
        ? ": its plan will say \"approx. north\"" : ": their plans will say \"approx. north\""
    } else {
      suffix = ""
    }
    return short(entries) + suffix
  }

  /// True when every capture is verified (Before you leave's ● and the overview's ● Verified).
  public static func allVerified(_ entries: [Entry]) -> Bool {
    !entries.isEmpty && entries.allSatisfy { $0.status == .verified }
  }

  /// The overview's word: all verified, all usable with an approximate, some usable, none.
  public static func overview(_ entries: [Entry]) -> OverviewStatus {
    let usable = entries.filter(\.status.isUsable).count
    if usable == 0 { return .notVerified }
    if usable < entries.count { return .partly }
    return allVerified(entries) ? .verified : .approximate
  }
}
