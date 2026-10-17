import XCTest

@testable import MeshExport

/// Mesh decimation to a face budget that keeps planar edges.
final class DecimationTests: XCTestCase {
  private func boxRoomMesh(subdivisions: Int) throws -> TriangleMesh {
    MeshFactory.subdivided(try Fixtures.captures(of: "box-room")[0].floorMesh().mesh, subdivisions)
  }

  func testMeshWithinBudgetIsReturnedUnchanged() throws {
    let mesh = try Fixtures.captures(of: "box-room")[0].floorMesh().mesh
    let result = try MeshDecimator.decimate(mesh, faceBudget: 1_000)
    XCTAssertEqual(result.mesh, mesh)
    XCTAssertTrue(result.reachedBudget)
  }

  func testDefaultBudgetIsOnePointFiveMillion() {
    XCTAssertEqual(MeshDecimator.defaultFaceBudget, 1_500_000)
    XCTAssertEqual(ExportOptions().faceBudget, 1_500_000)
  }

  func testDecimatesToBudgetAndKeepsBoxGeometry() throws {
    let dense = try boxRoomMesh(subdivisions: 10)  // 12 triangles x 100
    XCTAssertEqual(dense.triangleCount, 1200)
    let areaBefore = MeshFactory.area(dense)
    let result = try MeshDecimator.decimate(dense, faceBudget: 200)
    let out = result.mesh
    XCTAssertTrue(result.reachedBudget)
    XCTAssertLessThanOrEqual(out.triangleCount, 200)
    XCTAssertGreaterThan(out.triangleCount, 12)

    // Bounds are unchanged: border and corner vertices are preserved.
    let before = dense.bounds!
    let after = out.bounds!
    for axis in 0..<3 {
      XCTAssertEqual(after.min[axis], before.min[axis], accuracy: 1e-5)
      XCTAssertEqual(after.max[axis], before.max[axis], accuracy: 1e-5)
    }
    // Every surviving vertex is on one of the six planes of the box (planar surfaces stay planar).
    let lo = before.min
    let hi = before.max
    for p in out.positions {
      let onPlane =
        abs(p.x - lo.x) < 1e-4 || abs(p.x - hi.x) < 1e-4 || abs(p.y - lo.y) < 1e-4
        || abs(p.y - hi.y) < 1e-4 || abs(p.z - lo.z) < 1e-4 || abs(p.z - hi.z) < 1e-4
      XCTAssertTrue(onPlane, "vertex \(p) left the box surface")
    }
    // All eight corners survive.
    for x in [lo.x, hi.x] {
      for y in [lo.y, hi.y] {
        for z in [lo.z, hi.z] {
          XCTAssertTrue(
            out.positions.contains { abs($0.x - x) < 1e-4 && abs($0.y - y) < 1e-4 && abs($0.z - z) < 1e-4 },
            "corner \(x),\(y),\(z) lost")
        }
      }
    }
    // The surface area is preserved.
    XCTAssertEqual(MeshFactory.area(out), areaBefore, accuracy: areaBefore * 1e-3)
    // Valid output: indices in range, unit normals, face normals agree with vertex normals.
    XCTAssertNoThrow(try out.validate())
    XCTAssertEqual(out.normals.count, out.positions.count)
    var corner = 0
    while corner + 2 < out.indices.count {
      let a = Int(out.indices[corner])
      let b = Int(out.indices[corner + 1])
      let c = Int(out.indices[corner + 2])
      let faceNormal = normalizedOrUp(cross3(out.positions[b] - out.positions[a], out.positions[c] - out.positions[a]))
      let vertexNormal = out.normals[a]
      XCTAssertGreaterThan(
        faceNormal.x * vertexNormal.x + faceNormal.y * vertexNormal.y + faceNormal.z * vertexNormal.z, 0.99,
        "normals stay sharp at box corners")
      corner += 3
    }
  }

  func testPlanarRoomCollapsesFarBelowTheInputWithoutLosingTheOutline() throws {
    // An L-shaped room: concave corners must survive too.
    let base = try Fixtures.captures(of: "l-shaped-room")[0].floorMesh().mesh
    let dense = MeshFactory.subdivided(base, 8)
    let result = try MeshDecimator.decimate(dense, faceBudget: base.triangleCount + 40)
    XCTAssertTrue(result.reachedBudget)
    XCTAssertLessThan(result.outputFaces, dense.triangleCount / 4)
    let before = dense.bounds!
    let after = result.mesh.bounds!
    XCTAssertEqual(after.min, before.min)
    XCTAssertEqual(after.max, before.max)
    // The inner (concave) floor corner (3, 0, 2) of the L outline stays.
    XCTAssertTrue(
      result.mesh.positions.contains { abs($0.x - 3) < 1e-4 && abs($0.y) < 1e-4 && abs($0.z - 2) < 1e-4 }
        || result.mesh.positions.contains { abs($0.x - 3) < 1e-4 && abs($0.y) < 1e-4 && abs($0.z - 2) < 1e-4 },
      "concave corner kept")
    XCTAssertEqual(MeshFactory.area(result.mesh), MeshFactory.area(dense), accuracy: MeshFactory.area(dense) * 1e-3)
  }

  func testColoursSurviveDecimation() throws {
    let base = try Fixtures.captures(of: "box-room")[0].floorMesh().mesh
    let dense = MeshFactory.subdivided(base, 6)
    XCTAssertFalse(dense.colors.isEmpty)
    let out = try MeshDecimator.decimate(dense, faceBudget: 150).mesh
    XCTAssertEqual(out.colors.count, out.positions.count)
  }

  func testBudgetBelowFourIsRejected() throws {
    let mesh = try Fixtures.captures(of: "box-room")[0].floorMesh().mesh
    XCTAssertThrowsError(try MeshDecimator.decimate(mesh, faceBudget: 2))
  }

  func testBudgetIsAppliedByTheExporter() throws {
    let dense = try boxRoomMesh(subdivisions: 12)
    let directory = Fixtures.outputDirectory("decimated", "box-room-budget-500")
    let report = try CaptureExporter.export(
      floors: [FloorMesh(areaKey: "floor-1", label: "Floor 1", mesh: dense)], to: directory,
      options: ExportOptions(faceBudget: 500))
    XCTAssertLessThanOrEqual(report.decimation[0].outputFaces, 500)
    let glb = try GLBContents.read(Data(contentsOf: report.glbURL))
    XCTAssertLessThanOrEqual(glb.floorData(0).indices.count / 3, 500)
  }
}
