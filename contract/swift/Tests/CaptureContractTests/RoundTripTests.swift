import CaptureContract
import Foundation
import XCTest

/// AC2: every valid example decodes and re-encodes to JSON equal to the original.
/// "Equal" is semantic: same keys, same values, numbers compared numerically, key order and
/// whitespace ignored. A dropped field, an added field or a `null` fails the test.
final class RoundTripTests: XCTestCase {
  /// One entry per schema in contract/schema, keyed by the schema name (file name without
  /// `.schema.json`, which is also the example folder name).
  static let codecs: [String: @Sendable (Data) throws -> Data] = [
    "capture-record": { try roundTrip(CaptureRecord.self, $0) },
    "capture-model": { try roundTrip(CaptureModel.self, $0) },
    "field-controls": { try roundTrip(FieldControls.self, $0) },
    "manifest": { try roundTrip(PackageManifest.self, $0) },
    "verdict": { try roundTrip(Verdict.self, $0) },
  ]

  static func roundTrip<T: Codable>(_ type: T.Type, _ data: Data) throws -> Data {
    let value = try CaptureContractJSON.makeDecoder().decode(T.self, from: data)
    return try CaptureContractJSON.makeEncoder().encode(value)
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
        let differences = try JSONValue.parse(original).differences(
          from: JSONValue.parse(reencoded))
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
  }

  func testEncoderDoesNotEscapeSlashesInPaths() throws {
    let url = try XCTUnwrap(ContractFiles.examples(schema: "manifest", kind: "valid").first)
    let reencoded = try Self.codecs["manifest"]!(Data(contentsOf: url))
    let text = String(decoding: reencoded, as: UTF8.self)
    XCTAssertTrue(text.contains("\"Source Register/"))
    XCTAssertFalse(text.contains("\\/"))
  }
}
