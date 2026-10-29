#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import FieldRules
  import SketchEntry
  import SketchSolver
  import SwiftUI

  /// Step 4 of 4, Check (spec F14 2.4): the colour Floorplan drawn live from the solver, the
  /// "Complete" / "Limited" status, what the solver derived, estimated or assumed (and any
  /// closure residual), and what the required set still lacks. "Finish floor" hands the floor
  /// to the host (`onFinish`), which writes the originals and goes on to the photos.
  public struct SketchCheckScreen: View {
    @Bindable var model: SketchEntryModel
    let caption: String
    let onFinish: @MainActor () -> Void

    public init(
      model: SketchEntryModel, caption: String = "Step 4 of 4",
      onFinish: @escaping @MainActor () -> Void
    ) {
      self.model = model
      self.caption = caption
      self.onFinish = onFinish
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
          if let error = model.solveError {
            Banner(icon: .blocked, text: error)
              .accessibilityIdentifier("sketch.solveError")
          }
          plan
          status
          notes
          missing
        }
        .sketchContent()
      }
      .navigationTitle("Check")
      .navigationBarTitleDisplayMode(.large)
      .sketchNavigationCaption(caption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        Button(model.isFinishing ? "Finishing\u{2026}" : "Finish floor") { onFinish() }
          .buttonStyle(.chapter(.primary))
          .disabled(!model.canFinish)
          .accessibilityIdentifier("sketch.finish")
      }
      .task(id: model.measurements) { model.solve() }
    }

    // MARK: Parts

    @ViewBuilder
    private var plan: some View {
      Group {
        if let result = model.result {
          SketchPlanCanvas(model: result.model)
        } else {
          Text(model.solveError == nil ? "Solving\u{2026}" : "No plan")
            .chapterTextStyle(.footnote)
            .foregroundStyle(ChapterTheme.Color.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(height: 260)
      .frame(maxWidth: .infinity)
      .background(ChapterTheme.Color.surface)
      .clipShape(RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius))
      .overlay(
        RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
          .strokeBorder(ChapterTheme.Color.line, lineWidth: ChapterTheme.Metric.cardBorder))
    }

    private var status: some View {
      let result = model.result
      let kind: StatusKind = result == nil ? .missing : (result!.isLimited ? .partly : .done)
      return ChapterSection(header: "Measurements") {
        HStack(spacing: ChapterTheme.Metric.rowGap) {
          VStack(alignment: .leading, spacing: ChapterTheme.Metric.rowTitleGap) {
            Text(result.map(summaryTitle) ?? "Not solved")
              .chapterTextStyle(.body)
              .foregroundStyle(ChapterTheme.Color.ink)
            if let result {
              Text(summarySubtitle(result))
                .chapterTextStyle(.footnote)
                .foregroundStyle(ChapterTheme.Color.muted)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          StatusLabel(kind: kind, word: model.completenessWord)
        }
        .padding(.horizontal, ChapterTheme.Metric.rowPadding)
        .padding(.vertical, ChapterTheme.Metric.navigationRowVerticalPadding)
        .frame(minHeight: ChapterTheme.Metric.navigationRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sketch.status")
      }
    }

    /// "4 walls measured · 2 derived", from the summary.
    private func summaryTitle(_ result: SketchSolveResult) -> String {
      let summary = result.summary
      var parts = [SketchText.plural(summary.wallsMeasured, "wall measured", "walls measured")]
      if summary.wallsEstimated > 0 {
        parts.append("\(summary.wallsEstimated) estimated")
      }
      return parts.joined(separator: " \u{00B7} ")
    }

    private func summarySubtitle(_ result: SketchSolveResult) -> String {
      var parts: [String] = []
      parts.append(
        result.summary.ceilingHeightSource == .measured ? "ceiling measured" : "ceiling assumed")
      if let residual = result.summary.closureResidualMm {
        parts.append("closes within \(LengthFormatter.millimetres(residual))")
      }
      let model = result.model
      parts.append(
        "\(SketchText.plural(model.rooms.count, "room", "rooms")), "
          + "\(model.doors.count + model.windows.count + model.openings.count) openings")
      return parts.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private var notes: some View {
      if let result = model.result {
        ChapterSection(
          header: "Notes",
          footer: result.notes.isEmpty
            ? "Every wall and opening was measured; nothing was estimated."
            : "Estimated values carry low confidence in the capture model; the station names them."
        ) {
          if result.notes.isEmpty {
            ProminentTextRow("Nothing derived, estimated or assumed.", isPlaceholder: true)
          }
          ForEach(Array(result.notes.enumerated()), id: \.offset) { index, note in
            HStack(alignment: .top, spacing: ChapterTheme.Metric.statusGlyphGap) {
              StatusGlyph(Self.kind(of: note), size: ChapterTheme.Metric.statusGlyph)
                .padding(.top, 5)
              Text(note.message)
                .chapterTextStyle(.subhead)
                .foregroundStyle(ChapterTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, ChapterTheme.Metric.rowPadding)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sketch.note.\(index)")
          }
        }
      }
    }

    /// Derived from closure and a passing residual are ●; an estimate, an assumption and a
    /// residual over the tolerance are ▲; a refused closure is ■.
    static func kind(of note: SketchSolveNote) -> StatusKind {
      switch note.kind {
      case .wallDerivedFromClosure: return .done
      case .wallEstimated, .cornerAssumedSquare, .ceilingAssumed, .openingEstimated: return .partly
      case .closureResidual(_, _, _, let grade):
        switch grade {
        case .pass: return .done
        case .limitation: return .partly
        case .refused: return .missing
        }
      }
    }

    @ViewBuilder
    private var missing: some View {
      let items = model.missingRequired
      if !items.isEmpty {
        ChapterSection(
          header: "Still to measure",
          footer: "The floor can be finished without them; the model is then limited."
        ) {
          ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            HStack(alignment: .top, spacing: ChapterTheme.Metric.statusGlyphGap) {
              StatusGlyph(.partly, size: ChapterTheme.Metric.statusGlyph).padding(.top, 5)
              Text(item)
                .chapterTextStyle(.subhead)
                .foregroundStyle(ChapterTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, ChapterTheme.Metric.rowPadding)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sketch.missing.\(index)")
          }
        }
      }
    }
  }
#endif
