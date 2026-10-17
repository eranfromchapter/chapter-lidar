import Foundation

/// Uploads bytes to Azure Blob Storage through an upload target (a write-only SAS URL). The
/// transport only reads the package file; it never writes or deletes it. Every method returns
/// once the blob service confirmed the request (201) and throws otherwise.
///
/// Implementations: `HTTPBlobTransport` (foreground URLSession, portable) and
/// `BackgroundBlobTransport` (background URLSession, Apple platforms) in PackageTransport.
public protocol BlobTransport: Sendable {
  /// Put Blob: the whole file in one request, with the target's headers.
  func putBlob(_ upload: BlobUpload) async throws
  /// Put Block: `length` bytes of the file from `offset`, staged under `blockId` (base64).
  func putBlock(_ upload: BlobUpload, blockId: String, offset: Int64, length: Int) async throws
  /// Put Block List: commits the staged blocks in order.
  func putBlockList(_ upload: BlobUpload, blockIds: [String]) async throws
}

/// One file upload through one target.
public struct BlobUpload: Sendable, Hashable {
  public var target: UploadTarget
  /// The package file. Read only.
  public var file: URL
  public var bytes: Int64
  /// The manifest mime, sent as the blob's content type.
  public var mime: String

  public init(target: UploadTarget, file: URL, bytes: Int64, mime: String) {
    self.target = target
    self.file = file
    self.bytes = bytes
    self.mime = mime
  }
}

/// A failed blob request. Never carries the SAS URL.
public enum BlobTransportError: Error, Hashable, Sendable, CustomStringConvertible {
  /// The blob service answered with a status other than 201. `code` is x-ms-error-code.
  case http(status: Int, code: String?)
  /// No answer (offline, timeout, connection lost). Retry later.
  case network(String)
  /// The local file could not be read.
  case unreadable(String)

  public var description: String {
    switch self {
    case .http(let status, let code): return "blob service answered \(status) \(code ?? "")"
    case .network(let reason): return "blob upload did not complete: \(reason)"
    case .unreadable(let reason): return "cannot read the file to upload: \(reason)"
    }
  }
}

/// Block layout of resumable uploads.
public enum BlobBlocks {
  /// Files up to this size go up with one Put Blob; larger files in blocks of this size.
  public static let blockSize = 8 * 1024 * 1024

  /// Deterministic base64 block id of block `index` (all ids of a blob have the same length, as
  /// Azure requires). The same file and index always give the same id, so a block staged before
  /// an app kill is recognised after it.
  public static func blockId(_ index: Int) -> String {
    let digits = String(index)
    let padded = String(repeating: "0", count: max(0, 8 - digits.count)) + digits
    return Data("blk-\(padded)".utf8).base64EncodedString()
  }

  /// Number of blocks of a file of `bytes` bytes.
  public static func blockCount(bytes: Int64, blockSize: Int = blockSize) -> Int {
    guard bytes > 0 else { return 0 }
    return Int((bytes + Int64(blockSize) - 1) / Int64(blockSize))
  }
}
