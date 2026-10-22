import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// The PDF engine's colour, dash, cap and join, Bezier, clipping and rotated text operators.
final class PDFDrawingTests: XCTestCase {
  private func stream(_ draw: (PDFPage) -> Void) -> String {
    let page = PDFPage(width: 200, height: 100)
    draw(page)
    return String(decoding: page.content, as: UTF8.self)
  }

  func testRGBDashCapJoinAndStateOperators() {
    let text = stream { page in
      page.setFillRGB(0.36, 0.37, 0.42)
      page.setStrokeRGB(1, 0.5, 0)
      page.setDash([2, 1], phase: 0.5)
      page.setDash([])
      page.setLineCap(.round)
      page.setLineJoin(.bevel)
      page.setMiterLimit(4)
      page.saveState()
      page.restoreState()
    }
    XCTAssertEqual(
      text,
      "0.3600 0.3700 0.4200 rg\n1.0000 0.5000 0.0000 RG\n[2.000 1.000] 0.500 d\n[] 0.000 d\n"
        + "1 J\n2 j\n4.000 M\nq\nQ\n")
  }

  func testColourComponentsAreClamped() {
    let text = stream { $0.setFillRGB(-0.2, 1.4, 0.25) }
    XCTAssertEqual(text, "0.0000 1.0000 0.2500 rg\n")
  }

  func testPathsWithCurvesAndEveryPaintMode() {
    var path = PDFPage.Path()
    path.move(1, 2)
    path.line(3, 4)
    path.curve(5, 6, 7, 8, 9, 10)
    path.close()
    let text = stream { page in
      for paint in [
        PDFPage.Paint.fill, .fillEvenOdd, .stroke, .fillStroke, .fillEvenOddStroke,
      ] {
        page.path(path, paint: paint)
      }
    }
    let body = "1.000 2.000 m 3.000 4.000 l 5.000 6.000 7.000 8.000 9.000 10.000 c h"
    XCTAssertEqual(
      text, ["f", "f*", "S", "B", "B*"].map { "\(body) \($0)\n" }.joined())
  }

  func testClipIsWrappedInSaveAndRestore() {
    var clip = PDFPage.Path()
    clip.move(0, 0)
    clip.line(10, 0)
    clip.line(10, 10)
    clip.close()
    let text = stream { page in
      page.saveState()
      page.clip(clip)
      page.line((0, 0), (20, 20))
      page.restoreState()
      page.clip(clip, evenOdd: true)
    }
    let lines = text.split(separator: "\n").map(String.init)
    XCTAssertEqual(lines.first, "q")
    XCTAssertEqual(lines[1], "0.000 0.000 m 10.000 0.000 l 10.000 10.000 l h W n")
    XCTAssertEqual(lines[3], "Q")
    XCTAssertEqual(lines[4], "0.000 0.000 m 10.000 0.000 l 10.000 10.000 l h W* n")
  }

  func testArcsAndCirclesStayOnTheCircle() {
    // Every Bezier of a circle stays within 0.03 % of the radius along its length.
    for (start, end) in [(0.0, 360.0), (30.0, 100.0), (90.0, -45.0), (-10.0, 5.0)] {
      let radius = 50.0
      let beziers = PDFPage.arcBeziers(
        centerX: 10, centerY: -4, radius: radius, startDegrees: start, endDegrees: end)
      XCTAssertEqual(beziers.count, max(1, Int((abs(end - start) / 90).rounded(.up))))
      var previous = PDFPage.arcPoint(10, -4, radius, start)
      for b in beziers {
        for step in 0...20 {
          let t = Double(step) / 20
          let mt = 1 - t
          let x =
            mt * mt * mt * previous.0 + 3 * mt * mt * t * b.0 + 3 * mt * t * t * b.2
            + t * t * t * b.4
          let y =
            mt * mt * mt * previous.1 + 3 * mt * mt * t * b.1 + 3 * mt * t * t * b.3
            + t * t * t * b.5
          let r = ((x - 10) * (x - 10) + (y + 4) * (y + 4)).squareRoot()
          XCTAssertEqual(r, radius, accuracy: radius * 0.0003)
        }
        previous = (b.4, b.5)
      }
      let last = PDFPage.arcPoint(10, -4, radius, end)
      XCTAssertEqual(previous.0, last.0, accuracy: 1e-9)
      XCTAssertEqual(previous.1, last.1, accuracy: 1e-9)
    }
  }

  func testCircleIsFourCurvesClosed() {
    let text = stream { $0.circle(centerX: 0, centerY: 0, radius: 1, paint: .stroke) }
    XCTAssertTrue(text.hasPrefix("1.000 0.000 m "))
    XCTAssertEqual(text.components(separatedBy: " c").count - 1, 4)
    XCTAssertTrue(text.hasSuffix(" h S\n"))
  }

  func testRotatedCentredTextKeepsItsMiddleOnTheAnchor() {
    // A label turned 90 degrees and centred: the text matrix starts half its width below the
    // anchor, and the string is still extractable.
    let text = stream { page in
      page.setFillRGB(0.1, 0.1, 0.1)
      page.text("12' 6.6\"", x: 100, y: 50, size: 10, anchor: .center, rotation: 90)
    }
    let width = FontMetrics.width("12' 6.6\"", size: 10)
    XCTAssertTrue(
      text.contains(
        "0.00000 1.00000 -1.00000 0.00000 100.000 \(Format.fixed(50 - width / 2, 3)) Tm"),
      text)
    XCTAssertTrue(text.contains("(12' 6.6\") Tj ET"))
  }

  func testPlanSheetDrawsInTheSheetPalette() throws {
    // RGB only (no gray operators, no clip on a sheet that fits), every colour a design token
    // of the sheet or the logo's brand black.
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    let plan = PDFFile(try PlanSheetWriter.write(model: capture.model, context: context).file.data)
    let stream = try XCTUnwrap(plan.contentStreams.first)
    for op in [" g\n", " G\n", " W n"] {
      XCTAssertFalse(stream.contains(op), "plan-sheet.pdf uses \(op)")
    }
    let palette = ChapterBrand.Sheet.self
    let allowed = Set(
      [
        palette.ink, palette.muted, palette.line, palette.nude, palette.wet, palette.ground,
        palette.surface, ChapterBrand.ink,
      ].map { color in
        [color.red, color.green, color.blue].map { Format.fixed($0, 4) }.joined(separator: " ")
      })
    let used = Set(
      stream.split(separator: "\n").filter { $0.hasSuffix(" rg") || $0.hasSuffix(" RG") }
        .map { String($0.dropLast(3)) })
    XCTAssertTrue(used.isSubset(of: allowed), "\(used.subtracting(allowed))")
    XCTAssertTrue(used.contains(allowed.first { $0.hasPrefix("0.1216") }!), "ink #1F2429")
    XCTAssertEqual(ChapterBrand.tone(0), ChapterBrand.ink)
    XCTAssertEqual(ChapterBrand.tone(1), .white)
  }
}
