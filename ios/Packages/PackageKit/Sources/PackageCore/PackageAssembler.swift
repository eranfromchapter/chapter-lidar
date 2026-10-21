import CaptureContract
import Foundation

/// Builds a sealed package from a draft.
///
/// - Every source is copied byte for byte (on APFS `FileManager` clones it); it is never renamed,
///   re-encoded or rewritten, and only ever opened for reading. Each copy is hashed again and
///   must match its source's SHA-256 and size, or assembly fails.
/// - The manifest lists every file with role, capture, SHA-256, size, mime, generator and
///   `derivedFrom`, in the order of the draft, and is written last at
///   `Source Register/{visitId}/manifest.json` with sorted keys, as `schemaVersion` 1.1.0
///   (`ManifestSchemaVersion.current`: a draft never holds a retired role).
/// - The package is built in a hidden staging folder next to `root` and moved to `root` only once
///   complete, so `root` is either a whole sealed package or absent. Then every file and folder is
///   made read-only. `root` must not exist: packages are never written over.
/// - PackageKit never deletes anything. If assembly fails, the staging folder (copies only, never
///   the sources) is left in place and named in the error.
public struct PackageAssembler: Sendable {
  public init() {}

  public func assemble(
    _ draft: PackageDraft, at root: URL, sealedAt: UTCTimestamp = .now()
  ) throws -> SealedPackage {
    try checkPackageRules(draft)
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: root.path) {
      throw PackageError.destinationExists(root.path)
    }
    let parent = root.deletingLastPathComponent()
    let staging = parent.appendingPathComponent(
      ".\(root.lastPathComponent).assembling-\(UUID().uuidString.lowercased())", isDirectory: true)
    try fileSystem("create folder", staging.path) {
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    }

    var files: [PackageManifest.FileEntry] = []
    files.reserveCapacity(draft.entries.count)
    for entry in draft.entries {
      let digest = try copyVerified(entry, into: staging)
      let input = entry.input
      files.append(
        PackageManifest.FileEntry(
          path: entry.path, role: input.role, captureId: input.capture?.captureId,
          areaKey: input.capture?.areaKey, sha256: digest.sha256, bytes: digest.bytes,
          mime: input.mime, generator: input.generator, generatorVersion: input.generatorVersion,
          derivedFrom: input.derivedFrom, photo: input.photo))
    }

    let manifest = PackageManifest(
      packageId: draft.packageId, visitId: draft.visitId, revision: draft.revision,
      supersedesPackageId: draft.supersedesPackageId, sealedAt: sealedAt, files: files)
    let manifestData: Data
    do {
      manifestData = try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(manifest)
    } catch {
      throw PackageError.invalidManifest(String(describing: error))
    }
    let manifestURL = Self.url(
      for: PackagePaths.manifestPath(visitId: draft.visitId), under: staging)
    try fileSystem("write manifest", manifestURL.path) {
      try fileManager.createDirectory(
        at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try manifestData.write(to: manifestURL, options: .withoutOverwriting)
    }

    try fileSystem("move package into place", root.path) {
      try fileManager.moveItem(at: staging, to: root)
    }
    try Self.makeReadOnly(root)
    return SealedPackage(root: root, manifest: manifest, manifestData: manifestData)
  }

  /// Package-level rules: at least one file, exactly one capture record, revision and
  /// supersedesPackageId consistent.
  func checkPackageRules(_ draft: PackageDraft) throws {
    if draft.entries.isEmpty {
      throw PackageError.emptyPackage
    }
    let records = draft.entries.filter { $0.input.role == .captureRecord }.count
    if records != 1 {
      throw PackageError.captureRecordCount(records)
    }
    if draft.revision < 1 {
      throw PackageError.invalidRevision("revision must be at least 1")
    }
    if (draft.revision == 1) != (draft.supersedesPackageId == nil) {
      throw PackageError.invalidRevision(
        "supersedesPackageId is required exactly when revision is greater than 1")
    }
    if draft.supersedesPackageId == draft.packageId {
      throw PackageError.invalidRevision("supersedesPackageId must differ from packageId")
    }
  }

  /// Copies one source into the staging folder and proves the copy has the source's bytes.
  private func copyVerified(_ entry: PackageDraft.Entry, into staging: URL) throws -> FileDigest {
    let fileManager = FileManager.default
    let source = entry.input.source.resolvingSymlinksInPath()
    guard Self.isRegularFile(source) else {
      throw PackageError.notARegularFile(path: entry.input.source.path)
    }
    let sourceDigest = try FileDigest.of(fileAt: source)
    if let expected = entry.input.expected, expected != sourceDigest {
      throw PackageError.sourceChanged(
        path: entry.input.source.path, expected: expected, actual: sourceDigest)
    }
    let destination = Self.url(for: entry.path, under: staging)
    try fileSystem("copy", entry.path) {
      try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try fileManager.copyItem(at: source, to: destination)
    }
    guard Self.isRegularFile(destination) else {
      throw PackageError.notARegularFile(path: entry.path)
    }
    let copyDigest = try FileDigest.of(fileAt: destination)
    if copyDigest != sourceDigest {
      throw PackageError.copyMismatch(path: entry.path, expected: sourceDigest, actual: copyDigest)
    }
    return copyDigest
  }

  static func url(for path: String, under root: URL) -> URL {
    var url = root
    for segment in path.split(separator: "/") {
      url.appendPathComponent(String(segment))
    }
    return url
  }

  static func isRegularFile(_ url: URL) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let type = attributes[.type] as? FileAttributeType
    else { return false }
    return type == .typeRegular
  }

  /// Files 0444, folders 0555, deepest first so folders are locked after their contents.
  static func makeReadOnly(_ root: URL) throws {
    let fileManager = FileManager.default
    for item in PackageFiles.allItems(under: root).reversed() {
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory) else { continue }
      let mode: Int = isDirectory.boolValue ? 0o555 : 0o444
      do {
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: item.path)
      } catch {
        throw PackageError.fileSystem(
          operation: "make read-only", path: item.path, reason: String(describing: error))
      }
    }
  }

  private func fileSystem(_ operation: String, _ path: String, _ body: () throws -> Void) throws {
    do {
      try body()
    } catch let error as PackageError {
      throw error
    } catch {
      throw PackageError.fileSystem(
        operation: operation, path: path, reason: String(describing: error))
    }
  }
}
