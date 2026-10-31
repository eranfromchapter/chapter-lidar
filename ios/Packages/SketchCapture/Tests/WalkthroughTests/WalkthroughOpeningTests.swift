import CaptureContract
import Foundation
import SketchSolver
import Walkthrough
import XCTest

/// Spec F15 AC3: openings from the jamb, sill and head taps.
final class WalkthroughOpeningTests: XCTestCase {
  /// The 4 x 3 m rectangle turned 30°; a point `along` metres from corner `wall` towards the
  /// next corner, with ±3 mm of tap noise.
  private func onWall(_ wall: Int, _ along: Double, noise: inout WalkthroughNoise) -> Walk.Point {
    let truth = Walk.rectangleTruth
    let a = truth[wall]
    let b = truth[(wall + 1) % truth.count]
    let p = Walk.lerp(a, b, along / Walk.distance(a, b))
    return (p.x + noise.offset(0.003), p.y + noise.offset(0.003))
  }

  private func walk(_ openings: (inout WalkthroughNoise) -> [WalkthroughLog.Opening]) -> WalkthroughLog {
    var noise = WalkthroughNoise(seed: 0xD00D)
    let list = openings(&noise)
    return Walk.log(rooms: [
      Walk.cornersRoom(truth: Walk.rectangleTruth, noise: 0.002, seed: 3, openings: list)
    ])
  }

  func testDoorAndWindowFromJambSillAndHeadTaps() throws {
    // Door on wall 2 (corner 1 to 2): jambs at the floor 0.5 m and 1.4 m from corner 1 (the
    // left jamb is the far one), head at 2.03 m. Window on wall 1: jambs on the wall at 1.4 m
    // high, 1.0 m and 2.2 m from corner 0, sill at 0.9 m, head at 2.1 m.
    let log = walk { noise in
      [
        WalkthroughLog.Opening(
          id: "door-1", kind: .door, wallIndex: 1,
          leftJamb: Walk.tap(self.onWall(1, 1.4, noise: &noise), t: 60),
          rightJamb: Walk.tap(self.onWall(1, 0.5, noise: &noise), t: 62),
          head: Walk.tap(self.onWall(1, 0.95, noise: &noise), height: 2.03 + noise.offset(0.003), t: 64)),
        WalkthroughLog.Opening(
          id: "window-1", kind: .window, wallIndex: 0,
          leftJamb: Walk.tap(self.onWall(0, 1.0, noise: &noise), height: 1.4, t: 70),
          rightJamb: Walk.tap(self.onWall(0, 2.2, noise: &noise), height: 1.4, t: 72),
          head: Walk.tap(self.onWall(0, 1.6, noise: &noise), height: 2.1 + noise.offset(0.003), t: 74),
          sill: Walk.tap(self.onWall(0, 1.6, noise: &noise), height: 0.9 + noise.offset(0.003), t: 76)),
      ]
    }
    let room = try Walk.convert(log).measurements.rooms[0]
    let door = try XCTUnwrap(room.openings.first { $0.id == "door-1" })
    XCTAssertEqual(door.kind, .door)
    XCTAssertEqual(door.wallId, "wall-2")
    XCTAssertEqual(door.fromCorner, .start)
    XCTAssertEqual(door.width?.valueMm ?? 0, 900, accuracy: 10)
    XCTAssertEqual(door.fromCornerDistance?.valueMm ?? 0, 500, accuracy: 10)
    XCTAssertEqual(door.height?.valueMm ?? 0, 2030, accuracy: 10)
    XCTAssertNil(door.sill)
    XCTAssertTrue([door.width, door.height, door.fromCornerDistance].allSatisfy { $0?.measured == true })

    let window = try XCTUnwrap(room.openings.first { $0.id == "window-1" })
    XCTAssertEqual(window.wallId, "wall-1")
    XCTAssertEqual(window.width?.valueMm ?? 0, 1200, accuracy: 10)
    XCTAssertEqual(window.fromCornerDistance?.valueMm ?? 0, 1000, accuracy: 10)
    XCTAssertEqual(window.sill?.valueMm ?? 0, 900, accuracy: 10)
    XCTAssertEqual(window.height?.valueMm ?? 0, 1200, accuracy: 10)

    // Through the solver: the model opening keeps the walked sizes.
    let document = try Walk.convert(log).measurements
    try validate(document, schema: "sketch-measurements.schema.json")
    let result = try SketchSolver.solve(document, context: Walk.context)
    let modelDoor = try XCTUnwrap(result.model.doors.first)
    XCTAssertEqual(modelDoor.widthM, 0.9, accuracy: 0.010)
    XCTAssertEqual(modelDoor.heightM, 2.03, accuracy: 0.010)
    XCTAssertEqual(modelDoor.confidence, .high)
    let modelWindow = try XCTUnwrap(result.model.windows.first)
    XCTAssertEqual(modelWindow.bottomM, 0.9, accuracy: 0.010)
    XCTAssertEqual(modelWindow.heightM, 1.2, accuracy: 0.010)
    XCTAssertTrue(
      result.notes.allSatisfy {
        if case .openingEstimated = $0.kind { return false }
        return true
      }, "nothing about the openings was estimated")
  }

  func testDoorWithOnlyJambsLeavesTheHeightToTheSolver() throws {
    let log = walk { noise in
      [
        WalkthroughLog.Opening(
          id: "door-2", kind: .door, wallIndex: 2,
          leftJamb: Walk.tap(self.onWall(2, 0.3, noise: &noise), t: 60),
          rightJamb: Walk.tap(self.onWall(2, 1.1, noise: &noise), t: 62))
      ]
    }
    let document = try Walk.convert(log).measurements
    let door = try XCTUnwrap(document.rooms[0].openings.first)
    XCTAssertNil(door.height)
    XCTAssertEqual(door.width?.valueMm ?? 0, 800, accuracy: 10)
    XCTAssertEqual(door.fromCornerDistance?.valueMm ?? 0, 300, accuracy: 10)
    let result = try SketchSolver.solve(document, context: Walk.context)
    XCTAssertEqual(result.model.doors.first?.heightM ?? 0, SketchDefaults.doorHeightMm / 1000, accuracy: 1e-6)
    XCTAssertTrue(
      result.notes.contains {
        if case .openingEstimated("door-2", .height) = $0.kind { return true }
        return false
      })
  }

  func testWindowWithoutSillLeavesSillAndHeightOut() throws {
    let log = walk { noise in
      [
        WalkthroughLog.Opening(
          id: "window-2", kind: .window, wallIndex: 3,
          leftJamb: Walk.tap(self.onWall(3, 0.6, noise: &noise), height: 1.3, t: 60),
          rightJamb: Walk.tap(self.onWall(3, 1.8, noise: &noise), height: 1.3, t: 62),
          head: Walk.tap(self.onWall(3, 1.2, noise: &noise), height: 2.0, t: 64))
      ]
    }
    let window = try XCTUnwrap(try Walk.convert(log).measurements.rooms[0].openings.first)
    XCTAssertNil(window.sill)
    XCTAssertNil(window.height)
    XCTAssertEqual(window.width?.valueMm ?? 0, 1200, accuracy: 10)
  }

  func testJambOnTheCornerIsClampedOntoTheWall() throws {
    // A passage whose near jamb was tapped a little past the start corner.
    let log = walk { noise in
      [
        WalkthroughLog.Opening(
          id: "opening-1", kind: .opening, wallIndex: 0,
          leftJamb: Walk.tap(self.onWall(0, -0.05, noise: &noise), t: 60),
          rightJamb: Walk.tap(self.onWall(0, 1.0, noise: &noise), t: 62),
          head: Walk.tap(self.onWall(0, 0.5, noise: &noise), height: 2.4, t: 64))
      ]
    }
    let document = try Walk.convert(log).measurements
    let opening = try XCTUnwrap(document.rooms[0].openings.first)
    XCTAssertEqual(opening.fromCornerDistance?.valueMm, 1)
    XCTAssertEqual(opening.width?.valueMm ?? 0, 1050, accuracy: 10)
    XCTAssertEqual(opening.height?.valueMm ?? 0, 2400, accuracy: 5)
    try validate(document, schema: "sketch-measurements.schema.json")
  }
}
