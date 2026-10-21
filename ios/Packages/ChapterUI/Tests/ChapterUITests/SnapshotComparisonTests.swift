#if canImport(UIKit) && os(iOS)
  import ChapterUI
  import ChapterUISnapshotTesting
  import CoreGraphics
  import SwiftUI
  import XCTest

  @testable import ChapterUISnapshotTesting

  final class SnapshotComparisonTests: XCTestCase {
    /// A 100 × 100 opaque image of one colour, with `changed` pixels (row-major from the top left)
    /// set to `changedColor`.
    private func image(
      _ color: (UInt8, UInt8, UInt8), changed: Int = 0,
      changedColor: (UInt8, UInt8, UInt8) = (0, 0, 0), width: Int = 100, height: Int = 100
    ) throws -> CGImage {
      var pixels = [UInt8]()
      for index in 0..<(width * height) {
        let c = index < changed ? changedColor : color
        pixels += [c.0, c.1, c.2, 255]
      }
      return try XCTUnwrap(SnapshotComparison.image(rgba: pixels, width: width, height: height))
    }

    func testIdenticalImagesPass() throws {
      let a = try image((250, 245, 238))
      let (result, diff) = SnapshotComparison.compare(reference: a, actual: a, channelTolerance: 8)
      XCTAssertEqual(result.differingPixels, 0)
      XCTAssertTrue(result.passes(.phone))
      XCTAssertNotNil(diff)
    }

    func testChannelDifferencesUpToEightAreIgnored() throws {
      let reference = try image((100, 100, 100))
      let actual = try image((108, 92, 100))
      let (result, _) = SnapshotComparison.compare(
        reference: reference, actual: actual, channelTolerance: 8)
      XCTAssertEqual(result.differingPixels, 0)
      let (beyond, _) = SnapshotComparison.compare(
        reference: reference, actual: try image((109, 100, 100)), channelTolerance: 8)
      XCTAssertEqual(beyond.differingPixels, 100 * 100)
      XCTAssertFalse(beyond.passes(.phone))
    }

    func testFailsAboveHalfAPercentOfPixels() throws {
      let reference = try image((250, 245, 238))
      // 50 of 10,000 pixels = 0.5 %: passes. 51: fails.
      let atLimit = try image((250, 245, 238), changed: 50)
      let overLimit = try image((250, 245, 238), changed: 51)
      let (passing, _) = SnapshotComparison.compare(
        reference: reference, actual: atLimit, channelTolerance: 8)
      XCTAssertEqual(passing.differingPixels, 50)
      XCTAssertTrue(passing.passes(.phone))
      let (failing, _) = SnapshotComparison.compare(
        reference: reference, actual: overLimit, channelTolerance: 8)
      XCTAssertEqual(failing.differingPixels, 51)
      XCTAssertFalse(failing.passes(.phone))
    }

    func testDifferentSizesFail() throws {
      let (result, diff) = SnapshotComparison.compare(
        reference: try image((1, 2, 3)), actual: try image((1, 2, 3), width: 100, height: 101),
        channelTolerance: 8)
      XCTAssertFalse(result.sizesMatch)
      XCTAssertFalse(result.passes(.phone))
      XCTAssertNil(diff)
    }

    func testDiffMarksDifferingPixelsRed() throws {
      let reference = try image((250, 245, 238))
      let actual = try image((250, 245, 238), changed: 1)
      let (_, diff) = SnapshotComparison.compare(
        reference: reference, actual: actual, channelTolerance: 8)
      let pixels = try XCTUnwrap(SnapshotComparison.rgbaPixels(try XCTUnwrap(diff)))
      XCTAssertEqual(Array(pixels[0..<4]), [255, 0, 0, 255])
      XCTAssertNotEqual(Array(pixels[4..<8]), [255, 0, 0, 255])
    }

    func testReferencesLiveNextToTheTestFile() {
      let url = ChapterSnapshot.referenceURL(
        name: "buttons", file: "/repo/Tests/ChapterUITests/ComponentSnapshotTests.swift")
      XCTAssertEqual(
        url.path, "/repo/Tests/ChapterUITests/__Snapshots__/ComponentSnapshotTests/buttons.png")
    }

    /// The view of the harness's own reference,
    /// `__Snapshots__/SnapshotComparisonTests/harness.png`.
    private struct HarnessView: View {
      var background = ChapterTheme.Color.ground

      var body: some View {
        VStack(spacing: 16) {
          ChapterLogo()
          StatusLabel(kind: .done, word: "Ready")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
      }
    }

    @MainActor
    func testMatchesItsReference() {
      ChapterSnapshot.prepare()
      assertChapterSnapshot(of: HarnessView(), named: "harness")
    }

    /// A changed colour token (ground → nude, 13/255 apart) is caught, and the new image and a
    /// diff are kept.
    @MainActor
    func testAChangedViewFailsAndKeepsTheEvidence() throws {
      ChapterSnapshot.prepare()
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ChapterUISnapshotHarnessTest-\(UUID().uuidString)")
      setenv("SNAPSHOT_ARTIFACTS", directory.path, 1)
      defer {
        unsetenv("SNAPSHOT_ARTIFACTS")
        try? FileManager.default.removeItem(at: directory)
      }
      XCTExpectFailure("another background does not match the reference") {
        assertChapterSnapshot(
          of: HarnessView(background: ChapterTheme.Color.nude), named: "harness", record: false)
      }
      let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
      XCTAssertEqual(files, ["harness.actual.png", "harness.diff.png"])
    }

    @MainActor
    func testRendererDrawsTheDeviceFrameAtScaleThree() throws {
      let image = SnapshotRenderer.image(of: Color.red.ignoresSafeArea())
      XCTAssertEqual(image.scale, 3)
      XCTAssertEqual(image.size, CGSize(width: 402, height: 874))
      let cgImage = try XCTUnwrap(image.cgImage)
      XCTAssertEqual(cgImage.width, 1206)
      XCTAssertEqual(cgImage.height, 2622)
    }

    @MainActor
    func testRendererGivesTheDeviceSafeArea() throws {
      // Ground fills the safe area only; the window's own background (black) shows above and
      // below it, 62 and 34 pt.
      let image = SnapshotRenderer.image(of: Color(red: 0, green: 1, blue: 0))
      let pixels = try XCTUnwrap(SnapshotComparison.rgbaPixels(try XCTUnwrap(image.cgImage)))
      func green(atPoint y: Int) -> Bool {
        let offset = (y * 3 * 1206 + 600) * 4
        return pixels[offset] < 20 && pixels[offset + 1] > 235 && pixels[offset + 2] < 20
      }
      XCTAssertFalse(green(atPoint: 61))
      XCTAssertTrue(green(atPoint: 63))
      XCTAssertTrue(green(atPoint: 838))
      XCTAssertFalse(green(atPoint: 841))
    }
  }
#endif
