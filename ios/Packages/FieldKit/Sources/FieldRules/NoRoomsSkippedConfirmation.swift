import CaptureContract
import Foundation

/// The operator's tap on "All rooms scanned" in the before-leaving checklist, kept as a value so
/// the screen model can feed `ChecklistInput.noRoomsSkippedConfirmed` without ever defaulting it.
///
/// Rule: the tap covers exactly the captures that existed when it was made. It stops counting as
/// soon as the visit has a different set of capture ids (a new floor or area from "Add more
/// rooms", or a re-scan) or any capture lists an omitted or inaccessible room. Then the operator
/// must record the rooms not scanned or tap again. Label and order changes do not affect it; the
/// rule does not look at them.
///
/// `Codable` for the visit file (`visit.json`): `{"confirmedCaptureIds": ["…", "…"]}`, the ids
/// sorted so the file is byte-stable; the key is absent until the operator confirms.
public struct NoRoomsSkippedConfirmation: Hashable, Sendable, Codable {
  /// Capture ids at the moment of the tap; nil until the operator confirms.
  public private(set) var confirmedCaptureIds: Set<LowercaseUUID>?

  /// Not confirmed. Only `confirm(for:)` changes that.
  public init() {
    confirmedCaptureIds = nil
  }

  /// Records the operator's explicit tap for the record's current captures.
  public mutating func confirm(for record: CaptureRecord) {
    confirmedCaptureIds = Set(record.captures.map(\.captureId))
  }

  /// Forgets the tap.
  public mutating func clear() {
    confirmedCaptureIds = nil
  }

  /// The value for `ChecklistInput.noRoomsSkippedConfirmed`: true only while the record has the
  /// same captures as at the tap and none of them lists a room not scanned.
  public func isConfirmed(for record: CaptureRecord) -> Bool {
    guard let confirmedCaptureIds else { return false }
    let hasNote = record.captures.contains {
      !$0.omittedRooms.isEmpty || !$0.inaccessibleRooms.isEmpty
    }
    return !hasNote && Set(record.captures.map(\.captureId)) == confirmedCaptureIds
  }

  // MARK: Codable

  private enum CodingKeys: String, CodingKey {
    case confirmedCaptureIds
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    confirmedCaptureIds = try container.decodeIfPresent(
      [LowercaseUUID].self, forKey: .confirmedCaptureIds
    ).map(Set.init)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(
      confirmedCaptureIds?.sorted { $0.rawValue < $1.rawValue }, forKey: .confirmedCaptureIds)
  }
}
