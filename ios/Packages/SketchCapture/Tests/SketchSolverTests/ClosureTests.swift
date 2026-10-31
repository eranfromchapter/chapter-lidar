import CaptureContract
import SketchSolver
import XCTest

/// AC2: an L-shaped room with four of six walls closes from the other two; with every wall
/// measured a residual is distributed by length (compass rule) and graded against
/// max(1 %, 25.4 mm) and 3 % of the axis extent.
final class ClosureTests: XCTestCase {
  private let expectedCorners: [(Double, Double, Double)] = [
    (0, 0, 0), (4, 0, 0), (4, 0, -1.5), (2.5, 0, -1.5), (2.5, 0, -3), (0, 0, -3),
  ]

  func testLShapeWithFourWallsClosesFromTheOtherTwo() throws {
    // Walls 3 (x axis) and 6 (z axis) are left out: each is the only unknown on its axis.
    let result = try SketchSolver.solve(
      Sketch.lShape(wall3: nil, wall6: nil), context: Sketch.context)
    let room = try XCTUnwrap(result.model.rooms.first)
    XCTAssertEqual(room.polygon.count, 6)
    for (index, expected) in expectedCorners.enumerated() {
      assertVec(room.polygon[index], expected.0, expected.1, expected.2, "corner \(index)")
    }
    XCTAssertLessThan(signedArea(room.polygon), 0, "counter-clockwise seen from +Y")
    XCTAssertEqual(try wall("wall-3", in: result.model).confidence, .medium)
    XCTAssertEqual(try wall("wall-6", in: result.model).confidence, .medium)
    for id in ["wall-1", "wall-2", "wall-4", "wall-5"] {
      XCTAssertEqual(try wall(id, in: result.model).confidence, .high, id)
    }
    XCTAssertEqual(result.summary.measurements, .complete)
    XCTAssertEqual(result.summary.wallsMeasured, 4)
    XCTAssertEqual(result.summary.wallsEstimated, 0)
    XCTAssertNil(result.summary.closureResidualMm, "no axis had every wall measured")
    XCTAssertEqual(result.closureNotes.count, 0)
  }

  func testAllSixWallsMeasuredAndClosingExactly() throws {
    let result = try SketchSolver.solve(Sketch.lShape(), context: Sketch.context)
    let room = try XCTUnwrap(result.model.rooms.first)
    for (index, expected) in expectedCorners.enumerated() {
      assertVec(room.polygon[index], expected.0, expected.1, expected.2, "corner \(index)")
    }
    XCTAssertEqual(result.summary.closureResidualMm ?? -1, 0, accuracy: 1e-9)
    XCTAssertEqual(result.closureNotes.count, 2, "one per axis")
    XCTAssertTrue(result.closureNotes.allSatisfy { $0.grade == .pass })
    XCTAssertEqual(result.summary.measurements, .complete)
  }

  func testTwoPercentResidualIsDistributedByLengthAndGradedLimitation() throws {
    // Wall 5 is 80 mm long on a 4 m axis (2 %): over max(1 %, 25.4 mm), within 3 %.
    let result = try SketchSolver.solve(Sketch.lShape(wall5: 2580), context: Sketch.context)
    let room = try XCTUnwrap(result.model.rooms.first)
    let edges = edgeLengths(room)
    let entered: [Double] = [4000, 1500, 1500, 1500, 2580, 3000]
    // Compass rule: each wall on the x axis moves by residual x its share of the axis total.
    let xTotal = 4000.0 + 1500 + 2580
    let share = 80 / xTotal
    XCTAssertEqual(edges[0] * 1000, entered[0] * (1 + share), accuracy: 0.001, "wall-1 grows")
    XCTAssertEqual(edges[2] * 1000, entered[2] * (1 - share), accuracy: 0.001, "wall-3 shrinks")
    XCTAssertEqual(edges[4] * 1000, entered[4] * (1 - share), accuracy: 0.001, "wall-5 shrinks")
    for index in [1, 3, 5] {
      XCTAssertEqual(edges[index] * 1000, entered[index], accuracy: 0.001, "z walls untouched")
    }
    // Each x wall moved in proportion to its length.
    // (The polygon is rounded to a micrometre, so the shares agree to about 1e-6.)
    let moves = [0, 2, 4].map { abs(edges[$0] * 1000 - entered[$0]) / entered[$0] }
    XCTAssertEqual(moves[0], moves[1], accuracy: 2e-6)
    XCTAssertEqual(moves[1], moves[2], accuracy: 2e-6)
    // The polygon closes: the walk returns to the origin.
    XCTAssertEqual(edges[0], edges[2] + edges[4], accuracy: 1e-9)
    XCTAssertLessThan(signedArea(room.polygon), 0)

    let x = try XCTUnwrap(result.closureNotes.first { $0.axis == .x })
    XCTAssertEqual(x.residual, -80, accuracy: 1e-9)
    XCTAssertEqual(x.grade, .limitation)
    XCTAssertEqual(result.summary.closureResidualMm ?? 0, 80, accuracy: 1e-9)
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertEqual(result.summary.wallsMeasured, 6)
    XCTAssertEqual(result.summary.wallsEstimated, 0, "measured walls stay high")
    XCTAssertTrue(result.model.walls.allSatisfy { $0.confidence == .high })
  }

  func testFivePercentResidualIsRefusedAndTheCaptureIsLimited() throws {
    let result = try SketchSolver.solve(Sketch.lShape(wall5: 2700), context: Sketch.context)
    let x = try XCTUnwrap(result.closureNotes.first { $0.axis == .x })
    XCTAssertEqual(x.residual, -200, accuracy: 1e-9)
    XCTAssertEqual(x.grade, .refused)
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertEqual(result.summary.closureResidualMm ?? 0, 200, accuracy: 1e-9)
    // Still solved and closed.
    let room = try XCTUnwrap(result.model.rooms.first)
    let edges = edgeLengths(room)
    XCTAssertEqual(edges[0], edges[2] + edges[4], accuracy: 1e-9)
  }

  func testHalfPercentResidualPassesAndTheCaptureIsComplete() throws {
    let result = try SketchSolver.solve(Sketch.lShape(wall5: 2520), context: Sketch.context)
    let x = try XCTUnwrap(result.closureNotes.first { $0.axis == .x })
    XCTAssertEqual(x.residual, -20, accuracy: 1e-9)
    XCTAssertEqual(x.grade, .pass)
    XCTAssertEqual(result.summary.measurements, .complete)
    XCTAssertEqual(result.summary.closureResidualMm ?? 0, 20, accuracy: 1e-9)
    let room = try XCTUnwrap(result.model.rooms.first)
    let edges = edgeLengths(room)
    XCTAssertEqual(edges[0], edges[2] + edges[4], accuracy: 1e-9)
    XCTAssertEqual(edges[0] * 1000, 4000 + 20 * 4000 / 8020, accuracy: 0.001)
  }

  func testSmallRoomUsesTheOneInchFloorOfTheTolerance() throws {
    // 1 % of 1.2 m is 12 mm, below the 25.4 mm floor: a 20 mm residual still passes.
    let room = SketchMeasurements.Room(
      id: "room-1", label: "Cupboard",
      walls: [
        Sketch.wall("wall-1", 1200), Sketch.wall("wall-2", 800), Sketch.wall("wall-3", 1220),
        Sketch.wall("wall-4", 800),
      ])
    let result = try SketchSolver.solve(Sketch.measurements(rooms: [room]), context: Sketch.context)
    let x = try XCTUnwrap(result.closureNotes.first { $0.axis == .x })
    XCTAssertEqual(x.grade, .pass)
    XCTAssertEqual(result.summary.measurements, .complete)
  }

  func testEnteredValuesAreNotChangedByTheSolver() throws {
    let measurements = Sketch.lShape(wall5: 2580)
    _ = try SketchSolver.solve(measurements, context: Sketch.context)
    XCTAssertEqual(measurements.rooms[0].walls[4].length?.valueMm, 2580)
  }
}
