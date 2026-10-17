/// contract/schema/manifest.schema.json: inventory of one sealed intake package for one site
/// visit, one entry per file. Written at sealing as `Source Register/{visitId}/manifest.json`;
/// the manifest does not list itself. Files of one capture carry its `captureId` and `areaKey`;
/// visit-wide files (`FileRole.visitRoles`) carry neither. A changed package is a new revision
/// with a new `packageId`.
public struct PackageManifest: Hashable, Sendable, Codable {
  public var schemaVersion: SchemaVersion
  public var layoutVersion: LayoutVersion
  public var packageId: LowercaseUUID
  public var visitId: LowercaseUUID
  /// Package revision for this visit, starting at 1.
  public var revision: Int
  /// `packageId` of the previous revision. Present only when `revision` is greater than 1.
  public var supersedesPackageId: LowercaseUUID?
  public var sealedAt: UTCTimestamp
  public var files: [FileEntry]

  public init(
    schemaVersion: SchemaVersion = .current,
    layoutVersion: LayoutVersion = .current,
    packageId: LowercaseUUID,
    visitId: LowercaseUUID,
    revision: Int,
    supersedesPackageId: LowercaseUUID? = nil,
    sealedAt: UTCTimestamp,
    files: [FileEntry]
  ) {
    self.schemaVersion = schemaVersion
    self.layoutVersion = layoutVersion
    self.packageId = packageId
    self.visitId = visitId
    self.revision = revision
    self.supersedesPackageId = supersedesPackageId
    self.sealedAt = sealedAt
    self.files = files
  }

  public struct FileEntry: Hashable, Sendable, Codable {
    /// Path relative to the package root, forward slashes.
    public var path: String
    public var role: FileRole
    /// Capture the file belongs to. Nil exactly for visit-wide roles.
    public var captureId: LowercaseUUID?
    /// Floor or area key of that capture. Present exactly when `captureId` is.
    public var areaKey: String?
    /// Lowercase hex SHA-256 of the file bytes.
    public var sha256: String
    public var bytes: Int64
    public var mime: String
    /// Component that wrote the file, for example chapter-capture-ios/PlanExport.
    public var generator: String
    public var generatorVersion: String
    /// Paths of the package files this file was derived from. Empty for originals.
    public var derivedFrom: [String]
    /// Labels of a site photograph. Present exactly when `role` is `photo`.
    public var photo: PhotoLabels?

    public init(
      path: String,
      role: FileRole,
      captureId: LowercaseUUID? = nil,
      areaKey: String? = nil,
      sha256: String,
      bytes: Int64,
      mime: String,
      generator: String,
      generatorVersion: String,
      derivedFrom: [String] = [],
      photo: PhotoLabels? = nil
    ) {
      self.path = path
      self.role = role
      self.captureId = captureId
      self.areaKey = areaKey
      self.sha256 = sha256
      self.bytes = bytes
      self.mime = mime
      self.generator = generator
      self.generatorVersion = generatorVersion
      self.derivedFrom = derivedFrom
      self.photo = photo
    }
  }

  /// Labels of a site photograph.
  public struct PhotoLabels: Hashable, Sendable, Codable {
    /// Room label, matching the capture model room label.
    public var room: String
    public var direction: PhotoDirection
    public var subject: PhotoSubject
    public var takenAt: UTCTimestamp

    public init(
      room: String, direction: PhotoDirection, subject: PhotoSubject, takenAt: UTCTimestamp
    ) {
      self.room = room
      self.direction = direction
      self.subject = subject
      self.takenAt = takenAt
    }
  }
}
