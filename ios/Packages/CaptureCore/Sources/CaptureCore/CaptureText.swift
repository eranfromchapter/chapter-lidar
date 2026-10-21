import CaptureContract
import Foundation

/// Text formats of the capture screens (phone-capture §5.6), in the en_US_POSIX locale and the
/// device time zone (`timeZone`, injected in tests). They replace `RelativeDateTimeFormatter`,
/// which prints "2 min. ago" and not the design's "2 min ago". The compass's own `{AGO}` is
/// `CompassText.ago` (contract).
public enum CaptureText {
  static let locale = Locale(identifier: "en_US_POSIX")

  /// "updated …" of a HUB project: "just now" (under 60 s), "N min ago", "N h ago" (under 24 h),
  /// then "on MMM d" ("on Oct 20").
  public static func relativeAge(from date: Date, now: Date, timeZone: TimeZone = .current) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 60 { return "just now" }
    if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
    if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
    return "on \(format(date, "MMM d", timeZone))"
  }

  /// The text as it is drawn, with no line break inside an age: the spaces of "40 s ago",
  /// "2 min ago" and "3 h ago" become no-break spaces (U+00A0), so a wrapped line never leaves a
  /// number at the end of one line and its unit on the next ("read 40" / "s ago"; Inter is wider
  /// than the design's SF). For drawn text only: the strings themselves, and what VoiceOver reads,
  /// keep ordinary spaces.
  public static func keepingAgesTogether(_ text: String) -> String {
    text.replacingOccurrences(
      of: "([0-9]+) (s|min|h) ago", with: "$1\u{00A0}$2\u{00A0}ago", options: .regularExpression)
  }

  /// A sealed package's date: "Jan 25, 2025".
  public static func sealedDate(_ date: Date, timeZone: TimeZone = .current) -> String {
    format(date, "MMM d, yyyy", timeZone)
  }

  /// When the offline project list was saved: "Oct 20, 14:12" (24 h).
  public static func offlineStamp(_ date: Date, timeZone: TimeZone = .current) -> String {
    format(date, "MMM d, HH:mm", timeZone)
  }

  /// The overview's "Captured [WHEN]": "today", "yesterday", "Oct 20" in the same year,
  /// "Oct 20, 2025" otherwise.
  public static func capturedWhen(visitedAt: Date, now: Date, timeZone: TimeZone = .current)
    -> String
  {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    if calendar.isDate(visitedAt, inSameDayAs: now) { return "today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
      calendar.isDate(visitedAt, inSameDayAs: yesterday)
    {
      return "yesterday"
    }
    if calendar.component(.year, from: visitedAt) == calendar.component(.year, from: now) {
      return format(visitedAt, "MMM d", timeZone)
    }
    return format(visitedAt, "MMM d, yyyy", timeZone)
  }

  /// "1 floor" / "2 floors".
  public static func plural(_ count: Int, _ one: String, _ many: String) -> String {
    "\(count) \(count == 1 ? one : many)"
  }

  /// Running time as mm:ss ("06:42"); minutes may pass 59 ("72:05").
  public static func elapsed(_ seconds: TimeInterval) -> String {
    let whole = max(0, Int(seconds))
    return String(format: "%02d:%02d", whole / 60, whole % 60)
  }

  /// Running time as VoiceOver says it: "Elapsed 6 minutes 42 seconds".
  public static func spokenElapsed(_ seconds: TimeInterval) -> String {
    let whole = max(0, Int(seconds))
    let minutes = whole / 60
    let rest = whole % 60
    var parts: [String] = []
    if minutes > 0 { parts.append(plural(minutes, "minute", "minutes")) }
    if rest > 0 || minutes == 0 { parts.append(plural(rest, "second", "seconds")) }
    return "Elapsed " + parts.joined(separator: " ")
  }

  /// The mode as the screens name it.
  public static func modeTitle(_ mode: CaptureMode) -> String {
    switch mode {
    case .room: return "One room"
    case .floor: return "Whole floor"
    case .exterior: return "Exterior"
    }
  }

  /// The first letter uppercased ("locked" → "Locked"), the rest unchanged.
  public static func capitalizedFirst(_ text: String) -> String {
    guard let first = text.first else { return text }
    return String(first).uppercased(with: locale) + text.dropFirst()
  }

  /// The text without one final period ("Choose the HUB project." → "Choose the HUB project").
  public static func withoutFinalPeriod(_ text: String) -> String {
    text.hasSuffix(".") ? String(text.dropLast()) : text
  }

  private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = pattern
    return formatter.string(from: date)
  }
}
