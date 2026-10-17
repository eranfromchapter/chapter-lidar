#if canImport(SwiftUI) && canImport(Observation) && os(iOS)
  import SwiftUI

  /// The frozen design tokens (docs/waves/design/snapshot.html#tokens). Names and values match the
  /// `:root` variables of the snapshot.
  public enum ChapterTokens {
    public enum Palette {
      public static let ink = Color(hex: 0x1F2429)
      public static let ground = Color(hex: 0xF5EFE6)
      public static let surface = Color(hex: 0xFAF5EE)
      public static let nude = Color(hex: 0xE8DDD0)
      public static let line = Color(hex: 0xD9CCBC)
      public static let muted = Color(hex: 0x6B6557)
      public static let ready = Color(hex: 0x2E5E2E)
      public static let limited = Color(hex: 0x9A6A1E)
      public static let limitedText = Color(hex: 0x7A5214)
      public static let blocked = Color(hex: 0x8B2E2E)

      // Live scan screen (dark): values taken from screen-capture, panel 3.
      public static let scanPanel = Color(hex: 0x2B3137)
      public static let scanPanelBorder = Color(hex: 0x3A424A)
      public static let scanPlaceholder = Color(hex: 0xB9AFA2)
      public static let scanCaption = Color(hex: 0xD9CCBC)
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
      public static let chip: CGFloat = 8
      public static let card: CGFloat = 12
      public static let sheet: CGFloat = 16
      /// Segment inside the mode control (screen-capture panel 2).
      public static let segment: CGFloat = 9
    }

    public enum Control {
      /// Primary action height on the capture screens (the token minimum is 52).
      public static let primaryHeight: CGFloat = 56
      public static let fieldHeight: CGFloat = 52
      public static let projectButtonHeight: CGFloat = 56
      public static let segmentHeight: CGFloat = 48
      /// Chips and checkboxes.
      public static let minTouch: CGFloat = 44
      public static let checkbox: CGFloat = 24
    }

    public enum Typography {
      /// Display and title serif: 34 / 30 / 24.
      public static func serif(_ size: CGFloat) -> Font {
        .custom("Times New Roman", size: size)
      }

      public static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
      }

      public static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
      }

      public static let display = serif(34)
      public static let headline = sans(17, weight: .semibold)
      public static let body = sans(17)
      public static let caption = sans(13)
    }
  }

  extension Color {
    init(hex: UInt32) {
      self.init(
        .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
  }
#endif
