import Foundation

/// Where original photo files live. The record store only ever writes whole files it has not
/// written before; it never edits, re-encodes or rewrites a stored photo.
public protocol PhotoFileStore: Sendable {
  /// Writes `data` unchanged at a package-relative path, creating folders as needed.
  /// Throws `PhotoStoreError.fileExists` when `replacingExisting` is false and the file exists.
  func write(_ data: Data, toRelativePath path: String, replacingExisting: Bool) throws
  func read(relativePath path: String) throws -> Data
  func exists(relativePath path: String) -> Bool
  func remove(relativePath path: String) throws
}

/// Files under a directory, for example the visit's working folder on the device.
public struct DiskPhotoFileStore: PhotoFileStore {
  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  private func url(_ path: String) throws -> URL {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !path.isEmpty, !path.hasPrefix("/"),
      !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    else { throw PhotoStoreError.invalidPath(path) }
    return root.appendingPathComponent(path)
  }

  public func write(_ data: Data, toRelativePath path: String, replacingExisting: Bool) throws {
    let target = try url(path)
    if !replacingExisting, FileManager.default.fileExists(atPath: target.path) {
      throw PhotoStoreError.fileExists(path)
    }
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: target, options: .atomic)
  }

  public func read(relativePath path: String) throws -> Data {
    try Data(contentsOf: try url(path))
  }

  public func exists(relativePath path: String) -> Bool {
    guard let target = try? url(path) else { return false }
    return FileManager.default.fileExists(atPath: target.path)
  }

  public func remove(relativePath path: String) throws {
    try FileManager.default.removeItem(at: try url(path))
  }
}

/// Files in memory, for tests and previews.
public final class InMemoryPhotoFileStore: PhotoFileStore, @unchecked Sendable {
  private let lock = NSLock()
  private var files: [String: Data] = [:]

  public init() {}

  public var paths: [String] {
    lock.lock()
    defer { lock.unlock() }
    return files.keys.sorted()
  }

  public func write(_ data: Data, toRelativePath path: String, replacingExisting: Bool) throws {
    lock.lock()
    defer { lock.unlock() }
    if !replacingExisting, files[path] != nil { throw PhotoStoreError.fileExists(path) }
    files[path] = data
  }

  public func read(relativePath path: String) throws -> Data {
    lock.lock()
    defer { lock.unlock() }
    guard let data = files[path] else { throw PhotoStoreError.fileMissing(path) }
    return data
  }

  public func exists(relativePath path: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return files[path] != nil
  }

  public func remove(relativePath path: String) throws {
    lock.lock()
    defer { lock.unlock() }
    guard files.removeValue(forKey: path) != nil else { throw PhotoStoreError.fileMissing(path) }
  }
}
