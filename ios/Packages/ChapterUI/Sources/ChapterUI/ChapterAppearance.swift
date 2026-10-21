#if canImport(SwiftUI) && os(iOS)
  import UIKit

  /// The system navigation bar in the Chapter look (phone-capture §2.5, critique R-18c): every
  /// phone screen uses the system `NavigationStack`, with the large title in Times New Roman 34 on
  /// root and form screens, inline titles in Inter SemiBold 17 and the system back chevron (the
  /// 44 pt glass pill on iOS 26).
  @MainActor
  public enum ChapterAppearance {
    /// Sets the navigation bar appearance of the whole app. Call it once at launch, after
    /// `ChapterFonts.register()` (it registers the fonts itself when they are missing). Calling
    /// it again changes nothing.
    public static func apply() {
      ChapterFonts.register()
      let bar = UINavigationBar.appearance()
      bar.standardAppearance = navigationBarAppearance()
      bar.compactAppearance = navigationBarAppearance()
      bar.scrollEdgeAppearance = navigationBarAppearance(atScrollEdge: true)
      bar.compactScrollEdgeAppearance = navigationBarAppearance(atScrollEdge: true)
      // The back chevron and bar buttons.
      bar.tintColor = ChapterTheme.Swatch.ink.uiColor
    }

    /// Background ground #F5EFE6 without a shadow line; large title Times New Roman 34 and inline
    /// title Inter SemiBold 17, both ink and scaled with Dynamic Type; bar buttons Inter 17 ink
    /// (Done in SemiBold).
    ///
    /// At the scroll edge (content not scrolled under the bar) the bar draws no background of its
    /// own: every screen sits on ground (`chapterScreenBackground()`), so it reads as the same
    /// ground bar. On iOS 26 the large title lives in the screen's scroll view, under the bar's
    /// background view, and an opaque background there would cover it.
    public static func navigationBarAppearance(atScrollEdge: Bool = false)
      -> UINavigationBarAppearance
    {
      let ink = ChapterTheme.Swatch.ink.uiColor
      let appearance = UINavigationBarAppearance()
      if atScrollEdge {
        appearance.configureWithTransparentBackground()
      } else {
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ChapterTheme.Swatch.ground.uiColor
      }
      appearance.shadowColor = .clear
      appearance.largeTitleTextAttributes = [
        .font: ChapterTheme.TextStyle.largeTitle.uiFont(), .foregroundColor: ink,
      ]
      appearance.titleTextAttributes = [
        .font: ChapterTheme.TextStyle.navTitle.uiFont(), .foregroundColor: ink,
      ]

      let plain = UIBarButtonItemAppearance(style: .plain)
      plain.normal.titleTextAttributes = [
        .font: ChapterTheme.TextStyle.body.uiFont(), .foregroundColor: ink,
      ]
      let done = UIBarButtonItemAppearance(style: .done)
      done.normal.titleTextAttributes = [
        .font: ChapterTheme.TextStyle.bodyEmphasis.uiFont(), .foregroundColor: ink,
      ]
      appearance.buttonAppearance = plain
      appearance.backButtonAppearance = plain
      appearance.doneButtonAppearance = done
      return appearance
    }
  }
#endif
