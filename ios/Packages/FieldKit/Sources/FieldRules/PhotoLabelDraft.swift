import CaptureContract
import Foundation

/// The labels the operator must choose before a photo can be saved.
public enum PhotoLabelField: String, CaseIterable, Sendable {
  case room
  case direction
  case subject

  public var title: String {
    switch self {
    case .room: return "Room"
    case .direction: return "Looking toward"
    case .subject: return "Subject"
    }
  }
}

/// Label choices while the labeling screen is open. A photo cannot be saved until `missing` is
/// empty: room, viewing direction and subject are all required.
///
/// Direction is N, E, S or W only. The manifest schema (`photoDirection`) has no free-text
/// "toward <wall/landmark>" value, so none is offered. It may be pre-filled from the phone's
/// compass when the photo is taken (`applyCompass`); the saved label then records whether the
/// operator kept that suggestion (`directionSource` compass) or chose one (manual).
public struct PhotoLabelDraft: Hashable, Sendable {
  public static let maximumRoomLength = 100

  public var room: String?
  public var direction: PhotoDirection?
  public var subject: PhotoSubject?
  /// How `direction` was set: `.compass` while it is the untouched suggestion, `.manual` once the
  /// operator chose a segment; nil while no direction is set.
  public private(set) var directionSource: PhotoDirectionSource?
  /// The cardinal the compass suggested for the photo being labeled; nil without a reading.
  public private(set) var compassSuggestion: PhotoDirection?
  /// The operator chose a direction for this photo.
  public private(set) var directionTouched: Bool

  public init(room: String? = nil, direction: PhotoDirection? = nil, subject: PhotoSubject? = nil) {
    self.room = room
    self.direction = direction
    self.subject = subject
    self.directionSource = direction == nil ? nil : .manual
    self.compassSuggestion = nil
    self.directionTouched = direction != nil
  }

  /// The compass suggestion of a photo just taken (phone-field §9.3): a direction sets it with
  /// source compass, untouched; nil clears the direction (no reading, nothing pre-filled).
  public mutating func applyCompass(_ suggestion: PhotoDirection?) {
    compassSuggestion = suggestion
    directionTouched = false
    direction = suggestion
    directionSource = suggestion == nil ? nil : .compass
  }

  /// The operator tapped a direction segment. Tapping the untouched pre-filled segment keeps
  /// source compass; anything else makes the direction the operator's (manual).
  public mutating func chooseDirection(_ choice: PhotoDirection) {
    if choice == direction, directionSource == .compass, !directionTouched { return }
    direction = choice
    directionSource = .manual
    directionTouched = true
  }

  /// The source the saved label gets: compass only when the direction is the untouched compass
  /// suggestion; manual for any other direction; nil without a direction.
  public var savedDirectionSource: PhotoDirectionSource? {
    guard let direction else { return nil }
    let untouchedSuggestion =
      directionSource == .compass && !directionTouched && direction == compassSuggestion
    return untouchedSuggestion ? .compass : .manual
  }

  /// The words after `LOOKING TOWARD` (phone-field §3.2): the direction came from the compass,
  /// the operator chose it, or there was no reading and nothing is chosen yet.
  public var directionCaptionSuffix: String {
    if savedDirectionSource == .compass { return "\u{00B7} from the compass, change if wrong" }
    if direction != nil { return "\u{00B7} chosen by you" }
    return "\u{00B7} no compass reading, choose one"
  }

  private var cleanRoom: String? {
    guard let trimmed = room?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
      trimmed.count <= Self.maximumRoomLength
    else { return nil }
    return trimmed
  }

  public var missing: [PhotoLabelField] {
    var result: [PhotoLabelField] = []
    if cleanRoom == nil { result.append(.room) }
    if direction == nil { result.append(.direction) }
    if subject == nil { result.append(.subject) }
    return result
  }

  public var isComplete: Bool { missing.isEmpty }

  /// The complete manifest labels, with `directionSource`, or nil while anything is missing.
  public func labels(takenAt: UTCTimestamp) -> PackageManifest.PhotoLabels? {
    guard let room = cleanRoom, let direction, let subject else { return nil }
    return PackageManifest.PhotoLabels(
      room: room, direction: direction, subject: subject, takenAt: takenAt,
      directionSource: savedDirectionSource)
  }

  /// The next photo keeps the room (it stays selected: people usually shoot several photos per
  /// room); direction (re-filled from the compass at the next shutter) and subject start empty.
  public func forNextPhoto() -> PhotoLabelDraft {
    PhotoLabelDraft(room: room)
  }
}

/// Wording of the chips on the labeling screen.
extension PhotoDirection {
  public var chipTitle: String { rawValue }

  /// What VoiceOver reads for the segment.
  public var spokenTitle: String {
    switch self {
    case .north: return "North"
    case .east: return "East"
    case .south: return "South"
    case .west: return "West"
    }
  }
}

extension PhotoSubject {
  public var chipTitle: String {
    switch self {
    case .opening: return "Opening"
    case .cabinetry: return "Cabinetry"
    case .ceiling: return "Ceiling"
    case .fixture: return "Fixture"
    case .equipment: return "Equipment"
    case .defect: return "Defect"
    case .general: return "General"
    }
  }

  /// The seven subjects as the labeling screen shows them, all at once (no More).
  public static let primaryChoices: [PhotoSubject] = [
    .opening, .cabinetry, .ceiling, .fixture, .defect, .general, .equipment,
  ]
}
