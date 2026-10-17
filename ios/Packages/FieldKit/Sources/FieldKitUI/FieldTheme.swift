#if canImport(SwiftUI) && canImport(UIKit)
  import SwiftUI

  /// Design tokens from docs/waves/design/snapshot.html#tokens (frozen design).
  enum FieldTheme {
    // Colour
    static let ink = Color(hex: 0x1F2429)
    static let ground = Color(hex: 0xF5EFE6)
    static let surface = Color(hex: 0xFAF5EE)
    static let nude = Color(hex: 0xE8DDD0)
    static let line = Color(hex: 0xD9CCBC)
    static let muted = Color(hex: 0x6B6557)
    static let ready = Color(hex: 0x2E5E2E)
    static let limited = Color(hex: 0x9A6A1E)
    static let blocked = Color(hex: 0x8B2E2E)
    /// Text colour of a disabled primary button (design: #4E493F on #D9CCBC).
    static let disabledText = Color(hex: 0x4E493F)

    // Space 4 8 12 16 24 32 48
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space24: CGFloat = 24

    // Radius: chip 8, card 12, sheet 16
    static let chipRadius: CGFloat = 8
    static let cardRadius: CGFloat = 12
    static let sheetRadius: CGFloat = 16

    // Touch targets
    static let chipHeight: CGFloat = 44
    static let primaryHeight: CGFloat = 56
    static let fieldHeight: CGFloat = 52

    // Type
    static func title30() -> Font { .custom("Times New Roman", size: 30) }
    static let headline = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 17)
    static let chip = Font.system(size: 15)
    static let rowTitle = Font.system(size: 15, weight: .semibold)
    static let caption = Font.system(size: 13)
  }

  extension Color {
    init(hex: UInt32) {
      self.init(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: 1)
    }
  }
#endif
