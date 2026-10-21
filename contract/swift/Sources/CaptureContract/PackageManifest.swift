/// contract/schema/manifest.schema.json: inventory of one sealed intake package for one site
/// visit, one entry per file. Written at sealing as `Source Register/{visitId}/manifest.json`;
/// the manifest does not list itself. Files of one capture carry its `captureId` and `areaKey`;
/// visit-wide files (`FileRole.visitRoles`) carry neither. A changed package is a new revision
/// with a new `packageId`.
///
/// Reads schema 1.0.0 and 1.1.0 and writes `ManifestSchemaVersion.current`, with one exception:
/// a manifest that lists a retired role is written as 1.0.0, the only version that allows it
/// (`writtenSchemaVersion`). That is a package sealed by an app before v2, or one sealed while
/// PlanExport still writes the phone report. A manifest that lists a retired role and a field
/// added in 1.1.0 (`photo.directionSource`) fits neither version and does not encode.
public struct PackageManifest: Hashable, Sendable, Codable {
  /// The version this manifest was read as; `.current` for a new manifest. What is written is
  /// `writtenSchemaVersion`.
  public var schemaVersion: ManifestSchemaVersion
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
    schemaVersion: ManifestSchemaVersion = .current,
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

  /// The `schemaVersion` this manifest is written with: 1.0.0 when it lists a retired role (1.1.0
  /// does not allow those files), else `current`. It does not depend on the version read, so a
  /// new manifest that still lists the phone report is valid too.
  public var writtenSchemaVersion: ManifestSchemaVersion {
    files.contains(where: { $0.role.isRetired }) ? .v1 : .current
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, layoutVersion, packageId, visitId, revision, supersedesPackageId
    case sealedAt, files
  }

  // Decoding is synthesized: `schemaVersion` accepts every `ManifestSchemaVersion`.

  /// Throws `EncodingError.invalidValue` for a manifest that fits no schema version: a retired
  /// role (1.0.0 only) next to `photo.directionSource` (1.1.0 only).
  public func encode(to encoder: Encoder) throws {
    let version = writtenSchemaVersion
    if version == .v1,
      let retired = files.first(where: { $0.role.isRetired }),
      let photo = files.first(where: { $0.photo?.directionSource != nil })
    {
      throw EncodingError.invalidValue(
        self,
        EncodingError.Context(
          codingPath: [CodingKeys.files],
          debugDescription:
            "\(retired.path) has the retired role \(retired.role.rawValue), which only manifest "
            + "1.0.0 allows, and \(photo.path) has photo.directionSource, which only 1.1.0 "
            + "allows; leave the retired file out of the package"))
    }
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .schemaVersion)
    try container.encode(layoutVersion, forKey: .layoutVersion)
    try container.encode(packageId, forKey: .packageId)
    try container.encode(visitId, forKey: .visitId)
    try container.encode(revision, forKey: .revision)
    try container.encodeIfPresent(supersedesPackageId, forKey: .supersedesPackageId)
    try container.encode(sealedAt, forKey: .sealedAt)
    try container.encode(files, forKey: .files)
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
    /// How `direction` was set (1.1.0). Nil in 1.0.0 documents and for labels written before it
    /// existed.
    public var directionSource: PhotoDirectionSource?

    public init(
      room: String, direction: PhotoDirection, subject: PhotoSubject, takenAt: UTCTimestamp,
      directionSource: PhotoDirectionSource? = nil
    ) {
      self.room = room
      self.direction = direction
      self.subject = subject
      self.takenAt = takenAt
      self.directionSource = directionSource
    }
  }
}
