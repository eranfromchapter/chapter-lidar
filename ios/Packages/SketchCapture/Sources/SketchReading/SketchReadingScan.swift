import CaptureContract
import Foundation

/// A written dimension that measures one drawn wall.
struct WallDimension: Hashable, Sendable {
  /// Index in the reading's `dimensions`.
  var index: Int
  var text: String
  var valueMm: Double
  var room: Int
  /// The drawing's wall index.
  var wall: Int
  /// The wall's drawn length, drawing units.
  var drawnLength: Double

  /// Millimetres per drawing unit this dimension implies.
  var ratio: Double { valueMm / drawnLength }
}

/// What in a reading can set the scale.
enum SketchReadingScan {
  /// Drawn length of wall `wall` (corner `wall` to corner `wall + 1`), or nil when the room has
  /// fewer than three corners or no such wall.
  static func drawnLength(_ room: SketchInterpretation.Room, wall: Int) -> Double? {
    let n = room.corners.count
    guard n >= 3, (0..<n).contains(wall) else { return nil }
    let a = PlanPoint(room.corners[wall])
    let b = PlanPoint(room.corners[(wall + 1) % n])
    return (b - a).length
  }

  /// The written dimensions with a value and a room and wall that resolve to a drawn wall with a
  /// length; a note for each that names a room or wall the drawing does not have.
  static func wallDimensions(_ reading: SketchInterpretation.Reading) -> (
    usable: [WallDimension], notes: [String]
  ) {
    var usable: [WallDimension] = []
    var notes: [String] = []
    for (index, dimension) in reading.dimensions.enumerated() {
      guard let value = dimension.valueMm, value.isFinite, value > 0,
        let roomIndex = dimension.room, let wall = dimension.wall
      else { continue }
      guard reading.rooms.indices.contains(roomIndex),
        let drawn = drawnLength(reading.rooms[roomIndex], wall: wall)
      else {
        let room =
          reading.rooms.indices.contains(roomIndex)
          ? reading.rooms[roomIndex].label : "room \(roomIndex + 1)"
        notes.append(
          "\(dimension.text) names wall \(wall + 1) of \(room), which is not drawn; not used.")
        continue
      }
      guard drawn >= RoomOutline.sameCornerUnits else {
        notes.append(
          "\(dimension.text) is on a wall of \(reading.rooms[roomIndex].label) drawn with no length; not used."
        )
        continue
      }
      usable.append(
        WallDimension(
          index: index, text: dimension.text, valueMm: value, room: roomIndex, wall: wall,
          drawnLength: drawn))
    }
    return (usable, notes)
  }
}
