import CaptureContract
import CaptureModelMapping
import FieldRules
import Foundation
import PhotoStore
import PlanExport

/// The operator's room names of one visit, kept on the phone in `<visit>/room-names.json`
/// (`VisitWorkspace.roomNamesURL`) so they survive a relaunch, "Add more rooms" and "My scans".
///
/// Per capture, a list of `RoomName` (room id, the label the scan gives that room, where the
/// room is and how big, the name). A name is applied only to the room with that id that still
/// has that derived label and footprint (`RoomNaming.applies`), so a different split after an
/// app update does not put a name on another room. App-private: the file is not part of the
/// sealed package (the contract schema is unchanged); the names reach the package as the
/// capture models' room labels and the photos' and controls' room labels.
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

  /// Sets the name of one room, kept with the room's `footprint` (where it is and how big). A
  /// blank name, or the derived label itself, removes the entry, so the room is labelled and
  /// typed by the scan again.
  public mutating func setName(
    _ name: String, roomId: String, derivedLabel: String, footprint: RoomFootprint?,
    captureId: LowercaseUUID
  ) {
    var list = captures[captureId.rawValue] ?? []
    list.removeAll { $0.roomId == roomId }
    if let cleaned = RoomNaming.cleaned(name), cleaned != derivedLabel {
      list.append(
        RoomName(roomId: roomId, derivedLabel: derivedLabel, name: cleaned, footprint: footprint))
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
  /// Where the room is and how big, kept with its name; nil when the outline has no area.
  public var footprint: RoomFootprint?

  public init(
    id: String, derivedLabel: String, label: String, areaM2: Double,
    footprint: RoomFootprint? = nil
  ) {
    self.id = id
    self.derivedLabel = derivedLabel
    self.label = label
    self.areaM2 = areaM2
    self.footprint = footprint
  }
}

/// What a rename changed besides the names file and the photos.
public struct RoomRenameResult: Sendable {
  /// The new capture models of the renamed captures.
  public var models: [LowercaseUUID: CaptureModel]
  /// The field controls with the new room names, already written; nil when no control named a
  /// renamed room.
  public var controls: FieldControls?
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
  /// again, relabels the photos whose room was a renamed room's old label (only the photo
  /// records change, all captures in one write; see `PhotoRecordStore.relabelRooms`), and,
  /// when the visit has `controls`, moves the controls that named an old label to the new one
  /// (`FieldControlsEditor.renameRooms`) and hands them to `writeControls`.
  ///
  /// When a step fails, the steps before it are undone (the names file and the photo labels
  /// are written back exactly as they were) and the error is thrown. Only when writing a file
  /// back also fails can something stay changed.
  @discardableResult
  public mutating func rename(
    _ renames: [RoomRename], captures: [CaptureRecord.Capture], visitId: LowercaseUUID,
    photos: PhotoRecordStore, controls: FieldControls? = nil,
    writeControls: (FieldControls) throws -> Void = { _ in }
  ) throws -> RoomRenameResult {
    let previousNames = names
    var next = names
    for rename in renames {
      let footprint = rooms[rename.captureId]?.first { $0.id == rename.roomId }?.footprint
      next.setName(
        rename.to, roomId: rename.roomId, derivedLabel: rename.scannedLabel, footprint: footprint,
        captureId: rename.captureId)
    }
    let renamed = Set(renames.map(\.captureId))
    var models: [LowercaseUUID: CaptureModel] = [:]
    var nextRooms = rooms
    var relabels: [LowercaseUUID: [(from: String, to: String)]] = [:]
    var editor = controls.map(FieldControlsEditor.init(controls:))
    for capture in captures where renamed.contains(capture.captureId) {
      let named = try builder.namedCaptureModel(
        of: capture, visitId: visitId, names: next.names(for: capture.captureId))
      let before = rooms[capture.captureId] ?? []
      let after = Self.rooms(of: named)
      let pairs = Self.labelChanges(before: before, after: after)
      models[capture.captureId] = named.model
      nextRooms[capture.captureId] = after
      if !pairs.isEmpty {
        relabels[capture.captureId] = pairs
        editor?.renameRooms(
          captureId: capture.captureId, labels: before.map(\.label), renames: pairs)
      }
    }
    let nextControls = editor.flatMap { $0.controls == controls ? nil : $0.controls }

    try next.save(to: builder.workspace)
    let previousPhotos = photos.records
    do {
      if !relabels.isEmpty { try photos.relabelRooms(relabels) }
      if let nextControls {
        do {
          try writeControls(nextControls)
        } catch {
          try? photos.restoreLabels(previousPhotos)
          throw error
        }
      }
    } catch {
      try? previousNames.save(to: builder.workspace)
      throw error
    }
    names = next
    rooms = nextRooms
    return RoomRenameResult(models: models, controls: nextControls)
  }

  /// The "Rename rooms" sheet for `captures` (those with rooms): each room's floor area in the
  /// capture's display units, and whether it still needs a photo (`PhotoCoverage`, the
  /// checklist's rule, from `photos`). The sheet opens at the room labeled `focus` of the
  /// capture `focusCapture` (the room the checklist row or the photo step names), when given.
  public func draft(
    for captures: [CaptureRecord.Capture], photos: [PhotoRecord] = [],
    focus: (captureId: LowercaseUUID, room: String)? = nil
  ) -> RoomNamingDraft {
    var focusId: String?
    let draftCaptures = captures.map { capture in
      let formatter = UnitFormatter(system: capture.units.display)
      let list = rooms[capture.captureId] ?? []
      let coverage = PhotoCoverage.status(
        rooms: list.map(\.label), photos: photos.filter { $0.captureId == capture.captureId })
      let draftRooms = list.map { room in
        RoomNamingDraft.Room(
          captureId: capture.captureId, roomId: room.id, scannedLabel: room.derivedLabel,
          currentLabel: room.label,
          detail: room.areaM2 > 0 ? formatter.roomArea(room.areaM2) : nil,
          needsPhoto: coverage.needsPhoto(room.label))
      }
      if let focus, focus.captureId == capture.captureId, focusId == nil,
        let room = draftRooms.first(where: {
          PhotoCoverage.key($0.currentLabel) == PhotoCoverage.key(focus.room)
        })
      {
        focusId = room.id
      }
      return RoomNamingDraft.Capture(
        captureId: capture.captureId, label: capture.label, rooms: draftRooms)
    }
    return RoomNamingDraft(captures: draftCaptures, focusRoomId: focusId)
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
      let scanned = named.scannedRooms.indices.contains(index) ? named.scannedRooms[index] : nil
      return VisitRoom(
        id: room.id, derivedLabel: scanned?.derivedLabel ?? room.label, label: room.label,
        areaM2: area(room.polygon), footprint: scanned?.footprint)
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
