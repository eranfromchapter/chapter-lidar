import Foundation
import PhotoStore
import XCTest

final class SHA256Tests: XCTestCase {
  func testKnownDigests() {
    XCTAssertEqual(
      SHA256.hexDigest(of: Data()),
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    XCTAssertEqual(
      SHA256.hexDigest(of: Data("abc".utf8)),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    XCTAssertEqual(
      SHA256.hexDigest(of: Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
  }

  func testMillionAs() {
    XCTAssertEqual(
      SHA256.hexDigest(of: Data(repeating: UInt8(ascii: "a"), count: 1_000_000)),
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
  }
}
