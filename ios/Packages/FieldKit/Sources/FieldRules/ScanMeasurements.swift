import CaptureContract
import Foundation

/// The field-control quantities read from one capture's LiDAR model, so the operator does not
/// have to measure them by hand (decided by Eran 2026-10-18). Tape or laser checks stay optional
/// and are stored separately in `FieldControls`; these values are never written there.
///
/// - Long distance A runs along the direction of the longest wall; B is perpendicular to it. Each
///   is the overall extent of the walls' end points along that direction.
/// - Ceiling heights are per room, from the room's height in the model.
/// - Openings are the doors, windows and openings RoomPlan found.
public struct ScanMeasurements: Hashable, Sendable {
  public struct RoomHeight: Hashable, Sendable {
    public var room: String
    public var heightMm: Double

    public init(room: String, heightMm: Double) {
      self.room = room
      self.heightMm = heightMm
    }
  }

  public var distanceAMm: Double?
  public var distanceBMm: Double?
  public var ceilingHeights: [RoomHeight]
  public var doors: Int
  public var windows: Int
  public var openings: Int

  public init(
    distanceAMm: Double?, distanceBMm: Double?, ceilingHeights: [RoomHeight], doors: Int,
    windows: Int, openings: Int
  ) {
    self.distanceAMm = distanceAMm
    self.distanceBMm = distanceBMm
    self.ceilingHeights = ceilingHeights
    self.doors = doors
    self.windows = windows
    self.openings = openings
  }

  public init(model: CaptureModel) {
    let walls = model.walls.filter { Self.planLength($0) > 0.01 }
    if let longest = walls.max(by: { Self.planLength($0) < Self.planLength($1) }) {
      let length = Self.planLength(longest)
      let ax = (longest.end.x - longest.start.x) / length
      let az = (longest.end.z - longest.start.z) / length
      let points = walls.flatMap { [$0.start, $0.end] }
      let along = points.map { $0.x * ax + $0.z * az }
      let across = points.map { -$0.x * az + $0.z * ax }
      distanceAMm = Self.extentMm(along)
      distanceBMm = Self.extentMm(across)
    } else {
      distanceAMm = nil
      distanceBMm = nil
    }
    ceilingHeights = model.rooms.filter { $0.heightM > 0 }.map {
      RoomHeight(room: $0.label, heightMm: ($0.heightM * 1000).rounded())
    }
    doors = model.doors.count
    windows = model.windows.count
    openings = model.openings.count
  }

  /// "2 doors · 3 windows", or "None found".
  public var openingsSummary: String {
    let parts = [(doors, "door"), (windows, "window"), (openings, "opening")]
      .filter { $0.0 > 0 }
      .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
    return parts.isEmpty ? "None found" : parts.joined(separator: " \u{00B7} ")
  }

  private static func planLength(_ wall: CaptureModel.Wall) -> Double {
    let dx = wall.end.x - wall.start.x
    let dz = wall.end.z - wall.start.z
    return (dx * dx + dz * dz).squareRoot()
  }

  private static func extentMm(_ values: [Double]) -> Double? {
    guard let low = values.min(), let high = values.max(), high > low else { return nil }
    return ((high - low) * 1000).rounded()
  }
}
