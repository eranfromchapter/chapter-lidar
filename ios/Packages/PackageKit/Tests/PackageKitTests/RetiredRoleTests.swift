import CaptureContract
import Foundation
import PackageCore
import XCTest

/// Manifest 1.1.0 (phone-package §9.2, §11): a v2 package never holds the retired phone report;
/// packages sealed before v2 (manifest 1.0.0, with the report) still open, and their next
/// revision leaves the report out.
final class RetiredRoleTests: XCTestCase {
  private var folder: TemporaryFolder!

  override func setUpWithError() throws {
    folder = try TemporaryFolder()
  }

  override func tearDown() {
    folder.remove()
  }

  private func reportInput(for capture: CaptureRef) -> PackageFileInput {
    PackageFileInput(
      source: folder.url.appendingPathComponent("spatial-report.pdf"), role: .spatialReportPDF,
      fileName: "spatial-report.pdf", capture: capture, mime: "application/pdf",
      generator: "chapter-capture-ios/PlanExport", generatorVersion: "1.0.0")
  }

  func testADraftRefusesTheRetiredRole() throws {
    let fixture = try FixturePackage("box-room")
    var draft = try FixtureDraft.make(fixture)
    let capture = try XCTUnwrap(try fixture.captures().first)
    let count = draft.entries.count
    XCTAssertThrowsError(try draft.add(reportInput(for: capture))) { error in
      XCTAssertEqual(error as? PackageError, .retiredRole(.spatialReportPDF))
    }
    XCTAssertThrowsError(try draft.replace(reportInput(for: capture))) { error in
      XCTAssertEqual(error as? PackageError, .retiredRole(.spatialReportPDF))
    }
    XCTAssertEqual(draft.entries.count, count)
    XCTAssertEqual(
      PackageError.retiredRole(.spatialReportPDF).description,
      "role spatial_report_pdf is retired; a new package never holds it")
  }

  func testTheAssemblerWritesTheCurrentManifestVersion() throws {
    let fixture = try FixturePackage("two-floor-house")
    let sealed = try PackageAssembler().assemble(
      try FixtureDraft.make(fixture), at: folder.url.appendingPathComponent("package"))
    let json = try JSON.parse(sealed.manifestData)
    XCTAssertEqual(json["schemaVersion"]?.string, ManifestSchemaVersion.current.rawValue)
    XCTAssertEqual(sealed.manifest.schemaVersion, .current)
    XCTAssertFalse(sealed.manifest.files.contains { $0.role.isRetired })
    XCTAssertEqual(try Fixtures.manifestValidator().validate(jsonData: sealed.manifestData), [])
  }

  func testLegacyAndCurrentManifestsBothOpen() throws {
    let legacy = try LegacyFixture.sealedCopy(in: folder.url)
    XCTAssertEqual(legacy.manifest.schemaVersion, .v1)
    XCTAssertTrue(legacy.manifest.files.contains { $0.role == .spatialReportPDF })
    XCTAssertEqual(legacy.verify(), [])

    let current = try SealedPackage.open(at: try FixturePackage("box-room").root)
    XCTAssertEqual(current.manifest.schemaVersion, .v1_1)
  }

  func testTheNextRevisionOfALegacyPackageLeavesThePhoneReportOut() throws {
    let legacy = try LegacyFixture.sealedCopy(in: folder.url)
    let report = try XCTUnwrap(legacy.manifest.files.first { $0.role == .spatialReportPDF })
    let draft = try PackageDraft.nextRevision(of: legacy)
    XCTAssertEqual(draft.entries.count, legacy.manifest.files.count - 1)
    XCTAssertFalse(draft.entries.contains { $0.path == report.path })
    XCTAssertFalse(draft.entries.contains { $0.input.derivedFrom.contains(report.path) })

    let second = try PackageAssembler().assemble(
      draft, at: folder.url.appendingPathComponent("revision-2"))
    XCTAssertEqual(second.manifest.schemaVersion, .current)
    XCTAssertEqual(second.manifest.revision, 2)
    XCTAssertEqual(second.manifest.supersedesPackageId, legacy.packageId)
    XCTAssertEqual(try Fixtures.manifestValidator().validate(jsonData: second.manifestData), [])
    // Every other file is carried over byte for byte.
    XCTAssertEqual(
      second.manifest.files.map(\.sha256),
      legacy.manifest.files.filter { !$0.role.isRetired }.map(\.sha256))
  }

  func testADraftOfAnyRevisionNeedsTheRightSupersededPackage() throws {
    let visit = LowercaseUUID()
    let base = LowercaseUUID()
    let draft = try PackageDraft(visitId: visit, revision: 3, supersedesPackageId: base)
    XCTAssertEqual(draft.revision, 3)
    XCTAssertEqual(draft.supersedesPackageId, base)
    XCTAssertTrue(draft.entries.isEmpty)
    XCTAssertNoThrow(try PackageDraft(visitId: visit, revision: 1, supersedesPackageId: nil))

    let invalid: [(Int, LowercaseUUID?)] = [(0, nil), (1, base), (2, nil)]
    for (revision, supersedes) in invalid {
      XCTAssertThrowsError(
        try PackageDraft(visitId: visit, revision: revision, supersedesPackageId: supersedes),
        "revision \(revision)"
      ) { error in
        guard case .invalidRevision = error as? PackageError else { return XCTFail("\(error)") }
      }
    }
    let id = LowercaseUUID()
    XCTAssertThrowsError(
      try PackageDraft(visitId: visit, packageId: id, revision: 2, supersedesPackageId: id))
  }

  func testRemovingAFileOfADraft() throws {
    let fixture = try FixturePackage("box-room")
    var draft = try FixtureDraft.make(fixture)
    let model = try XCTUnwrap(draft.entries.first { $0.input.role == .captureModel })
    // The plan files are derived from the capture model: it cannot go first.
    XCTAssertThrowsError(try draft.remove(path: model.path)) { error in
      guard case .invalidDerivedFrom = error as? PackageError else { return XCTFail("\(error)") }
    }
    let svg = try XCTUnwrap(draft.entries.first { $0.input.role == .planSVG })
    try draft.remove(path: svg.path)
    XCTAssertFalse(draft.entries.contains { $0.path == svg.path })
    XCTAssertThrowsError(try draft.remove(path: svg.path)) { error in
      XCTAssertEqual(error as? PackageError, .unknownPath(svg.path))
    }
  }
}
