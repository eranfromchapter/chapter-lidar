import CaptureContract
import Foundation
import PackageCore
import XCTest

/// F6.AC1: packaging the two-floor fixture produces the guide's folder layout and a manifest that
/// validates and lists every file with the correct sha256.
final class PackageAssemblyTests: XCTestCase {
  private var folder: TemporaryFolder!

  override func setUpWithError() throws {
    folder = try TemporaryFolder()
  }

  override func tearDown() {
    folder.remove()
  }

  /// Assembles `fixture` with its own packageId and sealedAt, so the manifest can be compared
  /// with the fixture's.
  private func assemble(_ fixture: FixturePackage) throws -> SealedPackage {
    let draft = try FixtureDraft.make(fixture, packageId: fixture.manifest.packageId)
    return try PackageAssembler().assemble(
      draft, at: folder.url.appendingPathComponent(fixture.name, isDirectory: true),
      sealedAt: fixture.manifest.sealedAt)
  }

  func testTwoFloorHouseProducesTheGuideFolderLayout() throws {
    let fixture = try FixturePackage("two-floor-house")
    let sealed = try assemble(fixture)
    let visit = fixture.visitId.rawValue

    let written = Set(try fingerprints(under: sealed.root).keys)
    let expected = Set(fixture.filePaths()).union(["Source Register/\(visit)/manifest.json"])
    XCTAssertEqual(written, expected)

    // Top-level folders are capture-app folders of layout.json; downstream folders are not written.
    let topLevel = Set(written.compactMap { $0.split(separator: "/").first.map(String.init) })
    XCTAssertEqual(topLevel, ["Original Exports", "Site Photos", "Field Measurements", "Source Register"])
    for folderName in topLevel {
      let folder = try XCTUnwrap(PackageFolder.allCases.first { $0.name == folderName })
      XCTAssertEqual(folder.producedBy, .captureApp)
    }

    // Original exports and photos grouped by floor, then capture id.
    let captures = try fixture.captures()
    XCTAssertEqual(captures.map(\.areaKey), ["floor-1", "floor-2"])
    for capture in captures {
      let prefix = "Original Exports/\(capture.areaKey)/\(capture.captureId.rawValue)/"
      let names = Set(written.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
      XCTAssertEqual(names, Set(FixtureDraft.perCapture.map(\.fileName)))
      XCTAssertTrue(written.contains("Site Photos/\(capture.areaKey)/\(capture.captureId.rawValue)/photo-0001.jpg"))
    }
    XCTAssertTrue(written.contains("Source Register/\(visit)/capture-record.json"))
    XCTAssertTrue(written.contains("Field Measurements/\(visit)/field-controls.json"))
  }

  func testTwoFloorHouseManifestValidatesAgainstTheSchema() throws {
    let fixture = try FixturePackage("two-floor-house")
    let sealed = try assemble(fixture)
    let onDisk = try Data(contentsOf: sealed.url(for: sealed.manifestPath))
    XCTAssertEqual(onDisk, sealed.manifestData)
    XCTAssertEqual(try Fixtures.manifestValidator().validate(jsonData: onDisk), [])
  }

  func testTwoFloorHouseManifestListsEveryFileWithTheCorrectSha256() throws {
    let fixture = try FixturePackage("two-floor-house")
    let sealed = try assemble(fixture)
    var onDisk = try fingerprints(under: sealed.root)
    onDisk.removeValue(forKey: sealed.manifestPath)

    let listed = sealed.manifest.files
    XCTAssertEqual(listed.count, onDisk.count)
    XCTAssertEqual(Set(listed.map(\.path)).count, listed.count, "paths are unique")
    for entry in listed {
      let digest = try XCTUnwrap(onDisk[entry.path], entry.path)
      XCTAssertEqual(entry.sha256, digest.sha256, entry.path)
      XCTAssertEqual(entry.bytes, digest.bytes, entry.path)
      // And the hash of the bytes as an independent one-shot computation.
      XCTAssertEqual(
        entry.sha256, SHA256.hexDigest(of: try Data(contentsOf: sealed.url(for: entry.path))))
    }

    // Same files, roles, captures, fingerprints, provenance and labels as the fixture's manifest.
    XCTAssertEqual(sealed.manifest, fixture.manifest)
    XCTAssertEqual(sealed.verify(), [])
  }

  func testEveryGoodFixtureAssemblesToItsOwnManifest() throws {
    for name in ["box-room", "l-shaped-room", "two-room-apartment", "two-floor-house"] {
      let fixture = try FixturePackage(name)
      let sealed = try assemble(fixture)
      XCTAssertEqual(sealed.manifest, fixture.manifest, name)
      XCTAssertEqual(try Fixtures.manifestValidator().validate(jsonData: sealed.manifestData), [], name)
      XCTAssertEqual(sealed.verify(), [], name)
    }
  }

  func testDerivedFilesLinkToTheOriginalsTheyCameFrom() throws {
    let fixture = try FixturePackage("two-floor-house")
    let sealed = try assemble(fixture)
    let byPath = Dictionary(uniqueKeysWithValues: sealed.manifest.files.map { ($0.path, $0) })
    for entry in sealed.manifest.files {
      for source in entry.derivedFrom {
        let original = try XCTUnwrap(byPath[source], "\(entry.path) derives from a listed file")
        XCTAssertEqual(original.captureId, entry.captureId)
      }
    }
    let model = try XCTUnwrap(sealed.manifest.files.first { $0.role == .captureModel })
    XCTAssertEqual(model.derivedFrom.count, 1)
    XCTAssertEqual(byPath[model.derivedFrom[0]]?.role, .rawRoomplanJSON)
    let raw = sealed.manifest.files.filter { $0.role == .rawRoomplanJSON || $0.role == .rawDepth || $0.role == .photo }
    XCTAssertTrue(raw.allSatisfy { $0.derivedFrom.isEmpty })
  }

  func testVisitWideFilesCarryNoCaptureAndCaptureFilesCarryOne() throws {
    let sealed = try assemble(try FixturePackage("two-floor-house"))
    for entry in sealed.manifest.files {
      if entry.role.isVisitWide {
        XCTAssertNil(entry.captureId, entry.path)
        XCTAssertNil(entry.areaKey, entry.path)
      } else {
        XCTAssertNotNil(entry.captureId, entry.path)
        XCTAssertNotNil(entry.areaKey, entry.path)
      }
      XCTAssertEqual(entry.photo != nil, entry.role == .photo, entry.path)
    }
  }

  func testSealedPackageIsReadOnlyAndReopensUnchanged() throws {
    let sealed = try assemble(try FixturePackage("box-room"))
    XCTAssertTrue(sealed.isReadOnly())
    let reopened = try SealedPackage.open(at: sealed.root)
    XCTAssertEqual(reopened.manifest, sealed.manifest)
    XCTAssertEqual(reopened.manifestData, sealed.manifestData)
    XCTAssertEqual(reopened.verify(), [])
  }

  func testAnExistingDestinationIsNeverWrittenOver() throws {
    let fixture = try FixturePackage("box-room")
    let sealed = try assemble(fixture)
    let before = try fingerprints(under: sealed.root)
    let draft = try FixtureDraft.make(fixture)
    XCTAssertThrowsError(try PackageAssembler().assemble(draft, at: sealed.root)) { error in
      XCTAssertEqual(error as? PackageError, .destinationExists(sealed.root.path))
    }
    XCTAssertEqual(try fingerprints(under: sealed.root), before)
  }
}

/// The test validator accepts the contract's valid manifest example and rejects every invalid one,
/// so a passing validation above means something.
final class ManifestSchemaValidatorTests: XCTestCase {
  func testContractExamples() throws {
    let validator = try Fixtures.manifestValidator()
    let examples = Fixtures.repositoryRoot.appendingPathComponent("contract/examples/manifest")
    let valid = examples.appendingPathComponent("valid")
    let invalid = examples.appendingPathComponent("invalid")
    let validNames = try FileManager.default.contentsOfDirectory(atPath: valid.path).sorted()
    let invalidNames = try FileManager.default.contentsOfDirectory(atPath: invalid.path).sorted()
    XCTAssertFalse(validNames.isEmpty)
    XCTAssertFalse(invalidNames.isEmpty)
    for name in validNames {
      let data = try Data(contentsOf: valid.appendingPathComponent(name))
      XCTAssertEqual(try validator.validate(jsonData: data), [], name)
    }
    for name in invalidNames {
      let data = try Data(contentsOf: invalid.appendingPathComponent(name))
      XCTAssertFalse(try validator.validate(jsonData: data).isEmpty, name)
    }
  }
}

/// Layout and manifest rules enforced while a draft is built.
final class PackageLayoutRuleTests: XCTestCase {
  private let visitId = LowercaseUUID(rawValue: "d205358c-0394-44af-b86c-69bc3fdd9d21")!
  private let capture = CaptureRef(
    captureId: LowercaseUUID(rawValue: "ba028a66-d76e-4616-b0d6-e3e04e5c9535")!, areaKey: "floor-1")
  private let source = URL(fileURLWithPath: "/dev/null")

  private func input(
    _ role: FileRole, _ name: String, capture: CaptureRef?, derivedFrom: [String] = [],
    photo: PackageManifest.PhotoLabels? = nil, mime: String = "application/octet-stream"
  ) -> PackageFileInput {
    PackageFileInput(
      source: source, role: role, fileName: name, capture: capture, mime: mime,
      generator: "chapter-capture-ios/Test", generatorVersion: "1.0.0", derivedFrom: derivedFrom,
      photo: photo)
  }

  func testPathsFollowLayoutJSON() throws {
    XCTAssertEqual(
      try PackagePaths.path(role: .rawRoomplanJSON, fileName: "roomplan.json", visitId: visitId, capture: capture),
      "Original Exports/floor-1/ba028a66-d76e-4616-b0d6-e3e04e5c9535/roomplan.json")
    XCTAssertEqual(
      try PackagePaths.path(role: .texture, fileName: "textures/wall.png", visitId: visitId, capture: capture),
      "Original Exports/floor-1/ba028a66-d76e-4616-b0d6-e3e04e5c9535/textures/wall.png")
    XCTAssertEqual(
      try PackagePaths.path(role: .photo, fileName: "photo-0001.jpg", visitId: visitId, capture: capture),
      "Site Photos/floor-1/ba028a66-d76e-4616-b0d6-e3e04e5c9535/photo-0001.jpg")
    XCTAssertEqual(
      try PackagePaths.path(role: .captureRecord, fileName: "capture-record.json", visitId: visitId, capture: nil),
      "Source Register/d205358c-0394-44af-b86c-69bc3fdd9d21/capture-record.json")
    XCTAssertEqual(
      try PackagePaths.path(role: .fieldControls, fileName: "field-controls.json", visitId: visitId, capture: nil),
      "Field Measurements/d205358c-0394-44af-b86c-69bc3fdd9d21/field-controls.json")
    XCTAssertEqual(
      PackagePaths.manifestPath(visitId: visitId),
      "Source Register/d205358c-0394-44af-b86c-69bc3fdd9d21/manifest.json")
  }

  func testCaptureRulesOfVisitAndCaptureRoles() {
    XCTAssertThrowsError(
      try PackagePaths.path(role: .captureRecord, fileName: "capture-record.json", visitId: visitId, capture: capture))
    XCTAssertThrowsError(
      try PackagePaths.path(role: .fieldControls, fileName: "field-controls.json", visitId: visitId, capture: capture))
    XCTAssertThrowsError(
      try PackagePaths.path(role: .planDXF, fileName: "plan.dxf", visitId: visitId, capture: nil))
  }

  func testFixedFileNamesAndTheManifestPathAreEnforced() {
    XCTAssertThrowsError(
      try PackagePaths.path(role: .captureRecord, fileName: "record.json", visitId: visitId, capture: nil)
    ) { XCTAssertEqual($0 as? PackageError, .fixedFileName(role: "capture_record", expected: "capture-record.json", got: "record.json")) }
    XCTAssertThrowsError(
      try PackagePaths.path(role: .captureModel, fileName: "model.json", visitId: visitId, capture: capture))
  }

  func testUnsafePathsAndAreaKeysAreRefused() {
    for name in ["", "../x.bin", "a/../b.bin", "./x.bin", "/abs.bin", "a//b.bin", "dir/", "back\\slash.bin", "tab\there.bin"] {
      XCTAssertThrowsError(
        try PackagePaths.path(role: .texture, fileName: name, visitId: visitId, capture: capture), name)
    }
    for key in ["Floor-1", "floor_1", "-floor", "floor-", "floor--1", "", String(repeating: "a", count: 65)] {
      let bad = CaptureRef(captureId: capture.captureId, areaKey: key)
      XCTAssertThrowsError(
        try PackagePaths.path(role: .planPDF, fileName: "plan.pdf", visitId: visitId, capture: bad), key)
    }
    XCTAssertThrowsError(
      try PackagePaths.path(
        role: .texture, fileName: String(repeating: "x", count: 1000) + ".png", visitId: visitId, capture: capture))
  }

  func testDraftRefusesDuplicatesBadProvenanceAndInconsistentCaptures() throws {
    var draft = PackageDraft(visitId: visitId)
    let raw = try draft.add(input(.rawRoomplanJSON, "roomplan.json", capture: capture))
    XCTAssertThrowsError(try draft.add(input(.rawRoomplanJSON, "roomplan.json", capture: capture))) {
      XCTAssertEqual($0 as? PackageError, .duplicatePath(raw))
    }
    // derivedFrom must name files added earlier, once each, never the file itself.
    XCTAssertThrowsError(try draft.add(input(.captureModel, "capture-model.json", capture: capture, derivedFrom: ["Original Exports/floor-1/x.json"])))
    XCTAssertThrowsError(try draft.add(input(.captureModel, "capture-model.json", capture: capture, derivedFrom: [raw, raw])))
    let model = try draft.path(role: .captureModel, fileName: "capture-model.json", capture: capture)
    XCTAssertThrowsError(try draft.add(input(.captureModel, "capture-model.json", capture: capture, derivedFrom: [model])))
    XCTAssertNoThrow(try draft.add(input(.captureModel, "capture-model.json", capture: capture, derivedFrom: [raw])))
    // One capture id, one area key.
    let moved = CaptureRef(captureId: capture.captureId, areaKey: "floor-2")
    XCTAssertThrowsError(try draft.add(input(.planPDF, "plan.pdf", capture: moved))) { error in
      guard case .areaKeyConflict = error as? PackageError else { return XCTFail("\(error)") }
    }
  }

  func testPhotoLabelsAndMetadataRules() {
    var draft = PackageDraft(visitId: visitId)
    let labels = PackageManifest.PhotoLabels(
      room: "Living Room", direction: .north, subject: .general,
      takenAt: UTCTimestamp(secondsSince1970: 1_792_245_000))
    XCTAssertThrowsError(try draft.add(input(.photo, "photo.jpg", capture: capture, mime: "image/jpeg")))
    XCTAssertThrowsError(try draft.add(input(.planPDF, "plan.pdf", capture: capture, photo: labels)))
    XCTAssertThrowsError(try draft.add(input(.planPDF, "plan.pdf", capture: capture, mime: "PDF")))
    XCTAssertNoThrow(try draft.add(input(.photo, "photo.jpg", capture: capture, photo: labels, mime: "image/jpeg")))
    var noGenerator = input(.planDXF, "plan.dxf", capture: capture)
    noGenerator.generator = ""
    XCTAssertThrowsError(try draft.add(noGenerator))
  }

  func testAssemblyNeedsExactlyOneCaptureRecord() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = folder.url.appendingPathComponent("plan.pdf")
    try Data("%PDF-1.7".utf8).write(to: file)
    var draft = PackageDraft(visitId: visitId)
    var plan = input(.planPDF, "plan.pdf", capture: capture, mime: "application/pdf")
    plan.source = file
    try draft.add(plan)
    XCTAssertThrowsError(
      try PackageAssembler().assemble(draft, at: folder.url.appendingPathComponent("package"))
    ) { XCTAssertEqual($0 as? PackageError, .captureRecordCount(0)) }
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.url.appendingPathComponent("package").path))
    XCTAssertThrowsError(try PackageAssembler().assemble(PackageDraft(visitId: visitId), at: folder.url.appendingPathComponent("empty"))) {
      XCTAssertEqual($0 as? PackageError, .emptyPackage)
    }
  }
}
