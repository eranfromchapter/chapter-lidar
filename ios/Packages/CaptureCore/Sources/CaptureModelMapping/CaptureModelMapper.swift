import CaptureContract
import Foundation

/// What the mapper needs besides the RoomPlan geometry.
public struct MappingContext: Sendable {
  public var visitId: LowercaseUUID
  public var captureId: LowercaseUUID
  public var areaKey: String
  public var label: String
  /// Room labels in room order (RoomPlan does not name rooms). Missing entries become
  /// `Room 1`, `Room 2`, and so on.
  public var roomLabels: [String]
  public var refs: [CaptureModel.SourceRef]

  public init(
    visitId: LowercaseUUID, captureId: LowercaseUUID, areaKey: String, label: String,
    roomLabels: [String] = [], refs: [CaptureModel.SourceRef] = []
  ) {
    self.visitId = visitId
    self.captureId = captureId
    self.areaKey = areaKey
    self.label = label
    self.roomLabels = roomLabels
    self.refs = refs
  }
}

public enum MappingError: Error, Equatable, CustomStringConvertible {
  case noRooms
  case wallHasNoLength(surface: String)
  case roomHasNoWalls(roomIndex: Int)
  case roomHasNoOutline(roomIndex: Int)
  case openingHasNoWall(surface: String)

  public var description: String {
    switch self {
    case .noRooms: return "The RoomPlan capture has no rooms."
    case .wallHasNoLength(let surface): return "Wall \(surface) has no length or direction."
    case .roomHasNoWalls(let index): return "Room \(index + 1) has no walls."
    case .roomHasNoOutline(let index):
      return "Room \(index + 1) has no floor outline and its walls do not form a closed loop."
    case .openingHasNoWall(let surface):
      return "Opening \(surface) names no wall and does not lie on any wall."
    }
  }
}

/// RoomPlan geometry into the contract `CaptureModel`: metres, +Y up, one floor per capture, in
/// the capture's own frame. Pure functions; nothing here touches Apple frameworks.
///
/// Ids are numbered in document order across the whole capture: `room-1`, `wall-1`, `door-1`,
/// `window-1`, `opening-1`, `object-1`. A partition that two rooms both list appears once per
/// room, as RoomPlan reports it.
public enum CaptureModelMapper {
  /// Longest gap, in metres, between wall ends that still joins them when an outline has to be
  /// built from walls.
  static let chainToleranceM = 0.15

  public static func map(_ document: RoomPlanDocument, context: MappingContext) throws
    -> CaptureModel
  {
    guard !document.rooms.isEmpty else { throw MappingError.noRooms }

    var model = CaptureModel(
      visitId: context.visitId, captureId: context.captureId, areaKey: context.areaKey,
      label: context.label, refs: context.refs)

    // Pass 1: walls, so that openings in any room can find any wall.
    var placements: [WallPlacement] = []
    var wallIndexByRoom: [[Int]] = []
    var wallCounter = 0
    for (roomIndex, room) in document.rooms.enumerated() {
      guard !room.walls.isEmpty else { throw MappingError.roomHasNoWalls(roomIndex: roomIndex) }
      var indexes: [Int] = []
      for surface in room.walls {
        wallCounter += 1
        let placement = try wallPlacement(
          surface, id: "wall-\(wallCounter)", roomIndex: roomIndex)
        placements.append(placement)
        indexes.append(placements.count - 1)
        model.walls.append(
          CaptureModel.Wall(
            id: placement.id, start: placement.start.contractVec3, end: placement.end.contractVec3,
            heightM: placement.heightM.cleaned, thicknessM: max(0, surface.dimension(2)).cleaned,
            roomIds: ["room-\(roomIndex + 1)"], confidence: surface.confidence))
      }
      wallIndexByRoom.append(indexes)
    }

    // Object ids up front, so that an object can name a parent listed after it.
    var objectIdByIdentifier: [String: String] = [:]
    for (index, object) in document.rooms.flatMap(\.objects).enumerated()
    where objectIdByIdentifier[object.identifier] == nil {
      objectIdByIdentifier[object.identifier] = "object-\(index + 1)"
    }

    // Pass 2: rooms, openings, objects.
    var counters = ["door": 0, "window": 0, "opening": 0, "object": 0]
    func nextId(_ kind: String) -> String {
      counters[kind, default: 0] += 1
      return "\(kind)-\(counters[kind]!)"
    }
    for (roomIndex, room) in document.rooms.enumerated() {
      let roomId = "room-\(roomIndex + 1)"
      let roomPlacements = wallIndexByRoom[roomIndex].map { placements[$0] }
      let label =
        context.roomLabels.indices.contains(roomIndex)
        ? context.roomLabels[roomIndex] : "Room \(roomIndex + 1)"
      let polygon = try outline(of: room, walls: roomPlacements, roomIndex: roomIndex)
      model.rooms.append(
        CaptureModel.Room(
          id: roomId, label: label, polygon: polygon.map(\.contractVec3),
          heightM: (roomPlacements.map(\.heightM).max() ?? 0).cleaned))

      for (surfaces, kind) in [(room.doors, "door"), (room.windows, "window"), (room.openings, "opening")] {
        for surface in surfaces {
          guard
            let assignment = OpeningAssignment.assign(
              surface, roomIndex: roomIndex, walls: placements)
          else { throw MappingError.openingHasNoWall(surface: surface.identifier) }
          let wall = assignment.wall
          let opening = CaptureModel.WallOpening(
            id: nextId(kind), wallId: wall.id,
            offsetM: OpeningAssignment.offsetM(of: surface, on: wall).cleaned,
            bottomM: max(
              0, surface.transform.translation.y - surface.dimension(1) / 2 - wall.baseY
            ).cleaned,
            widthM: surface.dimension(0).cleaned, heightM: surface.dimension(1).cleaned,
            confidence: surface.confidence, isOpen: kind == "door" ? surface.category.isOpen : nil)
          switch kind {
          case "door": model.doors.append(opening)
          case "window": model.windows.append(opening)
          default: model.openings.append(opening)
          }
        }
      }

      for object in room.objects {
        let id = nextId("object")
        let parentId = object.parentIdentifier.flatMap { objectIdByIdentifier[$0] }
        // The schema takes attribute values of 1 to 100 characters; others are left out.
        let attributes = object.attributes.filter {
          !$0.value.isEmpty && $0.value.unicodeScalars.count <= 100
        }
        model.objects.append(
          CaptureModel.DetectedObject(
            id: id, category: object.category.objectCategory, roomId: roomId,
            box: CaptureModel.OrientedBox(
              center: object.transform.translation.contractVec3,
              sizeM: Vector3(
                object.dimensions.count > 0 ? object.dimensions[0] : 0,
                object.dimensions.count > 1 ? object.dimensions[1] : 0,
                object.dimensions.count > 2 ? object.dimensions[2] : 0
              ).contractVec3,
              rotation: object.transform.rotation),
            confidence: object.confidence, attributes: attributes.isEmpty ? nil : attributes,
            parentId: parentId == id ? nil : parentId))
      }
    }
    return model
  }

  /// A wall surface into a centreline at the wall base. The wall's local X axis runs along the
  /// wall; only its horizontal part is used, so a slightly tilted scan stays a vertical wall.
  public static func wallPlacement(_ surface: RoomPlanSurface, id: String, roomIndex: Int) throws
    -> WallPlacement
  {
    let axis = surface.transform.axis(0)
    guard let direction = Vector3(axis.x, 0, axis.z).normalized, surface.dimension(0) > 0 else {
      throw MappingError.wallHasNoLength(surface: surface.identifier)
    }
    let centre = surface.transform.translation
    let half = surface.dimension(0) / 2
    let baseY = centre.y - surface.dimension(1) / 2
    let base = Vector3(centre.x, baseY, centre.z)
    return WallPlacement(
      id: id, surfaceIdentifier: surface.identifier, roomIndex: roomIndex,
      start: base - direction * half, end: base + direction * half, heightM: surface.dimension(1))
  }

  /// The room outline as a closed loop at floor level, counter-clockwise from +Y.
  /// From the floor surface when RoomPlan reports one, otherwise from the walls.
  static func outline(of room: RoomPlanRoom, walls: [WallPlacement], roomIndex: Int) throws
    -> [Vector3]
  {
    for floor in room.floors {
      guard let corners = floor.polygonCorners, corners.count >= 3 else { continue }
      let points = corners.map { corner in
        floor.transform.apply(
          to: Vector3(
            corner.count > 0 ? corner[0] : 0, corner.count > 1 ? corner[1] : 0,
            corner.count > 2 ? corner[2] : 0))
      }
      let loop = PolygonMath.openLoop(points)
      if loop.count >= 3 {
        return PolygonMath.counterClockwise(loop)
      }
    }
    guard let loop = chainWalls(walls), loop.count >= 3 else {
      throw MappingError.roomHasNoOutline(roomIndex: roomIndex)
    }
    return PolygonMath.counterClockwise(loop)
  }

  /// Joins wall centrelines end to end into a closed loop, or nil when they do not close.
  static func chainWalls(_ walls: [WallPlacement]) -> [Vector3]? {
    guard let first = walls.first else { return nil }
    var loop = [first.start]
    var current = first.end
    var remaining = Array(walls.dropFirst())
    while !remaining.isEmpty {
      var best: (index: Int, reversed: Bool, gap: Double)?
      for (index, wall) in remaining.enumerated() {
        let forward = (wall.start - current).length
        let backward = (wall.end - current).length
        if forward <= chainToleranceM, best == nil || forward < best!.gap {
          best = (index, false, forward)
        }
        if backward <= chainToleranceM, best == nil || backward < best!.gap {
          best = (index, true, backward)
        }
      }
      guard let next = best else { return nil }
      let wall = remaining.remove(at: next.index)
      loop.append(next.reversed ? wall.end : wall.start)
      current = next.reversed ? wall.start : wall.end
    }
    guard (current - first.start).length <= chainToleranceM else { return nil }
    return loop
  }
}
