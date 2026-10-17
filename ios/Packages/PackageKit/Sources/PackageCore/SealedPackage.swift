import CaptureContract
import Foundation

/// A sealed package on disk: the package folder with `Source Register/{visitId}/manifest.json`.
/// Read-only: nothing in PackageKit writes into or deletes from a sealed package. A change is a
/// new revision (`PackageDraft.nextRevision(of:)`) in a new folder.
public struct SealedPackage: Sendable {
  /// The package root folder.
  public let root: URL
  public let manifest: PackageManifest
  /// The manifest exactly as written on disk. Sealing at the station sends these bytes; they are
  /// never re-encoded.
  public let manifestData: Data

  public var packageId: LowercaseUUID { manifest.packageId }
  public var visitId: LowercaseUUID { manifest.visitId }

  /// Package path of the manifest.
  public var manifestPath: String { PackagePaths.manifestPath(visitId: manifest.visitId) }

  init(root: URL, manifest: PackageManifest, manifestData: Data) {
    self.root = root
    self.manifest = manifest
    self.manifestData = manifestData
  }

  /// Opens the sealed package at `root`. It must hold exactly one
  /// `Source Register/<visitId>/manifest.json` whose `visitId` matches its folder.
  public static func open(at root: URL) throws -> SealedPackage {
    let fileManager = FileManager.default
    let register = root.appendingPathComponent(
      PackageFolder.sourceRegister.name, isDirectory: true)
    let visitFolders: [String]
    do {
      visitFolders = try fileManager.contentsOfDirectory(atPath: register.path)
    } catch {
      throw PackageError.notSealed("no \(PackageFolder.sourceRegister.name) folder in \(root.path)")
    }
    let manifests = visitFolders.sorted().filter { name in
      var isDirectory: ObjCBool = false
      let candidate = register.appendingPathComponent(name, isDirectory: true)
        .appendingPathComponent(PackageLayout.manifestFileName)
      return fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
        && !isDirectory.boolValue
    }
    guard manifests.count == 1, let visitFolder = manifests.first else {
      throw PackageError.notSealed("expected exactly one manifest, found \(manifests.count)")
    }
    let url = register.appendingPathComponent(visitFolder, isDirectory: true)
      .appendingPathComponent(PackageLayout.manifestFileName)
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw PackageError.unreadableFile(path: url.path, reason: String(describing: error))
    }
    let manifest: PackageManifest
    do {
      manifest = try CaptureContractJSON.makeDecoder().decode(PackageManifest.self, from: data)
    } catch {
      throw PackageError.invalidManifest(String(describing: error))
    }
    guard manifest.visitId.rawValue == visitFolder else {
      throw PackageError.invalidManifest("visitId does not match its Source Register folder")
    }
    return SealedPackage(root: root, manifest: manifest, manifestData: data)
  }

  /// File URL of a package path.
  public func url(for path: String) -> URL {
    var url = root
    for segment in path.split(separator: "/") {
      url.appendPathComponent(String(segment))
    }
    return url
  }

  /// The file's name in its folder (the part of its path after the role's folder).
  public func fileName(of file: PackageManifest.FileEntry) throws -> String {
    let capture: CaptureRef?
    if let captureId = file.captureId, let areaKey = file.areaKey {
      capture = CaptureRef(captureId: captureId, areaKey: areaKey)
    } else {
      capture = nil
    }
    let folder = try PackagePaths.folder(
      role: file.role, visitId: manifest.visitId, capture: capture)
    guard file.path.hasPrefix(folder), file.path.count > folder.count else {
      throw PackageError.invalidManifest("\(file.path) is not in the folder of role \(file.role)")
    }
    return String(file.path.dropFirst(folder.count))
  }

  /// Re-reads every file and returns the problems found: files whose bytes no longer match the
  /// manifest, listed files that are missing, and files on disk the manifest does not list (other
  /// than the manifest itself). Empty when the package is intact.
  public func verify() -> [String] {
    var problems: [String] = []
    for file in manifest.files {
      do {
        let digest = try FileDigest.of(fileAt: url(for: file.path))
        if digest.sha256 != file.sha256 || digest.bytes != file.bytes {
          problems.append("\(file.path): bytes differ from the manifest")
        }
      } catch {
        problems.append("\(file.path): missing or unreadable")
      }
    }
    let listed = Set(manifest.files.map(\.path)).union([manifestPath])
    for path in PackageFiles.relativeFilePaths(under: root) where !listed.contains(path) {
      problems.append("\(path): not listed in the manifest")
    }
    return problems
  }

  /// True when every file and folder of the package is read-only (no write permission bits).
  public func isReadOnly() -> Bool {
    PackageFiles.allItems(under: root).allSatisfy { url in
      guard
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
        let permissions = attributes[.posixPermissions] as? NSNumber
      else { return false }
      return permissions.intValue & 0o222 == 0
    }
  }
}

/// File-system walks of a package folder.
enum PackageFiles {
  /// Every regular file under `root`, as package paths (forward slashes), sorted.
  static func relativeFilePaths(under root: URL) -> [String] {
    var paths: [String] = []
    walk(root, prefix: "") { path, isDirectory in
      if !isDirectory { paths.append(path) }
    }
    return paths.sorted()
  }

  /// `root` and every file and folder under it.
  static func allItems(under root: URL) -> [URL] {
    var items: [URL] = [root]
    walk(root, prefix: "") { path, _ in
      var url = root
      for segment in path.split(separator: "/") { url.appendPathComponent(String(segment)) }
      items.append(url)
    }
    return items
  }

  private static func walk(
    _ directory: URL, prefix: String, _ visit: (String, Bool) -> Void
  ) {
    let fileManager = FileManager.default
    guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
    for name in names.sorted() {
      let url = directory.appendingPathComponent(name)
      let path = prefix.isEmpty ? name : prefix + "/" + name
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
      visit(path, isDirectory.boolValue)
      if isDirectory.boolValue {
        walk(url, prefix: path, visit)
      }
    }
  }
}
