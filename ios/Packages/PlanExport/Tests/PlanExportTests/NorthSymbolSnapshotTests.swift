import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// Visual checks of the north symbol (compass §13.3): SVG references of the symbol in its three
/// states at 26, 32 and 40 pt turned by A = 0, 32 and 212.4, each also drawn beside the
/// artboard's own geometry (`northArrow` of the design bundle's canvas/plan-parts.js) and
/// compared pixel by pixel; one colour Floorplan page reference per state; and a grey-scale
/// render of the approximate state on that page, checked for a dashed ring and a hollow arrow.
/// References: `__Snapshots__/NorthSymbolSnapshotTests/`, recorded with `RECORD_SNAPSHOTS=1`.
final class NorthSymbolSnapshotTests: XCTestCase {
  private let point = 25.4 / 72
  /// The plan sheet's colours, as the artboard draws the symbol (compass §6.1, G1).
  private let page = DrawingColor(hex: 0xFAF5EE)
  private let ink = DrawingColor(hex: 0x1F2429)
  private let sizes = [26.0, 32.0, 40.0]
  private let angles = [0.0, 32.0, 212.4]

  private enum Kind: String, CaseIterable {
    case verified
    case approximate
    case notVerified = "not-verified"
  }

  private func symbol(_ kind: Kind, angle: Double) -> NorthSymbol {
    switch kind {
    case .verified: return NorthSymbol(state: .verified(heading: angle, accuracy: 8))
    case .approximate:
      return NorthSymbol(state: .approximate(heading: angle, accuracy: 12, source: .magnetic))
    case .notVerified: return NorthSymbol(state: .notVerified(.noReading, accuracy: nil))
    }
  }

  /// The paper a symbol is drawn on: its block with a 4 pt margin, and the centre of its box.
  private func frame(_ symbol: NorthSymbol, size: Double)
    -> (width: Double, height: Double, center: DrawingPoint)
  {
    let box = size * point
    let block = NorthArrow.blockSizeMM(symbol: symbol, boxMM: box, caption: true)
    let extent = NorthArrow.blockExtentMM(symbol: symbol, boxMM: box, caption: true)
    let margin = 4 * point
    let width = block.width + 2 * margin
    let height = block.height + 2 * margin
    return (width, height, DrawingPoint(x: width / 2, y: height - margin - extent.top))
  }

  private func items(_ symbol: NorthSymbol, size: Double, center: DrawingPoint) -> [DrawingItem] {
    NorthArrow.items(
      symbol: symbol, centerMM: center, boxMM: size * point, page: page, caption: true, ink: ink)
  }

  // MARK: The symbol

  func testSymbolMatchesItsSVGReferences() throws {
    for kind in Kind.allCases {
      var unturned: String?
      for size in sizes {
        for angle in angles {
          let symbol = symbol(kind, angle: angle)
          let (width, height, center) = frame(symbol, size: size)
          func n(_ value: Double) -> String { Format.fixed(value, 2) }
          var svg = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
          svg +=
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(width))mm\" "
            + "height=\"\(n(height))mm\" viewBox=\"0 0 \(n(width)) \(n(height))\">\n"
          // The not-verified box neither scales nor turns: one reference for every size and
          // angle.
          let title =
            kind == .notVerified
            ? "North symbol, \(kind.rawValue)"
            : "North symbol, \(kind.rawValue), \(Format.compact(size)) pt, "
              + "A \(Format.compact(angle))"
          svg += "  <title>\(title)</title>\n"
          svg +=
            "  <rect x=\"0\" y=\"0\" width=\"\(n(width))\" height=\"\(n(height))\" "
            + "fill=\"\(page.hexString)\"/>\n"
          svg += DrawingSVG.elements(
            items(symbol, size: size, center: center), minX: 0, maxY: height)
          svg += "</svg>\n"
          guard kind != .notVerified else {
            if let unturned {
              XCTAssertEqual(svg, unturned, "\(size) pt, A \(angle)")
            } else {
              unturned = svg
              SVGSnapshot.assertMatches(svg, named: "symbol-not-verified")
            }
            continue
          }
          SVGSnapshot.assertMatches(
            svg,
            named: "symbol-\(kind.rawValue)-\(Format.compact(size))pt-A\(Format.compact(angle))")
        }
      }
    }
  }

  /// The artboard's symbol (`northArrow` in the design bundle's canvas/plan-parts.js, read as
  /// data) built from its own SVG and CSS numbers, without NorthArrow: a `size` pt box showing
  /// the view box 0 0 32 32, turned by CSS `rotate(-A deg)` about its centre; in it
  /// `<circle cx=16 cy=18 r=10.5>` stroked 0.75 (dashed "1.6 1.6" for an approximate reading,
  /// from its rightmost point, clockwise on the page, as SVG draws a circle),
  /// `<polygon points="16,6.5 20.5,25.5 16,22 11.5,25.5">` with round joins, filled with the
  /// page colour when approximate, and the "N" at (16, 4.6), centred, 6 units; under the box,
  /// 2 pt down (the column's gap), the caption: 7.5 pt lines in 9 pt line boxes, each baseline
  /// placed by the CSS line box (half-leading with Inter's ascent and descent). The not-verified
  /// box follows compass §6.1's reading of the artboard's span (padding 3 × 6 pt round a 9 pt
  /// line, 15 pt tall with its 0.75 pt border on the edge, 3 pt corners), its reason 2 pt under
  /// it, the block centred where the arrow block would be. Inter replaces the artboard's
  /// Helvetica (Inter SemiBold for the "N", compass §6.1).
  private func artboard(_ symbol: NorthSymbol, size: Double, center: DrawingPoint)
    -> [DrawingItem]
  {
    let muted = DrawingColor(hex: 0x6B6557)
    let ascent = Double(ChapterBrandAssets.interRegular.ascent) / 1000
    let descent = Double(ChapterBrandAssets.interRegular.descent) / 1000
    /// Baseline of a 7.5 pt line in a 9 pt CSS line box whose top is `top`.
    func baseline(top: Double) -> Double {
      let halfLeading = (9 - (ascent - descent) * 7.5) / 2
      return top - (halfLeading + ascent * 7.5) * point
    }
    func caption(_ text: String, top: Double) -> DrawingItem {
      .text(
        DrawingText(
          text, position: DrawingPoint(x: center.x, y: baseline(top: top)), size: 7.5 * point,
          anchor: .center, color: muted, layer: .compass))
    }
    func path(_ points: [DrawingPoint]) -> DrawingPath {
      DrawingPath(
        elements: points.enumerated().map { $0.offset == 0 ? .move($0.element) : .line($0.element) }
          + [.close])
    }
    switch symbol {
    case .arrow(let angle, let approximate, let line1, let line2):
      let s = size * point / 32
      let a = angle * .pi / 180
      // View box units (y down) to the page (y up), turned counter-clockwise by A on the page.
      func onPage(_ x: Double, _ y: Double) -> DrawingPoint {
        let dx = (x - 16) * s
        let dy = (16 - y) * s
        return DrawingPoint(
          x: center.x + dx * cos(a) - dy * sin(a), y: center.y + dx * sin(a) + dy * cos(a))
      }
      let ring = (0..<720).map { step -> DrawingPoint in
        let t = Double(step) / 720 * 2 * .pi
        return onPage(16 + 10.5 * cos(t), 18 + 10.5 * sin(t))
      }
      let arrow = [(16, 6.5), (20.5, 25.5), (16, 22), (11.5, 25.5)].map { onPage($0.0, $0.1) }
      let captionTop = center.y - size * point / 2 - 2 * point
      return [
        .shape(
          DrawingShape(
            path: path(ring),
            stroke: DrawingStroke(
              color: ink, width: 0.75 * s, dash: approximate ? [1.6 * s, 1.6 * s] : []),
            layer: .compass)),
        .shape(
          DrawingShape(
            path: path(arrow), fill: approximate ? page : ink,
            stroke: DrawingStroke(color: ink, width: 0.75 * s, join: .round), layer: .compass)),
        .text(
          DrawingText(
            "N", position: onPage(16, 4.6), size: 6 * s, rotationDegrees: angle, anchor: .center,
            bold: true, color: ink, layer: .compass)),
        caption(line1, top: captionTop),
        caption(line2, top: captionTop - 9 * point),
      ]
    case .notVerified(let box, let reason):
      let width = FontMetrics.width(box, size: 7.5 * point) + 12 * point
      let top = center.y - 10 * point + 13 * point
      let bottom = top - 15 * point
      let r = 3 * point
      var outline: [DrawingPoint] = []
      for (cx, cy, from) in [
        (center.x + width / 2 - r, top - r, 0.0), (center.x - width / 2 + r, top - r, 90.0),
        (center.x - width / 2 + r, bottom + r, 180.0),
        (center.x + width / 2 - r, bottom + r, 270.0),
      ] {
        for step in 0...45 {
          let t = (from + Double(step) * 2) * .pi / 180
          outline.append(DrawingPoint(x: cx + r * cos(t), y: cy + r * sin(t)))
        }
      }
      return [
        .shape(
          DrawingShape(
            path: path(outline), stroke: DrawingStroke(color: muted, width: 0.75 * point),
            layer: .compass)),
        .text(
          DrawingText(
            box, position: DrawingPoint(x: center.x, y: baseline(top: top - 3 * point)),
            size: 7.5 * point, anchor: .center, color: ink, layer: .compass)),
        caption(reason, top: bottom - 2 * point),
      ]
    }
  }

  /// Writes a render to `.build/test-output/north-symbol/<name>.png` for review.
  private func write(_ raster: DrawingRaster, named name: String) throws {
    let folder = Repo.testOutput.appendingPathComponent("north-symbol")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try PNGEncoder.encodeGrayscale(
      width: raster.width, height: raster.height, pixels: raster.canvas.pixels
    ).write(to: folder.appendingPathComponent("\(name).png"))
  }

  /// Grey-scale renders of `drawn` and of `reference` on the same paper at 8 px per point (also
  /// written to `.build/test-output/north-symbol/` for review): the share of their pixels that
  /// differ by more than a quarter of full scale, of all pixels and of the pixels either render
  /// inks.
  private func compare(
    _ drawn: [DrawingItem], _ reference: [DrawingItem], width: Double, height: Double,
    name: String
  ) throws -> (share: Double, inkShare: Double) {
    let scale = 8 / point
    var a = DrawingRaster(
      minX: 0, minY: 0, maxX: width, maxY: height, pixelsPerMM: scale, background: page)
    a.draw(drawn)
    var b = DrawingRaster(
      minX: 0, minY: 0, maxX: width, maxY: height, pixelsPerMM: scale, background: page)
    b.draw(reference)
    var differing = 0
    var inked = 0
    let paper = UInt8((DrawingRaster.gray(page) * 255).rounded())
    for (p, q) in zip(a.canvas.pixels, b.canvas.pixels) {
      if abs(Int(p) - Int(q)) > 64 { differing += 1 }
      if min(p, q) < paper - 24 { inked += 1 }
    }
    for (raster, suffix) in [(a, "drawn"), (b, "artboard")] {
      try write(raster, named: "\(name)-\(suffix)")
    }
    return (
      Double(differing) / Double(a.canvas.pixels.count), Double(differing) / Double(max(1, inked))
    )
  }

  func testSymbolMatchesTheArtboardGeometryWithinOnePercentOfItsPixels() throws {
    for kind in Kind.allCases {
      for size in sizes {
        for angle in angles {
          let symbol = symbol(kind, angle: angle)
          let (width, height, center) = frame(symbol, size: size)
          let name = "\(kind.rawValue)-\(Format.compact(size))pt-A\(Format.compact(angle))"
          let result = try compare(
            items(symbol, size: size, center: center), artboard(symbol, size: size, center: center),
            width: width, height: height, name: name)
          XCTAssertLessThanOrEqual(result.share, 0.01, name)
          // Stricter than the spec's 1 %: 1 % of the inked pixels, so a ring dashed from
          // another starting point (about 5 % of the ink at 40 pt) fails too.
          XCTAssertLessThanOrEqual(result.inkShare, 0.01, name)
        }
      }
    }
  }

  // MARK: The Floorplan page

  /// The colour Floorplan of a fixture capture, drawn as the app draws it: `north` from the
  /// capture record.
  private func floorplan(_ fixture: String, floor: Int) throws
    -> (sheet: FloorplanWriter.Sheet, svg: String, state: CompassState)
  {
    let capture = try Fixtures.load(fixture)[floor]
    let context = try PlanExportContext(record: capture.record, captureId: capture.model.captureId)
    let options = FloorplanWriter.Options(
      address: capture.record.address.formatted, north: context.compass)
    let sheet = try FloorplanWriter.Sheet(model: capture.model, options: options)
    return (sheet, sheet.svg(), context.compass)
  }

  func testFloorplanPageMatchesItsReferenceInEachState() throws {
    // two-floor-house Floor 1: verified 212.4 ±8 true; two-room-apartment: approximate, ±12
    // magnetic; box-room (a 1.0.0 record): no reading.
    for (fixture, kind) in [
      ("two-floor-house", Kind.verified), ("two-room-apartment", .approximate),
      ("box-room", .notVerified),
    ] {
      let (_, svg, state) = try floorplan(fixture, floor: 0)
      switch (kind, state) {
      case (.verified, .verified), (.approximate, .approximate), (.notVerified, .notVerified):
        break
      default:
        XCTFail("\(fixture) is \(state), not \(kind)")
      }
      SVGSnapshot.assertMatches(svg, named: "floorplan-\(kind.rawValue)")
    }
  }

  func testApproximateInGreyScaleShowsADashedRingAndAHollowArrow() throws {
    for (fixture, kind) in [
      ("two-room-apartment", Kind.approximate), ("two-floor-house", .verified),
    ] {
      let (sheet, _, _) = try floorplan(fixture, floor: 0)
      let compass = sheet.items.compactMap { item -> DrawingShape? in
        guard case .shape(let shape) = item, shape.layer == .compass else { return nil }
        return shape
      }
      XCTAssertEqual(compass.count, 2, "ring and arrow")
      // The whole page in grey scale, around the symbol, at 8 px per point.
      let symbolItems = sheet.items.filter {
        if case .shape(let s) = $0 { return s.layer == .compass }
        if case .text(let t) = $0 { return t.layer == .compass }
        return false
      }
      let extent = FloorPlanDrawing.extent(of: symbolItems)
      var raster = DrawingRaster(
        minX: extent.minX - 2, minY: extent.minY - 2, maxX: extent.maxX + 2,
        maxY: extent.maxY + 2, pixelsPerMM: 8 / point)
      raster.draw(sheet.items)
      try write(raster, named: "floorplan-\(kind.rawValue)-grey")

      // The ring's centre line, from its on-curve points: a dashed ring is about half ink,
      // in as many dashes as 1.6 + 1.6 units go round 2π × 10.5 (20.6); a solid one all ink.
      let ends = compass[0].path.elements.compactMap { element -> DrawingPoint? in
        switch element {
        case .move(let p), .curve(_, _, let p): return p
        default: return nil
        }
      }.dropLast()
      let cx = ends.map(\.x).reduce(0, +) / Double(ends.count)
      let cy = ends.map(\.y).reduce(0, +) / Double(ends.count)
      let radius = hypot(ends[ends.startIndex].x - cx, ends[ends.startIndex].y - cy)
      let threshold = (DrawingRaster.gray(ChapterBrand.ink) + 1) / 2
      let dark = (0..<1440).map { step -> Bool in
        let t = Double(step) / 1440 * 2 * .pi
        return raster.gray(atMM: cx + radius * cos(t), cy + radius * sin(t)) < threshold
      }
      let share = Double(dark.filter { $0 }.count) / Double(dark.count)
      let runs = dark.indices.filter { dark[$0] && !dark[($0 + dark.count - 1) % dark.count] }.count
      // Halfway between the tip (16, 6.5) and the notch (16, 22): inside the arrow, 1.8 units
      // from its edges.
      let corners = compass[1].path.elements.compactMap { element -> DrawingPoint? in
        switch element {
        case .move(let p), .line(let p): return p
        default: return nil
        }
      }
      let inside = DrawingPoint(
        x: (corners[0].x + corners[2].x) / 2, y: (corners[0].y + corners[2].y) / 2)
      let probes = [-0.3, 0, 0.3].flatMap { dx in
        [-0.3, 0, 0.3].map { dy in raster.gray(atMM: inside.x + dx * point, inside.y + dy * point) }
      }
      if kind == .approximate {
        XCTAssertGreaterThan(share, 0.35, "dashed: \(share)")
        XCTAssertLessThan(share, 0.65, "dashed: \(share)")
        XCTAssertTrue((19...22).contains(runs), "\(runs) dashes")
        XCTAssertTrue(probes.allSatisfy { $0 > 0.95 }, "hollow arrow: \(probes)")
      } else {
        XCTAssertGreaterThan(share, 0.98, "solid ring: \(share)")
        XCTAssertEqual(runs, share == 1 ? 0 : 1)
        XCTAssertTrue(probes.allSatisfy { $0 < 0.3 }, "filled arrow: \(probes)")
      }
    }
  }
}
