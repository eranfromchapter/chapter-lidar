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
  /// Present when the file is verified because revision N-1 (`supersedesPackageId`) holds the
  /// same verified file; no upload target is granted then (station 1.1.0).
  public var carriedOverFrom: LowercaseUUID?

  public init(
    path: String, status: FileStatus, upload: UploadTarget? = nil,
    carriedOverFrom: LowercaseUUID? = nil
  ) {
    self.path = path
    self.status = status
    self.upload = upload
    self.carriedOverFrom = carriedOverFrom
  }
}

/// components.schemas.UploadSession.
public struct UploadSession: Hashable, Sendable, Codable {
  public var packageId: LowercaseUUID
  public var visitId: LowercaseUUID
  public var dealId: String
  public var revision: Int
  public var status: PackageStatus
  /// When the station registered the package (the session was first opened). Shown as
  /// "Registered" on the phone. Stations before 1.1.0 omit it.
  public var createdAt: UTCTimestamp?
  public var files: [UploadSessionFile]

  public init(
    packageId: LowercaseUUID, visitId: LowercaseUUID, dealId: String, revision: Int,
    status: PackageStatus, createdAt: UTCTimestamp? = nil, files: [UploadSessionFile]
  ) {
    self.packageId = packageId
    self.visitId = visitId
    self.dealId = dealId
    self.revision = revision
    self.status = status
    self.createdAt = createdAt
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
  /// Present when the file was verified by carry-over from that package (revision N-1).
  public var carriedOverFrom: LowercaseUUID?

  public init(
    path: String, role: FileRole, captureId: LowercaseUUID? = nil, areaKey: String? = nil,
    sha256: String, bytes: Int64, status: FileStatus, checkedAt: UTCTimestamp? = nil,
    carriedOverFrom: LowercaseUUID? = nil
  ) {
    self.path = path
    self.role = role
    self.captureId = captureId
    self.areaKey = areaKey
    self.sha256 = sha256
    self.bytes = bytes
    self.status = status
    self.checkedAt = checkedAt
    self.carriedOverFrom = carriedOverFrom
  }
}

/// components.schemas.CheckRunSummary: the latest check run of a package. Omitted before the
/// seal.
public struct CheckRunSummary: Hashable, Sendable, Codable {
  public enum Status: String, CaseIterable, Hashable, Sendable, Codable {
    /// Sealed, no run yet.
    case queued
    case running
    case completed
    /// The station could not finish the checks (it retries).
    case failed
  }

  public var status: Status
  public var startedAt: UTCTimestamp?
  /// Present when completed or failed.
  public var finishedAt: UTCTimestamp?
  /// Rules run. Present when completed.
  public var rules: Int?

  public init(
    status: Status, startedAt: UTCTimestamp? = nil, finishedAt: UTCTimestamp? = nil,
    rules: Int? = nil
  ) {
    self.status = status
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.rules = rules
  }
}

/// components.schemas.PublicationSummary: HUB publication of this revision. Omitted when
/// nothing was queued.
public struct PublicationSummary: Hashable, Sendable, Codable {
  public enum Status: String, CaseIterable, Hashable, Sendable, Codable {
    case pending
    case publishing
    case published
    case publishFailed = "publish_failed"
  }

  public var status: Status
  /// Present exactly when published.
  public var publishedAt: UTCTimestamp?
  /// The revision's HUB folder, `Capture/{visitId}/r{revision}`.
  public var hubFolder: String

  public init(status: Status, publishedAt: UTCTimestamp? = nil, hubFolder: String) {
    self.status = status
    self.publishedAt = publishedAt
    self.hubFolder = hubFolder
  }
}

/// components.schemas.PackageLinks: web pages of a package.
public struct PackageLinks: Hashable, Sendable, Codable {
  /// The package page of the review screen.
  public var review: URL
  /// The HUB page of the deal. Omitted when the station has no HUB deal URL configured.
  public var hub: URL?

  public init(review: URL, hub: URL? = nil) {
    self.review = review
    self.hub = hub
  }
}

/// components.schemas.NextRevisionChange: one row of what the next revision adds, changes or
/// removes, worded as the phone shows it.
public struct NextRevisionChange: Hashable, Sendable, Codable {
  public enum Kind: String, CaseIterable, Hashable, Sendable, Codable {
    case added
    case changed
    case removed
  }

  public enum Subject: String, CaseIterable, Hashable, Sendable, Codable {
    case capture
    case roomNames = "room_names"
    case fieldControl = "field_control"
    case photos
    case retiredFile = "retired_file"
  }

  public var kind: Kind
  public var subject: Subject
  /// 1 to 200 characters.
  public var title: String
  /// 1 to 300 characters.
  public var detail: String
  /// A next action of the base verdict, verbatim, that this change answers.
  public var answersNextAction: String?
  /// Instrument of a field-control change.
  public var method: MeasurementMethod?

  public init(
    kind: Kind, subject: Subject, title: String, detail: String, answersNextAction: String? = nil,
    method: MeasurementMethod? = nil
  ) {
    self.kind = kind
    self.subject = subject
    self.title = title
    self.detail = detail
    self.answersNextAction = answersNextAction
    self.method = method
  }
}

/// components.schemas.NextRevisionNoticeInput: what the phone sends; the station adds
/// `updatedBy`.
public struct NextRevisionNoticeInput: Hashable, Sendable, Codable {
  /// The revision being prepared, the package's revision + 1 (at least 2).
  public var revision: Int
  /// When the phone last changed the revision.
  public var updatedAt: UTCTimestamp
  /// At most 50.
  public var changes: [NextRevisionChange]

  public init(revision: Int, updatedAt: UTCTimestamp, changes: [NextRevisionChange]) {
    self.revision = revision
    self.updatedAt = updatedAt
    self.changes = changes
  }
}

/// components.schemas.NextRevisionNotice: the next revision as the phone last described it,
/// present on a sealed package while its next revision is in progress on the phone.
public struct NextRevisionNotice: Hashable, Sendable, Codable {
  public var revision: Int
  public var updatedAt: UTCTimestamp
  /// Name of the signed-in user who sent the notice (set by the station).
  public var updatedBy: String?
  public var changes: [NextRevisionChange]

  public init(
    revision: Int, updatedAt: UTCTimestamp, updatedBy: String? = nil,
    changes: [NextRevisionChange]
  ) {
    self.revision = revision
    self.updatedAt = updatedAt
    self.updatedBy = updatedBy
    self.changes = changes
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
  /// The latest check run (station 1.1.0). Omitted before the seal.
  public var checks: CheckRunSummary?
  /// HUB publication of this revision (station 1.1.0). Omitted when nothing was queued.
  public var publication: PublicationSummary?
  /// Web pages of the package (station 1.1.0).
  public var links: PackageLinks?

  public init(
    packageId: LowercaseUUID, visitId: LowercaseUUID, dealId: String, revision: Int,
    supersedesPackageId: LowercaseUUID? = nil, status: PackageStatus, createdAt: UTCTimestamp,
    sealedAt: UTCTimestamp? = nil, verdict: VerdictSummary? = nil,
    checks: CheckRunSummary? = nil, publication: PublicationSummary? = nil,
    links: PackageLinks? = nil
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
    self.checks = checks
    self.publication = publication
    self.links = links
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
  /// The latest check run (station 1.1.0). Omitted before the seal.
  public var checks: CheckRunSummary?
  /// HUB publication of this revision (station 1.1.0). Omitted when nothing was queued.
  public var publication: PublicationSummary?
  /// Web pages of the package (station 1.1.0).
  public var links: PackageLinks?
  /// The next revision while the phone prepares it (station 1.1.0, `putNextRevisionNotice`).
  public var nextRevision: NextRevisionNotice?

  public init(
    packageId: LowercaseUUID, visitId: LowercaseUUID, dealId: String, revision: Int,
    supersedesPackageId: LowercaseUUID? = nil, status: PackageStatus, createdAt: UTCTimestamp,
    sealedAt: UTCTimestamp? = nil, files: [PackageFile], manifest: PackageManifest? = nil,
    captureRecord: CaptureRecord? = nil, verdict: VerdictSummary? = nil,
    checks: CheckRunSummary? = nil, publication: PublicationSummary? = nil,
    links: PackageLinks? = nil, nextRevision: NextRevisionNotice? = nil
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
    self.checks = checks
    self.publication = publication
    self.links = links
    self.nextRevision = nextRevision
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

// MARK: - Sketch interpretations

/// components.schemas.SketchInterpretationRequest (spec F16): a photo of a floor-plan sketch for
/// Claude to read. `data` is the image, base64; `mediaType` one the Claude API accepts
/// (`image/jpeg`, `image/png`, `image/webp`, `image/gif`; the app converts HEIC and PDF to JPEG).
/// At most 10 MB of image.
public struct SketchInterpretationRequest: Hashable, Sendable, Codable {
  public var mediaType: String
  /// The image bytes, standard base64 with padding.
  public var data: String
  /// A note for the reader ("the plan is in metres"), when the operator gave one.
  public var hint: String?

  public init(mediaType: String, imageData: Data, hint: String? = nil) {
    self.mediaType = mediaType
    self.data = imageData.base64EncodedString()
    self.hint = hint
  }
}

/// The 422 answer of `POST /sketch-interpretations`: problem details, `sketch_not_a_plan` with,
/// as an RFC 9457 extension member, what Claude read (`interpretation`), or `sketch_refused`
/// (Claude declined to read the photo; no interpretation).
struct SketchInterpretationRejectionBody: Decodable {
  var interpretation: SketchInterpretation?
}

/// The station read the photo and found no floor plan in it (`sketch_not_a_plan`), or Claude
/// declined to read it (`sketch_refused`): 422. The interpretation's `reading.problem` says why,
/// in Claude's words, when the station sent it.
public struct SketchInterpretationRejected: Error, Hashable, Sendable {
  public var problem: Problem?
  public var interpretation: SketchInterpretation?

  public init(problem: Problem?, interpretation: SketchInterpretation?) {
    self.problem = problem
    self.interpretation = interpretation
  }

  /// Why, in words: the reading's problem, else the problem's detail or title.
  public var reason: String {
    if let why = interpretation?.reading.problem, !why.isEmpty { return why }
    if let detail = problem?.detail, !detail.isEmpty { return detail }
    return problem?.title ?? "The photo could not be read as a floor plan."
  }
}
