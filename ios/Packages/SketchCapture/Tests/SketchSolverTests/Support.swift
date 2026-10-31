import CaptureContract
import SketchSolver
import XCTest

/// Builders for the measurements the tests feed the solver, in millimetres.
enum Sketch {
  static let visitId = LowercaseUUID(rawValue: "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")!
  static let captureId = LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!
  static let context = SketchSolveContext(label: "Floor 1")

  static func mm(_ value: Double, measured: Bool = true) -> SketchMeasurements.Length {
    SketchMeasurements.Length(
      valueMm: value, enteredUnit: .mm, enteredText: "\(Int(value))", measured: measured)
  }

  static func wall(
    _ id: String, _ length: Double? = nil, measured: Bool = true, turn: SketchTurn? = nil,
    exterior: Bool? = nil, sharedWith: SketchMeasurements.SharedWall? = nil
  ) -> SketchMeasurements.Wall {
    SketchMeasurements.Wall(
      id: id, length: length.map { mm($0, measured: measured) }, turn: turn, exterior: exterior,
      sharedWith: sharedWith)
  }

  static func measurements(
    ceiling: Double? = 2700, rooms: [SketchMeasurements.Room]
  ) -> SketchMeasurements {
    SketchMeasurements(
      visitId: visitId, captureId: captureId, areaKey: "floor-1", displayUnits: .metric,
      source: SketchMeasurements.Source(kind: .none), ceilingHeight: ceiling.map { mm($0) },
      rooms: rooms)
  }

  /// The required set of spec F14 1.1 for a 4.000 x 3.000 m room: walls 1 and 2, the ceiling,
  /// a 0.9 m door 0.5 m from the start of wall 2 and a 1.2 m window 1.0 m from the end of
  /// wall 1 (sill 0.9 m, height 1.2 m).
  static func requiredRectangle() -> SketchMeasurements {
    measurements(rooms: [
      SketchMeasurements.Room(
        id: "room-1", label: "Kitchen", type: .kitchen,
        walls: [wall("wall-1", 4000), wall("wall-2", 3000), wall("wall-3"), wall("wall-4")],
        openings: [
          SketchMeasurements.Opening(
            id: "door-1", kind: .door, wallId: "wall-2", width: mm(900), fromCorner: .start,
            fromCornerDistance: mm(500)),
          SketchMeasurements.Opening(
            id: "window-1", kind: .window, wallId: "wall-1", width: mm(1200), height: mm(1200),
            sill: mm(900), fromCorner: .end, fromCornerDistance: mm(1000)),
        ])
    ])
  }

  /// A 4.0 x 3.0 m L-shaped room: a 1.5 m notch cut from the corner between walls 3 and 4.
  /// Corners (0,0) (4000,0) (4000,1500) (2500,1500) (2500,3000) (0,3000).
  static func lShape(
    wall1: Double? = 4000, wall2: Double? = 1500, wall3: Double? = 1500, wall4: Double? = 1500,
    wall5: Double? = 2500, wall6: Double? = 3000
  ) -> SketchMeasurements {
    measurements(rooms: [
      SketchMeasurements.Room(
        id: "room-1", label: "Living room", type: .livingRoom,
        walls: [
          wall("wall-1", wall1), wall("wall-2", wall2), wall("wall-3", wall3, turn: .right),
          wall("wall-4", wall4), wall("wall-5", wall5), wall("wall-6", wall6),
        ])
    ])
  }
}

extension XCTestCase {
  func assertVec(
    _ actual: Vec3, _ x: Double, _ y: Double, _ z: Double, accuracy: Double = 0.001,
    _ label: String = "", file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(actual.x, x, accuracy: accuracy, "\(label) x", file: file, line: line)
    XCTAssertEqual(actual.y, y, accuracy: accuracy, "\(label) y", file: file, line: line)
    XCTAssertEqual(actual.z, z, accuracy: accuracy, "\(label) z", file: file, line: line)
  }

  func wall(_ id: String, in model: CaptureModel, file: StaticString = #filePath, line: UInt = #line)
    throws -> CaptureModel.Wall
  {
    try XCTUnwrap(model.walls.first { $0.id == id }, "wall \(id)", file: file, line: line)
  }

  /// The edge lengths of a room polygon in metres, edge i from point i to point i + 1.
  func edgeLengths(_ room: CaptureModel.Room) -> [Double] {
    room.polygon.indices.map { index in
      let a = room.polygon[index]
      let b = room.polygon[(index + 1) % room.polygon.count]
      return ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
    }
  }

  /// Signed shoelace area in (x, z): negative is counter-clockwise seen from +Y.
  func signedArea(_ polygon: [Vec3]) -> Double {
    var sum = 0.0
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      sum += a.x * b.z - b.x * a.z
    }
    return sum / 2
  }
}

extension SketchSolveResult {
  func notes(where predicate: (SketchSolveNote.Kind) -> Bool) -> [SketchSolveNote] {
    notes.filter { predicate($0.kind) }
  }

  var closureNotes: [(axis: SketchSolveNote.Axis, residual: Double, grade: SketchSolveNote.ClosureGrade)] {
    notes.compactMap { note in
      if case .closureResidual(_, let axis, let residual, let grade) = note.kind {
        return (axis, residual, grade)
      }
      return nil
    }
  }
}
