import CaptureContract
import CaptureCore
import FieldRules
import Foundation
import PackageCore
import PhotoStore
import StationClient
import XCTest

@testable import AppCore

/// "Delete all photos" (field-test and UI-test modes): every copy of site-photo bytes the app
/// holds goes, everything else stays byte for byte, and the app keeps working with sealed
/// packages whose photos are gone.
final class PhotoEraserTests: XCTestCase {
  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDownWithError() throws {
    if let base { Fixtures.removeTemporaryDirectory(base) }
  }

  // MARK: Fixture

  /// Two visits with photos in every place the app keeps them, plus the folders outside the
  /// visits: visit A sealed and confirmed by the (stub) station, visit B sealed and not uploaded.
  private struct Tree {
    let visitsRoot: URL
    let scratch: URL
    let temporary: URL
    let caches: URL
    let a: SealedFixture
    let b: SealedFixture
    let storage: UITestBlobStorage
    let station: UITestStationTransport
    let client: StationAPI
    /// The SHA-256 of every photo planted or saved (originals, copies, previews).
    var photoDigests: Set<String> = []
    /// Package-relative paths of visit A's photo blobs at the stub station.
    var photoBytes: [Data] = []

    var eraser: PhotoEraser {
      PhotoEraser(
        visitsRoots: [visitsRoot], scratchFolders: [scratch], sweptFolders: [temporary, caches],
        now: { Date(timeIntervalSince1970: 1_792_243_200) })
    }
  }

  /// A small synthetic HEIC header (an "ftyp heic" box), as a preview or thumbnail would start.
  private static let heicThumbnail: Data = {
    var data = Data([0x00, 0x00, 0x00, 0x18])
    data.append(contentsOf: Array("ftypheic".utf8))
    data.append(contentsOf: [UInt8](repeating: 0x2A, count: 64))
    return data
  }()

  private func write(_ data: Data, _ url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
  }

  private func makeTree() async throws -> Tree {
    let visitsRoot = base.appendingPathComponent("Visits", isDirectory: true)
    try FileManager.default.createDirectory(at: visitsRoot, withIntermediateDirectories: true)
    let a = try SealedFixture("box-room", in: visitsRoot)
    let b = try SealedFixture("two-room-apartment", in: visitsRoot)
    let storage = UITestBlobStorage()
    let station = UITestStationTransport(storage: storage)
    let client = StationAPI(
      configuration: try .init(stationURL: UITestStationTransport.stationURL),
      tokenProvider: UITestTokenProvider(), transport: station)
    var tree = Tree(
      visitsRoot: visitsRoot, scratch: base.appendingPathComponent("Caches/upload-scratch"),
      temporary: base.appendingPathComponent("tmp"), caches: base.appendingPathComponent("Caches"),
      a: a, b: b, storage: storage, station: station, client: client)

    // visit.json and room-names.json of both visits (they must stay).
    for fixture in [a, b] {
      XCTAssertNotNil(VisitStore.loadOrMigrate(fixture.visit.workspace))
      try write(
        Data(#"{"formatVersion":1,"captures":{}}"#.utf8), fixture.visit.workspace.roomNamesURL)
    }

    // Visit A is uploaded to the stub station and confirmed.
    let coordinator = UploadCoordinator(
      package: a.sealed, dealId: "UITEST-0001", service: StationUploadService(client: client),
      transport: UITestBlobTransport(storage: storage),
      statusSource: ScriptedStatusSource([.failure(StationAPIError.offline)]),
      sleep: { _ in throw CancellationError() })
    coordinator.start()
    await coordinator.waitUntilIdle()
    XCTAssertTrue(coordinator.snapshot.isConfirmedByStation, "visit A uploaded")

    let photoA = try XCTUnwrap(a.visit.photos.first)
    let bytesA = try Data(
      contentsOf: a.visit.workspace.photosRoot.appendingPathComponent(photoA.path))
    let bytesB = try Data(
      contentsOf: b.visit.workspace.photosRoot.appendingPathComponent(
        try XCTUnwrap(b.visit.photos.first).path))
    let capture = "floor-1/\(photoA.captureId.rawValue)"
    let ws = a.visit.workspace
    let draft = a.plan.draftFolder

    // Copies and previews a writer of photo data could leave anywhere.
    try write(bytesA, ws.photosRoot.appendingPathComponent("previews/photo-0001-preview.jpg"))
    try write(
      Self.heicThumbnail,
      ws.photosRoot.appendingPathComponent("Site Photos/\(capture)/.thumb-0001.heic"))
    try write(bytesA, draft.appendingPathComponent("Site Photos/\(capture)/photo-0001.jpg"))
    try write(bytesA, draft.appendingPathComponent("notes/attachment.dat"))
    let staging = ws.packagesRoot.appendingPathComponent(
      ".\(a.plan.draft.packageId.rawValue).assembling-\(UUID().uuidString.lowercased())")
    try write(bytesA, staging.appendingPathComponent("Site Photos/\(capture)/photo-0001.jpg"))
    try write(
      Data(#"{"scan":true}"#.utf8),
      staging.appendingPathComponent("Original Exports/\(capture)/roomplan.json"))
    try write(bytesB, ws.root.appendingPathComponent("legacy-photo.JPEG"))
    try write(bytesA.prefix(4096), tree.scratch.appendingPathComponent("0123abcd.block"))
    try write(Data("<BlockList/>".utf8), tree.scratch.appendingPathComponent("0123abcd.blocklist"))
    try write(bytesB, tree.temporary.appendingPathComponent("camera-capture.heic"))
    try write(bytesA, tree.caches.appendingPathComponent("com.apple.nsurl/fsCachedData/7F3A"))
    // Not photos: they stay.
    try write(Data(repeating: 7, count: 300), tree.temporary.appendingPathComponent("scan-x.usdz"))
    try write(
      Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + [UInt8](repeating: 1, count: 40)),
      tree.temporary.appendingPathComponent("floorplan-x/imperial/floorplan.png"))
    try write(Data("%PDF-1.7".utf8), tree.temporary.appendingPathComponent("floorplan-x/imperial/floorplan.pdf"))
    try write(Data(#"{"projects":[]}"#.utf8), tree.caches.appendingPathComponent("projects.json"))

    for fixture in [a, b] {
      for photo in fixture.visit.photos { tree.photoDigests.insert(photo.sha256) }
    }
    tree.photoDigests.formUnion([
      digest(bytesA), digest(bytesB), digest(Self.heicThumbnail),
    ])
    tree.photoBytes = [bytesA, bytesB]
    return tree
  }

  // MARK: Helpers

  private func digest(_ data: Data) -> String { PackageCore.SHA256.hexDigest(of: data) }

  private func files(under root: URL) -> [URL] {
    var result: [URL] = []
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    while let url = enumerator?.nextObject() as? URL {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        !isDirectory.boolValue
      {
        result.append(url.resolvingSymlinksInPath())
      }
    }
    return result.sorted { $0.path < $1.path }
  }

  private func digests(under root: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    for url in files(under: root) { result[url.path] = digest(try Data(contentsOf: url)) }
    return result
  }

  /// A photograph by extension or by its first bytes (JPEG, or an "ftyp" box of a HEIC brand),
  /// judged here independently of `PhotoEraser`.
  private func looksLikePhoto(_ url: URL) throws -> Bool {
    if ["heic", "heif", "hif", "jpg", "jpeg", "jpe"].contains(url.pathExtension.lowercased()) {
      return true
    }
    let head = [UInt8](try Data(contentsOf: url).prefix(12))
    if head.count >= 3, head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return true }
    if head.count >= 12, Array(head[4..<8]) == Array("ftyp".utf8) {
      let brand = String(decoding: head[8..<12], as: UTF8.self)
      return ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].contains(brand)
    }
    return false
  }

  /// Files that must survive: everything but photos, photo folders, the photo index and the
  /// upload scratch.
  private func keptFiles(_ tree: Tree, digests: [String: String]) throws -> [String: String] {
    try digests.filter { path, _ in
      let url = URL(fileURLWithPath: path)
      let parts = url.pathComponents
      if parts.contains("Site Photos") { return false }
      if parts.contains("photos") { return false }
      if path.hasPrefix(tree.scratch.resolvingSymlinksInPath().path + "/") { return false }
      return try !looksLikePhoto(url)
    }
  }

  // MARK: Tests

  func testEveryPhotoCopyGoesAndEverythingElseStaysByteForByte() async throws {
    let tree = try await makeTree()
    let before = try digests(under: base)
    let kept = try keptFiles(tree, digests: before)
    // The tree really holds photos in every place, and files that must stay.
    XCTAssertGreaterThanOrEqual(
      before.values.filter { tree.photoDigests.contains($0) }.count, 12)
    XCTAssertTrue(kept.keys.contains { $0.hasSuffix("/roomplan.json") })
    XCTAssertTrue(kept.keys.contains { $0.hasSuffix("/plan.png") || $0.hasSuffix(".png") })
    XCTAssertTrue(kept.keys.contains { $0.hasSuffix("/manifest.json") })
    XCTAssertTrue(kept.keys.contains { $0.hasSuffix("/capture-record.json") })
    XCTAssertTrue(kept.keys.contains { $0.hasSuffix("/field-controls.json") })
    XCTAssertTrue(kept.keys.contains { $0.hasSuffix("/visit.json") })
    XCTAssertTrue(kept.keys.contains { $0.hasSuffix("/room-names.json") })
    XCTAssertTrue(kept.keys.contains { $0.hasSuffix(".upload-state.json") })

    let result = tree.eraser.eraseAll()

    XCTAssertEqual(result.failures, [])
    XCTAssertEqual(result.records, tree.a.visit.photos.count + tree.b.visit.photos.count)
    XCTAssertEqual(result.photos, tree.photoDigests.count)
    XCTAssertEqual(result.sealedPackages, 2)
    XCTAssertEqual(result.scratchFiles, 2)
    XCTAssertGreaterThanOrEqual(result.files, 12)
    XCTAssertEqual(result.message, "Deleted \(tree.photoDigests.count) photos")

    let after = try digests(under: base)
    // No image file and no photo's bytes anywhere.
    for (path, sha) in after {
      XCTAssertFalse(try looksLikePhoto(URL(fileURLWithPath: path)), "photo left: \(path)")
      XCTAssertFalse(tree.photoDigests.contains(sha), "photo bytes left: \(path)")
      XCTAssertFalse(path.contains("/Site Photos/"), "photo folder left: \(path)")
    }
    for (path, sha) in after where !path.hasSuffix(".photos-erased.json") {
      let data = try Data(contentsOf: URL(fileURLWithPath: path))
      for photo in tree.photoBytes {
        XCTAssertNil(data.range(of: photo.prefix(2048)), "photo bytes inside \(path) (\(sha))")
      }
    }
    XCTAssertTrue(files(under: tree.scratch).isEmpty, "upload scratch emptied")
    // Scans, exports, plans, controls, records, manifests and states: byte for byte.
    for (path, sha) in kept {
      XCTAssertEqual(after[path], sha, "changed or missing: \(path)")
    }
    // Nothing new but the photo indexes and the two records.
    let added = Set(after.keys).subtracting(before.keys)
    XCTAssertEqual(added.filter { !$0.hasSuffix(".photos-erased.json") }, [])
    XCTAssertEqual(added.count, 2)

    // photo-records.json: a valid, empty list; the store opens with no photo.
    for fixture in [tree.a, tree.b] {
      let index = fixture.visit.workspace.photosRoot.appendingPathComponent(
        PhotoRecordStore.indexPath)
      let records = try CaptureContractJSON.makeDecoder().decode(
        [PhotoRecord].self, from: Data(contentsOf: index))
      XCTAssertEqual(records, [])
      let store = try PhotoRecordStore(
        files: DiskPhotoFileStore(root: fixture.visit.workspace.photosRoot))
      XCTAssertEqual(store.records, [])
      XCTAssertEqual(
        try FileManager.default.contentsOfDirectory(atPath: fixture.visit.workspace.photosRoot.path),
        [PhotoRecordStore.indexPath])
    }

    // Sealed packages: still open, read-only, only their photos missing, the erasure recorded.
    for fixture in [tree.a, tree.b] {
      let package = try SealedPackage.open(at: fixture.sealed.root)
      XCTAssertEqual(package.manifestData, fixture.sealed.manifestData)
      XCTAssertTrue(package.isReadOnly())
      let photoPaths = package.manifest.files.filter { $0.role == .photo }.map(\.path)
      XCTAssertFalse(photoPaths.isEmpty)
      XCTAssertEqual(
        Set(package.verify()), Set(photoPaths.map { "\($0): missing or unreadable" }))
      let record = try XCTUnwrap(PhotosErasedRecord.load(forPackageAt: package.root))
      XCTAssertEqual(record.packageId, package.packageId)
      XCTAssertEqual(record.paths, photoPaths)
      XCTAssertTrue(PhotosErasedRecord.isErased(packageAt: package.root))
    }

    // A second run deletes nothing and changes nothing.
    let second = tree.eraser.eraseAll()
    XCTAssertEqual(second, PhotoErasureResult())
    XCTAssertEqual(second.message, "No photos to delete")
    XCTAssertEqual(try digests(under: base), after)
  }

  func testThePackagesKeepWorkingWithoutTheirPhotos() async throws {
    let tree = try await makeTree()
    XCTAssertEqual(
      PendingUploads.find(visitsRoot: tree.visitsRoot).map(\.package.packageId),
      [tree.b.sealed.packageId], "visit B waits for the station")

    _ = tree.eraser.eraseAll()

    // Visit B (not confirmed): never uploaded again, and says why.
    XCTAssertTrue(PendingUploads.find(visitsRoot: tree.visitsRoot).isEmpty)
    XCTAssertEqual(
      PackageProgress(package: tree.b.sealed, live: nil).progress, .uploadStopped)
    let counting = CountingService()
    let stopped = UploadCoordinator(
      package: tree.b.sealed, dealId: "UITEST-0001", service: counting,
      transport: UploadCoordinatorTests.NoTransport(),
      statusSource: ScriptedStatusSource([.failure(StationAPIError.offline)]),
      sleep: { _ in throw CancellationError() })
    XCTAssertTrue(stopped.snapshot.photosErased)
    stopped.start()
    await stopped.waitUntilIdle()
    let snapshot = stopped.snapshot
    XCTAssertEqual(snapshot.phase, .stopped(PhotosErasedText.stopped))
    XCTAssertEqual(snapshot.title, "Upload stopped")
    XCTAssertTrue(snapshot.photosErased)
    XCTAssertEqual(counting.calls, 0, "nothing is sent to the station")
    XCTAssertEqual(
      snapshot.stoppedNote(canRetry: false, canReseal: true),
      "Its scans, plans and field controls stay on this phone. Re-seal to upload the files as "
        + "they are on this phone now as revision 2.")
    stopped.retry()
    await stopped.waitUntilIdle()
    XCTAssertEqual(stopped.snapshot.phase, .stopped(PhotosErasedText.stopped))

    // Visit A (confirmed): follows the station as before, and says its photos were erased.
    let confirmed = UploadCoordinator(
      package: tree.a.sealed, dealId: "UITEST-0001",
      service: StationUploadService(client: tree.client),
      transport: UploadCoordinatorTests.NoTransport(),
      statusSource: ScriptedStatusSource([.failure(StationAPIError.offline)]),
      sleep: { _ in throw CancellationError() })
    confirmed.start()
    await confirmed.waitUntilIdle()
    XCTAssertEqual(confirmed.snapshot.activity, .confirmed)
    XCTAssertTrue(confirmed.snapshot.photosErased)
    XCTAssertEqual(PackageProgress(package: tree.a.sealed, live: nil).progress, .checking)

    // Revision 2 of visit B: none of the erased photos is carried over; a photo taken since is.
    let store = try PhotoRecordStore(
      files: DiskPhotoFileStore(root: tree.b.visit.workspace.photosRoot))
    let builder = tree.b.builder
    let withoutPhotos = try builder.revisionPlan(
      base: tree.b.sealed, record: tree.b.visit.record, photos: store.records,
      controls: tree.b.visit.controls)
    XCTAssertFalse(withoutPhotos.draft.entries.contains { $0.input.role == .photo })
    let old = try XCTUnwrap(tree.b.visit.photos.first)
    let fresh = try store.save(
      original: tree.photoBytes[0],
      capture: FieldControls.CaptureRef(captureId: old.captureId, areaKey: old.areaKey),
      labels: old.labels)
    XCTAssertEqual(fresh.path, old.path, "the numbering starts again at photo-0001")
    let revision = try builder.revisionPlan(
      base: tree.b.sealed, record: tree.b.visit.record, photos: store.records,
      controls: tree.b.visit.controls)
    let photos = revision.draft.entries.filter { $0.input.role == .photo }
    XCTAssertEqual(photos.map(\.path), [fresh.path])
    XCTAssertEqual(photos.first?.input.expected?.sha256, fresh.sha256)
    let sealed = try PackageAssembler().assemble(
      revision.draft,
      at: tree.b.visit.workspace.packageURL(packageId: revision.draft.packageId.rawValue))
    XCTAssertEqual(sealed.verify(), [])
    XCTAssertEqual(sealed.manifest.files.filter { $0.role == .photo }.map(\.sha256), [fresh.sha256])
  }

  func testTheStubStationLetsGoOfThePhotoBlobs() async throws {
    let tree = try await makeTree()
    let stored = tree.storage.locations.compactMap { tree.storage.blob(at: $0) }
    let photoCount = tree.a.sealed.manifest.files.filter { $0.role == .photo }.count
    XCTAssertEqual(stored.count, tree.a.sealed.manifest.files.count)
    XCTAssertEqual(stored.filter { tree.photoDigests.contains(digest($0)) }.count, photoCount)

    XCTAssertEqual(tree.station.erasePhotoBlobs(), photoCount)

    let left = tree.storage.locations.compactMap { tree.storage.blob(at: $0) }
    XCTAssertEqual(left.count, tree.a.sealed.manifest.files.count - photoCount)
    XCTAssertTrue(left.allSatisfy { PhotoFormat.detect($0) == nil })
    XCTAssertTrue(left.allSatisfy { !tree.photoDigests.contains(digest($0)) })
    XCTAssertEqual(tree.station.erasePhotoBlobs(), 0, "a second run removes nothing")
  }

  func testPhotoFilesAreKnownByTheirBytesOrTheirExtension() throws {
    let folder = base.appendingPathComponent("kinds")
    let cases: [(String, Data, Bool)] = [
      ("a.jpg", Data("x".utf8), true),
      ("b.HEIC", Data("x".utf8), true),
      ("c.bin", Data([0xFF, 0xD8, 0xFF, 0xE1, 0, 0]), true),
      ("d", Self.heicThumbnail, true),
      ("e.png", Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), false),
      ("f.json", Data("{}".utf8), false),
      ("g.las", Data("LASF".utf8), false),
      ("h", Data(), false),
    ]
    for (name, data, _) in cases { try write(data, folder.appendingPathComponent(name)) }
    for (name, _, isPhoto) in cases {
      XCTAssertEqual(PhotoEraser.isPhotoFile(folder.appendingPathComponent(name)), isPhoto, name)
    }
  }

  func testTheWords() {
    XCTAssertEqual(DeletePhotosText.result(deleted: 0), "No photos to delete")
    XCTAssertEqual(DeletePhotosText.result(deleted: 1), "Deleted 1 photo")
    XCTAssertEqual(DeletePhotosText.result(deleted: 12), "Deleted 12 photos")
    XCTAssertEqual(
      DeletePhotosText.result(deleted: 3, failures: 1),
      "Deleted 3 photos. 1 file could not be deleted.")
    XCTAssertEqual(DeletePhotosText.title, "Delete all photos?")
    XCTAssertEqual(
      DeletePhotosText.message,
      "This erases every site photo Space Capture holds on this phone, including the copies in "
        + "drafts and sealed packages. Scans, plans and field controls stay. This cannot be "
        + "undone.")
    XCTAssertEqual(PhotosErasedText.note, "Photos erased on this phone")
  }
}

/// A station that counts every call and refuses it.
private final class CountingService: PackageUploadService, @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var calls: Int { lock.withLock { count } }

  private func called() -> Error {
    lock.withLock { count += 1 }
    return StationAPIError.offline
  }

  func openSession(_ request: PackageCore.UploadSessionRequest) async throws
    -> PackageCore.UploadSession
  { throw called() }
  func completeFile(packageId: UUID, path: String) async throws -> PackageCore.FileCheckResult {
    throw called()
  }
  func seal(packageId: UUID, manifestJSON: Data) async throws -> PackageCore.PackageSealResult {
    throw called()
  }
}
