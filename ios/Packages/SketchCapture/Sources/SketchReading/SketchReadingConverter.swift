import CaptureContract
import Foundation
import SketchSolver

// Sketch photo to sketch measurements (spec F16, section 4). What Claude read from the photo
// (`SketchInterpretation`) becomes the F14 document, so the one sketch solver builds the model.
// Pure functions; nothing here touches the network.
//
// This file is the public API the app builds against. The implementation is in the files next
// to it: `SketchReadingRun` (scale, walls, turns, openings, placement, furniture, ceiling),
// `RoomOutline` (repeated and straight corners, winding, wall renumbering), `SketchReadingScan`
// (which written dimensions can set the scale) and `SketchReadingText`.

/// Reads a sketch photo: the station in production, a direct call or a fixture in Debug builds.
public protocol SketchInterpreting: Sendable {
  /// `imageData` is the photo as taken or imported (JPEG, PNG or HEIC); `mediaType` its MIME type.
  func interpret(imageData: Data, mediaType: String) async throws -> SketchInterpretation
}

public enum SketchReadingDefaults {
  /// A drawn corner within this many degrees of 90 is squared (hand sketches are wobbly).
  public static let squareToleranceDegrees = 10.0
  /// A written dimension whose scale is more than this fraction from the median is dropped.
  public static let scaleOutlierFraction = 0.15
}

/// One drawn wall, for the "one length" step: the user picks it on the drawn plan.
public struct DrawnWall: Hashable, Sendable, Identifiable {
  public var roomIndex: Int
  public var wallIndex: Int
  public var roomLabel: String
  /// Length in drawing units (the image's longer side is 1000).
  public var drawnLength: Double
  public var start: SketchInterpretation.Point
  public var end: SketchInterpretation.Point

  public var id: String { "\(roomIndex)-\(wallIndex)" }

  public init(
    roomIndex: Int, wallIndex: Int, roomLabel: String, drawnLength: Double,
    start: SketchInterpretation.Point, end: SketchInterpretation.Point
  ) {
    self.roomIndex = roomIndex
    self.wallIndex = wallIndex
    self.roomLabel = roomLabel
    self.drawnLength = drawnLength
    self.start = start
    self.end = end
  }
}

/// The one length the user typed when the sketch has no written dimensions.
public struct UserScaleLength: Hashable, Sendable {
  public var roomIndex: Int
  public var wallIndex: Int
  public var length: SketchMeasurements.Length

  public init(roomIndex: Int, wallIndex: Int, length: SketchMeasurements.Length) {
    self.roomIndex = roomIndex
    self.wallIndex = wallIndex
    self.length = length
  }
}

/// Where the scale came from.
public enum SketchScaleSource: Hashable, Sendable {
  /// The dimensions written on the sketch (how many were used).
  case writtenDimensions(count: Int)
  /// The user's one length.
  case userLength
}

public struct SketchReadingConversion: Sendable {
  /// The F14 document: walls measured where a written dimension (or the user's length) gives
  /// them, estimated elsewhere; rooms placed where they are drawn; furniture; the source with
  /// the image and interpretation paths.
  public var measurements: SketchMeasurements
  public var scaleSource: SketchScaleSource
  /// Millimetres per drawing unit.
  public var millimetresPerUnit: Double
  /// One line per thing worth saying ("3 written dimensions set the scale; 9'10" on Bedroom wall
  /// 2 was 6 % off the others and was not used.").
  public var notes: [String]

  public init(
    measurements: SketchMeasurements, scaleSource: SketchScaleSource, millimetresPerUnit: Double,
    notes: [String]
  ) {
    self.measurements = measurements
    self.scaleSource = scaleSource
    self.millimetresPerUnit = millimetresPerUnit
    self.notes = notes
  }
}

public enum SketchReadingError: Error, Equatable, CustomStringConvertible {
  /// The photo is not a floor plan (the reading's problem says why).
  case notAFloorPlan(String)
  case noRooms
  /// No written dimension can set the scale and no user length was given.
  case needsOneLength
  case tooFewCorners(roomIndex: Int)
  case unknownWall(roomIndex: Int, wallIndex: Int)
  case notImplemented

  public var description: String {
    switch self {
    case .notAFloorPlan(let why): return "This photo is not a floor plan: \(why)"
    case .noRooms: return "No room could be read from the sketch."
    case .needsOneLength: return "The sketch has no written dimensions. Enter one wall's length."
    case .tooFewCorners(let room): return "Room \(room + 1) has fewer than three corners."
    case .unknownWall(let room, let wall):
      return "Room \(room + 1) has no wall \(wall + 1)."
    case .notImplemented: return "The sketch reader is not built yet."
    }
  }
}

public enum SketchReadingConverter {
  /// True when no written dimension can set the scale: the app asks for one length.
  public static func needsOneLength(_ interpretation: SketchInterpretation) -> Bool {
    SketchReadingScan.wallDimensions(interpretation.reading).usable.isEmpty
  }

  /// Every drawn wall, for the one-length step: the drawing's own wall numbers (wall `i` runs
  /// from corner `i` to corner `i + 1`), which `UserScaleLength` uses too. Rooms with fewer than
  /// three corners and walls drawn with no length are left out (they cannot set the scale).
  public static func drawnWalls(_ interpretation: SketchInterpretation) -> [DrawnWall] {
    var walls: [DrawnWall] = []
    for (roomIndex, room) in interpretation.reading.rooms.enumerated() {
      let n = room.corners.count
      guard n >= 3 else { continue }
      for wallIndex in 0..<n {
        guard let length = SketchReadingScan.drawnLength(room, wall: wallIndex),
          length >= RoomOutline.sameCornerUnits
        else { continue }
        walls.append(
          DrawnWall(
            roomIndex: roomIndex, wallIndex: wallIndex, roomLabel: room.label,
            drawnLength: length, start: room.corners[wallIndex],
            end: room.corners[(wallIndex + 1) % n]))
      }
    }
    return walls
  }

  /// Converts what Claude read. `imagePath` and `interpretationPath` are the package paths of
  /// the photo (role `sketch_image`) and the interpretation (role `sketch_interpretation`).
  public static func convert(
    _ interpretation: SketchInterpretation, userLength: UserScaleLength?,
    visitId: LowercaseUUID, captureId: LowercaseUUID, areaKey: String,
    displayUnits: DisplayUnitSystem, sourceKind: SketchSourceKind, imagePath: String,
    interpretationPath: String
  ) throws -> SketchReadingConversion {
    try SketchReadingRun(
      interpretation: interpretation, userLength: userLength, visitId: visitId,
      captureId: captureId, areaKey: areaKey, displayUnits: displayUnits, sourceKind: sourceKind,
      imagePath: imagePath, interpretationPath: interpretationPath
    ).run()
  }
}
