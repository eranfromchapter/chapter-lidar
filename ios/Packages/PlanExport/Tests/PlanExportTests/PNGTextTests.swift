import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// plan.png labels: Inter outlines read from the fonts the PDFs embed, set as the PDFs set them
/// (`RasterCanvas`).
final class PNGTextTests: XCTestCase {
  private let regular = GlyphOutlines.interRegular
  private let semiBold = GlyphOutlines.interSemiBold

  /// A render read back in grey (Rec. 709), one byte per pixel.
  private struct Gray {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(_ canvas: RasterCanvas) {
      width = canvas.width
      height = canvas.height
      pixels = canvas.grayPixels
    }
  }

  /// Ink extent of one glyph in font units: (minX, maxX, minY, maxY).
  private func bounds(_ font: GlyphOutlines, _ character: Unicode.Scalar) -> [Double] {
    let points = font.glyphs[font.glyph(for: character)].flatMap { $0 }
    return [
      points.map(\.x).min() ?? 0, points.map(\.x).max() ?? 0, points.map(\.y).min() ?? 0,
      points.map(\.y).max() ?? 0,
    ]
  }

  /// Columns and rows of the pixels more than half covered by black ink.
  private func inkBox(_ canvas: Gray) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
    var box: (minX: Int, maxX: Int, minY: Int, maxY: Int)?
    for y in 0..<canvas.height {
      for x in 0..<canvas.width where canvas.pixels[y * canvas.width + x] < 128 {
        box = (
          min(box?.minX ?? x, x), max(box?.maxX ?? x, x), min(box?.minY ?? y, y),
          max(box?.maxY ?? y, y)
        )
      }
    }
    return box
  }

  /// `text` drawn black on a 600 x 300 px canvas, its baseline at row 200, through the
  /// canvas's drawing of a `DrawingText` (pixels as millimetres, y down).
  private func canvas(
    _ text: String, x: Double = 40, emPixels: Double = 100, rotation: Double = 0,
    centered: Bool = false, bold: Bool = false, letterSpacing: Double = 0
  ) -> Gray {
    var canvas = RasterCanvas(width: 600, height: 300)
    canvas.draw(
      [
        .text(
          DrawingText(
            text, position: DrawingPoint(x: x, y: 200), size: emPixels,
            rotationDegrees: rotation, anchor: centered ? .center : .leading,
            font: bold ? .interSemiBold : .interRegular, letterSpacing: letterSpacing,
            color: DrawingColor(0, 0, 0), layer: .roomLabel))
      ], scale: 1
    ) { Point2(x: $0.x, y: $0.y) }
    return Gray(canvas)
  }

  func testOutlinesAreTheInterFontsThePDFsEmbed() {
    for (font, embedded) in [
      (regular, ChapterBrandAssets.interRegular), (semiBold, ChapterBrandAssets.interSemiBold),
    ] {
      XCTAssertGreaterThan(font.unitsPerEm, 0)
      // Every printable ASCII character has its own glyph, as wide as the PDF says (the PDF
      // widths are rounded to 1/1000 em).
      for code in 33...126 {
        let character = Unicode.Scalar(UInt8(code))
        let glyph = font.glyph(for: character)
        XCTAssertFalse(font.glyphs[glyph].isEmpty, "\(character) has an outline")
        XCTAssertEqual(
          font.advances[glyph] * 1000 / font.unitsPerEm, Double(embedded.widths[code - 32]),
          accuracy: 0.5, "\(embedded.postScriptName) \(character)")
      }
      // Capitals stand at the cap height of the PDF font descriptor.
      let capital = bounds(font, "H")
      XCTAssertEqual(
        (capital[3] - capital[2]) * 1000 / font.unitsPerEm, Double(embedded.capHeight),
        accuracy: 1)
      XCTAssertEqual(font.glyphs[font.glyph(for: "o")].count, 2, "o has an outer and inner contour")
      // Accented letters are composites: the base letter plus the accent above it.
      let accented = bounds(font, "\u{E9}")
      XCTAssertGreaterThan(
        font.glyphs[font.glyph(for: "\u{E9}")].count, font.glyphs[font.glyph(for: "e")].count)
      XCTAssertGreaterThan(accented[3], bounds(font, "e")[3] + font.unitsPerEm / 10)
      XCTAssertNotEqual(font.glyph(for: "\u{B2}"), font.glyph(for: "?"), "superscript two")
      XCTAssertEqual(font.glyph(for: "\u{2713}"), font.glyph(for: "?"))
      XCTAssertTrue(font.glyphs[font.glyph(for: " ")].isEmpty)
    }
  }

  func testNonzeroFillPaintsOverlapsOnceAndCoversEdgesExactly() {
    // Inter's outlines overlap (its e is one self-crossing contour): two overlapping squares
    // wound the same way are one shape, painted once, with no hole where they cross.
    var canvas = RasterCanvas(width: 40, height: 20)
    func square(_ x: Double) -> [Point2] {
      [
        Point2(x: x, y: 2), Point2(x: x + 10, y: 2), Point2(x: x + 10, y: 12),
        Point2(x: x, y: 12),
      ]
    }
    canvas.fill([square(2), square(7)], color: DrawingColor(0.5, 0.5, 0.5))
    let row = Array(Gray(canvas).pixels[(5 * 40)..<(6 * 40)])
    XCTAssertEqual(Array(row[2..<17]), [UInt8](repeating: 128, count: 15))
    XCTAssertEqual(row[1], 255)
    XCTAssertEqual(row[17], 255)
    // An edge through the middle of a pixel covers half of it.
    var half = RasterCanvas(width: 10, height: 10)
    half.fill(
      [[Point2(x: 2.5, y: 0), Point2(x: 6, y: 0), Point2(x: 6, y: 10), Point2(x: 2.5, y: 10)]],
      color: DrawingColor(0, 0, 0))
    XCTAssertEqual(Array(Gray(half).pixels[0..<10]), [255, 255, 128, 0, 0, 0, 255, 255, 255, 255])
  }

  func testCanvasTextHasInterCapitalsAndLowercase() throws {
    let scale = 100 / regular.unitsPerEm
    let capital = try XCTUnwrap(inkBox(canvas("H")))
    let lower = try XCTUnwrap(inkBox(canvas("x")))
    // Both sit on the baseline (row 200); H is the cap height tall, x the x-height.
    XCTAssertEqual(capital.maxY, 199)
    XCTAssertEqual(lower.maxY, 199)
    let h = bounds(regular, "H")
    let x = bounds(regular, "x")
    XCTAssertEqual(Double(capital.maxY + 1 - capital.minY), (h[3] - h[2]) * scale, accuracy: 1)
    XCTAssertEqual(Double(lower.maxY + 1 - lower.minY), (x[3] - x[2]) * scale, accuracy: 1)
    XCTAssertLessThan(lower.maxY - lower.minY, capital.maxY - capital.minY - 10)
    // The ink starts at the glyph's left side bearing from the origin (x = 40).
    XCTAssertEqual(Double(capital.minX), 40 + h[0] * scale, accuracy: 1)
    XCTAssertEqual(Double(capital.maxX + 1), 40 + h[1] * scale, accuracy: 1)
  }

  func testCanvasTextAdvancesByThePDFWidths() throws {
    // Two l stems: the second starts one PDF width of l after the first.
    let text = canvas("ll")
    let row = 160
    var starts: [Int] = []
    for column in 0..<text.width
    where text.pixels[row * text.width + column] < 128
      && (column == 0 || text.pixels[row * text.width + column - 1] >= 128)
    {
      starts.append(column)
    }
    XCTAssertEqual(starts.count, 2)
    let advance = FontMetrics.width("l", size: 100)
    XCTAssertEqual(Double(starts[1] - starts[0]), advance, accuracy: 1)
  }

  func testCanvasTextIsAntiAliasedCentredRotatedAndBold() throws {
    let text = canvas("Hallway 4.48 m\u{B2}")
    XCTAssertTrue(text.pixels.contains(0), "solid ink")
    XCTAssertTrue(text.pixels.contains { $0 > 0 && $0 < 255 }, "anti-aliased edges")
    // Centred at x is the same drawing as set from x minus half its PDF width.
    let width = FontMetrics.width("Hallway", size: 50)
    XCTAssertEqual(
      canvas("Hallway", x: 300, emPixels: 50, centered: true).pixels,
      canvas("Hallway", x: 300 - width / 2, emPixels: 50).pixels)
    // Turned 90 degrees counter-clockwise, H runs up the page: its ink box turns too.
    let upright = try XCTUnwrap(inkBox(canvas("H", x: 300)))
    let turned = try XCTUnwrap(inkBox(canvas("H", x: 300, rotation: 90)))
    XCTAssertEqual(turned.maxX - turned.minX, upright.maxY - upright.minY, accuracy: 2)
    XCTAssertEqual(turned.maxY - turned.minY, upright.maxX - upright.minX, accuracy: 2)
    XCTAssertEqual(turned.maxX, 299, "the baseline is the right edge")
    // SemiBold carries more ink than Regular.
    func ink(_ canvas: Gray) -> Int { canvas.pixels.reduce(0) { $0 + 255 - Int($1) } }
    XCTAssertGreaterThan(
      Double(ink(canvas("Hallway", bold: true))), Double(ink(canvas("Hallway"))) * 1.15)
    // A character WinAnsi lacks draws as ?, as in the PDF.
    XCTAssertEqual(canvas("\u{2713}").pixels, canvas("?").pixels)
  }

  func testLetterSpacingAddsItsSpaceAfterEachCharacter() throws {
    // "HH" spaced 20 px: the second H ends 20 px further right; the first does not move.
    let plain = try XCTUnwrap(inkBox(canvas("HH", bold: true)))
    let spaced = try XCTUnwrap(inkBox(canvas("HH", bold: true, letterSpacing: 20)))
    XCTAssertEqual(spaced.minX, plain.minX)
    XCTAssertEqual(Double(spaced.maxX - plain.maxX), 20, accuracy: 1)
  }
}
