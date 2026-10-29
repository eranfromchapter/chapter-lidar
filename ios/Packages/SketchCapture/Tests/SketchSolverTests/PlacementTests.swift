import CaptureContract
import Foundation
import SketchSolver
import XCTest

/// Rooms with a `placement` (measured where they stand, an AR walkthrough, spec F15) are kept
/// there: corner 0 at (x, z), wall 0 leaving at angleDeg counter-clockwise from +x seen from +Y.
final class PlacementTests: XCTestCase {
  private func rectangle(
    _ id: String, _ first: Int, width: Double, depth: Double,
    placement: SketchMeasurements.Placement?, sharedWith: SketchMeasurements.SharedWall? = nil
  ) -> SketchMeasurements.Room {
    SketchMeasurements.Room(
      id: id, label: id,
      walls: [
        Sketch.wall("wall-\(first)", width), Sketch.wall("wall-\(first + 1)", depth),
        Sketch.wall("wall-\(first + 2)", width),
        Sketch.wall("wall-\(first + 3)", depth, sharedWith: sharedWith),
      ],
      placement: placement)
  }

  func testPlacementPutsCornerZeroAndWallZeroWhereTheyWereMeasured() throws {
    let angle = 30.0 * Double.pi / 180
    let result = try SketchSolver.solve(
      Sketch.measurements(rooms: [
        rectangle(
          "room-1", 1, width: 4000, depth: 3000,
          placement: SketchMeasurements.Placement(x: 2, z: -1, angleDeg: 30))
      ]), context: Sketch.context)
    let polygon = try XCTUnwrap(result.model.rooms.first).polygon
    // Plan y is model −z: 30° counter-clockwise seen from +Y heads towards −z.
    let along = (x: cos(angle), z: -sin(angle))
    let across = (x: -sin(angle), z: -cos(angle))
    assertVec(polygon[0], 2, 0, -1, accuracy: 1e-5)
    assertVec(polygon[1], 2 + 4 * along.x, 0, -1 + 4 * along.z, accuracy: 1e-5)
    assertVec(
      polygon[2], 2 + 4 * along.x + 3 * across.x, 0, -1 + 4 * along.z + 3 * across.z,
      accuracy: 1e-5)
    assertVec(polygon[3], 2 + 3 * across.x, 0, -1 + 3 * across.z, accuracy: 1e-5)
    XCTAssertLessThan(signedArea(polygon), 0, "still counter-clockwise from +Y")
    XCTAssertEqual(result.summary.measurements, .complete)
  }

  func testEveryRoomPlacedReproducesTheMeasuredLayout() throws {
    // Two rooms side by side with a 120 mm partition between their inside faces; the second
    // also names the shared wall, which the placement overrides.
    let result = try SketchSolver.solve(
      Sketch.measurements(rooms: [
        rectangle(
          "room-1", 1, width: 4000, depth: 3000,
          placement: SketchMeasurements.Placement(x: 0, z: 0, angleDeg: 0)),
        rectangle(
          "room-2", 5, width: 2000, depth: 3000,
          placement: SketchMeasurements.Placement(x: 4.12, z: 0, angleDeg: 0),
          sharedWith: SketchMeasurements.SharedWall(roomId: "room-1", wallId: "wall-2")),
      ]), context: Sketch.context)
    let first = result.model.rooms[0].polygon
    let second = result.model.rooms[1].polygon
    assertVec(first[0], 0, 0, 0, accuracy: 1e-6)
    assertVec(first[2], 4, 0, -3, accuracy: 1e-6)
    assertVec(second[0], 4.12, 0, 0, accuracy: 1e-6)
    assertVec(second[1], 6.12, 0, 0, accuracy: 1e-6)
    assertVec(second[2], 6.12, 0, -3, accuracy: 1e-6)
    assertVec(second[3], 4.12, 0, -3, accuracy: 1e-6)
  }

  func testPlacementTurnedHalfWayRound() throws {
    let result = try SketchSolver.solve(
      Sketch.measurements(rooms: [
        rectangle(
          "room-1", 1, width: 4000, depth: 3000,
          placement: SketchMeasurements.Placement(x: 1, z: 2, angleDeg: -90))
      ]), context: Sketch.context)
    let polygon = result.model.rooms[0].polygon
    // −90°: wall 0 heads along +z; the room lies to its left, towards +x.
    assertVec(polygon[0], 1, 0, 2, accuracy: 1e-5)
    assertVec(polygon[1], 1, 0, 6, accuracy: 1e-5)
    assertVec(polygon[2], 4, 0, 6, accuracy: 1e-5)
    assertVec(polygon[3], 4, 0, 2, accuracy: 1e-5)
  }

  func testRoomsWithoutPlacementStillFollowTheirSharedWall() throws {
    // Room 1 is placed away from the origin; room 2 has no placement and is placed by its
    // shared wall against room 1 where room 1 now stands.
    let placed = try SketchSolver.solve(
      Sketch.measurements(rooms: [
        rectangle(
          "room-1", 1, width: 4000, depth: 3000,
          placement: SketchMeasurements.Placement(x: 10, z: 5, angleDeg: 0)),
        rectangle(
          "room-2", 5, width: 2000, depth: 3000, placement: nil,
          sharedWith: SketchMeasurements.SharedWall(roomId: "room-1", wallId: "wall-2")),
      ]), context: Sketch.context)
    let unplaced = try SketchSolver.solve(
      Sketch.measurements(rooms: [
        rectangle("room-1", 1, width: 4000, depth: 3000, placement: nil),
        rectangle(
          "room-2", 5, width: 2000, depth: 3000, placement: nil,
          sharedWith: SketchMeasurements.SharedWall(roomId: "room-1", wallId: "wall-2")),
      ]), context: Sketch.context)
    for (a, b) in zip(placed.model.rooms[1].polygon, unplaced.model.rooms[1].polygon) {
      assertVec(a, b.x + 10, 0, b.z + 5, accuracy: 1e-5)
    }
  }
}
