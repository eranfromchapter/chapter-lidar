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
    /// "Delete all photos" in the account dialog, after the in-page confirmation: erases every
    /// site photo on the phone and returns the line to show ("Deleted 3 photos"). Only the
    /// field-test and UI-test modes of a Debug build pass it; nil: the dialog has no such button.
    public var deletePhotos: (@MainActor () async -> String)?

    public init(
      newCapture: @escaping @MainActor () -> Void, open: @escaping @MainActor (CapturesHomeState.Row) -> Void,
      signOut: @escaping @MainActor () -> Void, refresh: @escaping @MainActor () async -> Void = {},
      deletePhotos: (@MainActor () async -> String)? = nil
    ) {
      self.newCapture = newCapture
      self.open = open
      self.signOut = signOut
      self.refresh = refresh
      self.deletePhotos = deletePhotos
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
    /// The in-page "Delete all photos?" confirmation is shown.
    @State private var confirmsDeletePhotos = false
    @State private var isDeletingPhotos = false
    /// "Deleted 3 photos" / "No photos to delete", after a deletion.
    @State private var photosMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    public init(state: CapturesHomeState, actions: CapturesHomeActions) {
      self.state = state
      self.actions = actions
    }

    public var body: some View {
      ScrollView {
        if let photosMessage {
          VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGap) {
            Banner(icon: .systemImage("checkmark.circle"), text: photosMessage)
              .accessibilityElement(children: .combine)
              .accessibilityIdentifier("captures.photosMessage")
            content
          }
          .captureContent(top: ChapterTheme.Metric.contentTop)
        } else {
          content.captureContent(top: ChapterTheme.Metric.contentTop)
        }
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
        if actions.deletePhotos != nil {
          Button(DeletePhotosText.button, role: .destructive) {
            photosMessage = nil
            confirmsDeletePhotos = true
          }
          .accessibilityIdentifier("account.deletePhotos")
        }
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
      .overlay {
        if confirmsDeletePhotos {
          DeletePhotosConfirmation(
            isDeleting: isDeletingPhotos, delete: deletePhotos,
            cancel: { confirmsDeletePhotos = false })
        }
      }
      .task { await actions.refresh() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await actions.refresh() } }
      }
    }

    /// "Delete all photos" in the confirmation: erases, then says what was deleted.
    private func deletePhotos() {
      guard let action = actions.deletePhotos, !isDeletingPhotos else { return }
      isDeletingPhotos = true
      Task { @MainActor in
        let message = await action()
        isDeletingPhotos = false
        confirmsDeletePhotos = false
        photosMessage = message
        AccessibilityNotification.Announcement(message).post()
        await actions.refresh()
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

  /// The in-page confirmation of "Delete all photos" over the dimmed Captures home: the
  /// alert-card fill, radius 16, padding 16; the title (bodyEmphasis), the text (subhead), then
  /// "Delete all photos" (`.destructive`) and "Cancel" (`.tinted`) stacked 10 pt apart.
  private struct DeletePhotosConfirmation: View {
    let isDeleting: Bool
    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
      ZStack {
        ChapterTheme.Color.ink.opacity(0.35)
          .ignoresSafeArea()
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 10) {
          Text(DeletePhotosText.title)
            .chapterTextStyle(.bodyEmphasis)
            .foregroundStyle(ChapterTheme.Color.ink)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("deletePhotos.title")
          Text(DeletePhotosText.message)
            .chapterTextStyle(.subhead)
            .foregroundStyle(ChapterTheme.Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("deletePhotos.message")
            .padding(.bottom, 6)
          Button(isDeleting ? DeletePhotosText.deleting : DeletePhotosText.button, action: delete)
            .buttonStyle(.chapter(.destructive))
            .disabled(isDeleting)
            .accessibilityIdentifier("deletePhotos.confirm")
          Button(DeletePhotosText.cancel, action: cancel)
            .buttonStyle(.chapter(.tinted))
            .disabled(isDeleting)
            .accessibilityIdentifier("deletePhotos.cancel")
        }
        .padding(16)
        .frame(maxWidth: 340)
        .background(ChapterTheme.Color.alertCard, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, ChapterTheme.Metric.screenPadding)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("deletePhotos.card")
      }
    }
  }
#endif
