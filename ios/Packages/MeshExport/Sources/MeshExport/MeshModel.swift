import Foundation

/// An 8-bit RGB colour (per-vertex colour sampled from the camera frames).
public struct RGB8: Hashable, Sendable {
  public var r: UInt8
  public var g: UInt8
  public var b: UInt8

  public init(r: UInt8, g: UInt8, b: UInt8) {
    self.r = r
    self.g = g
    self.b = b
  }
}

/// Platform-neutral triangle mesh: the input of every writer in this package.
///
/// The on-device adapter from ARKit (`ARMeshAnchor` vertices, normals and faces, plus the colour
/// sampling from camera frames) lives in the capture code (F2/F6), not here. It must hand over:
///
/// - `positions`: metres, right-handed, **+Y up**, in the capture's own frame (the ARKit world
///   frame already is Y up, and the anchor transform must be applied before the hand-over).
/// - `normals`: unit vectors, either empty (the writers compute smooth normals) or one per vertex.
/// - `colors`: either empty (no colour is written) or one per vertex.
/// - `indices`: triangle corner indices, counter-clockwise seen from the front, a multiple of 3.
public struct TriangleMesh: Sendable, Equatable {
  public var positions: [SIMD3<Float>]
  public var normals: [SIMD3<Float>]
  public var colors: [RGB8]
  public var indices: [UInt32]

  public init(
    positions: [SIMD3<Float>],
    normals: [SIMD3<Float>] = [],
    colors: [RGB8] = [],
    indices: [UInt32]
  ) {
    self.positions = positions
    self.normals = normals
    self.colors = colors
    self.indices = indices
  }

  public var vertexCount: Int { positions.count }
  public var triangleCount: Int { indices.count / 3 }

  /// Axis-aligned bounds of the positions, or nil for an empty mesh.
  public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
    guard var lo = positions.first else { return nil }
    var hi = lo
    for position in positions {
      lo = pointwiseMin(lo, position)
      hi = pointwiseMax(hi, position)
    }
    return (lo, hi)
  }

  /// Throws if the mesh cannot be written: empty, bad index count or range, non-finite values,
  /// or attribute arrays that do not match the vertex count.
  public func validate() throws {
    guard !positions.isEmpty, !indices.isEmpty else { throw MeshExportError.emptyMesh }
    guard indices.count % 3 == 0 else {
      throw MeshExportError.invalidMesh("index count \(indices.count) is not a multiple of 3")
    }
    guard normals.isEmpty || normals.count == positions.count else {
      throw MeshExportError.invalidMesh("normals count differs from vertex count")
    }
    guard colors.isEmpty || colors.count == positions.count else {
      throw MeshExportError.invalidMesh("colors count differs from vertex count")
    }
    let limit = UInt32(clamping: positions.count)
    for index in indices where index >= limit {
      throw MeshExportError.invalidMesh("index \(index) is out of range")
    }
    for position in positions where !(position.x.isFinite && position.y.isFinite && position.z.isFinite) {
      throw MeshExportError.invalidMesh("a position is not finite")
    }
    for normal in normals where !(normal.x.isFinite && normal.y.isFinite && normal.z.isFinite) {
      throw MeshExportError.invalidMesh("a normal is not finite")
    }
  }

  /// The mesh with unit normals: existing normals are kept, missing ones are computed as
  /// area-weighted smooth vertex normals.
  public func withNormals() -> TriangleMesh {
    guard normals.isEmpty else { return self }
    var accumulated = [SIMD3<Float>](repeating: .zero, count: positions.count)
    var corner = 0
    while corner + 2 < indices.count {
      let a = Int(indices[corner])
      let b = Int(indices[corner + 1])
      let c = Int(indices[corner + 2])
      let faceNormal = cross3(positions[b] - positions[a], positions[c] - positions[a])
      accumulated[a] += faceNormal
      accumulated[b] += faceNormal
      accumulated[c] += faceNormal
      corner += 3
    }
    var result = self
    result.normals = accumulated.map { normalizedOrUp($0) }
    return result
  }
}

/// One floor (one capture) of a site: a mesh in the capture's own frame.
public struct FloorMesh: Sendable, Equatable {
  /// Package area key, for example `floor-1`. Used as the GLB node name and the OBJ object name.
  public var areaKey: String
  /// Label shown to people, for example `Floor 1`.
  public var label: String
  public var mesh: TriangleMesh

  public init(areaKey: String, label: String, mesh: TriangleMesh) {
    self.areaKey = areaKey
    self.label = label
    self.mesh = mesh
  }
}

public enum MeshExportError: Error, Equatable, CustomStringConvertible {
  case emptyMesh
  case invalidMesh(String)
  case invalidOption(String)
  case invalidDepthFile(String)
  case noPoints
  case coordinateRange(String)

  public var description: String {
    switch self {
    case .emptyMesh: return "The mesh has no vertices or no triangles."
    case .invalidMesh(let reason): return "Invalid mesh: \(reason)."
    case .invalidOption(let reason): return "Invalid option: \(reason)."
    case .invalidDepthFile(let reason): return "Invalid depth sample file: \(reason)."
    case .noPoints: return "There are no points to write."
    case .coordinateRange(let reason): return "Coordinates out of range: \(reason)."
    }
  }
}

// MARK: - Small vector helpers (stdlib SIMD only, no platform frameworks)

@inline(__always)
func cross3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
  SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

@inline(__always)
func cross3(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
  SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

@inline(__always)
func dot3(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
  a.x * b.x + a.y * b.y + a.z * b.z
}

@inline(__always)
func length3(_ a: SIMD3<Double>) -> Double {
  dot3(a, a).squareRoot()
}

func normalizedOrUp(_ v: SIMD3<Float>) -> SIMD3<Float> {
  let length = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
  guard length > 1e-20, length.isFinite else { return SIMD3(0, 1, 0) }
  return v / length
}

func pointwiseMin(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
  SIMD3(Swift.min(a.x, b.x), Swift.min(a.y, b.y), Swift.min(a.z, b.z))
}

func pointwiseMax(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
  SIMD3(Swift.max(a.x, b.x), Swift.max(a.y, b.y), Swift.max(a.z, b.z))
}
