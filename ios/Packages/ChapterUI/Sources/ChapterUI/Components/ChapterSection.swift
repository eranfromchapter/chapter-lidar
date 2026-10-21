#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  /// A grouped section (phone-capture §2.4.1): an optional header (footnote, uppercase, muted,
  /// 16 pt inset), the card holding the rows, and an optional footer (footnote 13/17, muted,
  /// 16 pt inset, wrapping), 6 pt apart. A section without a header draws only the card.
  ///
  ///     ChapterSection(header: "Address in the HUB", footer: "If the address on site …") {
  ///       ProminentTextRow("618 Valley Street")
  ///       ToggleRow("I am at this address", isOn: $confirmed)
  ///     }
  public struct ChapterSection<Content: View, Footer: View>: View {
    public enum HeaderStyle: Sendable {
      /// Footnote 13, 6 pt above the card.
      case standard
      /// Caption 12, 4 pt above the card: the Field controls list.
      case compact
    }

    let header: String?
    let headerStyle: HeaderStyle
    let content: Content
    let footer: Footer

    public init(
      header: String? = nil, headerStyle: HeaderStyle = .standard,
      @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
    ) {
      self.header = header
      self.headerStyle = headerStyle
      self.content = content()
      self.footer = footer()
    }

    public var body: some View {
      VStack(
        alignment: .leading,
        spacing: headerStyle == .standard
          ? ChapterTheme.Metric.sectionHeaderGap : ChapterTheme.Metric.sectionHeaderGapCompact
      ) {
        if let header {
          SectionCaption(header, size: headerStyle == .standard ? .regular : .small)
        }
        ChapterCard { content }
        footer
      }
    }
  }

  extension ChapterSection where Footer == SectionFooter {
    public init(
      header: String? = nil, footer: String? = nil, headerStyle: HeaderStyle = .standard,
      @ViewBuilder content: () -> Content
    ) {
      self.init(header: header, headerStyle: headerStyle, content: content) {
        SectionFooter(footer)
      }
    }
  }

  /// The footnote under a section's card: footnote 13/17, muted, 16 pt inset, wrapping. Nothing
  /// when the text is nil.
  public struct SectionFooter: View {
    let text: String?

    public init(_ text: String?) {
      self.text = text
    }

    public var body: some View {
      if let text {
        Text(text)
          .chapterTextStyle(.footnote)
          .foregroundStyle(ChapterTheme.Color.muted)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, ChapterTheme.Metric.sectionInset)
      }
    }
  }

  /// An uppercase muted caption above a group (phone-field §1.3): 13 pt (`.regular`; section
  /// headers, the labeling screen, sheets) or 12 pt (`.small`; the Field controls list). Only
  /// `text` is uppercased; `suffix` keeps its case (`ROOM` + `· stays selected for the next
  /// photo`). VoiceOver reads the original case, as a header.
  public struct SectionCaption: View {
    public enum Size: Sendable {
      case regular
      case small
    }

    let text: String
    let suffix: String?
    let size: Size
    let inset: CGFloat

    public init(
      _ text: String, suffix: String? = nil, size: Size = .regular,
      inset: CGFloat = ChapterTheme.Metric.sectionInset
    ) {
      self.text = text
      self.suffix = suffix
      self.size = size
      self.inset = inset
    }

    public var body: some View {
      let upper = Text(text.uppercased(with: Locale(identifier: "en_US_POSIX")))
      (suffix.map { upper + Text(" " + $0) } ?? upper)
        .chapterTextStyle(size == .regular ? .footnote : .caption)
        .foregroundStyle(ChapterTheme.Color.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, inset)
        .accessibilityLabel(Text(suffix.map { "\(text) \($0)" } ?? text))
        .accessibilityAddTraits(.isHeader)
    }
  }

  /// The grouped card (phone-capture §2.3): surface fill, 1 pt line border, radius 12, content
  /// clipped, and a 1 pt nude separator across the full card width between rows (not inset).
  /// Each top-level view of `content` is a row (a `ForEach` gives one row per element).
  public struct ChapterCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
      self.content = content()
    }

    public var body: some View {
      let shape = RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
      SeparatedRows { content }
        .padding(ChapterTheme.Metric.cardBorder)
        .background(ChapterTheme.Color.surface)
        .clipShape(shape)
        .overlay(
          shape.strokeBorder(ChapterTheme.Color.line, lineWidth: ChapterTheme.Metric.cardBorder))
    }
  }

  /// The card's 1 pt nude row separator.
  struct RowSeparator: View {
    var body: some View {
      Rectangle()
        .fill(ChapterTheme.Color.nude)
        .frame(height: ChapterTheme.Metric.separator)
        .accessibilityHidden(true)
    }
  }

  /// Stacks the top-level views of `content` with a separator between each two.
  struct SeparatedRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
      if #available(iOS 18, *) {
        VStack(spacing: 0) {
          Group(subviews: content) { rows in
            ForEach(rows) { row in
              if row.id != rows.first?.id { RowSeparator() }
              row
            }
          }
        }
      } else {
        _VariadicView.Tree(SeparatedRowsRoot()) { content }
      }
    }
  }

  /// iOS 17: the same as the iOS 18 branch, through the variadic view that `Group(subviews:)`
  /// later made public.
  struct SeparatedRowsRoot: _VariadicView_UnaryViewRoot {
    func body(children: _VariadicView.Children) -> some View {
      VStack(spacing: 0) {
        ForEach(children) { row in
          if row.id != children.first?.id { RowSeparator() }
          row
        }
      }
    }
  }
#endif
