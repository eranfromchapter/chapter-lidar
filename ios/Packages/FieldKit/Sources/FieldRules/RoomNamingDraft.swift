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
    /// The checklist still asks a photo of this room (`PhotoCoverage`): the sheet says so, so
    /// the room a "Closet has no photo" row is about is easy to find.
    public var needsPhoto: Bool
    /// The name in the text field.
    public var name: String

    public var id: String { "\(captureId.rawValue)/\(roomId)" }

    public init(
      captureId: LowercaseUUID, roomId: String, scannedLabel: String, currentLabel: String,
      detail: String? = nil, needsPhoto: Bool = false
    ) {
      self.captureId = captureId
      self.roomId = roomId
      self.scannedLabel = scannedLabel
      self.currentLabel = currentLabel
      self.detail = detail
      self.needsPhoto = needsPhoto
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
    /// Another room of the same capture has this name: the other room's name as it is written
    /// there, and the label the scan gave that room, which tells the operator which room it is.
    case duplicate(name: String, otherScannedLabel: String)

    public var text: String {
      switch self {
      case .empty: return "Enter a name"
      case .tooLong: return "Use at most \(RoomNamingDraft.maximumLength) characters"
      case .duplicate(let name, let other):
        return "The room scanned as \(other) is already called \(name)"
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
  /// The room (`Room.id`) the sheet opens at: the room a failing checklist row names, or the
  /// room the photo step was opened for. Nil to open at the top.
  public var focusRoomId: String?
  /// When each room's name was last set (`setName`), counting up: which of two rooms with the
  /// same name the operator changed last.
  private var editOrder: [String: Int] = [:]
  private var edits = 0

  public init(captures: [Capture], focusRoomId: String? = nil, id: UUID = UUID()) {
    self.id = id
    self.captures = captures.filter { !$0.rooms.isEmpty }
    let rooms = self.captures.flatMap(\.rooms)
    self.focusRoomId = rooms.contains { $0.id == focusRoomId } ? focusRoomId : nil
  }

  public var rooms: [Room] { captures.flatMap(\.rooms) }

  public var isEmpty: Bool { captures.isEmpty }

  /// Sets the text field of the room with `id` (`Room.id`).
  public mutating func setName(_ name: String, room id: String) {
    for c in captures.indices {
      for r in captures[c].rooms.indices where captures[c].rooms[r].id == id {
        captures[c].rooms[r].name = name
        edits += 1
        editOrder[id] = edits
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
  ///
  /// A name another room of the capture already has is shown on one field only: the one of
  /// those rooms the operator changed last (the field being typed in), not on a room the
  /// operator did not touch. `hasIssues` counts every repeated name either way.
  public func issue(room id: String) -> Issue? {
    for capture in captures {
      guard let room = capture.rooms.first(where: { $0.id == id }) else { continue }
      let trimmed = room.name.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return .empty }
      if trimmed.unicodeScalars.count > Self.maximumLength { return .tooLong }
      let key = Self.key(trimmed)
      let others = capture.rooms.filter { $0.id != id && Self.key($0.name) == key }
      guard let other = others.first else { return nil }
      let mine = editOrder[id] ?? 0
      guard others.allSatisfy({ (editOrder[$0.id] ?? 0) < mine }) || isUntouchedGroup(others, id)
      else { return nil }
      return .duplicate(
        name: other.name.trimmingCharacters(in: .whitespacesAndNewlines),
        otherScannedLabel: other.scannedLabel)
    }
    return nil
  }

  /// No room of a repeated name was set by the operator (the sheet was opened with two rooms
  /// of one name): every one of them shows it.
  private func isUntouchedGroup(_ others: [Room], _ id: String) -> Bool {
    editOrder[id] == nil && others.allSatisfy { editOrder[$0.id] == nil }
  }

  /// True when two rooms of one capture have the same name (`key(_:)`).
  public var hasDuplicates: Bool {
    captures.contains { capture in
      let keys = capture.rooms.map { Self.key($0.name) }.filter { !$0.isEmpty }
      return Set(keys).count < keys.count
    }
  }

  public var hasIssues: Bool { hasDuplicates || rooms.contains { issue(room: $0.id) != nil } }

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
