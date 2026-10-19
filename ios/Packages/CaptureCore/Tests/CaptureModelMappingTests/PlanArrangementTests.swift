import Foundation
import XCTest

@testable import CaptureModelMapping

/// The planar arrangement of walk-through splitting (floorplan plan, phase 3).
final class PlanArrangementTests: XCTestCase {
  private let square = [P2(0, 0), P2(4, 0), P2(4, 4), P2(0, 4)]

  private func outline(_ ring: [P2]) -> [PlanSegment] {
    ring.indices.map { PlanSegment(a: ring[$0], b: ring[($0 + 1) % ring.count], kind: .outline, fixed: true) }
  }

  private func wall(_ a: P2, _ b: P2) -> PlanSegment { PlanSegment(a: a, b: b, kind: .wall, wall: 0) }

  private func areas(_ arr: PlanArrangement) -> [Double] {
    arr.faces.indices.map { Plan2D.area(arr.polygon($0)) }.sorted()
  }

  func testAFullCrossGivesFourFaces() {
    let arr = PlanArrangement(
      segments: outline(square) + [wall(P2(2, 0), P2(2, 4)), wall(P2(0, 2), P2(4, 2))], eps: 0.05, boundary: square)
    XCTAssertEqual(areas(arr), [4, 4, 4, 4])
    XCTAssertTrue(arr.selfCheck())
    XCTAssertEqual(arr.hints, [])
    // The outline vertices are the first nodes, bit for bit.
    XCTAssertEqual(Array(arr.points.prefix(4)), square)
    XCTAssertEqual(arr.isFixed.prefix(4), [true, true, true, true])
    // Two crossing walls meet at one node.
    XCTAssertTrue(arr.points.contains(P2(2, 2)))
  }

  func testAWallEndShortOfATWeldsIntoIt() {
    // The vertical wall stops 3 cm short of the horizontal one.
    let segments = outline(square) + [wall(P2(0, 2), P2(4, 2)), wall(P2(2, 0), P2(2, 1.97))]
    let welded = PlanArrangement(segments: segments, eps: 0.05, boundary: square)
    XCTAssertEqual(areas(welded).map { ($0 * 100).rounded() / 100 }, [3.97, 3.97, 8.06])
    XCTAssertTrue(welded.selfCheck())
    XCTAssertEqual(welded.hints, [])
    // The T node is the stub's end: the crossing welded to it.
    let tee = welded.points.firstIndex(of: P2(2, 1.97))
    XCTAssertEqual(welded.active.filter { $0.u == tee || $0.v == tee }.count, 3)
    // Without the weld the stub hangs into the face: a hint, and the face stays whole.
    let open = PlanArrangement(segments: segments, eps: 0.001, boundary: square)
    XCTAssertEqual(areas(open), [8, 8])
    XCTAssertEqual(open.hints.count, 1)
    XCTAssertTrue(open.selfCheck())
  }

  func testADanglingStubIsAHint() {
    let arr = PlanArrangement(
      segments: outline(square) + [wall(P2(2, 0), P2(2, 1.5))], eps: 0.05, boundary: square)
    XCTAssertEqual(areas(arr), [16])
    XCTAssertEqual(arr.hints.count, 1)
    XCTAssertTrue(arr.selfCheck())
  }

  func testAColumnIsAnIsland() {
    let column = [P2(1.7, 1.7), P2(2.3, 1.7), P2(2.3, 2.3), P2(1.7, 2.3)]
    let segments = outline(square) + column.indices.map { wall(column[$0], column[($0 + 1) % 4]) }
    let arr = PlanArrangement(segments: segments, eps: 0.05, boundary: square)
    XCTAssertEqual(areas(arr), [16])
    XCTAssertEqual(arr.hints.count, 4)
    XCTAssertEqual(arr.islandEdges, 4)
    XCTAssertTrue(arr.selfCheck())
  }

  func testCrossingWallsSplitAtTheirCrossing() {
    // Two walls that cross inside the square and touch the outline at their ends.
    let arr = PlanArrangement(
      segments: outline(square) + [wall(P2(0, 0), P2(4, 4)), wall(P2(0, 4), P2(4, 0))], eps: 0.05,
      boundary: square)
    XCTAssertEqual(areas(arr), [4, 4, 4, 4])
    XCTAssertTrue(arr.selfCheck())
    let centre = arr.points.firstIndex(of: P2(2, 2))
    XCTAssertNotNil(centre)
    XCTAssertEqual(arr.active.filter { $0.u == centre || $0.v == centre }.count, 4)
  }

  func testEdgeKindsAndClasses() {
    let arr = PlanArrangement(
      segments: outline(square) + [PlanSegment(a: P2(2, 0), b: P2(2, 4), kind: .cut)], eps: 0.05,
      boundary: square)
    XCTAssertEqual(areas(arr), [8, 8])
    let cut = arr.active.first { arr.edges[$0]?.kinds == .cut }
    XCTAssertNotNil(cut)
    XCTAssertEqual(EdgeKinds.cut.edgeClass, .virtual)
    XCTAssertEqual(EdgeKinds([.gap, .cut]).edgeClass, .real)
    XCTAssertEqual(EdgeKinds.outline.edgeClass, .real)
  }
}
