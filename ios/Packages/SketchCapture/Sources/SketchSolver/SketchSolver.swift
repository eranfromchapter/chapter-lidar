import CaptureContract
import Foundation

// The sketch solver (spec F14, Part 1): the operator's `SketchMeasurements` into the contract
// `CaptureModel`, with the closure rule (1.4), the estimates (1.5) and the confidences, and the
// `sketch` summary of the capture record. Pure functions; nothing here touches Apple frameworks.
//
// This file is the public API the app and the entry model build against. The implementation is
// in the files next to it: `RoomSolver` (one room: turns, closure, estimates, diagonals),
// `LeastSquares` (the corner fit for unsquare corners), `SketchSolveRun` (rooms placed by their
// shared walls, walls as centrelines, openings, the summary) and `Plan2` (the plan maths).

/// Defaults the solver uses for what was not measured (spec F14 1.3 and 1.5). Millimetres.
public enum SketchDefaults {
  public static let ceilingHeightMm: Double = 2440
  public static let doorWidthMm: Double = 914
  public static let doorHeightMm: Double = 2032
  public static let windowWidthMm: Double = 1219
  public static let windowHeightMm: Double = 1219
  public static let windowSillMm: Double = 914
  public static let openingWidthMm: Double = 1219
  /// 4.5 in, the interior wall thickness the LiDAR path assumes too.
  public static let interiorWallThicknessMm: Double = 114.3
  /// 6 in.
  public static let exteriorWallThicknessMm: Double = 152.4
  /// Closure residual within max(1 % of the axis extent, 25.4 mm) passes (the station's scale
  /// tolerance); up to 3 % is a limitation; over 3 % is refused at entry time (still solved).
  public static let closurePassFraction = 0.01
  public static let closurePassMinimumMm = 25.4
  public static let closureLimitFraction = 0.03
}

/// One thing the solver had to derive, estimate or assume, or a closure residual.
public struct SketchSolveNote: Hashable, Sendable {
  public enum OpeningField: String, Hashable, Sendable {
    case width, height, sill, position
  }

  public enum Axis: String, Hashable, Sendable {
    case x, z
  }

  public enum ClosureGrade: String, Hashable, Sendable {
    case pass, limitation, refused
  }

  public enum Kind: Hashable, Sendable {
    /// The wall's length came from closure (one unknown on its axis): confidence `medium`.
    case wallDerivedFromClosure(wallId: String)
    /// The wall's length is an "about" value, the opposite wall, or a sketch proportion:
    /// confidence `low`, the capture is limited.
    case wallEstimated(wallId: String)
    /// A corner marked unsquare had no diagonal: drawn square; both walls `low`, limited.
    case cornerAssumedSquare(roomId: String, corner: Int)
    /// No ceiling height entered: `SketchDefaults.ceilingHeightMm`, limited.
    case ceilingAssumed
    /// An opening field defaulted: confidence `low`; width or position makes the capture limited.
    case openingEstimated(openingId: String, field: OpeningField)
    /// A room with every wall measured did not close on an axis; `limitation` and `refused`
    /// make the capture limited.
    case closureResidual(roomId: String, axis: Axis, residualMm: Double, grade: ClosureGrade)
  }

  public var kind: Kind
  /// One line for people, for example "Kitchen: wall-3 estimated from the opposite wall."
  public var message: String

  public init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }
}

/// What the solver needs besides the measurements.
public struct SketchSolveContext: Sendable {
  /// The capture's floor or area label (`CaptureModel.label`).
  public var label: String
  /// Package files the model is accompanied by; empty for a sketch (the manifest's
  /// `derivedFrom` names the sketch image and the measurements).
  public var refs: [CaptureModel.SourceRef]

  public init(label: String, refs: [CaptureModel.SourceRef] = []) {
    self.label = label
    self.refs = refs
  }
}

public struct SketchSolveResult: Sendable {
  /// Contract 1.1 capture model: ids kept from the measurements, room polygons
  /// counter-clockwise from +Y at the inside faces, walls as centrelines with the assumed
  /// thickness, openings by offset from the wall start, confidences per 1.5.
  public var model: CaptureModel
  /// The capture record's `sketch` object.
  public var summary: CaptureRecord.Capture.SketchSummary
  public var notes: [SketchSolveNote]

  public init(
    model: CaptureModel, summary: CaptureRecord.Capture.SketchSummary, notes: [SketchSolveNote]
  ) {
    self.model = model
    self.summary = summary
    self.notes = notes
  }

  public var isLimited: Bool { summary.measurements == .limited }
}

public enum SketchSolverError: Error, Equatable, CustomStringConvertible {
  case noRooms
  case tooFewWalls(roomId: String)
  case duplicateId(String)
  case unknownWall(roomId: String, wallId: String)
  case unknownSharedWall(roomId: String, wallId: String)
  case badDiagonal(roomId: String, from: Int, to: Int)
  case notImplemented

  public var description: String {
    switch self {
    case .noRooms: return "The sketch has no rooms."
    case .tooFewWalls(let room): return "Room \(room) has fewer than three walls."
    case .duplicateId(let id): return "The id \(id) is used twice."
    case .unknownWall(let room, let wall): return "Room \(room) has no wall \(wall)."
    case .unknownSharedWall(let room, let wall):
      return "Room \(room) shares a wall with \(wall), which is not in an earlier room."
    case .badDiagonal(let room, let from, let to):
      return "Room \(room): the diagonal from corner \(from) to corner \(to) does not cross the room."
    case .notImplemented: return "The sketch solver is not built yet."
    }
  }
}

public enum SketchSolver {
  /// Solves every room, places the rooms by their shared walls and returns the model, the
  /// summary and the notes. Throws only for input that cannot be solved at all (no rooms, an
  /// unknown wall id); missing measurements are estimated and noted, never refused.
  public static func solve(_ measurements: SketchMeasurements, context: SketchSolveContext) throws
    -> SketchSolveResult
  {
    try SketchSolveRun(measurements: measurements, context: context).run()
  }
}
