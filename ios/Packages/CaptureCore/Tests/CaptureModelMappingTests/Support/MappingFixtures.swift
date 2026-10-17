import CaptureContract
import CaptureModelMapping
import CaptureTestSupport
import Foundation
import XCTest

/// Every generated capture that a mapping test runs on: (fixture name, capture index).
let allGeneratedCaptures: [(fixture: String, index: Int)] = [
  ("box-room", 0), ("l-shaped-room", 0), ("two-room-apartment", 0), ("two-floor-house", 0),
  ("two-floor-house", 1),
]

struct MappedFixture {
  let fixture: GeneratedFixture
  let index: Int
  var document: RoomPlanDocument
  var context: MappingContext
  /// The generator's own capture model of this capture (the expected result).
  let expected: JSON
  let model: CaptureModel

  var truth: JSON { fixture.captureTruth(index) }
}

func mapFixture(_ name: String, capture index: Int = 0) throws -> MappedFixture {
  let fixture = try Fixtures.load(name)
  let truth = fixture.captureTruth(index)
  let document = try RoomPlanDocument.decode(from: fixture.roomPlanData(index))
  let expectedJSON = try fixture.captureModel(index)
  // The refs and room labels are not in the RoomPlan JSON (they come from the capture record and
  // the form), so they are taken from the expected model; everything else is computed.
  let expectedModel = try JSONDecoder().decode(
    CaptureModel.self, from: try Data(contentsOf: fixture.captureDirectory(index).appendingPathComponent("capture-model.json")))
  let context = MappingContext(
    visitId: try XCTUnwrap(LowercaseUUID(rawValue: fixture.visitId)),
    captureId: try XCTUnwrap(LowercaseUUID(rawValue: try XCTUnwrap(truth["captureId"]?.string))),
    areaKey: try XCTUnwrap(truth["areaKey"]?.string), label: try XCTUnwrap(truth["label"]?.string),
    roomLabels: expectedModel.rooms.map(\.label), refs: expectedModel.refs)
  let model = try CaptureModelMapper.map(document, context: context)
  return MappedFixture(
    fixture: fixture, index: index, document: document, context: context, expected: expectedJSON,
    model: model)
}

/// JSON of a model exactly as the app writes it.
func encodedJSON(_ model: CaptureModel) throws -> JSON {
  try JSON.parse(CaptureContractJSON.makeEncoder().encode(model))
}

/// Differences between two JSON values, numbers compared within `tolerance`. A rotation
/// quaternion and its negative are the same rotation, so `rotation` arrays compare up to sign.
func differences(_ actual: JSON, _ expected: JSON, tolerance: Double, at path: String = "") -> [String] {
  switch (actual, expected) {
  case (.object(let a), .object(let e)):
    var result: [String] = []
    for key in Set(a.keys).union(e.keys).sorted() {
      switch (a[key], e[key]) {
      case (let l?, let r?): result += differences(l, r, tolerance: tolerance, at: "\(path)/\(key)")
      case (_?, nil): result.append("\(path)/\(key): not expected")
      case (nil, _?): result.append("\(path)/\(key): missing")
      case (nil, nil): break
      }
    }
    return result
  case (.array(let a), .array(let e)):
    guard a.count == e.count else { return ["\(path): \(a.count) items, expected \(e.count)"] }
    if path.hasSuffix("/rotation"), let x = actual.numbers, let y = expected.numbers {
      let dot = zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
      return abs(abs(dot) - 1) <= tolerance ? [] : ["\(path): rotation \(x) differs from \(y)"]
    }
    return zip(a, e).enumerated().flatMap { differences($1.0, $1.1, tolerance: tolerance, at: "\(path)/\($0)") }
  case (.number(let a), .number(let e)):
    return abs(a - e) <= tolerance ? [] : ["\(path): \(a) differs from \(e) by \(abs(a - e))"]
  default:
    return actual == expected ? [] : ["\(path): \(actual) differs from \(expected)"]
  }
}
