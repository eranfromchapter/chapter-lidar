#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import ChapterUI
  import SwiftUI

  /// The v1 token names, kept as a façade over ChapterUI's `ChapterTheme` (phone-capture §2,
  /// critique R-18) so screens outside this package that still use them compile unchanged and
  /// pick up the v2 values: Inter instead of SF (`sans`), Times New Roman for display titles,
  /// 52 pt primary buttons, a 44 pt segmented control. New code uses `ChapterTheme` directly.
  public enum ChapterTokens {
    public enum Palette {
      public static let ink = ChapterTheme.Color.ink
      public static let ground = ChapterTheme.Color.ground
      public static let surface = ChapterTheme.Color.surface
      public static let nude = ChapterTheme.Color.nude
      public static let line = ChapterTheme.Color.line
      public static let muted = ChapterTheme.Color.muted
      public static let ready = ChapterTheme.Color.ready
      public static let limited = ChapterTheme.Color.limited
      public static let limitedText = ChapterTheme.Color.limitedText
      public static let blocked = ChapterTheme.Color.blocked

      // Live scan screen (dark).
      public static let scanPanel = ChapterTheme.Color.scanWell
      public static let scanPanelBorder = ChapterTheme.Color.scanWellBorder
      public static let scanPlaceholder = ChapterTheme.Color.chevron
      public static let scanCaption = ChapterTheme.Color.onDarkCaption
    }

    /// Space scale 4, 8, 12, 16, 24, 32, 48.
    public enum Space {
      public static let s1: CGFloat = 4
      public static let s2: CGFloat = 8
      public static let s3: CGFloat = 12
      public static let s4: CGFloat = 16
      public static let s5: CGFloat = 24
      public static let s6: CGFloat = 32
      public static let s7: CGFloat = 48
    }

    public enum Radius {
      public static let chip: CGFloat = ChapterTheme.Metric.chipRadius
      public static let card: CGFloat = ChapterTheme.Metric.cardRadius
      public static let sheet: CGFloat = ChapterTheme.Metric.sheetRadius
      public static let segment: CGFloat = ChapterTheme.Metric.segmentedRadius
    }

    public enum Control {
      /// Primary action height (v1 was 56).
      public static let primaryHeight: CGFloat = ChapterTheme.Metric.primaryButtonHeight
      public static let fieldHeight: CGFloat = ChapterTheme.Metric.navigationRowHeight
      public static let projectButtonHeight: CGFloat = ChapterTheme.Metric.navigationRowHeight
      /// v1 was 48.
      public static let segmentHeight: CGFloat = ChapterTheme.Metric.segmentedHeight
      /// Chips and checkboxes.
      public static let minTouch: CGFloat = ChapterTheme.Metric.touchTarget
      public static let checkbox: CGFloat = 24
    }

    public enum Typography {
      /// Display and title serif: Times New Roman Regular.
      public static func serif(_ size: CGFloat) -> Font {
        .custom(ChapterFonts.timesRegular, size: size)
      }

      /// Inter: SemiBold for semibold and heavier weights, else Regular.
      public static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let semibold: [Font.Weight] = [.semibold, .bold, .heavy, .black]
        return .custom(
          semibold.contains(weight) ? ChapterFonts.interSemiBold : ChapterFonts.interRegular,
          size: size)
      }

      public static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
      }

      /// The large title: Times New Roman 34.
      public static let display = ChapterTheme.Font.largeTitle
      public static let headline = ChapterTheme.Font.bodyEmphasis
      public static let body = ChapterTheme.Font.body
      public static let caption = ChapterTheme.Font.footnote
    }
  }
#endif
