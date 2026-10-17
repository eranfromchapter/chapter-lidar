import XCTest

@testable import MeshExport

/// AC5: thinning keeps every 5 mm voxel represented and never exceeds the point cap.
final class ThinningTests: XCTestCase {
  private struct Voxel: Hashable {
    var x: Int
    var y: Int
    var z: Int
  }

  private func voxels(_ samples: [DepthSample], origin: SIMD3<Double>, size: Double) -> Set<Voxel> {
    var set = Set<Voxel>()
    for s in samples {
      set.insert(
        Voxel(
          x: Int(((Double(s.x) - origin.x) / size).rounded(.down)),
          y: Int(((Double(s.y) - origin.y) / size).rounded(.down)),
          z: Int(((Double(s.z) - origin.z) / size).rounded(.down))))
    }
    return set
  }

  /// A dense floor patch: 1 mm grid over `side` metres (many points per 5 mm voxel), with a wall.
  private func densePatch(side: Double) -> [DepthSample] {
    var samples: [DepthSample] = []
    let steps = Int(side / 0.001)
    for i in 0...steps {
      for j in 0...steps {
        let c = UInt8((i + j) % 256)
        samples.append(DepthSample(x: Float(i) * 0.001, y: 0, z: Float(j) * 0.001, r: c, g: 10, b: 20))
      }
    }
    for i in 0...steps {
      for k in 0...200 {
        samples.append(DepthSample(x: Float(i) * 0.001, y: Float(k) * 0.001, z: 0, r: 200, g: 200, b: 200))
      }
    }
    return samples
  }

  func testKeepsEveryOccupiedVoxelAndOnlyOnePerVoxel() throws {
    let input = densePatch(side: 0.3)
    let result = try PointThinning.thin(input)
    XCTAssertEqual(result.effectiveVoxelSize, 0.005)
    XCTAssertLessThan(result.points.count, input.count / 10)

    let inputVoxels = voxels(input, origin: result.gridOrigin, size: result.effectiveVoxelSize)
    let outputVoxels = voxels(result.points, origin: result.gridOrigin, size: result.effectiveVoxelSize)
    XCTAssertEqual(outputVoxels, inputVoxels, "every occupied 5 mm voxel stays represented")
    XCTAssertEqual(result.points.count, outputVoxels.count, "at most one point per voxel")
  }

  func testNeverExceedsTheCapAndStillCoversTheCloud() throws {
    let input = densePatch(side: 0.3)
    for cap in [50, 500, 3_000] {
      let result = try PointThinning.thin(input, options: ThinningOptions(maxPoints: cap))
      XCTAssertLessThanOrEqual(result.points.count, cap, "cap \(cap)")
      XCTAssertGreaterThan(result.points.count, 0)
      XCTAssertGreaterThan(result.effectiveVoxelSize, 0.005, "voxel grows when the cap forces it")
      let inputVoxels = voxels(input, origin: result.gridOrigin, size: result.effectiveVoxelSize)
      let outputVoxels = voxels(result.points, origin: result.gridOrigin, size: result.effectiveVoxelSize)
      XCTAssertEqual(outputVoxels, inputVoxels, "cap \(cap): coverage kept at the larger voxel")
    }
  }

  func testDefaultsAreFiveMillimetresAndTwentyMillionPoints() {
    XCTAssertEqual(ThinningOptions().voxelSize, 0.005)
    XCTAssertEqual(ThinningOptions().maxPoints, 20_000_000)
  }

  func testSparseFixtureCloudsAreKeptWhole() throws {
    for capture in try Fixtures.allCaptures() {
      let samples = try capture.depthSamples()
      let result = try PointThinning.thin(samples)
      let inputVoxels = voxels(samples, origin: result.gridOrigin, size: result.effectiveVoxelSize)
      let outputVoxels = voxels(result.points, origin: result.gridOrigin, size: result.effectiveVoxelSize)
      XCTAssertEqual(inputVoxels, outputVoxels, "\(capture.fixture)/\(capture.truth.areaKey)")
      XCTAssertLessThanOrEqual(result.points.count, samples.count)
      XCTAssertLessThanOrEqual(result.points.count, ThinningOptions.defaultMaxPoints)
    }
  }

  func testKeepsTheSampleNearestTheVoxelCentreAndIsDeterministic() throws {
    // Three points in one voxel (origin = first point's min): the middle one is nearest the centre.
    let a = DepthSample(x: 0.0000, y: 0, z: 0, r: 1, g: 0, b: 0)
    let b = DepthSample(x: 0.0025, y: 0.0025, z: 0.0025, r: 2, g: 0, b: 0)
    let c = DepthSample(x: 0.0049, y: 0.0049, z: 0.0049, r: 3, g: 0, b: 0)
    let far = DepthSample(x: 0.0501, y: 0.0001, z: 0.0001, r: 4, g: 0, b: 0)
    let first = try PointThinning.thin([a, b, c, far])
    XCTAssertEqual(first.points.map(\.r), [2, 4])
    XCTAssertEqual(try PointThinning.thin([a, b, c, far]).points, first.points)
  }

  func testConfidenceFilterAndInvalidOptions() throws {
    let samples = [
      DepthSample(x: 0, y: 0, z: 0, r: 0, g: 0, b: 0, confidence: 0),
      DepthSample(x: 1, y: 0, z: 0, r: 0, g: 0, b: 0, confidence: 2),
    ]
    let result = try PointThinning.thin(samples, options: ThinningOptions(minimumConfidence: 1))
    XCTAssertEqual(result.points.count, 1)
    XCTAssertEqual(result.droppedLowConfidence, 1)
    XCTAssertThrowsError(try PointThinning.thin(samples, options: ThinningOptions(voxelSize: 0)))
    XCTAssertThrowsError(try PointThinning.thin(samples, options: ThinningOptions(maxPoints: 0)))
    XCTAssertEqual(try PointThinning.thin([]).points.count, 0)
  }
}
