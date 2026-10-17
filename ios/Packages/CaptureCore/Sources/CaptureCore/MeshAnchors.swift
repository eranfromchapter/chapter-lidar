import CaptureModelMapping
import Foundation

/// Geometry of one ARMeshAnchor (scene reconstruction mesh), in the anchor's local frame.
public struct RawMeshAnchor: Sendable, Equatable {
  /// The anchor's UUID string, lowercase.
  public var identifier: String
  /// Anchor-to-capture-frame transform.
  public var transform: Matrix4
  /// x, y, z of every vertex, flattened (count is a multiple of 3).
  public var vertices: [Float]
  /// Vertex indexes of every triangle, flattened (count is a multiple of 3).
  public var triangles: [UInt32]

  public init(identifier: String, transform: Matrix4, vertices: [Float], triangles: [UInt32]) {
    self.identifier = identifier
    self.transform = transform
    self.vertices = vertices
    self.triangles = triangles
  }
}

/// "CHMA" version 1, little endian, the on-device original of the scene reconstruction mesh
/// (`mesh-anchors.bin`; it has no manifest role, MeshExport turns it into GLB, OBJ and LAS).
///
/// Header 16 bytes: magic `CHMA`, u32 version, u32 anchor count, u32 reserved. Then per anchor:
/// 16 bytes UUID, 16 x f32 transform (column-major), u32 vertex count, u32 triangle count,
/// vertex count x 3 x f32, triangle count x 3 x u32.
public enum MeshAnchorsCodec {
  public static let magic: [UInt8] = Array("CHMA".utf8)
  public static let version: UInt32 = 1

  public static func encode(_ anchors: [RawMeshAnchor]) throws -> Data {
    var writer = ByteWriter()
    writer.append(magic)
    writer.append(version)
    writer.append(UInt32(anchors.count))
    writer.append(UInt32(0))
    for anchor in anchors {
      guard let uuid = UUID(uuidString: anchor.identifier) else {
        throw RawOriginalsError.invalidIdentifier(anchor.identifier)
      }
      guard anchor.vertices.count % 3 == 0, anchor.triangles.count % 3 == 0 else {
        throw RawOriginalsError.invalidMesh(anchor.identifier)
      }
      let vertexCount = anchor.vertices.count / 3
      guard anchor.triangles.allSatisfy({ Int($0) < vertexCount }) else {
        throw RawOriginalsError.invalidMesh(anchor.identifier)
      }
      writer.append(uuidBytes(uuid))
      for column in anchor.transform.columns {
        for value in column {
          writer.append(Float(value))
        }
      }
      writer.append(UInt32(vertexCount))
      writer.append(UInt32(anchor.triangles.count / 3))
      for value in anchor.vertices { writer.append(value) }
      for index in anchor.triangles { writer.append(index) }
    }
    return writer.data
  }

  public static func decode(_ data: Data) throws -> [RawMeshAnchor] {
    var reader = ByteReader(data)
    guard try reader.readBytes(4) == magic else { throw RawOriginalsError.badMagic("CHMA") }
    let found = try reader.readU32()
    guard found == version else { throw RawOriginalsError.unsupportedVersion(found) }
    let count = Int(try reader.readU32())
    _ = try reader.readU32()
    var anchors: [RawMeshAnchor] = []
    for _ in 0..<count {
      let uuid = uuidFrom(try reader.readBytes(16))
      var columns: [[Double]] = []
      for _ in 0..<4 {
        var column: [Double] = []
        for _ in 0..<4 { column.append(Double(try reader.readF32())) }
        columns.append(column)
      }
      let vertexCount = Int(try reader.readU32())
      let triangleCount = Int(try reader.readU32())
      guard reader.remaining >= (vertexCount * 3 + triangleCount * 3) * 4 else {
        throw RawOriginalsError.truncated
      }
      var vertices: [Float] = []
      vertices.reserveCapacity(vertexCount * 3)
      for _ in 0..<vertexCount * 3 { vertices.append(try reader.readF32()) }
      var triangles: [UInt32] = []
      triangles.reserveCapacity(triangleCount * 3)
      for _ in 0..<triangleCount * 3 { triangles.append(try reader.readU32()) }
      anchors.append(
        RawMeshAnchor(
          identifier: uuid.uuidString.lowercased(), transform: Matrix4(columns: columns)!,
          vertices: vertices, triangles: triangles))
    }
    guard reader.remaining == 0 else { throw RawOriginalsError.truncated }
    return anchors
  }

  private static func uuidBytes(_ uuid: UUID) -> [UInt8] {
    let t = uuid.uuid
    return [
      t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7, t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15,
    ]
  }

  private static func uuidFrom(_ b: [UInt8]) -> UUID {
    UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
  }
}
