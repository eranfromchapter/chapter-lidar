import CaptureContract
import Foundation
import PackageCore
import XCTest

/// Records every saved upload state, to check what was ever marked verified and when.
final class StateRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var states: [UploadState] = []

  func record(_ state: UploadState) {
    lock.lock()
    states.append(state)
    lock.unlock()
  }

  var all: [UploadState] {
    lock.lock()
    defer { lock.unlock() }
    return states
  }
}

/// F6.AC3: the upload state machine resumes from the last confirmed block after a simulated kill
/// and never marks a file done before the server sha256 matches.
final class UploadResumeTests: XCTestCase {
  private var folder: TemporaryFolder!
  private var sealed: SealedPackage!
  private var world: FakeWorld!
  private var store: UploadStateStore!
  private let dealId = "fixture-deal-0001"
  /// The largest fixture file; with small blocks it goes up in many blocks.
  private var lasPath: String!

  override func setUpWithError() throws {
    folder = try TemporaryFolder()
    let fixture = try FixturePackage("two-floor-house")
    let draft = try FixtureDraft.make(fixture, generatorPrefix: "chapter-capture-ios/")
    sealed = try PackageAssembler().assemble(
      draft, at: folder.url.appendingPathComponent("package", isDirectory: true),
      sealedAt: UTCTimestamp(secondsSince1970: 1_792_256_400))
    world = FakeWorld()
    store = UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: sealed.root))
    lasPath = try XCTUnwrap(sealed.manifest.files.max { $0.bytes < $1.bytes }?.path)
  }

  override func tearDown() {
    folder.remove()
  }

  /// A new uploader, as after an app start: everything it knows comes from the state file.
  private func uploader(
    blockSize: Int = 4096, recorder: StateRecorder? = nil, maxRejectedUploads: Int = 3
  ) throws -> PackageUploader {
    let world = self.world!
    var progress: (@Sendable (UploadState) -> Void)?
    if let recorder {
      progress = { state in recorder.record(state) }
    }
    return try PackageUploader(
      package: sealed, dealId: dealId, service: FakeStationService(world: world),
      transport: FakeBlobTransport(world: world), store: store, now: { world.now },
      blockSize: blockSize, maxRejectedUploads: maxRejectedUploads, progress: progress)
  }

  private func savedState() throws -> UploadState {
    try XCTUnwrap(try store.load())
  }

  private func file(_ path: String, in state: UploadState) throws -> FileUploadState {
    try XCTUnwrap(state.files.first { $0.path == path })
  }

  private func assertEverythingStoredAndSealed(
    _ result: PackageSealResult, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    XCTAssertEqual(result.status, .checksQueued, file: file, line: line)
    XCTAssertEqual(world.packageStatus(sealed.packageId), .checksQueued, file: file, line: line)
    for entry in sealed.manifest.files {
      let blob = try XCTUnwrap(world.storedBlob(packageId: sealed.packageId, path: entry.path), entry.path)
      XCTAssertEqual(blob, try Data(contentsOf: sealed.url(for: entry.path)), entry.path, file: file, line: line)
    }
    XCTAssertEqual(world.receivedSealBodies().last, sealed.manifestData, file: file, line: line)
    let state = try savedState()
    XCTAssertTrue(state.isConfirmedByStation, file: file, line: line)
    XCTAssertEqual(state.verifiedCount, sealed.manifest.files.count, file: file, line: line)
  }

  // MARK: Happy path

  func testUploadsEveryFileHasEachCheckedAndSealsWithTheManifestBytes() async throws {
    let result = try await uploader().run()
    try assertEverythingStoredAndSealed(result)
    let calls = world.callLog()
    // Small files go up with one Put Blob; the large one in blocks plus one block list.
    let lasBlocks = BlobBlocks.blockCount(bytes: try file(lasPath, in: try savedState()).bytes, blockSize: 4096)
    XCTAssertGreaterThan(lasBlocks, 10)
    XCTAssertEqual(calls.filter { if case .putBlock(lasPath, _, _) = $0 { return true } else { return false } }.count, lasBlocks)
    XCTAssertEqual(calls.filter { if case .putBlockList(lasPath, _, lasBlocks) = $0 { return true } else { return false } }.count, 1)
    XCTAssertEqual(calls.filter { if case .completeFile(_, .verified) = $0 { return true } else { return false } }.count, sealed.manifest.files.count)
    XCTAssertEqual(calls.filter { $0 == .seal }.count, 1)
  }

  func testDefaultBlockSizeIsEightMebibytesWithPutBlobUpToIt() async throws {
    // Two files of exactly 8 MiB and 8 MiB + 1 byte, uploaded with the default block size.
    let sources = try folder.url.appendingPathComponent("big", isDirectory: true)
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    let exact = sources.appendingPathComponent("exact.las")
    let over = sources.appendingPathComponent("over.las")
    try Data(repeating: 1, count: BlobBlocks.blockSize).write(to: exact)
    try Data(repeating: 2, count: BlobBlocks.blockSize + 1).write(to: over)
    let record = try XCTUnwrap(sealed.manifest.files.first { $0.role == .captureRecord })
    let capture = try XCTUnwrap(sealed.manifest.files.first { $0.captureId != nil })
    let ref = CaptureRef(captureId: capture.captureId!, areaKey: capture.areaKey!)
    var draft = PackageDraft(visitId: sealed.visitId)
    try draft.add(
      PackageFileInput(
        source: sealed.url(for: record.path), role: .captureRecord, fileName: "capture-record.json",
        mime: "application/json", generator: "chapter-capture-ios/CaptureRecord", generatorVersion: "1.0.0"))
    for (url, name) in [(exact, "exact.las"), (over, "over.las")] {
      try draft.add(
        PackageFileInput(
          source: url, role: .pointCloudLAS, fileName: name, capture: ref, mime: "application/vnd.las",
          generator: "chapter-capture-ios/MeshExport", generatorVersion: "1.0.0"))
    }
    let big = try PackageAssembler().assemble(draft, at: folder.url.appendingPathComponent("big-package"))
    let world = self.world!
    let uploader = try PackageUploader(
      package: big, dealId: dealId, service: FakeStationService(world: world),
      transport: FakeBlobTransport(world: world),
      store: UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: big.root)),
      now: { world.now })
    let result = try await uploader.run()
    XCTAssertEqual(result.status, .checksQueued)
    let exactPath = try XCTUnwrap(big.manifest.files.first { $0.path.hasSuffix("exact.las") }?.path)
    let overPath = try XCTUnwrap(big.manifest.files.first { $0.path.hasSuffix("over.las") }?.path)
    let calls = world.callLog()
    XCTAssertTrue(calls.contains { if case .putBlob(exactPath, _) = $0 { return true } else { return false } })
    XCTAssertFalse(calls.contains { if case .putBlock(exactPath, _, _) = $0 { return true } else { return false } })
    XCTAssertEqual(
      calls.compactMap { if case .putBlock(overPath, _, let offset) = $0 { return offset } else { return nil } },
      [0, Int64(BlobBlocks.blockSize)])
    XCTAssertEqual(world.storedBlob(packageId: big.packageId, path: overPath), try Data(contentsOf: over))
  }

  // MARK: Resume after a kill

  func testResumesFromTheLastConfirmedBlockAfterAKill() async throws {
    // Killed while sending block 6 of the large file: blocks 0-5 were confirmed.
    world.addFault(
      Fault(timing: .before, error: SimulatedKill()) { [lasPath] call in
        if case .putBlock(lasPath, _, 6 * 4096) = call { return true }
        return false
      })
    do {
      try await uploader().run()
      XCTFail("expected the simulated kill")
    } catch is SimulatedKill {}

    // The in-memory uploader is gone; the state file says where to resume.
    let killed = try file(lasPath, in: try savedState())
    XCTAssertEqual(killed.phase, .pending)
    XCTAssertEqual(killed.stagedBlockIds, (0..<6).map(BlobBlocks.blockId))
    XCTAssertNotNil(killed.target)

    let before = world.callLog().count
    let result = try await uploader().run()
    try assertEverythingStoredAndSealed(result)

    let resumedOffsets = world.callLog()[before...].compactMap { call -> Int64? in
      if case .putBlock(lasPath, _, let offset) = call { return offset }
      return nil
    }
    XCTAssertEqual(resumedOffsets.first, 6 * 4096, "resumes at the first unconfirmed block")
    XCTAssertFalse(resumedOffsets.contains { $0 < 6 * 4096 }, "confirmed blocks are not sent again")
  }

  func testKillAfterTheBlobServiceAcceptedAnUploadAsksTheStationBeforeResending() async throws {
    let small = try XCTUnwrap(sealed.manifest.files.first { $0.role == .captureRecord }?.path)
    world.addFault(
      Fault(timing: .after, error: SimulatedKill()) { call in
        if case .putBlob(small, _) = call { return true }
        return false
      })
    do {
      try await uploader().run()
      XCTFail("expected the simulated kill")
    } catch is SimulatedKill {}
    XCTAssertEqual(try file(small, in: try savedState()).phase, .sending)

    let before = world.callLog().count
    try assertEverythingStoredAndSealed(try await uploader().run())
    let resumed = Array(world.callLog()[before...])
    let firstForFile = resumed.first { call in
      switch call {
      case .putBlob(small, _), .completeFile(small, _): return true
      default: return false
      }
    }
    XCTAssertEqual(firstForFile, .completeFile(path: small, status: .verified))
    XCTAssertFalse(resumed.contains { if case .putBlob(small, _) = $0 { return true } else { return false } })
  }

  func testKillAfterTheBlockListWasCommittedDoesNotUploadTheBlocksAgain() async throws {
    world.addFault(
      Fault(timing: .after, error: SimulatedKill()) { [lasPath] call in
        if case .putBlockList(lasPath, _, _) = call { return true }
        return false
      })
    do {
      try await uploader().run()
      XCTFail("expected the simulated kill")
    } catch is SimulatedKill {}
    let before = world.callLog().count
    try assertEverythingStoredAndSealed(try await uploader().run())
    XCTAssertFalse(
      world.callLog()[before...].contains { call in
        switch call {
        case .putBlock(lasPath, _, _), .putBlockList(lasPath, _, _): return true
        default: return false
        }
      })
  }

  func testNetworkLossBeforeAnUploadLandedResumesWithAFreshSend() async throws {
    let photo = try XCTUnwrap(sealed.manifest.files.first { $0.role == .photo }?.path)
    world.addFault(
      Fault(timing: .before, error: BlobTransportError.network("offline")) { call in
        if case .putBlob(photo, _) = call { return true }
        return false
      })
    do {
      try await uploader().run()
      XCTFail("expected the network error")
    } catch let error as BlobTransportError {
      XCTAssertEqual(error, .network("offline"))
    }
    XCTAssertEqual(try file(photo, in: try savedState()).phase, .sending)
    try assertEverythingStoredAndSealed(try await uploader().run())
  }

  func testExpiredTargetsAreReplacedByReopeningTheSession() async throws {
    world.addFault(
      Fault(timing: .before, error: SimulatedKill()) { [lasPath] call in
        if case .putBlock(lasPath, _, 3 * 4096) = call { return true }
        return false
      })
    do {
      try await uploader().run()
      XCTFail("expected the simulated kill")
    } catch is SimulatedKill {}
    let opensBefore = world.callLog().filter { $0 == .openSession }.count
    world.advance(by: 2 * 60 * 60)

    let before = world.callLog().count
    try assertEverythingStoredAndSealed(try await uploader().run())
    let resumed = Array(world.callLog()[before...])
    XCTAssertEqual(resumed.first, .openSession, "expired targets are refreshed before any upload")
    XCTAssertEqual(world.callLog().filter { $0 == .openSession }.count, opensBefore + 1)
    // Same blob after the refresh, so the staged blocks were kept.
    let offsets = resumed.compactMap { call -> Int64? in
      if case .putBlock(lasPath, _, let offset) = call { return offset }
      return nil
    }
    XCTAssertEqual(offsets.first, 3 * 4096)
  }

  func testRefusedTargetsAreCheckedWithTheStationAndReplaced() async throws {
    // Valid by their expiry, but refused by the blob service (403).
    world.addFault(
      Fault(timing: .before, error: SimulatedKill()) { call in
        if case .putBlob = call { return true }
        return false
      })
    do {
      try await uploader().run()
      XCTFail("expected the simulated kill")
    } catch is SimulatedKill {}
    world.revokeTargets()
    try assertEverythingStoredAndSealed(try await uploader().run())
  }

  func testStagedBlocksTheServiceNoLongerHasAreUploadedAgain() async throws {
    world.addFault(
      Fault(timing: .before, error: SimulatedKill()) { [lasPath] call in
        if case .putBlockList(lasPath, _, _) = call { return true }
        return false
      })
    do {
      try await uploader().run()
      XCTFail("expected the simulated kill")
    } catch is SimulatedKill {}
    world.dropStagedBlocks()
    let before = world.callLog().count
    try assertEverythingStoredAndSealed(try await uploader().run())
    let offsets = world.callLog()[before...].compactMap { call -> Int64? in
      if case .putBlock(lasPath, _, let offset) = call { return offset }
      return nil
    }
    XCTAssertEqual(offsets.first, 0, "blocks restart after InvalidBlockList")
  }

  func testLostSealAnswerIsRecoveredFromTheStation() async throws {
    world.addFault(Fault(timing: .after, error: SimulatedKill()) { $0 == .seal })
    do {
      try await uploader().run()
      XCTFail("expected the simulated kill")
    } catch is SimulatedKill {}
    XCTAssertEqual(world.packageStatus(sealed.packageId), .checksQueued)
    XCTAssertNil(try savedState().sealResult)
    try assertEverythingStoredAndSealed(try await uploader().run())
    XCTAssertEqual(Set(world.receivedSealBodies()), [sealed.manifestData])
  }

  func testAFinishedUploadDoesNothingMore() async throws {
    try await uploader().run()
    let before = world.callLog().count
    let again = try await uploader().run()
    XCTAssertEqual(again.status, .checksQueued)
    XCTAssertEqual(world.callLog().count, before)
  }

  // MARK: Done only when the server sha256 matches

  func testAFileIsNeverMarkedDoneBeforeTheServerSha256Matches() async throws {
    let photo = try XCTUnwrap(sealed.manifest.files.first { $0.role == .photo }?.path)
    world.corruptUploads(of: photo)
    world.corruptUploads(of: lasPath)
    let recorder = StateRecorder()
    let result = try await uploader(recorder: recorder).run()
    try assertEverythingStoredAndSealed(result)

    for path in [photo, lasPath!] {
      let phases = recorder.all.map { state in state.files.first { $0.path == path }!.phase }
      let firstVerified = try XCTUnwrap(phases.firstIndex(of: .verified))
      // The first upload was accepted by the blob service but rejected by the station's hash.
      let firstUploaded = try XCTUnwrap(phases.firstIndex(of: .uploaded))
      XCTAssertLessThan(firstUploaded, firstVerified)
      XCTAssertTrue(phases[firstUploaded..<firstVerified].contains(.pending), "\(path) was uploaded again")
      let final = try file(path, in: try savedState())
      XCTAssertEqual(final.rejectedUploads, 1)
      XCTAssertEqual(final.lastCheck?.status, .verified)
      XCTAssertEqual(final.lastCheck?.actualSha256, final.sha256)
    }
    // Each rejected file's second upload went to a new blob (the station's retry name).
    let calls = world.callLog()
    let photoBlobs = Set(calls.compactMap { if case .putBlob(photo, let blob) = $0 { return blob } else { return nil } })
    XCTAssertEqual(photoBlobs.count, 2)
    XCTAssertTrue(calls.contains(.completeFile(path: photo, status: .sha256Mismatch)))
    // Every state that showed a file verified came after the station said verified for it.
    for state in recorder.all {
      for entry in state.files where entry.phase == .verified {
        XCTAssertEqual(entry.lastCheck?.status, .verified, entry.path)
        XCTAssertEqual(entry.lastCheck?.actualSha256, entry.sha256, entry.path)
        XCTAssertEqual(entry.lastCheck?.actualBytes, entry.bytes, entry.path)
      }
    }
  }

  func testAVerifiedAnswerWithAnotherSha256IsRefused() async throws {
    world.overrideChecks { result in
      var changed = result
      if changed.status == .verified {
        changed.actualSha256 = String(repeating: "0", count: 64)
      }
      return changed
    }
    do {
      try await uploader().run()
      XCTFail("expected a check mismatch")
    } catch let error as PackageUploadError {
      guard case .checkMismatch = error else { return XCTFail("\(error)") }
    }
    let state = try savedState()
    XCTAssertEqual(state.verifiedCount, 0)
    XCTAssertNil(state.sealResult)
    XCTAssertFalse(world.callLog().contains(.seal))
  }

  func testACheckForOtherExpectedBytesIsRefused() async throws {
    world.overrideChecks { result in
      var changed = result
      changed.expectedBytes += 1
      return changed
    }
    do {
      try await uploader().run()
      XCTFail("expected a check mismatch")
    } catch let error as PackageUploadError {
      guard case .checkMismatch = error else { return XCTFail("\(error)") }
    }
    XCTAssertEqual(try savedState().verifiedCount, 0)
  }

  func testRepeatedRejectionsStopTheUploadWithoutMarkingTheFileDone() async throws {
    let photo = try XCTUnwrap(sealed.manifest.files.first { $0.role == .photo }?.path)
    world.corruptUploads(of: photo, count: 10)
    do {
      try await uploader(maxRejectedUploads: 3).run()
      XCTFail("expected too many rejections")
    } catch let error as PackageUploadError {
      XCTAssertEqual(error, .tooManyRejectedUploads(path: photo, lastStatus: .sha256Mismatch))
    }
    let state = try savedState()
    XCTAssertNotEqual(try file(photo, in: state).phase, .verified)
    XCTAssertFalse(world.callLog().contains(.seal))
  }

  // MARK: State file

  func testTheStateFileBelongsToExactlyOnePackage() async throws {
    try await uploader().run()
    let saved = try savedState()

    var otherManifest = saved
    otherManifest.manifestSha256 = String(repeating: "a", count: 64)
    try store.save(otherManifest)
    XCTAssertThrowsError(try uploader()) { error in
      guard case .stateMismatch = error as? PackageUploadError else { return XCTFail("\(error)") }
    }

    var otherPackage = saved
    otherPackage.packageId = LowercaseUUID()
    try store.save(otherPackage)
    XCTAssertThrowsError(try uploader()) { error in
      guard case .stateMismatch = error as? PackageUploadError else { return XCTFail("\(error)") }
    }

    // The right package, but a session for another deal.
    try store.save(saved)
    XCTAssertNoThrow(try uploader())
    XCTAssertThrowsError(
      try PackageUploader(
        package: sealed, dealId: "fixture-deal-0002", service: FakeStationService(world: world),
        transport: FakeBlobTransport(world: world), store: store)
    ) { error in
      guard case .stateMismatch = error as? PackageUploadError else { return XCTFail("\(error)") }
    }
  }

  func testTheStateFileIsOwnerOnlyAndNextToThePackage() async throws {
    try await uploader().run()
    XCTAssertEqual(store.url.deletingLastPathComponent().path, sealed.root.deletingLastPathComponent().path)
    let attributes = try FileManager.default.attributesOfItem(atPath: store.url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }
}
