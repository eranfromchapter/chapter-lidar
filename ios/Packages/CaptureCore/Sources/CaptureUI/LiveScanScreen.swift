#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import SwiftUI

  private typealias Palette = ChapterTokens.Palette
  private typealias Space = ChapterTokens.Space
  private typealias Radius = ChapterTokens.Radius
  private typealias Control = ChapterTokens.Control
  private typealias Typo = ChapterTokens.Typography

  /// Step 3 of 3: live scan with counts and Pause / Finish floor
  /// (docs/waves/design/snapshot.html#screen-capture, panel 3). `preview` is the live camera and
  /// RoomPlan view; the design draws it as a placeholder inside the panel.
  struct LiveScanScreen<Preview: View>: View {
    @Bindable var model: CaptureFlowModel
    @ViewBuilder var preview: () -> Preview

    var body: some View {
      VStack(spacing: Space.s4) {
        HStack {
          Text(model.scanTitle).font(Typo.sans(15)).foregroundStyle(Palette.surface)
          Spacer()
          Text(model.elapsedText).font(Typo.mono(15)).foregroundStyle(Palette.surface)
            .accessibilityLabel("Elapsed \(model.elapsedText)")
        }

        ZStack {
          preview()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sheet))
          VStack {
            guidanceCard(model.guidance)
            Spacer()
            HStack(spacing: Space.s2) {
              count(model.progress.counts.walls, "walls")
              count(model.progress.counts.doors, "doors")
              count(model.progress.counts.windows, "windows")
              count(model.progress.counts.rooms, "rooms")
            }
          }
          .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.scanPanel, in: RoundedRectangle(cornerRadius: Radius.sheet))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet).stroke(Palette.scanPanelBorder, lineWidth: 1))

        HStack(spacing: Space.s2) {
          Circle().fill(Palette.surface).frame(width: 10, height: 10)
          Text("LiDAR depth and mesh recording · originals saved on this phone")
            .font(Typo.caption).foregroundStyle(Palette.scanCaption)
          Spacer(minLength: 0)
        }

        if let message = model.errorMessage {
          Text("■ \(message)").font(Typo.caption).foregroundStyle(Palette.surface)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if model.scanFailed {
          failedActions
        } else {
          scanActions
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, Space.s2)
      .padding(.bottom, Space.s4)
      // Haptics, so the operator feels the scan working without watching the screen: a soft pulse
      // while scanning normally, a tap for each new wall, door, window or object, a warning when
      // RoomPlan needs something, and a click on Pause / Resume.
      .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.35), trigger: pulse)
      .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: foundCount) { old, new in
        new > old
      }
      .sensoryFeedback(.warning, trigger: model.instruction) { _, new in new != .normal }
      .sensoryFeedback(.error, trigger: model.scanFailed) { _, new in new }
      .sensoryFeedback(.selection, trigger: model.isPaused)
      .task(id: model.isPaused) {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(1.2))
          if model.sessionState == .running, !model.isPaused, model.instruction == .normal {
            pulse &+= 1
          }
        }
      }
    }

    /// After RoomPlan stopped on its own: start again, or go back to the scan setup.
    private var failedActions: some View {
      HStack(spacing: Space.s3) {
        Button {
          Task { await model.cancelScan() }
        } label: {
          Text("Back")
            .font(Typo.body).foregroundStyle(Palette.surface)
            .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.surface, lineWidth: 1))
        }
        .buttonStyle(.plain)
        Button {
          Task { await model.retryScan() }
        } label: {
          Text("Try again")
            .font(Typo.headline).foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("scan.tryAgain")
      }
    }

    private var scanActions: some View {
      HStack(spacing: Space.s3) {
        Button {
          Task { await model.togglePause() }
        } label: {
          Text(model.isPaused ? "Resume" : "Pause")
            .font(Typo.body).foregroundStyle(Palette.surface)
            .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
            .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.surface, lineWidth: 1))
        }
        .buttonStyle(.plain)
        Button {
          Task { await model.finishFloor() }
        } label: {
          Text("Finish floor")
            .font(Typo.headline).foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
      }
    }

    /// Heartbeat counter for the soft scanning pulse.
    @State private var pulse = 0

    /// Everything RoomPlan has found so far; a rise gives a tap.
    private var foundCount: Int {
      let counts = model.progress.counts
      return counts.walls + counts.doors + counts.windows + counts.openings + counts.objects
    }

    /// Direction for the operator: the step of the scan, what to do, and RoomPlan's warnings.
    private func guidanceCard(_ guidance: ScanGuidance) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        if let step = guidance.step {
          Text("Step \(step) of \(ScanGuidance.stepCount)")
            .font(Typo.sans(12, weight: .semibold)).foregroundStyle(Palette.muted)
        }
        Text(guidance.title)
          .font(Typo.sans(17, weight: .semibold))
          .foregroundStyle(guidance.isWarning ? Palette.blocked : Palette.ink)
        Text(guidance.detail)
          .font(Typo.sans(14)).foregroundStyle(Palette.ink)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
      .background(Palette.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: Radius.card))
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("scan.guidance")
      .animation(.easeInOut(duration: 0.2), value: guidance)
    }

    private func count(_ value: Int, _ label: String) -> some View {
      VStack(spacing: 2) {
        Text("\(value)").font(Typo.sans(22, weight: .semibold)).foregroundStyle(Palette.surface)
        Text(label).font(Typo.sans(12)).foregroundStyle(Palette.scanCaption)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .combine)
    }
  }
#endif
