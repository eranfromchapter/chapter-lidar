import CaptureContract
import Foundation

/// The operator's name for one room of a capture, for example the room the shape alone called
/// "Closet" that is really a shower. The app keeps these per visit and passes them to the mapper
/// as `MappingContext.roomLabels` through `RoomNaming`.
public struct RoomName: Codable, Hashable, Sendable {
  /// The capture model id of the room, for example `room-3`.
  public var roomId: String
  /// The label the scan gives that room without any name (`RoomTyping.labels` with no
  /// overrides), for example `Closet`. A name is applied only while the room with `roomId`
  /// still has this label, so a different split after an app update never puts a name on the
  /// wrong room.
  public var derivedLabel: String
  /// The operator's name, for example `Shower`.
  public var name: String

  public init(roomId: String, derivedLabel: String, name: String) {
    self.roomId = roomId
    self.derivedLabel = derivedLabel
    self.name = name
  }
}

/// A capture model with the operator's room names applied.
public struct NamedCaptureModel: Sendable {
  /// The capture model, labelled with the names (and typed by them, see
  /// `RoomTyping.renamedByOperator`).
  public var model: CaptureModel
  /// Per room, in room order: the label the scan gives the room without names.
  public var derivedLabels: [String]

  public init(model: CaptureModel, derivedLabels: [String]) {
    self.model = model
    self.derivedLabels = derivedLabels
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

  /// The overrides (`MappingContext.roomLabels`, in room order) for rooms with these ids and
  /// derived labels: per room, the name of the last entry with the room's id and exactly the
  /// room's derived label; "" for every other room. An entry whose room is gone or now has
  /// another derived label is ignored, and so is a name that `cleaned(_:)` refuses.
  public static func overrides(
    rooms: [(id: String, derivedLabel: String)], names: [RoomName]
  ) -> [String] {
    rooms.map { room in
      names.last { $0.roomId == room.id && $0.derivedLabel == room.derivedLabel }
        .flatMap { cleaned($0.name) } ?? ""
    }
  }

  /// The entries of `names` that apply to rooms with these ids and derived labels.
  public static func applicable(
    _ names: [RoomName], rooms: [(id: String, derivedLabel: String)]
  ) -> [RoomName] {
    names.filter { name in
      cleaned(name.name) != nil
        && rooms.contains { $0.id == name.roomId && $0.derivedLabel == name.derivedLabel }
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
    let derivedLabels = derived.rooms.map(\.label)
    let roomLabels = overrides(
      rooms: derived.rooms.map { (id: $0.id, derivedLabel: $0.label) }, names: names)
    guard roomLabels.contains(where: { !$0.isEmpty }) else {
      return NamedCaptureModel(model: derived, derivedLabels: derivedLabels)
    }
    var named = context
    named.roomLabels = roomLabels
    return NamedCaptureModel(
      model: try CaptureModelMapper.map(document, context: named), derivedLabels: derivedLabels)
  }
}
