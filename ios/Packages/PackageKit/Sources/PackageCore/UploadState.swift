import CaptureContract
import Foundation

/// Where one file is in its upload.
public enum FileUploadPhase: String, Codable, Sendable, CaseIterable {
  /// Nothing confirmed for the current target yet (blocks may be staged, see `stagedBlockIds`).
  case pending
  /// Put Blob or Put Block List was sent and its answer is not known (the app may have been
  /// killed). The station is asked before anything is sent again.
  case sending
  /// The blob service confirmed the upload; the station has not confirmed it yet.
  case uploaded
  /// The station confirmed the stored blob has the manifest's SHA-256 and size. Only a
  /// `completeFile` answer can put a file here.
  case verified
}

/// Upload progress of one package file.
public struct FileUploadState: Hashable, Sendable, Codable {
  public var path: String
  public var sha256: String
  public var bytes: Int64
  public var phase: FileUploadPhase
  /// Current upload target (a credential: never logged; descriptions redact it).
  public var target: UploadTarget?
  /// Blocks the blob service confirmed for the current blob (not yet committed), in order.
  public var stagedBlockIds: [String]
  /// Uploads the station rejected (sha256_mismatch, bytes_mismatch, not_uploaded after upload).
  public var rejectedUploads: Int
  /// The station's last check of this file.
  public var lastCheck: FileCheckResult?

  public init(path: String, sha256: String, bytes: Int64) {
    self.path = path
    self.sha256 = sha256
    self.bytes = bytes
    phase = .pending
    target = nil
    stagedBlockIds = []
    rejectedUploads = 0
    lastCheck = nil
  }
}

/// Upload progress of one sealed package, saved as JSON next to the package after every confirmed
/// step so a killed app resumes from the last confirmed block.
///
/// Format 2 adds `registeredAt`, `supersededBy` and `carriedOver`; a format 1 file (written by
/// app builds before v2) is read as format 2 without them, so its upload resumes after the app
/// update.
public struct UploadState: Hashable, Sendable, Codable {
  /// Format version of this file.
  public var formatVersion: Int
  public var packageId: LowercaseUUID
  /// SHA-256 of the manifest bytes: the state belongs to exactly this sealed package.
  public var manifestSha256: String
  /// HUB deal id the session was opened with.
  public var dealId: String
  /// One entry per manifest file, in manifest order.
  public var files: [FileUploadState]
  /// The station's answer to sealing. Set once the station registered the package.
  public var sealResult: PackageSealResult?
  /// When the station registered the package (opened its upload session): the station's
  /// `createdAt` from the first session answer, else the phone's time of that answer. Shown as
  /// "Registered" (critique R-16). Nil before the station answered.
  public var registeredAt: UTCTimestamp?
  /// The package that replaced this one after a failed upload (re-sealed as the next revision).
  /// A superseded package is never resumed; nothing of it is deleted.
  public var supersededBy: LowercaseUUID?
  /// Paths the station verified at once because the superseded revision holds the same verified
  /// file (`carriedOverFrom` in the session answer). They are never uploaded by this package.
  public var carriedOver: Set<String>

  public static let currentFormatVersion = 2
  /// Format versions this build reads.
  public static let readableFormatVersions: ClosedRange<Int> = 1...currentFormatVersion

  public init(package: SealedPackage, dealId: String) {
    formatVersion = Self.currentFormatVersion
    packageId = package.packageId
    manifestSha256 = SHA256.hexDigest(of: package.manifestData)
    self.dealId = dealId
    files = package.manifest.files.map {
      FileUploadState(path: $0.path, sha256: $0.sha256, bytes: $0.bytes)
    }
    sealResult = nil
    registeredAt = nil
    supersededBy = nil
    carriedOver = []
  }

  private enum CodingKeys: String, CodingKey {
    case formatVersion, packageId, manifestSha256, dealId, files, sealResult, registeredAt
    case supersededBy, carriedOver
  }

  /// Reads format 1 and 2 as format 2 (format 1 has none of the new fields). Any other version
  /// is kept as read, so the uploader refuses it (`PackageUploadError.stateMismatch`).
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .formatVersion)
    formatVersion = Self.readableFormatVersions.contains(version) ? Self.currentFormatVersion : version
    packageId = try container.decode(LowercaseUUID.self, forKey: .packageId)
    manifestSha256 = try container.decode(String.self, forKey: .manifestSha256)
    dealId = try container.decode(String.self, forKey: .dealId)
    files = try container.decode([FileUploadState].self, forKey: .files)
    sealResult = try container.decodeIfPresent(PackageSealResult.self, forKey: .sealResult)
    registeredAt = try container.decodeIfPresent(UTCTimestamp.self, forKey: .registeredAt)
    supersededBy = try container.decodeIfPresent(LowercaseUUID.self, forKey: .supersededBy)
    carriedOver = Set(try container.decodeIfPresent([String].self, forKey: .carriedOver) ?? [])
  }

  /// `carriedOver` is written sorted, so the same state always gives the same bytes.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(formatVersion, forKey: .formatVersion)
    try container.encode(packageId, forKey: .packageId)
    try container.encode(manifestSha256, forKey: .manifestSha256)
    try container.encode(dealId, forKey: .dealId)
    try container.encode(files, forKey: .files)
    try container.encodeIfPresent(sealResult, forKey: .sealResult)
    try container.encodeIfPresent(registeredAt, forKey: .registeredAt)
    try container.encodeIfPresent(supersededBy, forKey: .supersededBy)
    if !carriedOver.isEmpty {
      try container.encode(carriedOver.sorted(), forKey: .carriedOver)
    }
  }

  /// Every file is verified by the station.
  public var allFilesVerified: Bool { files.allSatisfy { $0.phase == .verified } }

  /// The station verified every file and registered the package. Only then may the app consider
  /// letting the phone's copy go (PackageKit itself never deletes anything).
  public var isConfirmedByStation: Bool {
    guard allFilesVerified, let sealResult else { return false }
    return sealResult.status != .uploading
  }

  /// Number of verified files.
  public var verifiedCount: Int { files.filter { $0.phase == .verified }.count }
}

/// Reads and writes the upload state file. Writes are atomic (temporary file and rename), the
/// file is readable by the owner only and, on iOS, protected until first unlock (background
/// uploads run while the phone is locked).
public struct UploadStateStore: Sendable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// `<package folder name>.upload-state.json` next to the package folder.
  public static func defaultURL(forPackageAt root: URL) -> URL {
    root.deletingLastPathComponent()
      .appendingPathComponent("\(root.lastPathComponent).upload-state.json")
  }

  public func load() throws -> UploadState? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      let data = try Data(contentsOf: url)
      return try CaptureContractJSON.makeDecoder().decode(UploadState.self, from: data)
    } catch {
      throw PackageUploadError.unreadableState(String(describing: error))
    }
  }

  public func save(_ state: UploadState) throws {
    do {
      let data = try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(state)
      #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      #else
        try data.write(to: url, options: .atomic)
      #endif
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
    } catch {
      throw PackageUploadError.unwritableState(String(describing: error))
    }
  }
}
