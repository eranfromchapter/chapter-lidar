import CaptureContract
import Foundation
import PackageCore

/// Thrown by a scripted fault to simulate the app being killed at that point.
struct SimulatedKill: Error, Equatable {}

/// One request the fake world received, for assertions.
enum FakeCall: Hashable, Sendable {
  case openSession
  case putBlob(path: String, blob: String)
  case putBlock(path: String, blob: String, offset: Int64)
  case putBlockList(path: String, blob: String, count: Int)
  case completeFile(path: String, status: FileStatus)
  case seal
}

/// A scripted failure of one blob or station request.
struct Fault: Sendable {
  enum Timing: Sendable {
    /// The request never reaches the service.
    case before
    /// The service applies the request, then the answer is lost.
    case after
  }

  let timing: Timing
  let error: any Error & Sendable
  let matches: @Sendable (FakeCall) -> Bool
}

/// An in-memory station (upload routes of station/api/src/routes/uploads) plus Azure Blob
/// Storage with create-only SAS targets, sharing one clock. Thread-safe; used through
/// `FakeStationService` and `FakeBlobTransport`.
final class FakeWorld: @unchecked Sendable {
  struct StoredFile {
    var declaration: UploadFileDeclaration
    var status: FileStatus = .pending
    var blobName: String
    var attempt = 1
    var actualSha256: String?
    var actualBytes: Int64?
    var checkedAt: UTCTimestamp?
    /// Set when the file was verified by carry-over from the superseded revision.
    var carriedOverFrom: LowercaseUUID?
  }

  struct StoredPackage {
    var request: UploadSessionRequest
    var status: PackageStatus = .uploading
    var files: [String: StoredFile]
    var createdAt: UTCTimestamp
    var manifestData: Data?
  }

  private let lock = NSLock()
  private var clock: Date
  private var packages: [LowercaseUUID: StoredPackage] = [:]
  private var blobs: [String: Data] = [:]
  private var staged: [String: [String: Data]] = [:]
  private var tokens: [String: (blob: String, path: String, expiresAt: Date)] = [:]
  private var faults: [Fault] = []
  private var corruptUploads: [String: Int] = [:]
  private var checkOverride: (@Sendable (FileCheckResult) -> FileCheckResult)?
  /// False simulates a station before 1.1.0: no `createdAt` in session answers.
  private var sendsCreatedAt = true
  private(set) var calls: [FakeCall] = []
  /// Manifest bodies received by seal, byte for byte.
  private(set) var sealBodies: [Data] = []

  static let targetLifetime: TimeInterval = 30 * 60

  init(now: Date = Date(timeIntervalSince1970: 1_792_243_200)) {
    clock = now
  }

  // MARK: Test controls

  var now: Date {
    lock.lock()
    defer { lock.unlock() }
    return clock
  }

  func advance(by seconds: TimeInterval) {
    locked { clock = clock.addingTimeInterval(seconds) }
  }

  func addFault(_ fault: Fault) {
    locked { faults.append(fault) }
  }

  /// The next `count` uploads of `path` are stored with one byte flipped.
  func corruptUploads(of path: String, count: Int = 1) {
    locked { corruptUploads[path] = count }
  }

  /// Rewrites every completeFile answer (to simulate an inconsistent station).
  func overrideChecks(_ transform: @escaping @Sendable (FileCheckResult) -> FileCheckResult) {
    locked { checkOverride = transform }
  }

  /// Session answers without `createdAt`, as a station before 1.1.0 sends them.
  func omitCreatedAt() {
    locked { sendsCreatedAt = false }
  }

  func createdAt(_ packageId: LowercaseUUID) -> UTCTimestamp? {
    locked { packages[packageId]?.createdAt }
  }

  func carriedOverFrom(_ packageId: LowercaseUUID, path: String) -> LowercaseUUID? {
    locked { packages[packageId]?.files[path]?.carriedOverFrom }
  }

  /// Invalidates every issued target (as if refused by the blob service).
  func revokeTargets() {
    locked { tokens.removeAll() }
  }

  /// Drops every staged, uncommitted block (Azure discards them after a week).
  func dropStagedBlocks() {
    locked { staged.removeAll() }
  }

  func blob(named name: String) -> Data? {
    locked { blobs[name] }
  }

  /// The committed blob the station currently associates with `path`.
  func storedBlob(packageId: LowercaseUUID, path: String) -> Data? {
    locked {
      guard let name = packages[packageId]?.files[path]?.blobName else { return nil }
      return blobs[name]
    }
  }

  func packageStatus(_ packageId: LowercaseUUID) -> PackageStatus? {
    locked { packages[packageId]?.status }
  }

  func fileStatus(_ packageId: LowercaseUUID, path: String) -> FileStatus? {
    locked { packages[packageId]?.files[path]?.status }
  }

  func callLog() -> [FakeCall] {
    locked { calls }
  }

  func receivedSealBodies() -> [Data] {
    locked { sealBodies }
  }

  // MARK: Station

  func openSession(_ request: UploadSessionRequest) throws -> UploadSession {
    try perform(.openSession) {
      let now = UTCTimestamp(clock)
      var package: StoredPackage
      if let existing = packages[request.packageId] {
        guard existing.request == request else {
          throw StationProblem(status: 409, code: "package_conflict")
        }
        package = existing
        if package.status == .uploading {
          for (path, var file) in package.files
          where file.status == .sha256Mismatch || file.status == .bytesMismatch {
            file.attempt += 1
            file.blobName = "\(request.packageId.rawValue).retry-\(file.attempt)/\(path)"
            file.status = .pending
            file.actualSha256 = nil
            file.actualBytes = nil
            file.checkedAt = nil
            package.files[path] = file
          }
        }
      } else {
        var files: [String: StoredFile] = [:]
        // Carry-over (station 1.1.0): a file equal to a verified file of the superseded
        // revision is verified at once from the stored blob.
        let previous = request.supersedesPackageId.flatMap { packages[$0] }
        for declaration in request.files {
          if let previous, previous.status != .uploading,
            let earlier = previous.files[declaration.path], earlier.status == .verified,
            earlier.declaration == declaration
          {
            var file = earlier
            file.carriedOverFrom = request.supersedesPackageId
            files[declaration.path] = file
          } else {
            files[declaration.path] = StoredFile(
              declaration: declaration,
              blobName: "\(request.packageId.rawValue)/\(declaration.path)")
          }
        }
        package = StoredPackage(request: request, files: files, createdAt: now)
      }
      packages[request.packageId] = package
      let uploading = package.status == .uploading
      let sessionFiles = request.files.map { declaration -> UploadSessionFile in
        let file = package.files[declaration.path]!
        guard uploading, file.status != .verified else {
          return UploadSessionFile(
            path: declaration.path, status: file.status, carriedOverFrom: file.carriedOverFrom)
        }
        return UploadSessionFile(
          path: declaration.path, status: file.status,
          upload: issueTarget(blob: file.blobName, path: declaration.path))
      }
      return UploadSession(
        packageId: request.packageId, visitId: request.visitId, dealId: request.dealId,
        revision: request.revision, status: package.status,
        createdAt: sendsCreatedAt ? package.createdAt : nil, files: sessionFiles)
    }
  }

  func completeFile(packageId: UUID, path: String) throws -> FileCheckResult {
    let id = LowercaseUUID(packageId)
    var computed: FileStatus = .pending
    let result: FileCheckResult = try lockedThrowing {
      guard var package = packages[id] else {
        throw StationProblem(status: 404, code: "package_not_found")
      }
      guard package.status == .uploading else {
        throw StationProblem(status: 409, code: "package_sealed")
      }
      guard var file = package.files[path] else {
        throw StationProblem(status: 404, code: "file_not_found")
      }
      if file.status != .verified {
        if let data = blobs[file.blobName] {
          let digest = FileDigest.of(data: data)
          file.actualSha256 = digest.sha256
          file.actualBytes = digest.bytes
          if digest.bytes != file.declaration.bytes {
            file.status = .bytesMismatch
          } else if digest.sha256 != file.declaration.sha256 {
            file.status = .sha256Mismatch
          } else {
            file.status = .verified
          }
        } else {
          file.status = .notUploaded
          file.actualSha256 = nil
          file.actualBytes = nil
        }
        file.checkedAt = UTCTimestamp(clock)
        package.files[path] = file
        packages[id] = package
      }
      computed = file.status
      let answer = FileCheckResult(
        path: path, status: file.status, expectedSha256: file.declaration.sha256,
        actualSha256: file.actualSha256, expectedBytes: file.declaration.bytes,
        actualBytes: file.actualBytes, checkedAt: file.checkedAt ?? UTCTimestamp(clock))
      return checkOverride.map { $0(answer) } ?? answer
    }
    return try perform(.completeFile(path: path, status: computed)) { result }
  }

  func seal(packageId: UUID, manifestJSON: Data) throws -> PackageSealResult {
    try perform(.seal) {
      sealBodies.append(manifestJSON)
      let id = LowercaseUUID(packageId)
      guard var package = packages[id] else {
        throw StationProblem(status: 404, code: "package_not_found")
      }
      if package.status != .uploading {
        guard package.manifestData == manifestJSON else {
          throw StationProblem(status: 409, code: "package_sealed")
        }
        return sealResult(package, id: id)
      }
      guard package.files.values.allSatisfy({ $0.status == .verified }) else {
        throw StationProblem(status: 409, code: "files_not_verified")
      }
      let manifest = try CaptureContractJSON.makeDecoder().decode(
        PackageManifest.self, from: manifestJSON)
      guard manifest.packageId == id,
        Set(manifest.files.map(\.path)) == Set(package.files.keys)
      else {
        throw StationProblem(status: 422, code: "manifest_mismatch")
      }
      package.status = .checksQueued
      package.manifestData = manifestJSON
      packages[id] = package
      return sealResult(package, id: id)
    }
  }

  private func sealResult(_ package: StoredPackage, id: LowercaseUUID) -> PackageSealResult {
    let manifest = package.manifestData.flatMap {
      try? CaptureContractJSON.makeDecoder().decode(PackageManifest.self, from: $0)
    }
    return PackageSealResult(
      packageId: id, visitId: package.request.visitId, dealId: package.request.dealId,
      revision: package.request.revision,
      supersedesPackageId: package.request.supersedesPackageId, status: package.status,
      createdAt: package.createdAt, sealedAt: manifest?.sealedAt,
      files: package.request.files.map { declaration in
        let file = package.files[declaration.path]!
        return PackageFileStatus(
          path: declaration.path, role: declaration.role, captureId: declaration.captureId,
          areaKey: declaration.areaKey, sha256: declaration.sha256, bytes: declaration.bytes,
          status: file.status, checkedAt: file.checkedAt)
      },
      manifest: manifest)
  }

  private func issueTarget(blob: String, path: String) -> UploadTarget {
    let token = UUID().uuidString.lowercased()
    let expiresAt = UTCTimestamp(clock.addingTimeInterval(Self.targetLifetime))
    tokens[token] = (blob, path, expiresAt.date)
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~/")
    let encoded = blob.addingPercentEncoding(withAllowedCharacters: allowed) ?? blob
    return UploadTarget(
      url: "https://blob.invalid/originals/\(encoded)?ticket=\(token)",
      headers: ["x-ms-blob-type": "BlockBlob"], expiresAt: expiresAt)
  }

  // MARK: Blob service

  func putBlob(_ upload: BlobUpload, data: Data) throws {
    let (blob, path) = try authorize(upload.target)
    try perform(.putBlob(path: path, blob: blob)) {
      guard blobs[blob] == nil else {
        throw BlobTransportError.http(status: 409, code: "BlobAlreadyExists")
      }
      blobs[blob] = maybeCorrupt(data, path: path)
    }
  }

  func putBlock(_ upload: BlobUpload, blockId: String, offset: Int64, data: Data) throws {
    let (blob, path) = try authorize(upload.target)
    try perform(.putBlock(path: path, blob: blob, offset: offset)) {
      guard blobs[blob] == nil else {
        throw BlobTransportError.http(status: 409, code: "BlobAlreadyExists")
      }
      staged[blob, default: [:]][blockId] = data
    }
  }

  func putBlockList(_ upload: BlobUpload, blockIds: [String]) throws {
    let (blob, path) = try authorize(upload.target)
    try perform(.putBlockList(path: path, blob: blob, count: blockIds.count)) {
      guard blobs[blob] == nil else {
        throw BlobTransportError.http(status: 409, code: "BlobAlreadyExists")
      }
      let blocks = staged[blob] ?? [:]
      var data = Data()
      for id in blockIds {
        guard let block = blocks[id] else {
          throw BlobTransportError.http(status: 400, code: "InvalidBlockList")
        }
        data.append(block)
      }
      blobs[blob] = maybeCorrupt(data, path: path)
      staged[blob] = nil
    }
  }

  private func authorize(_ target: UploadTarget) throws -> (blob: String, path: String) {
    try lockedThrowing {
      guard let components = URLComponents(string: target.url),
        let token = components.queryItems?.first(where: { $0.name == "ticket" })?.value,
        let grant = tokens[token]
      else {
        throw BlobTransportError.http(status: 403, code: "AuthenticationFailed")
      }
      guard clock < grant.expiresAt else {
        throw BlobTransportError.http(status: 403, code: "AuthenticationFailed")
      }
      return (grant.blob, grant.path)
    }
  }

  private func maybeCorrupt(_ data: Data, path: String) -> Data {
    guard let remaining = corruptUploads[path], remaining > 0, !data.isEmpty else { return data }
    corruptUploads[path] = remaining - 1
    var copy = data
    copy[copy.startIndex] ^= 0xff
    return copy
  }

  // MARK: Locking and faults

  /// Runs `body` under the lock, applying the first matching fault before or after it.
  private func perform<T>(_ call: FakeCall, _ body: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    calls.append(call)
    if let index = faults.firstIndex(where: { $0.matches(call) }) {
      let fault = faults.remove(at: index)
      if fault.timing == .before {
        throw fault.error
      }
      _ = try body()
      throw fault.error
    }
    return try body()
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private func lockedThrowing<T>(_ body: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}

/// `PackageUploadService` over the fake world.
struct FakeStationService: PackageUploadService {
  let world: FakeWorld

  func openSession(_ request: UploadSessionRequest) async throws -> UploadSession {
    try world.openSession(request)
  }

  func completeFile(packageId: UUID, path: String) async throws -> FileCheckResult {
    try world.completeFile(packageId: packageId, path: path)
  }

  func seal(packageId: UUID, manifestJSON: Data) async throws -> PackageSealResult {
    try world.seal(packageId: packageId, manifestJSON: manifestJSON)
  }
}

/// `BlobTransport` over the fake world. Reads the package file for reading only.
struct FakeBlobTransport: BlobTransport {
  let world: FakeWorld

  func putBlob(_ upload: BlobUpload) async throws {
    try world.putBlob(upload, data: try read(upload.file, offset: 0, length: Int(upload.bytes)))
  }

  func putBlock(_ upload: BlobUpload, blockId: String, offset: Int64, length: Int) async throws {
    try world.putBlock(
      upload, blockId: blockId, offset: offset, data: try read(upload.file, offset: offset, length: length))
  }

  func putBlockList(_ upload: BlobUpload, blockIds: [String]) async throws {
    try world.putBlockList(upload, blockIds: blockIds)
  }

  private func read(_ url: URL, offset: Int64, length: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    try handle.seek(toOffset: UInt64(offset))
    return try handle.read(upToCount: length) ?? Data()
  }
}
