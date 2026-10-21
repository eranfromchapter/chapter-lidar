#if canImport(UIKit) && os(iOS)
  import SwiftUI
  import XCTest

  @testable import ChapterUI

  @MainActor
  final class ChapterLogoTests: XCTestCase {
    func testLogoDataIsTheGeneratedLogo() {
      XCTAssertEqual(ChapterLogoData.logoWidth, 1756)
      XCTAssertEqual(ChapterLogoData.logoHeight, 635)
      // tools/brand/generate_plan_brand.py: "logo 148 paths 1756x635", the same as PlanExport.
      XCTAssertEqual(ChapterLogoData.logoPaths.count, 148)
      for path in ChapterLogoData.logoPaths {
        let commands = path.split(whereSeparator: \.isWhitespace).filter { Double($0) == nil }
        XCTAssertEqual(commands.first, "M")
        XCTAssertEqual(Set(commands).subtracting(["M", "C", "Z"]), [])
      }
    }

    func testPathsFillTheLogoBoxWithYFlipped() {
      let bounds = ChapterLogoPaths.paths.reduce(CGRect.null) { $0.union($1.boundingRect) }
      // The generator measured the box over every point, control points included; the curves
      // themselves stay inside it, within a couple of units of its edges.
      XCTAssertEqual(bounds.minX, 0, accuracy: 2)
      XCTAssertEqual(bounds.minY, 0, accuracy: 2)
      XCTAssertEqual(bounds.maxX, 1756, accuracy: 2)
      XCTAssertEqual(bounds.maxY, 635, accuracy: 2)
      XCTAssertGreaterThanOrEqual(bounds.minX, -0.01)
      XCTAssertLessThanOrEqual(bounds.maxY, 635.01)
      // "chapter" is above "RENOVATION": with y down, the first path (a letter of "chapter",
      // y up 561...) starts near the top of the box.
      let first = ChapterLogoPaths.paths[0].boundingRect
      XCTAssertLessThan(first.minY, 635 / 2)
    }

    func testParsesMoveCurveAndClose() {
      let path = ChapterLogoPaths.path(from: "M 0 10 C 1 9 2 8 3 7 Z", height: 10)
      var elements: [String] = []
      // swift-format-ignore: ReplaceForEachWithForLoop
      path.forEach { element in
        switch element {
        case .move(let to): elements.append("M \(to.x) \(to.y)")
        case .curve(let to, let c1, let c2):
          elements.append("C \(c1.x) \(c1.y) \(c2.x) \(c2.y) \(to.x) \(to.y)")
        case .closeSubpath: elements.append("Z")
        default: elements.append("?")
        }
      }
      XCTAssertEqual(elements, ["M 0.0 0.0", "C 1.0 1.0 2.0 2.0 3.0 3.0", "Z"])
    }

    func testSizesOfTheDesign() {
      XCTAssertEqual(ChapterLogo.aspectRatio, 1756.0 / 635.0, accuracy: 1e-9)
      // Captures home: 26 pt tall, 72 pt wide (the drawn wordmark's footprint).
      XCTAssertEqual(ChapterLogo.width(forHeight: 26), 72, accuracy: 0.2)
      XCTAssertEqual(ChapterLogo().height, 26)
      XCTAssertEqual(ChapterTheme.Metric.logoHeightLarge, 40)
    }
  }

  @MainActor
  final class ChapterAppearanceTests: XCTestCase {
    func testNavigationBarAppearance() throws {
      ChapterFonts.register()
      let appearance = ChapterAppearance.navigationBarAppearance()
      XCTAssertEqual(appearance.backgroundColor, ChapterTheme.Swatch.ground.uiColor)
      // No hairline under the bar (a clear shadow colour reads back as nil).
      XCTAssertTrue(appearance.shadowColor == nil || appearance.shadowColor == .clear)
      XCTAssertNil(appearance.shadowImage)

      let large = try XCTUnwrap(appearance.largeTitleTextAttributes[.font] as? UIFont)
      XCTAssertEqual(large.fontName, "TimesNewRomanPSMT")
      XCTAssertEqual(
        appearance.largeTitleTextAttributes[.foregroundColor] as? UIColor,
        ChapterTheme.Swatch.ink.uiColor)
      let title = try XCTUnwrap(appearance.titleTextAttributes[.font] as? UIFont)
      XCTAssertEqual(title.fontName, "Inter-SemiBold")
      let button = try XCTUnwrap(
        appearance.buttonAppearance.normal.titleTextAttributes[.font] as? UIFont)
      XCTAssertEqual(button.fontName, "Inter-Regular")
      let back = try XCTUnwrap(
        appearance.backButtonAppearance.normal.titleTextAttributes[.font] as? UIFont)
      XCTAssertEqual(back.fontName, "Inter-Regular")
      let done = try XCTUnwrap(
        appearance.doneButtonAppearance.normal.titleTextAttributes[.font] as? UIFont)
      XCTAssertEqual(done.fontName, "Inter-SemiBold")
    }

    func testScrollEdgeAppearanceDrawsNoBackground() throws {
      let appearance = ChapterAppearance.navigationBarAppearance(atScrollEdge: true)
      XCTAssertNil(appearance.backgroundColor)
      XCTAssertNil(appearance.backgroundEffect)
      XCTAssertTrue(appearance.shadowColor == nil || appearance.shadowColor == .clear)
      let large = try XCTUnwrap(appearance.largeTitleTextAttributes[.font] as? UIFont)
      XCTAssertEqual(large.fontName, "TimesNewRomanPSMT")
    }

    func testApplySetsEveryBarAppearanceAndIsRepeatable() throws {
      ChapterAppearance.apply()
      ChapterAppearance.apply()
      let bar = UINavigationBar.appearance()
      let opaque = [bar.standardAppearance, try XCTUnwrap(bar.compactAppearance)]
      let edge = [
        try XCTUnwrap(bar.scrollEdgeAppearance), try XCTUnwrap(bar.compactScrollEdgeAppearance),
      ]
      for appearance in opaque + edge {
        let large = try XCTUnwrap(appearance.largeTitleTextAttributes[.font] as? UIFont)
        XCTAssertEqual(large.fontName, "TimesNewRomanPSMT")
        let title = try XCTUnwrap(appearance.titleTextAttributes[.font] as? UIFont)
        XCTAssertEqual(title.fontName, "Inter-SemiBold")
      }
      for appearance in opaque {
        XCTAssertEqual(appearance.backgroundColor, ChapterTheme.Swatch.ground.uiColor)
      }
      for appearance in edge {
        XCTAssertNil(appearance.backgroundColor)
      }
      XCTAssertEqual(bar.tintColor, ChapterTheme.Swatch.ink.uiColor)
      XCTAssertTrue(ChapterFonts.isAvailable, "apply() registers the fonts it uses")
    }
  }
#endif
