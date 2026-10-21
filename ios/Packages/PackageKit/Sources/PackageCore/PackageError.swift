import CaptureContract
import Foundation

/// Why a package could not be laid out, assembled, sealed or opened. Nothing here is ever fixed up
/// silently: every rule break is an error the caller sees.
public enum PackageError: Error, Equatable, Sendable, CustomStringConvertible {
  /// A file name or path breaks the manifest's relativePath rule.
  case invalidPath(String, reason: String)
  /// An areaKey breaks the manifest's areaKey rule.
  case invalidAreaKey(String)
  /// A visit-wide role was given a capture, or a capture role was given none.
  case captureMismatch(path: String, role: String)
  /// The role has a fixed file name in layout.json and another name was given.
  case fixedFileName(role: String, expected: String, got: String)
  /// The path is the manifest's own path; the manifest is written at sealing.
  case reservedPath(String)
  /// Two files would have the same package path.
  case duplicatePath(String)
  /// No file with this path is in the draft.
  case unknownPath(String)
  /// A `derivedFrom` entry is not a file added earlier, repeats, or is the file itself.
  case invalidDerivedFrom(path: String, source: String)
  /// A capture id was used with two different area keys.
  case areaKeyConflict(captureId: String, areaKeys: [String])
  /// Photo labels are present on a role other than photo, or missing on a photo.
  case photoLabels(path: String)
  /// mime, generator or generatorVersion break the manifest rules.
  case invalidMetadata(path: String, field: String)
  /// The package does not have exactly one capture record.
  case captureRecordCount(Int)
  /// The draft has no files.
  case emptyPackage
  /// Revision 1 with supersedesPackageId, or a later revision without it.
  case invalidRevision(String)
  /// A source is missing, a directory or otherwise not a regular file.
  case notARegularFile(path: String)
  /// A file could not be read.
  case unreadableFile(path: String, reason: String)
  /// A source no longer has the fingerprint it was expected to have.
  case sourceChanged(path: String, expected: FileDigest, actual: FileDigest)
  /// The copy in the package does not have the bytes of its source.
  case copyMismatch(path: String, expected: FileDigest, actual: FileDigest)
  /// The package root already exists; packages are never written over.
  case destinationExists(String)
  /// A file-system operation failed.
  case fileSystem(operation: String, path: String, reason: String)
  /// The folder is not a sealed package (no manifest, more than one, or unreadable).
  case notSealed(String)
  /// The manifest could not be decoded.
  case invalidManifest(String)
  /// The role is retired (`FileRole.isRetired`, manifest 1.1.0): a package sealed by this app
  /// never holds it. The spatial report is made by the station, not packaged.
  case retiredRole(FileRole)

  public var description: String {
    switch self {
    case .invalidPath(let path, let reason): return "invalid package path \(path): \(reason)"
    case .invalidAreaKey(let key): return "invalid areaKey \(key)"
    case .captureMismatch(let path, let role):
      return "\(path): role \(role) needs a capture exactly when it is not visit-wide"
    case .fixedFileName(let role, let expected, let got):
      return "role \(role) must be named \(expected), got \(got)"
    case .reservedPath(let path): return "\(path) is the manifest path"
    case .duplicatePath(let path): return "duplicate package path \(path)"
    case .unknownPath(let path): return "no file \(path) in the package"
    case .invalidDerivedFrom(let path, let source):
      return "\(path): derivedFrom \(source) is not an earlier, distinct package file"
    case .areaKeyConflict(let captureId, let areaKeys):
      return "capture \(captureId) has more than one areaKey: \(areaKeys.joined(separator: ", "))"
    case .photoLabels(let path): return "\(path): photo labels are required exactly for role photo"
    case .invalidMetadata(let path, let field): return "\(path): invalid \(field)"
    case .captureRecordCount(let count):
      return "a package needs exactly one capture_record file, found \(count)"
    case .emptyPackage: return "a package needs at least one file"
    case .invalidRevision(let reason): return "invalid revision: \(reason)"
    case .notARegularFile(let path): return "\(path) is not a regular file"
    case .unreadableFile(let path, let reason): return "cannot read \(path): \(reason)"
    case .sourceChanged(let path, let expected, let actual):
      return
        "\(path) changed: expected \(expected.sha256) (\(expected.bytes) bytes), found \(actual.sha256) (\(actual.bytes) bytes)"
    case .copyMismatch(let path, let expected, let actual):
      return
        "copy of \(path) differs from its source: expected \(expected.sha256) (\(expected.bytes) bytes), found \(actual.sha256) (\(actual.bytes) bytes)"
    case .destinationExists(let path): return "\(path) already exists"
    case .fileSystem(let operation, let path, let reason):
      return "\(operation) failed for \(path): \(reason)"
    case .notSealed(let reason): return "not a sealed package: \(reason)"
    case .invalidManifest(let reason): return "invalid manifest: \(reason)"
    case .retiredRole(let role):
      return "role \(role.rawValue) is retired; a new package never holds it"
    }
  }
}
