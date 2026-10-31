import CaptureContract
import CaptureTestSupport
import Foundation
import SketchReading
import SketchSolver
import XCTest

/// Builders for sketch readings in drawing coordinates (origin top-left, y down).
enum Reading {
  static let visitId = LowercaseUUID(rawValue: "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")!
  static let captureId = LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!
  static let imagePath = "Original Exports/floor-1/a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60/sketch.jpg"
  static let interpretationPath =
    "Original Exports/floor-1/a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60/sketch-interpretation.json"
  static let context = SketchSolveContext(label: "Floor 1")

  static func point(_ x: Double, _ y: Double) -> SketchInterpretation.Point {
    SketchInterpretation.Point(x: x, y: y)
  }

  /// A rectangle drawn clockwise on the page (top-left, top-right, bottom-right, bottom-left),
  /// the way people usually draw it and the way the contract example is.
  static func clockwiseRectangle(
    x: Double, y: Double, width: Double, height: Double
  ) -> [SketchInterpretation.Point] {
    [point(x, y), point(x + width, y), point(x + width, y + height), point(x, y + height)]
  }

  static func interpretation(
    units: SketchDimensionUnits = .imperial, ceilingMm: Double? = nil,
    rooms: [SketchInterpretation.Room], dimensions: [SketchInterpretation.Dimension] = []
  ) -> SketchInterpretation {
    SketchInterpretation(
      model: "claude-opus-5-5", interpretedAt: UTCTimestamp(secondsSince1970: 1_792_243_900),
      image: SketchInterpretation.ImageSize(width: 3024, height: 4032),
      reading: SketchInterpretation.Reading(
        isFloorPlan: true, dimensionUnits: units, ceilingHeightMm: ceilingMm, rooms: rooms,
        dimensions: dimensions))
  }

  static func convert(
    _ interpretation: SketchInterpretation, userLength: UserScaleLength? = nil,
    displayUnits: DisplayUnitSystem = .imperial
  ) throws -> SketchReadingConversion {
    try SketchReadingConverter.convert(
      interpretation, userLength: userLength, visitId: visitId, captureId: captureId,
      areaKey: "floor-1", displayUnits: displayUnits, sourceKind: .handSketch,
      imagePath: imagePath, interpretationPath: interpretationPath)
  }

  static func solve(_ conversion: SketchReadingConversion) throws -> SketchSolveResult {
    try SketchSolver.solve(conversion.measurements, context: context)
  }

  static func example(_ name: String) throws -> SketchInterpretation {
    let url = Fixtures.repositoryRoot.appendingPathComponent(
      "contract/examples/sketch-interpretation/valid/\(name).json")
    return try CaptureContractJSON.makeDecoder().decode(
      SketchInterpretation.self, from: Data(contentsOf: url))
  }
}

extension XCTestCase {
  func validate(
    _ value: some Encodable, schema: String, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let data = try CaptureContractJSON.makeEncoder().encode(value)
    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL(schema))
    XCTAssertEqual(try validator.validate(jsonData: data), [], schema, file: file, line: line)
  }

  /// Edge lengths of a room polygon in millimetres, edge `i` from corner `i` to corner `i + 1`.
  func edgeLengthsMm(_ room: CaptureModel.Room) -> [Double] {
    let p = room.polygon
    return p.indices.map { index in
      let a = p[index]
      let b = p[(index + 1) % p.count]
      let dx: Double = b.x - a.x
      let dz: Double = b.z - a.z
      return (dx * dx + dz * dz).squareRoot() * 1000
    }
  }

  /// The limiting notes of a solve (those that make the capture Limited).
  func limitingNotes(_ result: SketchSolveResult) -> [SketchSolveNote.Kind] {
    result.notes.map(\.kind).filter { kind in
      switch kind {
      case .wallEstimated, .cornerAssumedSquare, .ceilingAssumed: return true
      case .openingEstimated(_, let field): return field == .width || field == .position
      case .closureResidual(_, _, _, let grade): return grade != .pass
      case .wallDerivedFromClosure: return false
      }
    }
  }

  /// True when (x, z) is inside the room polygon (even-odd rule).
  func contains(_ room: CaptureModel.Room, x: Double, z: Double) -> Bool {
    let p = room.polygon
    var inside = false
    var j = p.count - 1
    for i in p.indices {
      let zi = p[i].z
      let zj = p[j].z
      if (zi > z) != (zj > z) {
        let t: Double = (z - zi) / (zj - zi)
        let crossing: Double = p[i].x + t * (p[j].x - p[i].x)
        if x < crossing { inside.toggle() }
      }
      j = i
    }
    return inside
  }

  /// Where a box's local +x points in the model, from its rotation quaternion.
  func localX(_ q: Quaternion) -> (x: Double, y: Double, z: Double) {
    let x: Double = 1 - 2 * (q.y * q.y + q.z * q.z)
    let y: Double = 2 * (q.x * q.y + q.w * q.z)
    let z: Double = 2 * (q.x * q.z - q.w * q.y)
    return (x, y, z)
  }
}
