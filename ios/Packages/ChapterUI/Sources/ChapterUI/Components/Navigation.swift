#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  /// The signed-in operator in the Captures home's navigation bar (phone-capture §2.4.9): a 36 pt
  /// nude circle with the initials in footnoteEmphasis ink, a 44 pt hit area, and the label
  /// "Signed in as [OPERATOR]".
  public struct AvatarButton: View {
    let name: String
    let action: () -> Void

    public init(name: String, action: @escaping () -> Void) {
      self.name = name
      self.action = action
    }

    /// The first letter of each of the first two words, uppercased ("Dana Ruiz" → "DR",
    /// "Field test" → "FT"); "?" for an empty name.
    public nonisolated static func initials(for name: String) -> String {
      let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
      guard !letters.isEmpty else { return "?" }
      return String(letters).uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    public var body: some View {
      Button(action: action) {
        Text(Self.initials(for: name))
          .chapterTextStyle(.footnoteEmphasis)
          .foregroundStyle(ChapterTheme.Color.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
          .frame(width: ChapterTheme.Metric.avatar, height: ChapterTheme.Metric.avatar)
          .background(ChapterTheme.Color.nude, in: Circle())
          .frame(width: ChapterTheme.Metric.touchTarget, height: ChapterTheme.Metric.touchTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(name.isEmpty ? "Signed in" : "Signed in as \(name)"))
    }
  }

  /// The subtitle under a large title, as the first content line (critique R-18c): subhead 15/20,
  /// muted, up to 3 lines. Put it 8 pt under the title (`Metric.subtitleTop`).
  public struct ScreenSubtitle: View {
    let text: String

    public init(_ text: String) {
      self.text = text
    }

    public var body: some View {
      Text(text)
        .chapterTextStyle(.subhead)
        .foregroundStyle(ChapterTheme.Color.muted)
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// A toolbar item without the shared glass background iOS 26 puts behind bar items: for the
  /// trailing caption, the logo and the avatar, which are drawn on the bar itself.
  public struct PlainToolbarItem<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    let content: Content

    public init(placement: ToolbarItemPlacement, @ViewBuilder content: () -> Content) {
      self.placement = placement
      self.content = content()
    }

    public var body: some ToolbarContent {
      if #available(iOS 26.0, *) {
        ToolbarItem(placement: placement) { content }
          .sharedBackgroundVisibility(.hidden)
      } else {
        ToolbarItem(placement: placement) { content }
      }
    }
  }

  extension View {
    /// The right-hand caption of the navigation bar ("Step 1 of 3", "Deal [DEAL ID]"): footnote,
    /// muted, one line. It is text, not a button.
    public func chapterNavigationCaption(_ text: String) -> some View {
      toolbar {
        PlainToolbarItem(placement: .topBarTrailing) {
          Text(text)
            .chapterTextStyle(.footnote)
            .foregroundStyle(ChapterTheme.Color.muted)
            .lineLimit(1)
        }
      }
    }

    /// Back shows the chevron only (the system 44 pt glass pill on iOS 26). For pushed screens.
    public func chapterBackChevronOnly() -> some View {
      toolbarRole(.editor)
    }

    /// The screen background (ground, under the safe areas) and ink as the default text colour.
    public func chapterScreenBackground() -> some View {
      foregroundStyle(ChapterTheme.Color.ink)
        .background(ChapterTheme.Color.ground.ignoresSafeArea())
    }

    /// Limits content to the 600 pt column of the iPad layout, centred; no change on a phone.
    public func chapterContentWidth() -> some View {
      frame(maxWidth: ChapterTheme.Metric.contentMaxWidth)
        .frame(maxWidth: .infinity)
    }
  }
#endif
