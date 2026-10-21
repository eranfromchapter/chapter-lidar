#if canImport(UIKit) && os(iOS)
  import ChapterUI
  import ChapterUISnapshotTesting
  import SwiftUI
  import XCTest

  /// The component snapshots of phone-capture §10.2 item 6: every button state, the rows, the
  /// status, plus, equals and minus glyphs, the segmented control and chips, the compass glyph in
  /// its 3 states, the logo at 26 and 40 pt, the type scale and the navigation bar. Each board is a
  /// full iPhone 17 Pro screen (402 × 874 pt @3x, iOS 26.0). Record with RECORD_SNAPSHOTS=1.
  ///
  /// The boards with system chrome are also drawn by the render server in the app-hosted
  /// HostedTests/HostedSnapshotTests (glass back pill, switch knob, and the collapsed title of
  /// `CollapsedTitleScreen`, whose scrolled content this in-process renderer draws black on
  /// iOS 26).
  @MainActor
  final class ComponentSnapshotTests: ChapterSnapshotTestCase {
    func testButtons() {
      assertChapterSnapshot(of: ButtonsBoard(), named: "buttons")
    }

    func testNavigationRows() {
      assertChapterSnapshot(of: NavigationRowsBoard(), named: "rows-navigation")
    }

    func testFormRows() {
      assertChapterSnapshot(of: FormRowsBoard(), named: "rows-form")
    }

    func testEntryRows() {
      assertChapterSnapshot(of: EntryRowsBoard(), named: "rows-entry")
    }

    func testStatus() {
      assertChapterSnapshot(of: StatusBoard(), named: "status")
    }

    func testCompass() {
      assertChapterSnapshot(of: CompassBoard(), named: "compass")
    }

    func testBrand() {
      assertChapterSnapshot(of: BrandBoard(), named: "brand")
    }

    func testControls() {
      assertChapterSnapshot(of: ControlsBoard(), named: "controls")
    }

    func testType() {
      assertChapterSnapshot(of: TypeBoard(), named: "type")
    }

    func testNavigationBarPushedLargeTitle() {
      assertChapterSnapshot(of: PushedScreen(), named: "navigation-pushed")
    }

    func testNavigationBarHomeHeader() {
      assertChapterSnapshot(of: HomeHeaderScreen(), named: "navigation-home")
    }

    func testNavigationBarInlineTitle() {
      assertChapterSnapshot(of: InlineTitleScreen(), named: "navigation-inline")
    }

    /// Dynamic Type AX3: rows grow and wrap; nothing is clipped.
    func testNavigationRowsAtAX3() {
      assertChapterSnapshot(
        of: NavigationRowsBoard(), named: "rows-navigation-ax3",
        contentSize: .accessibilityExtraLarge)
    }

    func testFormRowsAtAX3() {
      assertChapterSnapshot(
        of: FormRowsBoard(), named: "rows-form-ax3", contentSize: .accessibilityExtraLarge)
    }

    func testButtonsAtAX3() {
      assertChapterSnapshot(
        of: ButtonsBoard(), named: "buttons-ax3", contentSize: .accessibilityExtraLarge)
    }
  }
#endif
