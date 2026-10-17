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

  public static let currentFormatVersion = 1

  public init(package: SealedPackage, dealId: String) {
    formatVersion = Self.currentFormatVersion
    packageId = package.packageId
    manifestSha256 = SHA256.hexDigest(of: package.manifestData)
    self.dealId = dealId
    files = package.manifest.files.map {
      FileUploadState(path: $0.path, sha256: $0.sha256, bytes: $0.bytes)
    }
    sealResult = nil
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
