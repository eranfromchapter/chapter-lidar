#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import ChapterUI
  import SwiftUI

  /// Step 3 of 3, the live scan (phone-capture §3.4, artboards 2b-3 and 2b-3b, compass §5.2):
  /// the title and timer pills, the camera well with the coaching pill and the counts, the
  /// compass chip and the recording line, then Pause / Finish floor. Its states: tracking lost
  /// (the dimmed well, "Paused · mm:ss", the card with "Restart this floor instead"), paused by
  /// the operator, and scan stopped (Back / Try again).
  ///
  /// The host presents it as a `fullScreenCover` while `model.step == .scanning`, with no
  /// navigation bar and a light status bar. `preview` is the camera feed
  /// (`CaptureSessionPreview(model:)` from CaptureRoomPlan), clipped to the well; without one
  /// (replay, UI tests) the well stays plain.
  public struct LiveScanScreen<Preview: View>: View {
    @Bindable var model: CaptureFlowModel
    let preview: () -> Preview
    @State private var showsRestart = false
    /// Heartbeat counter for the soft scanning pulse.
    @State private var pulse = 0

    public init(model: CaptureFlowModel, @ViewBuilder preview: @escaping () -> Preview) {
      self.model = model
      self.preview = preview
    }

    public var body: some View {
      VStack(spacing: 0) {
        topRow
        well
          .padding(.top, 12)
          .padding(.horizontal, ChapterTheme.Metric.screenPadding)
        statusRow
          .padding(.top, 12)
          .padding(.horizontal, ChapterTheme.Metric.screenPadding)
        actions
          .padding(.top, 12)
          .padding(.horizontal, ChapterTheme.Metric.screenPadding)
          .padding(.bottom, ChapterTheme.Metric.actionBarBottom)
      }
      .chapterContentWidth()
      .background(ChapterTheme.Color.ink.ignoresSafeArea())
      .preferredColorScheme(.dark)
      .alert(restartTitle, isPresented: $showsRestart) {
        Button("Cancel", role: .cancel) {}
        Button("Restart", role: .destructive) { Task { await model.restartFloor() } }
      } message: {
        Text(restartMessage)
      }
      // Haptics, so the operator feels the scan working without watching the screen: a soft
      // pulse while scanning normally, a tap for each new wall, door, window or object, a warning
      // when RoomPlan needs something or tracking is lost, a success tap when it is back, and a
      // click on Pause / Resume.
      .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.35), trigger: pulse)
      .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: foundCount) { old, new in
        new > old
      }
      .sensoryFeedback(.warning, trigger: model.instruction) { _, new in new != .normal }
      .sensoryFeedback(.warning, trigger: model.tracking.isLost) { _, new in new }
      .sensoryFeedback(.success, trigger: model.tracking.isLost) { old, new in old && !new }
      .sensoryFeedback(.error, trigger: model.scanFailed) { _, new in new }
      .sensoryFeedback(.selection, trigger: model.isPaused)
      .task(id: model.isPaused) {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(1.2))
          if model.livePhase == .scanning, model.sessionState == .running,
            model.instruction == .normal
          {
            pulse &+= 1
          }
        }
      }
    }

    // MARK: Parts

    private var topRow: some View {
      HStack {
        Text(model.scanTitle)
          .chapterTextStyle(.subheadEmphasis)
          .lineLimit(1)
          .modifier(ScanPill())
          .accessibilityIdentifier("scan.title")
        Spacer(minLength: 12)
        Text(model.elapsedText)
          .font(ChapterTheme.Font.mono)
          .modifier(ScanPill())
          .accessibilityLabel(Text(CaptureText.spokenElapsed(model.progress.elapsed)))
          .accessibilityIdentifier("scan.elapsed")
      }
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .frame(minHeight: 44)
    }

    private var isDimmed: Bool {
      switch model.livePhase {
      case .trackingLost, .stopped: true
      case .scanning, .paused: false
      }
    }

    private var well: some View {
      let shape = RoundedRectangle(cornerRadius: 16)
      return ZStack {
        (model.livePhase == .trackingLost ? ChapterTheme.Color.scanWellDimmed : ChapterTheme.Color.scanWell)
        preview()
        VStack(spacing: 0) {
          topPill
            .frame(maxWidth: .infinity, alignment: .leading)
          Spacer(minLength: 12)
          card
          Spacer(minLength: 12)
          counts
        }
        .padding(14)
      }
      .clipShape(shape)
      .overlay(shape.strokeBorder(ChapterTheme.Color.scanWellBorder, lineWidth: 1))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var topPill: some View {
      switch model.livePhase {
      case .scanning:
        let guidance = model.guidance
        CoachingPill(
          style: .coaching, title: guidance.title, detail: guidance.detail,
          isWarning: guidance.isWarning
        )
        .accessibilityIdentifier("scan.guidance")
      case .paused:
        TimelineView(.periodic(from: .now, by: 1)) { _ in
          CoachingPill(
            style: .paused, title: model.pausedText(now: model.now()) ?? "Paused",
            detail: model.guidance.detail)
        }
        .accessibilityIdentifier("scan.guidance")
      case .trackingLost:
        TimelineView(.periodic(from: .now, by: 1)) { _ in
          CoachingPill(style: .paused, title: model.pausedText(now: model.now()) ?? "Paused", detail: nil)
        }
        .accessibilityIdentifier("scan.guidance")
      case .stopped:
        EmptyView()
      }
    }

    @ViewBuilder
    private var card: some View {
      switch model.livePhase {
      case .trackingLost:
        ScanCard(
          glyph: .partly, title: "Tracking lost",
          message:
            "Point the camera at a wall you already scanned and hold still. Scanning continues "
            + "on its own. Nothing is lost.",
          actionTitle: "Restart this floor instead", actionIdentifier: "scan.restartFloor"
        ) {
          showsRestart = true
        }
        .accessibilityIdentifier("scan.trackingLost")
      case .stopped(let message):
        ScanCard(glyph: .missing, title: "Scan stopped", message: message)
          .accessibilityIdentifier("scan.stopped")
      case .scanning, .paused:
        EmptyView()
      }
    }

    private var counts: some View {
      let counts = model.progress.counts
      return HStack(spacing: 8) {
        count(counts.walls, "walls")
        count(counts.doors, "doors")
        count(counts.windows, "windows")
        count(counts.rooms, "rooms")
      }
      .opacity(isDimmed ? 0.5 : 1)
    }

    private func count(_ value: Int, _ label: String) -> some View {
      VStack(spacing: 2) {
        Text("\(value)")
          .chapterTextStyle(.count)
          .foregroundStyle(ChapterTheme.Color.surface)
        Text(label)
          .chapterTextStyle(.caption)
          .foregroundStyle(ChapterTheme.Color.onDarkCaption)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text("\(value) \(label)"))
    }

    private var statusRow: some View {
      let status = model.recordingStatus
      return HStack(spacing: 10) {
        CompassChip(state: model.liveCompass)
        HStack(spacing: 8) {
          Circle()
            .fill(dotColor(status.dot))
            .frame(width: 8, height: 8)
          Text(status.text)
            .chapterTextStyle(.footnote)
            .foregroundStyle(ChapterTheme.Color.onDarkCaption)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scan.status")
      }
    }

    private func dotColor(_ kind: RowStatusValue.Kind?) -> Color {
      switch kind {
      case .partly: ChapterTheme.Color.limited
      case .missing: ChapterTheme.Color.blocked
      default: ChapterTheme.Color.surface
      }
    }

    @ViewBuilder
    private var actions: some View {
      HStack(spacing: 12) {
        if case .stopped = model.livePhase {
          Button("Back") { Task { await model.cancelScan() } }
            .buttonStyle(.chapter(.outlineOnDark))
            .accessibilityIdentifier("scan.back")
          Button("Try again") { Task { await model.retryScan() } }
            .buttonStyle(.chapter(.filledOnDark))
            .accessibilityIdentifier("scan.tryAgain")
        } else {
          Button(model.isPaused ? "Resume" : "Pause") { Task { await model.togglePause() } }
            .buttonStyle(.chapter(.outlineOnDark))
            .disabled(!model.canTogglePause)
            .accessibilityIdentifier("scan.pause")
          Button {
            Task { await model.finishFloor() }
          } label: {
            if model.isFinishing {
              ProgressView().tint(ChapterTheme.Color.ink)
            } else {
              Text("Finish floor")
            }
          }
          .buttonStyle(.chapter(.filledOnDark))
          .disabled(!model.canFinishFloor)
          // Tracking lost: finishing keeps what was scanned, so the button stays enabled, drawn
          // at half strength as in the artboard.
          .opacity(model.livePhase == .trackingLost && model.canFinishFloor ? 0.5 : 1)
          .accessibilityLabel(Text("Finish floor"))
          .accessibilityIdentifier("scan.finish")
        }
      }
    }

    /// Everything RoomPlan has found so far; a rise gives a tap.
    private var foundCount: Int {
      let counts = model.progress.counts
      return counts.walls + counts.doors + counts.windows + counts.openings + counts.objects
    }

    private var floorName: String {
      model.draft.floorLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var restartTitle: String { "Restart \(floorName)?" }

    private var restartMessage: String {
      let walls = model.progress.counts.walls
      let scanned = walls == 1 ? "The 1 wall scanned so far is" : "The \(walls) walls scanned so far are"
      return "\(scanned) discarded. The compass is read again."
    }
  }

  /// The title and timer pills: height 36, padding 0 × 14, radius 18, surface at 14 %.
  private struct ScanPill: ViewModifier {
    func body(content: Content) -> some View {
      content
        .foregroundStyle(ChapterTheme.Color.surface)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(ChapterTheme.Color.onDarkPill, in: Capsule())
    }
  }
#endif
