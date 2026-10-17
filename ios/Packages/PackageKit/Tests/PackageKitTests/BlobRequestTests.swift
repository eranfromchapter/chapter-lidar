import CaptureContract
import Foundation
import PackageCore
@testable import PackageTransport
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

final class BlobRequestTests: XCTestCase {
  private let target = UploadTarget(
    url: "https://blob.invalid/originals/pkg/Site%20Photos/floor-1/photo-0001.jpg?sv=2025&ticket=abc",
    headers: ["x-ms-blob-type": "BlockBlob"],
    expiresAt: UTCTimestamp(secondsSince1970: 1_800_000_000))

  private func upload() -> BlobUpload {
    BlobUpload(
      target: target, file: URL(fileURLWithPath: "/dev/null"), bytes: 0, mime: "image/jpeg")
  }

  func testPutBlobUsesTheTargetExactlyWithItsHeaders() throws {
    let request = try BlobRequests.putBlob(upload())
    XCTAssertEqual(request.httpMethod, "PUT")
    XCTAssertEqual(request.url?.absoluteString, target.url)
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-ms-blob-type"), "BlockBlob")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
  }

  func testPutBlockAppendsBlockParametersAndDropsTheBlobTypeHeader() throws {
    let blockId = BlobBlocks.blockId(3)
    let request = try BlobRequests.putBlock(upload(), blockId: blockId)
    let url = try XCTUnwrap(request.url?.absoluteString)
    XCTAssertTrue(url.hasPrefix(target.url + "&comp=block&blockid="))
    let components = try XCTUnwrap(URLComponents(string: url))
    XCTAssertEqual(components.queryItems?.first { $0.name == "blockid" }?.value, blockId)
    XCTAssertNil(request.value(forHTTPHeaderField: "x-ms-blob-type"))
  }

  func testPutBlockListCommitsTheBlocksInOrder() throws {
    let request = try BlobRequests.putBlockList(upload())
    XCTAssertEqual(request.url?.absoluteString, target.url + "&comp=blocklist")
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-ms-blob-content-type"), "image/jpeg")
    let body = String(decoding: BlobRequests.blockListBody(["QQ==", "Qg=="]), as: UTF8.self)
    XCTAssertEqual(
      body,
      "<?xml version=\"1.0\" encoding=\"utf-8\"?><BlockList><Latest>QQ==</Latest><Latest>Qg==</Latest></BlockList>"
    )
  }

  func testBlockIdsAreDeterministicAndOfEqualLength() throws {
    let ids = (0..<1000).map(BlobBlocks.blockId)
    XCTAssertEqual(Set(ids).count, 1000)
    XCTAssertEqual(Set(ids.map(\.count)).count, 1)
    XCTAssertEqual(BlobBlocks.blockId(7), BlobBlocks.blockId(7))
    XCTAssertEqual(
      String(decoding: try XCTUnwrap(Data(base64Encoded: BlobBlocks.blockId(42))), as: UTF8.self),
      "blk-00000042")
    XCTAssertEqual(BlobBlocks.blockSize, 8 * 1024 * 1024)
    XCTAssertEqual(BlobBlocks.blockCount(bytes: 0), 0)
    XCTAssertEqual(BlobBlocks.blockCount(bytes: Int64(BlobBlocks.blockSize)), 1)
    XCTAssertEqual(BlobBlocks.blockCount(bytes: Int64(BlobBlocks.blockSize) + 1), 2)
  }

  func testTargetDescriptionsNeverShowTheSasUrl() {
    let texts = [
      String(describing: target), String(reflecting: target), dumped(target),
      String(describing: FileUploadStateWithTarget(target: target)),
    ]
    for text in texts {
      XCTAssertFalse(text.contains("ticket"), text)
      XCTAssertFalse(text.contains("blob.invalid"), text)
    }
    XCTAssertEqual(target.blobLocation, "https://blob.invalid/originals/pkg/Site%20Photos/floor-1/photo-0001.jpg")
  }

  func testNon201AnswersBecomeErrorsWithTheServiceCodeOnly() throws {
    let url = try XCTUnwrap(URL(string: target.url))
    let response = HTTPURLResponse(
      url: url, statusCode: 403, httpVersion: "HTTP/1.1",
      headerFields: ["x-ms-error-code": "AuthenticationFailed"])
    XCTAssertThrowsError(try BlobRequests.check(response)) { error in
      XCTAssertEqual(error as? BlobTransportError, .http(status: 403, code: "AuthenticationFailed"))
      XCTAssertFalse(String(describing: error).contains("ticket"))
    }
    let created = HTTPURLResponse(url: url, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: [:])
    XCTAssertNoThrow(try BlobRequests.check(created))
  }

  private func dumped<T>(_ value: T) -> String {
    var text = ""
    dump(value, to: &text)
    return text
  }
}

private struct FileUploadStateWithTarget {
  let target: UploadTarget
}
