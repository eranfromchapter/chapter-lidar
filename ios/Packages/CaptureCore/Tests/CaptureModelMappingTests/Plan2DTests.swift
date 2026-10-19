import Foundation
import XCTest

@testable import CaptureModelMapping

/// The plan primitives of walk-through splitting (floorplan plan, phase 3).
final class Plan2DTests: XCTestCase {
  private let unitSquare = [P2(0, 0), P2(1, 0), P2(1, 1), P2(0, 1)]

  func testShoelaceSign() {
    XCTAssertEqual(Plan2D.area(unitSquare), 1)
    XCTAssertEqual(Plan2D.area(unitSquare.reversed()), -1)
    XCTAssertEqual(Plan2D.perimeter(unitSquare), 4)
  }

  func testContainsAgreesWithPolygonMath() {
    // A non-convex polygon (a U shape).
    let u = [P2(0, 0), P2(5, 0), P2(5, 4), P2(3.5, 4), P2(3.5, 1.5), P2(1.5, 1.5), P2(1.5, 4), P2(0, 4)]
    let u3 = u.map { Vector3($0.x, 0, $0.y) }
    var rng = SplitMix64(seed: 7)
    var inside = 0
    for _ in 0..<1000 {
      let p = P2(rng.uniform(-1, 6), rng.uniform(-1, 5))
      let expected = PolygonMath.contains(u3, Vector3(p.x, 0, p.y))
      XCTAssertEqual(Plan2D.contains(u, p), expected, "\(p)")
      if expected { inside += 1 }
    }
    XCTAssertGreaterThan(inside, 200)
  }

  func testSegmentPrimitives() {
    XCTAssertNil(Plan2D.segSeg(P2(0, 0), P2(1, 0), P2(0, 1), P2(1, 1)), "parallel")
    let r = Plan2D.segSeg(P2(0, 0), P2(2, 0), P2(1, -1), P2(1, 1))
    XCTAssertEqual(r?.t, 0.5)
    XCTAssertEqual(r?.u, 0.5)
    let near = Plan2D.segPoint(P2(3, 1), P2(0, 0), P2(2, 0))
    XCTAssertEqual(near.t, 1)
    XCTAssertEqual(near.distance, 2.squareRoot(), accuracy: 1e-15)
    XCTAssertEqual(Plan2D.polyDist(unitSquare, P2(0.5, 0.25)), 0.25)
  }

  func testClipping() {
    // Half of the unit square lies right of x = 0.5.
    let right = [P2(0.5, -1), P2(2, -1), P2(2, 2), P2(0.5, 2)]
    XCTAssertEqual(Plan2D.area(Plan2D.clipConvex(unitSquare, right)), 0.5, accuracy: 1e-12)
    XCTAssertEqual(Plan2D.clipLenConvex(P2(-1, 0.5), P2(0.5, 0.5), unitSquare), 0.5, accuracy: 1e-12)
    XCTAssertEqual(Plan2D.clipLenConvex(P2(-1, 2), P2(2, 2), unitSquare), 0, "outside")
  }

  func testMinRectOfARotatedRectangle() {
    let c = cos(0.3)
    let s = sin(0.3)
    let rect = [P2(0, 0), P2(3, 0), P2(3, 1), P2(0, 1)].map { P2(c * $0.x - s * $0.y + 2, s * $0.x + c * $0.y - 1) }
    let (long, short) = Plan2D.minRect(rect)
    XCTAssertEqual(long, 3, accuracy: 1e-12)
    XCTAssertEqual(short, 1, accuracy: 1e-12)
    XCTAssertTrue(Plan2D.isSimple(rect))
    XCTAssertFalse(Plan2D.isSimple([P2(0, 0), P2(1, 1), P2(1, 0), P2(0, 1)]), "a bow tie")
  }

  func testAngleOrderIsExactAndTotal() {
    let directions = [P2(1, 0), P2(1, 1), P2(0, 1), P2(-1, 1), P2(-1, 0), P2(-1, -1), P2(0, -1), P2(1, -1)]
    for i in directions.indices {
      for j in directions.indices {
        XCTAssertEqual(Plan2D.angleOrder(directions[i], directions[j]), i < j ? -1 : (i == j ? 0 : 1), "\(i) \(j)")
      }
    }
    // Ids around a centre: by angle, then by id for the same direction.
    let points = [P2(0, 0), P2(0, -1), P2(-1, 0), P2(0, 2), P2(1, 0), P2(0, 1)]
    XCTAssertEqual(Plan2D.sortedAround([1, 2, 3, 4, 5], centre: points[0], points: points), [4, 3, 5, 2, 1])
  }

  func testDominantAxesWithoutTrig() {
    let angle = 14.2 * Double.pi / 180
    let u = P2(cos(angle), sin(angle))
    let v = P2(-u.y, u.x)
    let walls = [(a: P2(1, 2), b: P2(1, 2) + u * 4), (a: P2(0, 0), b: v * 3), (a: P2(5, 5), b: P2(5, 5) - u * 2)]
    let axes = PlanAxes(walls: walls)
    XCTAssertEqual(axes.u.x, u.x, accuracy: 1e-12)
    XCTAssertEqual(axes.u.y, u.y, accuracy: 1e-12)
    XCTAssertEqual(axes.v.x, -u.y, accuracy: 1e-12)
    XCTAssertEqual(axes.deviation(u), 0, accuracy: 1e-12)
    // Within 10 degrees snaps to the axis pointing the same way; farther stays.
    let off = P2(cos(angle + 0.1), sin(angle + 0.1))
    XCTAssertEqual(axes.snap(off * -1), axes.u * -1)
    let far = P2(cos(angle + 0.3), sin(angle + 0.3))
    XCTAssertEqual(axes.snap(far), far)
    XCTAssertEqual(PlanAxes(walls: []).u, P2(1, 0))
    let root = Plan2D.csqrt(-1, 0)
    XCTAssertEqual(root.re, 0)
    XCTAssertEqual(root.im, 1)
  }

  func testInteriorPoint() {
    let u = [P2(0, 0), P2(5, 0), P2(5, 4), P2(3.5, 4), P2(3.5, 1.5), P2(1.5, 1.5), P2(1.5, 4), P2(0, 4)]
    XCTAssertTrue(Plan2D.contains(u, Plan2D.interiorPoint(u)))
    XCTAssertEqual(Plan2D.interiorPoint(unitSquare), P2(0.5, 0.5))
  }
}

/// A small deterministic random generator (SplitMix64), the same on every platform.
struct SplitMix64 {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// Uniform in [low, high).
  mutating func uniform(_ low: Double, _ high: Double) -> Double {
    low + (high - low) * (Double(next() >> 11) / 9_007_199_254_740_992)
  }

  /// Fisher-Yates.
  mutating func shuffle<T>(_ items: inout [T]) {
    guard items.count > 1 else { return }
    for i in stride(from: items.count - 1, to: 0, by: -1) {
      items.swapAt(i, Int(next() % UInt64(i + 1)))
    }
  }
}
