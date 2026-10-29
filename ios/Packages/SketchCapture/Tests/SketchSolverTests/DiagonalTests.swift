import CaptureContract
import SketchSolver
import XCTest

/// Rooms with unsquare corners: the corner coordinates are fitted by least squares to the
/// measured sides and the diagonals across the unsquare corners (spec F14 1.3 and 1.4).
final class DiagonalTests: XCTestCase {
  private func room(
    _ walls: [SketchMeasurements.Wall], diagonals: [SketchMeasurements.Diagonal]
  ) -> SketchMeasurements {
    Sketch.measurements(rooms: [
      SketchMeasurements.Room(id: "room-1", label: "Hall", walls: walls, diagonals: diagonals)
    ])
  }

  func testTrapezoidSolvesToTheMeasuredDiagonalWithinTwoMillimetres() throws {
    // Corners (0,0) (4000,0) (4000,3000) (−500,3000): wall 3 runs 4.5 m back past the origin,
    // so corner 3 is not square and the last wall slopes home. The diagonal from corner 0 to
    // corner 2 (5 m) is the one across corner 3.
    let result = try SketchSolver.solve(
      room(
        [
          Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000),
          Sketch.wall("wall-3", 4500, turn: .unsquare), Sketch.wall("wall-4"),
        ],
        diagonals: [SketchMeasurements.Diagonal(from: 0, to: 2, length: Sketch.mm(5000))]),
      context: Sketch.context)
    let room = try XCTUnwrap(result.model.rooms.first)
    assertVec(room.polygon[0], 0, 0, 0, accuracy: 0.002)
    assertVec(room.polygon[1], 4, 0, 0, accuracy: 0.002)
    assertVec(room.polygon[2], 4, 0, -3, accuracy: 0.002)
    assertVec(room.polygon[3], -0.5, 0, -3, accuracy: 0.002)
    let diagonal = ((room.polygon[2].x - room.polygon[0].x) * (room.polygon[2].x - room.polygon[0].x)
      + (room.polygon[2].z - room.polygon[0].z) * (room.polygon[2].z - room.polygon[0].z)).squareRoot()
    XCTAssertEqual(diagonal, 5, accuracy: 0.002)
    XCTAssertEqual(edgeLengths(room)[3], (500.0 * 500 + 3000 * 3000).squareRoot() / 1000, accuracy: 0.002)
    XCTAssertLessThan(signedArea(room.polygon), 0)
    XCTAssertTrue(
      result.notes.map(\.kind).allSatisfy {
        if case .cornerAssumedSquare = $0 { return false }
        return true
      }, "the corner had its diagonal")
    XCTAssertEqual(try wall("wall-4", in: result.model).confidence, .medium, "derived on its axis")
    XCTAssertEqual(result.summary.measurements, .complete)

    // The sloping wall's centreline still meets its neighbours at the mitred corners.
    let wall4 = try wall("wall-4", in: result.model)
    let wall1 = try wall("wall-1", in: result.model)
    assertVec(wall4.end, wall1.start.x, 0, wall1.start.z, accuracy: 1e-6)
  }

  func testParallelogramFromBothDiagonals() throws {
    // Four unsquare corners, every side and both diagonals measured: a 60° parallelogram with
    // corners (0,0) (4000,0) (5500,2598) (1500,2598). The fit starts from the 4 x 3 rectangle.
    let tall = 3000 * sin(Double.pi / 3)
    let long = ((5500.0 * 5500) + tall * tall).squareRoot()
    let short = ((2500.0 * 2500) + tall * tall).squareRoot()
    let result = try SketchSolver.solve(
      room(
        [
          Sketch.wall("wall-1", 4000, turn: .unsquare), Sketch.wall("wall-2", 3000, turn: .unsquare),
          Sketch.wall("wall-3", 4000, turn: .unsquare), Sketch.wall("wall-4", 3000, turn: .unsquare),
        ],
        diagonals: [
          SketchMeasurements.Diagonal(from: 0, to: 2, length: Sketch.mm(long)),
          SketchMeasurements.Diagonal(from: 1, to: 3, length: Sketch.mm(short)),
        ]),
      context: Sketch.context)
    let room = try XCTUnwrap(result.model.rooms.first)
    assertVec(room.polygon[1], 4, 0, 0, accuracy: 0.002)
    assertVec(room.polygon[2], 5.5, 0, -tall / 1000, accuracy: 0.002)
    assertVec(room.polygon[3], 1.5, 0, -tall / 1000, accuracy: 0.002)
    XCTAssertTrue(result.model.walls.allSatisfy { $0.confidence == .high })
    let fit = try XCTUnwrap(result.closureNotes.first)
    XCTAssertEqual(fit.grade, .pass)
    XCTAssertEqual(abs(fit.residual), 0, accuracy: 0.002)
    XCTAssertEqual(result.summary.measurements, .complete)
    XCTAssertEqual(result.summary.closureResidualMm ?? 1, 0, accuracy: 0.002)
  }

  func testDiagonalThatDisagreesWithTheSidesIsGradedWithTheClosureTolerance() throws {
    // A 4 x 3 rectangle whose diagonal across the "unsquare" corner 3 is entered 100 mm long:
    // the sides and the diagonal cannot all hold; the disagreement is over 1 % of 4 m and
    // under 3 %, so the room is a limitation.
    let result = try SketchSolver.solve(
      room(
        [
          Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000),
          Sketch.wall("wall-3", 4000, turn: .unsquare), Sketch.wall("wall-4", 3000),
        ],
        diagonals: [SketchMeasurements.Diagonal(from: 0, to: 2, length: Sketch.mm(5100))]),
      context: Sketch.context)
    let fit = try XCTUnwrap(result.closureNotes.first)
    XCTAssertEqual(fit.grade, .limitation)
    XCTAssertGreaterThan(abs(fit.residual), 40)
    XCTAssertLessThan(abs(fit.residual), 120)
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertEqual(result.summary.closureResidualMm ?? 0, abs(fit.residual), accuracy: 0.001)
  }

  func testSquarenessCheckDiagonalIsReportedOnlyWhenItDisagrees() throws {
    // Every corner square with a check diagonal (the contract example's use): a diagonal that
    // agrees leaves nothing; one 200 mm off is noted and makes the capture limited, but the
    // shape is not changed.
    let agreeing = try SketchSolver.solve(
      room(
        [Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3", 4000), Sketch.wall("wall-4", 3000)],
        diagonals: [SketchMeasurements.Diagonal(from: 0, to: 2, length: Sketch.mm(5010))]),
      context: Sketch.context)
    XCTAssertEqual(agreeing.closureNotes.filter { $0.grade != .pass }.count, 0)
    XCTAssertEqual(agreeing.summary.measurements, .complete)

    let disagreeing = try SketchSolver.solve(
      room(
        [Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3", 4000), Sketch.wall("wall-4", 3000)],
        diagonals: [SketchMeasurements.Diagonal(from: 0, to: 2, length: Sketch.mm(5200))]),
      context: Sketch.context)
    let note = try XCTUnwrap(disagreeing.closureNotes.first { $0.grade != .pass })
    XCTAssertEqual(note.grade, .refused, "200 mm is over 3 % of 4 m")
    XCTAssertEqual(disagreeing.summary.measurements, .limited)
    assertVec(disagreeing.model.rooms[0].polygon[2], 4, 0, -3)
    XCTAssertEqual(disagreeing.summary.closureResidualMm ?? -1, 0, accuracy: 1e-9, "the check is not a closure residual")
  }
}
