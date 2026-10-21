#if canImport(UIKit) && os(iOS)
  import CoreText
  import UIKit
  import XCTest

  @testable import ChapterUI

  final class ChapterFontsTests: XCTestCase {
    func testBundlesBothInterFiles() throws {
      let names = ChapterFonts.fontURLs.map(\.lastPathComponent)
      XCTAssertEqual(names, ["Inter-Regular.ttf", "Inter-SemiBold.ttf"])
    }

    func testFilesAreStaticInterInstancesWithTheirPostScriptNames() throws {
      let expected = [
        ("Inter-Regular", "Inter", 400.0), ("Inter-SemiBold", "Inter", 600.0),
      ]
      let urls = ChapterFonts.fontURLs
      XCTAssertEqual(urls.count, expected.count)
      for (url, (postScript, family, weight)) in zip(urls, expected) {
        let descriptors = try XCTUnwrap(
          CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
        XCTAssertEqual(descriptors.count, 1, "\(url.lastPathComponent) holds one face")
        let font = CTFontCreateWithFontDescriptor(try XCTUnwrap(descriptors.first), 17, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, postScript)
        XCTAssertEqual(CTFontCopyFamilyName(font) as String, family)
        // Static instances: no variation axes left.
        XCTAssertNil(CTFontCopyVariationAxes(font), "\(postScript) is not variable")
        let os2 = try XCTUnwrap(CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?)
        let weightClass = Double(UInt16(os2[4]) << 8 | UInt16(os2[5]))
        XCTAssertEqual(weightClass, weight, "\(postScript) usWeightClass")
      }
    }

    func testRegisterIsIdempotent() {
      XCTAssertTrue(ChapterFonts.register())
      XCTAssertTrue(ChapterFonts.register(), "a second call is not an error")
      XCTAssertTrue(ChapterFonts.isAvailable)
      // Registering the same files again reports "already registered", which is not a failure.
      XCTAssertEqual(ChapterFonts.registerFiles(ChapterFonts.fontURLs), [])
    }

    func testRegisterFilesReportsAFileThatIsNotAFont() throws {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-font.ttf")
      try Data("not a font".utf8).write(to: url)
      defer { try? FileManager.default.removeItem(at: url) }
      let failures = ChapterFonts.registerFiles([url])
      XCTAssertEqual(failures.count, 1)
      XCTAssertTrue(failures[0].hasPrefix("not-a-font.ttf: "), failures[0])
    }

    func testFontsCoverTheCharactersThePhoneScreensUse() throws {
      ChapterFonts.register()
      // Middle dot, degree, plus-minus, ellipsis, en and em dash, right arrow, typographic
      // apostrophe, primes in ASCII, and accented Latin from addresses.
      let text = "· ° ± … – — → ’ ' \" Šibenik Zürich Ñ é"
      for name in [ChapterFonts.interRegular, ChapterFonts.interSemiBold] {
        let font = CTFontCreateWithName(name as CFString, 17, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name)
        var characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        XCTAssertTrue(
          CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count),
          "\(name) has a glyph for every character of \(text)")
      }
    }

    func testTimesNewRomanShipsWithIOS() {
      XCTAssertNotNil(UIFont(name: ChapterFonts.timesRegular, size: 34))
    }
  }
#endif
