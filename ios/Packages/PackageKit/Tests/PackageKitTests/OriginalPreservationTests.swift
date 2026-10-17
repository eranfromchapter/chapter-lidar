import CaptureContract
import Foundation
import PackageCore
import XCTest

/// F6.AC2: original files are byte-identical before and after packaging and upload.
final class OriginalPreservationTests: XCTestCase {
  private var folder: TemporaryFolder!

  override func setUpWithError() throws {
    folder = try TemporaryFolder()
  }

  override func tearDown() {
    folder.remove()
  }

  /// Fingerprint, size and modification time of every file under `root`.
  private func snapshot(_ root: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    for (path, digest) in try fingerprints(under: root) {
      let attributes = try FileManager.default.attributesOfItem(
        atPath: root.appendingPathComponent(path).path)
      let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
      result[path] = "\(digest.sha256) \(digest.bytes) \(modified)"
    }
    return result
  }

  func testOriginalsAreByteIdenticalBeforeAndAfterPackagingAndUpload() async throws {
    let fixture = try FixturePackage("two-floor-house")
    // The originals as the app holds them before packaging (a copy of the fixture, so the test
    // can also prove nothing was added to or removed from the sources' folder).
    let sources = folder.url.appendingPathComponent("sources", isDirectory: true)
    try FileManager.default.copyItem(at: fixture.root, to: sources)
    let originalBytes = try Dictionary(
      uniqueKeysWithValues: fixture.filePaths().map { path in
        (path, try Data(contentsOf: fixture.url(for: path)))
      })
    let before = try snapshot(sources)

    let draft = try FixtureDraft.make(fixture) { path in
      var url = sources
      for segment in path.split(separator: "/") { url.appendPathComponent(String(segment)) }
      return url
    }
    let sealed = try PackageAssembler().assemble(
      draft, at: folder.url.appendingPathComponent("package", isDirectory: true))
    XCTAssertEqual(try snapshot(sources), before, "packaging only reads the originals")

    // Every packaged file has exactly its original's bytes, under the same file name.
    for entry in sealed.manifest.files {
      let packaged = try Data(contentsOf: sealed.url(for: entry.path))
      XCTAssertEqual(packaged, originalBytes[entry.path], entry.path)
      XCTAssertEqual(
        sealed.url(for: entry.path).lastPathComponent,
        fixture.url(for: entry.path).lastPathComponent)
    }

    let world = FakeWorld()
    let uploader = try PackageUploader(
      package: sealed, dealId: "fixture-deal-0001", service: FakeStationService(world: world),
      transport: FakeBlobTransport(world: world),
      store: UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: sealed.root)),
      now: { world.now }, blockSize: 8192)
    let result = try await uploader.run()
    XCTAssertEqual(result.status, .checksQueued)

    // After upload: sources and package unchanged, and what the station stores is the original.
    XCTAssertEqual(try snapshot(sources), before, "upload only reads")
    XCTAssertEqual(sealed.verify(), [])
    for entry in sealed.manifest.files {
      XCTAssertEqual(
        world.storedBlob(packageId: sealed.packageId, path: entry.path), originalBytes[entry.path],
        entry.path)
      XCTAssertEqual(try Data(contentsOf: sealed.url(for: entry.path)), originalBytes[entry.path])
    }
    // The fixture itself is untouched too.
    for (path, bytes) in originalBytes {
      XCTAssertEqual(try Data(contentsOf: fixture.url(for: path)), bytes, path)
    }
  }

  func testOriginalsSurviveAKilledAndResumedUpload() async throws {
    let fixture = try FixturePackage("box-room")
    let sealed = try PackageAssembler().assemble(
      try FixtureDraft.make(fixture), at: folder.url.appendingPathComponent("package", isDirectory: true))
    let before = try snapshot(sealed.root)
    let world = FakeWorld()
    world.addFault(
      Fault(timing: .after, error: SimulatedKill()) { call in
        if case .putBlock(_, _, 8192) = call { return true }
        return false
      })
    let store = UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: sealed.root))
    func uploader() throws -> PackageUploader {
      try PackageUploader(
        package: sealed, dealId: "fixture-deal-0001", service: FakeStationService(world: world),
        transport: FakeBlobTransport(world: world), store: store, now: { world.now },
        blockSize: 4096)
    }
    do {
      try await uploader().run()
      XCTFail("expected the simulated kill")
    } catch is SimulatedKill {}
    XCTAssertEqual(try snapshot(sealed.root), before)
    try await uploader().run()
    XCTAssertEqual(try snapshot(sealed.root), before)
    for entry in sealed.manifest.files {
      XCTAssertEqual(
        world.storedBlob(packageId: sealed.packageId, path: entry.path),
        try Data(contentsOf: fixture.url(for: entry.path)), entry.path)
    }
  }

  func testCopiesAreRegularFilesEvenWhenTheSourceIsASymbolicLink() throws {
    let fixture = try FixturePackage("box-room")
    func permissions() throws -> [String: Int] {
      try Dictionary(
        uniqueKeysWithValues: fixture.filePaths().map { path in
          let attributes = try FileManager.default.attributesOfItem(atPath: fixture.url(for: path).path)
          return (path, (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1)
        })
    }
    let fixturePermissions = try permissions()
    let links = try TemporaryFolder()
    let draft = try FixtureDraft.make(fixture) { path in
      let link = links.url.appendingPathComponent(UUID().uuidString)
      try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.url(for: path))
      return link
    }
    let sealed = try PackageAssembler().assemble(
      draft, at: folder.url.appendingPathComponent("package", isDirectory: true))
    for entry in sealed.manifest.files {
      let attributes = try FileManager.default.attributesOfItem(atPath: sealed.url(for: entry.path).path)
      XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular, entry.path)
      XCTAssertEqual(try Data(contentsOf: sealed.url(for: entry.path)), try Data(contentsOf: fixture.url(for: entry.path)))
    }
    // Sealing locked the copies, not the linked originals; test cleanup leaves them alone too.
    XCTAssertEqual(try permissions(), fixturePermissions)
    links.remove()
    XCTAssertEqual(try permissions(), fixturePermissions)
  }

  func testASourceThatNoLongerMatchesItsExpectedFingerprintIsRefused() throws {
    let fixture = try FixturePackage("box-room")
    var draft = PackageDraft(visitId: fixture.visitId)
    let record = try XCTUnwrap(fixture.manifest.files.first { $0.role == .captureRecord })
    try draft.add(
      PackageFileInput(
        source: fixture.url(for: record.path), role: .captureRecord, fileName: "capture-record.json",
        mime: "application/json", generator: "chapter-capture-ios/CaptureRecord",
        generatorVersion: "1.0.0", expected: FileDigest(sha256: String(repeating: "0", count: 64), bytes: record.bytes)))
    let root = folder.url.appendingPathComponent("package", isDirectory: true)
    XCTAssertThrowsError(try PackageAssembler().assemble(draft, at: root)) { error in
      guard case .sourceChanged = error as? PackageError else { return XCTFail("\(error)") }
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "no partial package at the root")
  }

  func testAMissingOrDirectorySourceIsRefused() throws {
    let fixture = try FixturePackage("box-room")
    var draft = PackageDraft(visitId: fixture.visitId)
    try draft.add(
      PackageFileInput(
        source: folder.url, role: .captureRecord, fileName: "capture-record.json",
        mime: "application/json", generator: "chapter-capture-ios/CaptureRecord", generatorVersion: "1.0.0"))
    XCTAssertThrowsError(
      try PackageAssembler().assemble(draft, at: folder.url.appendingPathComponent("package"))
    ) { error in
      XCTAssertEqual(error as? PackageError, .notARegularFile(path: folder.url.path))
    }
  }
}
