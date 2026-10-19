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

  func testAWallEndOnTheTipOfAClosureStaysWhereItIs() {
    // W runs 3 cm past the line of V; V stops 10 cm short of W and is joined to it at J = (3, 2),
    // at right angles. W's free end then lies on the line of that closure, exactly at its tip
    // (t = 1), 3 cm from J. Whether it moves onto J must not depend on rounding, so it must not
    // depend on where the capture lies: in every frame the end stays and the faces are the same.
    let outline = [P2(0, 0), P2(6, 0), P2(6, 4), P2(0, 4)]
    let w = (P2(0, 2), P2(3.03, 2))
    let v = (P2(3, 4), P2(3, 2.1))
    var areas: [Double]?
    for k in 0..<400 {
      let theta = Double(k) * 0.0157 - 3.1
      let c = cos(theta)
      let s = sin(theta)
      let tx = Double(k % 17) * 0.731 - 5
      let ty = Double(k % 13) * 1.37 - 8
      func forward(_ p: P2) -> P2 { P2(c * p.x - s * p.y + tx, s * p.x + c * p.y + ty) }
      func back(_ p: P2) -> P2 { P2(c * (p.x - tx) + s * (p.y - ty), -s * (p.x - tx) + c * (p.y - ty)) }
      let moved = outline.map(forward)
      let result = segments([(forward(w.0), forward(w.1)), (forward(v.0), forward(v.1))], outline: moved)
      let piece = result.segments.first { $0.kind == .wall && $0.wall == 0 }
      XCTAssertEqual(Plan2D.dist(back(piece?.b ?? P2(0, 0)), w.1), 0, accuracy: 1e-9, "frame \(k)")
      let arr = PlanArrangement(segments: result.segments, eps: 0.05, boundary: moved)
      let faceAreas = arr.faces.indices.map { Plan2D.area(arr.polygon($0)) }.sorted()
      if let areas {
        XCTAssertEqual(faceAreas.count, areas.count, "frame \(k)")
        for (a, b) in zip(faceAreas, areas) { XCTAssertEqual(a, b, accuracy: 1e-9, "frame \(k)") }
      } else {
        areas = faceAreas
      }
    }
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

  func testACutAlongTheWallsBeatsAShorterDiagonal() throws {
    // Two rectangles that overlap at a corner. The 1.41 m diagonal between their reflex corners
    // costs 1.41 x (1 + 4 x (sin 45 - sin 1)) = 5.31; the 3 m ray down from (3, 3) costs 3.
    var builder = WalkthroughBuilder(outline: [(0, 0), (4, 0), (4, 2), (7, 2), (7, 6), (3, 6), (3, 3), (0, 3)])
    builder.addSection("livingRoom", at: (1, 1))
    builder.addSection("bedroom", at: (6, 5))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(diagnostics.cuts.map(\.tag), ["reflex-ray"])
    XCTAssertEqual(diagnostics.cuts.first?.virtualLengthM ?? 0, 3, accuracy: 1e-9)
    XCTAssertEqual(diagnostics.cuts.first?.score ?? 0, 3, accuracy: 1e-9)
    XCTAssertEqual(Walkthrough.summary(split), ["Living Room 9.00", "Bedroom 18.00"])
  }

  func testACutAlongAWallStubBeatsAShorterOneAcrossOpenFloor() throws {
    // Two rooms joined by a 1 x 1.5 m passage. Extending the 3 m stub costs 2 m of cut less half
    // of the 3 m of wall it follows (0.5); across the passage costs 1.5.
    var builder = WalkthroughBuilder(outline: [(0, 0), (9, 0), (9, 5), (6, 5), (6, 1.5), (5, 1.5), (5, 5), (0, 5)])
    builder.addWall((2.5, 0), (2.5, 3))
    builder.addSection("livingRoom", at: (1.2, 2.5))
    builder.addSection("bedroom", at: (7.5, 2.5))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(diagnostics.cuts.map(\.tag), ["stub-extend"])
    let cut = try XCTUnwrap(diagnostics.cuts.first)
    XCTAssertEqual(cut.virtualLengthM, 2, accuracy: 1e-9)
    XCTAssertEqual(cut.wallLengthM, 3, accuracy: 1e-9)
    XCTAssertEqual(cut.score, 0.5, accuracy: 1e-9)
    XCTAssertEqual(Walkthrough.summary(split), ["Living Room 12.50", "Bedroom 29.00"])
  }

  func testAStubIsContinuedThroughALooseWallInLineWithIt() throws {
    // A stub from the floor edge stops 1.4 m short of a loose piece of wall in line with it. The
    // cut bridges the gap, follows the loose piece and goes on to the far edge: 2.6 m of cut along
    // 2.4 m of wall. Extending the stub alone costs 3.8 m of cut along 1.2 m.
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.rectangle)
    builder.addWall((4, 0), (4, 1.2))
    builder.addWall((4, 2.6), (4, 3.8))
    builder.addSection("livingRoom", at: (2, 2.5))
    builder.addSection("bedroom", at: (6, 2.5))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(diagnostics.cuts.map(\.tag), ["chain-extend"])
    let cut = try XCTUnwrap(diagnostics.cuts.first)
    XCTAssertEqual(cut.virtualLengthM, 2.6, accuracy: 1e-9)
    XCTAssertEqual(cut.wallLengthM, 2.4, accuracy: 1e-9)
    XCTAssertEqual(Walkthrough.summary(split), ["Living Room 20.00", "Bedroom 20.00"])
  }

  // MARK: Limits and fallbacks

  func testOnlyAShortClosureEnclosesARoomWithoutASection() throws {
    // A wall at x = 3 parts the bedroom from the living room; a stub at x = 6 stops `gap` short of
    // the far edge. Closing the gap would make a 10 m2 room without a section, which only a
    // closure of at most 1.2 m may do.
    func split(gap: Double) throws -> (summary: [String], enclosures: Int) {
      var builder = WalkthroughBuilder(outline: WalkthroughBuilder.rectangle)
      builder.addWall((3, 0), (3, 5))
      builder.addWall((6, 0), (6, 5 - gap))
      builder.addSection("bedroom", at: (1.5, 2.5))
      builder.addSection("livingRoom", at: (4.5, 2.5))
      let (split, diagnostics) = try Walkthrough.analyze(builder.document)
      return (Walkthrough.summary(split), diagnostics.enclosures.count)
    }
    let short = try split(gap: 1.1)
    XCTAssertEqual(short.summary, ["Bedroom 15.00", "Living Room 15.00", "Room 3 10.00"])
    XCTAssertEqual(short.enclosures, 1)
    let long = try split(gap: 1.3)
    XCTAssertEqual(long.summary, ["Bedroom 15.00", "Living Room 25.00"])
    XCTAssertEqual(long.enclosures, 0)
  }

  func testAClosureThatWouldBeMostOfARoomsBoundaryEnclosesNothing() throws {
    // In the corner of the living room a 0.1 m stub from the right edge points at a stub from the
    // bottom edge 1.1 m away. Closing it cuts off a 1.2 m wide alcove `depth` deep; at 0.9 m the
    // 1.1 m closure is 26 % of the alcove's boundary (more than 25 %), at 1.2 m it is 23 %.
    func split(depth: Double) throws -> (summary: [String], enclosures: Int) {
      var builder = WalkthroughBuilder(outline: WalkthroughBuilder.rectangle)
      builder.addWall((3, 0), (3, 5))
      builder.addWall((8, depth), (7.9, depth))
      builder.addWall((6.8, 0), (6.8, 1.5))
      builder.addSection("bedroom", at: (1.5, 2.5))
      builder.addSection("livingRoom", at: (4.5, 2.5))
      let (split, diagnostics) = try Walkthrough.analyze(builder.document)
      return (Walkthrough.summary(split), diagnostics.enclosures.count)
    }
    let deep = try split(depth: 1.2)
    XCTAssertEqual(deep.summary, ["Bedroom 15.00", "Living Room 23.56", "Closet 1.44"])
    XCTAssertEqual(deep.enclosures, 1)
    let shallow = try split(depth: 0.9)
    XCTAssertEqual(shallow.summary, ["Bedroom 15.00", "Living Room 25.00"])
    XCTAssertEqual(shallow.enclosures, 0)
  }

  func testAKitchenSectionMovesOnlyToAppliancesWithinOneMetre() throws {
    func relocated(sectionAt x: Double) throws -> [Int] {
      var builder = twoFaces()
      builder.addSection("livingRoom", at: (2, 2.5))
      builder.addSection("kitchen", at: (x, 2.5))
      builder.addObject("stove", at: (6.5, 4))
      builder.addObject("refrigerator", at: (6.5, 1))
      return try Walkthrough.analyze(builder.document).diagnostics.sectionsRelocated
    }
    XCTAssertEqual(try relocated(sectionAt: 4.1), [1], "0.9 m from the appliances' face")
    XCTAssertEqual(try relocated(sectionAt: 3.8), [], "1.2 m from it")
  }

  func testAnArrangementThatFailsItsCheckIsBuiltAgainWithHalfTheWeld() throws {
    // Four walls fan out to the right, a few degrees apart, from ends within 13 cm of each other.
    // Welded at 5 cm they leave a face of no area, so the faces fail their check; welded at
    // 2.5 cm they do not.
    var builder = WalkthroughBuilder(outline: [(0, 0), (6, 0), (6, 4), (0, 4)])
    builder.addWall((2.9745, 2.4997), (5.5528, 2.4678))
    builder.addWall((3.0516, 2.5160), (5.1349, 2.1329))
    builder.addWall((3.1037, 2.5384), (6.0498, 2.1366))
    builder.addWall((2.9789, 2.4791), (5.8530, 2.3150))
    builder.addSection("livingRoom", at: (3, 1))
    builder.addSection("bedroom", at: (3, 3.5))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(diagnostics.eps, 0.025)
    XCTAssertNil(diagnostics.fallbackReason)
    XCTAssertEqual(split.map { Walkthrough.labels($0) }, ["Living Room", "Bedroom"])
  }

  func testARoomThatWouldTouchItselfFallsBackToOneRoom() throws {
    // A 2 m2 diamond of walls touches the floor edge at one point. The room around it would pass
    // through that point twice, which a contract polygon cannot; the capture maps as one room.
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.rectangle)
    builder.addWall((4, 0), (5, 1))
    builder.addWall((5, 1), (4, 2))
    builder.addWall((4, 2), (3, 1))
    builder.addWall((3, 1), (4, 0))
    builder.addSection("livingRoom", at: (1, 4))
    builder.addSection("bathroom", at: (4, 1))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertNil(split)
    XCTAssertEqual(diagnostics.fallbackReason, .validation)
    let context = try Walkthrough.context()
    let model = try CaptureModelMapper.map(builder.document, context: context)
    XCTAssertEqual(model.rooms.count, 1)
    XCTAssertEqual(
      model,
      try CaptureModelMapper.map(RoomPlanDocument(rooms: builder.document.rooms, isStructure: true), context: context))
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

  func testAFaceThatIsMostlyCutsIsKeptWhenItHoldsAToilet() {
    // The face of the test above, with a toilet in the strip: a second bathroom without a section
    // whose open door makes much of its boundary virtual.
    let outline = [P2(0, 0), P2(6, 0), P2(6, 3), P2(0, 3)]
    var segments = outline.indices.map {
      PlanSegment(a: outline[$0], b: outline[($0 + 1) % 4], kind: .outline, fixed: true)
    }
    segments.append(PlanSegment(a: P2(1, 0), b: P2(1, 3), kind: .cut))
    segments.append(PlanSegment(a: P2(1, 1), b: P2(6, 1), kind: .wall, wall: 0))
    let arr = PlanArrangement(segments: segments, eps: 0.05, boundary: outline)
    let top = try! XCTUnwrap(arr.faceContaining(P2(3, 2)))
    let bottom = try! XCTUnwrap(arr.faceContaining(P2(3, 0.5)))
    let strip = try! XCTUnwrap(arr.faceContaining(P2(0.5, 1.5)))
    var rooms = WalkthroughRooms(arrangement: arr)
    var diagnostics = WalkthroughSplitter.Diagnostics()
    let toilet = WalkthroughInput.Object(
      index: 0, identifier: "OBJECT-0001", parentIdentifier: nil, category: .toilet, center: P2(0.5, 1.5),
      center3: Vector3(0.5, 0, 1.5), axis: P2(1, 0), width: 0.4, depth: 0.7)
    let plan = WalkthroughInput.Plan(outline: outline, floorY: 0, walls: [], sections: [], objects: [toilet])
    rooms.resolve(seedFaces: [top, bottom], plan: plan, parameters: .init(), diagnostics: &diagnostics)
    XCTAssertEqual(diagnostics.merges.map(\.kind), [])
    XCTAssertEqual(rooms.find(strip), strip)
    XCTAssertEqual(rooms.roots().count, 3)
  }

  // MARK: Walls and openings

  func testADoorOnTheSecondPieceOfASplitWall() throws {
    // The L is cut at x = 4, which splits the bottom wall into wall-1 (living room, 0 to 4 m) and
    // wall-2 (kitchen, 4 to 8 m).
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape)
    builder.addSection("livingRoom", at: (2, 3))
    builder.addSection("kitchen", at: (6, 1.5))
    builder.addDoor(at: (6, 0), inWall: 0)
    builder.addDoor(at: (1, 0), inWall: 0)
    // Its centre lies past the end of the wall RoomPlan put it in: the last piece, offset from its
    // start as for a wall that is not split.
    builder.addDoor(at: (8.3, 0), inWall: 0)
    let model = try CaptureModelMapper.map(builder.document, context: try Walkthrough.context())
    XCTAssertEqual(model.rooms.map(\.label), ["Living Room", "Kitchen"])
    XCTAssertEqual(model.walls.prefix(2).map(\.roomIds), [["room-1"], ["room-2"]])
    XCTAssertEqual(model.doors.map(\.wallId), ["wall-2", "wall-1", "wall-2"])
    XCTAssertEqual(model.doors[0].offsetM, 2.0, accuracy: 1e-9)
    XCTAssertEqual(model.doors[1].offsetM, 1.0, accuracy: 1e-9)
    XCTAssertEqual(model.doors[2].offsetM, 4.3, accuracy: 1e-9)
  }

  func testARoomCornerNearAWallEndLeavesNoShortWallPiece() throws {
    // The bottom of the L is drawn as two walls that meet 0.1 m past the corner where the living
    // room and the kitchen meet. That 0.1 m stays with the living-room piece of the first wall.
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape, wallsAlongOutline: false)
    let walls: [((Double, Double), (Double, Double))] = [
      ((0, 0), (4.1, 0)), ((4.1, 0), (8, 0)), ((8, 0), (8, 3)), ((8, 3), (4, 3)), ((4, 3), (4, 6)), ((4, 6), (0, 6)),
      ((0, 6), (0, 0)),
    ]
    for wall in walls { builder.addWall(wall.0, wall.1) }
    builder.addSection("livingRoom", at: (2, 3))
    builder.addSection("kitchen", at: (6, 1.5))
    let split = try XCTUnwrap(try Walkthrough.split(builder.document))
    XCTAssertEqual(Walkthrough.summary(split), ["Living Room 24.00", "Kitchen 12.00"])
    XCTAssertEqual(split.wallPieces.map(\.sourceWall), Array(0...6))
    XCTAssertEqual(split.wallPieces.map(\.rooms), [[0], [1], [1], [1], [0], [0], [0]])
    XCTAssertTrue(split.wallPieces.allSatisfy { $0.endM - $0.startM >= 0.15 })
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

  func testHeightsAreKeptAsMeasured() throws {
    // Implausible heights stay as the walls measured them, so the station can flag them; a room
    // without walls gets the median as it is.
    let low = try XCTUnwrap(try Walkthrough.split(lShapeWithWalls(heights: [1.2, 1.2, 1.2, 1.2]).document))
    XCTAssertEqual(low.rooms.map(\.heightM), [1.2, 1.2])
    XCTAssertEqual(low.rooms.map(\.heightFromWalls), [true, false])
    let high = try XCTUnwrap(try Walkthrough.split(lShapeWithWalls(heights: [7, 7, 7, 7]).document))
    XCTAssertEqual(high.rooms.map(\.heightM), [7.0, 7.0])
    XCTAssertEqual(high.rooms.map(\.heightFromWalls), [true, false])
    // One tall wall: the room it bounds is as high as it, as when the capture is not split.
    let oneTall = try XCTUnwrap(try Walkthrough.split(lShapeWithWalls(heights: [2.5, 2.5, 6.4, 2.5]).document))
    XCTAssertEqual(oneTall.rooms.map(\.heightM), [6.4, 2.5])
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

  func testAnObjectOutsideTheFloorGoesToTheRoomItOverlapsMost() throws {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape)
    builder.addSection("livingRoom", at: (2, 3))
    builder.addSection("kitchen", at: (6, 1.5))
    // Centre in the notch of the L, 0.2 m from the kitchen and 0.3 m from the living room; 0.3 m2
    // of the footprint lies over the living room and 0.11 m2 over the kitchen.
    builder.addObject("storage", at: (4.3, 3.2), size: (1.6, 0.9, 0.6))
    let model = try CaptureModelMapper.map(builder.document, context: try Walkthrough.context())
    XCTAssertEqual(model.rooms.map(\.label), ["Living Room", "Kitchen"])
    XCTAssertEqual(model.objects.map { $0.roomId ?? "" }, ["room-1"])
  }

  func testACycleOfThreeParentsKeepsEachObjectsOwnRoom() throws {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape)
    builder.addSection("livingRoom", at: (2, 3))
    builder.addSection("kitchen", at: (6, 1.5))
    // Living room -> kitchen -> kitchen -> living room. Walking 16 parents from the first object
    // without noticing the cycle would stop on the second, in the kitchen.
    builder.addObject("storage", at: (1, 1), parent: "OBJECT-0002")
    builder.addObject("storage", at: (6, 1), parent: "OBJECT-0003")
    builder.addObject("sink", at: (7, 1), parent: "OBJECT-0001")
    let model = try CaptureModelMapper.map(builder.document, context: try Walkthrough.context())
    XCTAssertEqual(model.rooms.map(\.label), ["Living Room", "Kitchen"])
    XCTAssertEqual(model.objects.map { $0.roomId ?? "" }, ["room-1", "room-2", "room-2"])
  }

  // MARK: Ends, overshoots and closures near their tolerances

  func testEndsThatMeetThroughAnotherEndAllMeet() throws {
    // A wall from the left ends at (5, 1.4). The wall from the top stops 3.5 cm to the right of
    // that end, the wall from the bottom 3.5 cm further: each end touches the next, the outer two
    // are 7 cm apart. All three meet, so the hall below the first wall stays closed. Welded one
    // pair at a time, the bottom wall was left 7 cm short of the junction, touching an end and so
    // never closed, and the hall leaked into the bedroom.
    var builder = WalkthroughBuilder(outline: [(0, 0), (10, 0), (10, 6), (0, 6)])
    builder.addWall((0, 1.4), (5, 1.4))
    builder.addWall((5.035, 6), (5.035, 1.4))
    builder.addWall((5.07, 0), (5.07, 1.395))
    builder.addSection("bathroom", at: (2.5, 3.5))
    builder.addSection("bedroom", at: (8, 3))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(Walkthrough.summary(split), ["Bathroom 23.08", "Bedroom 29.87", "Hallway 7.05"])
    XCTAssertEqual(diagnostics.dangling, [])
  }

  func testAnEndBesideAWallNearItsEndJoinsTheJunctionThere() {
    // Three walls from the edges meet near (5, 5). The ends of the two longest are 2.9 cm apart
    // and meet at the end of the longest. The third stops 4 cm beside the second wall, 3.4 cm
    // along it from its end (5.3 cm from that end itself). Moving the second wall's end onto the
    // junction turns the wall away from the third end, which must not be left on its own.
    let result = segments([
      (P2(5.02, 10), P2(5.02, 5.021)), (P2(0.04, 5), P2(5, 5)), (P2(4.966, 0.04), P2(4.966, 4.96)),
    ])
    XCTAssertEqual(result.dangling, [])
    let pieces = result.segments.filter { $0.kind == .wall }
    XCTAssertEqual(pieces.count, 3)
    for piece in pieces { XCTAssertEqual(piece.b, P2(5.02, 5.021), "wall \(piece.wall ?? -1)") }
  }

  func testAShortWallBetweenTwoWallsIsNotTrimmedAway() {
    // A 0.51 m wall runs 1.5 cm past the wall at x = 3 and stops 6 cm short of the wall at
    // x = 3.555. Its far end is no overshoot: trimming it back to the crossing at its near end
    // deleted the whole wall. It stays, and its far end joins the other wall.
    let result = segments([(P2(3, 0), P2(3, 10)), (P2(3.555, 0), P2(3.555, 10)), (P2(2.985, 5), P2(3.495, 5))])
    XCTAssertEqual(result.overshootsTrimmed, 0)
    let piece = result.segments.first { $0.kind == .wall && $0.wall == 2 }
    XCTAssertEqual(piece?.a, P2(3, 5))
    XCTAssertEqual(piece?.b, P2(3.495, 5))
    XCTAssertEqual(result.dangling.map(\.method), [.join])
    XCTAssertEqual(result.dangling.first?.gapM ?? 0, 0.06, accuracy: 1e-9)
  }

  /// Frames for the tests below: turned by up to half a turn either way and moved up to 10 m.
  private static let frames: [(theta: Double, tx: Double, tz: Double)] = (0..<40).map { k in
    let theta: Double = Double(k) * 0.157 - 3.1
    let tx: Double = Double(k % 7) * 3.1 - 9.3
    let tz: Double = Double(k % 11) * 1.9 - 9.5
    return (theta, tx, tz)
  }

  func testAShortWallFromTheOutlineIsKeptInEveryFrame() throws {
    // A 0.497 m wall hangs from the top edge (or runs 1 cm past it, as RoomPlan's walls do) in
    // line with a free wall. Rounding put the crossing with the edge at its own end just inside
    // it in some frames, and the wall was trimmed to nothing there: no cut, one room.
    for past in [0.0, 0.01] {
      var builder = WalkthroughBuilder(outline: [(0, 0), (7.1, 0), (7.1, 10.7), (0, 10.7)])
      builder.addWall((2.1, 7.5), (2.1, 9.25))
      builder.addWall((2.1, 10.203), (2.1, 10.7 + past))
      builder.addSection("kitchen", at: (3.0, 3.9))
      builder.addSection("diningRoom", at: (6.4, 8.4))
      let expected = ["Kitchen 59.97", "Dining Room 16.00"]
      XCTAssertEqual(Walkthrough.summary(try Walkthrough.split(builder.document)), expected, "past \(past)")
      for (k, frame) in Self.frames.enumerated() {
        let moved = Walkthrough.moved(builder.document, theta: frame.theta, tx: frame.tx, tz: frame.tz)
        XCTAssertEqual(Walkthrough.summary(try Walkthrough.split(moved)), expected, "past \(past) frame \(k)")
      }
    }
  }

  func testTheEndsOfADoorwayMakeNoCornerInAnyFrame() throws {
    // Two pieces of one wall with a 0.81 m doorway between them. Their facing ends point at each
    // other, so their rays cross only by rounding; exactly in line (axis-aligned) each made a
    // 0.21 m corner closure, and that enclosed a third room the same capture turned by 1e-9 rad
    // did not have.
    var builder = WalkthroughBuilder(outline: [(0, 0), (7.4, 0), (7.4, 5.8), (0, 5.8)])
    builder.addWall((1.47, 3.15), (1.47, 3.96))
    builder.addWall((1.47, 4.77), (1.47, 5.67))
    builder.addWall((3.38, 3.6), (3.38, 5.3))
    builder.addWall((0, 2.52), (1.53, 2.52))
    builder.addSection("livingRoom", at: (3.05, 1.62))
    builder.addSection("kitchen", at: (5.86, 2.02))
    let expected = ["Living Room 19.60", "Kitchen 23.32"]
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(Walkthrough.summary(split), expected)
    XCTAssertFalse(diagnostics.dangling.contains { $0.method == .corner })
    let barely = Walkthrough.moved(builder.document, theta: 1e-9, tx: 0, tz: 0)
    XCTAssertEqual(Walkthrough.summary(try Walkthrough.split(barely)), expected)
    for (k, frame) in Self.frames.enumerated() {
      let moved = Walkthrough.moved(builder.document, theta: frame.theta, tx: frame.tx, tz: frame.tz)
      XCTAssertEqual(Walkthrough.summary(try Walkthrough.split(moved)), expected, "frame \(k)")
    }
  }

  func testAWallTenBillionKilometresAwayMapsTheCaptureAsOneRoom() throws {
    // Keys rounded to a micrometre trapped for coordinates of 9.2e12 m and more; the capture
    // is not split, and maps as it did before splitting.
    var builder = twoFaces()
    builder.addSection("livingRoom", at: (2, 2.5))
    builder.addSection("bedroom", at: (6.5, 2.5))
    builder.addWall((1e13, 0), (1e13 + 2, 0))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertNil(split)
    XCTAssertEqual(diagnostics.fallbackReason, .notWalkthrough)
    let context = try Walkthrough.context()
    XCTAssertEqual(
      try CaptureModelMapper.map(builder.document, context: context),
      try CaptureModelMapper.map(RoomPlanDocument(rooms: builder.document.rooms, isStructure: true), context: context))
    XCTAssertEqual(WalkthroughCuts.micro(1e13), 9_200_000_000_000_000_000)
    XCTAssertEqual(WalkthroughCuts.micro(-.infinity), -9_200_000_000_000_000_000)
    XCTAssertEqual(WalkthroughCuts.micro(.nan), 0)
    XCTAssertEqual(WalkthroughCuts.micro(-1.25), -1_250_000)
  }

  func testTwoPiecesInLineThatOverlapAreLinkedEndToEnd() {
    // A wall from the top edge and a loose piece in line with it, 5.5 cm to the side, overlap by
    // 6 cm. Each free end would join the other piece, closing a loop of a few centimetres that
    // hides both from the cuts; they are linked end to end instead.
    let result = segments([(P2(5, 10), P2(5, 6.94)), (P2(5.055, 7), P2(5.055, 5))])
    let gaps = result.segments.filter { $0.kind == .gap }
    XCTAssertEqual(gaps.count, 1)
    XCTAssertEqual(Set([gaps.first?.a, gaps.first?.b]), Set([P2(5, 6.94), P2(5.055, 7)]))
    XCTAssertEqual(result.dangling.map(\.method), [.join, .join, .unclosed])
  }

  func testAClosetBehindTwoPiecesOfOneWallIsEnclosed() throws {
    // The closet in the top right is closed off by joining the tip of the wall from the right
    // edge to the tip of the wall from the top edge, 0.9 m apart. That wall is two pieces in
    // line, 5.5 cm apart sideways and overlapping by 6 cm; linked by two joins, one from each
    // free end to the other piece, the pieces made a loop instead of a wall stub and the closet
    // merged into the bedroom.
    var builder = WalkthroughBuilder(outline: [(0, 0), (10, 0), (10, 8), (0, 8)])
    builder.addWall((4, 0), (4, 8))
    builder.addWall((7, 8), (7, 6.94))
    builder.addWall((7.055, 7), (7.055, 5.4))
    builder.addWall((10, 5), (7.86, 5))
    builder.addSection("livingRoom", at: (2, 4))
    builder.addSection("bedroom", at: (5.5, 2))
    let (split, diagnostics) = try Walkthrough.analyze(builder.document)
    XCTAssertEqual(Walkthrough.summary(split), ["Living Room 32.00", "Bedroom 39.27", "Room 3 8.73"])
    XCTAssertEqual(diagnostics.enclosures.map(\.tag), ["stub-stub"])
  }

  func testAStubExtensionThatJustMissesAJunctionStillEnclosesTheHall() throws {
    // A wall stub along y = 1.33 points at the corner where a wall up the middle of the right part
    // meets a wall from the right edge, 0.6 m away. Extended exactly through that corner it
    // enclosed the hall; 0.6 mm off, the same closure only counted as a bridge to a corner, and
    // the hall merged into the living room.
    for offset in [0.0, 0.0006, -0.0006] {
      var builder = WalkthroughBuilder(outline: [(0, 0), (10.9763, 0), (10.9763, 7.0205), (0, 7.0205)])
      builder.addWall((5.7924, 1.33 + offset), (8.1475, 1.33 + offset))
      builder.addWall((8.75, 1.33), (8.75, 6.372))
      builder.addWall((2.42, 3.3365), (2.42, 7.0205))
      builder.addWall((8.2553, 1.33), (10.9763, 1.33))
      builder.addWall((5.27, 0), (5.27, 3.61))
      builder.addSection("bedroom", at: (3.772, 2.1875))
      builder.addSection("livingRoom", at: (3.2564, 3.63))
      let (split, diagnostics) = try Walkthrough.analyze(builder.document)
      XCTAssertEqual(
        Walkthrough.summary(split), ["Bedroom 26.50", "Living Room 30.30", "Room 3 12.67", "Hallway 7.59"],
        "offset \(offset)")
      XCTAssertEqual(diagnostics.enclosures.map(\.tag), ["stub-extend", "stub-extend"], "offset \(offset)")
    }
  }

  func testAPointIsOneNodeWhereverItSplitsASegment() {
    // A closure's tip lies on a wall 4.5 cm from the wall's end, and the closure's line crosses a
    // short link from that end 6 cm from it. Found again when the closure was split, the tip
    // welded to the nearer node made at that crossing in between, and the closure crossed the
    // wall without a node.
    let outline = [P2(0, -3), P2(8, -3), P2(8, 3), P2(0, 3)]
    var segments = outline.indices.map {
      PlanSegment(a: outline[$0], b: outline[($0 + 1) % 4], kind: .outline, fixed: true)
    }
    let end = P2(4.6586, -1.5533)
    segments.append(PlanSegment(a: P2(0, -2.6), b: end, kind: .wall, wall: 0))
    segments.append(PlanSegment(a: end, b: P2(4.5577, -1.4995), kind: .gap, wall: 1))
    segments.append(PlanSegment(a: P2(4.6585, -1.7354), b: P2(4.61516, -1.56431), kind: .gap, wall: 2))
    let arr = PlanArrangement(segments: segments, eps: 0.05, boundary: outline)
    let keys = arr.edges.keys.sorted()
    for (i, e) in keys.enumerated() {
      for f in keys[(i + 1)...] where Set([e.u, e.v, f.u, f.v]).count == 4 {
        if let r = Plan2D.segSeg(arr.points[e.u], arr.points[e.v], arr.points[f.u], arr.points[f.v]) {
          XCTAssertFalse(0 < r.t && r.t < 1 && 0 < r.u && r.u < 1, "\(e) crosses \(f)")
        }
      }
    }
  }

  func testShortWallsAlongACurveCloseTheSameWhenMovedAMillimetre() throws {
    // A quarter circle of 128 walls 6 cm long. Two chords on either side of a third cross, by
    // the welding tolerance, just past the third's ends; that crossing was put after the start
    // of the chord instead of before it, and a stray edge across two chords left the curve open.
    var builder = WalkthroughBuilder(outline: [(0, 0), (10, 0), (10, 8), (0, 8)])
    for k in 0..<128 {
      let a0 = Double.pi / 2 * Double(k) / 128
      let a1 = Double.pi / 2 * Double(k + 1) / 128
      builder.addWall((10 - 5 * cos(a0), 5 * sin(a0)), (10 - 5 * cos(a1), 5 * sin(a1)))
    }
    builder.addSection("livingRoom", at: (2, 6))
    builder.addSection("bedroom", at: (8.5, 1.5))
    XCTAssertEqual(Walkthrough.summary(try Walkthrough.split(builder.document)), ["Living Room 60.39", "Bedroom 19.61"])
    for seed in UInt64(1)...12 {
      let split = try Walkthrough.split(Walkthrough.jitter(builder.document, sigma: 0.001, seed: seed))
      XCTAssertEqual(split?.rooms.count, 2, "seed \(seed)")
      XCTAssertEqual(split?.rooms.last?.areaM2 ?? 0, 19.61, accuracy: 0.05, "seed \(seed)")
    }
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

  func testOrderAndPlacementDoNotMatterWhenWallsStopShort() throws {
    // The fixture with every wall end moved by up to 3 cm, so ends stop short of each other and
    // several of them weld and snap together.
    let fixture = try fixtureDocument()
    for jitter in UInt64(1)...6 {
      let document = Walkthrough.jitter(fixture, sigma: 0.03, seed: jitter)
      let base = try XCTUnwrap(try Walkthrough.split(document), "jitter \(jitter)")
      for seed in UInt64(1)...3 {
        let name = "jitter \(jitter) shuffle \(seed)"
        let split = try XCTUnwrap(try Walkthrough.split(Walkthrough.shuffled(document, seed: seed)), name)
        XCTAssertEqual(Walkthrough.labels(split), Walkthrough.labels(base), name)
        for (a, b) in zip(split.rooms, base.rooms) {
          XCTAssertLessThan(Walkthrough.hausdorff(a.polygon, b.polygon), 1e-9, name)
        }
      }
      for (theta, tx, tz) in [(0.3, 1.0, -2.0), (1.1, -0.7, 16.25), (-0.7, 10.0, 10.0)] {
        let name = "jitter \(jitter) moved \(theta)"
        let split = try XCTUnwrap(
          try Walkthrough.split(Walkthrough.moved(document, theta: theta, tx: tx, tz: tz)), name)
        XCTAssertEqual(Walkthrough.labels(split), Walkthrough.labels(base), name)
        let c = cos(theta)
        let s = sin(theta)
        for (room, original) in zip(split.rooms, base.rooms) {
          let undone = room.polygon.map { p -> Vector3 in
            let x = p.x - tx
            let z = p.z - tz
            return Vector3(c * x - s * z, p.y, s * x + c * z)
          }
          XCTAssertLessThan(Walkthrough.hausdorff(undone, original.polygon), 1e-6, name)
        }
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
    // Interior walls doubled 3 cm apart by shorter copies: the copies merge into the longer
    // originals, the same rooms, whatever the order of the walls.
    func doubled(shortenedBy cut: Double) -> RoomPlanDocument {
      var doubled = document
      for wall in document.rooms[0].walls where interior.contains(wall.identifier) {
        var copy = wall
        copy.identifier = wall.identifier + "-COPY"
        copy.dimensions[0] -= cut
        copy.transform.columns[3][0] += -wall.transform.columns[0][2] * 0.03
        copy.transform.columns[3][2] += wall.transform.columns[0][0] * 0.03
        doubled.rooms[0].walls.append(copy)
      }
      return doubled
    }
    let (split, diagnostics) = try Walkthrough.analyze(doubled(shortenedBy: 0.2))
    XCTAssertEqual(Walkthrough.summary(split), Self.fixtureRooms)
    XCTAssertGreaterThanOrEqual(diagnostics.duplicatesMerged, interior.count)
    XCTAssertEqual(
      Walkthrough.summary(try Walkthrough.split(Walkthrough.shuffled(doubled(shortenedBy: 0.2), seed: 3))),
      Self.fixtureRooms)
    // Copies as long as the originals: either of a pair may stay, picked by where it lies, not
    // by the order of the walls.
    let sameLength = try Walkthrough.split(doubled(shortenedBy: 0))
    XCTAssertEqual(sameLength?.rooms.count, 7)
    XCTAssertEqual(types(sameLength), types(try Walkthrough.split(document)))
    for seed in UInt64(1)...3 {
      XCTAssertEqual(
        Walkthrough.summary(try Walkthrough.split(Walkthrough.shuffled(doubled(shortenedBy: 0), seed: seed))),
        Walkthrough.summary(sameLength), "shuffle \(seed)")
    }
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
