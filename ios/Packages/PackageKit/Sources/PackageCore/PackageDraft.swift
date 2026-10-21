import CaptureContract
import Foundation

/// One file to put into a package: the file on disk plus its manifest metadata. The source is
/// only ever read; its bytes go into the package unchanged.
public struct PackageFileInput: Hashable, Sendable {
  /// The file on disk (for example a RoomPlan export, a photo or a plan written by an exporter).
  public var source: URL
  public var role: FileRole
  /// Name in the role's folder; may contain subfolders (mesh companions). Roles with a fixed name
  /// in layout.json must use it.
  public var fileName: String
  /// The capture the file belongs to. Nil exactly for the visit-wide roles.
  public var capture: CaptureRef?
  public var mime: String
  /// Component that wrote the file, for example chapter-capture-ios/PlanExport.
  public var generator: String
  public var generatorVersion: String
  /// Package paths of the files this one was derived from (they must be added first). Empty for
  /// originals. Use `PackageDraft.path(role:fileName:capture:)` or the path `add` returns.
  public var derivedFrom: [String]
  /// Labels of a site photograph. Required exactly when `role` is photo.
  public var photo: PackageManifest.PhotoLabels?
  /// Fingerprint the source must have, when known (files carried over from a sealed revision).
  /// Assembly fails if the source differs.
  public var expected: FileDigest?

  public init(
    source: URL,
    role: FileRole,
    fileName: String,
    capture: CaptureRef? = nil,
    mime: String,
    generator: String,
    generatorVersion: String,
    derivedFrom: [String] = [],
    photo: PackageManifest.PhotoLabels? = nil,
    expected: FileDigest? = nil
  ) {
    self.source = source
    self.role = role
    self.fileName = fileName
    self.capture = capture
    self.mime = mime
    self.generator = generator
    self.generatorVersion = generatorVersion
    self.derivedFrom = derivedFrom
    self.photo = photo
    self.expected = expected
  }
}

/// The files of one package before it is assembled and sealed. One package is one site visit;
/// its captures are the floor or area scans. Every rule of the manifest schema and layout.json
/// that can be checked before the bytes are read is checked when a file is added.
public struct PackageDraft: Sendable {
  /// One planned file with its package path.
  public struct Entry: Hashable, Sendable {
    public let path: String
    public let input: PackageFileInput
  }

  public let packageId: LowercaseUUID
  public let visitId: LowercaseUUID
  /// Package revision for this visit, starting at 1.
  public let revision: Int
  /// `packageId` of the previous revision; present exactly when `revision` is greater than 1.
  public let supersedesPackageId: LowercaseUUID?
  public private(set) var entries: [Entry] = []

  /// A first revision (revision 1) of the visit's package.
  public init(visitId: LowercaseUUID, packageId: LowercaseUUID = LowercaseUUID()) {
    self.packageId = packageId
    self.visitId = visitId
    revision = 1
    supersedesPackageId = nil
  }

  /// A draft of any revision with no files yet, for building a revision from the visit's files
  /// rather than from the sealed one (re-seal after a failed upload). Revision 1 names no
  /// superseded package; a later revision names one, which must differ from `packageId`.
  public init(
    visitId: LowercaseUUID, packageId: LowercaseUUID = LowercaseUUID(), revision: Int,
    supersedesPackageId: LowercaseUUID?
  ) throws {
    guard revision >= 1 else {
      throw PackageError.invalidRevision("revision must be at least 1")
    }
    guard (revision == 1) == (supersedesPackageId == nil) else {
      throw PackageError.invalidRevision(
        "supersedesPackageId is required exactly when revision is greater than 1")
    }
    guard supersedesPackageId != packageId else {
      throw PackageError.invalidRevision("supersedesPackageId must differ from packageId")
    }
    self.packageId = packageId
    self.visitId = visitId
    self.revision = revision
    self.supersedesPackageId = supersedesPackageId
  }

  /// The next revision of a sealed package: same visit, a new `packageId`, `revision + 1` and
  /// `supersedesPackageId` set to the sealed package. Every file of the sealed package is carried
  /// over from it (read only, with its fingerprint as the expected one); add or replace files
  /// before assembling. The sealed package itself is never changed.
  ///
  /// Files with a retired role (the phone's spatial report of a manifest 1.0.0 package) are not
  /// carried over: the next revision is a manifest 1.1.0 package, which never holds them.
  public static func nextRevision(
    of sealed: SealedPackage, packageId: LowercaseUUID = LowercaseUUID()
  ) throws -> PackageDraft {
    let previous = sealed.manifest
    guard packageId != previous.packageId else {
      throw PackageError.invalidRevision("a new revision needs a new packageId")
    }
    var draft = try PackageDraft(
      visitId: previous.visitId, packageId: packageId, revision: previous.revision + 1,
      supersedesPackageId: previous.packageId)
    let retired = Set(previous.files.filter { $0.role.isRetired }.map(\.path))
    for file in previous.files where !file.role.isRetired {
      let capture: CaptureRef?
      if let captureId = file.captureId, let areaKey = file.areaKey {
        capture = CaptureRef(captureId: captureId, areaKey: areaKey)
      } else {
        capture = nil
      }
      let fileName = try sealed.fileName(of: file)
      let input = PackageFileInput(
        source: sealed.url(for: file.path), role: file.role, fileName: fileName, capture: capture,
        mime: file.mime, generator: file.generator, generatorVersion: file.generatorVersion,
        derivedFrom: file.derivedFrom.filter { !retired.contains($0) }, photo: file.photo,
        expected: FileDigest(sha256: file.sha256, bytes: file.bytes))
      try draft.add(input)
    }
    return draft
  }

  /// The package path a file of `role` named `fileName` gets in this package.
  public func path(role: FileRole, fileName: String, capture: CaptureRef?) throws -> String {
    try PackagePaths.path(role: role, fileName: fileName, visitId: visitId, capture: capture)
  }

  /// Adds a file and returns its package path. Derived files must be added after the files they
  /// were derived from.
  @discardableResult
  public mutating func add(_ input: PackageFileInput) throws -> String {
    let path = try check(input, replacing: nil)
    entries.append(Entry(path: path, input: input))
    return path
  }

  /// Replaces the file at an existing package path (same role, name and capture) with new
  /// content or metadata. Only drafts can change: a sealed package never does.
  public mutating func replace(_ input: PackageFileInput) throws {
    guard !input.role.isRetired else {
      throw PackageError.retiredRole(input.role)
    }
    let path = try self.path(role: input.role, fileName: input.fileName, capture: input.capture)
    guard let index = entries.firstIndex(where: { $0.path == path }) else {
      throw PackageError.unknownPath(path)
    }
    _ = try check(input, replacing: index)
    entries[index] = Entry(path: path, input: input)
  }

  /// Removes the file at `path` from the draft (a carried-over file a revision no longer has,
  /// for example a plan export written under another name now). Files derived from it must be
  /// removed or replaced first.
  public mutating func remove(path: String) throws {
    guard let index = entries.firstIndex(where: { $0.path == path }) else {
      throw PackageError.unknownPath(path)
    }
    if let dependant = entries.first(where: { $0.input.derivedFrom.contains(path) }) {
      throw PackageError.invalidDerivedFrom(path: dependant.path, source: path)
    }
    entries.remove(at: index)
  }

  /// Checks `input` against the manifest rules and the files before it; returns its path.
  private func check(_ input: PackageFileInput, replacing index: Int?) throws -> String {
    guard !input.role.isRetired else {
      throw PackageError.retiredRole(input.role)
    }
    let path = try self.path(role: input.role, fileName: input.fileName, capture: input.capture)
    let earlier = index.map { Array(entries[..<$0]) } ?? entries
    if index == nil, entries.contains(where: { $0.path == path }) {
      throw PackageError.duplicatePath(path)
    }

    guard PackagePaths.isValidMime(input.mime) else {
      throw PackageError.invalidMetadata(path: path, field: "mime")
    }
    let generatorLength = input.generator.unicodeScalars.count
    guard (1...100).contains(generatorLength) else {
      throw PackageError.invalidMetadata(path: path, field: "generator")
    }
    let versionLength = input.generatorVersion.unicodeScalars.count
    guard (1...50).contains(versionLength) else {
      throw PackageError.invalidMetadata(path: path, field: "generatorVersion")
    }

    if (input.role == .photo) != (input.photo != nil) {
      throw PackageError.photoLabels(path: path)
    }
    if let photo = input.photo {
      guard (1...100).contains(photo.room.unicodeScalars.count) else {
        throw PackageError.invalidMetadata(path: path, field: "photo.room")
      }
    }

    var seen: Set<String> = []
    let earlierPaths = Set(earlier.map(\.path))
    for source in input.derivedFrom {
      guard source != path, earlierPaths.contains(source), seen.insert(source).inserted else {
        throw PackageError.invalidDerivedFrom(path: path, source: source)
      }
    }

    if let capture = input.capture {
      let others = entries.enumerated().compactMap { offset, entry -> String? in
        guard offset != index, let other = entry.input.capture,
          other.captureId == capture.captureId, other.areaKey != capture.areaKey
        else { return nil }
        return other.areaKey
      }
      if let conflicting = others.first {
        throw PackageError.areaKeyConflict(
          captureId: capture.captureId.rawValue, areaKeys: [conflicting, capture.areaKey])
      }
    }
    return path
  }
}
