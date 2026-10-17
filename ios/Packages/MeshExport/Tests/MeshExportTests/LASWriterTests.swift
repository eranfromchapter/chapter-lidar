import XCTest

@testable import MeshExport

/// AC4: LAS files carry a header point count and extents equal to the written points.
/// (The PDAL check runs on the files in .build/test-output via scripts/verify-exports.sh.)
final class LASWriterTests: XCTestCase {
  private let fixedDate = Date(timeIntervalSince1970: 1_792_000_000)  // 2026-10-14 UTC

  func testHeaderAndRecordsForEveryFixture() throws {
    for capture in try Fixtures.allCaptures() {
      let name = "\(capture.fixture)/\(capture.truth.areaKey)"
      let samples = try capture.depthSamples()
      let (data, summary) = try LASWriter.encode(
        points: samples, options: LASOptions(generatorVersion: "1.2.3", creationDate: fixedDate))
      let las = LASContents(data)

      XCTAssertEqual(las.signature, "LASF")
      XCTAssertEqual(las.versionMajor, 1)
      XCTAssertEqual(las.versionMinor, 4)
      XCTAssertEqual(las.headerSize, 375)
      XCTAssertEqual(las.format, 7)
      XCTAssertEqual(las.recordLength, 36)
      XCTAssertEqual(las.legacyCount, 0, "legacy count is zero for formats 6 to 10")
      XCTAssertEqual(las.pointCount, samples.count, name)
      XCTAssertEqual(summary.pointCount, samples.count)
      XCTAssertEqual(las.systemIdentifier, "Chapter Capture")
      XCTAssertEqual(las.generatingSoftware, "Chapter Capture 1.2.3")
      XCTAssertEqual(las.scale, [0.001, 0.001, 0.001])
      XCTAssertEqual(las.globalEncoding & 0x10, 0, "no WKT: local coordinates")
      XCTAssertEqual(las.globalEncoding & 0x08, 0x08, "marked as derived (synthetic returns)")
      XCTAssertEqual(las.u16(90), 287, "creation day of year")
      XCTAssertEqual(las.u16(92), 2026)
      XCTAssertEqual(data.count, summary.fileBytes)
      XCTAssertEqual(las.pointDataOffset + las.pointCount * 36, data.count)

      // The provenance VLR says phone depth sensor, not survey data.
      XCTAssertEqual(las.vlrCount, 1)
      XCTAssertEqual(las.ascii(375 + 2, 16), "ChapterCapture")
      let vlrText = las.ascii(375 + 54, las.pointDataOffset - 375 - 54)
      XCTAssertTrue(vlrText.contains("phone depth sensor"))
      XCTAssertTrue(vlrText.contains("Not raw survey data"))

      // Header extents equal the extents of the written points; offsets are the box minimum.
      let extents = las.recomputedExtents()
      for axis in 0..<3 {
        XCTAssertEqual(las.headerMin[axis], extents.min[axis], accuracy: 1e-9, "\(name) min \(axis)")
        XCTAssertEqual(las.headerMax[axis], extents.max[axis], accuracy: 1e-9, "\(name) max \(axis)")
        XCTAssertEqual(las.offset[axis], las.headerMin[axis], accuracy: 1e-12, "offset at minimum")
        XCTAssertEqual(summary.min[axis], las.headerMin[axis])
        XCTAssertEqual(summary.max[axis], las.headerMax[axis])
      }

      // Z up: LAS (x, y, z) = (x, -z, y). Compare with the depth samples within the 1 mm scale.
      let points = las.points()
      for (index, sample) in samples.enumerated().prefix(500) {
        let p = points[index]
        XCTAssertEqual(p.xyz[0], Double(sample.x), accuracy: 0.0006)
        XCTAssertEqual(p.xyz[1], -Double(sample.z), accuracy: 0.0006)
        XCTAssertEqual(p.xyz[2], Double(sample.y), accuracy: 0.0006)
        XCTAssertEqual(p.rgb, [Int(sample.r) * 257, Int(sample.g) * 257, Int(sample.b) * 257])
        XCTAssertEqual(p.intensity, 0)
      }
      XCTAssertEqual(points.map(\.gps), points.map(\.gps).sorted(), "GPS time ascends")

      // Against truth.json: the cloud carries up to 5 mm noise per axis (plus 1 mm quantisation).
      let truth = capture.truth.boundsM
      XCTAssertEqual(extents.min[0], truth.min[0], accuracy: 0.0065)
      XCTAssertEqual(extents.max[0], truth.max[0], accuracy: 0.0065)
      XCTAssertEqual(extents.min[1], -truth.max[2], accuracy: 0.0065)
      XCTAssertEqual(extents.max[1], -truth.min[2], accuracy: 0.0065)
      XCTAssertEqual(extents.min[2], truth.min[1], accuracy: 0.0065)
      XCTAssertEqual(extents.max[2], truth.max[1], accuracy: 0.0065)
    }
  }

  func testStreamedFileEqualsEncodedBytes() throws {
    let samples = try Fixtures.captures(of: "box-room")[0].depthSamples()
    let options = LASOptions(creationDate: fixedDate)
    let url = Fixtures.outputDirectory("las-streamed").appendingPathComponent("points.las")
    let summary = try LASWriter.write(points: samples, to: url, options: options)
    let encoded = try LASWriter.encode(points: samples, options: options)
    XCTAssertEqual(try Data(contentsOf: url), encoded.data)
    XCTAssertEqual(summary, encoded.summary)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("part").path))
  }

  func testOffsetsAreAtTheMinimumAndExtentsCoverSingleAndNegativePoints() throws {
    let samples = [
      DepthSample(x: -1.2345, y: 0.5, z: 2.0004, r: 255, g: 0, b: 128),
      DepthSample(x: 3.0, y: 2.5, z: -4.0, r: 0, g: 255, b: 0),
    ]
    let las = LASContents(try LASWriter.encode(points: samples).data)
    XCTAssertEqual(las.pointCount, 2)
    XCTAssertEqual(las.offset[0], -1.2345, accuracy: 1e-6)
    XCTAssertEqual(las.offset[1], -2.0004, accuracy: 1e-6)  // -z of the first point
    XCTAssertEqual(las.offset[2], 0.5, accuracy: 1e-6)
    XCTAssertEqual(las.headerMax[0], 3.0, accuracy: 0.0006)
    XCTAssertEqual(las.headerMax[1], 4.0, accuracy: 0.0006)
    XCTAssertEqual(las.headerMax[2], 2.5, accuracy: 0.0006)
    XCTAssertEqual(las.points()[0].rgb, [65535, 0, 128 * 257])
  }

  func testNoPointsAndNonFinitePointsAreRejected() {
    XCTAssertThrowsError(try LASWriter.encode(points: []))
    XCTAssertThrowsError(
      try LASWriter.encode(points: [DepthSample(x: .nan, y: 0, z: 0, r: 0, g: 0, b: 0)]))
  }

  func testOptionalLocalWKTSetsTheBitAndWritesTheVLR() throws {
    let samples = try Fixtures.captures(of: "box-room")[0].depthSamples()
    let options = LASOptions(creationDate: fixedDate, writeLocalCoordinateSystemWKT: true)
    let url = Fixtures.outputDirectory("las-local-wkt").appendingPathComponent("points.las")
    try LASWriter.write(points: samples, to: url, options: options)
    let las = LASContents(try Data(contentsOf: url))
    XCTAssertEqual(las.globalEncoding & 0x10, 0x10)
    XCTAssertEqual(las.vlrCount, 2)
    XCTAssertEqual(las.pointCount, samples.count)
    XCTAssertEqual(las.pointDataOffset + las.pointCount * 36, las.bytes.count)
  }

  func testProvenanceConstantsNeverClaimSurveyData() {
    XCTAssertFalse(ExportProvenance.isSurveyGrade)
    XCTAssertEqual(ExportProvenance.lasSource, "phone_depth_sensor")
    XCTAssertTrue(ExportProvenance.statement.contains("Not raw survey data"))
  }
}
