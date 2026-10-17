import XCTest

@testable import MeshExport

/// AC3: the OBJ references its MTL by relative path and every referenced file exists.
final class OBJCompanionTests: XCTestCase {
  func testEveryFixtureOBJReferencesItsMTLByRelativePathAndTheFileExists() throws {
    for capture in try Fixtures.allCaptures() {
      let directory = Fixtures.outputDirectory(capture.fixture, capture.truth.areaKey)
      let package = try OBJWriter.write(floors: [try capture.floorMesh()], to: directory)
      let obj = OBJContents(try String(contentsOf: package.objURL, encoding: .utf8))
      let name = "\(capture.fixture)/\(capture.truth.areaKey)"

      XCTAssertEqual(obj.mtllib, ["mesh.mtl"], name)
      for reference in obj.mtllib {
        XCTAssertFalse(reference.hasPrefix("/"), "\(name): absolute path")
        XCTAssertFalse(reference.contains("/"), "\(name): path, not a bare file name")
        XCTAssertFalse(reference.contains("\\"), name)
        XCTAssertFalse(reference.contains(":"), name)
        let companion = package.objURL.deletingLastPathComponent().appendingPathComponent(reference)
        XCTAssertTrue(FileManager.default.fileExists(atPath: companion.path), "\(name): \(reference) missing")
        XCTAssertEqual(companion, package.mtlURL)
      }
      XCTAssertEqual(package.objURL.lastPathComponent, "mesh.obj")
      XCTAssertEqual(package.mtlName, "mesh.mtl")

      // The MTL defines the material the OBJ uses, and references no other file (no textures in v1).
      let mtl = try String(contentsOf: package.mtlURL, encoding: .utf8)
      let defined = mtl.split(separator: "\n").filter { $0.hasPrefix("newmtl ") }.map { String($0.dropFirst(7)) }
      XCTAssertFalse(defined.isEmpty)
      XCTAssertTrue(Set(obj.materialsUsed).isSubset(of: Set(defined)), name)
      XCTAssertFalse(mtl.contains("map_"), "\(name): no texture maps in v1")
      XCTAssertFalse(mtl.contains("/Users/") || mtl.contains("/home/"), name)
    }
  }

  func testFolderCanBeMovedAndStillResolves() throws {
    let capture = try Fixtures.captures(of: "box-room")[0]
    let source = FileManager.default.temporaryDirectory
      .appendingPathComponent("obj-companion-\(UUID().uuidString)/a")
    let package = try OBJWriter.write(floors: [try capture.floorMesh()], to: source)
    let target = source.deletingLastPathComponent().appendingPathComponent("moved elsewhere")
    try FileManager.default.moveItem(at: source, to: target)
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }
    let obj = OBJContents(
      try String(contentsOf: target.appendingPathComponent(package.objURL.lastPathComponent), encoding: .utf8))
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: target.appendingPathComponent(obj.mtllib[0]).path))
  }

  func testVertexColoursAreWrittenAsPerVertexRGB() throws {
    let capture = try Fixtures.captures(of: "box-room")[0]
    let floor = try capture.floorMesh()
    let (objData, _, _) = try OBJWriter.encode(floors: [floor])
    let obj = OBJContents(String(decoding: objData, as: UTF8.self))
    XCTAssertEqual(obj.positions.count, floor.mesh.vertexCount)
    XCTAssertTrue(obj.positions.allSatisfy { $0.count == 6 }, "v x y z r g b")
    XCTAssertEqual(obj.normalCount, floor.mesh.vertexCount)
    for (index, p) in obj.positions.enumerated() {
      let color = floor.mesh.colors[index]
      XCTAssertEqual(p[3], Double(color.r) / 255, accuracy: 1e-4)
      XCTAssertEqual(p[4], Double(color.g) / 255, accuracy: 1e-4)
      XCTAssertEqual(p[5], Double(color.b) / 255, accuracy: 1e-4)
      XCTAssertTrue((0...1).contains(p[3]) && (0...1).contains(p[4]) && (0...1).contains(p[5]))
    }
    XCTAssertEqual(obj.faces.count, floor.mesh.triangleCount)
    // 1-based indices that point at the same vertices as the mesh.
    XCTAssertEqual(obj.faces[0], floor.mesh.indices[0..<3].map { Int($0) + 1 })
  }

  func testMeshWithoutColoursWritesPlainVertices() throws {
    let capture = try Fixtures.captures(of: "box-room")[0]
    let floor = try capture.floorMesh(withColors: false)
    let obj = OBJContents(String(decoding: try OBJWriter.encode(floors: [floor]).obj, as: UTF8.self))
    XCTAssertTrue(obj.positions.allSatisfy { $0.count == 3 })
  }

  func testBaseNameMustBeAPlainFileName() throws {
    let floor = try Fixtures.captures(of: "box-room")[0].floorMesh()
    for bad in ["", "..", "../mesh", "/abs/mesh", "a/b", "a\\b", "has space", "tab\t", "caf\u{e9}"] {
      XCTAssertThrowsError(try OBJWriter.encode(floors: [floor], baseName: bad), "'\(bad)'")
    }
    let named = try OBJWriter.encode(floors: [floor], baseName: "Living-Room_1")
    XCTAssertTrue(String(decoding: named.obj, as: UTF8.self).contains("mtllib Living-Room_1.mtl\n"))
    XCTAssertEqual(named.mtlName, "Living-Room_1.mtl")
  }

  func testNumberFormatting() {
    func fixed(_ v: Double, _ d: Int) -> String {
      var out: [UInt8] = []
      DecimalText.appendFixed(v, decimals: d, to: &out)
      return String(decoding: out, as: UTF8.self)
    }
    XCTAssertEqual(fixed(0, 6), "0.000000")
    XCTAssertEqual(fixed(-0.0000001, 6), "0.000000")
    XCTAssertEqual(fixed(-1.5, 6), "-1.500000")
    XCTAssertEqual(fixed(2.7, 6), "2.700000")
    XCTAssertEqual(fixed(0.000123, 6), "0.000123")
    XCTAssertEqual(fixed(12.3456785, 3), "12.346")
    XCTAssertEqual(fixed(0.999999999, 4), "1.0000")
  }
}
