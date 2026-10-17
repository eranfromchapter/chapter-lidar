import CaptureContract
import XCTest

@testable import MeshExport

/// AC2: GLB and OBJ bounding boxes match truth.json within 2 mm and are +Y up.
final class GeometryTruthTests: XCTestCase {
  private let tolerance = 0.002

  private func assertBounds(
    _ lo: [Double], _ hi: [Double], truth: Fixtures.Truth.Capture.Bounds, _ label: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    for axis in 0..<3 {
      XCTAssertEqual(lo[axis], truth.min[axis], accuracy: tolerance, "\(label) min[\(axis)]", file: file, line: line)
      XCTAssertEqual(hi[axis], truth.max[axis], accuracy: tolerance, "\(label) max[\(axis)]", file: file, line: line)
    }
  }

  func testGLBAndOBJBoundsMatchTruthForEveryFixtureCapture() throws {
    for capture in try Fixtures.allCaptures() {
      let floor = try capture.floorMesh()
      let name = "\(capture.fixture)/\(capture.truth.areaKey)"
      let directory = Fixtures.outputDirectory(capture.fixture, capture.truth.areaKey)
      let report = try CaptureExporter.export(
        floors: [floor], depthSamples: try capture.depthSamples(), to: directory)

      let glb = try GLBContents.read(Data(contentsOf: report.glbURL))
      XCTAssertEqual(glb.nodes.count, 1, name)
      let node = glb.floorData(0)
      XCTAssertFalse(node.hasMatrix, "\(name): node must not rotate (+Y up as written)")
      var lo = [Double.infinity, .infinity, .infinity]
      var hi = [-Double.infinity, -.infinity, -.infinity]
      for p in node.positions {
        for (axis, v) in [p.x, p.y, p.z].enumerated() {
          lo[axis] = Swift.min(lo[axis], Double(v))
          hi[axis] = Swift.max(hi[axis], Double(v))
        }
      }
      assertBounds(lo, hi, truth: capture.truth.boundsM, "\(name) GLB")

      let obj = OBJContents(try String(contentsOf: report.objURL, encoding: .utf8))
      let bounds = obj.bounds
      assertBounds(bounds.min, bounds.max, truth: capture.truth.boundsM, "\(name) OBJ")

      // +Y up: the vertical extent is the room height (the model's heightM), not a horizontal one.
      let height = capture.model.rooms.map(\.heightM).max()!
      XCTAssertEqual(hi[1] - lo[1], height, accuracy: tolerance, "\(name) GLB height on Y")
      XCTAssertEqual(bounds.max[1] - bounds.min[1], height, accuracy: tolerance, "\(name) OBJ height on Y")
      XCTAssertEqual(lo[1], 0, accuracy: tolerance, "\(name) floor at y = 0")
    }
  }

  func testYUpCheckRejectsAZUpMesh() throws {
    // The fixtures' broken z-up-mesh has height along +Z. The same bounds check must fail on it.
    let capture = try Fixtures.captures(of: "box-room")[0]
    let glbURL = Fixtures.generated
      .appendingPathComponent("broken/z-up-mesh/package/Original Exports/floor-1")
    let enumerator = FileManager.default.enumerator(at: glbURL, includingPropertiesForKeys: nil)!
    var found: URL?
    for case let url as URL in enumerator where url.lastPathComponent == "mesh.glb" { found = url }
    let glb = try GLBContents.read(Data(contentsOf: XCTUnwrap(found)))
    let node = glb.floorData(0)
    let lo = [Double(node.positions.map(\.x).min()!), Double(node.positions.map(\.y).min()!)]
    let hi = [Double(node.positions.map(\.x).max()!), Double(node.positions.map(\.y).max()!)]
    let truth = capture.truth.boundsM
    let matches = (0..<2).allSatisfy {
      abs(lo[$0] - truth.min[$0]) <= tolerance && abs(hi[$0] - truth.max[$0]) <= tolerance
    }
    XCTAssertFalse(matches, "a z-up mesh must fail the bounds check on x and y")
  }

  func testTwoFloorHouseWritesOneNodePerFloorWithEachFloorsBounds() throws {
    let captures = try Fixtures.captures(of: "two-floor-house")
    XCTAssertEqual(captures.count, 2)
    let floors = try captures.map { try $0.floorMesh() }
    let directory = Fixtures.outputDirectory("two-floor-house", "combined")
    let report = try CaptureExporter.export(floors: floors, to: directory)
    let glb = try GLBContents.read(Data(contentsOf: report.glbURL))
    XCTAssertEqual(glb.nodes.count, 2)
    XCTAssertEqual(glb.nodes.map { $0["name"] as? String }, ["floor-1", "floor-2"])
    for (index, capture) in captures.enumerated() {
      let node = glb.floorData(index)
      let lo = (0..<3).map { axis in Double(node.positions.map { [$0.x, $0.y, $0.z][axis] }.min()!) }
      let hi = (0..<3).map { axis in Double(node.positions.map { [$0.x, $0.y, $0.z][axis] }.max()!) }
      assertBounds(lo, hi, truth: capture.truth.boundsM, "node \(index)")
    }
    let obj = OBJContents(try String(contentsOf: report.objURL, encoding: .utf8))
    XCTAssertEqual(obj.objects, ["floor-1", "floor-2"])
    // Face indices continue across objects and stay in range.
    XCTAssertEqual(obj.positions.count, floors.map { $0.mesh.vertexCount }.reduce(0, +))
    XCTAssertTrue(obj.faces.allSatisfy { $0.allSatisfy { (1...obj.positions.count).contains($0) } })
  }

  func testGLBMetadataColoursAndNormals() throws {
    let capture = try Fixtures.captures(of: "box-room")[0]
    let floor = try capture.floorMesh()
    let data = try GLBWriter.encode(floors: [floor], generatorVersion: "9.8.7")
    let glb = try GLBContents.read(data)
    XCTAssertEqual(glb.generator, "Chapter Capture 9.8.7")
    XCTAssertEqual((glb.json["asset"] as! [String: Any])["version"] as? String, "2.0")
    XCTAssertNil(glb.json["images"], "no texture images in v1")
    XCTAssertNil(glb.json["textures"])
    let node = glb.floorData(0)
    XCTAssertEqual(node.positions.count, floor.mesh.vertexCount)
    XCTAssertEqual(node.indices, floor.mesh.indices)
    XCTAssertEqual(node.colors.count, node.positions.count)
    XCTAssertEqual(node.colors.first!, [floor.mesh.colors[0].r, floor.mesh.colors[0].g, floor.mesh.colors[0].b, 255])
    for n in node.normals {
      XCTAssertEqual((n.x * n.x + n.y * n.y + n.z * n.z).squareRoot(), 1, accuracy: 1e-4)
    }
  }

  func testMissingNormalsAreComputedAndColoursAreOptional() throws {
    var mesh = try Fixtures.captures(of: "box-room")[0].floorMesh(withColors: false).mesh
    mesh.normals = []
    let glb = try GLBContents.read(
      GLBWriter.encode(floors: [FloorMesh(areaKey: "a", label: "A", mesh: mesh)]))
    let node = glb.floorData(0)
    XCTAssertEqual(node.normals.count, mesh.vertexCount)
    XCTAssertTrue(node.colors.isEmpty)
  }

  func testLargeFloorUsesWideIndices() throws {
    let base = try Fixtures.captures(of: "box-room")[0].floorMesh().mesh
    let big = MeshFactory.subdivided(base, 120)
    XCTAssertGreaterThan(big.vertexCount, 65535)
    let url = Fixtures.outputDirectory("wide-indices").appendingPathComponent("mesh.glb")
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try GLBWriter.write(floors: [FloorMesh(areaKey: "big", label: "Big", mesh: big)], to: url)
    let glb = try GLBContents.read(Data(contentsOf: url))
    let node = glb.floorData(0)
    XCTAssertEqual(node.indices, big.indices)
    let accessors = glb.json["accessors"] as! [[String: Any]]
    XCTAssertTrue(accessors.contains { ($0["componentType"] as? Int) == 5125 })
  }

  func testInvalidMeshesAreRejected() {
    let empty = TriangleMesh(positions: [], indices: [])
    XCTAssertThrowsError(try GLBWriter.encode(floors: [FloorMesh(areaKey: "a", label: "A", mesh: empty)]))
    let badIndex = TriangleMesh(positions: [.zero, .zero, .zero], indices: [0, 1, 3])
    XCTAssertThrowsError(try GLBWriter.encode(floors: [FloorMesh(areaKey: "a", label: "A", mesh: badIndex)]))
    XCTAssertThrowsError(try GLBWriter.encode(floors: []))
  }
}
