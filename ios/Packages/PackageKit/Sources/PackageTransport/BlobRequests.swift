import Foundation
import PackageCore

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Azure Blob requests built from an upload target. The SAS URL is used exactly as issued; only
/// the `comp`/`blockid` parameters are appended for Put Block and Put Block List. Nothing here
/// logs or stringifies the URL.
enum BlobRequests {
  /// The target's headers that apply to Put Blob only.
  static let putBlobOnlyHeaders: Set<String> = ["x-ms-blob-type"]

  static func putBlob(_ upload: BlobUpload) throws -> URLRequest {
    var request = try base(upload.target, extraQuery: nil)
    for (name, value) in upload.target.headers {
      request.setValue(value, forHTTPHeaderField: name)
    }
    request.setValue(upload.mime, forHTTPHeaderField: "Content-Type")
    return request
  }

  static func putBlock(_ upload: BlobUpload, blockId: String) throws -> URLRequest {
    var request = try base(
      upload.target, extraQuery: "comp=block&blockid=\(percentEncoded(blockId))")
    applyNonBlobHeaders(upload.target, to: &request)
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    return request
  }

  static func putBlockList(_ upload: BlobUpload) throws -> URLRequest {
    var request = try base(upload.target, extraQuery: "comp=blocklist")
    applyNonBlobHeaders(upload.target, to: &request)
    request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
    request.setValue(upload.mime, forHTTPHeaderField: "x-ms-blob-content-type")
    return request
  }

  /// `<BlockList><Latest>id</Latest>...</BlockList>`. Block ids are base64 (no XML escaping
  /// needed, but escaped anyway).
  static func blockListBody(_ blockIds: [String]) -> Data {
    var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><BlockList>"
    for id in blockIds {
      let escaped = id.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
      xml += "<Latest>\(escaped)</Latest>"
    }
    xml += "</BlockList>"
    return Data(xml.utf8)
  }

  /// Error for a non-201 answer, with the service's error code (never the URL).
  static func check(_ response: URLResponse?) throws {
    guard let http = response as? HTTPURLResponse else {
      throw BlobTransportError.network("no HTTP response")
    }
    guard http.statusCode == 201 else {
      throw BlobTransportError.http(
        status: http.statusCode, code: http.value(forHTTPHeaderField: "x-ms-error-code"))
    }
  }

  /// Reads `length` bytes at `offset` of a file opened for reading only.
  static func readSlice(of file: URL, offset: Int64, length: Int) throws -> Data {
    if length == 0 {
      return Data()
    }
    do {
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      try handle.seek(toOffset: UInt64(offset))
      let data = try handle.read(upToCount: length) ?? Data()
      guard data.count == length else {
        throw BlobTransportError.unreadable("short read")
      }
      return data
    } catch let error as BlobTransportError {
      throw error
    } catch {
      throw BlobTransportError.unreadable(String(describing: type(of: error)))
    }
  }

  private static func applyNonBlobHeaders(_ target: UploadTarget, to request: inout URLRequest) {
    for (name, value) in target.headers where !putBlobOnlyHeaders.contains(name.lowercased()) {
      request.setValue(value, forHTTPHeaderField: name)
    }
  }

  private static func base(_ target: UploadTarget, extraQuery: String?) throws -> URLRequest {
    guard target.method.uppercased() == "PUT" else {
      throw BlobTransportError.http(status: 0, code: "UnsupportedMethod")
    }
    var text = target.url
    if let extraQuery {
      text += (text.contains("?") ? "&" : "?") + extraQuery
    }
    guard let url = URL(string: text) else {
      throw BlobTransportError.http(status: 0, code: "InvalidTargetURL")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    return request
  }

  private static func percentEncoded(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}
