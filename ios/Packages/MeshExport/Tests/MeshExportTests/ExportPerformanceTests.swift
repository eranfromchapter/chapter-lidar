import XCTest

@testable import MeshExport

/// AC6: exporting the two-floor fixture completes in under 60 s on the Linux runner.
final class ExportPerformanceTests: XCTestCase {
  private func assertUnderLimit(_ seconds: Double, _ label: String) {
    XCTAssertLessThan(seconds, 60, "\(label) took \(seconds) s")
  }

  func testTwoFloorFixtureExportCompletesInUnderSixtySeconds() throws {
    let captures = try Fixtures.captures(of: "two-floor-house")
    let directory = Fixtures.outputDirectory("performance", "two-floor-house")
    let clock = ContinuousClock()
    let elapsed = try clock.measure {
      // Exactly what the app writes for the visit: every capture's files, then the combined GLB.
      var floors: [FloorMesh] = []
      for capture in captures {
        let floor = try capture.floorMesh()
        floors.append(floor)
        _ = try CaptureExporter.export(
          floors: [floor], depthSamples: try capture.depthSamples(),
          to: directory.appendingPathComponent(capture.truth.areaKey))
      }
      _ = try CaptureExporter.export(floors: floors, to: directory.appendingPathComponent("combined"))
    }
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    print("ExportPerformanceTests: two-floor fixture export took \(seconds) s")
    assertUnderLimit(seconds, "two-floor fixture export")
    for area in ["floor-1", "floor-2"] {
      for file in ["mesh.glb", "mesh.obj", "mesh.mtl", "points.las"] {
        XCTAssertTrue(
          FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(area).appendingPathComponent(file).path), "\(area)/\(file)")
      }
    }
  }

  func testDenseTwoFloorExportWithDecimationAndThinningStaysUnderSixtySeconds() throws {
    // The same two floors with the meshes cut into ~170k triangles each and 31 shifted copies of
    // the depth samples, so decimation, thinning and all three writers do real work.
    let captures = try Fixtures.captures(of: "two-floor-house")
    let clock = ContinuousClock()
    var decimated = 0
    var thinnedFrom = 0
    var thinnedTo = 0
    let elapsed = try clock.measure {
      for capture in captures {
        let base = try capture.floorMesh().mesh
        let dense = MeshFactory.subdivided(base, 120)
        var samples = try capture.depthSamples()
        let original = samples
        for copy in 0..<30 {
          for var sample in original {
            sample.x += Float(copy) * 0.0001
            samples.append(sample)
          }
        }
        let report = try CaptureExporter.export(
          floors: [FloorMesh(areaKey: capture.truth.areaKey, label: capture.truth.label, mesh: dense)],
          depthSamples: samples,
          to: Fixtures.outputDirectory("performance", "dense", capture.truth.areaKey),
          options: ExportOptions(faceBudget: 50_000))
        decimated += report.decimation[0].outputFaces
        thinnedFrom += samples.count
        thinnedTo += report.thinning!.points.count
        XCTAssertLessThanOrEqual(report.decimation[0].outputFaces, 50_000)
      }
    }
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    print("ExportPerformanceTests: dense export took \(seconds) s (faces \(decimated), points \(thinnedFrom) -> \(thinnedTo))")
    assertUnderLimit(seconds, "dense two-floor export")
    XCTAssertLessThan(thinnedTo, thinnedFrom)
  }
}
