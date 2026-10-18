// UI-test blob transport. DEBUG ONLY (see UITestStation.swift): compiled only with the DEBUG
// condition and selected only in `LaunchMode.uiTestReplay` and `.fieldTest`.
#if DEBUG
  import Foundation
  import PackageCore

  enum UITestDigest {
    static func sha256Hex(_ data: Data) -> String { SHA256.hexDigest(of: data) }
  }

  /// `BlobTransport` that "uploads" into `UITestBlobStorage` in process. It reads the package
  /// file exactly as the real transports do (read only) and never touches the network.
  public struct UITestBlobTransport: BlobTransport {
    public let storage: UITestBlobStorage

    public init(storage: UITestBlobStorage) {
      self.storage = storage
    }

    public func putBlob(_ upload: BlobUpload) async throws {
      storage.putBlob(try read(upload, offset: 0, length: Int(upload.bytes)), at: location(upload))
    }

    public func putBlock(
      _ upload: BlobUpload, blockId: String, offset: Int64, length: Int
    ) async throws {
      storage.putBlock(
        try read(upload, offset: offset, length: length), id: blockId, at: location(upload))
    }

    public func putBlockList(_ upload: BlobUpload, blockIds: [String]) async throws {
      guard storage.commit(blockIds, at: location(upload)) else {
        throw BlobTransportError.http(status: 400, code: "InvalidBlockList")
      }
    }

    private func location(_ upload: BlobUpload) -> String { upload.target.blobLocation }

    private func read(_ upload: BlobUpload, offset: Int64, length: Int) throws -> Data {
      do {
        let handle = try FileHandle(forReadingFrom: upload.file)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: length) ?? Data()
      } catch {
        throw BlobTransportError.unreadable("cannot read \(upload.file.lastPathComponent)")
      }
    }
  }
#endif
