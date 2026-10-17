import Foundation

/// The two files of an OBJ package, with the names that were written.
public struct OBJPackage: Sendable, Equatable {
  public var objURL: URL
  public var mtlURL: URL
  /// File name of the MTL as referenced by `mtllib` (a bare file name, never a path).
  public var mtlName: String
}

/// Writes OBJ + MTL: same geometry as the GLB, metres, +Y up.
///
/// - One `o` object per floor (named by its area key); vertex, normal and face indices continue
///   across objects, as OBJ requires.
/// - Vertex colours are written as `v x y z r g b` (0 to 1), the de-facto extension that
///   MeshLab, Blender and CloudCompare read.
/// - The OBJ names its MTL with a bare file name in `mtllib` (same folder, no absolute path).
///   Both files share a base name, for example `mesh.obj` and `mesh.mtl`.
public enum OBJWriter {
  public static let defaultBaseName = "mesh"
  public static let materialName = "chapter_vertex_colour"

  /// File names for a base name, or an error if the base name is not a plain file name.
  public static func fileNames(baseName: String) throws -> (obj: String, mtl: String) {
    try validate(baseName: baseName)
    return ("\(baseName).obj", "\(baseName).mtl")
  }

  public static func encode(
    floors: [FloorMesh], baseName: String = defaultBaseName,
    generatorVersion: String = ExportInfo.version
  ) throws -> (obj: Data, mtl: Data, mtlName: String) {
    let names = try fileNames(baseName: baseName)
    guard !floors.isEmpty else { throw MeshExportError.emptyMesh }

    var out: [UInt8] = []
    DecimalText.append(
      "# \(ExportInfo.generator(version: generatorVersion)). Metres, +Y up.\n", to: &out)
    DecimalText.append("mtllib \(names.mtl)\n", to: &out)
    var vertexOffset: UInt64 = 0
    for floor in floors {
      try floor.mesh.validate()
      let mesh = floor.mesh.withNormals()
      DecimalText.append("o \(objectName(floor.areaKey))\n", to: &out)
      let hasColors = !mesh.colors.isEmpty
      for (index, p) in mesh.positions.enumerated() {
        out.append(UInt8(ascii: "v"))
        for value in [p.x, p.y, p.z] {
          out.append(UInt8(ascii: " "))
          DecimalText.appendFixed(Double(value), decimals: 6, to: &out)
        }
        if hasColors {
          let c = mesh.colors[index]
          for value in [c.r, c.g, c.b] {
            out.append(UInt8(ascii: " "))
            DecimalText.appendFixed(Double(value) / 255, decimals: 4, to: &out)
          }
        }
        out.append(UInt8(ascii: "\n"))
      }
      for n in mesh.normals {
        DecimalText.append("vn", to: &out)
        for value in [n.x, n.y, n.z] {
          out.append(UInt8(ascii: " "))
          DecimalText.appendFixed(Double(value), decimals: 6, to: &out)
        }
        out.append(UInt8(ascii: "\n"))
      }
      DecimalText.append("usemtl \(materialName)\ns off\n", to: &out)
      var corner = 0
      while corner + 2 < mesh.indices.count {
        out.append(UInt8(ascii: "f"))
        for k in 0..<3 {
          out.append(UInt8(ascii: " "))
          let index = UInt64(mesh.indices[corner + k]) + vertexOffset + 1
          DecimalText.appendInteger(index, to: &out)
          out.append(UInt8(ascii: "/"))
          out.append(UInt8(ascii: "/"))
          DecimalText.appendInteger(index, to: &out)
        }
        out.append(UInt8(ascii: "\n"))
        corner += 3
      }
      vertexOffset += UInt64(mesh.vertexCount)
    }

    let mtl = """
      # \(ExportInfo.generator(version: generatorVersion)). Colour comes from the vertex colours in the OBJ.
      newmtl \(materialName)
      Ka 1.000000 1.000000 1.000000
      Kd 1.000000 1.000000 1.000000
      Ks 0.000000 0.000000 0.000000
      d 1.000000
      illum 1

      """
    return (Data(out), Data(mtl.utf8), names.mtl)
  }

  /// Writes `<baseName>.obj` and `<baseName>.mtl` into `directory` (created if needed).
  @discardableResult
  public static func write(
    floors: [FloorMesh], to directory: URL, baseName: String = defaultBaseName,
    generatorVersion: String = ExportInfo.version
  ) throws -> OBJPackage {
    let names = try fileNames(baseName: baseName)
    let encoded = try encode(floors: floors, baseName: baseName, generatorVersion: generatorVersion)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let objURL = directory.appendingPathComponent(names.obj)
    let mtlURL = directory.appendingPathComponent(names.mtl)
    try encoded.obj.write(to: objURL, options: .atomic)
    try encoded.mtl.write(to: mtlURL, options: .atomic)
    return OBJPackage(objURL: objURL, mtlURL: mtlURL, mtlName: names.mtl)
  }

  private static func validate(baseName: String) throws {
    let bad = baseName.isEmpty || baseName == "." || baseName == ".."
      || baseName.contains("/") || baseName.contains("\\")
      || baseName.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
      || baseName.unicodeScalars.contains { $0.value < 0x20 || $0.value > 0x7E }
    if bad {
      throw MeshExportError.invalidOption(
        "OBJ base name must be a plain ASCII file name without spaces or path separators")
    }
  }

  private static func objectName(_ areaKey: String) -> String {
    let cleaned = String(
      areaKey.unicodeScalars.map { scalar -> Character in
        (scalar.value > 0x20 && scalar.value < 0x7F) ? Character(scalar) : "_"
      })
    return cleaned.isEmpty ? "floor" : cleaned
  }
}
