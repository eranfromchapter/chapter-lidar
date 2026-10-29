#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import FieldRules
  import MeshExport
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
      SketchCheckView(
        result: model.result, solveError: model.solveError, missing: model.missingRequired,
        completenessWord: model.completenessWord, caption: caption,
        isFinishing: model.isFinishing, canFinish: model.canFinish, onFinish: onFinish
      )
      .task(id: model.measurements) { model.solve() }
    }
  }

  /// The Check screen of a capture without LiDAR (spec F14 2.4, F15 2): the plan drawn from the
  /// solver's model, the status, the notes (`leadingNotes` first: an AR walkthrough's
  /// converter notes and scale, then the solver's), what is still to measure, and Finish floor.
  /// The sketch flow and the walkthrough show the same screen with the same identifiers
  /// (`sketch.plan`, `sketch.status`, `sketch.note.N`, `sketch.finish`). A sketch photo read by
  /// Claude (spec F16) puts the 3D preview (`mesh3D`, `sketchPhoto.model3D`) on top, the plan
  /// under it.
  public struct SketchCheckView: View {
    let result: SketchSolveResult?
    let mesh3D: TriangleMesh?
    let solveError: String?
    let leadingNotes: [String]
    let missing: [String]
    let completenessWord: String
    let caption: String
    let isFinishing: Bool
    let canFinish: Bool
    let onFinish: @MainActor () -> Void

    public init(
      result: SketchSolveResult?, solveError: String?, leadingNotes: [String] = [],
      missing: [String] = [], completenessWord: String, caption: String, isFinishing: Bool,
      canFinish: Bool, mesh3D: TriangleMesh? = nil, onFinish: @escaping @MainActor () -> Void
    ) {
      self.result = result
      self.mesh3D = mesh3D
      self.solveError = solveError
      self.leadingNotes = leadingNotes
      self.missing = missing
      self.completenessWord = completenessWord
      self.caption = caption
      self.isFinishing = isFinishing
      self.canFinish = canFinish
      self.onFinish = onFinish
    }

    public var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionGapCompact) {
          if let error = solveError {
            Banner(icon: .blocked, text: error)
              .accessibilityIdentifier("sketch.solveError")
          }
          if let mesh3D {
            SketchModel3DCard(
              mesh: mesh3D,
              accessibilityText: "3D model: \(SketchText.plural(result?.model.rooms.count ?? 0, "room", "rooms"))")
          }
          plan
          status
          notes
          missingSection
        }
        .sketchContent()
      }
      .navigationTitle("Check")
      .navigationBarTitleDisplayMode(.large)
      .sketchNavigationCaption(caption)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .chapterActionBar {
        Button(isFinishing ? "Finishing\u{2026}" : "Finish floor") { onFinish() }
          .buttonStyle(.chapter(.primary))
          .disabled(!canFinish)
          .accessibilityIdentifier("sketch.finish")
      }
    }

    // MARK: Parts

    @ViewBuilder
    private var plan: some View {
      Group {
        if let result {
          SketchPlanCanvas(model: result.model)
        } else {
          Text(solveError == nil ? "Solving\u{2026}" : "No plan")
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
          StatusLabel(kind: kind, word: completenessWord)
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
      if let result {
        ChapterSection(
          header: "Notes",
          footer: result.notes.isEmpty
            ? "Every wall and opening was measured; nothing was estimated."
            : "Estimated values carry low confidence in the capture model; the station names them."
        ) {
          if result.notes.isEmpty && leadingNotes.isEmpty {
            ProminentTextRow("Nothing derived, estimated or assumed.", isPlaceholder: true)
          }
          ForEach(Array(leadingNotes.enumerated()), id: \.offset) { index, note in
            noteRow(note, kind: .done)
              .accessibilityIdentifier("sketch.leadingNote.\(index)")
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

    private func noteRow(_ text: String, kind: StatusKind) -> some View {
      HStack(alignment: .top, spacing: ChapterTheme.Metric.statusGlyphGap) {
        StatusGlyph(kind, size: ChapterTheme.Metric.statusGlyph)
          .padding(.top, 5)
        Text(text)
          .chapterTextStyle(.subhead)
          .foregroundStyle(ChapterTheme.Color.ink)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, ChapterTheme.Metric.rowPadding)
      .padding(.vertical, 10)
      .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var missingSection: some View {
      let items = missing
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
