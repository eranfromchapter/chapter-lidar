import CaptureContract
import Foundation
import SketchSolver

// AR walkthrough to sketch measurements (spec F15, section 3). The walkthrough's taps become the
// F14 document (`SketchMeasurements`, source kind `ar_walkthrough`) so the one sketch solver
// builds the model. Pure functions; nothing here touches ARKit.
//
// This file is the public API the app builds against. F15.2 fills in the implementation (and
// may add files next to this one); the public names below stay.

public enum WalkthroughDefaults {
  /// A corner within this many degrees of 90 is squared by the solver; otherwise it is
  /// unsquare and keeps its angle through diagonals.
  public static let squareToleranceDegrees = 5.0
  /// A corner tap this close to the first corner closes the room (metres).
  public static let closeSnapMetres = 0.25
}

public struct WalkthroughConversion: Sendable {
  /// The F14 document: source kind `ar_walkthrough`, every length `measured: true`, each room's
  /// `placement` where it was walked, lengths scaled by the scale check when there is one.
  public var measurements: SketchMeasurements
  /// The capture record's `walkthrough` object.
  public var summary: CaptureRecord.Capture.WalkthroughSummary
  /// Each room's floor corners after the loop drift was distributed, in the capture frame
  /// (metres, floor at y 0), by room id: for the live outline and the Check screen.
  public var corners: [String: [Vec3]]
  /// One line per thing worth saying ("Bedroom: the loop closed 38 mm apart, spread over the
  /// corners.").
  public var notes: [String]

  public init(
    measurements: SketchMeasurements, summary: CaptureRecord.Capture.WalkthroughSummary,
    corners: [String: [Vec3]], notes: [String]
  ) {
    self.measurements = measurements
    self.summary = summary
    self.corners = corners
    self.notes = notes
  }
}

public enum WalkthroughError: Error, Equatable, CustomStringConvertible {
  case noRooms
  case tooFewCorners(roomId: String)
  case wallsDoNotMeet(roomId: String, wallIndex: Int)
  case unknownWall(openingId: String, wallIndex: Int)
  case unknownScaleWall(roomId: String, wallIndex: Int)
  case notImplemented

  public var description: String {
    switch self {
    case .noRooms: return "The walkthrough has no rooms."
    case .tooFewCorners(let room): return "Room \(room) has fewer than three corners."
    case .wallsDoNotMeet(let room, let wall):
      return "Room \(room): wall \(wall + 1) and the next wall are parallel, so they have no corner."
    case .unknownWall(let opening, let wall):
      return "Opening \(opening) is in wall \(wall + 1), which the room does not have."
    case .unknownScaleWall(let room, let wall):
      return "The scale check names wall \(wall + 1) of \(room), which is not walked."
    case .notImplemented: return "The walkthrough converter is not built yet."
    }
  }
}

public enum WalkthroughConverter {
  /// Converts a finished walkthrough: corners (drift distributed by time for `corners` rooms,
  /// wall lines intersected for `walls` rooms), turns (square within
  /// `WalkthroughDefaults.squareToleranceDegrees`, else unsquare with diagonals), openings from
  /// the jamb, sill and head taps, ceiling from the ceiling taps, and the scale check.
  /// `sourcePath` is the package path of the walkthrough log (the document's `source.path`).
  public static func convert(
    _ log: WalkthroughLog, displayUnits: DisplayUnitSystem, sourcePath: String, recorded: Bool
  ) throws -> WalkthroughConversion {
    throw WalkthroughError.notImplemented
  }

  /// The corners of one room while it is being walked (no drift distribution, no closing tap
  /// needed): for the live outline. Nil when the room has too few taps to have corners yet.
  public static func liveCorners(_ room: WalkthroughLog.Room, floorY: Double) -> [Vec3]? {
    nil
  }
}
