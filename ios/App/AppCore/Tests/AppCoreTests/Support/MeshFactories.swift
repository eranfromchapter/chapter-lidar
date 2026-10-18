import CaptureCore
import CaptureModelMapping
import Foundation

enum Matrix4Columns {
  static func make(_ columns: [[Double]]) -> Matrix4? { Matrix4(columns: columns) }
}

enum RawMeshAnchorFactory {
  static func make(transform: Matrix4, vertices: [Float], triangles: [UInt32]) -> RawMeshAnchor {
    RawMeshAnchor(
      identifier: UUID().uuidString.lowercased(), transform: transform, vertices: vertices,
      triangles: triangles)
  }
}
