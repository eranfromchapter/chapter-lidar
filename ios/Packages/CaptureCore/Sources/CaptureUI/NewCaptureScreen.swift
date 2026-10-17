#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import SwiftUI

  private typealias Palette = ChapterTokens.Palette
  private typealias Space = ChapterTokens.Space
  private typealias Radius = ChapterTokens.Radius
  private typealias Control = ChapterTokens.Control
  private typealias Typo = ChapterTokens.Typography

  /// Step 1 of 3: HUB project and address confirmation
  /// (docs/waves/design/snapshot.html#screen-capture, panel 1).
  struct NewCaptureScreen: View {
    @Bindable var model: CaptureFlowModel
    @State private var showProjectPicker = false

    var body: some View {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          Wordmark()
          Spacer()
          Text("Step 1 of 3").font(Typo.caption).foregroundStyle(Palette.muted)
        }
        Text("New capture").font(Typo.display).foregroundStyle(Palette.ink)
          .accessibilityAddTraits(.isHeader)

        VStack(alignment: .leading, spacing: Space.s2) {
          FieldLabel("HUB project")
          Button {
            showProjectPicker = true
          } label: {
            HStack {
              Text(projectTitle).font(Typo.body).foregroundStyle(Palette.ink)
              Spacer()
              Text(model.draft.project == nil ? "Choose" : "Change").foregroundStyle(Palette.muted)
            }
            .font(Typo.body)
            .padding(.horizontal, Space.s4)
            .frame(maxWidth: .infinity, minHeight: Control.projectButtonHeight)
            .fieldBackground()
          }
          .buttonStyle(.plain)
          .accessibilityLabel("HUB project")
          .accessibilityValue(projectTitle)
          Text(dealCaption).font(Typo.caption).foregroundStyle(Palette.muted)
        }

        VStack(alignment: .leading, spacing: Space.s2) {
          Text("Address in the HUB").font(Typo.caption).foregroundStyle(Palette.muted)
          Text(model.draft.project?.address ?? "Choose a HUB project first")
            .font(Typo.headline)
            .foregroundStyle(model.draft.project == nil ? Palette.muted : Palette.ink)
          Button {
            model.setAddressConfirmed(!model.draft.isAddressConfirmed)
          } label: {
            HStack(spacing: Space.s3) {
              Image(systemName: model.draft.isAddressConfirmed ? "checkmark.square.fill" : "square")
                .font(.system(size: Control.checkbox))
                .foregroundStyle(Palette.ink)
              Text("I am at this address").font(Typo.body).foregroundStyle(Palette.ink)
              Spacer(minLength: 0)
            }
            .frame(minHeight: Control.minTouch)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(model.draft.project == nil)
          .accessibilityAddTraits(model.draft.isAddressConfirmed ? [.isButton, .isSelected] : .isButton)
          Text(
            "If the address on site is different, stop and call the PM. The station blocks packages with a mismatched address."
          )
          .font(Typo.caption).foregroundStyle(Palette.muted)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fieldBackground()

        HStack(alignment: .top, spacing: Space.s3) {
          VStack(alignment: .leading, spacing: Space.s1) {
            Text("Operator").font(Typo.caption).foregroundStyle(Palette.muted)
            Text(model.draft.operatorName).font(Typo.sans(15)).foregroundStyle(Palette.ink)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          VStack(alignment: .leading, spacing: Space.s1) {
            Text("Device").font(Typo.caption).foregroundStyle(Palette.muted)
            Text(deviceText).font(Typo.sans(15)).foregroundStyle(Palette.ink)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let message = model.gate.message {
          Text("■ \(message)").font(Typo.caption).foregroundStyle(Palette.blocked)
        }
        if let message = model.projectsError {
          Text("■ \(message)").font(Typo.caption).foregroundStyle(Palette.blocked)
        }

        Spacer(minLength: 0)
        PrimaryButton(title: "Continue", isEnabled: model.canContinueToSetup) {
          model.continueToSetup()
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, Space.s2)
      .padding(.bottom, Space.s4)
      .sheet(isPresented: $showProjectPicker) {
        ProjectPickerSheet(model: model)
      }
    }

    private var projectTitle: String {
      guard let project = model.draft.project else { return "Choose a HUB project" }
      return project.projectName.isEmpty ? project.address : project.projectName
    }

    /// "Deal [DEAL ID] · from the HUB, updated 2 min ago".
    private var dealCaption: String {
      guard let project = model.draft.project else { return "Projects come from the HUB" }
      var text = "Deal \(project.dealId) · from the HUB"
      if let updated = project.updatedAt {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        text += ", updated \(formatter.localizedString(for: updated, relativeTo: Date()))"
      }
      return text
    }

    /// "iPhone Pro · LiDAR ✓".
    private var deviceText: String {
      let device = model.draft.device
      return "\(device.marketingName ?? device.model) · LiDAR \(model.hasLidar ? "✓" : "✗")"
    }
  }

  /// The list behind the HUB project button. The HUB data comes from the injected provider.
  struct ProjectPickerSheet: View {
    @Bindable var model: CaptureFlowModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        Group {
          if model.isLoadingProjects {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if model.projects.isEmpty {
            Text(model.projectsError ?? "No HUB projects.")
              .font(Typo.body).foregroundStyle(Palette.muted).padding(Space.s5)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            List(model.projects) { project in
              Button {
                model.choose(project)
                dismiss()
              } label: {
                VStack(alignment: .leading, spacing: Space.s1) {
                  Text(project.projectName.isEmpty ? project.address : project.projectName)
                    .font(Typo.body).foregroundStyle(Palette.ink)
                  Text(project.address).font(Typo.caption).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: Control.primaryHeight - Space.s2, alignment: .leading)
              }
              .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
          }
        }
        .background(Palette.ground)
        .navigationTitle("HUB project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .task { if model.projects.isEmpty { await model.loadProjects() } }
      }
    }
  }
#endif
