import CaptureContract
import Foundation

/// Why an upload stopped. Transient failures (network, blob service, station unavailable) are
/// rethrown as they are; the state is saved first, so calling `run()` again resumes.
public enum PackageUploadError: Error, Hashable, Sendable, CustomStringConvertible {
  /// The state file belongs to another package or another manifest.
  case stateMismatch(String)
  case unreadableState(String)
  case unwritableState(String)
  /// The station's session does not match the package (identity, file list or missing target).
  case sessionMismatch(String)
  /// The station's check answer is inconsistent with the manifest (path, expected values, or
  /// verified with a different fingerprint). The file is not marked done.
  case checkMismatch(path: String, reason: String)
  /// The station rejected the uploaded bytes of a file too many times.
  case tooManyRejectedUploads(path: String, lastStatus: FileStatus)
  /// Upload targets kept failing (expired or refused) after fresh ones were requested.
  case targetsKeepFailing(path: String)
  /// The local package file no longer has the manifest's fingerprint. Nothing is uploaded.
  case localFileChanged(path: String)
  /// The station's answer to sealing does not show the package registered with every file
  /// verified.
  case sealNotConfirmed(String)

  public var description: String {
    switch self {
    case .stateMismatch(let reason): return "upload state does not belong to this package: \(reason)"
    case .unreadableState(let reason): return "cannot read the upload state: \(reason)"
    case .unwritableState(let reason): return "cannot save the upload state: \(reason)"
    case .sessionMismatch(let reason): return "upload session does not match the package: \(reason)"
    case .checkMismatch(let path, let reason): return "station check of \(path) is inconsistent: \(reason)"
    case .tooManyRejectedUploads(let path, let status):
      return "the station rejected \(path) too many times (last: \(status.rawValue))"
    case .targetsKeepFailing(let path): return "upload targets for \(path) keep failing"
    case .localFileChanged(let path): return "\(path) no longer matches the manifest"
    case .sealNotConfirmed(let reason): return "the station did not confirm the package: \(reason)"
    }
  }
}

/// Uploads one sealed package to the station and resumes after an app kill or network loss.
///
/// Rules:
/// - A file is verified only after `completeFile` answers `verified` with the manifest's SHA-256
///   and size as both expected and actual values. An upload the blob service accepted is not
///   enough.
/// - Files up to 8 MiB go up with one Put Blob; larger files as 8 MiB blocks (Put Block, then Put
///   Block List). The state is saved after every confirmed step (each block, each upload, each
///   check), and before a Put Blob or Put Block List is sent, so a restarted uploader asks the
///   station before sending anything twice.
/// - On sha256_mismatch, bytes_mismatch or not_uploaded after an upload, and when targets expire
///   or are refused, the session is opened again with the same body for fresh targets. Retries
///   may point to different blobs: targets are used exactly as issued and staged blocks are kept
///   only while the blob (URL without its query) stays the same.
/// - When every file is verified the manifest bytes are sent to seal, exactly as on disk.
/// - Nothing is ever deleted: not the package, not the state file.
public actor PackageUploader {
  public let package: SealedPackage
  private let service: any PackageUploadService
  private let transport: any BlobTransport
  private let store: UploadStateStore
  private let now: @Sendable () -> Date
  private let blockSize: Int
  private let maxRejectedUploads: Int
  private let maxTargetRefreshes: Int
  private let progress: (@Sendable (UploadState) -> Void)?
  private var state: UploadState
  private var request: UploadSessionRequest
  /// Session reopenings in this run (bounded so a broken target cannot loop forever).
  private var refreshes = 0
  /// Files whose local bytes were checked against the manifest in this run.
  private var locallyVerified: Set<String> = []

  /// Targets that expire within this margin are refreshed before use.
  public static let expiryMargin: TimeInterval = 120

  /// Loads the saved state from `store` (or starts a new one). The state must belong to this
  /// package's exact manifest bytes and deal.
  public init(
    package: SealedPackage,
    dealId: String,
    service: any PackageUploadService,
    transport: any BlobTransport,
    store: UploadStateStore,
    now: @escaping @Sendable () -> Date = { Date() },
    blockSize: Int = BlobBlocks.blockSize,
    maxRejectedUploads: Int = 3,
    maxTargetRefreshes: Int = 5,
    progress: (@Sendable (UploadState) -> Void)? = nil
  ) throws {
    self.package = package
    self.service = service
    self.transport = transport
    self.store = store
    self.now = now
    self.blockSize = blockSize
    self.maxRejectedUploads = maxRejectedUploads
    self.maxTargetRefreshes = maxTargetRefreshes
    self.progress = progress
    request = UploadSessionRequest(manifest: package.manifest, dealId: dealId)
    let fresh = UploadState(package: package, dealId: dealId)
    if let saved = try store.load() {
      guard saved.formatVersion == UploadState.currentFormatVersion else {
        throw PackageUploadError.stateMismatch("unknown format version \(saved.formatVersion)")
      }
      guard saved.packageId == fresh.packageId, saved.manifestSha256 == fresh.manifestSha256,
        saved.files.map(\.path) == fresh.files.map(\.path),
        saved.files.map(\.sha256) == fresh.files.map(\.sha256),
        saved.files.map(\.bytes) == fresh.files.map(\.bytes)
      else {
        throw PackageUploadError.stateMismatch("package or manifest differs")
      }
      guard saved.dealId == dealId else {
        throw PackageUploadError.stateMismatch("the session was opened for another deal")
      }
      state = saved
    } else {
      state = fresh
    }
  }

  /// The current upload state.
  public var currentState: UploadState { state }

  /// Uploads every file that is not verified, has the station check each one, then seals.
  /// Returns the station's answer to sealing. Throws on any failure with the state saved; call
  /// again (in this or a new process) to resume.
  @discardableResult
  public func run() async throws -> PackageSealResult {
    refreshes = 0
    if let sealed = state.sealResult, state.isConfirmedByStation {
      return sealed
    }
    try save()

    let needsTargets = state.files.contains { $0.phase == .pending && !usable($0.target) }
    if needsTargets, let result = try await openSession() {
      return result
    }

    for index in state.files.indices {
      try await uploadAndVerify(index)
    }
    if let sealed = state.sealResult, state.isConfirmedByStation {
      return sealed
    }
    return try await sealPackage()
  }

  // MARK: Session

  /// Opens (or resumes) the session and takes the fresh targets. Returns the seal result when the
  /// station has already registered the package (sealed before the app learned of it).
  @discardableResult
  private func openSession() async throws -> PackageSealResult? {
    refreshes += 1
    let session = try await service.openSession(request)
    guard session.packageId == request.packageId, session.visitId == request.visitId,
      session.revision == request.revision, session.dealId == request.dealId
    else {
      throw PackageUploadError.sessionMismatch("identity differs")
    }
    let byPath = Dictionary(session.files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    guard byPath.count == session.files.count, Set(byPath.keys) == Set(state.files.map(\.path))
    else {
      throw PackageUploadError.sessionMismatch("file list differs")
    }
    if session.status != .uploading {
      // Already sealed at the station: sealing again with the same manifest is idempotent and
      // returns the package with every file's status.
      return try await sealPackage()
    }
    for index in state.files.indices {
      guard let remote = byPath[state.files[index].path] else { continue }
      if state.files[index].phase == .verified {
        continue
      }
      if remote.status == .verified {
        // The station verified it (its answer was lost); confirm through completeFile.
        state.files[index].target = nil
        state.files[index].phase = .uploaded
        continue
      }
      guard let target = remote.upload else {
        throw PackageUploadError.sessionMismatch("no upload target for \(remote.path)")
      }
      guard target.method.uppercased() == "PUT" else {
        throw PackageUploadError.sessionMismatch("upload target method is not PUT")
      }
      let old = state.files[index].target
      if old?.blobLocation != target.blobLocation {
        // A different blob: blocks staged for the old one do not carry over.
        state.files[index].stagedBlockIds = []
      }
      state.files[index].target = target
    }
    try save()
    return nil
  }

  private func usable(_ target: UploadTarget?) -> Bool {
    guard let target else { return false }
    return target.expiresAt.date.timeIntervalSince(now()) > Self.expiryMargin
  }

  private func refreshTargets(for index: Int) async throws {
    guard refreshes < maxTargetRefreshes else {
      throw PackageUploadError.targetsKeepFailing(path: state.files[index].path)
    }
    if try await openSession() != nil {
      // The station already holds the package sealed; every file was confirmed by sealing.
      return
    }
  }

  // MARK: Files

  private func uploadAndVerify(_ index: Int) async throws {
    while state.files[index].phase != .verified {
      if state.sealResult != nil, state.isConfirmedByStation { return }
      switch state.files[index].phase {
      case .verified:
        return
      case .sending:
        try await check(index, afterUncertainSend: true)
      case .uploaded:
        try await check(index, afterUncertainSend: false)
      case .pending:
        guard usable(state.files[index].target) else {
          try await refreshTargets(for: index)
          continue
        }
        try verifyLocalFile(index)
        do {
          try await upload(index)
        } catch let error as BlobTransportError {
          try handleTransportError(error, index: index)
        }
      }
    }
  }

  /// Sends the file (whole or remaining blocks). Leaves the file `uploaded` when the blob service
  /// confirmed it.
  private func upload(_ index: Int) async throws {
    let file = state.files[index]
    guard let target = file.target, let entry = manifestEntry(file.path) else { return }
    let upload = BlobUpload(
      target: target, file: package.url(for: file.path), bytes: file.bytes, mime: entry.mime)

    if file.bytes <= Int64(blockSize) {
      state.files[index].phase = .sending
      try save()
      try await transport.putBlob(upload)
    } else {
      let count = BlobBlocks.blockCount(bytes: file.bytes, blockSize: blockSize)
      let ids = (0..<count).map(BlobBlocks.blockId)
      var staged = state.files[index].stagedBlockIds
      if staged != Array(ids.prefix(staged.count)) {
        staged = []
      }
      for blockIndex in staged.count..<count {
        let offset = Int64(blockIndex) * Int64(blockSize)
        let length = Int(min(Int64(blockSize), file.bytes - offset))
        try await transport.putBlock(upload, blockId: ids[blockIndex], offset: offset, length: length)
        staged.append(ids[blockIndex])
        state.files[index].stagedBlockIds = staged
        try save()
      }
      state.files[index].phase = .sending
      try save()
      try await transport.putBlockList(upload, blockIds: ids)
    }
    state.files[index].phase = .uploaded
    try save()
  }

  /// Blob service refusals. 403/409 can mean an expired or refused target or a blob that already
  /// exists (create-only targets): ask the station what it holds before anything else. A block
  /// list the service does not know (staged blocks expired) restarts the blocks. Anything else
  /// (network, 5xx) stops the run with the state saved.
  private func handleTransportError(_ error: BlobTransportError, index: Int) throws {
    switch error {
    case .http(let status, _) where status == 403 || status == 409:
      state.files[index].phase = .sending
      state.files[index].target = state.files[index].target.map { expired($0) }
      try save()
    case .http(400, let code) where code == "InvalidBlockList" || code == "InvalidBlockId":
      // Restart the blocks on a fresh target (bounded by maxTargetRefreshes).
      state.files[index].stagedBlockIds = []
      state.files[index].phase = .pending
      state.files[index].target = state.files[index].target.map { expired($0) }
      try save()
    default:
      // The send may or may not have reached the service; `sending` (if set) makes the next run
      // ask the station first.
      try save()
      throw error
    }
  }

  /// A copy of the target that is treated as expired, so the next send gets a fresh one.
  private func expired(_ target: UploadTarget) -> UploadTarget {
    var copy = target
    copy.expiresAt = UTCTimestamp(secondsSince1970: 0)
    return copy
  }

  /// Asks the station to check the stored blob. Marks the file verified only on a consistent
  /// `verified` answer.
  private func check(_ index: Int, afterUncertainSend: Bool) async throws {
    let file = state.files[index]
    let result: FileCheckResult
    do {
      result = try await service.completeFile(packageId: package.packageId.uuid, path: file.path)
    } catch let problem as StationProblem where problem.code == "upload_target_changed" {
      // A new target was issued during the check: take it and upload again.
      state.files[index].phase = .pending
      state.files[index].target = nil
      try save()
      return
    } catch let problem as StationProblem where problem.code == "package_sealed" {
      _ = try await sealPackage()
      return
    }
    guard result.path == file.path else {
      throw PackageUploadError.checkMismatch(path: file.path, reason: "answer is for another path")
    }
    guard result.expectedSha256 == file.sha256, result.expectedBytes == file.bytes else {
      throw PackageUploadError.checkMismatch(
        path: file.path, reason: "station expects other bytes than the manifest")
    }
    state.files[index].lastCheck = result

    switch result.status {
    case .verified:
      guard result.actualSha256 == file.sha256, result.actualBytes == file.bytes else {
        try save()
        throw PackageUploadError.checkMismatch(
          path: file.path, reason: "verified with a different SHA-256 or size")
      }
      state.files[index].phase = .verified
      state.files[index].target = nil
      state.files[index].stagedBlockIds = []
      try save()
    case .notUploaded, .pending:
      if afterUncertainSend {
        // The send never landed: send again (staged blocks are kept for the same blob).
        state.files[index].phase = .pending
        try save()
      } else {
        try rejectUpload(index, status: result.status)
      }
    case .sha256Mismatch, .bytesMismatch:
      try rejectUpload(index, status: result.status)
    }
  }

  /// The station holds wrong or no bytes after an upload: upload again to a fresh target.
  private func rejectUpload(_ index: Int, status: FileStatus) throws {
    state.files[index].rejectedUploads += 1
    state.files[index].phase = .pending
    state.files[index].target = nil
    state.files[index].stagedBlockIds = []
    try save()
    if state.files[index].rejectedUploads >= maxRejectedUploads {
      throw PackageUploadError.tooManyRejectedUploads(path: state.files[index].path, lastStatus: status)
    }
  }

  /// Hashes the package file once per run before the first send of it.
  private func verifyLocalFile(_ index: Int) throws {
    let file = state.files[index]
    guard !locallyVerified.contains(file.path) else { return }
    let digest: FileDigest
    do {
      digest = try FileDigest.of(fileAt: package.url(for: file.path))
    } catch {
      throw PackageUploadError.localFileChanged(path: file.path)
    }
    guard digest.sha256 == file.sha256, digest.bytes == file.bytes else {
      throw PackageUploadError.localFileChanged(path: file.path)
    }
    locallyVerified.insert(file.path)
  }

  private func manifestEntry(_ path: String) -> PackageManifest.FileEntry? {
    package.manifest.files.first { $0.path == path }
  }

  // MARK: Seal

  private func sealPackage() async throws -> PackageSealResult {
    let result = try await service.seal(
      packageId: package.packageId.uuid, manifestJSON: package.manifestData)
    guard result.packageId == package.packageId, result.visitId == package.visitId,
      result.revision == package.manifest.revision
    else {
      throw PackageUploadError.sealNotConfirmed("the answer is for another package")
    }
    guard result.status != .uploading else {
      throw PackageUploadError.sealNotConfirmed("the package is still uploading")
    }
    let remote = Dictionary(result.files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    for index in state.files.indices {
      let file = state.files[index]
      guard let station = remote[file.path], station.status == .verified,
        station.sha256 == file.sha256, station.bytes == file.bytes
      else {
        throw PackageUploadError.sealNotConfirmed("\(file.path) is not verified at the station")
      }
      if file.phase != .verified {
        state.files[index].phase = .verified
        state.files[index].target = nil
        state.files[index].stagedBlockIds = []
      }
    }
    guard remote.count == state.files.count else {
      throw PackageUploadError.sealNotConfirmed("the station lists other files")
    }
    state.sealResult = result
    try save()
    return result
  }

  // MARK: State

  private func save() throws {
    try store.save(state)
    progress?(state)
  }
}
