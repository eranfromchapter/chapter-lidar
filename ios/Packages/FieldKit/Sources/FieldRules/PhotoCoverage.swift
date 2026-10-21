import Foundation

/// Which rooms of one capture have a photo. This is the rule of the checklist's "A photo for
/// every room" (`ChecklistRules`); the photo step uses it for "Still needs a photo: Shower" and
/// the Room chips, and the photo store uses its `key(_:)` to relabel photos after a rename.
public enum PhotoCoverage {
  /// A room label as the rule compares it: without white space at either end, ignoring case.
  public static func key(_ room: String) -> String {
    room.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// The rooms of a capture as the rule counts them, in order: blank labels left out, and a
  /// label repeated (same `key(_:)`) counted once.
  public static func rooms(_ labels: [String]) -> [String] {
    var seen = Set<String>()
    return labels.filter { !key($0).isEmpty && seen.insert(key($0)).inserted }
  }

  /// True when one of `photos` is labeled with `room` (same `key(_:)`).
  public static func hasPhoto(_ room: String, in photos: [PhotoRecord]) -> Bool {
    let wanted = key(room)
    return photos.contains { key($0.room) == wanted }
  }

  /// What one capture still needs. `rooms` are the room labels of its capture model and
  /// `photos` the photos of that capture.
  public static func status(rooms labels: [String], photos: [PhotoRecord]) -> Status {
    let rooms = rooms(labels)
    return Status(
      rooms: rooms, roomsWithoutPhoto: rooms.filter { !hasPhoto($0, in: photos) },
      needsAnyPhoto: rooms.isEmpty && photos.isEmpty)
  }

  /// The coverage of one capture.
  public struct Status: Hashable, Sendable {
    /// The rooms the rule counts (`PhotoCoverage.rooms(_:)`).
    public var rooms: [String]
    /// Rooms with no photo labeled with their name, in room order.
    public var roomsWithoutPhoto: [String]
    /// The capture has no room list and no photo: it needs a photo of any kind.
    public var needsAnyPhoto: Bool

    public var isComplete: Bool { roomsWithoutPhoto.isEmpty && !needsAnyPhoto }

    /// True when `room` is one of the rooms that still need a photo.
    public func needsPhoto(_ room: String) -> Bool {
      let wanted = PhotoCoverage.key(room)
      return roomsWithoutPhoto.contains { PhotoCoverage.key($0) == wanted }
    }

    /// The line under the photo step's title: "Still needs a photo: Shower",
    /// "Still needs a photo: Bedroom, Shower", "Still needs a photo" (no room list, no photo
    /// yet) or "Every room has a photo".
    public var text: String {
      if needsAnyPhoto { return "Still needs a photo" }
      if roomsWithoutPhoto.isEmpty { return "Every room has a photo" }
      return "Still needs a photo: " + roomsWithoutPhoto.joined(separator: ", ")
    }
  }
}
