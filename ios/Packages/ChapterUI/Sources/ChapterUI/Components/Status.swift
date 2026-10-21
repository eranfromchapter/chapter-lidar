#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  /// The four statuses of the phone. A status always shows a word and a shape, never colour
  /// alone, and the shapes are drawn (Inter has no ●▲■ the design can rely on).
  public enum StatusKind: String, CaseIterable, Sendable {
    /// ● Done / Verified / Recorded / Ready / Confirmed.
    case done
    /// ▲ Partly / Approx. / Limited / Not verified (never blocks).
    case partly
    /// ■ Missing / Open / Blocked / Stopped.
    case missing
    /// ○ Waiting / Checking / Optional.
    case waiting

    public var glyphColor: Color {
      switch self {
      case .done: ChapterTheme.Color.ready
      case .partly: ChapterTheme.Color.limited
      case .missing: ChapterTheme.Color.blocked
      case .waiting: ChapterTheme.Color.muted
      }
    }

    public var textColor: Color {
      switch self {
      case .done: ChapterTheme.Color.ready
      case .partly: ChapterTheme.Color.limitedText
      case .missing: ChapterTheme.Color.blocked
      case .waiting: ChapterTheme.Color.muted
      }
    }

    /// What VoiceOver says for a glyph shown without a word (phone-field §1.3).
    public var accessibilityWord: String {
      switch self {
      case .done: "Done"
      case .partly: "Partly"
      case .missing: "Missing"
      case .waiting: "Optional"
      }
    }
  }

  /// The status shape in a 10-unit view box, drawn `size` points square (10 next to text, 14 in
  /// the verdict card):
  /// ● circle (5, 5) r 4.5 · ▲ `M5 .6 9.6 9.4H.4z` · ■ rect .6 .6 8.8 8.8 · ○ circle (5, 5) r 4,
  /// stroke 1.2, no fill (critique R-18b).
  ///
  /// Hidden from accessibility unless given a label: next to its word, VoiceOver reads the word.
  public struct StatusGlyph: View {
    public let kind: StatusKind
    public let size: CGFloat
    public let accessibilityLabel: String?

    public init(
      _ kind: StatusKind, size: CGFloat = ChapterTheme.Metric.statusGlyph,
      accessibilityLabel: String? = nil
    ) {
      self.kind = kind
      self.size = size
      self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
      let unit = size / 10
      shape(unit: unit)
        .frame(width: size, height: size)
        .accessibilityHidden(accessibilityLabel == nil)
        .accessibilityLabel(Text(accessibilityLabel ?? ""))
    }

    @ViewBuilder
    private func shape(unit: CGFloat) -> some View {
      switch kind {
      case .done:
        Circle().fill(kind.glyphColor).frame(width: 9 * unit, height: 9 * unit)
      case .partly:
        ViewBoxPolygon(
          points: [CGPoint(x: 5, y: 0.6), CGPoint(x: 9.6, y: 9.4), CGPoint(x: 0.4, y: 9.4)],
          viewBox: CGSize(width: 10, height: 10)
        )
        .fill(kind.glyphColor)
      case .missing:
        Rectangle().fill(kind.glyphColor).frame(width: 8.8 * unit, height: 8.8 * unit)
      case .waiting:
        Circle()
          .stroke(kind.glyphColor, lineWidth: 1.2 * unit)
          .frame(width: 8 * unit, height: 8 * unit)
      }
    }
  }

  /// A status as glyph and word (phone-capture §2.4.6): HStack spacing 5, the 10 pt glyph, then the
  /// word in subhead 15 (`.regular`) or, when the status is part of a subtitle, footnote 13
  /// (`.small`). VoiceOver reads the word.
  public struct StatusLabel: View {
    public enum Size: Sendable {
      /// Word in subhead 15: the trailing status of a row.
      case regular
      /// Word in footnote 13: a status inside a subtitle.
      case small
    }

    public let kind: StatusKind
    public let word: String
    public let size: Size
    /// The glyph grows with the word at larger text sizes (10 pt at the default size).
    @ScaledMetric(relativeTo: .subheadline) private var glyphSize = ChapterTheme.Metric.statusGlyph

    public init(kind: StatusKind, word: String, size: Size = .regular) {
      self.kind = kind
      self.word = word
      self.size = size
    }

    public var body: some View {
      HStack(spacing: ChapterTheme.Metric.statusGlyphGap) {
        StatusGlyph(kind, size: glyphSize)
        Text(word)
          .chapterTextStyle(size == .regular ? .subhead : .footnote)
          .foregroundStyle(kind.textColor)
      }
      .accessibilityElement(children: .combine)
    }
  }
#endif
