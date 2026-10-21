#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import CaptureCore
  import ChapterUI
  import SwiftUI

  /// The compass row of "What are you scanning?" (compass §5.1, phone-capture §3.3.1 host layout):
  /// the 32 pt glyph, the reading over its status, and Read again. Min height 56, padding
  /// 8 × 16, gap 12. Every word comes from `CompassPhoneText`; `{AGO}` is refreshed every second.
  /// There is no field: a heading is never typed.
  struct CompassRow: View {
    let state: CompassPrecheckState
    let now: () -> Date
    let onReadAgain: () -> Void
    /// The status glyph grows with the text (10 pt at the default size) and is centred on the
    /// first line of the status (17 pt line).
    @ScaledMetric(relativeTo: .footnote) private var glyphSize = ChapterTheme.Metric.statusGlyph
    @ScaledMetric(relativeTo: .footnote) private var glyphTop: CGFloat = 3.5

    var body: some View {
      TimelineView(.periodic(from: .now, by: 1)) { _ in
        let row = CompassPhoneText.row(state, now: now())
        HStack(spacing: ChapterTheme.Metric.rowGap) {
          HStack(spacing: ChapterTheme.Metric.rowGap) {
            CompassGlyph(state: row.glyph.glyphState, rotation: row.rotation)
            VStack(alignment: .leading, spacing: ChapterTheme.Metric.rowTitleGap) {
              Text(row.line1)
                .chapterTextStyle(.body)
                .foregroundStyle(ChapterTheme.Color.ink)
              HStack(alignment: .top, spacing: ChapterTheme.Metric.statusGlyphGap) {
                switch row.status {
                case .verified: StatusGlyph(.done, size: glyphSize).padding(.top, glyphTop)
                case .limited: StatusGlyph(.partly, size: glyphSize).padding(.top, glyphTop)
                case .none: EmptyView()
                }
                Text(row.line2)
                  .chapterTextStyle(.footnote)
                  .foregroundStyle(color(row.status))
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Text(row.accessibilityLabel))
          .accessibilityIdentifier("compass.row")
          if row.showsReadAgain {
            Button(CompassPhoneText.readAgain, action: onReadAgain)
              .buttonStyle(.chapter(.rowAction))
              .disabled(!row.readAgainEnabled)
              .fixedSize()
              .accessibilityIdentifier("compass.readAgain")
          }
        }
        .padding(.horizontal, ChapterTheme.Metric.rowPadding)
        .padding(.vertical, ChapterTheme.Metric.navigationRowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: ChapterTheme.Metric.compassRowHeight)
      }
    }

    private func color(_ status: CompassPhoneText.Status) -> Color {
      switch status {
      case .verified: ChapterTheme.Color.ready
      case .limited: ChapterTheme.Color.limitedText
      case .none: ChapterTheme.Color.muted
      }
    }
  }

  /// The footnotes under the compass card: the advice, and while Location is off the note in
  /// limited text with "Open Settings" (compass §5.1).
  struct CompassFootnotes: View {
    let isLocationOff: Bool
    let onOpenSettings: () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: ChapterTheme.Metric.sectionHeaderGap) {
        SectionFooter(CompassPhoneText.footnote)
        if isLocationOff {
          Text(CompassPhoneText.locationOffNote)
            .chapterTextStyle(.footnote)
            .foregroundStyle(ChapterTheme.Color.limitedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ChapterTheme.Metric.sectionInset)
          Button(action: onOpenSettings) {
            Text(CompassPhoneText.openSettings)
              .chapterTextStyle(.subhead)
              .foregroundStyle(ChapterTheme.Color.ink)
              .padding(.horizontal, ChapterTheme.Metric.sectionInset)
              .frame(minHeight: ChapterTheme.Metric.touchTarget)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("compass.openSettings")
        }
      }
    }
  }

  /// The live scan's compass chip (compass §5.2, phone-capture §3.4 host layout): height 32,
  /// padding 0 × 10, radius 16, the 14 pt arrow and the text in footnote surface. The arrow turns
  /// with the camera (up on the chip is where the camera looks) and keeps its last angle while
  /// the camera points steeply up or down. Not a button.
  struct CompassChip: View {
    let state: CompassLiveState
    @State private var lastRotation: Double = 0

    var body: some View {
      let chip = CompassPhoneText.chip(state)
      HStack(spacing: 6) {
        if chip.glyph != .none {
          CompassPillGlyph(state: chip.glyph.glyphState, rotation: chip.rotation ?? lastRotation)
        }
        Text(chip.text)
          .chapterTextStyle(.footnote)
          .foregroundStyle(ChapterTheme.Color.surface)
          .lineLimit(1)
      }
      .padding(.horizontal, 10)
      .frame(minHeight: 32)
      .background(ChapterTheme.Color.onDarkPill, in: Capsule())
      .fixedSize()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(chip.accessibilityLabel))
      .accessibilityIdentifier("scan.compass")
      .onChange(of: chip.rotation) { _, rotation in
        if let rotation { lastRotation = rotation }
      }
    }
  }
#endif
