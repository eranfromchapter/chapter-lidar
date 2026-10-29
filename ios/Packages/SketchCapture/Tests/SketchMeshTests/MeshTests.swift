import CaptureContract
import MeshExport
import SketchSolver
import XCTest

@testable import SketchMesh

/// AC4: the extruded mesh is +Y up with horizontal floor faces at Y 0, a height extent equal to
/// the ceiling height, openings cut through the walls, and it writes through the MeshExport
/// writers.
final class MeshTests: XCTestCase {
  private static let visitId = LowercaseUUID(rawValue: "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")!
  private static let captureId = LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!

  private func mm(_ value: Double) -> SketchMeasurements.Length {
    SketchMeasurements.Length(valueMm: value, enteredUnit: .mm, enteredText: "\(Int(value))", measured: true)
  }

  /// The 4.000 x 3.000 m room of AC1 with its door and window, solved.
  private func rectangleModel() throws -> CaptureModel {
    let room = SketchMeasurements.Room(
      id: "room-1", label: "Kitchen",
      walls: [
        SketchMeasurements.Wall(id: "wall-1", length: mm(4000)),
        SketchMeasurements.Wall(id: "wall-2", length: mm(3000)),
        SketchMeasurements.Wall(id: "wall-3"), SketchMeasurements.Wall(id: "wall-4"),
      ],
      openings: [
        SketchMeasurements.Opening(
          id: "door-1", kind: .door, wallId: "wall-2", width: mm(900), fromCorner: .start,
          fromCornerDistance: mm(500)),
        SketchMeasurements.Opening(
          id: "window-1", kind: .window, wallId: "wall-1", width: mm(1200), height: mm(1200),
          sill: mm(900), fromCorner: .end, fromCornerDistance: mm(1000)),
      ])
    let measurements = SketchMeasurements(
      visitId: Self.visitId, captureId: Self.captureId, areaKey: "floor-1", displayUnits: .metric,
      source: SketchMeasurements.Source(kind: .none), ceilingHeight: mm(2700), rooms: [room])
    return try SketchSolver.solve(measurements, context: SketchSolveContext(label: "Floor 1")).model
  }

  private struct Triangle {
    var a: SIMD3<Double>
    var b: SIMD3<Double>
    var c: SIMD3<Double>

    var normal: SIMD3<Double> {
      let u = b - a
      let v = c - a
      return SIMD3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
    }

    var area: Double {
      let n = normal
      return (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot() / 2
    }

    /// True when `p` lies in the triangle's plane and inside it (edges included).
    func contains(_ p: SIMD3<Double>, tolerance: Double = 1e-6) -> Bool {
      let n = normal
      let length = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
      guard length > 1e-12 else { return false }
      let unit = n / length
      let w = p - a
      guard abs(w.x * unit.x + w.y * unit.y + w.z * unit.z) <= tolerance else { return false }
      // Same side of every edge, in the plane.
      func cross(_ u: SIMD3<Double>, _ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
      }
      func dot(_ u: SIMD3<Double>, _ v: SIMD3<Double>) -> Double { u.x * v.x + u.y * v.y + u.z * v.z }
      let s1 = dot(cross(b - a, p - a), unit)
      let s2 = dot(cross(c - b, p - b), unit)
      let s3 = dot(cross(a - c, p - c), unit)
      return s1 >= -tolerance && s2 >= -tolerance && s3 >= -tolerance
    }
  }

  private func triangles(_ mesh: TriangleMesh) -> [Triangle] {
    stride(from: 0, to: mesh.indices.count, by: 3).map { corner in
      func point(_ index: UInt32) -> SIMD3<Double> {
        let p = mesh.positions[Int(index)]
        return SIMD3(Double(p.x), Double(p.y), Double(p.z))
      }
      return Triangle(
        a: point(mesh.indices[corner]), b: point(mesh.indices[corner + 1]),
        c: point(mesh.indices[corner + 2]))
    }
  }

  func testRectangleMeshIsYUpWithTheFloorAtZeroAndTheCeilingHeightExtent() throws {
    let model = try rectangleModel()
    let mesh = try SketchMesh.extrude(model)
    XCTAssertNoThrow(try mesh.validate())
    let bounds = try XCTUnwrap(mesh.bounds)
    XCTAssertEqual(Double(bounds.min.y), 0, accuracy: 1e-6)
    XCTAssertEqual(Double(bounds.max.y), 2.7, accuracy: 1e-5)
    // Plan extents: the room plus a wall thickness each way.
    XCTAssertEqual(Double(bounds.min.x), -0.1143, accuracy: 1e-5)
    XCTAssertEqual(Double(bounds.max.x), 4.1143, accuracy: 1e-5)
    XCTAssertEqual(Double(bounds.min.z), -3.1143, accuracy: 1e-5)
    XCTAssertEqual(Double(bounds.max.z), 0.1143, accuracy: 1e-5)

    // Horizontal faces at the lowest Y facing up add up to the room area; the ceiling underside
    // at the room height faces down with the same area.
    let all = triangles(mesh)
    let floor = all.filter { t in
      [t.a, t.b, t.c].allSatisfy { abs($0.y) < 1e-6 } && t.normal.y > 0
    }
    XCTAssertEqual(floor.reduce(0) { $0 + $1.area }, 12, accuracy: 1e-4)
    let ceiling = all.filter { t in
      [t.a, t.b, t.c].allSatisfy { abs($0.y - 2.7) < 1e-5 } && t.normal.y < 0
    }
    XCTAssertEqual(ceiling.reduce(0) { $0 + $1.area }, 12, accuracy: 1e-4)
    for t in all {
      XCTAssertGreaterThan(t.area, 1e-9, "no degenerate triangle")
    }
  }

  func testWallFacesFaceOutwardFromTheSolid() throws {
    let model = try rectangleModel()
    let mesh = try SketchMesh.extrude(model)
    let all = triangles(mesh)
    // Wall 1 runs along x at z in [0, 0.1143]: its room-side face at z = 0 faces −z (into the
    // room, away from the wall's solid) and its far face at z = 0.1143 faces +z.
    let inner = all.filter { t in [t.a, t.b, t.c].allSatisfy { abs($0.z) < 1e-6 && $0.x > -0.05 && $0.x < 4.05 } }
    XCTAssertFalse(inner.isEmpty)
    XCTAssertTrue(inner.allSatisfy { $0.normal.z < 0 }, "inside face of wall 1 faces the room")
    let outer = all.filter { t in [t.a, t.b, t.c].allSatisfy { abs($0.z - 0.1143) < 1e-5 } }
    XCTAssertFalse(outer.isEmpty)
    XCTAssertTrue(outer.allSatisfy { $0.normal.z > 0 }, "outside face of wall 1 faces away")
    // Wall tops face up, wall undersides face down.
    let tops = all.filter { t in [t.a, t.b, t.c].allSatisfy { abs($0.y - 2.7) < 1e-5 } && t.normal.y > 0 }
    XCTAssertEqual(tops.reduce(0) { $0 + $1.area }, 4 * 0.1143 * 2 + 3 * 0.1143 * 2 + 4 * 0.1143 * 0.1143, accuracy: 1e-3)
  }

  func testOpeningsAreCutThroughBothWallFaces() throws {
    let model = try rectangleModel()
    let mesh = try SketchMesh.extrude(model)
    let all = triangles(mesh)
    let door = model.doors[0]
    let wall2 = try XCTUnwrap(model.walls.first { $0.id == "wall-2" })
    // The door's centre at mid height, on the inside face, the outside face and in between.
    let centreZ = wall2.start.z - door.offsetM
    let midHeight = door.heightM / 2
    for x in [4.0, 4.05715, 4.1143] {
      let point = SIMD3<Double>(x, midHeight, centreZ)
      XCTAssertFalse(all.contains { $0.contains(point) }, "a triangle covers the door at x \(x)")
    }
    // The window the same way, at the middle of its height.
    let window = model.windows[0]
    let wall1 = try XCTUnwrap(model.walls.first { $0.id == "wall-1" })
    let windowX = wall1.start.x + window.offsetM
    let windowY = window.bottomM + window.heightM / 2
    for z in [0.0, 0.05715, 0.1143] {
      let point = SIMD3<Double>(windowX, windowY, z)
      XCTAssertFalse(all.contains { $0.contains(point) }, "a triangle covers the window at z \(z)")
    }
    // Solid wall beside the door and under the window is covered, so the check means something.
    XCTAssertTrue(all.contains { $0.contains(SIMD3<Double>(4.0, 1.0, -2.5)) }, "wall 2 beside the door")
    XCTAssertTrue(all.contains { $0.contains(SIMD3<Double>(windowX, 0.45, 0)) }, "wall 1 under the window")
    XCTAssertTrue(all.contains { $0.contains(SIMD3<Double>(windowX, 2.4, 0)) }, "wall 1 over the window")
    XCTAssertTrue(all.contains { $0.contains(SIMD3<Double>(4.0, 2.5, centreZ)) }, "wall 2 over the door")
    // The sill of the window faces up at its height and the head faces down.
    let sills = all.filter { t in
      [t.a, t.b, t.c].allSatisfy {
        abs($0.y - window.bottomM) < 1e-6 && $0.x > windowX - 0.6 - 1e-5 && $0.x < windowX + 0.6 + 1e-5
          && $0.z > -1e-5 && $0.z < 0.1143 + 1e-5
      }
    }
    XCTAssertEqual(sills.reduce(0) { $0 + $1.area }, 1.2 * 0.1143, accuracy: 1e-4)
    XCTAssertTrue(sills.allSatisfy { $0.normal.y > 0 })
  }

  func testWritesThroughTheGLBAndOBJWriters() throws {
    let model = try rectangleModel()
    let mesh = try SketchMesh.extrude(model)
    let floor = FloorMesh(areaKey: model.areaKey, label: model.label, mesh: mesh)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SketchMeshTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let glbURL = try GLBWriter.write(floors: [floor], to: directory.appendingPathComponent("mesh.glb"))
    let glb = try Data(contentsOf: glbURL)
    XCTAssertGreaterThan(glb.count, 12)
    XCTAssertEqual(glb[0..<4], Data("glTF".utf8))

    let obj = try OBJWriter.write(floors: [floor], to: directory)
    let text = try String(contentsOf: obj.objURL, encoding: .utf8)
    XCTAssertTrue(text.contains("v "))
    XCTAssertTrue(text.contains("f "))
    XCTAssertTrue(FileManager.default.fileExists(atPath: obj.mtlURL.path))
  }

  func testLShapedFloorIsTriangulatedByEarClipping() throws {
    let loop: [SIMD2<Double>] = [
      SIMD2(0, 0), SIMD2(4, 0), SIMD2(4, 1.5), SIMD2(2.5, 1.5), SIMD2(2.5, 3), SIMD2(0, 3),
    ]
    let triangles = EarClipping.triangulate(loop)
    XCTAssertEqual(triangles.count, 4, "n − 2 triangles")
    var area = 0.0
    for (i, j, k) in triangles {
      let a = loop[i]
      let b = loop[j]
      let c = loop[k]
      let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
      XCTAssertGreaterThan(cross, 0, "counter-clockwise")
      area += cross / 2
    }
    XCTAssertEqual(area, 4 * 3 - 1.5 * 1.5, accuracy: 1e-9)
    // The reflex corner (2.5, 1.5) must not be inside any triangle that does not use it.
    for (i, j, k) in triangles where ![i, j, k].contains(3) {
      let a = loop[i]
      let b = loop[j]
      let c = loop[k]
      let p = loop[3]
      func side(_ p1: SIMD2<Double>, _ p2: SIMD2<Double>) -> Double {
        (p2.x - p1.x) * (p.y - p1.y) - (p2.y - p1.y) * (p.x - p1.x)
      }
      let inside = side(a, b) > 1e-9 && side(b, c) > 1e-9 && side(c, a) > 1e-9
      XCTAssertFalse(inside)
    }
  }

  func testFacePiecesLeaveTheHolesOut() {
    let pieces = MeshBuilder.facePieces(
      length: 4, height: 2.7,
      holes: [
        MeshBuilder.Hole(a0: 0.5, a1: 1.4, y0: 0, y1: 2.032),
        MeshBuilder.Hole(a0: 2, a1: 3.2, y0: 0.9, y1: 2.1),
      ])
    XCTAssertEqual(pieces.count, 6)
    let area = pieces.reduce(0) { $0 + ($1.a1 - $1.a0) * ($1.y1 - $1.y0) }
    XCTAssertEqual(area, 4 * 2.7 - 0.9 * 2.032 - 1.2 * 1.2, accuracy: 1e-9)
  }

  func testEmptyModelIsRefused() {
    let model = CaptureModel(
      visitId: Self.visitId, captureId: Self.captureId, areaKey: "floor-1", label: "Floor 1")
    XCTAssertThrowsError(try SketchMesh.extrude(model)) { error in
      XCTAssertEqual(error as? SketchMeshError, .noGeometry)
    }
  }

  func testTwoRoomModelHeightExtentIsTheTallestRoom() throws {
    var model = try rectangleModel()
    var second = model.rooms[0]
    second.id = "room-2"
    second.heightM = 3.2
    second.polygon = second.polygon.map { Vec3(x: $0.x + 6, y: 0, z: $0.z) }
    model.rooms.append(second)
    let mesh = try SketchMesh.extrude(model)
    let bounds = try XCTUnwrap(mesh.bounds)
    XCTAssertEqual(Double(bounds.min.y), 0, accuracy: 1e-6)
    XCTAssertEqual(Double(bounds.max.y), 3.2, accuracy: 1e-5)
  }
}
