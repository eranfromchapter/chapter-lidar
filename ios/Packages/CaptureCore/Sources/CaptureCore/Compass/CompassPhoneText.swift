import CaptureContract
import Foundation

/// Every compass word on the phone's capture screens (compass §5.1–5.2, critique R-20): the
/// compass row of "What are you scanning?" and the live scan's chip. Pure, so the exact strings
/// are tested on Linux; CaptureUI only draws them.
public enum CompassPhoneText {
  /// The footnote under the compass card.
  public static let footnote =
    "Read automatically. Hold the phone flat, away from steel and appliances. Approximate or "
    + "missing readings are shown as such on the plans."
  /// Shown under the footnote while Location is denied or restricted.
  public static let locationOffNote =
    "Location is off for Chapter Capture, so north is magnetic and shown as approximate. Turn "
    + "on Location in Settings to record true north."
  public static let openSettings = "Open Settings"
  public static let readAgain = "Read again"

  /// How the compass glyph is drawn.
  public enum Glyph: Hashable, Sendable {
    /// Filled arrow.
    case verified
    /// Hollow arrow, dashed ring.
    case approximate
    /// The 32 pt glyph's dashed ring only; no arrow ever. The chip draws nothing.
    case none
  }

  /// The status in front of the row's second line.
  public enum Status: Hashable, Sendable {
    /// No glyph, muted text (reading).
    case none
    /// ● in ready.
    case verified
    /// ▲ in limited (never ■: the compass does not block).
    case limited
  }

  /// The compass row (compass §5.1).
  public struct Row: Hashable, Sendable {
    public var line1: String
    public var line2: String
    public var status: Status
    public var glyph: Glyph
    /// Degrees, clockwise: −(the heading of the phone's top edge at the reading).
    public var rotation: Double
    /// Hidden when the phone has no compass.
    public var showsReadAgain: Bool
    /// Disabled (opacity 0.4) while reading.
    public var readAgainEnabled: Bool
    /// The row is one element.
    public var accessibilityLabel: String
  }

  /// The live scan's compass chip (compass §5.2).
  public struct Chip: Hashable, Sendable {
    public var text: String
    public var glyph: Glyph
    /// Degrees, clockwise: −(the bearing the camera looks at); nil keeps the last angle.
    public var rotation: Double?
    public var accessibilityLabel: String
  }

  /// The row for a pre-check state; `now` gives `{AGO}`.
  public static func row(_ state: CompassPrecheckState, now: Date) -> Row {
    switch state {
    case .reading:
      return Row(
        line1: "Compass", line2: "Reading the compass…", status: .none, glyph: .none, rotation: 0,
        showsReadAgain: true, readAgainEnabled: false,
        accessibilityLabel: "Compass. Reading the compass.")
    case .notCalibrated:
      return Row(
        line1: "No compass reading",
        line2: "Not verified · move the phone in a figure 8, then read again", status: .limited,
        glyph: .none, rotation: 0, showsReadAgain: true, readAgainEnabled: true,
        accessibilityLabel:
          "Compass. No compass reading. Not verified, move the phone in a figure 8, then read again.")
    case .unavailable:
      return Row(
        line1: "No compass on this phone", line2: "Not verified · the plans will say so",
        status: .limited, glyph: .none, rotation: 0, showsReadAgain: false,
        readAgainEnabled: false,
        accessibilityLabel: "Compass. No compass on this phone. Not verified, the plans will say so.")
    case .result(let heading, let accuracy, let source, let readAt):
      let seconds = now.timeIntervalSince(readAt)
      let ago = CompassText.ago(seconds: seconds)
      let spokenAgo = spokenAgo(seconds: seconds)
      let degrees = CompassText.heading(heading)
      let line1 = "North \(degrees)° \(source.rawValue) · ±\(accuracy)°"
      let spoken =
        "North \(degrees) degrees \(source.rawValue), plus or minus \(accuracy) degrees"
      let state = CompassState(reading: heading, accuracy: accuracy, source: source, at: readAt)
      let rotation = -CompassMath.normalized(heading)
      switch state {
      case .verified:
        return Row(
          line1: line1, line2: "Verified · read \(ago)", status: .verified, glyph: .verified,
          rotation: rotation, showsReadAgain: true, readAgainEnabled: true,
          accessibilityLabel: "Compass. \(spoken). Verified, read \(spokenAgo).")
      case .approximate:
        return Row(
          line1: line1, line2: "Approximate · read \(ago)", status: .limited, glyph: .approximate,
          rotation: rotation, showsReadAgain: true, readAgainEnabled: true,
          accessibilityLabel: "Compass. \(spoken). Approximate, read \(spokenAgo).")
      case .notVerified:
        return Row(
          line1: line1, line2: "Not verified · accuracy too low · read \(ago)", status: .limited,
          glyph: .none, rotation: 0, showsReadAgain: true, readAgainEnabled: true,
          accessibilityLabel:
            "Compass. \(spoken). Not verified, accuracy too low, read \(spokenAgo).")
      }
    }
  }

  /// The chip for the live state of the floor's scan.
  public static func chip(_ state: CompassLiveState) -> Chip {
    switch state {
    case .reading:
      return Chip(
        text: "N · reading…", glyph: .none, rotation: nil, accessibilityLabel: "Compass reading")
    case .notVerified:
      return notVerifiedChip
    case .result(let compass, let bearing):
      let rotation = bearing.map { -CompassMath.normalized($0) }
      switch compass {
      case .verified(_, let accuracy):
        return Chip(
          text: "N · true · ±\(accuracy)°", glyph: .verified, rotation: rotation,
          accessibilityLabel:
            "Compass verified, true north, plus or minus \(accuracy) degrees")
      case .approximate(_, let accuracy, let source):
        return Chip(
          text: source == .trueNorth ? "N · approx. · ±\(accuracy)°" : "N · magnetic · ±\(accuracy)°",
          glyph: .approximate, rotation: rotation,
          accessibilityLabel:
            "Compass approximate, \(source.rawValue) north, plus or minus \(accuracy) degrees")
      case .notVerified:
        return notVerifiedChip
      }
    }
  }

  private static let notVerifiedChip = Chip(
    text: "N · not verified", glyph: .none, rotation: nil,
    accessibilityLabel: "Compass not verified")

  /// `{AGO}` as VoiceOver says it: "just now", "12 seconds ago", "3 minutes ago", "over an hour
  /// ago".
  public static func spokenAgo(seconds: Double) -> String {
    let elapsed = max(0, seconds)
    if elapsed < 5 { return "just now" }
    if elapsed < 60 { return "\(Int(elapsed)) seconds ago" }
    if elapsed < 3600 {
      let minutes = Int(elapsed / 60)
      return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
    }
    return "over an hour ago"
  }
}
