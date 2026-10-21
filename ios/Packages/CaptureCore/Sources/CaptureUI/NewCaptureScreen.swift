#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import ChapterUI
  import SwiftUI

  /// Step 1 of 3, New capture (phone-capture §3.2, artboards 2b-1, 1b, 1c): the HUB project, the
  /// address confirmation and what is recorded automatically. Pushed on the app's
  /// NavigationStack; Continue moves the model to step 2 (`model.step`), which the host pushes.
  ///
  /// `onDiscard` is "Call the PM" in the address-different alert: the draft is discarded and the
  /// host goes back to the Captures home (nothing was saved). When the HUB gives the PM's phone,
  /// the call is placed first.
  public struct NewCaptureScreen: View {
    @Bindable var model: CaptureFlowModel
    let onDiscard: @MainActor () -> Void
    @State private var showsProjects = false
    @State private var showsAddressAlert: Bool
    @Environment(\.openURL) private var openURL

    /// `showsAddressAlert` opens the screen with the alert up (snapshots of artboard 1c).
    public init(
      model: CaptureFlowModel, showsAddressAlert: Bool = false,
      onDiscard: @escaping @MainActor () -> Void = {}
    ) {
      self.model = model
      self.onDiscard = onDiscard
      self._showsAddressAlert = State(initialValue: showsAddressAlert)
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGap) {
          banners
          projectSection
          addressSection
          ChapterSection(header: "Recorded automatically") {
            ValueRow(label: "Operator", value: model.draft.operatorName)
            ValueRow(label: "Device", value: model.deviceText)
            ValueRow(label: "App", value: model.appText)
          }
        }
        .captureContent(top: ChapterTheme.Metric.contentTop)
      }
      .navigationTitle("New capture")
      .navigationBarTitleDisplayMode(.large)
      .chapterNavigationCaption("Step 1 of 3")
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        Button(model.continueTitle) { model.continueToSetup() }
          .buttonStyle(.chapter(.primary))
          .disabled(!model.canContinueToSetup)
          .accessibilityIdentifier("capture.continue")
      }
      .sheet(isPresented: $showsProjects) {
        HubProjectSheet(model: model)
      }
      .alert("Address is different on site?", isPresented: $showsAddressAlert) {
        Button("Go back", role: .cancel) {}
        Button("Call the PM") {
          if let url = model.draft.project?.projectManagerCallURL { openURL(url) }
          onDiscard()
        }
        .keyboardShortcut(.defaultAction)
      } message: {
        Text(
          "Do not scan under this project. Call the PM to fix the HUB record, then start the "
            + "capture again. Nothing is saved.")
      }
      .task {
        if model.listing == nil, !model.isLoadingProjects, !model.isOfflineWithoutList {
          await model.loadProjects()
        }
      }
    }

    // MARK: Parts

    @ViewBuilder
    private var banners: some View {
      if let message = model.gate.message {
        Banner(icon: .blocked, text: message)
      }
      if let offline = model.offlineBanner {
        Banner(icon: .offline, text: offline)
      }
      if let error = model.projectsError {
        Banner(icon: .blocked, text: error) {
          // A row-action button, filled surface: the usual nude fill would vanish on the banner.
          Button { Task { await model.loadProjects() } } label: {
            Text("Try again")
              .chapterTextStyle(.subhead)
              .foregroundStyle(ChapterTheme.Color.ink)
              .padding(.horizontal, ChapterTheme.Metric.rowActionPadding)
              .frame(minHeight: ChapterTheme.Metric.rowActionHeight)
              .background(
                ChapterTheme.Color.surface,
                in: RoundedRectangle(cornerRadius: ChapterTheme.Metric.rowActionRadius))
              .fixedSize()
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("capture.retryProjects")
        }
      }
    }

    private var projectSection: some View {
      let project = model.draft.project
      return ChapterSection(
        header: "HUB project",
        footer: model.isOffline
          ? "A project not in this list cannot be started offline: the deal id must come from the HUB."
          : nil
      ) {
        NavigationRow(
          title: model.projectRowTitle, subtitle: model.projectRowSubtitle,
          detail: project == nil ? "Choose" : "Change", isPlaceholder: project == nil
        ) {
          showsProjects = true
        }
        .disabled(model.isOfflineWithoutList && project == nil)
        .accessibilityIdentifier("capture.project")
      }
    }

    private var addressSection: some View {
      let project = model.draft.project
      return ChapterSection(
        header: "Address in the HUB",
        footer:
          "If the address on site is different, stop and call the PM. The station blocks "
          + "packages with a different address."
      ) {
        ProminentTextRow(project?.address ?? "Choose a HUB project first", isPlaceholder: project == nil)
        ToggleRow(
          "I am at this address",
          isOn: Binding(
            get: { model.draft.isAddressConfirmed },
            set: { isOn in
              if model.addressToggleChanged(isOn: isOn) { showsAddressAlert = true }
            })
        )
        .disabled(project == nil)
        .accessibilityIdentifier("capture.addressConfirmed")
      }
    }
  }

  /// The HUB project sheet: one row per project (title and address); a tap chooses it.
  struct HubProjectSheet: View {
    @Bindable var model: CaptureFlowModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      VStack(spacing: 0) {
        SheetBar(title: "HUB project", onCancel: { dismiss() })
        ScrollView {
          Group {
            if model.isLoadingProjects {
              ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else if model.projects.isEmpty {
              ChapterSection {
                ProminentTextRow(model.projectsError ?? "No HUB projects.", isPlaceholder: true)
              }
            } else {
              ChapterSection {
                ForEach(model.projects) { project in
                  NavigationRow(title: project.title, subtitle: project.address) {
                    model.choose(project)
                    dismiss()
                  }
                }
              }
            }
          }
          .captureContent(top: ChapterTheme.Metric.sectionHeaderGap)
        }
      }
      .chapterScreenBackground()
      .chapterSheet()
      .task { if model.projects.isEmpty, !model.isLoadingProjects { await model.loadProjects() } }
    }
  }
#endif
