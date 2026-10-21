import CaptureContract
import Foundation

/// Where a room is and how big it is: the area and the centre of its floor outline in the
/// capture frame. With the room's id and derived label it tells whether a saved name still
/// belongs to the same room. The id and label alone do not: a room the scan leaves untyped is
/// "Room N" by its position, so after a different split another room can have both.
public struct RoomFootprint: Codable, Hashable, Sendable {
  /// Floor area, square metres.
  public var areaM2: Double
  /// Centre of the floor area in plan, metres, in the capture frame (x and z).
  public var centerX: Double
  public var centerZ: Double

  /// Largest distance between two centres that still counts as the same room, metres.
  public static let centerTolerance = 0.5
  /// Largest area difference that still counts as the same room: this share of the larger
  /// area, but at least `minimumAreaTolerance` square metres.
  public static let areaToleranceShare = 0.2
  public static let minimumAreaTolerance = 0.3

  public init(areaM2: Double, centerX: Double, centerZ: Double) {
    self.areaM2 = areaM2
    self.centerX = centerX
    self.centerZ = centerZ
  }

  /// The footprint of a capture-model room outline (plan x and z), rounded to the centimetre
  /// and the hundredth of a square metre so the saved file stays readable; nil for an outline
  /// with no area.
  public init?(polygon: [Vec3]) {
    guard polygon.count >= 3 else { return nil }
    var twiceArea = 0.0
    var sumX = 0.0
    var sumZ = 0.0
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      let cross = a.x * b.z - b.x * a.z
      twiceArea += cross
      sumX += (a.x + b.x) * cross
      sumZ += (a.z + b.z) * cross
    }
    guard abs(twiceArea) > 1e-9, twiceArea.isFinite else { return nil }
    func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
    self.init(
      areaM2: rounded(abs(twiceArea) / 2), centerX: rounded(sumX / (3 * twiceArea)),
      centerZ: rounded(sumZ / (3 * twiceArea)))
  }

  /// True when `other` is the same room: centres within `centerTolerance` and areas within
  /// the area tolerance.
  public func matches(_ other: RoomFootprint) -> Bool {
    let dx = centerX - other.centerX
    let dz = centerZ - other.centerZ
    let tolerance = max(
      Self.minimumAreaTolerance, Self.areaToleranceShare * max(areaM2, other.areaM2))
    return (dx * dx + dz * dz).squareRoot() <= Self.centerTolerance
      && abs(areaM2 - other.areaM2) <= tolerance
  }
}

/// The operator's name for one room of a capture, for example the room the shape alone called
/// "Closet" that is really a shower. The app keeps these per visit and passes them to the mapper
/// as `MappingContext.roomLabels` through `RoomNaming`.
public struct RoomName: Codable, Hashable, Sendable {
  /// The capture model id of the room, for example `room-3`.
  public var roomId: String
  /// The label the scan gives that room without any name (`RoomTyping.labels` with no
  /// overrides), for example `Closet`.
  public var derivedLabel: String
  /// The operator's name, for example `Shower`.
  public var name: String
  /// Where the room was and how big when it was named. A name is applied only while the room
  /// with `roomId` still has `derivedLabel` and this footprint (`RoomFootprint.matches`), so a
  /// different split after an app update does not put the name on another room. Nil in a name
  /// saved without it: then the id and the label are checked.
  public var footprint: RoomFootprint?

  public init(
    roomId: String, derivedLabel: String, name: String, footprint: RoomFootprint? = nil
  ) {
    self.roomId = roomId
    self.derivedLabel = derivedLabel
    self.name = name
    self.footprint = footprint
  }
}

/// A room as the scan makes it, before any name: what a saved `RoomName` is checked against.
public struct ScannedRoom: Hashable, Sendable {
  /// The capture model id, for example `room-3`.
  public var id: String
  /// The label without names, for example `Closet`.
  public var derivedLabel: String
  /// Nil when the outline has no area.
  public var footprint: RoomFootprint?

  public init(id: String, derivedLabel: String, footprint: RoomFootprint? = nil) {
    self.id = id
    self.derivedLabel = derivedLabel
    self.footprint = footprint
  }
}

/// A capture model with the operator's room names applied.
public struct NamedCaptureModel: Sendable {
  /// The capture model, labelled with the names (and typed by them, see
  /// `RoomTyping.renamedByOperator`).
  public var model: CaptureModel
  /// Per room, in room order: the room as the scan makes it without names.
  public var scannedRooms: [ScannedRoom]

  /// Per room, in room order: the label the scan gives the room without names.
  public var derivedLabels: [String] { scannedRooms.map(\.derivedLabel) }

  public init(model: CaptureModel, scannedRooms: [ScannedRoom]) {
    self.model = model
    self.scannedRooms = scannedRooms
  }
}

/// Applying the operator's room names: which name goes on which room, and the mapping with them.
/// Pure; the app stores the names (AppCore `VisitRoomNames`).
public enum RoomNaming {
  /// `name` without white space at either end, or nil when that is empty or longer than the
  /// capture-model schema allows a room label (`RoomTyping.maximumLabelLength` Unicode scalars).
  public static func cleaned(_ name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= RoomTyping.maximumLabelLength else {
      return nil
    }
    return trimmed
  }

  /// True when the saved `name` belongs to `room`: the same id, exactly the same derived label,
  /// and, when the name has a footprint, a footprint that matches the room's.
  public static func applies(_ name: RoomName, to room: ScannedRoom) -> Bool {
    guard name.roomId == room.id, name.derivedLabel == room.derivedLabel else { return false }
    guard let saved = name.footprint else { return true }
    guard let now = room.footprint else { return false }
    return saved.matches(now)
  }

  /// The overrides (`MappingContext.roomLabels`, in room order) for these rooms: per room, the
  /// name of the last entry that applies to it (`applies(_:to:)`); "" for every other room. An
  /// entry whose room is gone, now has another derived label or lies elsewhere is ignored, and
  /// so is a name that `cleaned(_:)` refuses.
  public static func overrides(rooms: [ScannedRoom], names: [RoomName]) -> [String] {
    rooms.map { room in
      names.last { applies($0, to: room) }.flatMap { cleaned($0.name) } ?? ""
    }
  }

  /// The entries of `names` that apply to one of these rooms.
  public static func applicable(_ names: [RoomName], rooms: [ScannedRoom]) -> [RoomName] {
    names.filter { name in
      cleaned(name.name) != nil && rooms.contains { applies(name, to: $0) }
    }
  }

  /// The rooms of a capture model as the scan makes them: ids, labels and footprints. Use it on
  /// a model mapped without names.
  public static func scannedRooms(of model: CaptureModel) -> [ScannedRoom] {
    model.rooms.map {
      ScannedRoom(id: $0.id, derivedLabel: $0.label, footprint: RoomFootprint(polygon: $0.polygon))
    }
  }

  /// The capture model of `document` with the operator's `names`. Maps once without names (the
  /// derived labels; `context.roomLabels` is not used), and again with the names that apply as
  /// `MappingContext.roomLabels` when there are any.
  public static func map(
    _ document: RoomPlanDocument, context: MappingContext, names: [RoomName]
  ) throws -> NamedCaptureModel {
    var plain = context
    plain.roomLabels = []
    let derived = try CaptureModelMapper.map(document, context: plain)
    let rooms = scannedRooms(of: derived)
    let roomLabels = overrides(rooms: rooms, names: names)
    guard roomLabels.contains(where: { !$0.isEmpty }) else {
      return NamedCaptureModel(model: derived, scannedRooms: rooms)
    }
    var named = context
    named.roomLabels = roomLabels
    return NamedCaptureModel(
      model: try CaptureModelMapper.map(document, context: named), scannedRooms: rooms)
  }
}
