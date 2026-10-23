import CaptureContract
import CaptureCore
import FieldRules
import Foundation
import PackageCore
import PhotoStore

/// `<packageId>.photos-erased.json` next to a sealed package (as its `.upload-state.json` is):
/// the site photos of the package were erased on this phone ("Delete all photos"). App-private,
/// not in the package and not in the contract.
///
/// The sealed package keeps its manifest (it still lists the photos, with their fingerprints);
/// only the photo files are gone. A package whose upload the station had not confirmed is never
/// uploaded after this (`UploadCoordinator`), a revision built on it does not carry its photos
/// over (`VisitPackageBuilder.revisionPlan`), and its screens say "Photos erased on this phone".
public struct PhotosErasedRecord: Codable, Equatable, Sendable {
  public static let currentFormatVersion = 1

  public var formatVersion: Int
  public var packageId: LowercaseUUID
  public var erasedAt: UTCTimestamp
  /// The manifest's photo paths that were erased.
  public var paths: [String]

  public init(packageId: LowercaseUUID, erasedAt: UTCTimestamp, paths: [String]) {
    formatVersion = Self.currentFormatVersion
    self.packageId = packageId
    self.erasedAt = erasedAt
    self.paths = paths
  }

  /// `<package folder name>.photos-erased.json` next to the package folder.
  public static func url(forPackageAt root: URL) -> URL {
    let root = root.standardizedFileURL
    return root.deletingLastPathComponent()
      .appendingPathComponent("\(root.lastPathComponent).photos-erased.json")
  }

  /// The record of the package at `root`, nil when its photos were not erased. A record that
  /// cannot be read still means erased (`isErased`).
  public static func load(forPackageAt root: URL) -> PhotosErasedRecord? {
    guard let data = try? Data(contentsOf: url(forPackageAt: root)) else { return nil }
    return try? CaptureContractJSON.makeDecoder().decode(PhotosErasedRecord.self, from: data)
  }

  /// True when the photos of the package at `root` were erased on this phone.
  public static func isErased(packageAt root: URL) -> Bool {
    FileManager.default.fileExists(atPath: url(forPackageAt: root).path)
  }

  func write(forPackageAt root: URL) throws {
    let data = try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(self)
    #if os(iOS)
      try data.write(
        to: Self.url(forPackageAt: root),
        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #else
      try data.write(to: Self.url(forPackageAt: root), options: .atomic)
    #endif
  }
}

/// The words of a package whose photos were erased.
public enum PhotosErasedText {
  /// The note on Package status and Verdict received.
  public static let note = "Photos erased on this phone"
  /// Upload stopped: the package was not confirmed by the station when its photos were erased.
  public static let stopped = "Photos erased on this phone. This revision is not uploaded."
}

/// What "Delete all photos" removed.
public struct PhotoErasureResult: Equatable, Sendable {
  /// Distinct photos removed: different SHA-256s among the photo files deleted and the photo
  /// records cleared. A photo kept in the visit and in two sealed packages counts once.
  public var photos = 0
  /// Photo files deleted (every copy: originals, package copies, previews, temporary files).
  public var files = 0
  public var bytes: Int64 = 0
  /// Records cleared from the visits' `photo-records.json`.
  public var records = 0
  /// Sealed packages whose photos were erased by this run (`PhotosErasedRecord` written).
  public var sealedPackages = 0
  /// Upload scratch files and app snapshots deleted (copies of package blocks, screen images).
  public var scratchFiles = 0
  /// Photo blobs the in-process stub station held (field-test and UI-test modes).
  public var stationBlobs = 0
  /// Paths that could not be deleted or rewritten, with why.
  public var failures: [String] = []

  public init() {}

  /// "Deleted 3 photos", "No photos to delete" (and the files that could not be deleted).
  public var message: String {
    DeletePhotosText.result(deleted: photos, failures: failures.count)
  }
}

/// Erases every copy of site-photo bytes the app holds on the phone ("Delete all photos", in the
/// field-test and UI-test modes), and keeps everything else.
///
/// In each visit workspace under each of `visitsRoots`:
/// - `photos/`: every file but the index is deleted (the originals under `Site Photos/`, and any
///   preview or thumbnail written next to them); `photo-records.json` becomes an empty list.
/// - `packages/<packageId>/` (sealed, read-only): the manifest's photo files and the package's
///   `Site Photos` folder are deleted (the folders are made writable for that and read-only
///   again), and `<packageId>.photos-erased.json` records it (`PhotosErasedRecord`). The
///   manifest, every other file and the upload and station status files stay as they are.
/// - Anything else (drafts, failed assembly folders `packages/.<id>.assembling-*`, files of
///   older app builds): every `Site Photos` folder, and every JPEG or HEIC file (by its first
///   bytes or its extension) outside the scans.
/// - Never touched: `originals/` (the scans) and every `Original Exports` folder (scans, capture
///   models, plans and meshes), `controls/`, `visit.json`, `room-names.json`, the capture
///   records, the manifests, the upload and station status files.
///
/// Outside the visits: every file in `scratchFolders` (upload scratch: copies of blocks of
/// package files; the app switcher's snapshots), and every JPEG or HEIC file in `sweptFolders`
/// (the temporary folder, the caches).
///
/// Erasing twice deletes nothing the second time. Failures do not stop the run; they are listed
/// in the result.
public struct PhotoEraser: Sendable {
  public var visitsRoots: [URL]
  public var scratchFolders: [URL]
  public var sweptFolders: [URL]
  public var now: @Sendable () -> Date

  /// File extensions of photographs (the camera's HEIC and JPEG).
  public static let photoExtensions: Set<String> = ["heic", "heif", "hif", "jpg", "jpeg", "jpe"]
  static let sitePhotosFolder = PackageFolder.sitePhotos.name
  static let originalExportsFolder = PackageFolder.originalExports.name

  public init(
    visitsRoots: [URL], scratchFolders: [URL] = [], sweptFolders: [URL] = [],
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.visitsRoots = visitsRoots
    self.scratchFolders = scratchFolders
    self.sweptFolders = sweptFolders
    self.now = now
  }

  /// Erases every photo; see the type's description.
  public func eraseAll() -> PhotoErasureResult {
    var run = Run(now: now)
    for root in unique(visitsRoots) {
      for child in run.children(of: root) {
        if run.isDirectory(child) {
          run.eraseWorkspace(VisitWorkspace(root: child))
        } else {
          run.sweepFile(child)
        }
      }
    }
    for folder in unique(scratchFolders) {
      for child in run.children(of: folder) {
        run.scratchFiles += run.removeTree(child, countsPhotos: false)
      }
    }
    for folder in unique(sweptFolders) {
      run.sweep(folder, insideOriginalExports: false)
    }
    return run.result
  }

  private func unique(_ urls: [URL]) -> [URL] {
    var seen: Set<String> = []
    return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
  }

  /// True when the file is a photograph: JPEG or HEIC by its first bytes, or by its extension.
  public static func isPhotoFile(_ url: URL) -> Bool {
    if photoExtensions.contains(url.pathExtension.lowercased()) { return true }
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    guard let head = try? handle.read(upToCount: 12) else { return false }
    return PhotoFormat.detect(head) != nil
  }

  // MARK: Run

  private struct Run {
    let now: @Sendable () -> Date
    var result = PhotoErasureResult()
    var shas: Set<String> = []
    var scratchFiles: Int {
      get { result.scratchFiles }
      set { result.scratchFiles = newValue }
    }
    let fileManager = FileManager.default

    init(now: @escaping @Sendable () -> Date) {
      self.now = now
    }

    // MARK: Workspace

    mutating func eraseWorkspace(_ workspace: VisitWorkspace) {
      for child in children(of: workspace.root) {
        switch child.lastPathComponent {
        case "originals":
          // The scans: never touched.
          continue
        case "photos" where isDirectory(child):
          erasePhotoStore(child)
        case "packages" where isDirectory(child):
          erasePackages(child)
        default:
          if isDirectory(child) {
            sweep(child, insideOriginalExports: false)
          } else {
            sweepFile(child)
          }
        }
      }
    }

    /// `photos/`: everything but the index goes; the index becomes an empty list.
    mutating func erasePhotoStore(_ folder: URL) {
      let index = folder.appendingPathComponent(PhotoRecordStore.indexPath)
      if fileManager.fileExists(atPath: index.path) {
        if let data = try? Data(contentsOf: index),
          let records = try? CaptureContractJSON.makeDecoder().decode([PhotoRecord].self, from: data)
        {
          result.records += records.count
          for record in records { shas.insert(record.sha256) }
          result.photos = shas.count
        }
      }
      for child in children(of: folder) where child.lastPathComponent != PhotoRecordStore.indexPath {
        _ = removeTree(child, countsPhotos: true)
      }
      writeEmptyIndex(index)
    }

    /// Writes `[]` as the photo index, unless it already is an empty list.
    mutating func writeEmptyIndex(_ index: URL) {
      if let data = try? Data(contentsOf: index),
        let records = try? CaptureContractJSON.makeDecoder().decode([PhotoRecord].self, from: data),
        records.isEmpty
      {
        return
      }
      do {
        let data = try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode([PhotoRecord]())
        try data.write(to: index, options: .atomic)
      } catch {
        result.failures.append("\(index.path): \(error.localizedDescription)")
      }
    }

    // MARK: Packages

    /// `packages/`: each sealed package, and anything else there (failed assembly folders).
    mutating func erasePackages(_ folder: URL) {
      for child in children(of: folder) {
        guard isDirectory(child) else {
          sweepFile(child)
          continue
        }
        if !child.lastPathComponent.hasPrefix("."), let package = try? SealedPackage.open(at: child)
        {
          eraseSealed(package, at: child)
        } else {
          sweep(child, insideOriginalExports: false)
        }
      }
    }

    /// One sealed package: its photo files and `Site Photos` folder, then the record.
    mutating func eraseSealed(_ package: SealedPackage, at root: URL) {
      let photoPaths = package.manifest.files.filter { $0.role == .photo }.map(\.path)
      let listed = Set(package.manifest.files.map(\.path)).union([package.manifestPath])
      for path in photoPaths {
        let url = package.url(for: path)
        guard fileManager.fileExists(atPath: url.path) else { continue }
        _ = removeTree(url, countsPhotos: true)
      }
      let sitePhotos = root.appendingPathComponent(PhotoEraser.sitePhotosFolder, isDirectory: true)
      if fileManager.fileExists(atPath: sitePhotos.path) {
        _ = removeTree(sitePhotos, countsPhotos: true)
      }
      // A photo the manifest does not list (it should hold none) goes too; listed files stay.
      sweep(root, insideOriginalExports: false, keeping: listed, packageRoot: root)

      guard !photoPaths.isEmpty, !PhotosErasedRecord.isErased(packageAt: root) else { return }
      do {
        try PhotosErasedRecord(
          packageId: package.packageId, erasedAt: UTCTimestamp(now()), paths: photoPaths
        ).write(forPackageAt: root)
        result.sealedPackages += 1
      } catch {
        result.failures.append(
          "\(PhotosErasedRecord.url(forPackageAt: root).path): \(error.localizedDescription)")
      }
    }

    // MARK: Sweeps

    /// Deletes every `Site Photos` folder under `folder` and every photo file outside the scans
    /// (`Original Exports` folders). `keeping`: package paths (under `packageRoot`) never
    /// deleted.
    mutating func sweep(
      _ folder: URL, insideOriginalExports: Bool, keeping: Set<String> = [],
      packageRoot: URL? = nil
    ) {
      for child in children(of: folder) {
        if isDirectory(child) && !isSymbolicLink(child) {
          let name = child.lastPathComponent
          if name == PhotoEraser.sitePhotosFolder {
            _ = removeTree(child, countsPhotos: true)
          } else {
            sweep(
              child, insideOriginalExports: insideOriginalExports
                || name == PhotoEraser.originalExportsFolder,
              keeping: keeping, packageRoot: packageRoot)
          }
        } else if !insideOriginalExports {
          if let packageRoot, keeping.contains(relativePath(of: child, under: packageRoot)) {
            continue
          }
          sweepFile(child)
        }
      }
    }

    /// Deletes one file when it is a photo.
    mutating func sweepFile(_ url: URL) {
      guard !isSymbolicLink(url), PhotoEraser.isPhotoFile(url) else { return }
      _ = removeTree(url, countsPhotos: true)
    }

    // MARK: Removal

    /// Removes `url` (a file or a whole folder), making read-only folders writable for it and
    /// putting their permissions back after. Counts the files removed (and, when
    /// `countsPhotos`, the photos among them). Returns the number of files removed.
    @discardableResult
    mutating func removeTree(_ url: URL, countsPhotos: Bool) -> Int {
      var files: [URL] = []
      if isDirectory(url) && !isSymbolicLink(url) {
        collectFiles(under: url, into: &files)
      } else {
        files = [url]
      }
      var digests: [(sha: String, bytes: Int64, photo: Bool)] = []
      if countsPhotos {
        for file in files where !isSymbolicLink(file) {
          guard let digest = try? FileDigest.of(fileAt: file) else { continue }
          digests.append((digest.sha256, digest.bytes, PhotoEraser.isPhotoFile(file)))
        }
      }
      let parent = url.deletingLastPathComponent()
      let restore = makeWritable(parent)
      if isDirectory(url) && !isSymbolicLink(url) { makeTreeWritable(url) }
      defer { restore() }
      do {
        try fileManager.removeItem(at: url)
      } catch {
        result.failures.append("\(url.path): \(error.localizedDescription)")
        return 0
      }
      if countsPhotos { result.files += files.count }
      for digest in digests {
        result.bytes += digest.bytes
        if digest.photo { shas.insert(digest.sha) }
      }
      result.photos = shas.count
      return files.count
    }

    private func collectFiles(under folder: URL, into files: inout [URL]) {
      for child in children(of: folder) {
        if isDirectory(child) && !isSymbolicLink(child) {
          collectFiles(under: child, into: &files)
        } else {
          files.append(child)
        }
      }
    }

    /// Adds the owner's write permission to `folder` when it lacks it; returns what puts the
    /// old permissions back.
    private func makeWritable(_ folder: URL) -> () -> Void {
      guard let mode = permissions(folder), mode & 0o200 == 0 else { return {} }
      try? fileManager.setAttributes(
        [.posixPermissions: NSNumber(value: mode | 0o700)], ofItemAtPath: folder.path)
      return {
        try? FileManager.default.setAttributes(
          [.posixPermissions: NSNumber(value: mode)], ofItemAtPath: folder.path)
      }
    }

    /// Makes every folder under (and including) `folder` writable, so it can be removed.
    private func makeTreeWritable(_ folder: URL) {
      if let mode = permissions(folder), mode & 0o700 != 0o700 {
        try? fileManager.setAttributes(
          [.posixPermissions: NSNumber(value: mode | 0o700)], ofItemAtPath: folder.path)
      }
      for child in children(of: folder) where isDirectory(child) && !isSymbolicLink(child) {
        makeTreeWritable(child)
      }
    }

    private func permissions(_ url: URL) -> Int? {
      (try? fileManager.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
    }

    // MARK: Files

    func children(of folder: URL) -> [URL] {
      ((try? fileManager.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? [])
        .sorted { $0.path < $1.path }
    }

    func isDirectory(_ url: URL) -> Bool {
      var isDirectory: ObjCBool = false
      return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        && isDirectory.boolValue
    }

    func isSymbolicLink(_ url: URL) -> Bool {
      (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    func relativePath(of url: URL, under root: URL) -> String {
      let base = root.resolvingSymlinksInPath().path
      let path = url.resolvingSymlinksInPath().path
      guard path.hasPrefix(base + "/") else { return path }
      return String(path.dropFirst(base.count + 1))
    }
  }
}
