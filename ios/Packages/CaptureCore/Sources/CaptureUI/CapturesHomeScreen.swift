#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import ChapterUI
  import SwiftUI

  /// What the Captures home asks its host to do.
  public struct CapturesHomeActions {
    /// "New capture": step 1 of a new visit.
    public var newCapture: @MainActor () -> Void
    /// A row: the Capture overview (in progress) or Verdict received (sealed).
    public var open: @MainActor (CapturesHomeState.Row) -> Void
    /// "Sign out" in the account dialog.
    public var signOut: @MainActor () -> Void
    /// Re-reads the disk and asks the station about packages waiting for a verdict: on appear,
    /// when the app becomes active and on pull to refresh.
    public var refresh: @MainActor () async -> Void

    public init(
      newCapture: @escaping @MainActor () -> Void, open: @escaping @MainActor (CapturesHomeState.Row) -> Void,
      signOut: @escaping @MainActor () -> Void, refresh: @escaping @MainActor () async -> Void = {}
    ) {
      self.newCapture = newCapture
      self.open = open
      self.signOut = signOut
      self.refresh = refresh
    }

    /// Does nothing (previews and snapshots).
    public static let none = CapturesHomeActions(newCapture: {}, open: { _ in }, signOut: {})
  }

  /// The app's home (phone-capture §3.1, artboard 2b-0, critique R-28): every capture on this
  /// phone, in progress and sealed, and "New capture". The root of the app's NavigationStack;
  /// the screen only draws `state` and calls `actions`.
  public struct CapturesHomeScreen: View {
    let state: CapturesHomeState
    let actions: CapturesHomeActions
    @State private var showsAccount = false
    @Environment(\.scenePhase) private var scenePhase

    public init(state: CapturesHomeState, actions: CapturesHomeActions) {
      self.state = state
      self.actions = actions
    }

    public var body: some View {
      ScrollView {
        content.captureContent(top: ChapterTheme.Metric.contentTop)
      }
      .refreshable { await actions.refresh() }
      .navigationTitle("Captures")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        PlainToolbarItem(placement: .topBarLeading) { ChapterLogo() }
        PlainToolbarItem(placement: .topBarTrailing) {
          AvatarButton(name: state.operatorName) { showsAccount = true }
            .accessibilityIdentifier("account.avatar")
        }
      }
      .confirmationDialog(state.accountTitle, isPresented: $showsAccount, titleVisibility: .visible) {
        Button("Sign out") { actions.signOut() }
          .accessibilityIdentifier("account.signOut")
        Button("Cancel", role: .cancel) {}
      } message: {
        if let message = state.accountMessage { Text(message) }
      }
      .chapterScreenBackground()
      .chapterActionBar {
        Button("New capture") { actions.newCapture() }
          .buttonStyle(.chapter(.primary))
          .accessibilityIdentifier("captures.newCapture")
      }
      .task { await actions.refresh() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await actions.refresh() } }
      }
    }

    @ViewBuilder
    private var content: some View {
      if state.isLoading {
        ProgressView()
          .tint(ChapterTheme.Color.muted)
          .frame(maxWidth: .infinity, minHeight: 200)
      } else if state.isEmpty {
        ChapterSection(footer: CapturesHomeState.emptyFootnote) {
          ProminentTextRow(CapturesHomeState.emptyText, isPlaceholder: true)
        }
      } else {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGap) {
          if !state.inProgress.isEmpty {
            ChapterSection(
              header: "In progress",
              footer: state.sealed.isEmpty ? CapturesHomeState.footnote : nil
            ) {
              ForEach(state.inProgress) { row(for: $0) }
            }
          }
          if !state.sealed.isEmpty {
            ChapterSection(header: "Sealed", footer: CapturesHomeState.footnote) {
              ForEach(state.sealed) { row(for: $0) }
            }
          }
        }
      }
    }

    @ViewBuilder
    private func row(for row: CapturesHomeState.Row) -> some View {
      Group {
        if let fraction = row.progress {
          ProgressNavigationRow(title: row.title, subtitle: row.subtitle, fraction: fraction) {
            actions.open(row)
          }
        } else {
          NavigationRow(title: row.title, subtitle: row.subtitle, status: row.status?.rowStatus) {
            actions.open(row)
          }
        }
      }
      .accessibilityIdentifier("captures.row.\(row.id)")
    }
  }
#endif
