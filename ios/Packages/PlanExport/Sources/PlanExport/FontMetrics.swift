import Foundation

/// Advance widths of the PDF fonts, in 1/1000 em: Inter Regular and Inter SemiBold (the
/// Chapter sans, embedded; every WinAnsi character), the standard Times-Roman and Times-Italic
/// (the Chapter serif; printable ASCII from the Adobe Core 14 metrics, other characters a mean
/// width) and Courier (every glyph 600). A character is measured as the PDF draws it, so one
/// WinAnsi lacks counts as the `?` that replaces it.
enum FontMetrics {
  /// Times-Roman, index 0 is U+0020 (space) through U+007E (~).
  private static let serif: [Int] = [
    250, 333, 408, 500, 500, 833, 778, 180, 333, 333, 500, 564, 250, 333, 250, 278,
    500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564, 564, 444,
    921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611, 889, 722, 722,
    556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333, 278, 333, 469, 500,
    333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278, 500, 278, 778, 500, 500,
    500, 500, 333, 389, 278, 500, 500, 722, 500, 500, 444, 480, 200, 480, 541,
  ]

  /// Times-Italic (Adobe Core 14 AFM, WinAnsi: 0x27 is quotesingle), U+0020 through U+007E.
  private static let serifItalic: [Int] = [
    250, 333, 420, 500, 500, 833, 778, 214, 333, 333, 500, 675, 250, 333, 250, 278,
    500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 675, 675, 675, 500,
    920, 611, 611, 667, 722, 611, 611, 722, 722, 333, 444, 667, 556, 833, 667, 722,
    611, 722, 611, 500, 556, 722, 611, 833, 611, 556, 556, 389, 278, 389, 422, 500,
    333, 500, 500, 444, 500, 444, 278, 500, 500, 278, 278, 444, 278, 722, 500, 500,
    500, 500, 389, 389, 278, 500, 444, 667, 444, 444, 389, 400, 275, 400, 541,
  ]

  /// Courier's advance, every glyph.
  static let courierAdvance = 600

  /// Width of `text` in points at `size` points: Inter SemiBold when `bold`, Times-Roman when
  /// `serif`, Inter Regular otherwise. Measured composed (`Format.composed`), as it is drawn.
  static func width(_ text: String, size: Double, bold: Bool = false, serif: Bool = false)
    -> Double
  {
    width(text, size: size, font: DrawingFont(bold: bold, serif: serif))
  }

  /// Width of `text` in points at `size` points in `font`, as the PDF draws it.
  static func width(_ text: String, size: Double, font: DrawingFont) -> Double {
    let text = Format.composed(text)
    var total = 0
    switch font {
    case .timesRoman, .timesItalic:
      let table = font == .timesRoman ? Self.serif : Self.serifItalic
      for scalar in text.unicodeScalars {
        let index = Int(scalar.value) - 0x20
        total += index >= 0 && index < table.count ? table[index] : 500
      }
    case .courier:
      total = text.unicodeScalars.count * courierAdvance
    case .interRegular, .interSemiBold:
      let widths =
        font == .interSemiBold
        ? ChapterBrandAssets.interSemiBold.widths : ChapterBrandAssets.interRegular.widths
      for scalar in text.unicodeScalars {
        let code = Int(PDFPage.winAnsi(scalar))
        total += code >= 32 ? widths[code - 32] : widths[Int(UInt8(ascii: "?")) - 32]
      }
    }
    return Double(total) * size / 1000
  }

  /// Cap height of `font`, em: centres capitals in a line box (plan-sheet §3.1).
  static func capHeight(_ font: DrawingFont) -> Double {
    switch font {
    case .interRegular, .interSemiBold: return 0.727
    case .timesRoman: return 0.662
    case .timesItalic: return 0.653
    case .courier: return 0.562
    }
  }
}
