import Foundation
import PackageCore
import XCTest

final class SHA256Tests: XCTestCase {
  func testKnownVectors() {
    XCTAssertEqual(
      SHA256.hexDigest(of: Data()),
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    XCTAssertEqual(
      SHA256.hexDigest(of: Data("abc".utf8)),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    XCTAssertEqual(
      SHA256.hexDigest(of: Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    XCTAssertEqual(
      SHA256.hexDigest(of: Data(repeating: UInt8(ascii: "a"), count: 1_000_000)),
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
  }

  func testIncrementalUpdatesMatchOneShotAtEveryChunkBoundary() {
    var generator = SplitMix(seed: 7)
    let data = Data((0..<1000).map { _ in UInt8(truncatingIfNeeded: generator.next()) })
    let expected = SHA256.hexDigest(of: data)
    for chunk in [1, 3, 55, 56, 63, 64, 65, 127, 128, 999] {
      var hasher = SHA256()
      var offset = 0
      while offset < data.count {
        let end = min(offset + chunk, data.count)
        hasher.update(data.subdata(in: offset..<end))
        offset = end
      }
      XCTAssertEqual(hasher.finalizeHex(), expected, "chunk size \(chunk)")
    }
  }

  func testFileDigestStreamsTheFile() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    var generator = SplitMix(seed: 11)
    let data = Data(
      (0..<(FileDigest.chunkSize * 2 + 17)).map { _ in UInt8(truncatingIfNeeded: generator.next()) })
    let url = folder.url.appendingPathComponent("file.bin")
    try data.write(to: url)
    let digest = try FileDigest.of(fileAt: url)
    XCTAssertEqual(digest, FileDigest(sha256: SHA256.hexDigest(of: data), bytes: Int64(data.count)))
  }
}

/// Deterministic pseudo-random numbers for test data.
struct SplitMix {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
