import CaptureContract
import CaptureTestSupport
import Foundation
import SketchSolver
import Walkthrough
import XCTest

/// A seeded generator (SplitMix64) so the "noisy" taps are the same on every run.
struct WalkthroughNoise {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// Uniform in [−amplitude, amplitude].
  mutating func offset(_ amplitude: Double) -> Double {
    let unit = Double(next() >> 11) / Double(1 << 53)
    return (unit * 2 - 1) * amplitude
  }
}

/// Builders for walkthrough logs. Plan points are (x, y) metres seen from +Y with y = −z, the
/// way a room is drawn; `ar` turns one into a tap in the AR frame at a height above the floor.
enum Walk {
  static let visitId = LowercaseUUID(rawValue: "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")!
  static let captureId = LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!
  static let floorY = -1.4
  static let sourcePath =
    "Original Exports/floor-1/a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60/walkthrough-log.json"
  static let context = SketchSolveContext(label: "Floor 1")

  typealias Point = (x: Double, y: Double)

  static func ar(_ point: Point, height: Double = 0) -> Vec3 {
    Vec3(x: point.x, y: floorY + height, z: -point.y)
  }

  static func tap(_ point: Point, height: Double = 0, t: Double) -> WalkthroughLog.Tap {
    WalkthroughLog.Tap(p: ar(point, height: height), t: t)
  }

  /// The plan points turned by `degrees` (counter-clockwise from +Y) about the origin, then moved.
  static func transform(_ points: [Point], degrees: Double, dx: Double, dy: Double) -> [Point] {
    let a = degrees * Double.pi / 180
    return points.map { p in
      (x: p.x * cos(a) - p.y * sin(a) + dx, y: p.x * sin(a) + p.y * cos(a) + dy)
    }
  }

  static func lerp(_ a: Point, _ b: Point, _ f: Double) -> Point {
    (x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
  }

  static func distance(_ a: Point, _ b: Point) -> Double {
    ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
  }

  static func log(
    rooms: [WalkthroughLog.Room], frames: [WalkthroughLog.Frame] = [],
    scaleCheck: WalkthroughLog.ScaleCheck? = nil
  ) -> WalkthroughLog {
    WalkthroughLog(
      visitId: visitId, captureId: captureId, areaKey: "floor-1",
      startedAt: UTCTimestamp(secondsSince1970: 1_792_243_805),
      finishedAt: UTCTimestamp(secondsSince1970: 1_792_244_512), floorY: floorY, frames: frames,
      rooms: rooms, scaleCheck: scaleCheck)
  }

  static func tape(_ millimetres: Double) -> WalkthroughLog.Length {
    WalkthroughLog.Length(
      valueMm: millimetres, enteredUnit: .mm, enteredText: "\(Int(millimetres.rounded()))")
  }

  /// A `corners` room: one tap per corner, 7 s apart, with tap noise, the drift growing with
  /// time to `drift` at the closing tap, and the closing tap back on corner 0.
  static func cornersRoom(
    id: String = "room-1", label: String = "Bedroom", truth: [Point], noise amplitude: Double,
    seed: UInt64, drift: Point = (0, 0), close: Bool = true, scale: Double = 1,
    ceilingHeight: Double? = 2.7, openings: [WalkthroughLog.Opening] = []
  ) -> WalkthroughLog.Room {
    var noise = WalkthroughNoise(seed: seed)
    let times = truth.indices.map { 10 + 7 * Double($0) }
    let closingTime = 10 + 7 * Double(truth.count)
    var corners: [WalkthroughLog.Tap] = []
    for (index, corner) in truth.enumerated() {
      let f = (times[index] - times[0]) / (closingTime - times[0])
      let p: Point = (
        corner.x * scale + noise.offset(amplitude) + drift.x * f,
        corner.y * scale + noise.offset(amplitude) + drift.y * f
      )
      corners.append(tap(p, t: times[index]))
    }
    let first = corners[0].p
    let closing = WalkthroughLog.Tap(
      p: Vec3(x: first.x + drift.x, y: first.y, z: first.z - drift.y), t: closingTime)
    let ceiling = ceilingHeight.map { h in
      [tap(lerp(truth[0], truth[1], 0.5), height: h * scale, t: closingTime + 5)]
    }
    return WalkthroughLog.Room(
      id: id, label: label, type: .bedroom, method: .corners, corners: corners,
      closingTap: close ? closing : nil, ceiling: ceiling ?? [], openings: openings)
  }

  /// The 4.000 x 3.000 m rectangle, turned 30° and moved off the origin so placement matters.
  static let rectangleTruth = transform(
    [(0, 0), (4, 0), (4, 3), (0, 3)], degrees: 30, dx: 1.2, dy: 0.7)

  static func convert(
    _ log: WalkthroughLog, units: DisplayUnitSystem = .metric
  ) throws -> WalkthroughConversion {
    try WalkthroughConverter.convert(
      log, displayUnits: units, sourcePath: sourcePath, recorded: true)
  }
}

extension XCTestCase {
  /// The plan point (x, −z) of a model point.
  func plan(_ point: Vec3) -> Walk.Point { (point.x, -point.z) }

  func edgeLengths(_ polygon: [Vec3]) -> [Double] {
    polygon.indices.map { index in
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      return ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
    }
  }

  /// Signed shoelace area in (x, z): negative is counter-clockwise seen from +Y.
  func signedArea(_ polygon: [Vec3]) -> Double {
    var sum = 0.0
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      sum += a.x * b.z - b.x * a.z
    }
    return sum / 2
  }

  /// The interior angle at each corner of a counter-clockwise polygon, in degrees.
  func interiorAngles(_ polygon: [Vec3]) -> [Double] {
    let n = polygon.count
    return (0..<n).map { index in
      let a = plan(polygon[(index + n - 1) % n])
      let b = plan(polygon[index])
      let c = plan(polygon[(index + 1) % n])
      let incoming = (x: b.x - a.x, y: b.y - a.y)
      let outgoing = (x: c.x - b.x, y: c.y - b.y)
      let turn = atan2(
        incoming.x * outgoing.y - incoming.y * outgoing.x,
        incoming.x * outgoing.x + incoming.y * outgoing.y)
      return 180 - turn * 180 / Double.pi
    }
  }

  func assertPoint(
    _ actual: Vec3, _ expected: Walk.Point, within accuracy: Double, _ label: String = "",
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let d = Walk.distance(plan(actual), expected)
    XCTAssertLessThanOrEqual(
      d, accuracy, "\(label): \(plan(actual)) is \(Int((d * 1000).rounded())) mm from \(expected)",
      file: file, line: line)
  }

  func validate(
    _ value: some Encodable, schema: String, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let data = try CaptureContractJSON.makeEncoder().encode(value)
    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL(schema))
    XCTAssertEqual(try validator.validate(jsonData: data), [], schema, file: file, line: line)
  }
}
