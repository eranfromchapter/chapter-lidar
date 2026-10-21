#if canImport(SwiftUI) && os(iOS)
  import SwiftUI
  import UIKit

  /// The phone's screen tokens v2 (design v2, artboard 2k; build spec phone-capture §2): colour,
  /// type and metrics of every phone screen. CaptureUI's `ChapterTokens` and FieldKitUI's
  /// `FieldTheme` forward here, so there is one source.
  ///
  /// The app is light only. The live scan is dark by design and has its own tokens (`scanWell`,
  /// `onDarkCaption`, `onDarkPill`, `alertCard`).
  public enum ChapterTheme {
    /// Every phone colour by name, with its design value (sRGB).
    public enum Swatch: String, CaseIterable, Sendable {
      /// Text, primary button fill, toggle tint, live-scan background.
      case ink
      /// Screen and navigation bar background.
      case ground
      /// Grouped cards, text on ink, filled button on the dark scan screen.
      case surface
      /// Row separators, tinted buttons, segmented track, banners, avatar, progress track.
      case nude
      /// 1 pt card border, disabled button fill, grabber.
      case line
      /// Secondary text, section headers, footnotes, the waiting glyph.
      case muted
      /// Text of a disabled primary or tinted button.
      case disabledText
      /// Navigation-row chevron, disabled text button and sheet action.
      case chevron
      /// ● Done / Verified / Recorded / Ready; the "add" circle.
      case ready
      /// ▲ glyph.
      case limited
      /// Text next to ▲ (Partly / Approx. / Limited / Not verified).
      case limitedText
      /// ■ Missing / Open / Blocked; the "remove" circle; error text.
      case blocked
      /// Chapter logo fill only (brand black).
      case logo
      /// Live scan: camera well.
      case scanWell
      /// Live scan: camera well while tracking is lost.
      case scanWellDimmed
      /// Live scan: 1 pt camera-well border.
      case scanWellBorder
      /// Live scan: count labels and status line.
      case onDarkCaption
      /// Live scan: pills (surface at 14 %).
      case onDarkPill
      /// Live scan: tracking-lost card (surface at 97 %).
      case alertCard
      /// Photo labeling: time pill on the photo (ink at 70 %).
      case photoPill

      /// The colour as 0xRRGGBB.
      public var hex: UInt32 {
        switch self {
        case .ink: 0x1F2429
        case .ground: 0xF5EFE6
        case .surface: 0xFAF5EE
        case .nude: 0xE8DDD0
        case .line: 0xD9CCBC
        case .muted: 0x6B6557
        case .disabledText: 0x4E493F
        case .chevron: 0xB9AFA2
        case .ready: 0x2E5E2E
        case .limited: 0x9A6A1E
        case .limitedText: 0x7A5214
        case .blocked: 0x8B2E2E
        case .logo: 0x231F20
        case .scanWell: 0x2B3137
        case .scanWellDimmed: 0x23282D
        case .scanWellBorder: 0x3A424A
        case .onDarkCaption: 0xD9CCBC
        case .onDarkPill: 0xFAF5EE
        case .alertCard: 0xFAF5EE
        case .photoPill: 0x1F2429
        }
      }

      /// Opacity of the colour (1 except the translucent live-scan and photo tokens).
      public var opacity: Double {
        switch self {
        case .onDarkPill: 0.14
        case .alertCard: 0.97
        case .photoPill: 0.70
        default: 1
        }
      }

      public var color: SwiftUI.Color {
        SwiftUI.Color(
          .sRGB, red: component(16), green: component(8), blue: component(0), opacity: opacity)
      }

      public var uiColor: UIColor {
        UIColor(red: component(16), green: component(8), blue: component(0), alpha: opacity)
      }

      private func component(_ shift: UInt32) -> Double { Double((hex >> shift) & 0xFF) / 255 }
    }

    /// The colours as SwiftUI colours (§2.1).
    public enum Color {
      public static let ink = Swatch.ink.color
      public static let ground = Swatch.ground.color
      public static let surface = Swatch.surface.color
      public static let nude = Swatch.nude.color
      public static let line = Swatch.line.color
      public static let muted = Swatch.muted.color
      public static let disabledText = Swatch.disabledText.color
      public static let chevron = Swatch.chevron.color
      public static let ready = Swatch.ready.color
      public static let limited = Swatch.limited.color
      public static let limitedText = Swatch.limitedText.color
      public static let blocked = Swatch.blocked.color
      public static let logo = Swatch.logo.color
      public static let scanWell = Swatch.scanWell.color
      public static let scanWellDimmed = Swatch.scanWellDimmed.color
      public static let scanWellBorder = Swatch.scanWellBorder.color
      public static let onDarkCaption = Swatch.onDarkCaption.color
      public static let onDarkPill = Swatch.onDarkPill.color
      public static let alertCard = Swatch.alertCard.color
      public static let photoPill = Swatch.photoPill.color
    }

    /// One type style (§2.2): face, design size and line height, and the Dynamic Type style it
    /// scales with. `font` is for `.font(_:)`; `View.chapterTextStyle(_:)` also applies the line
    /// height to wrapping text (`lineSpacing = lineHeight − the font's own line height`).
    public struct TextStyle: Hashable, Sendable {
      public enum Face: Hashable, Sendable {
        /// Inter Regular (400), bundled.
        case interRegular
        /// Inter SemiBold (600), bundled. Design weights 600 and 700 both map here.
        case interSemiBold
        /// Times New Roman Regular, shipped with iOS: display titles only.
        case timesRegular
        /// The system monospaced font (SF Mono): timers and ids.
        case monospaced

        /// PostScript name of the face (nil for the system monospaced font).
        public var postScriptName: String? {
          switch self {
          case .interRegular: ChapterFonts.interRegular
          case .interSemiBold: ChapterFonts.interSemiBold
          case .timesRegular: ChapterFonts.timesRegular
          case .monospaced: nil
          }
        }
      }

      public let face: Face
      /// Point size at the default text size (Large).
      public let size: CGFloat
      /// Design line height at the default text size.
      public let lineHeight: CGFloat
      /// The Dynamic Type style this style scales with; nil keeps the size fixed.
      public let relativeTo: SwiftUI.Font.TextStyle?

      public init(
        face: Face, size: CGFloat, lineHeight: CGFloat, relativeTo: SwiftUI.Font.TextStyle?
      ) {
        self.face = face
        self.size = size
        self.lineHeight = lineHeight
        self.relativeTo = relativeTo
      }

      /// The SwiftUI font, scaled with Dynamic Type unless `relativeTo` is nil. The monospaced
      /// face uses the system font of its text style, whose default size equals `size`.
      public var font: SwiftUI.Font {
        switch (face.postScriptName, relativeTo) {
        case (let name?, let style?): .custom(name, size: size, relativeTo: style)
        case (let name?, nil): .custom(name, fixedSize: size)
        case (nil, let style?): .system(style, design: .monospaced)
        case (nil, nil): .system(size: size, design: .monospaced)
        }
      }

      /// The UIKit font at the text size of `traits` (the current one when nil).
      public func uiFont(compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        let base: UIFont
        if let name = face.postScriptName, let font = UIFont(name: name, size: size) {
          base = font
        } else if face == .monospaced {
          base = .monospacedSystemFont(ofSize: size, weight: .regular)
        } else {
          // Inter not registered: the system font keeps the screen readable.
          base = .systemFont(ofSize: size, weight: face == .interSemiBold ? .semibold : .regular)
        }
        guard let relativeTo else { return base }
        return UIFontMetrics(forTextStyle: relativeTo.uiTextStyle)
          .scaledFont(for: base, compatibleWith: traits)
      }

      /// The design line height at the text size of `traits`.
      public func scaledLineHeight(compatibleWith traits: UITraitCollection? = nil) -> CGFloat {
        guard let relativeTo else { return lineHeight }
        return UIFontMetrics(forTextStyle: relativeTo.uiTextStyle)
          .scaledValue(for: lineHeight, compatibleWith: traits)
      }

      /// Extra space between wrapped lines so they sit `lineHeight` apart.
      public func lineSpacing(compatibleWith traits: UITraitCollection? = nil) -> CGFloat {
        max(0, scaledLineHeight(compatibleWith: traits) - uiFont(compatibleWith: traits).lineHeight)
      }

      // §2.2, phone-capture.
      /// Times New Roman 34/41: Captures, New capture, What are you scanning?, every large title.
      public static let largeTitle = TextStyle(
        face: .timesRegular, size: 34, lineHeight: 41, relativeTo: .largeTitle)
      /// Inter SemiBold 17/22: inline navigation title, sheet titles.
      public static let navTitle = TextStyle(
        face: .interSemiBold, size: 17, lineHeight: 22, relativeTo: .headline)
      /// Inter 17/22: row titles, values, text fields.
      public static let body = TextStyle(
        face: .interRegular, size: 17, lineHeight: 22, relativeTo: .body)
      /// Inter SemiBold 17/22: primary buttons, the address row, alert titles.
      public static let bodyEmphasis = TextStyle(
        face: .interSemiBold, size: 17, lineHeight: 22, relativeTo: .body)
      /// Inter 15/20: statuses, banners, segments, tinted row buttons, subtitles under titles.
      public static let subhead = TextStyle(
        face: .interRegular, size: 15, lineHeight: 20, relativeTo: .subheadline)
      /// Inter SemiBold 15/20: the selected segment, live-scan title and coaching pills.
      public static let subheadEmphasis = TextStyle(
        face: .interSemiBold, size: 15, lineHeight: 20, relativeTo: .subheadline)
      /// Inter 13/17: row subtitles, section headers (uppercased), footnotes, captions.
      public static let footnote = TextStyle(
        face: .interRegular, size: 13, lineHeight: 17, relativeTo: .footnote)
      /// Inter SemiBold 13/17: avatar initials.
      public static let footnoteEmphasis = TextStyle(
        face: .interSemiBold, size: 13, lineHeight: 17, relativeTo: .footnote)
      /// Inter 12/16: live-scan count labels, Field controls section headers (uppercased).
      public static let caption = TextStyle(
        face: .interRegular, size: 12, lineHeight: 16, relativeTo: .caption)
      /// Inter SemiBold 22/28: live-scan counts.
      public static let count = TextStyle(
        face: .interSemiBold, size: 22, lineHeight: 28, relativeTo: .title2)
      /// Inter SemiBold 7, fixed: the "N" of the 32 pt compass glyph.
      public static let glyphN = TextStyle(
        face: .interSemiBold, size: 7, lineHeight: 7, relativeTo: nil)
      /// SF Mono 15/20: the live-scan timer.
      public static let mono = TextStyle(
        face: .monospaced, size: 15, lineHeight: 20, relativeTo: .subheadline)

      // The union of critique R-18: phone-field §1.2 and phone-package §2.3.
      /// Inter 26: feet, inches, mm and m fields of the field-control entry sheet.
      public static let entryValue = TextStyle(
        face: .interRegular, size: 26, lineHeight: 32, relativeTo: .title2)
      /// Inter SemiBold 20/25: the verdict word ("Limited") on Verdict received.
      public static let verdictWord = TextStyle(
        face: .interSemiBold, size: 20, lineHeight: 25, relativeTo: .title3)
      /// SF Mono 13/17: the feet-inches line of a Field controls row.
      public static let mono13 = TextStyle(
        face: .monospaced, size: 13, lineHeight: 17, relativeTo: .footnote)
      /// SF Mono 11/13: the time pill on a photo.
      public static let mono11 = TextStyle(
        face: .monospaced, size: 11, lineHeight: 13, relativeTo: .caption2)

      /// Every named style, for tests and the type specimen.
      public static let all: [(name: String, style: TextStyle)] = [
        ("largeTitle", largeTitle), ("navTitle", navTitle), ("body", body),
        ("bodyEmphasis", bodyEmphasis), ("subhead", subhead), ("subheadEmphasis", subheadEmphasis),
        ("footnote", footnote), ("footnoteEmphasis", footnoteEmphasis), ("caption", caption),
        ("count", count), ("glyphN", glyphN), ("mono", mono), ("entryValue", entryValue),
        ("verdictWord", verdictWord), ("mono13", mono13), ("mono11", mono11),
      ]
    }

    /// The type styles as SwiftUI fonts (`.font(ChapterTheme.Font.body)`). Use
    /// `.chapterTextStyle(.body)` for text that wraps, so the design line height applies.
    public enum Font {
      public static let largeTitle = TextStyle.largeTitle.font
      public static let navTitle = TextStyle.navTitle.font
      public static let body = TextStyle.body.font
      public static let bodyEmphasis = TextStyle.bodyEmphasis.font
      public static let subhead = TextStyle.subhead.font
      public static let subheadEmphasis = TextStyle.subheadEmphasis.font
      public static let footnote = TextStyle.footnote.font
      public static let footnoteEmphasis = TextStyle.footnoteEmphasis.font
      public static let caption = TextStyle.caption.font
      public static let count = TextStyle.count.font
      public static let glyphN = TextStyle.glyphN.font
      public static let mono = TextStyle.mono.font
      public static let entryValue = TextStyle.entryValue.font
      public static let verdictWord = TextStyle.verdictWord.font
      public static let mono13 = TextStyle.mono13.font
      public static let mono11 = TextStyle.mono11.font
    }

    /// Spacing, sizes and radii in points (§2.3 plus the union of critique R-18). Heights are
    /// minimums: rows and buttons grow with Dynamic Type.
    public enum Metric {
      // Screen
      /// Side padding of every screen (v1 used 20).
      public static let screenPadding: CGFloat = 16
      /// Content top padding under the title: home and step 1.
      public static let contentTop: CGFloat = 16
      /// Content top padding under the title: step 2.
      public static let contentTopCompact: CGFloat = 14
      /// Content top padding under the title: the capture overview.
      public static let contentTopOverview: CGFloat = 12
      /// Gap between sections: home and step 1.
      public static let sectionGap: CGFloat = 18
      /// Gap between sections: step 2.
      public static let sectionGapCompact: CGFloat = 14
      /// Gap between sections: the capture overview.
      public static let sectionGapOverview: CGFloat = 10
      /// Gap from a large title to the subtitle under it (the first content line).
      public static let subtitleTop: CGFloat = 8
      /// Width of the content column on iPad.
      public static let contentMaxWidth: CGFloat = 600

      // Sections and cards
      /// Section header (and footer) to the card.
      public static let sectionHeaderGap: CGFloat = 6
      /// The Field controls list's 12 pt header to its card.
      public static let sectionHeaderGapCompact: CGFloat = 4
      /// Section header and footnote inset inside the card edge.
      public static let sectionInset: CGFloat = 16
      public static let cardRadius: CGFloat = 12
      public static let cardBorder: CGFloat = 1
      public static let separator: CGFloat = 1

      // Rows
      /// Gap between the parts of a row.
      public static let rowGap: CGFloat = 12
      /// Gap between a row's title and subtitle.
      public static let rowTitleGap: CGFloat = 2
      /// Gap between title, subtitle and bar of a row with a progress bar.
      public static let progressRowGap: CGFloat = 6
      public static let rowPadding: CGFloat = 16
      public static let navigationRowHeight: CGFloat = 52
      public static let navigationRowVerticalPadding: CGFloat = 8
      public static let progressRowVerticalPadding: CGFloat = 10
      public static let overviewRowHeight: CGFloat = 48
      public static let overviewRowVerticalPadding: CGFloat = 6
      public static let valueRowHeight: CGFloat = 48
      public static let compassRowHeight: CGFloat = 56
      public static let textAreaHeight: CGFloat = 72
      public static let textAreaVerticalPadding: CGFloat = 14

      // Bottom action bar
      public static let actionBarTop: CGFloat = 12
      public static let actionBarBottom: CGFloat = 8
      public static let actionBarGap: CGFloat = 10

      // Controls
      /// Primary, tinted and on-dark buttons (v1 was 56).
      public static let primaryButtonHeight: CGFloat = 52
      public static let buttonRadius: CGFloat = 12
      public static let textButtonHeight: CGFloat = 44
      /// Tinted row buttons ("Read again", "Take photo").
      public static let rowActionHeight: CGFloat = 44
      public static let rowActionPadding: CGFloat = 12
      public static let rowActionRadius: CGFloat = 8
      /// The button inside the live-scan tracking-lost card.
      public static let cardActionHeight: CGFloat = 44
      public static let cardActionPadding: CGFloat = 16
      public static let cardActionRadius: CGFloat = 10
      public static let segmentedHeight: CGFloat = 44
      public static let segmentedPadding: CGFloat = 2
      public static let segmentedRadius: CGFloat = 9
      public static let segmentRadius: CGFloat = 7
      public static let chipHeight: CGFloat = 44
      public static let chipRadius: CGFloat = 8
      /// Chip padding: rooms 14, subjects 12.
      public static let roomChipPadding: CGFloat = 14
      public static let subjectChipPadding: CGFloat = 12
      public static let touchTarget: CGFloat = 44

      // Glyphs
      public static let statusGlyph: CGFloat = 10
      /// Status glyph of the verdict card.
      public static let verdictGlyph: CGFloat = 14
      public static let statusGlyphGap: CGFloat = 5
      public static let chevronWidth: CGFloat = 8
      public static let chevronHeight: CGFloat = 14
      /// The add, remove, plus, equals and minus circles.
      public static let circleGlyph: CGFloat = 22
      public static let compassGlyph: CGFloat = 32
      public static let compassPillGlyph: CGFloat = 14

      // Progress, banners, notes
      public static let progressBarHeight: CGFloat = 4
      /// The upload progress bar of Package status.
      public static let progressBarHeightLarge: CGFloat = 8
      public static let bannerPadding: CGFloat = 16
      public static let bannerVerticalPadding: CGFloat = 12
      public static let bannerGap: CGFloat = 10
      public static let bannerIcon: CGFloat = 18
      public static let infoNoteHorizontalPadding: CGFloat = 14
      public static let infoNoteVerticalPadding: CGFloat = 10
      public static let infoNoteIcon: CGFloat = 16

      // Sheets
      public static let sheetRadius: CGFloat = 16
      public static let sheetBarHeight: CGFloat = 52
      public static let sheetBarButtonWidth: CGFloat = 60
      public static let grabberWidth: CGFloat = 36
      public static let grabberHeight: CGFloat = 5
      public static let grabberTop: CGFloat = 6

      // Navigation bar
      public static let avatar: CGFloat = 36
      /// The Chapter logo on the Captures home.
      public static let logoHeight: CGFloat = 26
      /// The Chapter logo on the sign-in screen.
      public static let logoHeightLarge: CGFloat = 40
    }
  }

  extension SwiftUI.Font.TextStyle {
    /// The UIKit text style with the same Dynamic Type curve.
    var uiTextStyle: UIFont.TextStyle {
      switch self {
      case .largeTitle: .largeTitle
      case .title: .title1
      case .title2: .title2
      case .title3: .title3
      case .headline: .headline
      case .subheadline: .subheadline
      case .callout: .callout
      case .footnote: .footnote
      case .caption: .caption1
      case .caption2: .caption2
      default: .body
      }
    }
  }

  private struct ChapterTextStyleModifier: ViewModifier {
    let style: ChapterTheme.TextStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
      let traits = UITraitCollection(
        preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
      content
        .font(style.font)
        .lineSpacing(style.lineSpacing(compatibleWith: traits))
    }
  }

  extension View {
    /// Sets the font of `style` and spaces wrapped lines at its design line height.
    public func chapterTextStyle(_ style: ChapterTheme.TextStyle) -> some View {
      modifier(ChapterTextStyleModifier(style: style))
    }
  }
#endif
