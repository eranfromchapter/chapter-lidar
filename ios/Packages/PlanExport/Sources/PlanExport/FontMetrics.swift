import Foundation

/// Advance widths of the PDF fonts, in 1/1000 em: Inter Regular and Inter SemiBold (the
/// Chapter sans, embedded; every WinAnsi character) and the standard Times-Roman (the Chapter
/// serif; printable ASCII, other characters a mean width). A character is measured as the PDF
/// draws it, so one WinAnsi lacks counts as the `?` that replaces it.
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

  /// Width of `text` in points at `size` points: Inter SemiBold when `bold`, Times-Roman when
  /// `serif`, Inter Regular otherwise.
  static func width(_ text: String, size: Double, bold: Bool = false, serif: Bool = false)
    -> Double
  {
    var total = 0
    if serif {
      for scalar in text.unicodeScalars {
        let index = Int(scalar.value) - 0x20
        total += index >= 0 && index < Self.serif.count ? Self.serif[index] : 500
      }
    } else {
      let widths =
        bold ? ChapterBrandAssets.interSemiBold.widths : ChapterBrandAssets.interRegular.widths
      for scalar in text.unicodeScalars {
        let code = Int(PDFPage.winAnsi(scalar))
        total += code >= 32 ? widths[code - 32] : widths[Int(UInt8(ascii: "?")) - 32]
      }
    }
    return Double(total) * size / 1000
  }
}
