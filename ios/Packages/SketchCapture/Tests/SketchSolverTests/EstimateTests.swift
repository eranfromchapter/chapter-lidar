import CaptureContract
import SketchSolver
import XCTest

/// AC3: with fewer measurements than the required set the solver still builds a model, marks
/// what it estimated with low confidence and the capture as limited (spec F14 1.5).
final class EstimateTests: XCTestCase {
  private func rectangle(
    walls: [SketchMeasurements.Wall], openings: [SketchMeasurements.Opening] = [],
    ceiling: Double? = 2700
  ) -> SketchMeasurements {
    Sketch.measurements(
      ceiling: ceiling,
      rooms: [SketchMeasurements.Room(id: "room-1", label: "Kitchen", walls: walls, openings: openings)])
  }

  func testOnlyOneWallMeasuredDerivesItsOppositeAndEstimatesTheOtherAxis() throws {
    let result = try SketchSolver.solve(
      rectangle(walls: [
        Sketch.wall("wall-1", 4000), Sketch.wall("wall-2"), Sketch.wall("wall-3"), Sketch.wall("wall-4"),
      ]), context: Sketch.context)
    let room = try XCTUnwrap(result.model.rooms.first)
    // Wall 3 is the only unknown on the x axis: derived. Walls 2 and 4 are both unknown on the
    // z axis with nothing measured there: the 3 m fallback, low.
    assertVec(room.polygon[1], 4, 0, 0)
    assertVec(room.polygon[2], 4, 0, -3)
    assertVec(room.polygon[3], 0, 0, -3)
    XCTAssertEqual(try wall("wall-1", in: result.model).confidence, .high)
    XCTAssertEqual(try wall("wall-3", in: result.model).confidence, .medium)
    XCTAssertEqual(try wall("wall-2", in: result.model).confidence, .low)
    XCTAssertEqual(try wall("wall-4", in: result.model).confidence, .low)
    let kinds = result.notes.map(\.kind)
    XCTAssertTrue(kinds.contains(.wallDerivedFromClosure(wallId: "wall-3")))
    XCTAssertTrue(kinds.contains(.wallEstimated(wallId: "wall-2")))
    XCTAssertTrue(kinds.contains(.wallEstimated(wallId: "wall-4")))
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertTrue(result.isLimited)
    XCTAssertEqual(result.summary.wallsMeasured, 1)
    XCTAssertEqual(result.summary.wallsEstimated, 2)
    XCTAssertNil(result.summary.closureResidualMm)
  }

  func testAboutWallIsUsedButLowAndLimited() throws {
    let result = try SketchSolver.solve(
      rectangle(walls: [
        Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 2800, measured: false), Sketch.wall("wall-3"),
        Sketch.wall("wall-4"),
      ]), context: Sketch.context)
    let room = try XCTUnwrap(result.model.rooms.first)
    assertVec(room.polygon[2], 4, 0, -2.8)
    XCTAssertEqual(try wall("wall-2", in: result.model).confidence, .low)
    XCTAssertEqual(try wall("wall-4", in: result.model).confidence, .medium, "derived from the about wall")
    XCTAssertTrue(result.notes.map(\.kind).contains(.wallEstimated(wallId: "wall-2")))
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertEqual(result.summary.wallsMeasured, 1)
    XCTAssertEqual(result.summary.wallsEstimated, 1)
  }

  func testUnmeasuredWallTakesTheOppositeMeasuredWallOfARectangle() throws {
    // Walls 2 and 4 both missing on the z axis of an L-shape have no opposite wall: the mean
    // of the measured walls on that axis is used; in a rectangle the opposite wall is.
    let result = try SketchSolver.solve(
      Sketch.lShape(wall2: nil, wall4: nil), context: Sketch.context)
    let room = try XCTUnwrap(result.model.rooms.first)
    // Wall 6 (3000) is the only measured z wall; walls 2 and 4 each start at 3000 and are then
    // scaled together so the axis closes: 1500 each.
    assertVec(room.polygon[2], 4, 0, -1.5)
    assertVec(room.polygon[4], 2.5, 0, -3)
    XCTAssertEqual(try wall("wall-2", in: result.model).confidence, .low)
    XCTAssertEqual(try wall("wall-4", in: result.model).confidence, .low)
    XCTAssertEqual(try wall("wall-6", in: result.model).confidence, .high)
    XCTAssertEqual(result.summary.measurements, .limited)
  }

  func testNoCeilingHeightAssumesTwoPointFourFourMetresAndIsLimited() throws {
    let result = try SketchSolver.solve(
      rectangle(
        walls: [Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"), Sketch.wall("wall-4")],
        ceiling: nil), context: Sketch.context)
    XCTAssertEqual(result.model.rooms[0].heightM, 2.44, accuracy: 1e-9)
    XCTAssertTrue(result.model.walls.allSatisfy { abs($0.heightM - 2.44) < 1e-9 })
    XCTAssertEqual(result.summary.ceilingHeightSource, .assumed)
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertTrue(result.notes.map(\.kind).contains(.ceilingAssumed))
    XCTAssertEqual(result.summary.wallsEstimated, 0, "the ceiling is not a wall estimate")
  }

  func testRoomCeilingOverridesTheFloorCeiling() throws {
    var measurements = rectangle(walls: [
      Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"), Sketch.wall("wall-4"),
    ])
    measurements.rooms[0].ceilingHeight = Sketch.mm(3100)
    let result = try SketchSolver.solve(measurements, context: Sketch.context)
    XCTAssertEqual(result.model.rooms[0].heightM, 3.1, accuracy: 1e-9)
    XCTAssertEqual(result.summary.ceilingHeightSource, .measured)
  }

  func testOpeningWithoutWidthOrDistanceGetsDefaultsAndIsLimited() throws {
    let result = try SketchSolver.solve(
      rectangle(
        walls: [Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"), Sketch.wall("wall-4")],
        openings: [
          SketchMeasurements.Opening(id: "door-1", kind: .door, wallId: "wall-1", fromCorner: .start),
          SketchMeasurements.Opening(id: "window-1", kind: .window, wallId: "wall-2", fromCorner: .start),
          SketchMeasurements.Opening(id: "arch-1", kind: .opening, wallId: "wall-3", fromCorner: .end),
        ]), context: Sketch.context)
    let door = try XCTUnwrap(result.model.doors.first)
    XCTAssertEqual(door.widthM, 0.914, accuracy: 1e-9)
    XCTAssertEqual(door.heightM, 2.032, accuracy: 1e-9)
    XCTAssertEqual(door.bottomM, 0)
    XCTAssertEqual(door.offsetM, 0.05715 + 2.0, accuracy: 0.001, "centred on the 4 m wall")
    XCTAssertEqual(door.confidence, .low)

    let window = try XCTUnwrap(result.model.windows.first)
    XCTAssertEqual(window.widthM, 1.219, accuracy: 1e-9)
    XCTAssertEqual(window.heightM, 1.219, accuracy: 1e-9)
    XCTAssertEqual(window.bottomM, 0.914, accuracy: 1e-9)
    XCTAssertEqual(window.offsetM, 0.05715 + 1.5, accuracy: 0.001, "centred on the 3 m wall")
    XCTAssertEqual(window.confidence, .low)

    let arch = try XCTUnwrap(result.model.openings.first)
    XCTAssertEqual(arch.widthM, 1.219, accuracy: 1e-9)
    XCTAssertEqual(arch.heightM, 2.7, accuracy: 1e-9, "an opening is the full wall height")
    XCTAssertEqual(arch.bottomM, 0)
    XCTAssertEqual(arch.confidence, .low)

    let kinds = result.notes.map(\.kind)
    for id in ["door-1", "window-1", "arch-1"] {
      XCTAssertTrue(kinds.contains(.openingEstimated(openingId: id, field: .width)), id)
      XCTAssertTrue(kinds.contains(.openingEstimated(openingId: id, field: .position)), id)
      XCTAssertTrue(kinds.contains(.openingEstimated(openingId: id, field: .height)), id)
    }
    XCTAssertTrue(kinds.contains(.openingEstimated(openingId: "window-1", field: .sill)))
    XCTAssertFalse(kinds.contains(.openingEstimated(openingId: "door-1", field: .sill)))
    XCTAssertEqual(result.summary.measurements, .limited)
  }

  func testDefaultedHeightsAloneDoNotMakeTheCaptureLimited() throws {
    // A measured width and position with a defaulted door height and window sill/height: low
    // on those fields, but the capture stays complete (1.5, last row).
    let result = try SketchSolver.solve(
      rectangle(
        walls: [Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"), Sketch.wall("wall-4")],
        openings: [
          SketchMeasurements.Opening(
            id: "door-1", kind: .door, wallId: "wall-1", width: Sketch.mm(900), fromCorner: .start,
            fromCornerDistance: Sketch.mm(300)),
          SketchMeasurements.Opening(
            id: "window-1", kind: .window, wallId: "wall-2", width: Sketch.mm(1000), fromCorner: .end,
            fromCornerDistance: Sketch.mm(400)),
        ]), context: Sketch.context)
    XCTAssertEqual(result.summary.measurements, .complete)
    XCTAssertEqual(result.model.doors[0].confidence, .high)
    XCTAssertEqual(result.model.windows[0].confidence, .high)
    XCTAssertEqual(result.model.windows[0].bottomM, 0.914, accuracy: 1e-9)
    XCTAssertEqual(result.model.windows[0].heightM, 1.219, accuracy: 1e-9)
    XCTAssertTrue(result.notes.map(\.kind).contains(.openingEstimated(openingId: "window-1", field: .sill)))
  }

  func testTwoOpeningsWithoutDistancesAreSpacedEvenlyInOrder() throws {
    let result = try SketchSolver.solve(
      rectangle(
        walls: [Sketch.wall("wall-1", 6000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"), Sketch.wall("wall-4")],
        openings: [
          SketchMeasurements.Opening(id: "window-1", kind: .window, wallId: "wall-1", width: Sketch.mm(1000), fromCorner: .start),
          SketchMeasurements.Opening(id: "window-2", kind: .window, wallId: "wall-1", width: Sketch.mm(1000), fromCorner: .start),
        ]), context: Sketch.context)
    XCTAssertEqual(result.model.windows[0].offsetM, 0.05715 + 2.0, accuracy: 0.001)
    XCTAssertEqual(result.model.windows[1].offsetM, 0.05715 + 4.0, accuracy: 0.001)
  }

  func testOpeningIsClampedInsideItsWall() throws {
    // A 0.9 m door said to be 3.8 m from the start of a 4 m wall would overhang the corner.
    let result = try SketchSolver.solve(
      rectangle(
        walls: [Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"), Sketch.wall("wall-4")],
        openings: [
          SketchMeasurements.Opening(
            id: "door-1", kind: .door, wallId: "wall-1", width: Sketch.mm(900), fromCorner: .start,
            fromCornerDistance: Sketch.mm(3800))
        ]), context: Sketch.context)
    let door = result.model.doors[0]
    XCTAssertEqual(door.offsetM, 0.05715 + 4.0 - 0.45, accuracy: 0.001)
  }

  func testUnsquareCornerWithoutADiagonalIsDrawnSquareAndLimited() throws {
    let result = try SketchSolver.solve(
      rectangle(walls: [
        Sketch.wall("wall-1", 4000, turn: .unsquare), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3", 4000),
        Sketch.wall("wall-4", 3000),
      ]), context: Sketch.context)
    let room = try XCTUnwrap(result.model.rooms.first)
    assertVec(room.polygon[1], 4, 0, 0)
    assertVec(room.polygon[2], 4, 0, -3)
    assertVec(room.polygon[3], 0, 0, -3)
    XCTAssertTrue(result.notes.map(\.kind).contains(.cornerAssumedSquare(roomId: "room-1", corner: 1)))
    // Corner 1 is the end of wall 1 and the start of wall 2: both are low.
    XCTAssertEqual(try wall("wall-1", in: result.model).confidence, .low)
    XCTAssertEqual(try wall("wall-2", in: result.model).confidence, .low)
    XCTAssertEqual(try wall("wall-3", in: result.model).confidence, .high)
    XCTAssertEqual(try wall("wall-4", in: result.model).confidence, .high)
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertEqual(result.summary.wallsMeasured, 4)
    XCTAssertEqual(result.summary.wallsEstimated, 2)
  }

  func testClockwiseSketchIsMirroredToCounterClockwise() throws {
    // Every turn to the right: the operator walked the room clockwise. The polygon is still
    // counter-clockwise seen from +Y with wall 1 along +x.
    let result = try SketchSolver.solve(
      rectangle(walls: [
        Sketch.wall("wall-1", 4000, turn: .right), Sketch.wall("wall-2", 3000, turn: .right),
        Sketch.wall("wall-3", 4000, turn: .right), Sketch.wall("wall-4", 3000, turn: .right),
      ]), context: Sketch.context)
    let room = try XCTUnwrap(result.model.rooms.first)
    XCTAssertLessThan(signedArea(room.polygon), 0)
    assertVec(room.polygon[1], 4, 0, 0)
    XCTAssertEqual(abs(signedArea(room.polygon)), 12, accuracy: 1e-6)
  }
}
