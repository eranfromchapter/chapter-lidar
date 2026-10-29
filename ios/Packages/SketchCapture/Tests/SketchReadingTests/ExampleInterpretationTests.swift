import CaptureContract
import SketchReading
import SketchSolver
import XCTest

/// The contract examples `sketch-interpretation/valid/*.json` through the converter, the
/// schemas and the solver.
final class ExampleInterpretationTests: XCTestCase {
  private func convert() throws -> SketchReadingConversion {
    try Reading.convert(Reading.example("bedroom-and-closet"))
  }

  func testBedroomAndClosetConvertsAndValidates() throws {
    let conversion = try convert()
    let document = conversion.measurements
    try validate(document, schema: "sketch-measurements.schema.json")
    XCTAssertEqual(document.areaKey, "floor-1")
    XCTAssertEqual(document.visitId, Reading.visitId)
    XCTAssertEqual(document.captureId, Reading.captureId)
    XCTAssertEqual(
      document.source,
      SketchMeasurements.Source(
        kind: .handSketch, path: Reading.imagePath, interpretation: Reading.interpretationPath))
    XCTAssertEqual(document.rooms.map(\.id), ["room-1", "room-2"])
    XCTAssertEqual(document.rooms.map(\.label), ["Bedroom", "Closet"])
    XCTAssertEqual(document.rooms.map(\.type), [.bedroom, .closet])
    XCTAssertEqual(document.rooms.flatMap(\.walls).map(\.id), (1...8).map { "wall-\($0)" })
    XCTAssertEqual(document.rooms.flatMap(\.openings).map(\.id), ["window-1", "door-1", "door-2"])
    XCTAssertEqual(
      document.rooms.flatMap { $0.furniture ?? [] }.map(\.id), ["furniture-1", "furniture-2"])
    XCTAssertEqual(
      document.ceilingHeight,
      SketchMeasurements.Length(
        valueMm: 2438, enteredUnit: .ftIn, enteredText: "8' clg", measured: true))
    XCTAssertEqual(conversion.scaleSource, .writtenDimensions(count: 2))
    let wide: Double = 3988.0 / 460
    let deep: Double = 2997.0 / 345
    let expectedScale: Double = (wide + deep) / 2
    XCTAssertEqual(conversion.millimetresPerUnit, expectedScale, accuracy: 1e-9)

    // Both rooms are drawn clockwise on the page: rewound, corner 0 kept.
    XCTAssertTrue(conversion.notes.contains("Bedroom was drawn clockwise; its walls were renumbered counter-clockwise."))
    XCTAssertTrue(conversion.notes.contains("Closet was drawn clockwise; its walls were renumbered counter-clockwise."))
    let bedroom = document.rooms[0]
    XCTAssertEqual(bedroom.placement, SketchMeasurements.Placement(x: 0, z: 0, angleDeg: -90))
    XCTAssertEqual(bedroom.walls[3].length?.enteredText, "13'1\"")
    XCTAssertEqual(bedroom.walls[3].length?.valueMm, 3988)
    XCTAssertEqual(bedroom.walls[2].length?.enteredText, "9'10\"")
    // The window on the drawn top wall (0.35 to 0.58 along it, left to right) is on document
    // wall 4, which runs right to left: 0.42 to 0.65 from its start.
    let window = try XCTUnwrap(bedroom.openings.first { $0.kind == .window })
    XCTAssertEqual(window.wallId, "wall-4")
    XCTAssertEqual(window.fromCorner, .start)
    XCTAssertEqual(window.fromCornerDistance?.valueMm ?? 0, 0.42 * 3988, accuracy: 0.1)
    XCTAssertEqual(window.width?.valueMm ?? 0, 0.23 * 3988, accuracy: 0.1)
    XCTAssertEqual(window.width?.measured, false)
    XCTAssertNil(window.height)
    XCTAssertNil(window.sill)

    // The closet's corner 0 is where it is drawn, relative to the bedroom's.
    let closet = document.rooms[1]
    let placement = try XCTUnwrap(closet.placement)
    XCTAssertEqual(placement.x, 460 * expectedScale / 1000, accuracy: 1e-6)
    XCTAssertEqual(placement.z, 80 * expectedScale / 1000, accuracy: 1e-6)
    XCTAssertEqual(placement.angleDeg, -90)
    XCTAssertNil(closet.furniture)
    XCTAssertTrue(closet.walls.allSatisfy { $0.length?.measured == false })
  }

  func testBedroomAndClosetSolvesWithTheClosetBesideTheBedroomAndTheFurnitureInside() throws {
    let conversion = try convert()
    let result = try Reading.solve(conversion)
    try validate(result.model, schema: "capture-model.schema.json")
    let bedroom = result.model.rooms[0]
    let closet = result.model.rooms[1]
    let bedroomXs = bedroom.polygon.map(\.x)
    let bedroomZs = bedroom.polygon.map(\.z)
    let closetXs = closet.polygon.map(\.x)
    let closetZs = closet.polygon.map(\.z)
    XCTAssertEqual(bedroomXs.min() ?? 1, 0, accuracy: 1e-6)
    XCTAssertEqual(bedroomXs.max() ?? 0, 3.988, accuracy: 1e-3)
    XCTAssertEqual(bedroomZs.min() ?? 1, 0, accuracy: 1e-6)
    XCTAssertEqual(bedroomZs.max() ?? 0, 2.997, accuracy: 1e-3)
    // The closet shares the bedroom's right-hand wall line (within the drawing's 0.1 %).
    XCTAssertEqual(closetXs.min() ?? 0, bedroomXs.max() ?? 1, accuracy: 0.01)
    XCTAssertGreaterThan(closetZs.min() ?? 0, bedroomZs.min() ?? 1)
    XCTAssertLessThan(closetZs.max() ?? 9, bedroomZs.max() ?? 0)
    XCTAssertEqual((closetXs.max() ?? 0) - (closetXs.min() ?? 0), 0.781, accuracy: 0.002)

    let scale = conversion.millimetresPerUnit
    let bed = try XCTUnwrap(result.model.objects.first { $0.category == .bed })
    XCTAssertEqual(bed.roomId, "room-1")
    XCTAssertTrue(contains(bedroom, x: bed.box.center.x, z: bed.box.center.z))
    XCTAssertEqual(bed.box.center.x, 150 * scale / 1000, accuracy: 1e-5)
    XCTAssertEqual(bed.box.center.z, 160 * scale / 1000, accuracy: 1e-5)
    XCTAssertEqual(bed.box.sizeM.x, 175 * scale / 1000, accuracy: 1e-5)
    XCTAssertEqual(bed.box.sizeM.z, 230 * scale / 1000, accuracy: 1e-5)
    XCTAssertEqual(bed.box.sizeM.y, 0.55, accuracy: 1e-9)
    XCTAssertEqual(bed.box.center.y, 0.275, accuracy: 1e-9)
    let storage = try XCTUnwrap(result.model.objects.first { $0.category == .storage })
    XCTAssertTrue(contains(bedroom, x: storage.box.center.x, z: storage.box.center.z))
    // Every corner of the storage box is inside the bedroom too.
    for dx in [-0.5, 0.5] {
      for dz in [-0.5, 0.5] {
        let x: Double = storage.box.center.x + dx * storage.box.sizeM.x
        let z: Double = storage.box.center.z + dz * storage.box.sizeM.z
        XCTAssertTrue(contains(bedroom, x: x, z: z), "storage corner \(x), \(z)")
      }
    }
    XCTAssertEqual(result.summary.ceilingHeightSource, .measured)
    // The closet's walls and the openings' widths come from the drawing: Limited.
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertEqual(result.summary.wallsMeasured, 2)
  }

  func testNotAPlanThrowsWithTheProblem() throws {
    let reading = try Reading.example("not-a-plan")
    XCTAssertThrowsError(try Reading.convert(reading)) { error in
      XCTAssertEqual(
        error as? SketchReadingError,
        .notAFloorPlan("The photo shows a kitchen, not a drawing of a floor plan."))
    }
  }
}
