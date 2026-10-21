import CaptureContract
import Foundation

/// One room renamed by the operator, as the "Rename rooms" sheet hands it to the app.
public struct RoomRename: Hashable, Sendable {
  public var captureId: LowercaseUUID
  /// The capture model id of the room, for example `room-3`.
  public var roomId: String
  /// The label the scan gives the room without names, for example `Closet`.
  public var scannedLabel: String
  /// The room's label before this rename (an earlier name, or `scannedLabel`).
  public var from: String
  /// The new name, trimmed, for example `Shower`.
  public var to: String

  public init(
    captureId: LowercaseUUID, roomId: String, scannedLabel: String, from: String, to: String
  ) {
    self.captureId = captureId
    self.roomId = roomId
    self.scannedLabel = scannedLabel
    self.from = from
    self.to = to
  }
}

/// The "Rename rooms" sheet: the rooms of one or more captures, each with the name the operator
/// types (prefilled with its current label), checked before it can be saved. Pure; the app
/// applies `changes` (room labels in the capture model, the photos already labeled with the old
/// name, and the names it keeps per visit).
public struct RoomNamingDraft: Hashable, Sendable, Identifiable {
  public struct Room: Hashable, Sendable, Identifiable {
    public var captureId: LowercaseUUID
    public var roomId: String
    /// The label the scan gives the room, for example `Closet`.
    public var scannedLabel: String
    /// The room's label now: the operator's earlier name, or `scannedLabel`.
    public var currentLabel: String
    /// What tells this room apart from the others, for example its floor area ("1.9 m²").
    public var detail: String?
    /// The name in the text field.
    public var name: String

    public var id: String { "\(captureId.rawValue)/\(roomId)" }

    public init(
      captureId: LowercaseUUID, roomId: String, scannedLabel: String, currentLabel: String,
      detail: String? = nil
    ) {
      self.captureId = captureId
      self.roomId = roomId
      self.scannedLabel = scannedLabel
      self.currentLabel = currentLabel
      self.detail = detail
      self.name = currentLabel
    }

    /// "Scanned as Closet · 1.9 m²": what the scan called the room, and its detail, so the
    /// operator knows which room the field names.
    public var caption: String {
      var parts = ["Scanned as \(scannedLabel)"]
      if let detail, !detail.isEmpty { parts.append(detail) }
      return parts.joined(separator: " \u{00B7} ")
    }
  }

  public struct Capture: Hashable, Sendable, Identifiable {
    public var captureId: LowercaseUUID
    /// The floor or area label, for example "Room Mexico".
    public var label: String
    public var rooms: [Room]

    public var id: LowercaseUUID { captureId }

    public init(captureId: LowercaseUUID, label: String, rooms: [Room]) {
      self.captureId = captureId
      self.label = label
      self.rooms = rooms
    }
  }

  /// Why a name cannot be saved.
  public enum Issue: Hashable, Sendable {
    case empty
    case tooLong
    /// Another room of the same capture has this name.
    case duplicate(String)

    public var text: String {
      switch self {
      case .empty: return "Enter a name"
      case .tooLong: return "Use at most \(RoomNamingDraft.maximumLength) characters"
      case .duplicate(let name): return "Another room is already called \(name)"
      }
    }
  }

  /// The longest name: the capture-model schema's room label (100 Unicode scalars), which is
  /// also within the 100 characters of a photo's room label.
  public static let maximumLength = 100

  /// Quick names the sheet offers under every room (RoomPlan has no shower, pantry or entry).
  public static let suggestions = [
    "Shower", "Closet", "Bathroom", "Half bath", "Hallway", "Entry", "Pantry", "Laundry",
    "Storage",
  ]

  public let id: UUID
  public var captures: [Capture]

  public init(captures: [Capture], id: UUID = UUID()) {
    self.id = id
    self.captures = captures.filter { !$0.rooms.isEmpty }
  }

  public var rooms: [Room] { captures.flatMap(\.rooms) }

  public var isEmpty: Bool { captures.isEmpty }

  /// Sets the text field of the room with `id` (`Room.id`).
  public mutating func setName(_ name: String, room id: String) {
    for c in captures.indices {
      for r in captures[c].rooms.indices where captures[c].rooms[r].id == id {
        captures[c].rooms[r].name = name
      }
    }
  }

  /// A name as two room labels are compared for uniqueness (as the capture model's labels are):
  /// lower case, white space at either end dropped and runs of it as one space.
  public static func key(_ name: String) -> String {
    name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// `name` trimmed, or nil when it is empty or too long.
  public static func cleaned(_ name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= maximumLength else { return nil }
    return trimmed
  }

  /// What is wrong with the name of the room with `id`; nil when it can be saved.
  public func issue(room id: String) -> Issue? {
    for capture in captures {
      guard let room = capture.rooms.first(where: { $0.id == id }) else { continue }
      let trimmed = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return .empty }
      if trimmed.unicodeScalars.count > Self.maximumLength { return .tooLong }
      let key = Self.key(trimmed)
      if capture.rooms.contains(where: { $0.id != id && Self.key($0.name) == key }) {
        return .duplicate(trimmed)
      }
      return nil
    }
    return nil
  }

  public var hasIssues: Bool { rooms.contains { issue(room: $0.id) != nil } }

  /// The rooms whose name differs from their current label, in room order.
  public var changes: [RoomRename] {
    rooms.compactMap { room in
      guard let name = Self.cleaned(room.name), name != room.currentLabel else { return nil }
      return RoomRename(
        captureId: room.captureId, roomId: room.roomId, scannedLabel: room.scannedLabel,
        from: room.currentLabel, to: name)
    }
  }

  /// "Save names" is enabled: something changed and every name can be saved.
  public var canSave: Bool { !changes.isEmpty && !hasIssues }
}
