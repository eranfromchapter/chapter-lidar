import Foundation

/// SHA-256 (lowercase hex) and size of a file's bytes, as listed in the manifest.
public struct FileDigest: Hashable, Sendable, Codable {
  public var sha256: String
  public var bytes: Int64

  public init(sha256: String, bytes: Int64) {
    self.sha256 = sha256
    self.bytes = bytes
  }

  /// Chunk size used to stream files through the hasher.
  public static let chunkSize = 1 << 20

  /// Reads the file at `url` in chunks (never whole into memory) and hashes it. The file is
  /// opened for reading only.
  public static func of(fileAt url: URL) throws -> FileDigest {
    let handle: FileHandle
    do {
      handle = try FileHandle(forReadingFrom: url)
    } catch {
      throw PackageError.unreadableFile(path: url.path, reason: String(describing: error))
    }
    defer { try? handle.close() }
    var hasher = SHA256()
    var total: Int64 = 0
    while true {
      let chunk: Data?
      do {
        chunk = try handle.read(upToCount: chunkSize)
      } catch {
        throw PackageError.unreadableFile(path: url.path, reason: String(describing: error))
      }
      guard let chunk, !chunk.isEmpty else { break }
      hasher.update(chunk)
      total += Int64(chunk.count)
    }
    return FileDigest(sha256: hasher.finalizeHex(), bytes: total)
  }

  public static func of(data: Data) -> FileDigest {
    FileDigest(sha256: SHA256.hexDigest(of: data), bytes: Int64(data.count))
  }
}
