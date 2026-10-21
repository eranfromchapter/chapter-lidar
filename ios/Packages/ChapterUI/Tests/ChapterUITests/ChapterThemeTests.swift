#if canImport(UIKit) && os(iOS)
  import SwiftUI
  import UIKit
  import XCTest

  @testable import ChapterUI

  final class ChapterThemeTests: XCTestCase {
    override func setUp() {
      super.setUp()
      ChapterFonts.register()
    }

    /// The colour table of phone-capture §2.1 and phone-field §1.1, value for value.
    func testSwatchesHaveTheDesignValues() {
      let expected: [ChapterTheme.Swatch: (UInt32, Double)] = [
        .ink: (0x1F2429, 1), .ground: (0xF5EFE6, 1), .surface: (0xFAF5EE, 1),
        .nude: (0xE8DDD0, 1), .line: (0xD9CCBC, 1), .muted: (0x6B6557, 1),
        .disabledText: (0x4E493F, 1), .chevron: (0xB9AFA2, 1), .ready: (0x2E5E2E, 1),
        .limited: (0x9A6A1E, 1), .limitedText: (0x7A5214, 1), .blocked: (0x8B2E2E, 1),
        .logo: (0x231F20, 1), .scanWell: (0x2B3137, 1), .scanWellDimmed: (0x23282D, 1),
        .scanWellBorder: (0x3A424A, 1), .onDarkCaption: (0xD9CCBC, 1),
        .onDarkPill: (0xFAF5EE, 0.14), .alertCard: (0xFAF5EE, 0.97), .photoPill: (0x1F2429, 0.70),
      ]
      XCTAssertEqual(Set(expected.keys), Set(ChapterTheme.Swatch.allCases))
      for swatch in ChapterTheme.Swatch.allCases {
        let (hex, opacity) = expected[swatch]!
        XCTAssertEqual(swatch.hex, hex, "\(swatch)")
        XCTAssertEqual(swatch.opacity, opacity, "\(swatch)")
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(swatch.uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(Int((red * 255).rounded()), Int(hex >> 16 & 0xFF), "\(swatch) red")
        XCTAssertEqual(Int((green * 255).rounded()), Int(hex >> 8 & 0xFF), "\(swatch) green")
        XCTAssertEqual(Int((blue * 255).rounded()), Int(hex & 0xFF), "\(swatch) blue")
        XCTAssertEqual(Double(alpha), opacity, accuracy: 0.0001, "\(swatch) alpha")
      }
    }

    /// The type table of phone-capture §2.2 plus the union of critique R-18.
    func testTextStylesHaveTheDesignFacesSizesAndLineHeights() {
      typealias Style = ChapterTheme.TextStyle
      let expected: [String: (Style.Face, CGFloat, CGFloat, Font.TextStyle?)] = [
        "largeTitle": (.timesRegular, 34, 41, .largeTitle),
        "navTitle": (.interSemiBold, 17, 22, .headline),
        "body": (.interRegular, 17, 22, .body),
        "bodyEmphasis": (.interSemiBold, 17, 22, .body),
        "subhead": (.interRegular, 15, 20, .subheadline),
        "subheadEmphasis": (.interSemiBold, 15, 20, .subheadline),
        "footnote": (.interRegular, 13, 17, .footnote),
        "footnoteEmphasis": (.interSemiBold, 13, 17, .footnote),
        "caption": (.interRegular, 12, 16, .caption),
        "count": (.interSemiBold, 22, 28, .title2),
        "glyphN": (.interSemiBold, 7, 7, nil),
        "mono": (.monospaced, 15, 20, .subheadline),
        "entryValue": (.interRegular, 26, 32, .title2),
        "verdictWord": (.interSemiBold, 20, 25, .title3),
        "mono13": (.monospaced, 13, 17, .footnote),
        "mono11": (.monospaced, 11, 13, .caption2),
      ]
      XCTAssertEqual(Set(Style.all.map(\.name)), Set(expected.keys))
      for (name, style) in Style.all {
        let (face, size, lineHeight, relativeTo) = expected[name]!
        XCTAssertEqual(style.face, face, name)
        XCTAssertEqual(style.size, size, name)
        XCTAssertEqual(style.lineHeight, lineHeight, name)
        XCTAssertEqual(style.relativeTo, relativeTo, name)
      }
    }

    func testFacesResolveToInterTimesAndMonospacedFonts() {
      let large = UITraitCollection(preferredContentSizeCategory: .large)
      for (name, style) in ChapterTheme.TextStyle.all {
        let font = style.uiFont(compatibleWith: large)
        XCTAssertEqual(font.pointSize, style.size, accuracy: 0.01, "\(name) at Large")
        switch style.face {
        case .interRegular: XCTAssertEqual(font.fontName, "Inter-Regular", name)
        case .interSemiBold: XCTAssertEqual(font.fontName, "Inter-SemiBold", name)
        case .timesRegular: XCTAssertEqual(font.fontName, "TimesNewRomanPSMT", name)
        case .monospaced:
          XCTAssertTrue(
            font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace), "\(name) is monospaced")
        }
      }
    }

    /// The SwiftUI font of a monospaced style is the system font of its text style, so that
    /// style's default size must be the design size.
    func testMonospacedStylesMatchTheirTextStyleSize() {
      let large = UITraitCollection(preferredContentSizeCategory: .large)
      for (name, style) in ChapterTheme.TextStyle.all where style.face == .monospaced {
        let textStyle = style.relativeTo!.uiTextStyle
        let systemSize = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: large)
          .pointSize
        XCTAssertEqual(systemSize, style.size, accuracy: 0.01, name)
      }
    }

    func testStylesScaleWithDynamicTypeExceptTheCompassN() {
      let ax3 = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
      XCTAssertGreaterThan(ChapterTheme.TextStyle.body.uiFont(compatibleWith: ax3).pointSize, 30)
      XCTAssertGreaterThan(
        ChapterTheme.TextStyle.body.scaledLineHeight(compatibleWith: ax3), 22 * 1.5)
      XCTAssertEqual(ChapterTheme.TextStyle.glyphN.uiFont(compatibleWith: ax3).pointSize, 7)
    }

    func testLineSpacingBringsLinesToTheDesignLineHeight() {
      let large = UITraitCollection(preferredContentSizeCategory: .large)
      for (name, style) in ChapterTheme.TextStyle.all {
        let font = style.uiFont(compatibleWith: large)
        let spacing = style.lineSpacing(compatibleWith: large)
        XCTAssertGreaterThanOrEqual(spacing, 0, name)
        if font.lineHeight < style.lineHeight {
          XCTAssertEqual(font.lineHeight + spacing, style.lineHeight, accuracy: 0.01, name)
        }
      }
    }

    func testMetricsOfTheTokenTable() {
      typealias Metric = ChapterTheme.Metric
      XCTAssertEqual(Metric.screenPadding, 16)
      XCTAssertEqual(Metric.primaryButtonHeight, 52)
      XCTAssertEqual(Metric.segmentedHeight, 44)
      XCTAssertEqual(Metric.navigationRowHeight, 52)
      XCTAssertEqual(Metric.overviewRowHeight, 48)
      XCTAssertEqual(Metric.valueRowHeight, 48)
      XCTAssertEqual(Metric.compassRowHeight, 56)
      XCTAssertEqual(Metric.cardRadius, 12)
      XCTAssertEqual(Metric.sheetRadius, 16)
      XCTAssertEqual(Metric.touchTarget, 44)
      XCTAssertEqual(Metric.statusGlyph, 10)
      XCTAssertEqual(Metric.verdictGlyph, 14)
      XCTAssertEqual(Metric.circleGlyph, 22)
      XCTAssertEqual(Metric.progressBarHeight, 4)
      XCTAssertEqual(Metric.progressBarHeightLarge, 8)
    }

    func testAvatarInitials() {
      XCTAssertEqual(AvatarButton.initials(for: "Dana Ruiz"), "DR")
      XCTAssertEqual(AvatarButton.initials(for: "Field test"), "FT")
      XCTAssertEqual(AvatarButton.initials(for: "  dana   maria ruiz "), "DM")
      XCTAssertEqual(AvatarButton.initials(for: "Operator"), "O")
      XCTAssertEqual(AvatarButton.initials(for: "élodie durand"), "ÉD")
      XCTAssertEqual(AvatarButton.initials(for: ""), "?")
      XCTAssertEqual(AvatarButton.initials(for: "   "), "?")
    }

    func testStatusColoursAndWords() {
      XCTAssertEqual(StatusKind.done.glyphColor, ChapterTheme.Color.ready)
      XCTAssertEqual(StatusKind.partly.glyphColor, ChapterTheme.Color.limited)
      XCTAssertEqual(StatusKind.partly.textColor, ChapterTheme.Color.limitedText)
      XCTAssertEqual(StatusKind.missing.textColor, ChapterTheme.Color.blocked)
      XCTAssertEqual(StatusKind.waiting.glyphColor, ChapterTheme.Color.muted)
      XCTAssertEqual(
        StatusKind.allCases.map(\.accessibilityWord), ["Done", "Partly", "Missing", "Optional"])
    }
  }
#endif
