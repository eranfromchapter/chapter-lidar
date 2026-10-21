import CaptureContract
import CaptureModelMapping
import FieldRules
import Foundation
import PhotoStore
import PlanExport

/// The operator's room names of one visit, kept on the phone in `<visit>/room-names.json`
/// (`VisitWorkspace.roomNamesURL`) so they survive a relaunch, "Add more rooms" and "My scans".
///
/// Per capture, a list of `RoomName` (room id, the label the scan gives that room, the name).
/// A name is applied only to the room with that id that still has that derived label
/// (`RoomNaming.overrides`), so a different split after an app update never puts a name on the
/// wrong room. App-private: the file is not part of the sealed package (the contract schema is
/// unchanged); the names reach the package as the capture models' room labels and the photos'
/// room labels.
public struct VisitRoomNames: Codable, Equatable, Sendable {
  public static let fileName = "room-names.json"
  public static let currentVersion = 1

  public var version: Int
  /// Names per capture id (lowercase UUID string).
  public var captures: [String: [RoomName]]

  public init(captures: [String: [RoomName]] = [:]) {
    self.version = Self.currentVersion
    self.captures = captures
  }

  public func names(for captureId: LowercaseUUID) -> [RoomName] {
    captures[captureId.rawValue] ?? []
  }

  /// Sets the name of one room. A blank name, or the derived label itself, removes the entry,
  /// so the room is labelled and typed by the scan again.
  public mutating func setName(
    _ name: String, roomId: String, derivedLabel: String, captureId: LowercaseUUID
  ) {
    var list = captures[captureId.rawValue] ?? []
    list.removeAll { $0.roomId == roomId }
    if let cleaned = RoomNaming.cleaned(name), cleaned != derivedLabel {
      list.append(RoomName(roomId: roomId, derivedLabel: derivedLabel, name: cleaned))
    }
    captures[captureId.rawValue] = list.isEmpty ? nil : list
  }

  /// The names in `workspace`; empty when the visit has none yet. Throws when the file exists
  /// but cannot be read.
  public static func load(from workspace: VisitWorkspace) throws -> VisitRoomNames {
    let url = workspace.roomNamesURL
    guard FileManager.default.fileExists(atPath: url.path) else { return VisitRoomNames() }
    return try JSONDecoder().decode(VisitRoomNames.self, from: Data(contentsOf: url))
  }

  /// Writes the names into `workspace`, replacing the file in one step.
  public func save(to workspace: VisitWorkspace) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try FileManager.default.createDirectory(at: workspace.root, withIntermediateDirectories: true)
    try encoder.encode(self).write(to: workspace.roomNamesURL, options: .atomic)
  }
}

/// One room of a capture as the visit's screens show it.
public struct VisitRoom: Hashable, Sendable {
  /// The capture model id, for example `room-3`.
  public var id: String
  /// The label the scan gives the room without names, for example `Closet`.
  public var derivedLabel: String
  /// The label now, with the operator's name, for example `Shower`.
  public var label: String
  /// Floor area of the room's outline, in square metres.
  public var areaM2: Double

  public init(id: String, derivedLabel: String, label: String, areaM2: Double) {
    self.id = id
    self.derivedLabel = derivedLabel
    self.label = label
    self.areaM2 = areaM2
  }
}

/// The rooms of a visit's captures with the operator's names, and how a rename reaches the
/// names file, the capture model and the photos already labeled with the old name.
public struct VisitRooms: Sendable {
  public let builder: VisitPackageBuilder
  public private(set) var names: VisitRoomNames
  /// Rooms per capture, in room order; a capture whose model could not be made has none.
  public private(set) var rooms: [LowercaseUUID: [VisitRoom]] = [:]

  /// Loads the names already in the visit's workspace (none for a new visit, or when the file
  /// cannot be read).
  public init(builder: VisitPackageBuilder) {
    self.builder = builder
    self.names = (try? VisitRoomNames.load(from: builder.workspace)) ?? VisitRoomNames()
  }

  /// Room labels of a capture, in room order: the capture model's labels for the checklist and
  /// the Room chips.
  public func labels(of captureId: LowercaseUUID) -> [String] {
    (rooms[captureId] ?? []).map(\.label)
  }

  /// Maps a capture with the visit's names and remembers its rooms. Returns the named model.
  @discardableResult
  public mutating func load(_ capture: CaptureRecord.Capture, visitId: LowercaseUUID) throws
    -> CaptureModel
  {
    let named = try builder.namedCaptureModel(
      of: capture, visitId: visitId, names: names.names(for: capture.captureId))
    rooms[capture.captureId] = Self.rooms(of: named)
    return named.model
  }

  /// Applies the sheet's renames: saves the names in the workspace, maps each renamed capture
  /// again and relabels the photos whose room was a renamed room's old label (only the photo
  /// records change; see `PhotoRecordStore.relabelRooms`). Returns the new models of the
  /// renamed captures. When the names cannot be saved, or the photos cannot be relabeled,
  /// nothing is left changed and the error is thrown.
  @discardableResult
  public mutating func rename(
    _ renames: [RoomRename], captures: [CaptureRecord.Capture], visitId: LowercaseUUID,
    photos: PhotoRecordStore
  ) throws -> [LowercaseUUID: CaptureModel] {
    let previousNames = names
    var next = names
    for rename in renames {
      next.setName(
        rename.to, roomId: rename.roomId, derivedLabel: rename.scannedLabel,
        captureId: rename.captureId)
    }
    let renamed = Set(renames.map(\.captureId))
    var models: [LowercaseUUID: CaptureModel] = [:]
    var nextRooms = rooms
    var relabels: [(captureId: LowercaseUUID, renames: [(from: String, to: String)])] = []
    for capture in captures where renamed.contains(capture.captureId) {
      let named = try builder.namedCaptureModel(
        of: capture, visitId: visitId, names: next.names(for: capture.captureId))
      let after = Self.rooms(of: named)
      let pairs = Self.labelChanges(before: rooms[capture.captureId] ?? [], after: after)
      models[capture.captureId] = named.model
      nextRooms[capture.captureId] = after
      if !pairs.isEmpty { relabels.append((capture.captureId, pairs)) }
    }

    try next.save(to: builder.workspace)
    var done: [(captureId: LowercaseUUID, renames: [(from: String, to: String)])] = []
    do {
      for relabel in relabels {
        try photos.relabelRooms(captureId: relabel.captureId, renames: relabel.renames)
        done.append(relabel)
      }
    } catch {
      for relabel in done.reversed() {
        _ = try? photos.relabelRooms(
          captureId: relabel.captureId, renames: relabel.renames.map { (from: $0.to, to: $0.from) })
      }
      try? previousNames.save(to: builder.workspace)
      throw error
    }
    names = next
    rooms = nextRooms
    return models
  }

  /// The "Rename rooms" sheet for `captures` (those with rooms), each room's floor area in the
  /// capture's display units.
  public func draft(for captures: [CaptureRecord.Capture]) -> RoomNamingDraft {
    RoomNamingDraft(
      captures: captures.map { capture in
        let formatter = UnitFormatter(system: capture.units.display)
        return RoomNamingDraft.Capture(
          captureId: capture.captureId, label: capture.label,
          rooms: (rooms[capture.captureId] ?? []).map { room in
            RoomNamingDraft.Room(
              captureId: capture.captureId, roomId: room.id, scannedLabel: room.derivedLabel,
              currentLabel: room.label,
              detail: room.areaM2 > 0 ? formatter.roomArea(room.areaM2) : nil)
          })
      })
  }

  /// The labels that changed between two room lists of one capture, matched by room id:
  /// (old label, new label) in room order.
  public static func labelChanges(before: [VisitRoom], after: [VisitRoom]) -> [(
    from: String, to: String
  )] {
    after.compactMap { room in
      guard let old = before.first(where: { $0.id == room.id }), old.label != room.label else {
        return nil
      }
      return (from: old.label, to: room.label)
    }
  }

  static func rooms(of named: NamedCaptureModel) -> [VisitRoom] {
    named.model.rooms.enumerated().map { index, room in
      VisitRoom(
        id: room.id,
        derivedLabel: named.derivedLabels.indices.contains(index)
          ? named.derivedLabels[index] : room.label,
        label: room.label, areaM2: area(room.polygon))
    }
  }

  /// Area of a floor outline in plan (x, z), square metres.
  static func area(_ polygon: [Vec3]) -> Double {
    guard polygon.count >= 3 else { return 0 }
    var twice = 0.0
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      twice += a.x * b.z - b.x * a.z
    }
    return abs(twice) / 2
  }
}
