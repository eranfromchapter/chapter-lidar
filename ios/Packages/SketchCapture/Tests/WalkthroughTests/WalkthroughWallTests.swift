import CaptureContract
import Foundation
import SketchSolver
import Walkthrough
import XCTest

/// Spec F15 AC2: "Tap each wall" rooms, corners from the intersections of the wall lines.
final class WalkthroughWallTests: XCTestCase {
  /// 6 x 4 m with the 3 x 2 m corner between walls 3 and 4 cut out, turned −20° and moved.
  private let lTruth = Walk.transform(
    [(0, 0), (6, 0), (6, 2), (3, 2), (3, 4), (0, 4)], degrees: -20, dx: -2.5, dy: 1.1)

  /// Two taps per wall at 15 % and 85 % of it (four on wall 0 when asked), ±5 mm noise.
  private func lRoom(seed: UInt64, extraOnFirstWall: Bool = false) -> WalkthroughLog.Room {
    var noise = WalkthroughNoise(seed: seed)
    var t = 20.0
    var walls: [[WalkthroughLog.Tap]] = []
    for index in lTruth.indices {
      let a = lTruth[index]
      let b = lTruth[(index + 1) % lTruth.count]
      let fractions = extraOnFirstWall && index == 0 ? [0.1, 0.35, 0.6, 0.9] : [0.15, 0.85]
      walls.append(
        fractions.map { f in
          t += 2
          let p = Walk.lerp(a, b, f)
          return Walk.tap((p.x + noise.offset(0.005), p.y + noise.offset(0.005)), t: t)
        })
    }
    return WalkthroughLog.Room(
      id: "room-1", label: "Living room", type: .livingRoom, method: .walls, walls: walls,
      ceiling: [Walk.tap(lTruth[0], height: 2.6, t: t + 5)])
  }

  func testLShapedRoomFromTwoTapsPerWallGivesSixCornersWithin10Millimetres() throws {
    // Eight different (seeded) walks: every corner of every walk within 10 mm.
    for seed: UInt64 in 1...8 {
      let conversion = try Walk.convert(Walk.log(rooms: [lRoom(seed: seed)]))
      let corners = try XCTUnwrap(conversion.corners["room-1"])
      XCTAssertEqual(corners.count, 6)
      for (index, corner) in corners.enumerated() {
        assertPoint(corner, lTruth[index], within: 0.010, "walk \(seed) corner \(index)")
      }
    }

    let conversion = try Walk.convert(Walk.log(rooms: [lRoom(seed: 1)]))
    let room = conversion.measurements.rooms[0]
    XCTAssertEqual(room.walls.map(\.turn), [nil, nil, .right, nil, nil, nil], "one right turn")
    XCTAssertEqual(conversion.summary.loopClosureMm, 0)

    let result = try SketchSolver.solve(conversion.measurements, context: Walk.context)
    let polygon = result.model.rooms[0].polygon
    XCTAssertEqual(polygon.count, 6)
    for (index, corner) in polygon.enumerated() {
      assertPoint(corner, lTruth[index], within: 0.020, "solved corner \(index)")
    }
    for (index, length) in edgeLengths(polygon).enumerated() {
      XCTAssertEqual(length, [6.0, 2, 3, 2, 3, 4][index], accuracy: 0.010, "wall \(index + 1)")
    }
  }

  func testThreeOrMoreTapsAreFittedByTotalLeastSquares() throws {
    let conversion = try Walk.convert(
      Walk.log(rooms: [lRoom(seed: 0xB3, extraOnFirstWall: true)]))
    let corners = try XCTUnwrap(conversion.corners["room-1"])
    for (index, corner) in corners.enumerated() {
      assertPoint(corner, lTruth[index], within: 0.010, "corner \(index)")
    }
  }

  func testParallelConsecutiveWallsThrow() {
    // Walls 2 and 3 run along the same line: no corner between them.
    let walls: [[WalkthroughLog.Tap]] = [
      [Walk.tap((0.5, 0), t: 1), Walk.tap((3.5, 0), t: 2)],
      [Walk.tap((4, 0.5), t: 3), Walk.tap((4, 1.0), t: 4)],
      [Walk.tap((4, 2.0), t: 5), Walk.tap((4, 2.5), t: 6)],
      [Walk.tap((2, 3), t: 7), Walk.tap((1, 3), t: 8)],
      [Walk.tap((0, 2), t: 9), Walk.tap((0, 1), t: 10)],
    ]
    let room = WalkthroughLog.Room(id: "room-4", label: "Hall", method: .walls, walls: walls)
    XCTAssertThrowsError(try Walk.convert(Walk.log(rooms: [room]))) {
      XCTAssertEqual($0 as? WalkthroughError, .wallsDoNotMeet(roomId: "room-4", wallIndex: 1))
    }
  }

  func testWallsRoomNeedsThreeWalls() {
    let room = WalkthroughLog.Room(
      id: "room-2", label: "Nook", method: .walls,
      walls: [
        [Walk.tap((0, 0), t: 1), Walk.tap((1, 0), t: 2)],
        [Walk.tap((1, 0), t: 3), Walk.tap((1, 1), t: 4)],
      ])
    XCTAssertThrowsError(try Walk.convert(Walk.log(rooms: [room]))) {
      XCTAssertEqual($0 as? WalkthroughError, .tooFewCorners(roomId: "room-2"))
    }
  }

  func testLiveCornersOfAWallsRoom() throws {
    var room = lRoom(seed: 1)
    let all = room.walls ?? []
    room.walls = Array(all.prefix(1))
    XCTAssertNil(WalkthroughConverter.liveCorners(room, floorY: Walk.floorY), "no corner yet")
    room.walls = Array(all.prefix(2))
    XCTAssertNil(WalkthroughConverter.liveCorners(room, floorY: Walk.floorY), "one corner")
    // A wall with one tap so far does not count.
    room.walls = Array(all.prefix(3)) + [Array(all[3].prefix(1))]
    let live = try XCTUnwrap(WalkthroughConverter.liveCorners(room, floorY: Walk.floorY))
    XCTAssertEqual(live.count, 2)
    XCTAssertEqual(live[0].y, Walk.floorY)
    assertPoint(Vec3(x: live[0].x, y: 0, z: live[0].z), lTruth[1], within: 0.010, "corner 1")
    assertPoint(Vec3(x: live[1].x, y: 0, z: live[1].z), lTruth[2], within: 0.010, "corner 2")
  }
}
