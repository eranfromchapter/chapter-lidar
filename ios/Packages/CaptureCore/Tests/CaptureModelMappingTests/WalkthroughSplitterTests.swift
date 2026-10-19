import CaptureContract
import CaptureTestSupport
import Foundation
import XCTest

@testable import CaptureModelMapping

/// The rules of walk-through splitting, one at a time (floorplan plan, phase 3).
final class WalkthroughSplitterTests: XCTestCase {
  // MARK: Segments

  private let square = [P2(0, 0), P2(10, 0), P2(10, 10), P2(0, 10)]

  private func segments(_ walls: [(P2, P2)], outline: [P2]? = nil, eps: Double = 0.05) -> WalkthroughSegments {
    let plan = WalkthroughInput.Plan(
      outline: outline ?? square, floorY: 0,
      walls: walls.enumerated().map { .init(index: $0, a: $1.0, b: $1.1, heightM: 2.5, baseY: 0) },
      sections: [], objects: [])
    return WalkthroughSegments(plan: plan, parameters: .init(), eps: eps)
  }

  private func assertClosure(
    _ result: WalkthroughSegments, _ method: WalkthroughSplitter.ClosureMethod, _ gap: Double?,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(result.dangling.map(\.method), [method], file: file, line: line)
    if let gap {
      XCTAssertEqual(result.dangling.first?.gapM ?? -1, gap, accuracy: 1e-9, file: file, line: line)
    } else {
      XCTAssertNil(result.dangling.first?.gapM, file: file, line: line)
    }
  }

  func testAWallEndShortOfAWallIsClosedByTheRightRule() {
    let across = (P2(0, 5), P2(10, 5))
    // Join: the end is 0.10 from the wall.
    assertClosure(segments([across, (P2(3, 0), P2(3, 4.9))]), .join, 0.1)
    // Ray: 0.45 m along the wall to the next one.
    assertClosure(segments([across, (P2(3, 0), P2(3, 4.55))]), .ray, 0.45)
    // No closure: 0.8 m is too far.
    let open = segments([across, (P2(3, 0), P2(3, 4.2))])
    assertClosure(open, .unclosed, nil)
    XCTAssertEqual(open.segments.filter { $0.kind == .gap }.count, 0)
  }

  func testTwoEndsThatMissEachOtherMeetAtTheirCorner() {
    // A wall from the left and one from the top stop 0.4 m short of the corner they should form.
    let result = segments([(P2(0, 6), P2(4.6, 6)), (P2(5, 10), P2(5, 6.4))])
    XCTAssertEqual(result.dangling.map(\.method), [.corner, .corner])
    for end in result.dangling { XCTAssertEqual(end.gapM ?? 0, 0.4, accuracy: 1e-9) }
    let gaps = result.segments.filter { $0.kind == .gap }
    XCTAssertEqual(gaps.count, 2)
    for gap in gaps { XCTAssertEqual(Plan2D.dist(gap.b, P2(5, 6)), 0, accuracy: 1e-9) }
  }

  func testAnEndAimingNearAnOutlineCornerIsClosedToIt() {
    // An end 0.5 m from the reflex corner of an L, aiming 15 degrees off it.
    let corner = P2(4, 3)
    let toCorner = P2(0.5.squareRoot(), 0.5.squareRoot())
    let end = corner - toCorner * 0.5
    let d = P2(0.5, 0.75.squareRoot())  // 60 degrees; the corner is at 45
    let start = end - d * (end.y / d.y)
    let lShape = [P2(0, 0), P2(8, 0), P2(8, 3), P2(4, 3), P2(4, 6), P2(0, 6)]
    let result = segments([(start, end)], outline: lShape)
    assertClosure(result, .cone, 0.5)
    XCTAssertEqual(result.segments.last?.b, corner)
  }

  func testAnOvershootingWallIsCutBackToTheCrossing() {
    let result = segments([(P2(0, 5), P2(10, 5)), (P2(3, 0), P2(3, 5.4))])
    XCTAssertEqual(result.overshootsTrimmed, 1)
    let piece = result.segments.first { $0.kind == .wall && $0.wall == 1 }
    XCTAssertEqual(piece?.b.y ?? 0, 5, accuracy: 1e-9)
    XCTAssertTrue(result.dangling.isEmpty)
  }

  func testANearDuplicateWallIsDroppedAndTheLongerExtended() {
    let result = segments([(P2(0, 5), P2(6, 5)), (P2(3, 5.03), P2(7.5, 5.03))])
    XCTAssertEqual(result.duplicatesMerged, 1)
    let pieces = result.segments.filter { $0.kind == .wall }
    XCTAssertEqual(pieces.count, 1)
    XCTAssertEqual(pieces.first?.wall, 0)
    XCTAssertEqual(pieces.first?.b.x ?? 0, 7.5, accuracy: 1e-9)
  }

  func testWallsAlongTheOutlineAreLeftOutOfTheArrangement() {
    let result = segments([(P2(0.1, 0.05), P2(9.9, 0.05)), (P2(5, 0), P2(5, 10))])
    XCTAssertEqual(result.outlineWalls, [0])
    XCTAssertEqual(result.interiorWalls, [1])
  }

  // MARK: Seeds

  /// An 8 x 5 m rectangle split by a wall at x = 5.
  private func twoFaces() -> WalkthroughBuilder {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.rectangle)
    builder.addWall((5, 0), (5, 5))
    return builder
  }

  func testASectionJustOutsideTheFloorIsMovedIn() throws {
    var builder = twoFaces()
    builder.addSection("livingRoom", at: (2, 2.5))
    builder.addSection("bedroom", at: (6.5, 5.3))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(diagnostics.sectionsSnapped, [1])
    XCTAssertEqual(Walkthrough.summary(split), ["Living Room 25.00", "Bedroom 15.00"])
  }

  func testAKitchenSectionMovesToItsAppliances() throws {
    var builder = twoFaces()
    builder.addSection("livingRoom", at: (2, 2.5))
    // RoomPlan placed the kitchen centre 0.5 m inside the living room.
    builder.addSection("kitchen", at: (4.5, 2.5))
    builder.addObject("stove", at: (6.5, 4))
    builder.addObject("refrigerator", at: (6.5, 1))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(diagnostics.sectionsRelocated, [1])
    XCTAssertEqual(Walkthrough.summary(split), ["Living Room 25.00", "Kitchen 15.00"])
    XCTAssertEqual(
      split?.rooms.map(\.typing), [.typed(.livingRoom, .roomplanSection), .typed(.kitchen, .roomplanSection)])
  }

  func testKitchenObjectSeeds() throws {
    func seeds(_ change: (inout WalkthroughBuilder) -> Void) throws -> Int {
      var builder = WalkthroughBuilder(outline: [(0, 0), (10, 0), (10, 5), (0, 5)])
      builder.addSection("livingRoom", at: (2, 2.5))
      builder.addSection("unidentified", at: (5, 2.5))
      change(&builder)
      return try Walkthrough.analyze(builder.document).diagnostics.objectSeeds
    }
    XCTAssertEqual(
      try seeds {
        $0.addObject("stove", at: (8.5, 4))
        $0.addObject("refrigerator", at: (8.5, 1))
      }, 1, "two kinds of appliance, 3.5 m from the nearest section")
    XCTAssertEqual(try seeds { $0.addObject("refrigerator", at: (8.5, 1)) }, 0, "a single refrigerator")
    XCTAssertEqual(
      try seeds {
        $0.addObject("refrigerator", at: (8.5, 1))
        $0.addObject("refrigerator", at: (8.5, 4))
      }, 0, "one kind of appliance")
    XCTAssertEqual(
      try seeds {
        $0.addObject("stove", at: (8.5, 4))
        $0.addObject("refrigerator", at: (8.5, 1))
        $0.sections[1].center = Vector3(7, 0, 2.5)
      }, 0, "within 2 m of a section")
    XCTAssertEqual(
      try seeds {
        $0.addObject("stove", at: (8.5, 4))
        $0.addObject("refrigerator", at: (8.5, 1))
        $0.sections[1] = RoomPlanSection(label: "kitchen", story: 0, center: Vector3(5, 0, 2.5))
      }, 0, "a kitchen section")
  }

  // MARK: Cuts

  func testAnLShapeIsCutAtItsReflexCorner() throws {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape)
    builder.addSection("livingRoom", at: (2, 3))
    builder.addSection("kitchen", at: (6, 1.5))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(Walkthrough.summary(split), ["Living Room 24.00", "Kitchen 12.00"])
    let cut = try XCTUnwrap(diagnostics.cuts.first)
    XCTAssertEqual(diagnostics.cuts.count, 1)
    XCTAssertEqual(cut.tag, "reflex-ray")
    XCTAssertEqual(cut.virtualLengthM, 3, accuracy: 1e-9)
    XCTAssertEqual(try XCTUnwrap(cut.margin), 4, accuracy: 1e-9)
    XCTAssertFalse(cut.approximate)
    XCTAssertEqual(split?.rooms.map(\.heightM), [2.49, 2.49])
  }

  func testACutNeverCrossesAStove() throws {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape)
    builder.addSection("livingRoom", at: (2, 3))
    builder.addSection("kitchen", at: (6, 1.5))
    // On the 3 m ray from the reflex corner down to the outline.
    builder.addObject("stove", at: (4, 1.5))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    let cut = try XCTUnwrap(diagnostics.cuts.first)
    XCTAssertNotEqual(cut.virtualLengthM, 3, accuracy: 1e-6)
    let stove = Vector3(4, 0, 1.5)
    let kitchen = try XCTUnwrap(split?.rooms.first { $0.typing.type == .kitchen })
    XCTAssertTrue(PolygonMath.contains(kitchen.polygon, stove))
  }

  // MARK: Rooms without a section

  func testASmallEnclosedFaceBecomesACloset() throws {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape)
    builder.addWall((0, 4.6), (1.2, 4.6))
    builder.addWall((1.6, 4.6), (1.6, 6))
    builder.addSection("bedroom", at: (2, 3))
    builder.addSection("unidentified", at: (6, 1.5))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(Walkthrough.summary(split), ["Bedroom 21.76", "Room 2 12.00", "Closet 2.24"])
    XCTAssertEqual(split?.rooms.last?.typing, .typed(.closet, .inferred))
    // The 0.4 m between the two walls is closed along the first wall; the end of the second has
    // nothing ahead of it within 0.6 m, and the first closure reaches it.
    XCTAssertEqual(diagnostics.dangling.map(\.method), [.ray, .unclosed])
    XCTAssertEqual(diagnostics.dangling.first?.gapM ?? 0, 0.4, accuracy: 1e-9)
  }

  func testAnEnclosedRoomWithoutSectionOrObjectsIsKeptUntyped() throws {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.rectangle)
    builder.addWall((4, 0), (4, 5))
    builder.addWall((6, 0), (6, 1.75))
    builder.addWall((6, 1.75), (8, 1.75))
    builder.addSection("livingRoom", at: (2, 2.5))
    builder.addSection("bedroom", at: (5, 3.5))
    let split = try XCTUnwrap(try Walkthrough.split(builder.document))
    XCTAssertEqual(Walkthrough.summary(split), ["Living Room 20.00", "Bedroom 16.50", "Room 3 3.50"])
    XCTAssertEqual(split.rooms[2].typing, .unknown)
  }

  func testASliverWithoutASectionMerges() throws {
    var builder = twoFaces()
    builder.addSection("livingRoom", at: (2.5, 2.5))
    builder.addSection("bedroom", at: (6.5, 2.5))
    // Cuts a 0.3 m2 triangle off the corner.
    builder.addWall((0, 0.5), (1.2, 0))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(Walkthrough.summary(split), ["Living Room 25.00", "Bedroom 15.00"])
    XCTAssertEqual(diagnostics.merges.map(\.kind), [.sliver])
    XCTAssertEqual(diagnostics.merges.first?.areaM2 ?? 0, 0.3, accuracy: 1e-9)
    XCTAssertEqual(split?.rooms.first?.polygon.count, 4, "the merged corner is simplified away")
  }

  func testAFaceThatIsMostlyCutsMergesIntoItsLongestVirtualNeighbour() {
    // A 6 x 3 m outline; a cut at x = 1 makes a 3 m2 face with 3 of its 8 m of boundary virtual.
    let outline = [P2(0, 0), P2(6, 0), P2(6, 3), P2(0, 3)]
    var segments = outline.indices.map {
      PlanSegment(a: outline[$0], b: outline[($0 + 1) % 4], kind: .outline, fixed: true)
    }
    segments.append(PlanSegment(a: P2(1, 0), b: P2(1, 3), kind: .cut))
    segments.append(PlanSegment(a: P2(1, 1), b: P2(6, 1), kind: .wall, wall: 0))
    let arr = PlanArrangement(segments: segments, eps: 0.05, boundary: outline)
    XCTAssertEqual(arr.faces.count, 3)
    let top = try! XCTUnwrap(arr.faceContaining(P2(3, 2)))
    let bottom = try! XCTUnwrap(arr.faceContaining(P2(3, 0.5)))
    let strip = try! XCTUnwrap(arr.faceContaining(P2(0.5, 1.5)))
    var rooms = WalkthroughRooms(arrangement: arr)
    var diagnostics = WalkthroughSplitter.Diagnostics()
    let plan = WalkthroughInput.Plan(outline: outline, floorY: 0, walls: [], sections: [], objects: [])
    rooms.resolve(seedFaces: [top, bottom], plan: plan, parameters: .init(), diagnostics: &diagnostics)
    XCTAssertEqual(diagnostics.merges.map(\.kind), [.sectionless])
    XCTAssertEqual(diagnostics.merges.first?.virtualFraction ?? 0, 0.375, accuracy: 1e-12)
    XCTAssertEqual(rooms.find(strip), rooms.find(top), "2 m shared with the top, 1 m with the bottom")
    XCTAssertNotEqual(rooms.find(strip), rooms.find(bottom))
  }

  // MARK: Heights

  private func lShapeWithWalls(heights: [Double]) -> WalkthroughBuilder {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape, wallsAlongOutline: false)
    // Walls only around the living-room wing; the kitchen wing has outline without walls.
    let walls: [((Double, Double), (Double, Double))] = [
      ((0, 6), (0, 0)), ((0, 0), (4, 0)), ((4, 3), (4, 6)), ((4, 6), (0, 6)),
    ]
    for (wall, height) in zip(walls, heights) { builder.addWall(wall.0, wall.1, height: height) }
    builder.addSection("livingRoom", at: (2, 3))
    builder.addSection("kitchen", at: (6, 1.5))
    return builder
  }

  func testARoomWithoutWallsGetsTheMedianWallHeight() throws {
    // Lengths 6, 4, 3 and 4 m: half the 17 m is reached at the 2.55 m wall.
    let split = try XCTUnwrap(try Walkthrough.split(lShapeWithWalls(heights: [2.55, 2.5, 2.6, 2.7]).document))
    XCTAssertEqual(Walkthrough.labels(split), ["Living Room", "Kitchen"])
    XCTAssertEqual(split.rooms.map(\.heightM), [2.7, 2.55])
    XCTAssertEqual(split.rooms.map(\.heightFromWalls), [true, false])
  }

  func testHeightsOutsideTheRangeAreClamped() throws {
    let low = try XCTUnwrap(try Walkthrough.split(lShapeWithWalls(heights: [1.2, 1.2, 1.2, 1.2]).document))
    XCTAssertEqual(low.rooms.map(\.heightM), [2.0, 2.0])
    let high = try XCTUnwrap(try Walkthrough.split(lShapeWithWalls(heights: [7, 7, 7, 7]).document))
    XCTAssertEqual(high.rooms.map(\.heightM), [6.0, 6.0])
    XCTAssertEqual(high.rooms.map(\.heightFromWalls), [false, false])
  }

  // MARK: Objects

  func testObjectsGoToTheRoomTheyStandIn() throws {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape)
    builder.addSection("livingRoom", at: (2, 3))
    builder.addSection("kitchen", at: (6, 1.5))
    let table = builder.addObject("table", at: (6, 2))
    builder.addObject("chair", at: (2, 5), parent: table)
    // Centre just outside the floor; the footprint lies mostly under the kitchen.
    builder.addObject("storage", at: (4.3, -0.05), size: (1.2, 0.9, 1.0))
    // Outside the floor altogether, nearest the kitchen.
    builder.addObject("television", at: (10, 1.5))
    // A cycle of parents keeps each object's own room.
    let a = builder.addObject("storage", at: (1, 1), parent: "OBJECT-0006")
    builder.addObject("sink", at: (7, 1), parent: a)
    let model = try CaptureModelMapper.map(builder.document, context: try Walkthrough.context())
    XCTAssertEqual(model.rooms.map(\.label), ["Living Room", "Kitchen"])
    XCTAssertEqual(
      model.objects.map { $0.roomId ?? "" }, ["room-2", "room-2", "room-2", "room-2", "room-1", "room-2"])
  }

  // MARK: Determinism and robustness (the fixture)

  private func fixtureDocument() throws -> RoomPlanDocument {
    try RoomPlanDocument.decode(from: Fixtures.roomPlanOnly("apartment-walkthrough").roomPlanData())
  }

  private static let fixtureRooms = [
    "Bedroom 1 12.21", "Kitchen 14.10", "Living Room 28.54", "Hallway 4.48", "Bathroom 4.51", "Bedroom 2 12.24",
    "Closet 2.05",
  ]

  private func types(_ split: WalkthroughSplitter.Split?) -> [String] {
    (split?.rooms ?? []).map { $0.typing.type?.rawValue ?? "none" }.sorted()
  }

  func testTheSameCaptureGivesTheSameBytes() throws {
    let document = try fixtureDocument()
    let encoder = CaptureContractJSON.makeEncoder()
    let first = try encoder.encode(try CaptureModelMapper.map(document, context: try Walkthrough.context()))
    let second = try encoder.encode(try CaptureModelMapper.map(document, context: try Walkthrough.context()))
    XCTAssertEqual(first, second)
  }

  func testOrderAndPlacementOfTheCaptureDoNotMatter() throws {
    let document = try fixtureDocument()
    let base = try XCTUnwrap(try Walkthrough.split(document))
    let baseLabels = Walkthrough.labels(base)
    func assertSame(_ other: RoomPlanDocument, _ name: String) throws {
      let split = try XCTUnwrap(try Walkthrough.split(other), name)
      XCTAssertEqual(Walkthrough.labels(split), baseLabels, name)
      for (a, b) in zip(split.rooms, base.rooms) { XCTAssertEqual(a.areaM2, b.areaM2, accuracy: 1e-6, name) }
    }
    for seed in UInt64(1)...4 { try assertSame(Walkthrough.shuffled(document, seed: seed), "shuffle \(seed)") }
    for (theta, tx, tz) in [(0.3, 1.0, -2.0), (1.2, -5.0, 3.0), (2.5, 0.0, 0.0), (-0.7, 10.0, 10.0)] {
      let moved = Walkthrough.moved(document, theta: theta, tx: tx, tz: tz)
      try assertSame(moved, "moved \(theta)")
      // The rooms are the same rooms, moved.
      let split = try XCTUnwrap(try Walkthrough.split(moved))
      let c = cos(theta)
      let s = sin(theta)
      for (room, original) in zip(split.rooms, base.rooms) {
        let undone = room.polygon.map { p -> Vector3 in
          let x = p.x - tx
          let z = p.z - tz
          return Vector3(c * x - s * z, p.y, s * x + c * z)
        }
        XCTAssertLessThan(Walkthrough.hausdorff(undone, original.polygon), 1e-6, "moved \(theta)")
      }
    }
  }

  func testWallEndsMovedByUpToFiveCentimetres() throws {
    let document = try fixtureDocument()
    let expected = types(try Walkthrough.split(document))
    for seed in UInt64(0)..<40 {
      let split = try Walkthrough.split(Walkthrough.jitter(document, sigma: 0.05, seed: 5000 + seed))
      XCTAssertEqual(split?.rooms.count, 7, "seed \(seed)")
      XCTAssertEqual(types(split), expected, "seed \(seed)")
    }
  }

  func testWallsShortenedOrLengthened() throws {
    let document = try fixtureDocument()
    let expected = types(try Walkthrough.split(document))
    for cut in [0.1, 0.2, 0.4] {
      var shortened = document
      for i in shortened.rooms[0].walls.indices {
        shortened.rooms[0].walls[i].dimensions[0] = max(0.1, shortened.rooms[0].walls[i].dimensions[0] - cut)
      }
      let split = try Walkthrough.split(shortened)
      XCTAssertEqual(split?.rooms.count, 7, "shortened \(cut)")
      XCTAssertEqual(types(split), expected, "shortened \(cut)")
    }
    // Interior walls 0.8 m too long: trimmed back, the same rooms.
    let interior = Set(
      try Fixtures.roomPlanOnly("apartment-walkthrough").expected.walls.filter { $0.kind == "interior" }.map(
        \.identifier))
    var longer = document
    for i in longer.rooms[0].walls.indices where interior.contains(longer.rooms[0].walls[i].identifier) {
      longer.rooms[0].walls[i].dimensions[0] += 0.8
    }
    XCTAssertEqual(Walkthrough.summary(try Walkthrough.split(longer)), Self.fixtureRooms)
    // Interior walls doubled 3 cm apart: merged, the same rooms.
    var doubled = document
    for wall in document.rooms[0].walls where interior.contains(wall.identifier) {
      var copy = wall
      copy.identifier = wall.identifier + "-COPY"
      copy.transform.columns[3][0] += -wall.transform.columns[0][2] * 0.03
      copy.transform.columns[3][2] += wall.transform.columns[0][0] * 0.03
      doubled.rooms[0].walls.append(copy)
    }
    let (split, diagnostics) = try Walkthrough.analyze(doubled)
    XCTAssertEqual(Walkthrough.summary(split), Self.fixtureRooms)
    XCTAssertGreaterThanOrEqual(diagnostics.duplicatesMerged, interior.count)
  }

  func testWeldToleranceDoesNotChangeTheRooms() throws {
    let document = try fixtureDocument()
    for eps in [0.01, 0.03, 0.05, 0.08, 0.10] {
      var parameters = WalkthroughSplitter.Parameters()
      parameters.eps = eps
      XCTAssertEqual(Walkthrough.summary(try Walkthrough.split(document, parameters)), Self.fixtureRooms, "eps \(eps)")
    }
  }

  func testDroppingAnyOneWall() throws {
    let document = try fixtureDocument()
    var lost: [Int] = []
    for (index, wall) in document.rooms[0].walls.enumerated() {
      let split = try Walkthrough.split(Walkthrough.dropping(document, wall: wall.identifier))
      if Walkthrough.summary(split) == Self.fixtureRooms { continue }
      lost.append(index)
      // Without one of the closet's walls the closet merges into a neighbour; nothing else changes.
      XCTAssertEqual(split?.rooms.count, 6, "wall \(index)")
      XCTAssertFalse(types(split).contains("closet"), "wall \(index)")
    }
    XCTAssertEqual(lost, [11, 17, 23])
  }

  func testOddCapturesOfTheFixture() throws {
    let document = try fixtureDocument()
    // A column (a small closed loop of walls) in the living room is ignored.
    var column = WalkthroughBuilder(outline: [], wallsAlongOutline: false)
    for (a, b) in [
      ((-1.2, 0.3), (-0.6, 0.3)), ((-0.6, 0.3), (-0.6, 0.9)), ((-0.6, 0.9), (-1.2, 0.9)), ((-1.2, 0.9), (-1.2, 0.3)),
    ] {
      column.addWall(a, b)
    }
    var withColumn = document
    withColumn.rooms[0].walls += column.walls
    XCTAssertEqual(Walkthrough.summary(try Walkthrough.split(withColumn)), Self.fixtureRooms, "column")

    // A section 6 m outside the floor is ignored; the hall still becomes a room of its own.
    var outside = document
    let hall = try XCTUnwrap(outside.rooms[0].sections[3].center)
    outside.rooms[0].sections[3].center = Vector3(hall.x, hall.y, hall.z - 6)
    let (split, diagnostics) = try Walkthrough.analyze(outside)
    XCTAssertEqual(diagnostics.sectionsIgnored, [3])
    XCTAssertEqual(Walkthrough.summary(split).sorted(), Self.fixtureRooms.sorted())

    // Openings without a parent wall find the same wall pieces.
    var noParents = document
    for i in noParents.rooms[0].doors.indices { noParents.rooms[0].doors[i].parentIdentifier = nil }
    for i in noParents.rooms[0].windows.indices { noParents.rooms[0].windows[i].parentIdentifier = nil }
    for i in noParents.rooms[0].openings.indices { noParents.rooms[0].openings[i].parentIdentifier = nil }
    let context = try Walkthrough.context()
    let a = try CaptureModelMapper.map(document, context: context)
    let b = try CaptureModelMapper.map(noParents, context: context)
    XCTAssertEqual((b.doors + b.windows + b.openings).map(\.wallId), (a.doors + a.windows + a.openings).map(\.wallId))
  }
}
