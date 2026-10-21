#if canImport(UIKit) && os(iOS)
  import CaptureContract
  import CaptureCore
  @testable import CaptureUI
  import ChapterUI
  import ChapterUISnapshotTesting
  import SwiftUI
  import XCTest

  /// The compass parts of the capture screens on boards (compass §13.3, phone parts): the row of
  /// "What are you scanning?" in its six states with the Location-off note and Open Settings,
  /// and the live scan's chip in its five states.
  @MainActor
  final class CompassViewSnapshotTests: ChapterSnapshotTestCase {
    typealias F = CaptureScreenFixtures

    private struct RowsBoard: View {
      var body: some View {
        let ago = F.now.addingTimeInterval(-12)
        let states: [CompassPrecheckState] = [
          .reading,
          .result(heading: 212.4, accuracy: 8, source: .trueNorth, readAt: ago),
          .result(heading: 212.4, accuracy: 18, source: .trueNorth, readAt: ago),
          .result(heading: 38, accuracy: 12, source: .magnetic, readAt: F.now.addingTimeInterval(-90)),
          .result(heading: 212.4, accuracy: 42, source: .trueNorth, readAt: ago),
          .notCalibrated,
          .unavailable,
        ]
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(states.indices, id: \.self) { index in
              ChapterCard {
                CompassRow(state: states[index], now: { F.now }, onReadAgain: {})
              }
            }
            CompassFootnotes(isLocationOff: true, onOpenSettings: {})
          }
          .padding(.horizontal, ChapterTheme.Metric.screenPadding)
          .padding(.top, 62)
        }
        .chapterScreenBackground()
      }
    }

    private struct ChipsBoard: View {
      var body: some View {
        let states: [CompassLiveState] = [
          .reading,
          .result(.verified(heading: 212.4, accuracy: 8), cameraBearing: 0),
          .result(.verified(heading: 212.4, accuracy: 8), cameraBearing: 300),
          .result(.approximate(heading: 212.4, accuracy: 18, source: .trueNorth), cameraBearing: 90),
          .result(.approximate(heading: 212.4, accuracy: 12, source: .magnetic), cameraBearing: 212),
          .notVerified,
        ]
        VStack(alignment: .leading, spacing: 16) {
          ForEach(states.indices, id: \.self) { index in
            CompassChip(state: states[index])
          }
        }
        .padding(.horizontal, ChapterTheme.Metric.screenPadding)
        .padding(.top, 62)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ChapterTheme.Color.ink)
      }
    }

    func testCompassRows() {
      assertChapterSnapshot(of: RowsBoard(), named: "compass-rows")
    }

    func testCompassRowsAtAX3() {
      assertChapterSnapshot(
        of: RowsBoard(), named: "compass-rows-ax3", contentSize: .accessibilityExtraLarge)
    }

    func testCompassChips() {
      assertChapterSnapshot(of: ChipsBoard(), named: "compass-chips")
    }
  }
#endif
