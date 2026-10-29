import CaptureContract
import Foundation
import MeshExport

// The 3D model of a sketch capture (spec F14 2.1): the capture model extruded into a MeshExport
// `TriangleMesh`. This file is the public API; `MeshBuilder` next to it does the work.

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
  /// around an opening are rectangles in the wall's plane), each room's ceiling underside at
  /// its height, and each object (sketch furniture, spec F16) as a closed box turned about +Y,
  /// kept between the floor and the tallest room. Every vertex has a colour
  /// (`SketchMeshPalette`): floor oak, walls warm white, opening reveals light grey, ceiling
  /// white, furniture by category. Triangles are counter-clockwise seen from outside the solid.
  /// The result passes `TriangleMesh.validate()` and the station's orientation check:
  /// horizontal floor faces at the lowest Y, height extent equal to the tallest room.
  public static func extrude(_ model: CaptureModel) throws -> TriangleMesh {
    var builder = MeshBuilder()
    for room in model.rooms {
      builder.addRoom(room)
    }
    let openingsByWall = Dictionary(
      grouping: model.doors + model.windows + model.openings, by: \.wallId)
    for wall in model.walls {
      builder.addWall(wall, openings: openingsByWall[wall.id] ?? [])
    }
    let tallest = (model.rooms.map(\.heightM) + model.walls.map(\.heightM)).max() ?? 0
    if tallest > 0 {
      for object in model.objects {
        builder.addObject(object, ceilingM: tallest)
      }
    }
    guard !builder.indices.isEmpty else { throw SketchMeshError.noGeometry }
    let mesh = TriangleMesh(
      positions: builder.positions, colors: builder.colors, indices: builder.indices)
    try mesh.validate()
    return mesh
  }
}
