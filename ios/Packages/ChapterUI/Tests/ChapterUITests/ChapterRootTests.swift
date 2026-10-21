#if canImport(UIKit) && os(iOS)
  import ChapterUI
  import ChapterUISnapshotTesting
  import SwiftUI
  import XCTest

  @testable import ChapterUISnapshotTesting

  /// `chapterRoot()`: the SwiftUI half of the Chapter look, which ChapterCaptureApp puts on its
  /// root view and the snapshot harness on every view it draws.
  @MainActor
  final class ChapterRootTests: ChapterSnapshotTestCase {
    private func tintSwatch(_ view: some View) throws -> RGB {
      let renderer = ImageRenderer(content: view.frame(width: 12, height: 12))
      renderer.scale = 1
      let probe = try XCTUnwrap(PixelProbe(try XCTUnwrap(renderer.uiImage)))
      return probe.pixel(x: 6, y: 6)
    }

    func testTintIsInk() throws {
      let ink = RGB(.ink)
      let tinted = try tintSwatch(Rectangle().fill(.tint).chapterRoot())
      XCTAssertLessThanOrEqual(tinted.distance(to: ink), 2, "tint \(tinted), ink \(ink)")
      // Without it SwiftUI's tint is the system blue: what the back chevron was on iOS 17/18.
      let system = try tintSwatch(Rectangle().fill(.tint))
      XCTAssertGreaterThan(system.b - system.r, 100, "system tint \(system)")
    }

    func testHarnessDrawsUnderTheChapterRoot() throws {
      let image = SnapshotRenderer.image(of: Rectangle().fill(.tint).ignoresSafeArea())
      let probe = try XCTUnwrap(PixelProbe(image))
      XCTAssertLessThanOrEqual(probe.pixel(at: CGPoint(x: 201, y: 437)).distance(to: RGB(.ink)), 2)

      // Text without a font of its own is Inter body, as in the app.
      func board(_ text: some View) -> some View {
        text.frame(maxWidth: .infinity, maxHeight: .infinity).background(ChapterTheme.Color.ground)
      }
      let sample = Text("Hamburgefonstiv 0123")
      let byDefault = try XCTUnwrap(SnapshotRenderer.image(of: board(sample)).cgImage)
      let inter = try XCTUnwrap(
        SnapshotRenderer.image(of: board(sample.font(ChapterTheme.Font.body))).cgImage)
      let system = try XCTUnwrap(SnapshotRenderer.image(of: board(sample.font(.body))).cgImage)
      XCTAssertEqual(
        SnapshotComparison.compare(reference: inter, actual: byDefault, channelTolerance: 8).0
          .differingPixels, 0)
      XCTAssertGreaterThan(
        SnapshotComparison.compare(reference: inter, actual: system, channelTolerance: 8).0
          .differingPixels, 0, "SF and Inter draw differently")
    }

    /// The back chevron of a pushed screen is ink (phone-package §2.2), not the system blue: on
    /// iOS 17 and 18 its colour is the SwiftUI tint. iOS 26 draws it in a glass pill in the label
    /// colour whatever the tint, which the in-process renderer cannot draw (it comes out light);
    /// the app-hosted HostedSnapshotTests check it there.
    func testBackChevronIsInk() throws {
      if #available(iOS 26.0, *), !SnapshotRenderer.drawsWithRenderServer {
        throw XCTSkip(
          "iOS 26 draws the back chevron in the render server: ChapterUIHostedSnapshotTests")
      }
      assertBackChevronIsInk(in: SnapshotRenderer.image(of: PushedScreen()))
      // The check catches the system blue the chevron had without the root's tint.
      let blue = SnapshotRenderer.image(of: PushedScreen().tint(Color(uiColor: .systemBlue)))
      XCTExpectFailure("a system-blue chevron is not ink") {
        assertBackChevronIsInk(in: blue)
      }
    }
  }
#endif
