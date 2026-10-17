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
/// "toward <wall/landmark>" value, so none is offered.
public struct PhotoLabelDraft: Hashable, Sendable {
  public static let maximumRoomLength = 100

  public var room: String?
  public var direction: PhotoDirection?
  public var subject: PhotoSubject?

  public init(room: String? = nil, direction: PhotoDirection? = nil, subject: PhotoSubject? = nil) {
    self.room = room
    self.direction = direction
    self.subject = subject
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

  /// The complete manifest labels, or nil while anything is missing.
  public func labels(takenAt: UTCTimestamp) -> PackageManifest.PhotoLabels? {
    guard let room = cleanRoom, let direction, let subject else { return nil }
    return PackageManifest.PhotoLabels(
      room: room, direction: direction, subject: subject, takenAt: takenAt)
  }

  /// Next photo keeps the room (people usually shoot several photos per room) but must be
  /// labeled again for direction and subject.
  public func forNextPhoto() -> PhotoLabelDraft {
    PhotoLabelDraft(room: room)
  }
}

/// Wording of the chips on the labeling screen.
extension PhotoDirection {
  public var chipTitle: String { rawValue }
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

  /// The six subjects the design shows as chips. `equipment` is reached through More.
  public static let primaryChoices: [PhotoSubject] = [
    .opening, .cabinetry, .ceiling, .fixture, .defect, .general,
  ]
  public static let moreChoices: [PhotoSubject] = [.equipment]
}
