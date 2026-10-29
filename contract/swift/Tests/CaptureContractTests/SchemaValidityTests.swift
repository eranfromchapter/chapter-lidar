import CaptureContract
import Foundation
import XCTest

/// What the Swift types write is valid against the JSON Schemas, not only equal to what they
/// read: the station validates every manifest at seal (422 otherwise), so a manifest the app
/// writes must pass `manifest.schema.json`, version rules included.
final class SchemaValidityTests: XCTestCase {
  private func validator(_ schema: String) throws -> SchemaValidator {
    try SchemaValidator(schemaURL: ContractFiles.schemaURL("\(schema).schema.json"))
  }

  private func example(_ path: String) throws -> Data {
    try Data(contentsOf: ContractFiles.examplesDirectory.appendingPathComponent(path))
  }

  private func written(_ manifest: PackageManifest) throws -> JSONValue {
    try JSONValue.parse(CaptureContractJSON.makeEncoder().encode(manifest))
  }

  // MARK: The validator itself

  /// The validator agrees with the examples (the TypeScript tests check the same files with
  /// Ajv), so a passing validation below means something.
  func testTheValidatorAcceptsEveryValidExampleAndRejectsEveryInvalidOne() throws {
    for schema in RoundTripTests.codecs.keys.sorted() {
      let validator = try validator(schema)
      for url in try ContractFiles.examples(schema: schema, kind: "valid") {
        XCTAssertEqual(
          try validator.validate(jsonData: Data(contentsOf: url)), [],
          "\(schema)/valid/\(url.lastPathComponent)")
      }
      for url in try ContractFiles.examples(schema: schema, kind: "invalid") {
        XCTAssertNotEqual(
          try validator.validate(jsonData: Data(contentsOf: url)), [],
          "\(schema)/invalid/\(url.lastPathComponent) passes the validator")
      }
    }
  }

  // MARK: Every document the Swift types write

  func testEveryReencodedValidExampleIsValid() throws {
    for schema in RoundTripTests.codecs.keys.sorted() {
      let validator = try validator(schema)
      for url in try ContractFiles.examples(schema: schema, kind: "valid") {
        let reencoded = try RoundTripTests.codecs[schema]!(Data(contentsOf: url))
        XCTAssertEqual(
          try validator.validate(jsonData: reencoded), [],
          "\(schema)/valid/\(url.lastPathComponent) re-encoded")
      }
    }
  }

  // MARK: Manifests

  /// A manifest built as `PackageAssembler` builds it (default `schemaVersion`) while the app
  /// still writes the phone report: written as 1.0.0, the only version that allows the file.
  func testANewManifestThatStillListsThePhoneReportIsWrittenAsValid1_0_0() throws {
    let legacy = try CaptureContractJSON.makeDecoder().decode(
      PackageManifest.self, from: example("manifest/valid/legacy-spatial-report-1.0.0.json"))
    let created = PackageManifest(
      packageId: legacy.packageId, visitId: legacy.visitId, revision: 1,
      sealedAt: legacy.sealedAt, files: legacy.files)
    XCTAssertEqual(created.schemaVersion, .current)
    XCTAssertTrue(created.files.contains { $0.role == .spatialReportPDF })

    let json = try written(created)
    guard case .object(let members) = json else { return XCTFail("not an object") }
    XCTAssertEqual(members["schemaVersion"], .string("1.0.0"))
    XCTAssertEqual(try validator("manifest").validate(json), [])
  }

  func testANewManifestWithoutARetiredRoleIsWrittenAsValid1_2_0() throws {
    let source = try CaptureContractJSON.makeDecoder().decode(
      PackageManifest.self, from: example("manifest/valid/photo-direction-source.json"))
    let created = PackageManifest(
      packageId: source.packageId, visitId: source.visitId, revision: 1,
      sealedAt: source.sealedAt, files: source.files)

    let json = try written(created)
    guard case .object(let members) = json else { return XCTFail("not an object") }
    XCTAssertEqual(members["schemaVersion"], .string("1.2.0"))
    XCTAssertEqual(try validator("manifest").validate(json), [])
  }

  /// The phone report (1.0.0 only) next to `photo.directionSource` (1.1.0 only) fits neither
  /// version, so the manifest is not written at all instead of failing at the station's seal.
  func testAManifestWithARetiredRoleAndADirectionSourceIsNotWritten() throws {
    var manifest = try CaptureContractJSON.makeDecoder().decode(
      PackageManifest.self, from: example("manifest/valid/legacy-spatial-report-1.0.0.json"))
    let photo = try XCTUnwrap(manifest.files.firstIndex { $0.photo != nil })
    manifest.files[photo].photo?.directionSource = .compass

    XCTAssertThrowsError(try CaptureContractJSON.makeEncoder().encode(manifest)) { error in
      guard case EncodingError.invalidValue(_, let context) = error else {
        return XCTFail("unexpected error \(error)")
      }
      let message = context.debugDescription
      XCTAssertTrue(message.contains("spatial_report_pdf"), message)
      XCTAssertTrue(message.contains("directionSource"), message)
    }

    manifest.files.removeAll { $0.role.isRetired }
    XCTAssertEqual(try validator("manifest").validate(try written(manifest)), [])
  }
}
