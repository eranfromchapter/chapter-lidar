import CaptureContract
import Foundation

// Request and response bodies of contract/openapi/station.yaml (components.schemas), one type per
// schema. Wire conventions follow the contract: optional fields are omitted when nil (synthesized
// Codable uses encodeIfPresent), timestamps are UTC whole seconds (`UTCTimestamp`), UUIDs are
// lowercase (`LowercaseUUID`). Document bodies (manifest, capture record, verdict) use the
// CaptureContract models.

// MARK: - Health

/// components.schemas.Health.
public struct Health: Hashable, Sendable, Codable {
  /// Always `ok`.
  public var status: String
  /// Station build version.
  public var version: String

  public init(status: String, version: String) {
    self.status = status
    self.version = version
  }
}

// MARK: - Problem

/// components.schemas.Problem: RFC 9457 problem details returned with every 4xx and 5xx.
public struct Problem: Hashable, Sendable, Codable {
  public var type: String
  public var title: String
  public var status: Int
  /// Stable machine-readable code, for example `verdict_not_ready` or `package_conflict`.
  public var code: String
  public var detail: String?
  /// Individual rule violations, for 400 and 422.
  public var errors: [FieldError]?

  public init(
    type: String, title: String, status: Int, code: String, detail: String? = nil,
    errors: [FieldError]? = nil
  ) {
    self.type = type
    self.title = title
    self.status = status
    self.code = code
    self.detail = detail
    self.errors = errors
  }

  public struct FieldError: Hashable, Sendable, Codable {
    /// JSON Pointer to the offending value in the request body.
    public var pointer: String
    public var message: String

    public init(pointer: String, message: String) {
      self.pointer = pointer
      self.message = message
    }
  }
}

// MARK: - Projects

/// components.schemas.HubProject: a HUB deal with its confirmed property address.
public struct HubProject: Hashable, Sendable, Codable {
  /// HUB sales deal id.
  public var dealId: String
  public var projectName: String?
  public var address: Address

  public init(dealId: String, projectName: String? = nil, address: Address) {
    self.dealId = dealId
    self.projectName = projectName
    self.address = address
  }

  public struct Address: Hashable, Sendable, Codable {
    /// Single-line address exactly as shown by the HUB. The app copies it into the capture
    /// record's `address.formatted` without rewriting it.
    public var formatted: String

    public init(formatted: String) {
      self.formatted = formatted
    }
  }

  /// True when the project carries a usable address. The station only returns deals whose
  /// address is confirmed in the HUB; this guards against an entry with a blank address.
  public var hasUsableAddress: Bool {
    !address.formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

/// Response body of `listProjects`.
public struct ProjectListResponse: Hashable, Sendable, Codable {
  public var projects: [HubProject]

  public init(projects: [HubProject]) {
    self.projects = projects
  }
}

// MARK: - Upload sessions

/// components.schemas.PackageStatus.
public enum PackageStatus: String, CaseIterable, Sendable, Codable {
  case uploading
  case checksQueued = "checks_queued"
  case checking
  case verdictReady = "verdict_ready"
  case checkError = "check_error"
}

/// components.schemas.FileStatus.
public enum FileStatus: String, CaseIterable, Sendable, Codable {
  case pending
  case verified
  case sha256Mismatch = "sha256_mismatch"
  case bytesMismatch = "bytes_mismatch"
  case notUploaded = "not_uploaded"
}

/// components.schemas.UploadFileDeclaration: one manifest file entry, declared before upload.
public struct UploadFileDeclaration: Hashable, Sendable, Codable {
  public var path: String
  public var role: FileRole
  /// Required for every role except capture_record and field_controls, which omit it.
  public var captureId: LowercaseUUID?
  /// Present exactly when `captureId` is.
  public var areaKey: String?
  /// Lowercase hex SHA-256.
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
}

/// components.schemas.UploadSessionRequest.
public struct UploadSessionRequest: Hashable, Sendable, Codable {
  public var packageId: LowercaseUUID
  public var visitId: LowercaseUUID
  public var dealId: String
  public var revision: Int
  /// Required when `revision` is greater than 1, omitted otherwise.
  public var supersedesPackageId: LowercaseUUID?
  /// Every file of the manifest; paths are unique.
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
}

/// components.schemas.UploadTarget: a write-only Azure Blob SAS URL for one file.
///
/// The URL carries a signature, so `description`, `debugDescription` and `dump` redact it.
public struct UploadTarget: Hashable, Sendable, Codable {
  public enum Method: String, Hashable, Sendable, Codable {
    case put = "PUT"
  }

  public var url: URL
  public var method: Method
  /// Headers to send with the upload, for example `x-ms-blob-type: BlockBlob`.
  public var headers: [String: String]
  public var expiresAt: UTCTimestamp

  public init(url: URL, method: Method = .put, headers: [String: String], expiresAt: UTCTimestamp) {
    self.url = url
    self.method = method
    self.headers = headers
    self.expiresAt = expiresAt
  }
}

extension UploadTarget: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
  public var description: String {
    "UploadTarget(url: <redacted>, method: \(method.rawValue), expiresAt: \(expiresAt))"
  }
  public var debugDescription: String { description }
  public var customMirror: Mirror {
    Mirror(
      self,
      children: ["url": "<redacted>", "method": method, "expiresAt": expiresAt],
      displayStyle: .struct)
  }
}

/// components.schemas.UploadSessionFile.
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

/// components.schemas.UploadSession.
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

/// components.schemas.FileCheckResult: the station's server-side check of one uploaded file.
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

/// Request body of `completeFile`.
public struct CompleteFileRequest: Hashable, Sendable, Codable {
  public var path: String

  public init(path: String) {
    self.path = path
  }
}

// MARK: - Packages

/// components.schemas.PackageFile.
public struct PackageFile: Hashable, Sendable, Codable {
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

/// components.schemas.VerdictSummary.
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

/// components.schemas.PackageSummary.
public struct PackageSummary: Hashable, Sendable, Codable {
  public var packageId: LowercaseUUID
  public var visitId: LowercaseUUID
  public var dealId: String
  public var revision: Int
  public var supersedesPackageId: LowercaseUUID?
  public var status: PackageStatus
  /// When the upload session was opened.
  public var createdAt: UTCTimestamp
  /// The manifest's sealedAt. Present once the package is sealed at the station.
  public var sealedAt: UTCTimestamp?
  /// Present when status is verdict_ready.
  public var verdict: VerdictSummary?

  public init(
    packageId: LowercaseUUID, visitId: LowercaseUUID, dealId: String, revision: Int,
    supersedesPackageId: LowercaseUUID? = nil, status: PackageStatus, createdAt: UTCTimestamp,
    sealedAt: UTCTimestamp? = nil, verdict: VerdictSummary? = nil
  ) {
    self.packageId = packageId
    self.visitId = visitId
    self.dealId = dealId
    self.revision = revision
    self.supersedesPackageId = supersedesPackageId
    self.status = status
    self.createdAt = createdAt
    self.sealedAt = sealedAt
    self.verdict = verdict
  }
}

/// Response body of `listPackages`.
public struct PackageListResponse: Hashable, Sendable, Codable {
  public var packages: [PackageSummary]

  public init(packages: [PackageSummary]) {
    self.packages = packages
  }
}

/// components.schemas.Package: a package with its files. Manifest and capture record are present
/// once sealed.
public struct Package: Hashable, Sendable, Codable {
  public var packageId: LowercaseUUID
  public var visitId: LowercaseUUID
  public var dealId: String
  public var revision: Int
  public var supersedesPackageId: LowercaseUUID?
  public var status: PackageStatus
  public var createdAt: UTCTimestamp
  public var sealedAt: UTCTimestamp?
  public var files: [PackageFile]
  /// The registered manifest. Present once sealed.
  public var manifest: PackageManifest?
  /// The package's capture record file. Present once sealed.
  public var captureRecord: CaptureRecord?
  /// Present when status is verdict_ready.
  public var verdict: VerdictSummary?

  public init(
    packageId: LowercaseUUID, visitId: LowercaseUUID, dealId: String, revision: Int,
    supersedesPackageId: LowercaseUUID? = nil, status: PackageStatus, createdAt: UTCTimestamp,
    sealedAt: UTCTimestamp? = nil, files: [PackageFile], manifest: PackageManifest? = nil,
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

/// components.schemas.DownloadLink: a short-lived read-only link to one verified original.
///
/// The URL carries a signature, so `description`, `debugDescription` and `dump` redact it.
public struct DownloadLink: Hashable, Sendable, Codable {
  public var path: String
  /// Verified SHA-256 of the file, to check the download against.
  public var sha256: String
  public var bytes: Int64
  public var url: URL
  public var expiresAt: UTCTimestamp

  public init(path: String, sha256: String, bytes: Int64, url: URL, expiresAt: UTCTimestamp) {
    self.path = path
    self.sha256 = sha256
    self.bytes = bytes
    self.url = url
    self.expiresAt = expiresAt
  }
}

extension DownloadLink: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
  public var description: String {
    "DownloadLink(path: \(path), sha256: \(sha256), bytes: \(bytes), url: <redacted>, "
      + "expiresAt: \(expiresAt))"
  }
  public var debugDescription: String { description }
  public var customMirror: Mirror {
    Mirror(
      self,
      children: [
        "path": path, "sha256": sha256, "bytes": bytes, "url": "<redacted>",
        "expiresAt": expiresAt,
      ],
      displayStyle: .struct)
  }
}

// MARK: - Modeling decisions

/// components.schemas.DecisionSource.
public struct DecisionSource: Hashable, Sendable, Codable {
  public var path: String
  public var controlId: String?
  public var elementId: String?

  public init(path: String, controlId: String? = nil, elementId: String? = nil) {
    self.path = path
    self.controlId = controlId
    self.elementId = elementId
  }
}

/// components.schemas.ModelingDecisionInput.
public struct ModelingDecisionInput: Hashable, Sendable, Codable {
  public var element: String
  public var decision: String
  public var captureId: LowercaseUUID?
  /// Present exactly when `captureId` is.
  public var areaKey: String?
  public var sources: [DecisionSource]
  public var note: String?

  public init(
    element: String, decision: String, captureId: LowercaseUUID? = nil, areaKey: String? = nil,
    sources: [DecisionSource], note: String? = nil
  ) {
    self.element = element
    self.decision = decision
    self.captureId = captureId
    self.areaKey = areaKey
    self.sources = sources
    self.note = note
  }
}

/// components.schemas.ModelingDecision.
public struct ModelingDecision: Hashable, Sendable, Codable {
  public var decisionId: LowercaseUUID
  public var packageId: LowercaseUUID
  public var element: String
  public var decision: String
  public var captureId: LowercaseUUID?
  public var areaKey: String?
  public var sources: [DecisionSource]
  public var note: String?
  public var decidedBy: DecidedBy
  public var decidedAt: UTCTimestamp

  public init(
    decisionId: LowercaseUUID, packageId: LowercaseUUID, element: String, decision: String,
    captureId: LowercaseUUID? = nil, areaKey: String? = nil, sources: [DecisionSource],
    note: String? = nil, decidedBy: DecidedBy, decidedAt: UTCTimestamp
  ) {
    self.decisionId = decisionId
    self.packageId = packageId
    self.element = element
    self.decision = decision
    self.captureId = captureId
    self.areaKey = areaKey
    self.sources = sources
    self.note = note
    self.decidedBy = decidedBy
    self.decidedAt = decidedAt
  }

  /// The signed-in user who logged the decision.
  public struct DecidedBy: Hashable, Sendable, Codable {
    public var name: String
    /// Entra ID object id of the user.
    public var userId: String

    public init(name: String, userId: String) {
      self.name = name
      self.userId = userId
    }
  }
}

/// Response body of `listModelingDecisions`.
public struct ModelingDecisionListResponse: Hashable, Sendable, Codable {
  public var decisions: [ModelingDecision]

  public init(decisions: [ModelingDecision]) {
    self.decisions = decisions
  }
}
