#if canImport(UIKit) && os(iOS)
  import ChapterUI
  import ChapterUISnapshotTesting
  import SwiftUI
  import XCTest

  /// The phone boards with system chrome, drawn the binding way (critique R-18d): inside a host
  /// app, with `drawHierarchy(in:afterScreenUpdates: true)`, so the render server composites the
  /// iOS 26 glass back pill, the switch's knob and the content scrolled under the bar, which the
  /// package's ComponentSnapshotTests (`layer.render(in:)`, no host app) cannot draw. The boards
  /// are those of Tests/ChapterUITests/SnapshotBoards.swift. Target and scheme
  /// `ChapterUISnapshots` in ios/project.yml; ios.yml runs them in the ChapterUI job.
  @MainActor
  final class HostedSnapshotTests: ChapterSnapshotTestCase {
    override func setUpWithError() throws {
      try super.setUpWithError()
      // Without the host app these would silently fall back to the in-process renderer.
      XCTAssertTrue(
        SnapshotRenderer.drawsWithRenderServer, "Run these tests hosted by ChapterUISnapshotHost")
    }

    /// The back chevron and its glass pill, the large title at the scroll edge (transparent bar
    /// over ground), the trailing caption and the action bar.
    func testNavigationBarPushedLargeTitle() {
      assertChapterSnapshot(of: PushedScreen(), named: "navigation-pushed")
    }

    /// Scrolled: the collapsed inline title in the opaque standard bar over the cards
    /// (phone-capture §9 R6).
    func testNavigationBarCollapsedTitle() {
      assertChapterSnapshot(of: CollapsedTitleScreen(), named: "navigation-collapsed")
    }

    func testNavigationBarHomeHeader() {
      assertChapterSnapshot(of: HomeHeaderScreen(), named: "navigation-home")
    }

    func testNavigationBarInlineTitle() {
      assertChapterSnapshot(of: InlineTitleScreen(), named: "navigation-inline")
    }

    /// The system switch, knob included.
    func testFormRows() {
      assertChapterSnapshot(of: FormRowsBoard(), named: "rows-form")
    }

    /// The back chevron is dark in its glass pill (phone-package §2.2: ink). iOS 26 draws it in
    /// the label colour whatever the tint; on iOS 17 and 18 the tint decides, which
    /// ChapterRootTests checks.
    func testBackChevronIsInk() {
      assertBackChevronIsInk(in: SnapshotRenderer.image(of: PushedScreen()))
    }
  }
#endif
