#if canImport(SwiftUI) && canImport(UIKit)
  import ChapterUI
  import SwiftUI

  /// The field screens' tokens: a thin alias of ChapterUI's `ChapterTheme` (critique R-18), so
  /// there is one source of colour, type and metrics on the phone. `FieldTheme.Color.ink`,
  /// `FieldTheme.TextStyle.body`, `FieldTheme.Metric.screenPadding`.
  typealias FieldTheme = ChapterTheme

  /// Sizes of the field screens that no other screen shares (phone-field §3.2, §4.2, §5.2, §6.1).
  enum FieldMetric {
    // Label a photo
    /// The photo just taken.
    static let photoHeight: CGFloat = 210
    static let photoRadius: CGFloat = 16
    /// The time pill on the photo: 12 from the left, 10 from the bottom.
    static let photoPillInset = CGSize(width: 12, height: 10)
    /// Gap between the labeling screen's blocks, and from a caption to its control.
    static let labelBlockGap: CGFloat = 12
    static let labelCaptionGap: CGFloat = 6
    /// Inset of the labeling screen's captions inside the screen padding.
    static let labelCaptionInset: CGFloat = 4
    static let thumbnail: CGFloat = 40
    static let thumbnailRadius: CGFloat = 6
    static let chipGap: CGFloat = 8

    // Field controls list
    static let controlRowHeight: CGFloat = 50
    static let controlRowCompactHeight: CGFloat = 42
    static let controlRowVerticalPadding: CGFloat = 5
    static let controlSectionGap: CGFloat = 8

    // Entry sheet
    static let valueFieldHeight: CGFloat = 56
    static let valueFieldPadding: CGFloat = 14
    static let valueFieldGap: CGFloat = 10
    static let sheetSectionGap: CGFloat = 14

    // Before you leave
    static let checklistRowHeight: CGFloat = 56
    static let checklistRowWithButtonHeight: CGFloat = 64
    static let checklistCardTop: CGFloat = 14
    static let checklistGap: CGFloat = 10
  }
#endif
