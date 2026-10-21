import CaptureContract
import Foundation

/// What the Capture overview shows (phone-capture §3.5 with critique R-21, R-25, R-37, R-38):
/// plain data, so the screen is drawn from fixtures. The app's `OverviewBuilder` fills it from
/// the visit (record, photos, FieldRules' checklist, `ControlsList` and `CompassSummary`); the
/// words of this screen's own rows are made here (`FloorRow`, `subtitle(…)`, `ReviewButton`).
public struct CaptureOverviewState: Hashable, Sendable {
  public static let footer = "Photos and controls cannot be recovered later."

  /// Where the visit stands, for the subtitle.
  public enum SealState: Hashable, Sendable {
    /// Revision 1 is being captured.
    case notSealed
    /// Revision `revision` is sealed.
    case sealed(revision: Int)
    /// Revision `revision` (2 or more) is being captured after a verdict.
    case revisionDraft(revision: Int)

    public var text: String {
      switch self {
      case .notSealed: return "not sealed yet"
      case .sealed(let revision): return "revision \(revision) sealed"
      case .revisionDraft(let revision): return "revision \(revision) not sealed yet"
      }
    }
  }

  /// One floor or area of the visit (accessibility id `overview.floor.[areaKey]`).
  public struct FloorRow: Hashable, Sendable, Identifiable {
    /// The capture's area key.
    public var id: String
    public var title: String
    public var subtitle: String
    /// ● Done or ■ Open; nil while the scan's model loads.
    public var status: RowStatusValue?

    public init(id: String, title: String, subtitle: String, status: RowStatusValue?) {
      self.id = id
      self.title = title
      self.subtitle = subtitle
      self.status = status
    }

    /// A scanned floor: "[Mode] · [R] rooms · [P] photos · controls [STATE]" ("1 room", "1 photo",
    /// "no photos yet"; no rooms part when R = 0). `controls` is FieldRules' word for this floor
    /// ("complete", "missing", "incomplete", or under the standard policy "from the scan",
    /// "optional"). Done when the floor has no photo gap and no per-floor control gap.
    public static func scanned(
      areaKey: String, label: String, mode: CaptureMode, rooms: Int, photos: Int,
      controls: String, isDone: Bool
    ) -> FloorRow {
      var parts = [CaptureText.modeTitle(mode)]
      if rooms > 0 { parts.append(CaptureText.plural(rooms, "room", "rooms")) }
      parts.append(photos == 0 ? "no photos yet" : CaptureText.plural(photos, "photo", "photos"))
      parts.append("controls \(controls)")
      return FloorRow(
        id: areaKey, title: label, subtitle: parts.joined(separator: " · "),
        status: isDone ? RowStatusValue(.done, "Done") : RowStatusValue(.missing, "Open"))
    }

    /// A floor whose model is still being read after a relaunch: "Loading…", no status.
    public static func loading(areaKey: String, label: String) -> FloorRow {
      FloorRow(id: areaKey, title: label, subtitle: "Loading…", status: nil)
    }

    /// A floor whose model failed to map; its originals are kept.
    public static func unreadable(areaKey: String, label: String, mode: CaptureMode) -> FloorRow {
      FloorRow(
        id: areaKey, title: label,
        subtitle: "\(CaptureText.modeTitle(mode)) · the scan could not be read",
        status: RowStatusValue(.missing, "Open"))
    }
  }

  /// The four rows of "Before you leave".
  public enum CheckID: String, CaseIterable, Hashable, Sendable {
    case photos
    case controls
    case compass
    case skippedRooms

    public var title: String {
      switch self {
      case .photos: return "Photos"
      case .controls: return "Field controls"
      case .compass: return "Compass"
      case .skippedRooms: return "Rooms not scanned"
      }
    }

    /// `overview.photos`, `overview.controls`, `overview.compass`, `overview.skippedRooms`.
    public var accessibilityIdentifier: String { "overview.\(rawValue)" }
  }

  /// One "Before you leave" row: the subtitle and status come from the checklist (the compass row
  /// never shows ■ and never counts).
  public struct CheckRow: Hashable, Sendable, Identifiable {
    public var id: CheckID
    public var subtitle: String
    public var status: RowStatusValue

    public init(_ id: CheckID, subtitle: String, status: RowStatusValue) {
      self.id = id
      self.subtitle = subtitle
      self.status = status
    }

    public var title: String { id.title }
  }

  /// The bottom button (phone-capture addendum A4).
  public enum ReviewButton: Hashable, Sendable {
    /// Not sealed (revision 1 or revision mode) with `items` blocking checklist items: disabled.
    case fix(items: Int)
    /// Revision 1, checklist passes: Package ready.
    case reviewPackage
    /// Revision mode, checklist passes: the Revision n screen.
    case reviewRevision(Int)
    /// Sealed, the newest package has no verdict yet: Package status.
    case uploadStatus
    /// Sealed with a verdict: Verdict received.
    case openVerdict

    public var title: String {
      switch self {
      case .fix(let items):
        return items == 1
          ? "Fix 1 item to review the package" : "Fix \(items) items to review the package"
      case .reviewPackage: return "Review the package"
      case .reviewRevision(let revision): return "Review revision \(revision)"
      case .uploadStatus: return "Upload status"
      case .openVerdict: return "Open the verdict"
      }
    }

    public var isEnabled: Bool {
      if case .fix = self { return false }
      return true
    }
  }

  /// The project title (R-29), the large title.
  public var title: String
  /// The navigation bar's caption: "Deal [DEAL ID]".
  public var dealCaption: String
  /// "Captured today by Dana Ruiz · not sealed yet".
  public var subtitle: String
  public var floors: [FloorRow]
  /// "Scan another floor or room" is offered (not after sealing, except in revision mode).
  public var canAddFloor: Bool
  /// Photos, Field controls, Compass, Rooms not scanned, in that order.
  public var checks: [CheckRow]
  public var button: ReviewButton

  public init(
    title: String, dealId: String, subtitle: String, floors: [FloorRow], canAddFloor: Bool,
    checks: [CheckRow], button: ReviewButton
  ) {
    self.title = title
    self.dealCaption = "Deal \(dealId)"
    self.subtitle = subtitle
    self.floors = floors
    self.canAddFloor = canAddFloor
    self.checks = checks
    self.button = button
  }

  /// "Captured [WHEN] by [OPERATOR] · [SEAL STATE]".
  public static func subtitle(
    visitedAt: Date, now: Date, operatorName: String, sealState: SealState,
    timeZone: TimeZone = .current
  ) -> String {
    let when = CaptureText.capturedWhen(visitedAt: visitedAt, now: now, timeZone: timeZone)
    return "Captured \(when) by \(operatorName) · \(sealState.text)"
  }
}
