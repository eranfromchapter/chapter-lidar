import CaptureContract
import Foundation
import PackageCore
import XCTest

/// Upload state format 2 (phone-package §9.2): when the station registered the package, files the
/// station carried over from the superseded revision, and packages sealed before v2.
final class RevisionUploadTests: XCTestCase {
  private var folder: TemporaryFolder!
  private var world: FakeWorld!
  private let dealId = "fixture-deal-0001"

  override func setUpWithError() throws {
    folder = try TemporaryFolder()
    world = FakeWorld()
  }

  override func tearDown() {
    folder.remove()
  }

  private func seal(_ draft: PackageDraft, _ name: String) throws -> SealedPackage {
    try PackageAssembler().assemble(
      draft, at: folder.url.appendingPathComponent(name, isDirectory: true),
      sealedAt: UTCTimestamp(world.now))
  }

  private func uploader(_ package: SealedPackage, store: UploadStateStore? = nil) throws
    -> PackageUploader
  {
    let world = self.world!
    return try PackageUploader(
      package: package, dealId: dealId, service: FakeStationService(world: world),
      transport: FakeBlobTransport(world: world),
      store: store ?? UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: package.root)),
      now: { world.now }, blockSize: 4096)
  }

  private func uploadedPaths(since index: Int = 0) -> Set<String> {
    Set(
      world.callLog()[index...].compactMap { call -> String? in
        switch call {
        case .putBlob(let path, _), .putBlock(let path, _, _), .putBlockList(let path, _, _):
          return path
        default: return nil
        }
      })
  }

  // MARK: Registered

  func testRegisteredIsTheStationsCreatedAt() async throws {
    let package = try seal(try FixtureDraft.make(try FixturePackage("box-room")), "package")
    // The phone's clock is 5 minutes ahead of the station's: the station's time is kept.
    let world = self.world!
    let phoneNow = world.now.addingTimeInterval(300)
    let uploader = try PackageUploader(
      package: package, dealId: dealId, service: FakeStationService(world: world),
      transport: FakeBlobTransport(world: world),
      store: UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: package.root)),
      now: { phoneNow })
    try await uploader.run()
    let created = try XCTUnwrap(world.createdAt(package.packageId))
    XCTAssertNotEqual(created, UTCTimestamp(phoneNow))
    let registered = await uploader.currentState.registeredAt
    XCTAssertEqual(registered, created)
    XCTAssertEqual(
      try UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: package.root)).load()?
        .registeredAt, created)
  }

  func testAnOlderStationsSessionGivesThePhonesTime() async throws {
    world.omitCreatedAt()
    let package = try seal(try FixtureDraft.make(try FixturePackage("box-room")), "package")
    let world = self.world!
    let phoneNow = world.now.addingTimeInterval(7)
    let uploader = try PackageUploader(
      package: package, dealId: dealId, service: FakeStationService(world: world),
      transport: FakeBlobTransport(world: world),
      store: UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: package.root)),
      now: { phoneNow })
    try await uploader.run()
    let registered = await uploader.currentState.registeredAt
    XCTAssertEqual(registered, UTCTimestamp(phoneNow))
  }

  // MARK: Carry-over

  func testUnchangedFilesOfTheNextRevisionAreCarriedOverAndNeverUploaded() async throws {
    let fixture = try FixturePackage("two-floor-house")
    let first = try seal(try FixtureDraft.make(fixture), "revision-1")
    try await uploader(first).run()

    // Revision 2: one photo retaken, everything else as sealed.
    var draft = try PackageDraft.nextRevision(of: first)
    let photo = try XCTUnwrap(first.manifest.files.first { $0.role == .photo })
    let retaken = folder.url.appendingPathComponent("retaken.jpg")
    try Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0xFF, 0xD9]).write(to: retaken)
    try draft.replace(
      PackageFileInput(
        source: retaken, role: .photo, fileName: try first.fileName(of: photo),
        capture: CaptureRef(captureId: photo.captureId!, areaKey: photo.areaKey!),
        mime: "image/jpeg", generator: "chapter-capture-ios/FieldKit", generatorVersion: "1.0.0",
        photo: photo.photo))
    let second = try seal(draft, "revision-2")

    let before = world.callLog().count
    let result = try await uploader(second).run()
    XCTAssertEqual(result.status, .checksQueued)
    XCTAssertEqual(uploadedPaths(since: before), [photo.path], "only the changed file goes up")

    let state = try XCTUnwrap(
      try UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: second.root)).load())
    XCTAssertTrue(state.isConfirmedByStation)
    XCTAssertEqual(state.carriedOver, Set(second.manifest.files.map(\.path)).subtracting([photo.path]))
    for path in state.carriedOver {
      XCTAssertEqual(world.carriedOverFrom(second.packageId, path: path), first.packageId)
      XCTAssertEqual(state.files.first { $0.path == path }?.phase, .verified)
    }
    // The carried-over files are the very blobs revision 1 stored.
    let record = try XCTUnwrap(second.manifest.files.first { $0.role == .captureRecord }?.path)
    XCTAssertEqual(
      world.storedBlob(packageId: second.packageId, path: record),
      world.storedBlob(packageId: first.packageId, path: record))
  }

  func testNothingIsCarriedOverWhenTheSupersededRevisionNeverArrived() async throws {
    let fixture = try FixturePackage("box-room")
    let first = try seal(try FixtureDraft.make(fixture), "revision-1")
    let second = try seal(try PackageDraft.nextRevision(of: first), "revision-2")
    try await uploader(second).run()
    let state = try XCTUnwrap(
      try UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: second.root)).load())
    XCTAssertTrue(state.carriedOver.isEmpty)
    XCTAssertTrue(state.isConfirmedByStation)
    XCTAssertEqual(uploadedPaths(), Set(second.manifest.files.map(\.path)))
  }

  // MARK: State file versions

  func testAFormat1StateFileIsReadAsFormat2AndResumes() async throws {
    let package = try seal(try FixtureDraft.make(try FixturePackage("box-room")), "package")
    let store = UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: package.root))
    // A state as a v1 build wrote it: no registeredAt, supersededBy or carriedOver.
    let encoded = try CaptureContractJSON.makeEncoder().encode(
      UploadState(package: package, dealId: dealId))
    var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    XCTAssertNil(object["registeredAt"])
    XCTAssertNil(object["carriedOver"])
    object["formatVersion"] = 1
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: store.url)

    let loaded = try XCTUnwrap(try store.load())
    XCTAssertEqual(loaded.formatVersion, 2)
    XCTAssertNil(loaded.registeredAt)
    XCTAssertNil(loaded.supersededBy)
    XCTAssertTrue(loaded.carriedOver.isEmpty)

    let result = try await uploader(package, store: store).run()
    XCTAssertEqual(result.status, .checksQueued)
    let saved = try JSON.parse(try Data(contentsOf: store.url))
    XCTAssertEqual(saved["formatVersion"]?.number, 2)
    XCTAssertNotNil(saved["registeredAt"]?.string)
  }

  func testAnUnknownFormatIsRefused() throws {
    let package = try seal(try FixtureDraft.make(try FixturePackage("box-room")), "package")
    let store = UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: package.root))
    var state = UploadState(package: package, dealId: dealId)
    state.formatVersion = 3
    try store.save(state)
    XCTAssertEqual(try store.load()?.formatVersion, 3)
    XCTAssertThrowsError(try uploader(package, store: store)) { error in
      guard case .stateMismatch = error as? PackageUploadError else { return XCTFail("\(error)") }
    }
  }

  func testSupersededByAndCarriedOverRoundTrip() throws {
    let package = try seal(try FixtureDraft.make(try FixturePackage("box-room")), "package")
    let store = UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: package.root))
    var state = UploadState(package: package, dealId: dealId)
    let next = LowercaseUUID()
    state.supersededBy = next
    state.carriedOver = ["b", "a"]
    state.registeredAt = UTCTimestamp(secondsSince1970: 1_800_000_000)
    try store.save(state)
    XCTAssertEqual(try store.load(), state)
    let json = try JSON.parse(try Data(contentsOf: store.url))
    XCTAssertEqual(json["carriedOver"]?.array?.compactMap(\.string), ["a", "b"], "written sorted")
    XCTAssertEqual(json["supersededBy"]?.string, next.rawValue)
  }

  // MARK: Packages sealed before v2

  func testALegacyPackageStillUploadsAndSeals() async throws {
    let legacy = try LegacyFixture.sealedCopy(in: folder.url)
    let result = try await uploader(legacy).run()
    XCTAssertEqual(result.status, .checksQueued)
    XCTAssertEqual(world.receivedSealBodies().last, legacy.manifestData, "1.0.0 bytes, unchanged")
    XCTAssertEqual(uploadedPaths(), Set(legacy.manifest.files.map(\.path)))
    XCTAssertTrue(uploadedPaths().contains { $0.hasSuffix("spatial-report.pdf") })
  }
}
