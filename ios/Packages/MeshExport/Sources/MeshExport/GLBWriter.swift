import Foundation

/// Writes GLB 2.0 (binary glTF): one file, one node per floor, +Y up, metres.
///
/// Each floor becomes one node (named by its area key) with one mesh and one triangle primitive:
/// POSITION, NORMAL and per-vertex COLOR_0 (normalized unsigned byte, RGBA with alpha 255), and
/// 16-bit indices when the floor has up to 65535 vertices, else 32-bit. No texture images in v1.
/// Floors keep their own capture frame (no node transform), as the contract defines.
public enum GLBWriter {
  private static let magic: UInt32 = 0x4654_6C67  // "glTF"
  private static let jsonChunk: UInt32 = 0x4E4F_534A  // "JSON"
  private static let binChunk: UInt32 = 0x004E_4942  // "BIN\0"

  public static func encode(
    floors: [FloorMesh], generatorVersion: String = ExportInfo.version
  ) throws -> Data {
    guard !floors.isEmpty else { throw MeshExportError.emptyMesh }
    var bin = ByteBuffer()
    var bufferViews: [String] = []
    var accessors: [String] = []
    var meshes: [String] = []
    var nodes: [String] = []

    for floor in floors {
      try floor.mesh.validate()
      let mesh = floor.mesh.withNormals()
      let count = mesh.vertexCount
      let floorHasColors = !mesh.colors.isEmpty

      // POSITION
      let positionView = bufferViews.count
      bufferViews.append(view(offset: bin.count, length: count * 12, target: 34962))
      var lo = SIMD3<Float>(repeating: .infinity)
      var hi = SIMD3<Float>(repeating: -.infinity)
      for p in mesh.positions {
        bin.append(p.x)
        bin.append(p.y)
        bin.append(p.z)
        lo = pointwiseMin(lo, p)
        hi = pointwiseMax(hi, p)
      }
      let positionAccessor = accessors.count
      accessors.append(
        """
        {"bufferView":\(positionView),"componentType":5126,"count":\(count),"type":"VEC3",\
        "min":[\(num(lo.x)),\(num(lo.y)),\(num(lo.z))],"max":[\(num(hi.x)),\(num(hi.y)),\(num(hi.z))]}
        """)

      // NORMAL
      let normalView = bufferViews.count
      bufferViews.append(view(offset: bin.count, length: count * 12, target: 34962))
      for n in mesh.normals {
        bin.append(n.x)
        bin.append(n.y)
        bin.append(n.z)
      }
      let normalAccessor = accessors.count
      accessors.append(
        "{\"bufferView\":\(normalView),\"componentType\":5126,\"count\":\(count),\"type\":\"VEC3\"}")

      // COLOR_0
      var colorAccessor: Int?
      if floorHasColors {
        let colorView = bufferViews.count
        bufferViews.append(view(offset: bin.count, length: count * 4, target: 34962))
        for c in mesh.colors {
          bin.append(c.r)
          bin.append(c.g)
          bin.append(c.b)
          bin.append(UInt8(255))
        }
        colorAccessor = accessors.count
        accessors.append(
          "{\"bufferView\":\(colorView),\"componentType\":5121,\"normalized\":true,\"count\":\(count),\"type\":\"VEC4\"}"
        )
      }

      // Indices
      let wide = count > 65535
      let indexView = bufferViews.count
      let indexBytes = mesh.indices.count * (wide ? 4 : 2)
      bufferViews.append(view(offset: bin.count, length: indexBytes, target: 34963))
      for index in mesh.indices {
        if wide { bin.append(index) } else { bin.append(UInt16(index)) }
      }
      bin.padTo4()
      let indexAccessor = accessors.count
      accessors.append(
        """
        {"bufferView":\(indexView),"componentType":\(wide ? 5125 : 5123),\
        "count":\(mesh.indices.count),"type":"SCALAR"}
        """)

      var attributes = "\"POSITION\":\(positionAccessor),\"NORMAL\":\(normalAccessor)"
      if let colorAccessor { attributes += ",\"COLOR_0\":\(colorAccessor)" }
      meshes.append(
        """
        {"name":\(quote(floor.areaKey)),"primitives":[{"attributes":{\(attributes)},\
        "indices":\(indexAccessor),"material":0,"mode":4}]}
        """)
      nodes.append(
        """
        {"name":\(quote(floor.areaKey)),"mesh":\(meshes.count - 1),\
        "extras":{"areaKey":\(quote(floor.areaKey)),"label":\(quote(floor.label))}}
        """)
    }

    let nodeIndices = (0..<nodes.count).map(String.init).joined(separator: ",")
    let materialColor = "[1,1,1,1]"
    let json = """
      {"asset":{"version":"2.0","generator":\(quote(ExportInfo.generator(version: generatorVersion)))},\
      "scene":0,"scenes":[{"name":"Chapter Capture","nodes":[\(nodeIndices)]}],\
      "nodes":[\(nodes.joined(separator: ","))],\
      "meshes":[\(meshes.joined(separator: ","))],\
      "materials":[{"name":"vertex-colour","doubleSided":true,\
      "pbrMetallicRoughness":{"baseColorFactor":\(materialColor),"metallicFactor":0,"roughnessFactor":1}}],\
      "accessors":[\(accessors.joined(separator: ","))],\
      "bufferViews":[\(bufferViews.joined(separator: ","))],\
      "buffers":[{"byteLength":\(bin.count)}]}
      """
    var jsonBytes = Array(json.utf8)
    while jsonBytes.count % 4 != 0 { jsonBytes.append(0x20) }

    var out = ByteBuffer(capacity: 12 + 8 + jsonBytes.count + 8 + bin.count)
    out.append(magic)
    out.append(UInt32(2))
    out.append(UInt32(12 + 8 + jsonBytes.count + 8 + bin.count))
    out.append(UInt32(jsonBytes.count))
    out.append(jsonChunk)
    out.append(contentsOf: jsonBytes)
    out.append(UInt32(bin.count))
    out.append(binChunk)
    out.append(contentsOf: bin.bytes)
    return Data(out.bytes)
  }

  @discardableResult
  public static func write(
    floors: [FloorMesh], to url: URL, generatorVersion: String = ExportInfo.version
  ) throws -> URL {
    let data = try encode(floors: floors, generatorVersion: generatorVersion)
    try data.write(to: url, options: .atomic)
    return url
  }

  private static func view(offset: Int, length: Int, target: Int) -> String {
    "{\"buffer\":0,\"byteOffset\":\(offset),\"byteLength\":\(length),\"target\":\(target)}"
  }

  /// Exact decimal of a float32 value (via Double, so it parses back to the same float).
  private static func num(_ value: Float) -> String {
    Double(value).description
  }

  private static func quote(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    return out + "\""
  }
}
