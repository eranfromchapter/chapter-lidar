#if canImport(SwiftUI) && os(iOS)
  import SwiftUI
  import UIKit

  /// The system navigation bar in the Chapter look (phone-capture §2.5, critique R-18c): every
  /// phone screen uses the system `NavigationStack`, with the large title in Times New Roman 34 on
  /// root and form screens, inline titles in Inter SemiBold 17 and the system back chevron (the
  /// 44 pt glass pill on iOS 26), in ink.
  ///
  /// Two halves, both needed: `apply()` sets the UIKit appearance (fonts, colours, background) at
  /// launch, and `chapterRoot()` on the root view sets the SwiftUI environment. The colour of the
  /// back chevron and bar buttons comes from the second: `NavigationStack` gives its bar the
  /// SwiftUI tint and ignores the appearance proxy's `tintColor`.
  @MainActor
  public enum ChapterAppearance {
    /// Sets the navigation bar appearance of the whole app. Call it once at launch, after
    /// `ChapterFonts.register()` (it registers the fonts itself when they are missing), and put
    /// `chapterRoot()` on the root view. Calling it again changes nothing.
    public static func apply() {
      ChapterFonts.register()
      let bar = UINavigationBar.appearance()
      bar.standardAppearance = navigationBarAppearance()
      bar.compactAppearance = navigationBarAppearance()
      bar.scrollEdgeAppearance = navigationBarAppearance(atScrollEdge: true)
      bar.compactScrollEdgeAppearance = navigationBarAppearance(atScrollEdge: true)
      // Bar buttons of navigation bars UIKit draws on its own (controllers presented by UIKit,
      // not by SwiftUI). SwiftUI's bars take the tint of `chapterRoot()` instead.
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

  extension View {
    /// The Chapter look's SwiftUI environment, for the root view of every window (the app's
    /// `WindowGroup`; the snapshot harness puts it on every view it draws): Inter body as the
    /// default font of text without a font of its own, and ink as the tint. The tint colours the
    /// navigation bar's back chevron and buttons (system blue without it, on iOS 17 and 18), the
    /// text cursor, links, menus and the other controls drawn in the accent colour.
    public func chapterRoot() -> some View {
      font(ChapterTheme.Font.body)
        .tint(ChapterTheme.Color.ink)
    }
  }
#endif
