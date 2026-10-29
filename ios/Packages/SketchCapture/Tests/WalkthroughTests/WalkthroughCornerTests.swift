import CaptureContract
import Foundation
import SketchSolver
import Walkthrough
import XCTest

/// Spec F15 AC1 and the corner rules of section 3: corner taps with the loop drift spread by
/// time, square and unsquare corners, the scale check, the winding.
final class WalkthroughCornerTests: XCTestCase {
  private let truthLengths = [4.0, 3.0, 4.0, 3.0]

  /// ±20 mm tap noise (uniform, per coordinate) and a 60 mm loop gap that grew with time.
  private func noisyRectangle(seed: UInt64 = 1, scaleCheck: Bool) -> WalkthroughLog {
    let room = Walk.cornersRoom(
      truth: Walk.rectangleTruth, noise: 0.020, seed: seed, drift: (0.036, -0.048))
    return Walk.log(
      rooms: [room],
      scaleCheck: scaleCheck
        ? WalkthroughLog.ScaleCheck(roomId: "room-1", wallIndex: 0, tape: Walk.tape(4000)) : nil)
  }

  func testWalkedRectangleSolvesToWallsWithin25MillimetresAndSquareCorners() throws {
    let conversion = try Walk.convert(noisyRectangle(scaleCheck: false))
    let document = conversion.measurements
    let room = try XCTUnwrap(document.rooms.first)
    XCTAssertEqual(document.source, SketchMeasurements.Source(kind: .arWalkthrough, path: Walk.sourcePath))
    XCTAssertEqual(room.walls.map(\.id), ["wall-1", "wall-2", "wall-3", "wall-4"])
    XCTAssertTrue(room.walls.allSatisfy { $0.turn == nil }, "every corner left (square)")
    XCTAssertTrue(room.walls.allSatisfy { $0.length?.measured == true })
    XCTAssertTrue(room.diagonals.isEmpty)
    XCTAssertEqual(conversion.summary.loopClosureMm, 60, accuracy: 0.05)
    XCTAssertEqual(conversion.summary.scaleSource, .ar)
    XCTAssertNil(conversion.summary.scaleFactor)
    XCTAssertTrue(conversion.summary.recorded)
    XCTAssertEqual(conversion.notes.first, "Bedroom: the loop closed 60 mm apart; spread over the corners.")

    // The drift is gone: the converted corners are within the tap noise of the truth.
    let corners = try XCTUnwrap(conversion.corners["room-1"])
    for (index, corner) in corners.enumerated() {
      XCTAssertEqual(corner.y, 0)
      assertPoint(corner, Walk.rectangleTruth[index], within: 0.030, "corner \(index)")
    }

    let result = try SketchSolver.solve(document, context: Walk.context)
    let polygon = try XCTUnwrap(result.model.rooms.first).polygon
    for (index, length) in edgeLengths(polygon).enumerated() {
      XCTAssertEqual(length, truthLengths[index], accuracy: 0.025, "wall \(index + 1)")
    }
    for angle in interiorAngles(polygon) {
      XCTAssertEqual(angle, 90, accuracy: 1e-4)
    }
    // Placement honoured: the room is where it was walked, not at the origin.
    assertPoint(polygon[0], Walk.rectangleTruth[0], within: 0.030, "corner 0")
    assertPoint(polygon[2], Walk.rectangleTruth[2], within: 0.060, "corner 2")
    XCTAssertEqual(result.model.rooms[0].heightM, 2.7, accuracy: 0.001)
    XCTAssertEqual(result.summary.ceilingHeightSource, .measured)
  }

  func testEightNoisyWalksAllSolveWithin25Millimetres() throws {
    for seed: UInt64 in 1...8 {
      let conversion = try Walk.convert(noisyRectangle(seed: seed, scaleCheck: false))
      XCTAssertTrue(conversion.measurements.rooms[0].walls.allSatisfy { $0.turn == nil })
      XCTAssertEqual(conversion.summary.loopClosureMm, 60, accuracy: 0.05)
      let result = try SketchSolver.solve(conversion.measurements, context: Walk.context)
      for (index, length) in edgeLengths(result.model.rooms[0].polygon).enumerated() {
        XCTAssertEqual(length, truthLengths[index], accuracy: 0.025, "walk \(seed) wall \(index + 1)")
      }
    }
  }

  func testNoisyWalkWithATapeCheckStaysWithin25Millimetres() throws {
    let conversion = try Walk.convert(noisyRectangle(scaleCheck: true))
    XCTAssertEqual(conversion.summary.scaleSource, .tape)
    let factor = try XCTUnwrap(conversion.summary.scaleFactor)
    XCTAssertEqual(factor, 1, accuracy: 0.02)
    XCTAssertEqual(conversion.measurements.rooms[0].walls[0].length?.valueMm, 4000)
    let result = try SketchSolver.solve(conversion.measurements, context: Walk.context)
    for (index, length) in edgeLengths(result.model.rooms[0].polygon).enumerated() {
      XCTAssertEqual(length, truthLengths[index], accuracy: 0.025, "wall \(index + 1)")
    }
  }

  func testTapeCheckRemovesTheTrackingScaleError() throws {
    // The phone's tracking reads 1.2 % long (48 mm on the 4 m walls) with ±5 mm tap noise and
    // the 60 mm loop gap: without a reference every wall is off by more than 25 mm; a tape of
    // wall 1 brings every other wall within 10 mm.
    func walk(_ check: WalkthroughLog.ScaleCheck?, seed: UInt64 = 1) -> WalkthroughLog {
      Walk.log(
        rooms: [
          Walk.cornersRoom(
            truth: Walk.rectangleTruth, noise: 0.005, seed: seed, drift: (0.036, -0.048),
            scale: 1.012)
        ], scaleCheck: check)
    }
    let unscaled = try SketchSolver.solve(
      Walk.convert(walk(nil)).measurements, context: Walk.context)
    XCTAssertTrue(
      zip(edgeLengths(unscaled.model.rooms[0].polygon), truthLengths).allSatisfy {
        abs($0 - $1) > 0.025
      })

    let conversion = try Walk.convert(
      walk(WalkthroughLog.ScaleCheck(roomId: "room-1", wallIndex: 0, tape: Walk.tape(4000))))
    let factor = try XCTUnwrap(conversion.summary.scaleFactor)
    XCTAssertEqual(factor, 1 / 1.012, accuracy: 0.003)
    XCTAssertEqual(conversion.summary.scaleSource, .tape)
    XCTAssertEqual(
      conversion.notes.last, "Scale checked with a tape on Bedroom wall 1: ×\(factor).")
    let document = conversion.measurements
    XCTAssertEqual(document.rooms[0].walls[0].length?.valueMm, 4000)
    for (index, wall) in document.rooms[0].walls.enumerated() {
      XCTAssertEqual((wall.length?.valueMm ?? 0) / 1000, truthLengths[index], accuracy: 0.010)
    }
    // Ceiling and placement are scaled too.
    XCTAssertEqual((document.ceilingHeight?.valueMm ?? 0) / 1000, 2.7, accuracy: 0.010)
    let placement = try XCTUnwrap(document.rooms[0].placement)
    XCTAssertEqual(placement.x, Walk.rectangleTruth[0].x, accuracy: 0.010)
    XCTAssertEqual(-placement.z, Walk.rectangleTruth[0].y, accuracy: 0.010)

    // Five different (seeded) walks, solved: every wall within 10 mm.
    for seed: UInt64 in 1...5 {
      let taped = try Walk.convert(
        walk(
          WalkthroughLog.ScaleCheck(roomId: "room-1", wallIndex: 0, tape: Walk.tape(4000)),
          seed: seed))
      let result = try SketchSolver.solve(taped.measurements, context: Walk.context)
      for (index, length) in edgeLengths(result.model.rooms[0].polygon).enumerated() {
        XCTAssertEqual(length, truthLengths[index], accuracy: 0.010, "walk \(seed) wall \(index + 1)")
      }
    }
  }

  func testDriftIsSpreadInProportionToTime() throws {
    // Exact taps, a 100 mm gap along +x: corner i moves back by its share of the walk's time.
    var room = Walk.cornersRoom(
      truth: [(0, 0), (4, 0), (4, 3), (0, 3)], noise: 0, seed: 1, drift: (0.1, 0))
    // Uneven times: 10, 12, 30, 31, closing 40.
    let times = [10.0, 12, 30, 31]
    room.corners = room.corners?.enumerated().map { index, tap in
      let f = (times[index] - 10) / 30
      return WalkthroughLog.Tap(
        p: Walk.ar(([0.0, 4, 4, 0][index] + 0.1 * f, [0.0, 0, 3, 3][index])), t: times[index])
    }
    room.closingTap = WalkthroughLog.Tap(p: Walk.ar((0.1, 0)), t: 40)
    let conversion = try Walk.convert(Walk.log(rooms: [room]))
    let corners = try XCTUnwrap(conversion.corners["room-1"])
    for (index, expected) in [(0.0, 0.0), (4, 0), (4, 3), (0, 3)].enumerated() {
      assertPoint(corners[index], expected, within: 1e-6, "corner \(index)")
    }
    XCTAssertEqual(conversion.summary.loopClosureMm, 100, accuracy: 0.05)
  }

  func testRoomWithoutClosingTapHasNoLoopGap() throws {
    let room = Walk.cornersRoom(truth: Walk.rectangleTruth, noise: 0, seed: 1, close: false)
    let conversion = try Walk.convert(Walk.log(rooms: [room]))
    XCTAssertEqual(conversion.summary.loopClosureMm, 0)
    XCTAssertTrue(conversion.notes.isEmpty)
  }

  func testUnsquareCornerGetsItsDiagonalAndKeepsItsAngle() throws {
    // Corners (0,0) (4,0) (4,3) (−0.5,3): corner 3 is 80.5° and corner 0 99.5°, both unsquare.
    let truth: [Walk.Point] = [(0, 0), (4, 0), (4, 3), (-0.5, 3)]
    let conversion = try Walk.convert(
      Walk.log(rooms: [Walk.cornersRoom(truth: truth, noise: 0.002, seed: 7)]))
    let room = conversion.measurements.rooms[0]
    XCTAssertEqual(room.walls.map(\.turn), [nil, nil, .unsquare, .unsquare])
    XCTAssertEqual(room.diagonals.map { [$0.from, $0.to] }, [[0, 2], [1, 3]])
    XCTAssertEqual(room.diagonals[0].length.valueMm, 5000, accuracy: 6)
    XCTAssertEqual(room.diagonals[1].length.valueMm, (4.5 * 4.5 + 9).squareRoot() * 1000, accuracy: 6)
    XCTAssertTrue(room.diagonals.allSatisfy { $0.length.measured })
    XCTAssertEqual(conversion.notes.filter { $0.contains("not square") }.count, 2)

    let result = try SketchSolver.solve(conversion.measurements, context: Walk.context)
    let angles = interiorAngles(result.model.rooms[0].polygon)
    let truthCorner3 = atan2(3, 0.5) * 180 / Double.pi  // 80.54°
    XCTAssertEqual(angles[3], truthCorner3, accuracy: 0.5)
    XCTAssertEqual(angles[0], 180 - truthCorner3, accuracy: 0.5)
    XCTAssertEqual(angles[1], 90, accuracy: 0.5)
    XCTAssertEqual(angles[2], 90, accuracy: 0.5)
    XCTAssertTrue(
      result.notes.allSatisfy {
        if case .cornerAssumedSquare = $0.kind { return false }
        return true
      })
  }

  func testClockwiseWalkIsRewound() throws {
    // Walked clockwise: (0,0) (0,3) (4,3) (4,0). A door on walked wall 1 ((0,0) to (0,3)), the
    // tape on walked wall 2 ((0,3) to (4,3)).
    let door = WalkthroughLog.Opening(
      id: "door-1", kind: .door, wallIndex: 0, leftJamb: Walk.tap((0, 0.5), t: 50),
      rightJamb: Walk.tap((0, 1.4), t: 51), head: Walk.tap((0, 1.0), height: 2.03, t: 52))
    let room = Walk.cornersRoom(
      truth: [(0, 0), (0, 3), (4, 3), (4, 0)], noise: 0, seed: 1, openings: [door])
    let conversion = try Walk.convert(
      Walk.log(
        rooms: [room],
        scaleCheck: WalkthroughLog.ScaleCheck(roomId: "room-1", wallIndex: 1, tape: Walk.tape(4000)))
    )
    let corners = try XCTUnwrap(conversion.corners["room-1"])
    for (index, expected) in [(0.0, 0.0), (4, 0), (4, 3), (0, 3)].enumerated() {
      assertPoint(corners[index], expected, within: 1e-6, "corner \(index)")
    }
    let document = conversion.measurements.rooms[0]
    XCTAssertTrue(document.walls.allSatisfy { $0.turn == nil })
    XCTAssertEqual(conversion.summary.scaleFactor, 1)
    // Walked wall 1 is the document's wall 4, from (0,3) back to (0,0).
    let opening = try XCTUnwrap(document.openings.first)
    XCTAssertEqual(opening.wallId, "wall-4")
    XCTAssertEqual(opening.fromCornerDistance?.valueMm ?? 0, 1600, accuracy: 0.1)
    XCTAssertEqual(opening.width?.valueMm ?? 0, 900, accuracy: 0.1)
    let placement = try XCTUnwrap(document.placement)
    XCTAssertEqual(placement.angleDeg, 0, accuracy: 1e-9)

    let result = try SketchSolver.solve(conversion.measurements, context: Walk.context)
    XCTAssertLessThan(signedArea(result.model.rooms[0].polygon), 0)
  }

  func testImperialTextAndValues() throws {
    let conversion = try Walk.convert(
      Walk.log(rooms: [
        Walk.cornersRoom(truth: [(0, 0), (4.001, 0), (4.001, 3), (0, 3)], noise: 0, seed: 1)
      ]), units: .imperial)
    XCTAssertEqual(conversion.measurements.displayUnits, .imperial)
    let wall = try XCTUnwrap(conversion.measurements.rooms[0].walls[0].length)
    XCTAssertEqual(wall.valueMm, 4001, accuracy: 0.05)
    XCTAssertEqual(wall.enteredUnit, .ftIn)
    XCTAssertEqual(wall.enteredText, "13' 1.5\"")
    let metric = try Walk.convert(
      Walk.log(rooms: [
        Walk.cornersRoom(truth: [(0, 0), (4.012, 0), (4.012, 3), (0, 3)], noise: 0, seed: 1)
      ]))
    XCTAssertEqual(metric.measurements.rooms[0].walls[0].length?.enteredText, "4012")
    XCTAssertEqual(metric.measurements.rooms[0].walls[0].length?.enteredUnit, .mm)
  }

  func testCeilingCarriesToTheNextRoomAndDifferentCeilingsAreKept() throws {
    let a = Walk.cornersRoom(id: "room-1", truth: [(0, 0), (3, 0), (3, 3), (0, 3)], noise: 0, seed: 1)
    let b = Walk.cornersRoom(
      id: "room-2", label: "Hall", truth: [(4, 0), (6, 0), (6, 3), (4, 3)], noise: 0, seed: 2,
      ceilingHeight: nil)
    let c = Walk.cornersRoom(
      id: "room-3", label: "Loft", truth: [(7, 0), (9, 0), (9, 3), (7, 3)], noise: 0, seed: 3,
      ceilingHeight: 2.4)
    let document = try Walk.convert(Walk.log(rooms: [a, b, c])).measurements
    XCTAssertEqual(document.ceilingHeight?.valueMm ?? 0, 2700, accuracy: 0.05)
    XCTAssertNil(document.rooms[0].ceilingHeight)
    XCTAssertNil(document.rooms[1].ceilingHeight, "the previous room's")
    XCTAssertEqual(document.rooms[2].ceilingHeight?.valueMm ?? 0, 2400, accuracy: 0.05)
    XCTAssertEqual(document.rooms.flatMap(\.walls).map(\.id), (1...12).map { "wall-\($0)" })

    let none = try Walk.convert(
      Walk.log(rooms: [
        Walk.cornersRoom(truth: [(0, 0), (3, 0), (3, 3), (0, 3)], noise: 0, seed: 1, ceilingHeight: nil)
      ])
    ).measurements
    XCTAssertNil(none.ceilingHeight)
    let solved = try SketchSolver.solve(none, context: Walk.context)
    XCTAssertEqual(solved.summary.ceilingHeightSource, .assumed)
  }

  func testTrackingLimitedSecondsFromFrames() throws {
    let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    let frames = [
      WalkthroughLog.Frame(t: 0, transform: identity, tracking: .normal),
      WalkthroughLog.Frame(t: 0.5, transform: identity, tracking: .limited),
      WalkthroughLog.Frame(t: 1.0, transform: identity, tracking: .notAvailable),
      WalkthroughLog.Frame(t: 1.75, transform: identity, tracking: .normal),
      WalkthroughLog.Frame(t: 2.0, transform: identity, tracking: .limited),
    ]
    let room = Walk.cornersRoom(truth: Walk.rectangleTruth, noise: 0, seed: 1)
    let conversion = try Walk.convert(Walk.log(rooms: [room], frames: frames))
    XCTAssertEqual(conversion.summary.trackingLimitedSeconds, 1.25, accuracy: 1e-9)
    let none = try Walk.convert(Walk.log(rooms: [room]))
    XCTAssertEqual(none.summary.trackingLimitedSeconds, 0)
  }

  func testErrors() throws {
    XCTAssertThrowsError(try Walk.convert(Walk.log(rooms: []))) {
      XCTAssertEqual($0 as? WalkthroughError, .noRooms)
    }
    var short = Walk.cornersRoom(truth: Walk.rectangleTruth, noise: 0, seed: 1)
    short.corners = Array(short.corners!.prefix(2))
    XCTAssertThrowsError(try Walk.convert(Walk.log(rooms: [short]))) {
      XCTAssertEqual($0 as? WalkthroughError, .tooFewCorners(roomId: "room-1"))
    }
    let window = WalkthroughLog.Opening(
      id: "window-9", kind: .window, wallIndex: 4, leftJamb: Walk.tap((1, 0), height: 1.4, t: 60),
      rightJamb: Walk.tap((2, 0), height: 1.4, t: 61))
    let room = Walk.cornersRoom(
      truth: [(0, 0), (4, 0), (4, 3), (0, 3)], noise: 0, seed: 1, openings: [window])
    XCTAssertThrowsError(try Walk.convert(Walk.log(rooms: [room]))) {
      XCTAssertEqual($0 as? WalkthroughError, .unknownWall(openingId: "window-9", wallIndex: 4))
    }
    let plain = Walk.cornersRoom(truth: Walk.rectangleTruth, noise: 0, seed: 1)
    for check in [
      WalkthroughLog.ScaleCheck(roomId: "room-1", wallIndex: 4, tape: Walk.tape(4000)),
      WalkthroughLog.ScaleCheck(roomId: "room-7", wallIndex: 0, tape: Walk.tape(4000)),
    ] {
      XCTAssertThrowsError(try Walk.convert(Walk.log(rooms: [plain], scaleCheck: check))) {
        XCTAssertEqual(
          $0 as? WalkthroughError,
          .unknownScaleWall(roomId: check.roomId, wallIndex: check.wallIndex))
      }
    }
  }

  func testLiveCornersOfACornersRoom() {
    let room = Walk.cornersRoom(truth: Walk.rectangleTruth, noise: 0, seed: 1, close: false)
    let live = WalkthroughConverter.liveCorners(room, floorY: Walk.floorY)
    XCTAssertEqual(live?.count, 4)
    XCTAssertEqual(live?.first?.y, Walk.floorY)
    var one = room
    one.corners = Array(room.corners!.prefix(1))
    XCTAssertNil(WalkthroughConverter.liveCorners(one, floorY: Walk.floorY))
    var two = room
    two.corners = Array(room.corners!.prefix(2))
    XCTAssertEqual(WalkthroughConverter.liveCorners(two, floorY: Walk.floorY)?.count, 2)
  }
}
