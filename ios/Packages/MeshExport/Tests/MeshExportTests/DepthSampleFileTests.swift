import XCTest

@testable import MeshExport

final class DepthSampleFileTests: XCTestCase {
  func testReadsEveryFixtureFileAndRoundTripsByteForByte() throws {
    for capture in try Fixtures.allCaptures() {
      let bytes = try Data(contentsOf: capture.depthURL)
      let samples = try DepthSampleFile.read(bytes)
      let declared = Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16 | Int(bytes[11]) << 24
      XCTAssertEqual(samples.count, declared)
      XCTAssertGreaterThan(samples.count, 100)
      XCTAssertEqual(DepthSampleFile.encode(samples), bytes, "\(capture.fixture)/\(capture.truth.areaKey)")
      XCTAssertTrue(samples.allSatisfy { $0.confidence <= 2 })
    }
  }

  func testRejectsBadFiles() throws {
    let good = DepthSampleFile.encode([DepthSample(x: 1, y: 2, z: 3, r: 4, g: 5, b: 6)])
    XCTAssertNoThrow(try DepthSampleFile.read(good))
    XCTAssertThrowsError(try DepthSampleFile.read(Data()))
    XCTAssertThrowsError(try DepthSampleFile.read(good.dropLast()))
    var wrongMagic = good
    wrongMagic[0] = 0x58
    XCTAssertThrowsError(try DepthSampleFile.read(wrongMagic))
    var wrongVersion = good
    wrongVersion[4] = 2
    XCTAssertThrowsError(try DepthSampleFile.read(wrongVersion))
  }
}
