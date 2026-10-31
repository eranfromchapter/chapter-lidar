import CaptureContract
import SketchReading
import SketchSolver
import XCTest

/// Winding, odd corners, openings and furniture of a reading.
final class OutlineInterpretationTests: XCTestCase {
  private let dimensions = [
    SketchInterpretation.Dimension(text: "4000", valueMm: 4000, room: 0, wall: 0),
    SketchInterpretation.Dimension(text: "3000", valueMm: 3000, room: 0, wall: 1),
  ]

  private func reading(
    corners: [SketchInterpretation.Point], openings: [SketchInterpretation.Opening] = [],
    furniture: [SketchInterpretation.Furniture] = [],
    dimensions: [SketchInterpretation.Dimension]? = nil
  ) -> SketchInterpretation {
    Reading.interpretation(
      units: .metric,
      rooms: [
        SketchInterpretation.Room(
          label: "Kitchen", type: .kitchen, corners: corners, openings: openings,
          furniture: furniture)
      ], dimensions: dimensions ?? self.dimensions)
  }

  func testAClockwiseRoomIsRewoundWithItsOpeningsRemapped() throws {
    // Clockwise on the page: top-left, top-right, bottom-right, bottom-left; a window on the
    // top wall from 0.1 to 0.3 of the way left to right (x 140 to 220, model x 0.4 to 1.2 m).
    let window = SketchInterpretation.Opening(kind: .window, wall: 0, start: 0.1, end: 0.3)
    let clockwise = reading(
      corners: Reading.clockwiseRectangle(x: 100, y: 100, width: 400, height: 300),
      openings: [window])
    let conversion = try Reading.convert(clockwise, displayUnits: .metric)
    XCTAssertTrue(conversion.notes.contains("Kitchen was drawn clockwise; its walls were renumbered counter-clockwise."))
    let room = conversion.measurements.rooms[0]
    XCTAssertEqual(room.walls[3].length?.valueMm, 4000, "drawn wall 1 is document wall 4")
    XCTAssertEqual(room.walls[2].length?.valueMm, 3000, "drawn wall 2 is document wall 3")
    let opening = try XCTUnwrap(room.openings.first)
    XCTAssertEqual(opening.wallId, room.walls[3].id)
    XCTAssertEqual(opening.fromCornerDistance?.valueMm ?? 0, 2800, accuracy: 0.1)
    XCTAssertEqual(opening.width?.valueMm ?? 0, 800, accuracy: 0.1)

    let result = try Reading.solve(conversion)
    let model = try XCTUnwrap(result.model.windows.first)
    let wall = try XCTUnwrap(result.model.walls.first { $0.id == model.wallId })
    let dx: Double = wall.end.x - wall.start.x
    let dz: Double = wall.end.z - wall.start.z
    let length: Double = (dx * dx + dz * dz).squareRoot()
    let centreX: Double = wall.start.x + dx / length * model.offsetM
    let centreZ: Double = wall.start.z + dz / length * model.offsetM
    XCTAssertEqual(centreX, 0.8, accuracy: 0.001, "where it is drawn")
    XCTAssertLessThan(centreZ, 0, "in the top wall, up the sheet")
    XCTAssertEqual(model.widthM, 0.8, accuracy: 1e-6)

    // The same room drawn counter-clockwise on the page: not rewound, the same polygon.
    let counterClockwise = reading(
      corners: [
        Reading.point(100, 100), Reading.point(100, 400), Reading.point(500, 400),
        Reading.point(500, 100),
      ],
      openings: [SketchInterpretation.Opening(kind: .window, wall: 3, start: 0.7, end: 0.9)],
      dimensions: [
        SketchInterpretation.Dimension(text: "4000", valueMm: 4000, room: 0, wall: 3),
        SketchInterpretation.Dimension(text: "3000", valueMm: 3000, room: 0, wall: 2),
      ])
    let plain = try Reading.convert(counterClockwise, displayUnits: .metric)
    XCTAssertFalse(plain.notes.contains { $0.contains("drawn clockwise") })
    XCTAssertEqual(plain.measurements.rooms, conversion.measurements.rooms)
  }

  func testAnUnsquareCornerGetsADiagonalAndIsNoted() throws {
    // A room whose right wall leans out: the top-right corner is drawn at about 76°.
    let corners = [
      Reading.point(100, 100), Reading.point(100, 400), Reading.point(500, 400),
      Reading.point(425, 100),
    ]
    let conversion = try Reading.convert(
      reading(
        corners: corners,
        dimensions: [SketchInterpretation.Dimension(text: "3000", valueMm: 3000, room: 0, wall: 0)]),
      displayUnits: .metric)
    let room = conversion.measurements.rooms[0]
    XCTAssertEqual(room.walls.map(\.turn), [nil, .unsquare, .unsquare, nil])
    XCTAssertEqual(Set(room.diagonals.map { [$0.from, $0.to] }), [[1, 3], [0, 2]])
    XCTAssertTrue(room.diagonals.allSatisfy { !$0.length.measured })
    XCTAssertTrue(conversion.notes.contains { $0.hasPrefix("Kitchen: corner 3 is drawn at 76°") })
    let result = try Reading.solve(conversion)
    let edges = edgeLengthsMm(result.model.rooms[0])
    XCTAssertEqual(edges[0], 3000, accuracy: 1)
    XCTAssertEqual(edges[1], 4000, accuracy: 5)
    XCTAssertEqual(edges[3], 3250, accuracy: 5)
  }

  func testRepeatedAndStraightCornersAreLeftOut() throws {
    // The first corner repeated at the end, and the top wall drawn in two strokes.
    let corners = [
      Reading.point(100, 100), Reading.point(100, 400), Reading.point(500, 400),
      Reading.point(500, 100), Reading.point(300, 101), Reading.point(100, 100),
    ]
    let door = SketchInterpretation.Opening(kind: .door, wall: 4, start: 0.5, end: 0.9)
    let conversion = try Reading.convert(
      reading(
        corners: corners, openings: [door],
        dimensions: [SketchInterpretation.Dimension(text: "3000", valueMm: 3000, room: 0, wall: 0)]),
      displayUnits: .metric)
    let room = conversion.measurements.rooms[0]
    XCTAssertEqual(room.walls.count, 4)
    XCTAssertTrue(conversion.notes.contains("Kitchen: 2 drawn corners on a straight wall or repeated were left out."))
    // Drawn wall 4 runs from x 300 to 100: the second half of document wall 4 (x 500 to 100).
    let opening = try XCTUnwrap(room.openings.first)
    XCTAssertEqual(opening.wallId, room.walls[3].id)
    XCTAssertEqual(opening.fromCornerDistance?.valueMm ?? 0, 3000, accuracy: 10)
    XCTAssertEqual(opening.width?.valueMm ?? 0, 800, accuracy: 10)
  }

  func testTooFewCornersAndUnknownWallsThrow() throws {
    let two = reading(corners: [Reading.point(0, 0), Reading.point(100, 0)])
    XCTAssertThrowsError(try Reading.convert(two)) { error in
      XCTAssertEqual(error as? SketchReadingError, .tooFewCorners(roomIndex: 0))
    }
    let line = reading(corners: [Reading.point(0, 0), Reading.point(100, 0), Reading.point(200, 0)])
    XCTAssertThrowsError(try Reading.convert(line)) { error in
      XCTAssertEqual(error as? SketchReadingError, .tooFewCorners(roomIndex: 0))
    }
    let badOpening = reading(
      corners: Reading.clockwiseRectangle(x: 100, y: 100, width: 400, height: 300),
      openings: [SketchInterpretation.Opening(kind: .door, wall: 4, start: 0.1, end: 0.3)])
    XCTAssertThrowsError(try Reading.convert(badOpening)) { error in
      XCTAssertEqual(error as? SketchReadingError, .unknownWall(roomIndex: 0, wallIndex: 4))
    }
    XCTAssertThrowsError(try Reading.convert(Reading.interpretation(rooms: []))) { error in
      XCTAssertEqual(error as? SketchReadingError, .noRooms)
    }
  }

  func testFurnitureAngleClockwiseInTheDrawingIsClockwiseSeenFromAbove() throws {
    // A 2 m x 0.5 m table turned 30° clockwise on the page: its length runs right and down the
    // page, which is +x and +z in the model.
    let table = SketchInterpretation.Furniture(
      category: .table, center: Reading.point(300, 250), width: 200, depth: 50, angleDeg: 30)
    let conversion = try Reading.convert(
      reading(
        corners: Reading.clockwiseRectangle(x: 100, y: 100, width: 400, height: 300),
        furniture: [table]),
      displayUnits: .metric)
    let item = try XCTUnwrap(conversion.measurements.rooms[0].furniture?.first)
    XCTAssertEqual(item.id, "furniture-1")
    XCTAssertEqual(item.angleDeg, -30, "counter-clockwise about +Y")
    XCTAssertEqual(item.x, 2, accuracy: 1e-9)
    XCTAssertEqual(item.z, 1.5, accuracy: 1e-9)
    XCTAssertEqual(item.widthM, 2, accuracy: 1e-9)
    XCTAssertEqual(item.depthM, 0.5, accuracy: 1e-9)
    XCTAssertNil(item.heightM)

    let object = try XCTUnwrap(try Reading.solve(conversion).model.objects.first)
    let axis = localX(object.box.rotation)
    let radians: Double = 30 * Double.pi / 180
    XCTAssertEqual(axis.x, cos(radians), accuracy: 1e-6)
    XCTAssertEqual(axis.y, 0, accuracy: 1e-9)
    XCTAssertEqual(axis.z, sin(radians), accuracy: 1e-6, "+z: down the page, as drawn")
    XCTAssertEqual(object.box.sizeM.y, 0.75, accuracy: 1e-9)
  }
}
