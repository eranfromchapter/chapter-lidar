import CaptureContract
import SketchReading
import SketchSolver
import XCTest

/// AC1 and AC2 of spec F16, and how the scale is chosen.
final class ScaleInterpretationTests: XCTestCase {
  /// The 4 x 3 m bedroom drawn at about 10 mm per unit, clockwise on the page, with the top and
  /// right walls dimensioned 13' 1.5" (4000.5 mm) and 9' 10.5" (3009.9 mm).
  private func dimensionedBedroom(ceilingMm: Double? = nil) -> SketchInterpretation {
    Reading.interpretation(
      units: .imperial, ceilingMm: ceilingMm,
      rooms: [
        SketchInterpretation.Room(
          label: "Bedroom", type: .bedroom,
          corners: Reading.clockwiseRectangle(x: 100, y: 100, width: 400, height: 300))
      ],
      dimensions: [
        SketchInterpretation.Dimension(text: "13' 1.5\"", valueMm: 4000.5, room: 0, wall: 0),
        SketchInterpretation.Dimension(text: "9' 10.5\"", valueMm: 3009.9, room: 0, wall: 1),
      ])
  }

  // MARK: - AC1

  func testAC1WrittenDimensionsGiveMeasuredWallsAndTheOthersAreDerived() throws {
    let conversion = try Reading.convert(dimensionedBedroom())
    XCTAssertEqual(conversion.scaleSource, .writtenDimensions(count: 2))
    let ratios = [4000.5 / 400, 3009.9 / 300]
    XCTAssertEqual(conversion.millimetresPerUnit, (ratios[0] + ratios[1]) / 2, accuracy: 1e-9)
    try validate(conversion.measurements, schema: "sketch-measurements.schema.json")

    // Drawn clockwise: corner 0 kept, the walls renumbered, so drawn wall 0 (top) is document
    // wall 3 and drawn wall 1 (right) is document wall 2.
    let walls = conversion.measurements.rooms[0].walls
    XCTAssertEqual(walls.map(\.id), ["wall-1", "wall-2", "wall-3", "wall-4"])
    XCTAssertEqual(
      walls[3].length,
      SketchMeasurements.Length(
        valueMm: 4000.5, enteredUnit: .ftIn, enteredText: "13' 1.5\"", measured: true))
    XCTAssertEqual(
      walls[2].length,
      SketchMeasurements.Length(
        valueMm: 3009.9, enteredUnit: .ftIn, enteredText: "9' 10.5\"", measured: true))
    // The opposite walls are the only unknown on their axes: left to the solver's closure.
    XCTAssertNil(walls[0].length)
    XCTAssertNil(walls[1].length)
    XCTAssertTrue(walls.allSatisfy { $0.turn == nil }, "every corner square")

    let result = try Reading.solve(conversion)
    let room = try XCTUnwrap(result.model.rooms.first)
    let edges = edgeLengthsMm(room)
    XCTAssertEqual(edges[3], 4000.5, accuracy: 1)
    XCTAssertEqual(edges[2], 3009.9, accuracy: 1)
    XCTAssertEqual(edges[1], 4000.5, accuracy: 1)
    XCTAssertEqual(edges[0], 3009.9, accuracy: 1)
    XCTAssertEqual(result.model.walls.map(\.confidence), [.medium, .medium, .high, .high])
    let derived = result.notes.compactMap { note -> String? in
      if case .wallDerivedFromClosure(let id) = note.kind { return id }
      return nil
    }
    XCTAssertEqual(Set(derived), ["wall-1", "wall-2"])

    // Complete apart from the height: the only thing that limits it is the assumed ceiling.
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertEqual(limitingNotes(result), [.ceilingAssumed])
    XCTAssertEqual(result.summary.wallsMeasured, 2)
    XCTAssertEqual(result.summary.wallsEstimated, 0)
    XCTAssertEqual(result.summary.ceilingHeightSource, .assumed)
  }

  func testAC1WithTheCeilingWrittenSolvesComplete() throws {
    var reading = dimensionedBedroom(ceilingMm: 2438)
    reading.reading.dimensions.append(
      SketchInterpretation.Dimension(text: "8' clg", valueMm: 2438))
    let conversion = try Reading.convert(reading)
    XCTAssertEqual(
      conversion.measurements.ceilingHeight,
      SketchMeasurements.Length(
        valueMm: 2438, enteredUnit: .ftIn, enteredText: "8' clg", measured: true))
    let result = try Reading.solve(conversion)
    XCTAssertEqual(result.summary.measurements, .complete)
    XCTAssertEqual(result.summary.ceilingHeightSource, .measured)
    XCTAssertEqual(result.model.rooms[0].heightM, 2.438, accuracy: 1e-9)
  }

  func testCeilingWithoutALabelGetsAGeneratedText() throws {
    let conversion = try Reading.convert(dimensionedBedroom(ceilingMm: 2700), displayUnits: .metric)
    XCTAssertEqual(
      conversion.measurements.ceilingHeight,
      SketchMeasurements.Length(valueMm: 2700, enteredUnit: .mm, enteredText: "2700", measured: true))
  }

  // MARK: - AC2

  func testAC2OneUserLengthGivesEveryOtherWallByProportionEstimated() throws {
    // 400 x 225 units, no dimensions written.
    let reading = Reading.interpretation(
      units: .none,
      rooms: [
        SketchInterpretation.Room(
          label: "Office", type: .office,
          corners: Reading.clockwiseRectangle(x: 100, y: 100, width: 400, height: 225))
      ])
    XCTAssertTrue(SketchReadingConverter.needsOneLength(reading))
    XCTAssertThrowsError(try Reading.convert(reading)) { error in
      XCTAssertEqual(error as? SketchReadingError, .needsOneLength)
    }

    let typed = SketchMeasurements.Length(
      valueMm: 4000, enteredUnit: .mm, enteredText: "4000", measured: true)
    let conversion = try Reading.convert(
      reading, userLength: UserScaleLength(roomIndex: 0, wallIndex: 0, length: typed),
      displayUnits: .metric)
    XCTAssertEqual(conversion.scaleSource, .userLength)
    XCTAssertEqual(conversion.millimetresPerUnit, 10, accuracy: 1e-12)
    try validate(conversion.measurements, schema: "sketch-measurements.schema.json")

    let walls = conversion.measurements.rooms[0].walls
    // Drawn wall 0 (top) is document wall 3 after renumbering.
    XCTAssertEqual(walls[3].length, typed)
    for index in 0..<3 {
      let length = try XCTUnwrap(walls[index].length, "wall \(index) has a proportional length")
      XCTAssertFalse(length.measured, "wall \(index) is estimated")
      XCTAssertEqual(length.enteredUnit, .mm)
    }
    XCTAssertEqual(walls[0].length?.valueMm ?? 0, 2250, accuracy: 0.1)
    XCTAssertEqual(walls[1].length?.valueMm ?? 0, 4000, accuracy: 0.1)
    XCTAssertEqual(walls[2].length?.valueMm ?? 0, 2250, accuracy: 0.1)
    XCTAssertEqual(walls[0].length?.enteredText, "2250")

    let result = try Reading.solve(conversion)
    XCTAssertEqual(result.summary.measurements, .limited)
    XCTAssertEqual(result.summary.wallsMeasured, 1)
    XCTAssertEqual(result.summary.wallsEstimated, 3)
    let estimated = result.notes.compactMap { note -> String? in
      if case .wallEstimated(let id) = note.kind { return id }
      return nil
    }
    XCTAssertEqual(Set(estimated), ["wall-1", "wall-2", "wall-3"])
    let edges = edgeLengthsMm(result.model.rooms[0])
    XCTAssertEqual(edges[3], 4000, accuracy: 1)
    XCTAssertEqual(edges[0], 2250, accuracy: 1)
  }

  func testProportionalWallsOfAWobblyRoomAreClosedWithoutTouchingTheUserLength() throws {
    // A hand-drawn rectangle: the bottom is drawn 410 long against the top's 400.
    let reading = Reading.interpretation(
      units: .none,
      rooms: [
        SketchInterpretation.Room(
          label: "Den",
          corners: [
            Reading.point(100, 100), Reading.point(500, 101), Reading.point(503, 300),
            Reading.point(93, 302),
          ])
      ])
    let typed = SketchMeasurements.Length(
      valueMm: 4000, enteredUnit: .mm, enteredText: "4000", measured: true)
    let conversion = try Reading.convert(
      reading, userLength: UserScaleLength(roomIndex: 0, wallIndex: 0, length: typed),
      displayUnits: .metric)
    let walls = conversion.measurements.rooms[0].walls
    XCTAssertEqual(walls[3].length, typed)
    // The opposite wall takes the whole residual of its axis so the room closes on 4000.
    XCTAssertEqual(walls[1].length?.valueMm ?? 0, 4000, accuracy: 0.1)
    let result = try Reading.solve(conversion)
    let residuals = result.notes.compactMap { note -> Double? in
      if case .closureResidual(_, _, let residual, _) = note.kind { return residual }
      return nil
    }
    XCTAssertTrue(residuals.allSatisfy { abs($0) < 0.5 }, "\(residuals)")
    XCTAssertEqual(edgeLengthsMm(result.model.rooms[0])[3], 4000, accuracy: 0.5)
  }

  // MARK: - Scale

  func testADimensionFarFromTheOthersIsDroppedAndNoted() throws {
    var reading = dimensionedBedroom()
    reading.reading.dimensions = [
      SketchInterpretation.Dimension(text: "13'", valueMm: 4000, room: 0, wall: 0),
      SketchInterpretation.Dimension(text: "10'", valueMm: 3000, room: 0, wall: 1),
      SketchInterpretation.Dimension(text: "16' 5\"", valueMm: 5000, room: 0, wall: 2),
    ]
    let conversion = try Reading.convert(reading)
    XCTAssertEqual(conversion.scaleSource, .writtenDimensions(count: 2))
    XCTAssertEqual(conversion.millimetresPerUnit, 10, accuracy: 1e-12)
    XCTAssertTrue(
      conversion.notes.contains("16' 5\" on Bedroom wall 3 was 25 % off the others and was not used."),
      "\(conversion.notes)")
    XCTAssertEqual(conversion.notes.first, "2 written dimensions set the scale.")
    // Drawn wall 2 (bottom) is document wall 1: not measured by the dropped dimension.
    let walls = conversion.measurements.rooms[0].walls
    XCTAssertNil(walls[1].length)
    let result = try Reading.solve(conversion)
    let edges = edgeLengthsMm(result.model.rooms[0])
    XCTAssertEqual(edges[1], 4000, accuracy: 1)
  }

  func testAUserLengthSetsTheScaleAloneAndKeepsWrittenDimensionsThatAgree() throws {
    var reading = dimensionedBedroom()
    reading.reading.dimensions = [
      SketchInterpretation.Dimension(text: "10'", valueMm: 3048, room: 0, wall: 1)
    ]
    let typed = SketchMeasurements.Length(
      valueMm: 4100, enteredUnit: .ftIn, enteredText: "13' 5.4\"", measured: true)
    let conversion = try Reading.convert(
      reading, userLength: UserScaleLength(roomIndex: 0, wallIndex: 0, length: typed))
    XCTAssertEqual(conversion.scaleSource, .userLength)
    XCTAssertEqual(conversion.millimetresPerUnit, 10.25, accuracy: 1e-12)
    let walls = conversion.measurements.rooms[0].walls
    XCTAssertEqual(walls[3].length, typed)
    XCTAssertEqual(walls[2].length?.valueMm, 3048)
    XCTAssertEqual(walls[2].length?.measured, true)
  }

  func testDimensionsOnWallsThatAreNotDrawnAreNotedAndIgnored() throws {
    var reading = dimensionedBedroom()
    reading.reading.dimensions.append(
      SketchInterpretation.Dimension(text: "22'", valueMm: 6706, room: 0, wall: 9))
    reading.reading.dimensions.append(
      SketchInterpretation.Dimension(text: "30'", valueMm: 9144, room: nil, wall: nil))
    let conversion = try Reading.convert(reading)
    XCTAssertEqual(conversion.scaleSource, .writtenDimensions(count: 2))
    XCTAssertTrue(
      conversion.notes.contains("22' names wall 10 of Bedroom, which is not drawn; not used."))
  }

  func testNeedsOneLength() throws {
    XCTAssertFalse(SketchReadingConverter.needsOneLength(dimensionedBedroom()))
    var reading = dimensionedBedroom()
    reading.reading.dimensions = [
      SketchInterpretation.Dimension(text: "30' overall", valueMm: 9144),
      SketchInterpretation.Dimension(text: "13'", valueMm: 4000, room: 0, wall: 7),
      SketchInterpretation.Dimension(text: "13'", valueMm: 4000, room: 3, wall: 0),
      SketchInterpretation.Dimension(text: "about a foot", valueMm: nil, room: 0, wall: 1),
    ]
    XCTAssertTrue(SketchReadingConverter.needsOneLength(reading))
    XCTAssertThrowsError(try Reading.convert(reading)) { error in
      XCTAssertEqual(error as? SketchReadingError, .needsOneLength)
    }
    XCTAssertTrue(
      SketchReadingConverter.needsOneLength(Reading.interpretation(rooms: [])),
      "nothing drawn, nothing written")
  }

  func testDrawnWalls() throws {
    let walls = SketchReadingConverter.drawnWalls(try Reading.example("bedroom-and-closet"))
    XCTAssertEqual(walls.count, 8)
    XCTAssertEqual(
      walls[0],
      DrawnWall(
        roomIndex: 0, wallIndex: 0, roomLabel: "Bedroom", drawnLength: 460,
        start: Reading.point(150, 220), end: Reading.point(610, 220)))
    XCTAssertEqual(walls[3].end, Reading.point(150, 220), "the last wall closes the loop")
    XCTAssertEqual(walls[5].drawnLength, 180)
    XCTAssertEqual(walls[5].id, "1-1")
    XCTAssertEqual(walls.map(\.roomLabel), Array(repeating: "Bedroom", count: 4) + Array(repeating: "Closet", count: 4))
  }

  func testUserLengthOnAWallThatIsNotDrawnThrows() throws {
    let typed = SketchMeasurements.Length(
      valueMm: 4000, enteredUnit: .mm, enteredText: "4000", measured: true)
    XCTAssertThrowsError(
      try Reading.convert(
        dimensionedBedroom(), userLength: UserScaleLength(roomIndex: 0, wallIndex: 4, length: typed))
    ) { error in
      XCTAssertEqual(error as? SketchReadingError, .unknownWall(roomIndex: 0, wallIndex: 4))
    }
  }
}
