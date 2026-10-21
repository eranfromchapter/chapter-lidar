#if canImport(SwiftUI) && os(iOS)
  import SwiftUI

  /// The icon at the start of a banner.
  public enum BannerIcon: Sendable, Hashable {
    /// SF Symbol `wifi.slash`: offline.
    case offline
    /// The ■ glyph: something stops the screen (device gate, project list error).
    case blocked
    /// The ▲ glyph.
    case partly
    /// Any SF Symbol.
    case systemImage(String)
  }

  /// A banner (phone-capture §2.4.5): HStack aligned to the top, spacing 10, padding 12 × 16,
  /// radius 12, nude fill; an 18 pt ink icon 1 pt down from the top, then the text (subhead 15/20,
  /// ink, wrapping), then an optional accessory such as a `.rowAction` "Try again".
  public struct Banner<Accessory: View>: View {
    let icon: BannerIcon?
    let text: String
    let accessory: Accessory

    public init(icon: BannerIcon? = nil, text: String, @ViewBuilder accessory: () -> Accessory) {
      self.icon = icon
      self.text = text
      self.accessory = accessory()
    }

    public var body: some View {
      HStack(alignment: .top, spacing: ChapterTheme.Metric.bannerGap) {
        if let icon {
          iconView(icon)
            .frame(width: ChapterTheme.Metric.bannerIcon, height: ChapterTheme.Metric.bannerIcon)
            .padding(.top, 1)
            .accessibilityHidden(true)
        }
        Text(text)
          .chapterTextStyle(.subhead)
          .foregroundStyle(ChapterTheme.Color.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
        accessory
      }
      .padding(.vertical, ChapterTheme.Metric.bannerVerticalPadding)
      .padding(.horizontal, ChapterTheme.Metric.bannerPadding)
      .background(
        ChapterTheme.Color.nude, in: RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
      )
      .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func iconView(_ icon: BannerIcon) -> some View {
      switch icon {
      case .offline: symbol("wifi.slash")
      case .systemImage(let name): symbol(name)
      case .blocked: StatusGlyph(.missing, size: ChapterTheme.Metric.verdictGlyph)
      case .partly: StatusGlyph(.partly, size: ChapterTheme.Metric.verdictGlyph)
      }
    }

    private func symbol(_ name: String) -> some View {
      Image(systemName: name)
        .resizable()
        .scaledToFit()
        .foregroundStyle(ChapterTheme.Color.ink)
    }
  }

  extension Banner where Accessory == EmptyView {
    public init(icon: BannerIcon? = nil, text: String) {
      self.init(icon: icon, text: text) { EmptyView() }
    }
  }

  /// The lock note of the package screens (phone-package §2.5): HStack aligned to the top, spacing
  /// 10, padding 10 × 14, radius 12, nude fill; the 16 pt lock (stroke ink 1.5) 1 pt down, then
  /// the text in footnote 13/17 ink.
  public struct InfoNote: View {
    let text: String

    public init(_ text: String) {
      self.text = text
    }

    public var body: some View {
      HStack(alignment: .top, spacing: ChapterTheme.Metric.bannerGap) {
        LockIcon().padding(.top, 1)
        Text(text)
          .chapterTextStyle(.footnote)
          .foregroundStyle(ChapterTheme.Color.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, ChapterTheme.Metric.infoNoteVerticalPadding)
      .padding(.horizontal, ChapterTheme.Metric.infoNoteHorizontalPadding)
      .background(
        ChapterTheme.Color.nude, in: RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
      )
      .accessibilityElement(children: .combine)
    }
  }
#endif
