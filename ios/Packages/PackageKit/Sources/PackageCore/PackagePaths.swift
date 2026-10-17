import CaptureContract
import Foundation

/// The capture a file belongs to: one floor or area scan of the visit.
public struct CaptureRef: Hashable, Sendable, Codable {
  public var captureId: LowercaseUUID
  /// Floor or area key from the capture record, for example floor-1.
  public var areaKey: String

  public init(captureId: LowercaseUUID, areaKey: String) {
    self.captureId = captureId
    self.areaKey = areaKey
  }
}

/// Package paths from contract/schema/layout.json. Every path is relative to the package root,
/// uses forward slashes and starts with the folder of the file's role.
public enum PackagePaths {
  /// Longest path the manifest schema allows (relativePath maxLength).
  public static let maxPathLength = 1024
  /// Longest areaKey the manifest schema allows.
  public static let maxAreaKeyLength = 64

  /// `Source Register/{visitId}/manifest.json`. The manifest does not list itself.
  public static func manifestPath(visitId: LowercaseUUID) -> String {
    PackageLayout.manifestPathTemplate.replacingOccurrences(
      of: "{visitId}", with: visitId.rawValue)
  }

  /// Folder of a file of `role`, with a trailing slash: `Original Exports/{areaKey}/{captureId}/`
  /// for capture roles, `Source Register/{visitId}/` and `Field Measurements/{visitId}/` for the
  /// visit-wide roles.
  public static func folder(
    role: FileRole, visitId: LowercaseUUID, capture: CaptureRef?
  ) throws -> String {
    let folder = role.folder
    switch folder.scope {
    case .visit:
      return folder.pathTemplate.replacingOccurrences(of: "{visitId}", with: visitId.rawValue)
    case .capture:
      guard let capture else {
        throw PackageError.captureMismatch(path: folder.name, role: role.rawValue)
      }
      try validateAreaKey(capture.areaKey)
      return folder.pathTemplate
        .replacingOccurrences(of: "{areaKey}", with: capture.areaKey)
        .replacingOccurrences(of: "{captureId}", with: capture.captureId.rawValue)
    }
  }

  /// The package path of a file: its role's folder followed by `fileName` (which may contain
  /// subfolders, for mesh companions). Visit-wide roles take no capture; every other role needs
  /// one. Roles with a fixed name in layout.json (capture record, capture model, field controls)
  /// must use it.
  public static func path(
    role: FileRole, fileName: String, visitId: LowercaseUUID, capture: CaptureRef?
  ) throws -> String {
    if role.isVisitWide != (capture == nil) {
      throw PackageError.captureMismatch(path: fileName, role: role.rawValue)
    }
    if let fixed = fixedFileName(for: role), fixed != fileName {
      throw PackageError.fixedFileName(role: role.rawValue, expected: fixed, got: fileName)
    }
    try validateRelativePath(fileName)
    let path = try folder(role: role, visitId: visitId, capture: capture) + fileName
    try validateRelativePath(path)
    if path == manifestPath(visitId: visitId) {
      throw PackageError.reservedPath(path)
    }
    return path
  }

  /// The fixed file name of `role` in layout.json, if it has one.
  public static func fixedFileName(for role: FileRole) -> String? {
    switch role {
    case .captureRecord: return PackageLayout.captureRecordFileName
    case .captureModel: return PackageLayout.captureModelFileName
    case .fieldControls: return PackageLayout.fieldControlsFileName
    default: return nil
    }
  }

  /// The manifest's relativePath rule: not empty, at most 1024 characters, forward slashes, no
  /// leading, trailing or doubled slash, no `.` or `..` segment, no backslash or control character.
  public static func validateRelativePath(_ path: String) throws {
    let scalars = path.unicodeScalars
    if scalars.isEmpty {
      throw PackageError.invalidPath(path, reason: "empty")
    }
    if scalars.count > maxPathLength {
      throw PackageError.invalidPath(path, reason: "longer than \(maxPathLength) characters")
    }
    if path.hasPrefix("/") || path.hasSuffix("/") || path.contains("//") {
      throw PackageError.invalidPath(path, reason: "leading, trailing or doubled slash")
    }
    for scalar in scalars where scalar.value < 0x20 || scalar == "\\" {
      throw PackageError.invalidPath(path, reason: "backslash or control character")
    }
    for segment in path.split(separator: "/", omittingEmptySubsequences: false)
    where segment == "." || segment == ".." {
      throw PackageError.invalidPath(path, reason: "'.' or '..' segment")
    }
  }

  /// The manifest's areaKey rule: lowercase letters and digits in groups joined by single hyphens,
  /// at most 64 characters.
  public static func validateAreaKey(_ key: String) throws {
    guard !key.isEmpty, key.unicodeScalars.count <= maxAreaKeyLength else {
      throw PackageError.invalidAreaKey(key)
    }
    let groups = key.split(separator: "-", omittingEmptySubsequences: false)
    for group in groups {
      guard !group.isEmpty,
        group.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) })
      else {
        throw PackageError.invalidAreaKey(key)
      }
    }
  }

  /// The manifest's mime rule: `type/subtype`, lowercase, at most 127 characters.
  public static func isValidMime(_ mime: String) -> Bool {
    guard mime.unicodeScalars.count <= 127 else { return false }
    let parts = mime.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return false }
    let first: Set<Unicode.Scalar> = Set("abcdefghijklmnopqrstuvwxyz0123456789".unicodeScalars)
    let rest = first.union("!#$&^_.+-".unicodeScalars)
    for part in parts {
      guard let head = part.unicodeScalars.first, first.contains(head),
        part.unicodeScalars.allSatisfy({ rest.contains($0) })
      else { return false }
    }
    return true
  }
}
