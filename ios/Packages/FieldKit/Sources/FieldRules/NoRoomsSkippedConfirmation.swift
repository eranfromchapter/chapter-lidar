import CaptureContract
import Foundation

/// The operator's tap on "No rooms skipped" in the before-leaving checklist, kept as a value so
/// the screen model can feed `ChecklistInput.noRoomsSkippedConfirmed` without ever defaulting it.
///
/// Rule: the tap covers exactly the captures that existed when it was made. It stops counting as
/// soon as the visit has a different set of capture ids (a new floor or area from "Add more
/// rooms", or a re-scan) or any capture lists an omitted or inaccessible room. Then the operator
/// must record the skipped rooms or tap again. Label and order changes do not affect it; the
/// skipped-rooms rule does not look at them.
public struct NoRoomsSkippedConfirmation: Hashable, Sendable {
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
  /// same captures as at the tap and none of them lists a skipped room.
  public func isConfirmed(for record: CaptureRecord) -> Bool {
    guard let confirmedCaptureIds else { return false }
    let hasNote = record.captures.contains {
      !$0.omittedRooms.isEmpty || !$0.inaccessibleRooms.isEmpty
    }
    return !hasNote && Set(record.captures.map(\.captureId)) == confirmedCaptureIds
  }
}
