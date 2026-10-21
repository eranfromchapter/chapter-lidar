#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import ChapterUI
  import SwiftUI

  /// What the Capture overview asks its host to do.
  public struct CaptureOverviewActions {
    /// A floor row: that floor's scan (`ScanViewer`), by area key.
    public var openFloor: @MainActor (String) -> Void
    /// "Scan another floor or room": step 2 with the visit's project.
    public var addFloor: @MainActor () -> Void
    /// A "Before you leave" row: Photos, Field controls, or Before you leave focused on the
    /// compass or the skipped rooms (critique R-21, R-39).
    public var openCheck: @MainActor (CaptureOverviewState.CheckID) -> Void
    /// The bottom button (`CaptureOverviewState.ReviewButton` says where it leads).
    public var review: @MainActor () -> Void

    public init(
      openFloor: @escaping @MainActor (String) -> Void, addFloor: @escaping @MainActor () -> Void,
      openCheck: @escaping @MainActor (CaptureOverviewState.CheckID) -> Void,
      review: @escaping @MainActor () -> Void
    ) {
      self.openFloor = openFloor
      self.addFloor = addFloor
      self.openCheck = openCheck
      self.review = review
    }

    /// Does nothing (previews and snapshots).
    public static let none = CaptureOverviewActions(
      openFloor: { _ in }, addFloor: {}, openCheck: { _ in }, review: {})
  }

  /// The home of one capture (phone-capture §3.5, artboard 2b-4): its floors and areas, the
  /// "Before you leave" state and the way to the package. Pushed on the app's NavigationStack
  /// from the Captures home; the screen only draws `state` and calls `actions`.
  public struct CaptureOverviewScreen: View {
    let state: CaptureOverviewState
    let actions: CaptureOverviewActions

    public init(state: CaptureOverviewState, actions: CaptureOverviewActions) {
      self.state = state
      self.actions = actions
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.contentTopOverview) {
          ScreenSubtitle(state.subtitle)
          VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapOverview) {
            floors
            ChapterSection(header: "Before you leave", footer: CaptureOverviewState.footer) {
              ForEach(state.checks) { check in
                NavigationRow(
                  title: check.title, subtitle: check.subtitle, status: check.status.rowStatus,
                  density: .compact
                ) {
                  actions.openCheck(check.id)
                }
                .accessibilityIdentifier(check.id.accessibilityIdentifier)
              }
            }
          }
        }
        .captureContent(top: ChapterTheme.Metric.subtitleTop)
      }
      .navigationTitle(state.title)
      .navigationBarTitleDisplayMode(.large)
      .chapterNavigationCaption(state.dealCaption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        Button(state.button.title) { actions.review() }
          .buttonStyle(.chapter(.primary))
          .disabled(!state.button.isEnabled)
          .accessibilityIdentifier("overview.review")
      }
    }

    private var floors: some View {
      ChapterSection(header: "Floors and areas") {
        ForEach(state.floors) { floor in
          NavigationRow(
            title: floor.title, subtitle: floor.subtitle, status: floor.status?.rowStatus,
            density: .compact
          ) {
            actions.openFloor(floor.id)
          }
          .accessibilityIdentifier("overview.floor.\(floor.id)")
        }
        if state.canAddFloor {
          AddRow(title: "Scan another floor or room") { actions.addFloor() }
            .accessibilityIdentifier("overview.addFloor")
        }
      }
    }
  }
#endif
