import CaptureContract
import Foundation
import PackageCore
import XCTest

/// Sealing and revision rules: a sealed package never changes; an edit is revision N+1 with a new
/// packageId and supersedesPackageId.
final class PackageRevisionTests: XCTestCase {
  private var folder: TemporaryFolder!
  private var fixture: FixturePackage!
  private var first: SealedPackage!

  override func setUpWithError() throws {
    folder = try TemporaryFolder()
    fixture = try FixturePackage("two-floor-house")
    first = try PackageAssembler().assemble(
      try FixtureDraft.make(fixture), at: folder.url.appendingPathComponent("revision-1", isDirectory: true))
  }

  override func tearDown() {
    folder.remove()
  }

  func testAChangeMakesTheNextRevisionAndLeavesTheSealedPackageAlone() throws {
    let before = try fingerprints(under: first.root)
    var draft = try PackageDraft.nextRevision(of: first)
    XCTAssertEqual(draft.revision, 2)
    XCTAssertEqual(draft.visitId, first.visitId)
    XCTAssertEqual(draft.supersedesPackageId, first.packageId)
    XCTAssertNotEqual(draft.packageId, first.packageId)

    // Replace one photo with a retaken one.
    let photo = try XCTUnwrap(first.manifest.files.first { $0.role == .photo })
    let retaken = folder.url.appendingPathComponent("retaken.jpg")
    try Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0xFF, 0xD9]).write(to: retaken)
    let capture = CaptureRef(captureId: photo.captureId!, areaKey: photo.areaKey!)
    try draft.replace(
      PackageFileInput(
        source: retaken, role: .photo, fileName: try first.fileName(of: photo), capture: capture,
        mime: "image/jpeg", generator: "chapter-capture-ios/FieldKit", generatorVersion: "1.0.0",
        photo: photo.photo))

    let second = try PackageAssembler().assemble(
      draft, at: folder.url.appendingPathComponent("revision-2", isDirectory: true))
    XCTAssertEqual(second.manifest.revision, 2)
    XCTAssertEqual(second.manifest.supersedesPackageId, first.packageId)
    XCTAssertEqual(try Fixtures.manifestValidator().validate(jsonData: second.manifestData), [])
    XCTAssertEqual(second.verify(), [])
    XCTAssertTrue(second.isReadOnly())

    let replaced = try XCTUnwrap(second.manifest.files.first { $0.path == photo.path })
    XCTAssertEqual(replaced.sha256, SHA256.hexDigest(of: try Data(contentsOf: retaken)))
    XCTAssertNotEqual(replaced.sha256, photo.sha256)
    let unchanged = second.manifest.files.filter { $0.path != photo.path }
    XCTAssertEqual(unchanged, first.manifest.files.filter { $0.path != photo.path })

    // Revision 1 is exactly as sealed.
    XCTAssertEqual(try fingerprints(under: first.root), before)
    XCTAssertEqual(try SealedPackage.open(at: first.root).manifestData, first.manifestData)
  }

  func testTheNextRevisionNeedsANewPackageId() {
    XCTAssertThrowsError(try PackageDraft.nextRevision(of: first, packageId: first.packageId)) { error in
      guard case .invalidRevision = error as? PackageError else { return XCTFail("\(error)") }
    }
  }

  func testACarriedOverFileThatChangedOnDiskIsRefused() throws {
    let draft = try PackageDraft.nextRevision(of: first)
    // Tamper with a sealed file (only possible by undoing its read-only mode first).
    let target = try XCTUnwrap(first.manifest.files.first { $0.role == .roomsCSV })
    let url = first.url(for: target.path)
    let directory = url.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: directory.path)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: url.path)
    try Data("tampered".utf8).write(to: url)

    XCTAssertEqual(first.verify(), ["\(target.path): bytes differ from the manifest"])
    XCTAssertThrowsError(
      try PackageAssembler().assemble(draft, at: folder.url.appendingPathComponent("revision-2"))
    ) { error in
      guard case .sourceChanged = error as? PackageError else { return XCTFail("\(error)") }
    }
  }

  func testRevisionOneHasNoSupersededPackage() throws {
    XCTAssertEqual(first.manifest.revision, 1)
    XCTAssertNil(first.manifest.supersedesPackageId)
    let json = try JSON.parse(first.manifestData)
    XCTAssertNil(json["supersedesPackageId"], "omitted, never null")
  }

  func testOnlyDraftsChange() throws {
    // A sealed package has no mutating API; replacing a path that is not in a draft fails.
    var draft = try PackageDraft.nextRevision(of: first)
    let capture = try XCTUnwrap(first.manifest.files.first { $0.captureId != nil })
    XCTAssertThrowsError(
      try draft.replace(
        PackageFileInput(
          source: folder.url, role: .planPDF, fileName: "other.pdf",
          capture: CaptureRef(captureId: capture.captureId!, areaKey: capture.areaKey!),
          mime: "application/pdf", generator: "chapter-capture-ios/PlanExport", generatorVersion: "1.0.0"))
    ) { error in
      guard case .unknownPath = error as? PackageError else { return XCTFail("\(error)") }
    }
  }
}
