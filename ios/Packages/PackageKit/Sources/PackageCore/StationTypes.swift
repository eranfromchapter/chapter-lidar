import CaptureContract
import Foundation

// Codable mirrors of the upload schemas in contract/openapi/station.yaml (UploadFileDeclaration,
// UploadSessionRequest, UploadSession, UploadSessionFile, UploadTarget, FileStatus,
// FileCheckResult, PackageStatus, PackageFile, VerdictSummary, Package). Optional fields are
// omitted when nil, never null. Encode with CaptureContractJSON.makeEncoder().

/// Server-side state of one declared file (FileStatus).
public enum FileStatus: String, CaseIterable, Codable, Sendable {
  /// No verified upload yet.
  case pending
  /// The stored blob matches the declared SHA-256 and size.
  case verified
  case sha256Mismatch = "sha256_mismatch"
  case bytesMismatch = "bytes_mismatch"
  /// No blob found at the target.
  case notUploaded = "not_uploaded"
}

/// State of a package at the station (PackageStatus).
public enum PackageStatus: String, CaseIterable, Codable, Sendable {
  case uploading
  case checksQueued = "checks_queued"
  case checking
  case verdictReady = "verdict_ready"
  case checkError = "check_error"
}

/// One manifest file entry as declared before upload (UploadFileDeclaration).
public struct UploadFileDeclaration: Hashable, Sendable, Codable {
  public var path: String
  public var role: FileRole
  /// Nil exactly for the visit-wide roles.
  public var captureId: LowercaseUUID?
  /// Present exactly when `captureId` is.
  public var areaKey: String?
  public var sha256: String
  public var bytes: Int64

  public init(
    path: String, role: FileRole, captureId: LowercaseUUID? = nil, areaKey: String? = nil,
    sha256: String, bytes: Int64
  ) {
    self.path = path
    self.role = role
    self.captureId = captureId
    self.areaKey = areaKey
    self.sha256 = sha256
    self.bytes = bytes
  }

  public init(_ entry: PackageManifest.FileEntry) {
    self.init(
      path: entry.path, role: entry.role, captureId: entry.captureId, areaKey: entry.areaKey,
      sha256: entry.sha256, bytes: entry.bytes)
  }
}

/// Body of `POST /packages` (createUploadSession). Repeating the same body resumes the session.
public struct UploadSessionRequest: Hashable, Sendable, Codable {
  public var packageId: LowercaseUUID
  public var visitId: LowercaseUUID
  /// HUB deal id.
  public var dealId: String
  public var revision: Int
  /// Required when `revision` is greater than 1, omitted otherwise.
  public var supersedesPackageId: LowercaseUUID?
  /// Every file of the manifest, in manifest order.
  public var files: [UploadFileDeclaration]

  public init(
    packageId: LowercaseUUID, visitId: LowercaseUUID, dealId: String, revision: Int,
    supersedesPackageId: LowercaseUUID? = nil, files: [UploadFileDeclaration]
  ) {
    self.packageId = packageId
    self.visitId = visitId
    self.dealId = dealId
    self.revision = revision
    self.supersedesPackageId = supersedesPackageId
    self.files = files
  }

  /// The session request of a sealed package: its manifest identity and file list.
  public init(manifest: PackageManifest, dealId: String) {
    self.init(
      packageId: manifest.packageId, visitId: manifest.visitId, dealId: dealId,
      revision: manifest.revision, supersedesPackageId: manifest.supersedesPackageId,
      files: manifest.files.map(UploadFileDeclaration.init))
  }
}

/// Write-only Azure Blob SAS URL for one file (UploadTarget). The URL is a credential until it
/// expires: it is never logged, and `description`, `debugDescription` and `dump` redact it.
public struct UploadTarget: Hashable, Sendable, Codable, CustomStringConvertible,
  CustomDebugStringConvertible, CustomReflectable
{
  /// SAS URL, exactly as issued. Never rebuilt, re-encoded or logged.
  public var url: String
  /// Always PUT.
  public var method: String
  /// Headers to send with the upload, for example x-ms-blob-type BlockBlob.
  public var headers: [String: String]
  public var expiresAt: UTCTimestamp

  public init(url: String, method: String = "PUT", headers: [String: String], expiresAt: UTCTimestamp)
  {
    self.url = url
    self.method = method
    self.headers = headers
    self.expiresAt = expiresAt
  }

  /// Scheme, host and path of the URL, without the SAS query. Identifies the blob; safe to log.
  public var blobLocation: String {
    guard let components = URLComponents(string: url) else { return "" }
    var location = components
    location.query = nil
    location.fragment = nil
    location.user = nil
    location.password = nil
    return location.string ?? ""
  }

  public var description: String {
    "UploadTarget(method: \(method), expiresAt: \(expiresAt), url: <redacted>)"
  }

  public var debugDescription: String { description }

  public var customMirror: Mirror {
    Mirror(
      self,
      children: ["method": method, "expiresAt": expiresAt, "url": "<redacted>"],
      displayStyle: .struct)
  }
}

/// One file of an upload session (UploadSessionFile).
public struct UploadSessionFile: Hashable, Sendable, Codable {
  public var path: String
  public var status: FileStatus
  /// Present for every file that is not verified.
  public var upload: UploadTarget?

  public init(path: String, status: FileStatus, upload: UploadTarget? = nil) {
    self.path = path
    self.status = status
    self.upload = upload
  }
}

/// Response of `POST /packages` (UploadSession).
public struct UploadSession: Hashable, Sendable, Codable {
  public var packageId: LowercaseUUID
  public var visitId: LowercaseUUID
  public var dealId: String
  public var revision: Int
  public var status: PackageStatus
  public var files: [UploadSessionFile]

  public init(
    packageId: LowercaseUUID, visitId: LowercaseUUID, dealId: String, revision: Int,
    status: PackageStatus, files: [UploadSessionFile]
  ) {
    self.packageId = packageId
    self.visitId = visitId
    self.dealId = dealId
    self.revision = revision
    self.status = status
    self.files = files
  }
}

/// Server-side check of one uploaded file (FileCheckResult).
public struct FileCheckResult: Hashable, Sendable, Codable {
  public var path: String
  public var status: FileStatus
  public var expectedSha256: String
  /// SHA-256 of the stored blob. Omitted when status is not_uploaded.
  public var actualSha256: String?
  public var expectedBytes: Int64
  /// Size of the stored blob. Omitted when status is not_uploaded.
  public var actualBytes: Int64?
  public var checkedAt: UTCTimestamp

  public init(
    path: String, status: FileStatus, expectedSha256: String, actualSha256: String? = nil,
    expectedBytes: Int64, actualBytes: Int64? = nil, checkedAt: UTCTimestamp
  ) {
    self.path = path
    self.status = status
    self.expectedSha256 = expectedSha256
    self.actualSha256 = actualSha256
    self.expectedBytes = expectedBytes
    self.actualBytes = actualBytes
    self.checkedAt = checkedAt
  }
}

/// One file of a package at the station (PackageFile).
public struct PackageFileStatus: Hashable, Sendable, Codable {
  public var path: String
  public var role: FileRole
  public var captureId: LowercaseUUID?
  public var areaKey: String?
  public var sha256: String
  public var bytes: Int64
  public var status: FileStatus
  /// Time of the last server-side check. Omitted while pending.
  public var checkedAt: UTCTimestamp?

  public init(
    path: String, role: FileRole, captureId: LowercaseUUID? = nil, areaKey: String? = nil,
    sha256: String, bytes: Int64, status: FileStatus, checkedAt: UTCTimestamp? = nil
  ) {
    self.path = path
    self.role = role
    self.captureId = captureId
    self.areaKey = areaKey
    self.sha256 = sha256
    self.bytes = bytes
    self.status = status
    self.checkedAt = checkedAt
  }
}

/// Verdict of a package (VerdictSummary).
public struct VerdictSummary: Hashable, Sendable, Codable {
  public var verdictId: LowercaseUUID
  public var outcome: VerdictOutcome
  public var evaluatedAt: UTCTimestamp

  public init(verdictId: LowercaseUUID, outcome: VerdictOutcome, evaluatedAt: UTCTimestamp) {
    self.verdictId = verdictId
    self.outcome = outcome
    self.evaluatedAt = evaluatedAt
  }
}

/// Response of `POST /packages/{packageId}/seal`: the package with its files (Package).
public struct PackageSealResult: Hashable, Sendable, Codable {
  public var packageId: LowercaseUUID
  public var visitId: LowercaseUUID
  public var dealId: String
  public var revision: Int
  public var supersedesPackageId: LowercaseUUID?
  public var status: PackageStatus
  public var createdAt: UTCTimestamp
  public var sealedAt: UTCTimestamp?
  public var files: [PackageFileStatus]
  /// The registered manifest. Present once sealed.
  public var manifest: PackageManifest?
  /// The package's capture record. Present once sealed.
  public var captureRecord: CaptureRecord?
  /// Present when status is verdict_ready.
  public var verdict: VerdictSummary?

  public init(
    packageId: LowercaseUUID, visitId: LowercaseUUID, dealId: String, revision: Int,
    supersedesPackageId: LowercaseUUID? = nil, status: PackageStatus, createdAt: UTCTimestamp,
    sealedAt: UTCTimestamp? = nil, files: [PackageFileStatus], manifest: PackageManifest? = nil,
    captureRecord: CaptureRecord? = nil, verdict: VerdictSummary? = nil
  ) {
    self.packageId = packageId
    self.visitId = visitId
    self.dealId = dealId
    self.revision = revision
    self.supersedesPackageId = supersedesPackageId
    self.status = status
    self.createdAt = createdAt
    self.sealedAt = sealedAt
    self.files = files
    self.manifest = manifest
    self.captureRecord = captureRecord
    self.verdict = verdict
  }
}
