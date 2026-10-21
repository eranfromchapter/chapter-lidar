#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  /// The phone's buttons (phone-capture §2.4.3 with phone-field's text button):
  ///
  /// - `.primary`: 52 pt, full width, radius 12, ink fill, bodyEmphasis surface. Disabled: line
  ///   fill, bodyEmphasis #4E493F.
  /// - `.tinted`: 52 pt, full width, radius 12, nude fill, body ink. Disabled: as primary.
  /// - `.text`: 44 pt, full width, no fill, body ink ("Done with photos"). Disabled: #B9AFA2.
  /// - `.rowAction`: 44 pt, padding 0 × 12, radius 8, nude fill, subhead ink ("Read again").
  /// - `.cardAction`: 44 pt, padding 0 × 16, radius 10, nude fill, subhead ink.
  /// - `.outlineOnDark`: 52 pt, full width, radius 12, 1 pt surface border, body surface.
  /// - `.filledOnDark`: 52 pt, full width, radius 12, surface fill, bodyEmphasis ink.
  ///
  /// The last four are drawn at opacity 0.4 when disabled.
  /// A disabled primary button is never drawn with opacity: its label is different text that says
  /// what is missing, and each screen gives it. Every kind dims to 0.7 while pressed. Heights are
  /// minimums; labels wrap and the button grows with Dynamic Type.
  ///
  ///     Button("Continue") { … }.buttonStyle(.chapter(.primary))
  public struct ChapterButtonStyle: ButtonStyle {
    public enum Kind: String, CaseIterable, Sendable {
      case primary
      case tinted
      case text
      case rowAction
      case cardAction
      case outlineOnDark
      case filledOnDark
    }

    public let kind: Kind

    public init(_ kind: Kind) {
      self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
      ChapterButtonLabel(kind: kind, label: configuration.label, isPressed: configuration.isPressed)
    }
  }

  extension ButtonStyle where Self == ChapterButtonStyle {
    /// A Chapter button style: `.buttonStyle(.chapter(.primary))`.
    public static func chapter(_ kind: ChapterButtonStyle.Kind) -> ChapterButtonStyle {
      ChapterButtonStyle(kind)
    }
  }

  private struct ChapterButtonLabel<Label: View>: View {
    typealias Kind = ChapterButtonStyle.Kind
    typealias Metric = ChapterTheme.Metric

    let kind: Kind
    let label: Label
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      styled
        .multilineTextAlignment(.center)
        .contentShape(Rectangle())
        .opacity(isPressed ? 0.7 : dimmed ? 0.4 : 1)
    }

    /// Kinds whose disabled state is drawn at opacity 0.4.
    private var dimmed: Bool {
      guard !isEnabled else { return false }
      switch kind {
      case .rowAction, .cardAction, .outlineOnDark, .filledOnDark: return true
      case .primary, .tinted, .text: return false
      }
    }

    @ViewBuilder
    private var styled: some View {
      switch kind {
      case .primary, .tinted:
        let primary = kind == .primary
        label
          .chapterTextStyle(!isEnabled || primary ? .bodyEmphasis : .body)
          .foregroundStyle(
            !isEnabled
              ? ChapterTheme.Color.disabledText
              : primary ? ChapterTheme.Color.surface : ChapterTheme.Color.ink
          )
          .fullWidth(minHeight: Metric.primaryButtonHeight)
          .background(
            !isEnabled
              ? ChapterTheme.Color.line
              : primary ? ChapterTheme.Color.ink : ChapterTheme.Color.nude,
            in: RoundedRectangle(cornerRadius: Metric.buttonRadius))
      case .text:
        label
          .chapterTextStyle(.body)
          .foregroundStyle(isEnabled ? ChapterTheme.Color.ink : ChapterTheme.Color.chevron)
          .fullWidth(minHeight: Metric.textButtonHeight)
      case .rowAction:
        label
          .chapterTextStyle(.subhead)
          .foregroundStyle(ChapterTheme.Color.ink)
          .padding(.horizontal, Metric.rowActionPadding)
          .padding(.vertical, 4)
          .frame(minHeight: Metric.rowActionHeight)
          .background(
            ChapterTheme.Color.nude, in: RoundedRectangle(cornerRadius: Metric.rowActionRadius))
      case .cardAction:
        label
          .chapterTextStyle(.subhead)
          .foregroundStyle(ChapterTheme.Color.ink)
          .padding(.horizontal, Metric.cardActionPadding)
          .padding(.vertical, 4)
          .frame(minHeight: Metric.cardActionHeight)
          .background(
            ChapterTheme.Color.nude, in: RoundedRectangle(cornerRadius: Metric.cardActionRadius))
      case .outlineOnDark:
        label
          .chapterTextStyle(.body)
          .foregroundStyle(ChapterTheme.Color.surface)
          .fullWidth(minHeight: Metric.primaryButtonHeight)
          .overlay(
            RoundedRectangle(cornerRadius: Metric.buttonRadius)
              .strokeBorder(ChapterTheme.Color.surface, lineWidth: 1))
      case .filledOnDark:
        label
          .chapterTextStyle(.bodyEmphasis)
          .foregroundStyle(ChapterTheme.Color.ink)
          .fullWidth(minHeight: Metric.primaryButtonHeight)
          .background(
            ChapterTheme.Color.surface, in: RoundedRectangle(cornerRadius: Metric.buttonRadius))
      }
    }
  }

  extension View {
    /// Full width, at least `minHeight` tall, with room for a wrapped label.
    fileprivate func fullWidth(minHeight: CGFloat) -> some View {
      padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
  }

  /// A full-width 44 pt text button: Inter 17 ink, #B9AFA2 when disabled ("Done with photos").
  public struct TextButton: View {
    public let title: String
    public let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
      self.title = title
      self.action = action
    }

    public var body: some View {
      Button(title, action: action).buttonStyle(.chapter(.text))
    }
  }

  /// The bottom action bar of a screen: buttons stacked with a 10 pt gap, padding 12 above, 16 at
  /// the sides and 8 above the bottom safe area, on ground. Prefer `View.chapterActionBar`, which
  /// pins it with `safeAreaInset(edge: .bottom)` so it stays above the keyboard and scrolling
  /// content.
  public struct ChapterActionBar<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
      self.content = content()
    }

    public var body: some View {
      VStack(spacing: ChapterTheme.Metric.actionBarGap) {
        content
      }
      .frame(maxWidth: ChapterTheme.Metric.contentMaxWidth)
      .padding(.top, ChapterTheme.Metric.actionBarTop)
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .padding(.bottom, ChapterTheme.Metric.actionBarBottom)
      .frame(maxWidth: .infinity)
      .background(ChapterTheme.Color.ground)
    }
  }

  extension View {
    /// Pins a `ChapterActionBar` with these buttons to the bottom of the screen.
    public func chapterActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
      safeAreaInset(edge: .bottom, spacing: 0) {
        ChapterActionBar(content: bar)
      }
    }
  }
#endif
