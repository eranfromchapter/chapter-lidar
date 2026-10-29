import CaptureContract
import Foundation
import XCTest

/// AC2: every valid example decodes and re-encodes to JSON equal to the original.
/// "Equal" is semantic: same keys, same values, numbers compared numerically, key order and
/// whitespace ignored. A dropped field, an added field or a `null` fails the test. The one
/// expected change: a capture model, a capture record and a manifest are written as the current
/// version, so a 1.0.0 example comes back as 1.1.0 (except a manifest that lists a retired role,
/// which 1.1.0 does not allow and is written as 1.0.0).
final class RoundTripTests: XCTestCase {
  /// One entry per schema in contract/schema, keyed by the schema name (file name without
  /// `.schema.json`, which is also the example folder name).
  static let codecs: [String: @Sendable (Data) throws -> Data] = [
    "capture-record": { try roundTrip(CaptureRecord.self, $0) },
    "capture-model": { try roundTrip(CaptureModel.self, $0) },
    "field-controls": { try roundTrip(FieldControls.self, $0) },
    "manifest": { try roundTrip(PackageManifest.self, $0) },
    "sketch-measurements": { try roundTrip(SketchMeasurements.self, $0) },
    "verdict": { try roundTrip(Verdict.self, $0) },
  ]

  static func roundTrip<T: Codable>(_ type: T.Type, _ data: Data) throws -> Data {
    let value = try CaptureContractJSON.makeDecoder().decode(T.self, from: data)
    return try CaptureContractJSON.makeEncoder().encode(value)
  }

  /// The JSON a valid example re-encodes to: the example itself, with the `schemaVersion` the
  /// Swift type writes.
  static func expectedAfterRoundTrip(schema: String, _ original: JSONValue) -> JSONValue {
    guard case .object(var members) = original else { return original }
    switch schema {
    case "capture-model":
      members["schemaVersion"] = .string(CaptureModelSchemaVersion.current.rawValue)
    case "capture-record":
      members["schemaVersion"] = .string(CaptureRecordSchemaVersion.current.rawValue)
    case "manifest":
      let roles: [String] = {
        guard case .array(let files)? = members["files"] else { return [] }
        return files.compactMap { file in
          guard case .object(let entry) = file, case .string(let role)? = entry["role"] else {
            return nil
          }
          return role
        }
      }()
      let listsRetiredRole = roles.contains { FileRole(rawValue: $0)?.isRetired == true }
      members["schemaVersion"] = .string(
        (listsRetiredRole ? ManifestSchemaVersion.v1 : .current).rawValue)
    default:
      break
    }
    return .object(members)
  }

  func testEverySchemaHasASwiftModel() throws {
    let schemas = try ContractFiles.schemaNames()
    XCTAssertFalse(
      schemas.isEmpty, "no *.schema.json files found in \(ContractFiles.schemaDirectory.path)")
    XCTAssertEqual(
      Set(schemas), Set(Self.codecs.keys),
      "Swift models and contract/schema/*.schema.json are out of step")
  }

  func testEveryExampleFolderHasASwiftModel() throws {
    let folders = try ContractFiles.exampleFolderNames()
    XCTAssertEqual(
      Set(folders), Set(Self.codecs.keys),
      "Swift models and contract/examples/<schema>/ folders are out of step")
  }

  func testEveryValidExampleRoundTrips() throws {
    var checked = 0
    for schema in Self.codecs.keys.sorted() {
      let examples = try ContractFiles.examples(schema: schema, kind: "valid")
      XCTAssertFalse(examples.isEmpty, "\(schema): no valid examples to round-trip")
      for url in examples {
        let name = "\(schema)/valid/\(url.lastPathComponent)"
        let original = try Data(contentsOf: url)
        let reencoded: Data
        do {
          reencoded = try Self.codecs[schema]!(original)
        } catch {
          XCTFail("\(name): does not decode: \(error)")
          continue
        }
        let differences = Self.expectedAfterRoundTrip(schema: schema, try JSONValue.parse(original))
          .differences(from: try JSONValue.parse(reencoded))
        XCTAssertEqual(
          differences, [],
          "\(name): re-encoded JSON differs:\n" + differences.joined(separator: "\n"))
        XCTAssertFalse(
          try JSONValue.parse(reencoded).containsNull, "\(name): re-encoded JSON contains null")
        checked += 1
      }
    }
    XCTAssertGreaterThanOrEqual(checked, Self.codecs.count)
  }

  /// Decoding then encoding twice gives the same bytes, so files written by the app are
  /// reproducible (their SHA-256 does not depend on dictionary order).
  func testEncodingIsDeterministic() throws {
    for schema in Self.codecs.keys.sorted() {
      for url in try ContractFiles.examples(schema: schema, kind: "valid") {
        let once = try Self.codecs[schema]!(Data(contentsOf: url))
        let twice = try Self.codecs[schema]!(once)
        XCTAssertEqual(
          once, twice, "\(schema)/valid/\(url.lastPathComponent): encoding is not stable")
      }
    }
  }

  /// Closed enums reject values outside the contract. This is not schema validation (Swift does
  /// not check patterns, ranges or cross-field rules); it only shows the enums are closed.
  func testClosedEnumsRejectUnknownValues() throws {
    let unknownRole = ContractFiles.examplesDirectory
      .appendingPathComponent("manifest/invalid/unknown-role.json")
    XCTAssertThrowsError(
      try CaptureContractJSON.makeDecoder().decode(
        PackageManifest.self, from: Data(contentsOf: unknownRole)))

    let unknownMode = ContractFiles.examplesDirectory
      .appendingPathComponent("capture-record/invalid/unknown-mode.json")
    XCTAssertThrowsError(
      try CaptureContractJSON.makeDecoder().decode(
        CaptureRecord.self, from: Data(contentsOf: unknownMode)))

    let unknownRoomType = ContractFiles.examplesDirectory
      .appendingPathComponent("capture-model/invalid/unknown-room-type.json")
    XCTAssertThrowsError(
      try CaptureContractJSON.makeDecoder().decode(
        CaptureModel.self, from: Data(contentsOf: unknownRoomType)))
  }

  // MARK: Capture model versions

  private func captureModelExample(_ fileName: String) throws -> Data {
    try Data(
      contentsOf: ContractFiles.examplesDirectory.appendingPathComponent(
        "capture-model/valid/\(fileName)"))
  }

  func testCaptureModelReadsBothVersionsAndWritesTheCurrentOne() throws {
    let decoder = CaptureContractJSON.makeDecoder()
    let old = try decoder.decode(CaptureModel.self, from: captureModelExample("floor-1.json"))
    XCTAssertEqual(old.schemaVersion, .v1)
    XCTAssertNil(old.rooms[0].type)
    let new = try decoder.decode(CaptureModel.self, from: captureModelExample("floor-2.json"))
    XCTAssertEqual(new.schemaVersion, .v1_1)

    for model in [old, new] {
      let written = try JSONValue.parse(CaptureContractJSON.makeEncoder().encode(model))
      guard case .object(let members) = written else { return XCTFail("not an object") }
      XCTAssertEqual(members["schemaVersion"], .string("1.1.0"))
    }
    let created = CaptureModel(
      visitId: old.visitId, captureId: old.captureId, areaKey: "floor-1", label: "Floor 1")
    XCTAssertEqual(created.schemaVersion, .current)
  }

  func testCaptureModelFieldsAddedIn1_1Decode() throws {
    let model = try CaptureContractJSON.makeDecoder().decode(
      CaptureModel.self, from: captureModelExample("floor-2.json"))
    XCTAssertEqual(model.rooms.map(\.type), [.bedroom, .bathroom])
    XCTAssertEqual(model.rooms.map(\.typeSource), [.roomplanSection, .inferred])
    XCTAssertEqual(model.doors.map(\.isOpen), [true, false])
    XCTAssertEqual(model.windows.map(\.isOpen), [nil])
    XCTAssertEqual(model.objects[2].attributes, ["StorageType": "cabinet"])
    XCTAssertEqual(model.objects[3].parentId, model.objects[2].id)
    XCTAssertNil(model.objects[0].attributes)
  }

  func testCaptureModelRejectsAnUnknownVersion() throws {
    let text = String(decoding: try captureModelExample("floor-1.json"), as: UTF8.self)
      .replacingOccurrences(of: "\"1.0.0\"", with: "\"1.2.0\"")
    XCTAssertThrowsError(
      try CaptureContractJSON.makeDecoder().decode(CaptureModel.self, from: Data(text.utf8)))
  }

  // MARK: Capture record versions

  private func example(_ path: String) throws -> Data {
    try Data(contentsOf: ContractFiles.examplesDirectory.appendingPathComponent(path))
  }

  private func writtenVersion<T: Encodable>(_ value: T) throws -> JSONValue? {
    guard case .object(let members) = try JSONValue.parse(
      CaptureContractJSON.makeEncoder().encode(value))
    else { return nil }
    return members["schemaVersion"]
  }

  func testCaptureRecordReadsBothVersionsAndWritesTheCurrentOne() throws {
    let decoder = CaptureContractJSON.makeDecoder()
    let old = try decoder.decode(
      CaptureRecord.self, from: example("capture-record/valid/two-captures.json"))
    XCTAssertEqual(old.schemaVersion, .v1)
    XCTAssertNil(old.captures[0].heading)
    let new = try decoder.decode(
      CaptureRecord.self, from: example("capture-record/valid/compass-two-captures.json"))
    XCTAssertEqual(new.schemaVersion, .v1_1)
    let sketch = try decoder.decode(
      CaptureRecord.self, from: example("capture-record/valid/sketch-capture.json"))
    XCTAssertEqual(sketch.schemaVersion, .v1_2)
    for record in [old, new, sketch] {
      XCTAssertEqual(try writtenVersion(record), .string("1.2.0"))
    }
    XCTAssertEqual(CaptureRecordSchemaVersion.current, .v1_2)
  }

  func testCaptureRecordSourceIsLidarUnlessTheRecordSaysSketch() throws {
    let decoder = CaptureContractJSON.makeDecoder()
    let old = try decoder.decode(
      CaptureRecord.self, from: example("capture-record/valid/compass-two-captures.json"))
    XCTAssertNil(old.captures[0].captureSource)
    XCTAssertEqual(old.captures[0].source, .lidar)
    XCTAssertNil(old.captures[0].sketch)
    let record = try decoder.decode(
      CaptureRecord.self, from: example("capture-record/valid/sketch-capture.json"))
    XCTAssertEqual(record.captures[0].captureSource, .lidar)
    XCTAssertEqual(record.captures[1].captureSource, .sketch)
    XCTAssertEqual(record.captures[1].source, .sketch)
    let summary = try XCTUnwrap(record.captures[1].sketch)
    XCTAssertEqual(summary.measurements, .limited)
    XCTAssertEqual(summary.wallsMeasured, 7)
    XCTAssertEqual(summary.wallsEstimated, 1)
    XCTAssertEqual(summary.ceilingHeightSource, .measured)
    XCTAssertEqual(summary.closureResidualMm, 12)
    XCTAssertNil(record.captures[1].heading)
    XCTAssertNil(record.captures[1].headingIssue)
  }

  func testCaptureRecordCompassFieldsDecode() throws {
    let record = try CaptureContractJSON.makeDecoder().decode(
      CaptureRecord.self, from: example("capture-record/valid/compass-two-captures.json"))
    let floor1 = record.captures[0]
    XCTAssertEqual(floor1.heading, 212.4)
    XCTAssertEqual(floor1.headingAccuracy, 8)
    XCTAssertEqual(floor1.headingSource, .trueNorth)
    XCTAssertEqual(floor1.headingRecordedAt?.rawValue, "2026-10-17T14:02:20Z")
    XCTAssertNil(floor1.headingIssue)
    XCTAssertNil(record.captures[1].heading)
    XCTAssertEqual(record.captures[1].headingIssue, .rejected)
  }

  func testCaptureRecordRejectsAnUnknownVersionOrSource() throws {
    let text = String(
      decoding: try example("capture-record/valid/compass-two-captures.json"), as: UTF8.self)
    for (from, to) in [("\"1.1.0\"", "\"1.3.0\""), ("\"headingSource\": \"true\"", "\"headingSource\": \"grid\"")] {
      XCTAssertThrowsError(
        try CaptureContractJSON.makeDecoder().decode(
          CaptureRecord.self, from: Data(text.replacingOccurrences(of: from, with: to).utf8)),
        to)
    }
  }

  func testSetCompassWritesTheReadingOrTheIssueAndClearsTheRest() throws {
    var capture = try CaptureContractJSON.makeDecoder().decode(
      CaptureRecord.self, from: example("capture-record/valid/two-captures.json")
    ).captures[0]
    let readAt = UTCTimestamp(rawValue: "2026-10-17T14:02:20Z")!
    capture.setCompass(.reading(heading: 212.44, accuracy: 8, source: .trueNorth, recordedAt: readAt))
    XCTAssertEqual(capture.heading, 212.4)
    XCTAssertEqual(capture.headingAccuracy, 8)
    XCTAssertEqual(capture.headingSource, .trueNorth)
    XCTAssertEqual(capture.headingRecordedAt, readAt)
    XCTAssertNil(capture.headingIssue)
    XCTAssertEqual(CompassState(capture), .verified(heading: 212.4, accuracy: 8))

    capture.setCompass(.none(issue: .rejected))
    XCTAssertNil(capture.heading)
    XCTAssertNil(capture.headingAccuracy)
    XCTAssertNil(capture.headingSource)
    XCTAssertNil(capture.headingRecordedAt)
    XCTAssertEqual(capture.headingIssue, .rejected)

    capture.setCompass(.reading(heading: 359.97, accuracy: 0, source: .magnetic, recordedAt: readAt))
    XCTAssertEqual(capture.heading, 0)
    XCTAssertEqual(capture.headingAccuracy, 1)
    XCTAssertNil(capture.headingIssue)
    capture.setCompass(.reading(heading: -0.04, accuracy: 400, source: .magnetic, recordedAt: readAt))
    XCTAssertEqual(capture.heading, 0)
    XCTAssertEqual(capture.headingAccuracy, 180)

    capture.setCompass(.none(issue: nil))
    XCTAssertEqual(capture, try CaptureContractJSON.makeDecoder().decode(
      CaptureRecord.self, from: example("capture-record/valid/two-captures.json")
    ).captures[0])
  }

  func testACaptureWithoutCompassFieldsWritesNone() throws {
    let record = try CaptureContractJSON.makeDecoder().decode(
      CaptureRecord.self, from: example("capture-record/valid/two-captures.json"))
    let text = String(decoding: try CaptureContractJSON.makeEncoder().encode(record), as: UTF8.self)
    XCTAssertFalse(text.contains("heading"))
  }

  // MARK: Manifest versions

  func testManifestReadsBothVersionsAndWritesTheCurrentOne() throws {
    let decoder = CaptureContractJSON.makeDecoder()
    let old = try decoder.decode(
      PackageManifest.self, from: example("manifest/valid/two-captures.json"))
    XCTAssertEqual(old.schemaVersion, .v1)
    XCTAssertEqual(old.writtenSchemaVersion, .v1_2)
    XCTAssertEqual(try writtenVersion(old), .string("1.2.0"))
    let new = try decoder.decode(
      PackageManifest.self, from: example("manifest/valid/photo-direction-source.json"))
    XCTAssertEqual(new.schemaVersion, .v1_1)
    XCTAssertEqual(try writtenVersion(new), .string("1.2.0"))
    let sketch = try decoder.decode(
      PackageManifest.self, from: example("manifest/valid/sketch-capture.json"))
    XCTAssertEqual(sketch.schemaVersion, .v1_2)
    XCTAssertEqual(try writtenVersion(sketch), .string("1.2.0"))
    XCTAssertEqual(sketch.files.filter { $0.role.isSketchRole }.map(\.role), [.sketchImage, .sketchMeasurements])
    XCTAssertEqual(ManifestSchemaVersion.current, .v1_2)
  }

  func testAManifestWithARetiredRoleIsWrittenAs1_0_0() throws {
    let legacy = try CaptureContractJSON.makeDecoder().decode(
      PackageManifest.self, from: example("manifest/valid/legacy-spatial-report-1.0.0.json"))
    XCTAssertTrue(legacy.files.contains { $0.role == .spatialReportPDF })
    XCTAssertEqual(legacy.writtenSchemaVersion, .v1)
    XCTAssertEqual(try writtenVersion(legacy), .string("1.0.0"))

    var dropped = legacy
    dropped.files.removeAll { $0.role.isRetired }
    XCTAssertEqual(dropped.writtenSchemaVersion, .v1_2)

    // Built new (as PackageAssembler does) while PlanExport still writes the phone report:
    // 1.1.0 would not allow the file, so it is written as 1.0.0 too.
    var created = legacy
    created.schemaVersion = .current
    XCTAssertEqual(created.writtenSchemaVersion, .v1)
    XCTAssertEqual(try writtenVersion(created), .string("1.0.0"))
    created.files.removeAll { $0.role.isRetired }
    XCTAssertEqual(try writtenVersion(created), .string("1.2.0"))
  }

  func testPhotoDirectionSourceDecodesAndIsOmittedWhenNil() throws {
    let manifest = try CaptureContractJSON.makeDecoder().decode(
      PackageManifest.self, from: example("manifest/valid/photo-direction-source.json"))
    XCTAssertEqual(manifest.files.compactMap { $0.photo?.directionSource }, [.compass, .manual])

    let old = try CaptureContractJSON.makeDecoder().decode(
      PackageManifest.self, from: example("manifest/valid/two-captures.json"))
    XCTAssertEqual(old.files.compactMap(\.photo).map(\.directionSource), [nil])
    let text = String(decoding: try CaptureContractJSON.makeEncoder().encode(old), as: UTF8.self)
    XCTAssertFalse(text.contains("directionSource"))
  }

  func testEncoderDoesNotEscapeSlashesInPaths() throws {
    let url = try XCTUnwrap(ContractFiles.examples(schema: "manifest", kind: "valid").first)
    let reencoded = try Self.codecs["manifest"]!(Data(contentsOf: url))
    let text = String(decoding: reencoded, as: UTF8.self)
    XCTAssertTrue(text.contains("\"Source Register/"))
    XCTAssertFalse(text.contains("\\/"))
  }
}
