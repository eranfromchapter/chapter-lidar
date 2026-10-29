import CaptureContract
import CaptureTestSupport
import SketchSolver
import XCTest

/// Furniture drawn in a room (spec F16) becomes capture model objects.
final class FurnitureTests: XCTestCase {
  private func rectangle(
    furniture: [SketchMeasurements.Furniture], ceiling: Double? = 2700
  ) -> SketchMeasurements {
    Sketch.measurements(
      ceiling: ceiling,
      rooms: [
        SketchMeasurements.Room(
          id: "room-1", label: "Living room",
          walls: [
            Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"),
            Sketch.wall("wall-4"),
          ], furniture: furniture)
      ])
  }

  func testFurnitureBecomesOrientedBoxesOnTheFloor() throws {
    let sofa = SketchMeasurements.Furniture(
      id: "furniture-1", category: .sofa, x: 2, z: -1, widthM: 2.1, depthM: 0.9, angleDeg: 90)
    let model = try SketchSolver.solve(rectangle(furniture: [sofa]), context: Sketch.context).model
    XCTAssertEqual(model.objects.count, 1)
    let object = try XCTUnwrap(model.objects.first)
    XCTAssertEqual(object.id, "furniture-1")
    XCTAssertEqual(object.category, .sofa)
    XCTAssertEqual(object.roomId, "room-1")
    XCTAssertEqual(object.confidence, .low)
    assertVec(object.box.center, 2, 0.425, -1, accuracy: 1e-9)
    assertVec(object.box.sizeM, 2.1, 0.85, 0.9, accuracy: 1e-9)
    // 90° counter-clockwise about +Y: local +x points to −z.
    let q = object.box.rotation
    XCTAssertEqual(q.x, 0)
    XCTAssertEqual(q.z, 0)
    XCTAssertEqual(q.y, sin(Double.pi / 4), accuracy: 1e-9)
    XCTAssertEqual(q.w, cos(Double.pi / 4), accuracy: 1e-9)
    let xz: Double = 2 * (q.x * q.z - q.w * q.y)
    XCTAssertEqual(xz, -1, accuracy: 1e-9)
  }

  func testHeightsByCategoryGivenAndClampedToTheRoom() throws {
    let furniture = [
      SketchMeasurements.Furniture(id: "f-1", category: .bed, x: 1, z: -1, widthM: 1.5, depthM: 2),
      SketchMeasurements.Furniture(
        id: "f-2", category: .table, x: 2, z: -1, widthM: 1, depthM: 1, heightM: 1.1),
      SketchMeasurements.Furniture(
        id: "f-3", category: .storage, x: 3, z: -1, widthM: 1, depthM: 0.5, heightM: 3.5),
      SketchMeasurements.Furniture(id: "f-4", category: .stairs, x: 3, z: -2, widthM: 1, depthM: 2),
      SketchMeasurements.Furniture(id: "f-5", category: .other, x: 1, z: -2, widthM: 1, depthM: 1),
      SketchMeasurements.Furniture(id: "f-6", category: .refrigerator, x: 1, z: -2.5, widthM: 0.9, depthM: 0.8),
    ]
    let model = try SketchSolver.solve(rectangle(furniture: furniture, ceiling: 2400), context: Sketch.context).model
    XCTAssertEqual(model.objects.map(\.box.sizeM.y), [0.55, 1.1, 2.4, 2.4, 0.8, 1.8])
    for object in model.objects {
      XCTAssertEqual(object.box.center.y, object.box.sizeM.y / 2, accuracy: 1e-9)
      XCTAssertLessThanOrEqual(object.box.center.y + object.box.sizeM.y / 2, 2.4 + 1e-9)
    }
    XCTAssertEqual(model.objects.first?.box.rotation, .identity)
  }

  func testEveryCategoryHasAHeightOrTheRoomHeight() {
    for category in ObjectCategory.allCases {
      let height = SketchDefaults.furnitureHeightMm(category)
      if category == .stairs {
        XCTAssertNil(height)
      } else {
        XCTAssertGreaterThan(height ?? 0, 0, "\(category)")
      }
    }
  }

  func testFurnitureWithoutSizeIsLeftOutAndDuplicateIdsAreRefused() throws {
    let flat = SketchMeasurements.Furniture(id: "f-1", category: .table, x: 1, z: -1, widthM: 0, depthM: 1)
    let model = try SketchSolver.solve(rectangle(furniture: [flat]), context: Sketch.context).model
    XCTAssertTrue(model.objects.isEmpty)

    let a = SketchMeasurements.Furniture(id: "f-1", category: .chair, x: 1, z: -1, widthM: 0.5, depthM: 0.5)
    XCTAssertThrowsError(try SketchSolver.solve(rectangle(furniture: [a, a]), context: Sketch.context)) {
      XCTAssertEqual($0 as? SketchSolverError, .duplicateId("f-1"))
    }
  }

  func testTheModelWithFurnitureValidates() throws {
    let chair = SketchMeasurements.Furniture(
      id: "furniture-1", category: .chair, x: 1, z: -1, widthM: 0.5, depthM: 0.5, angleDeg: -45)
    let model = try SketchSolver.solve(rectangle(furniture: [chair]), context: Sketch.context).model
    let data = try CaptureContractJSON.makeEncoder().encode(model)
    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
    XCTAssertEqual(try validator.validate(jsonData: data), [])
  }
}
