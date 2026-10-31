import CaptureContract
import MeshExport
import SketchSolver
import XCTest

@testable import SketchMesh

/// Spec F16 section 5: furniture as coloured boxes, and colour on every part of the model.
final class FurnitureMeshTests: XCTestCase {
  private static let visitId = LowercaseUUID(rawValue: "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")!
  private static let captureId = LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!

  private func mm(_ value: Double) -> SketchMeasurements.Length {
    SketchMeasurements.Length(valueMm: value, enteredUnit: .mm, enteredText: "\(Int(value))", measured: true)
  }

  /// A 4 x 3 m room 2.5 m high with a door and the given furniture, solved.
  private func model(_ furniture: [SketchMeasurements.Furniture]) throws -> CaptureModel {
    let room = SketchMeasurements.Room(
      id: "room-1", label: "Living room",
      walls: [
        SketchMeasurements.Wall(id: "wall-1", length: mm(4000)),
        SketchMeasurements.Wall(id: "wall-2", length: mm(3000)),
        SketchMeasurements.Wall(id: "wall-3"), SketchMeasurements.Wall(id: "wall-4"),
      ],
      openings: [
        SketchMeasurements.Opening(
          id: "door-1", kind: .door, wallId: "wall-2", width: mm(900), fromCorner: .start,
          fromCornerDistance: mm(500))
      ], furniture: furniture)
    let measurements = SketchMeasurements(
      visitId: Self.visitId, captureId: Self.captureId, areaKey: "floor-1", displayUnits: .metric,
      source: SketchMeasurements.Source(kind: .none), ceilingHeight: mm(2500), rooms: [room])
    return try SketchSolver.solve(measurements, context: SketchSolveContext(label: "Floor 1")).model
  }

  private struct Face {
    var points: [SIMD3<Double>]
    var colour: RGB8

    var normal: SIMD3<Double> {
      let u = points[1] - points[0]
      let v = points[2] - points[0]
      return SIMD3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
    }

    var centre: SIMD3<Double> { (points[0] + points[1] + points[2]) / 3 }
  }

  private func faces(_ mesh: TriangleMesh) -> [Face] {
    stride(from: 0, to: mesh.indices.count, by: 3).map { corner in
      let indices = (0..<3).map { Int(mesh.indices[corner + $0]) }
      let points = indices.map { index -> SIMD3<Double> in
        let p = mesh.positions[index]
        return SIMD3(Double(p.x), Double(p.y), Double(p.z))
      }
      XCTAssertEqual(mesh.colors[indices[0]], mesh.colors[indices[1]])
      XCTAssertEqual(mesh.colors[indices[0]], mesh.colors[indices[2]])
      return Face(points: points, colour: mesh.colors[indices[0]])
    }
  }

  func testEveryVertexIsColouredByWhatItBelongsTo() throws {
    let mesh = try SketchMesh.extrude(model([]))
    XCTAssertEqual(mesh.colors.count, mesh.vertexCount)
    let all = faces(mesh)
    let floor = all.filter { $0.points.allSatisfy { abs($0.y) < 1e-6 } && $0.normal.y > 0 }
    XCTAssertFalse(floor.isEmpty)
    XCTAssertTrue(floor.allSatisfy { $0.colour == SketchMeshPalette.floor })
    let ceiling = all.filter { $0.points.allSatisfy { abs($0.y - 2.5) < 1e-5 } && $0.normal.y < 0 }
    XCTAssertTrue(ceiling.contains { $0.colour == SketchMeshPalette.ceiling })
    // The door's jambs and head face into the hole: light grey.
    let reveals = all.filter { $0.colour == SketchMeshPalette.reveal }
    XCTAssertEqual(reveals.count, 6, "two jambs and a head, two triangles each")
    // Everything else is wall.
    let others = Set(all.map { "\($0.colour)" })
    XCTAssertEqual(
      others,
      Set(
        [SketchMeshPalette.floor, SketchMeshPalette.ceiling, SketchMeshPalette.reveal, SketchMeshPalette.wall]
          .map { "\($0)" }))
  }

  func testFurnitureIsAClosedTurnedBoxInItsColour() throws {
    // A 2 x 1 m table at (2, −1.5), turned 90° counter-clockwise: its 2 m runs along z.
    let table = SketchMeasurements.Furniture(
      id: "furniture-1", category: .table, x: 2, z: -1.5, widthM: 2, depthM: 1, angleDeg: 90)
    let mesh = try SketchMesh.extrude(model([table]))
    XCTAssertNoThrow(try mesh.validate())
    let box = faces(mesh).filter { $0.colour == SketchMeshPalette.furniture(.table) }
    XCTAssertEqual(box.count, 12)
    let points = box.flatMap(\.points)
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    let zs = points.map(\.z)
    XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), 1, accuracy: 1e-5)
    XCTAssertEqual((zs.max() ?? 0) - (zs.min() ?? 0), 2, accuracy: 1e-5)
    XCTAssertEqual(ys.min() ?? 1, 0, accuracy: 1e-6)
    XCTAssertEqual(ys.max() ?? 0, 0.75, accuracy: 1e-6)
    // Closed and facing out: every face's normal points away from the box centre, and the
    // signed volume is the box's.
    let centre = SIMD3<Double>(2, 0.375, -1.5)
    var volume = 0.0
    for face in box {
      let n = face.normal
      let away = face.centre - centre
      XCTAssertGreaterThan(n.x * away.x + n.y * away.y + n.z * away.z, 0)
      let a = face.points[0] - centre
      let b = face.points[1] - centre
      let c = face.points[2] - centre
      let first: Double = a.x * (b.y * c.z - b.z * c.y)
      let second: Double = a.y * (b.x * c.z - b.z * c.x)
      let third: Double = a.z * (b.x * c.y - b.y * c.x)
      volume += (first - second + third) / 6
    }
    XCTAssertEqual(volume, 2 * 1 * 0.75, accuracy: 1e-5)
  }

  func testFurnitureNeverRaisesTheModelAboveTheRoomOrBelowTheFloor() throws {
    let shelf = SketchMeasurements.Furniture(
      id: "furniture-1", category: .storage, x: 1, z: -1, widthM: 1, depthM: 0.4, heightM: 4)
    let stairs = SketchMeasurements.Furniture(
      id: "furniture-2", category: .stairs, x: 3, z: -2, widthM: 0.9, depthM: 2.5, angleDeg: 30)
    let model = try model([shelf, stairs])
    let mesh = try SketchMesh.extrude(model)
    let bounds = try XCTUnwrap(mesh.bounds)
    XCTAssertEqual(Double(bounds.min.y), 0, accuracy: 1e-6)
    XCTAssertEqual(Double(bounds.max.y), 2.5, accuracy: 1e-5)

    // An object placed out of range by other code is clamped the same way.
    var lifted = model
    lifted.objects.append(
      CaptureModel.DetectedObject(
        id: "lamp", category: .other,
        box: CaptureModel.OrientedBox(
          center: Vec3(x: 1, y: 2.4, z: -1), sizeM: Vec3(x: 0.3, y: 0.6, z: 0.3))))
    lifted.objects.append(
      CaptureModel.DetectedObject(
        id: "sunk", category: .other,
        box: CaptureModel.OrientedBox(
          center: Vec3(x: 2, y: 0, z: -1), sizeM: Vec3(x: 0.3, y: 0.6, z: 0.3))))
    let clamped = try XCTUnwrap(try SketchMesh.extrude(lifted).bounds)
    XCTAssertEqual(Double(clamped.min.y), 0, accuracy: 1e-6)
    XCTAssertEqual(Double(clamped.max.y), 2.5, accuracy: 1e-5)
  }

  func testTheBoxAxesFollowTheQuaternion() {
    let half: Double = 30 * Double.pi / 360
    let axes = MeshBuilder.axes(of: Quaternion(x: 0, y: sin(half), z: 0, w: cos(half)))
    let radians: Double = 30 * Double.pi / 180
    XCTAssertEqual(axes.x.x, cos(radians), accuracy: 1e-12)
    XCTAssertEqual(axes.x.z, -sin(radians), accuracy: 1e-12, "counter-clockwise seen from +Y")
    XCTAssertEqual(axes.z.x, sin(radians), accuracy: 1e-12)
    XCTAssertEqual(axes.z.z, cos(radians), accuracy: 1e-12)
  }
}
