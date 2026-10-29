import CaptureContract
import Foundation
import MeshExport

// The 3D model of a sketch capture (spec F14 2.1): the capture model extruded into a MeshExport
// `TriangleMesh`. This file is the public API; F14.2 fills in the implementation.

public enum SketchMeshError: Error, Equatable, CustomStringConvertible {
  case noGeometry
  case notImplemented

  public var description: String {
    switch self {
    case .noGeometry: return "The model has no rooms or walls to extrude."
    case .notImplemented: return "The sketch mesh is not built yet."
    }
  }
}

public enum SketchMesh {
  /// Metres, +Y up, in the model's frame: each room's floor polygon at Y 0 (ear-clipped, facing
  /// up), each wall as a box of its thickness and height with its openings cut out (the faces
  /// around an opening are rectangles in the wall's plane), and each room's ceiling underside at
  /// its height. Triangles are counter-clockwise seen from outside the solid. The result passes
  /// `TriangleMesh.validate()` and the station's orientation check: horizontal floor faces at
  /// the lowest Y, height extent equal to the tallest room.
  public static func extrude(_ model: CaptureModel) throws -> TriangleMesh {
    throw SketchMeshError.notImplemented
  }
}
