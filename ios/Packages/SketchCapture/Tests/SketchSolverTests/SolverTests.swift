import CaptureContract
import CaptureTestSupport
import SketchSolver
import XCTest

/// AC1: the required set of a 4.000 x 3.000 m rectangle gives a capture model within 1 mm,
/// validates against the contract schema and survives a JSON round trip; the contract's own
/// two-room example solves with the closet placed against the bedroom.
final class SolverTests: XCTestCase {
  private let halfInterior = 0.05715  // half of 114.3 mm

  func testRequiredRectangleGivesTheModelWithinOneMillimetre() throws {
    let result = try SketchSolver.solve(Sketch.requiredRectangle(), context: Sketch.context)
    let model = result.model

    XCTAssertEqual(model.label, "Floor 1")
    XCTAssertEqual(model.areaKey, "floor-1")
    XCTAssertEqual(model.visitId, Sketch.visitId)
    XCTAssertEqual(model.captureId, Sketch.captureId)
    XCTAssertTrue(model.refs.isEmpty)
    XCTAssertTrue(model.objects.isEmpty)

    // The room: corner 0 at the origin, wall 1 along +x, counter-clockwise seen from +Y.
    let room = try XCTUnwrap(model.rooms.first)
    XCTAssertEqual(model.rooms.count, 1)
    XCTAssertEqual(room.id, "room-1")
    XCTAssertEqual(room.label, "Kitchen")
    XCTAssertEqual(room.type, .kitchen)
    XCTAssertEqual(room.typeSource, .operator)
    XCTAssertEqual(room.heightM, 2.7, accuracy: 1e-9)
    XCTAssertEqual(room.polygon.count, 4)
    assertVec(room.polygon[0], 0, 0, 0, "corner 0")
    assertVec(room.polygon[1], 4, 0, 0, "corner 1")
    assertVec(room.polygon[2], 4, 0, -3, "corner 2")
    assertVec(room.polygon[3], 0, 0, -3, "corner 3")
    XCTAssertLessThan(signedArea(room.polygon), 0, "counter-clockwise seen from +Y")

    // Walls: centrelines half a thickness outside the inside faces, meeting at the corners.
    XCTAssertEqual(model.walls.map(\.id), ["wall-1", "wall-2", "wall-3", "wall-4"])
    let h = halfInterior
    let wall1 = try wall("wall-1", in: model)
    assertVec(wall1.start, -h, 0, h, "wall-1 start")
    assertVec(wall1.end, 4 + h, 0, h, "wall-1 end")
    let wall2 = try wall("wall-2", in: model)
    assertVec(wall2.start, 4 + h, 0, h, "wall-2 start")
    assertVec(wall2.end, 4 + h, 0, -3 - h, "wall-2 end")
    let wall3 = try wall("wall-3", in: model)
    assertVec(wall3.start, 4 + h, 0, -3 - h, "wall-3 start")
    assertVec(wall3.end, -h, 0, -3 - h, "wall-3 end")
    let wall4 = try wall("wall-4", in: model)
    assertVec(wall4.start, -h, 0, -3 - h, "wall-4 start")
    assertVec(wall4.end, -h, 0, h, "wall-4 end")
    for wall in model.walls {
      XCTAssertEqual(wall.heightM, 2.7, accuracy: 1e-9, wall.id)
      XCTAssertEqual(wall.thicknessM, 0.1143, accuracy: 1e-9, wall.id)
      XCTAssertEqual(wall.roomIds, ["room-1"], wall.id)
    }
    // Measured walls are high; the two filled from closure are derived (medium), not estimates.
    XCTAssertEqual(wall1.confidence, .high)
    XCTAssertEqual(wall2.confidence, .high)
    XCTAssertEqual(wall3.confidence, .medium)
    XCTAssertEqual(wall4.confidence, .medium)
    XCTAssertEqual(
      Set(result.notes(where: { if case .wallDerivedFromClosure = $0 { return true }; return false }).map(\.kind)),
      [.wallDerivedFromClosure(wallId: "wall-3"), .wallDerivedFromClosure(wallId: "wall-4")])

    // The door: 0.5 m from the start corner of wall 2, so its centre is 0.95 m along the inside
    // face, plus the half thickness the centreline starts before the corner.
    XCTAssertEqual(model.doors.count, 1)
    let door = try XCTUnwrap(model.doors.first)
    XCTAssertEqual(door.id, "door-1")
    XCTAssertEqual(door.wallId, "wall-2")
    XCTAssertEqual(door.offsetM, h + 0.95, accuracy: 0.001)
    XCTAssertEqual(door.bottomM, 0)
    XCTAssertEqual(door.widthM, 0.9, accuracy: 1e-9)
    XCTAssertEqual(door.heightM, 2.032, accuracy: 1e-9, "default door height")
    XCTAssertEqual(door.confidence, .high)
    XCTAssertNil(door.isOpen)
    // Where that puts it on the plan: on wall 2's centreline, 0.95 m from corner 1.
    let doorCentreZ = wall2.start.z - door.offsetM
    XCTAssertEqual(doorCentreZ, -0.95, accuracy: 0.001)

    // The window: 1.0 m from the end corner of wall 1 with a 1.2 m width, so its centre is
    // 4.0 − 1.0 − 0.6 = 2.4 m from the start corner.
    XCTAssertEqual(model.windows.count, 1)
    let window = try XCTUnwrap(model.windows.first)
    XCTAssertEqual(window.wallId, "wall-1")
    XCTAssertEqual(window.offsetM, h + 2.4, accuracy: 0.001)
    XCTAssertEqual(window.bottomM, 0.9, accuracy: 1e-9)
    XCTAssertEqual(window.widthM, 1.2, accuracy: 1e-9)
    XCTAssertEqual(window.heightM, 1.2, accuracy: 1e-9)
    XCTAssertEqual(window.confidence, .high)
    XCTAssertNil(window.isOpen)
    XCTAssertTrue(model.openings.isEmpty)

    // Summary: complete. Derived walls and a defaulted door height do not make it limited.
    XCTAssertEqual(result.summary.measurements, .complete)
    XCTAssertFalse(result.isLimited)
    XCTAssertEqual(result.summary.wallsMeasured, 2)
    XCTAssertEqual(result.summary.wallsEstimated, 0)
    XCTAssertEqual(result.summary.ceilingHeightSource, .measured)
    XCTAssertNil(result.summary.closureResidualMm, "no axis had every wall measured")
    XCTAssertEqual(
      result.notes.map(\.kind).filter {
        if case .openingEstimated(_, let field) = $0 { return field == .width || field == .position }
        return false
      }.count, 0)
  }

  func testRequiredRectangleValidatesAgainstTheCaptureModelSchema() throws {
    let result = try SketchSolver.solve(Sketch.requiredRectangle(), context: Sketch.context)
    let data = try CaptureContractJSON.makeEncoder().encode(result.model)
    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
    XCTAssertEqual(try validator.validate(jsonData: data), [])
  }

  func testRequiredRectangleRoundTripsThroughJSON() throws {
    let result = try SketchSolver.solve(Sketch.requiredRectangle(), context: Sketch.context)
    let encoder = CaptureContractJSON.makeEncoder()
    let data = try encoder.encode(result.model)
    let decoded = try JSONDecoder().decode(CaptureModel.self, from: data)
    XCTAssertEqual(decoded, result.model)
    XCTAssertEqual(try encoder.encode(decoded), data, "byte-stable")
  }

  func testSolvingTwiceGivesTheSameModel() throws {
    let a = try SketchSolver.solve(Sketch.requiredRectangle(), context: Sketch.context)
    let b = try SketchSolver.solve(Sketch.requiredRectangle(), context: Sketch.context)
    XCTAssertEqual(a.model, b.model)
    XCTAssertEqual(a.notes, b.notes)
  }

  func testContextLabelAndRefsAreCarried() throws {
    let refs = [CaptureModel.SourceRef(role: .meshGLB, path: "Original Exports/floor-1/x/mesh.glb")]
    let result = try SketchSolver.solve(
      Sketch.requiredRectangle(), context: SketchSolveContext(label: "Ground floor", refs: refs))
    XCTAssertEqual(result.model.label, "Ground floor")
    XCTAssertEqual(result.model.refs, refs)
  }

  // MARK: - The contract example

  private func twoRooms() throws -> SketchMeasurements {
    let url = Fixtures.repositoryRoot.appendingPathComponent(
      "contract/examples/sketch-measurements/valid/two-rooms.json")
    return try JSONDecoder().decode(SketchMeasurements.self, from: Data(contentsOf: url))
  }

  func testTwoRoomsExampleSolvesAndPlacesTheClosetAgainstTheBedroom() throws {
    let result = try SketchSolver.solve(try twoRooms(), context: Sketch.context)
    let model = result.model
    XCTAssertEqual(model.rooms.map(\.id), ["room-1", "room-2"])
    XCTAssertEqual(model.walls.count, 8)
    XCTAssertEqual(model.doors.map(\.id), ["door-1", "door-2"])
    XCTAssertEqual(model.windows.map(\.id), ["window-1"])

    // The bedroom closes within tolerance on both axes (13 mm on 4 m and on 3 m): the residual
    // is distributed over the walls, so opposite walls come out equal.
    let bedroom = model.rooms[0]
    let bedroomEdges = edgeLengths(bedroom)
    XCTAssertEqual(bedroomEdges[0], bedroomEdges[2], accuracy: 1e-6)
    XCTAssertEqual(bedroomEdges[1], bedroomEdges[3], accuracy: 1e-6)
    // Compass rule: the 13 mm residual is shared in proportion to length, so the longer entered
    // wall gives up a little more than the shorter one gains.
    XCTAssertEqual(bedroomEdges[0], (4001 - 13 * 4001 / (4001 + 3988)) / 1000, accuracy: 2e-6)
    XCTAssertEqual(bedroomEdges[1], (3010 - 13 * 3010 / (3010 + 2997)) / 1000, accuracy: 2e-6)
    XCTAssertEqual(result.summary.closureResidualMm ?? 0, 13, accuracy: 1e-6)
    XCTAssertTrue(result.closureNotes.allSatisfy { $0.grade == .pass })

    // Exterior walls are 6 in thick, the others 4.5 in.
    XCTAssertEqual(try wall("wall-1", in: model).thicknessM, 0.1524, accuracy: 1e-9)
    XCTAssertEqual(try wall("wall-2", in: model).thicknessM, 0.1524, accuracy: 1e-9)
    XCTAssertEqual(try wall("wall-3", in: model).thicknessM, 0.1143, accuracy: 1e-9)

    // The closet's wall-5 shares the bedroom's wall-4: centrelines coincide (same line, same
    // thickness), the walls run opposite ways, and the closet sits outside the bedroom (−x),
    // centred along wall-4 of the bedroom.
    let wall4 = try wall("wall-4", in: model)
    let wall5 = try wall("wall-5", in: model)
    XCTAssertEqual(wall4.thicknessM, wall5.thicknessM, accuracy: 1e-9)
    XCTAssertEqual(wall4.start.x, -halfInterior, accuracy: 0.001)
    XCTAssertEqual(wall4.end.x, -halfInterior, accuracy: 0.001)
    XCTAssertEqual(wall5.start.x, -halfInterior, accuracy: 0.001, "wall-5 on the same line")
    XCTAssertEqual(wall5.end.x, -halfInterior, accuracy: 0.001)
    let direction4 = wall4.end.z - wall4.start.z
    let direction5 = wall5.end.z - wall5.start.z
    XCTAssertLessThan(direction4 * direction5, 0, "the shared walls run in opposite directions")
    let closet = model.rooms[1]
    let bedroomDepth = bedroomEdges[1]
    let closetStartZ = -(bedroomDepth / 2 - 0.75)
    assertVec(closet.polygon[0], -0.1143, 0, closetStartZ, "closet corner 0")
    assertVec(closet.polygon[1], -0.1143, 0, closetStartZ - 1.5, "closet corner 1")
    XCTAssertTrue(closet.polygon.allSatisfy { $0.x <= -0.1143 + 1e-6 }, "closet outside the bedroom")
    XCTAssertLessThan(signedArea(closet.polygon), 0, "closet counter-clockwise seen from +Y")
    XCTAssertEqual(try wall("wall-5", in: model).roomIds, ["room-2"])
    XCTAssertEqual(wall4.roomIds, ["room-1"], "a partition appears once per room")

    // The closet: wall-5 measured, wall-6 and wall-8 "about" (low), wall-7 the only unknown on
    // its axis so derived from wall-5 (medium). That makes 5 measured walls, 2 estimated, and
    // the capture limited by the "about" walls and the unmeasured door.
    XCTAssertEqual(try wall("wall-5", in: model).confidence, .high)
    XCTAssertEqual(try wall("wall-6", in: model).confidence, .low)
    XCTAssertEqual(try wall("wall-7", in: model).confidence, .medium)
    XCTAssertEqual(try wall("wall-8", in: model).confidence, .low)
    XCTAssertEqual(result.summary.wallsMeasured, 5)
    XCTAssertEqual(result.summary.wallsEstimated, 2)
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertEqual(result.summary.ceilingHeightSource, .measured)
    XCTAssertTrue(result.notes.map(\.kind).contains(.wallDerivedFromClosure(wallId: "wall-7")))
    XCTAssertTrue(result.notes.map(\.kind).contains(.wallEstimated(wallId: "wall-6")))
    XCTAssertTrue(result.notes.map(\.kind).contains(.wallEstimated(wallId: "wall-8")))

    // The closet door has no width or distance: defaults, centred, low.
    let door2 = try XCTUnwrap(model.doors.first { $0.id == "door-2" })
    XCTAssertEqual(door2.widthM, 0.914, accuracy: 1e-9)
    XCTAssertEqual(door2.heightM, 2.032, accuracy: 1e-9)
    XCTAssertEqual(door2.offsetM, halfInterior + 0.75, accuracy: 0.001, "centred on the 1.5 m wall")
    XCTAssertEqual(door2.confidence, .low)
    XCTAssertTrue(result.notes.map(\.kind).contains(.openingEstimated(openingId: "door-2", field: .width)))
    XCTAssertTrue(result.notes.map(\.kind).contains(.openingEstimated(openingId: "door-2", field: .position)))

    // The bedroom's door and window were fully measured: high, with the measured heights.
    let door1 = try XCTUnwrap(model.doors.first { $0.id == "door-1" })
    XCTAssertEqual(door1.confidence, .high)
    XCTAssertEqual(door1.wallId, "wall-3")
    XCTAssertEqual(door1.widthM, 0.813, accuracy: 1e-9)
    let window = try XCTUnwrap(model.windows.first)
    XCTAssertEqual(window.confidence, .high)
    XCTAssertEqual(window.bottomM, 0.914, accuracy: 1e-9)

    let data = try CaptureContractJSON.makeEncoder().encode(model)
    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
    XCTAssertEqual(try validator.validate(jsonData: data), [])
  }

  // MARK: - Refusals

  func testNoRoomsIsRefused() {
    XCTAssertThrowsError(
      try SketchSolver.solve(Sketch.measurements(rooms: []), context: Sketch.context)
    ) { error in
      XCTAssertEqual(error as? SketchSolverError, .noRooms)
    }
  }

  func testTooFewWallsIsRefused() {
    let room = SketchMeasurements.Room(
      id: "room-1", label: "Nook", walls: [Sketch.wall("wall-1", 1000), Sketch.wall("wall-2", 1000)])
    XCTAssertThrowsError(
      try SketchSolver.solve(Sketch.measurements(rooms: [room]), context: Sketch.context)
    ) { error in
      XCTAssertEqual(error as? SketchSolverError, .tooFewWalls(roomId: "room-1"))
    }
  }

  func testDuplicateWallIdIsRefused() {
    let room = SketchMeasurements.Room(
      id: "room-1", label: "Kitchen",
      walls: [Sketch.wall("wall-1", 4000), Sketch.wall("wall-1", 3000), Sketch.wall("wall-3"), Sketch.wall("wall-4")])
    XCTAssertThrowsError(
      try SketchSolver.solve(Sketch.measurements(rooms: [room]), context: Sketch.context)
    ) { error in
      XCTAssertEqual(error as? SketchSolverError, .duplicateId("wall-1"))
    }
  }

  func testOpeningOnAnUnknownWallIsRefused() {
    let room = SketchMeasurements.Room(
      id: "room-1", label: "Kitchen",
      walls: [Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"), Sketch.wall("wall-4")],
      openings: [SketchMeasurements.Opening(id: "door-1", kind: .door, wallId: "wall-9", fromCorner: .start)])
    XCTAssertThrowsError(
      try SketchSolver.solve(Sketch.measurements(rooms: [room]), context: Sketch.context)
    ) { error in
      XCTAssertEqual(error as? SketchSolverError, .unknownWall(roomId: "room-1", wallId: "wall-9"))
    }
  }

  func testSharingAWallOfALaterRoomIsRefused() {
    let first = SketchMeasurements.Room(
      id: "room-1", label: "Kitchen",
      walls: [
        Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"),
        Sketch.wall("wall-4", sharedWith: SketchMeasurements.SharedWall(roomId: "room-2", wallId: "wall-5")),
      ])
    let second = SketchMeasurements.Room(
      id: "room-2", label: "Closet",
      walls: [Sketch.wall("wall-5", 1500), Sketch.wall("wall-6", 700), Sketch.wall("wall-7"), Sketch.wall("wall-8")])
    XCTAssertThrowsError(
      try SketchSolver.solve(Sketch.measurements(rooms: [first, second]), context: Sketch.context)
    ) { error in
      XCTAssertEqual(error as? SketchSolverError, .unknownSharedWall(roomId: "room-1", wallId: "wall-5"))
    }
  }

  func testDiagonalToANeighbourIsRefused() {
    let room = SketchMeasurements.Room(
      id: "room-1", label: "Kitchen",
      walls: [Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"), Sketch.wall("wall-4")],
      diagonals: [SketchMeasurements.Diagonal(from: 0, to: 1, length: Sketch.mm(4000))])
    XCTAssertThrowsError(
      try SketchSolver.solve(Sketch.measurements(rooms: [room]), context: Sketch.context)
    ) { error in
      XCTAssertEqual(error as? SketchSolverError, .badDiagonal(roomId: "room-1", from: 0, to: 1))
    }
  }

  func testUnsharedSecondRoomIsPlacedToThePlusXSideWithAGap() throws {
    let first = SketchMeasurements.Room(
      id: "room-1", label: "Kitchen",
      walls: [Sketch.wall("wall-1", 4000), Sketch.wall("wall-2", 3000), Sketch.wall("wall-3"), Sketch.wall("wall-4")])
    let second = SketchMeasurements.Room(
      id: "room-2", label: "Bath",
      walls: [Sketch.wall("wall-5", 2000), Sketch.wall("wall-6", 2500), Sketch.wall("wall-7"), Sketch.wall("wall-8")])
    let result = try SketchSolver.solve(
      Sketch.measurements(rooms: [first, second]), context: Sketch.context)
    let bath = result.model.rooms[1]
    XCTAssertEqual(bath.polygon.map(\.x).min() ?? 0, 5, accuracy: 0.001, "1 m past the kitchen")
    XCTAssertEqual(bath.polygon.map(\.z).max() ?? 0, 0, accuracy: 0.001, "aligned at the start")
    XCTAssertEqual(result.summary.measurements, .complete)
  }
}
