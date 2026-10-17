import Foundation
import PackageCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Blob transport over a foreground URLSession. Portable (Linux, macOS, iOS); used by tests and
/// as the in-app fallback. A request body is at most one block (8 MiB) or one small file, read
/// from the package file opened for reading only.
public struct HTTPBlobTransport: BlobTransport {
  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func putBlob(_ upload: BlobUpload) async throws {
    let body = try BlobRequests.readSlice(
      of: upload.file, offset: 0, length: Int(upload.bytes))
    try await send(BlobRequests.putBlob(upload), body: body)
  }

  public func putBlock(
    _ upload: BlobUpload, blockId: String, offset: Int64, length: Int
  ) async throws {
    let body = try BlobRequests.readSlice(of: upload.file, offset: offset, length: length)
    try await send(BlobRequests.putBlock(upload, blockId: blockId), body: body)
  }

  public func putBlockList(_ upload: BlobUpload, blockIds: [String]) async throws {
    try await send(BlobRequests.putBlockList(upload), body: BlobRequests.blockListBody(blockIds))
  }

  private func send(_ request: URLRequest, body: Data) async throws {
    let response: URLResponse
    do {
      (_, response) = try await session.upload(for: request, from: body)
    } catch let error as URLError {
      // URLError descriptions can quote the URL: keep only the code.
      throw BlobTransportError.network("URLError \(error.code.rawValue)")
    } catch {
      throw BlobTransportError.network(String(describing: type(of: error)))
    }
    try BlobRequests.check(response)
  }
}
