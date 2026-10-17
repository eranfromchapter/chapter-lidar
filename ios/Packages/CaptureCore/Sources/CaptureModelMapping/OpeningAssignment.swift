import Foundation

/// A mapped wall, with what is needed to place openings on it.
public struct WallPlacement: Hashable, Sendable {
  /// Id in the capture model, for example `wall-3`.
  public var id: String
  /// RoomPlan surface identifier of the wall.
  public var surfaceIdentifier: String
  /// Index of the room (in `RoomPlanDocument.rooms`) that lists this wall.
  public var roomIndex: Int
  /// Centreline start and end at the wall base.
  public var start: Vector3
  public var end: Vector3
  public var heightM: Double

  public var lengthM: Double { (end - start).length }
  public var baseY: Double { start.y }
}

/// How an opening was matched to its wall.
public enum OpeningAssignmentMethod: Sendable, Equatable {
  /// RoomPlan named the wall (`parentIdentifier`).
  case parentIdentifier
  /// No usable `parentIdentifier`: the nearest wall that the opening lies on.
  case geometry
}

public struct OpeningAssignmentResult: Sendable, Equatable {
  public var wall: WallPlacement
  public var method: OpeningAssignmentMethod
}

/// Assigns each door, window and opening to exactly one parent wall.
public enum OpeningAssignment {
  /// Farthest an opening centre may be from a wall line, in metres, when there is no
  /// `parentIdentifier`. RoomPlan walls and openings agree to a few centimetres.
  public static let maximumDistanceM = 0.3

  /// How far past a wall end the opening centre may project, in metres.
  public static let endSlackM = 0.05

  /// The parent wall of `opening`, or nil when no wall qualifies.
  ///
  /// 1. The wall named by `parentIdentifier` (searched in the opening's own room first, then in
  ///    the other rooms of the structure).
  /// 2. Otherwise the closest wall whose extent the opening centre projects onto and that is no
  ///    farther than `maximumDistanceM`, preferring walls of the opening's own room. A tie goes to
  ///    the wall that comes first.
  public static func assign(
    _ opening: RoomPlanSurface, roomIndex: Int, walls: [WallPlacement]
  ) -> OpeningAssignmentResult? {
    if let parent = opening.parentIdentifier {
      let named = walls.filter { $0.surfaceIdentifier == parent }
      if let wall = named.first(where: { $0.roomIndex == roomIndex }) ?? named.first {
        return OpeningAssignmentResult(wall: wall, method: .parentIdentifier)
      }
    }
    let centre = opening.transform.translation
    let sameRoom = walls.filter { $0.roomIndex == roomIndex }
    let others = walls.filter { $0.roomIndex != roomIndex }
    for group in [sameRoom, others] {
      if let wall = closestWall(to: centre, in: group) {
        return OpeningAssignmentResult(wall: wall, method: .geometry)
      }
    }
    return nil
  }

  /// Position of the opening centre along `wall`, from the wall start, in metres (never negative).
  public static func offsetM(of opening: RoomPlanSurface, on wall: WallPlacement) -> Double {
    guard
      let projected = PolygonMath.project(opening.transform.translation, onto: wall.start, wall.end)
    else { return 0 }
    return max(0, projected.along)
  }

  private static func closestWall(to centre: Vector3, in walls: [WallPlacement]) -> WallPlacement? {
    var best: (wall: WallPlacement, distance: Double)?
    for wall in walls {
      guard let projected = PolygonMath.project(centre, onto: wall.start, wall.end) else {
        continue
      }
      guard projected.distance <= maximumDistanceM,
        projected.along >= -endSlackM, projected.along <= wall.lengthM + endSlackM
      else { continue }
      if best == nil || projected.distance < best!.distance - 1e-6 {
        best = (wall, projected.distance)
      }
    }
    return best?.wall
  }
}
