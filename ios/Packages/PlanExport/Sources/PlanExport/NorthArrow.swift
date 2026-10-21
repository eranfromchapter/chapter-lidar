import CaptureContract
import Foundation

/// The north symbol of a plan (compass §6.1): for a verified or approximate reading a ring, an
/// arrow and an "N" turned to north, with two caption lines under it; for any other capture
/// the box `Orientation: not verified` with the reason under it, never an arrow. The angle and
/// the texts come from the contract's `NorthSymbol` (`NorthSymbol(state:drawingRotationCCW:)`),
/// so every drawn output and the station say the same thing.
///
/// Geometry is the artboard's 32 × 32 box (y down, origin top left) scaled by s = box / 32:
///
/// | Part  | Verified                                              | Approximate          |
/// |-------|-------------------------------------------------------|----------------------|
/// | Ring  | circle (16, 18) r 10.5, stroke 0.75 s, no fill         | dash 1.6 s / 1.6 s   |
/// | Arrow | (16, 6.5) (20.5, 25.5) (16, 22) (11.5, 25.5), ink fill | page-colour fill     |
/// | N     | Inter SemiBold 6 s, centred on x 16, baseline y 4.6    | same                 |
///
/// Everything in the box turns counter-clockwise by the symbol's angle about the box centre
/// (16, 16); the caption does not turn. Captions are Inter 7.5 pt on 9 pt lines in the muted
/// colour, 2 pt below the box, whatever the box size. The not-verified box is Inter 7.5 pt in
/// ink, padded 3 pt by 6 pt (15 pt tall), with a 0.75 pt muted border on its edge and 3 pt
/// corners; its caption is one line 2 pt below it; it does not scale with the box, and the
/// block is centred where the arrow block would be.
///
/// Items are paper millimetres, y up, on `layer`. A drawing at 1:n moves them onto its plan
/// millimetres with `SheetTransform(scale: n, …)`.
public enum NorthArrow {
  /// Millimetres per point.
  static let point = 25.4 / 72
  /// Caption text size and line height, points.
  static let captionSize = 7.5
  static let captionLine = 9.0
  /// Space between the box and the caption, points.
  static let captionGap = 2.0
  /// Not-verified box: padding (points) around its one line, border width and corner radius.
  static let boxPaddingX = 6.0
  static let boxPaddingY = 3.0
  static let boxBorder = 0.75
  static let boxRadius = 3.0
  /// Inter's cap height, em: centres capitals in a line box (plan-sheet §3.1).
  static let capHeight = 0.727

  /// Drawing items of `symbol` with the centre of its `boxMM` square box at `centerMM`. `page` is
  /// the colour of the paper under it (the hollow arrow of an approximate reading), `ink` the
  /// output's ink: nil for the brand black of the colour Floorplan, the design ink `#1F2429` on
  /// the plan sheet. `caption` false leaves out the two caption lines of an arrow and the
  /// reason under the not-verified box.
  public static func items(
    symbol: NorthSymbol, centerMM: DrawingPoint, boxMM: Double, page: DrawingColor,
    caption: Bool, ink: DrawingColor? = nil, layer: DrawingLayer = .compass
  ) -> [DrawingItem] {
    let center = Point2(x: centerMM.x, y: centerMM.y)
    let ink = ink ?? ChapterBrand.ink
    switch symbol {
    case .arrow(let angle, let approximate, let line1, let line2):
      var items = arrowItems(
        center: center, boxMM: boxMM, angleCCW: angle, approximate: approximate, page: page,
        ink: ink, layer: layer)
      if caption {
        // Two centred lines, the first one's line box 2 pt under the unturned box.
        let top = center.y - boxMM / 2 - captionGap * point
        for (index, line) in [line1, line2].enumerated() {
          items.append(
            captionText(
              line, centerX: center.x, lineTop: top - Double(index) * captionLine * point,
              layer: layer))
        }
      }
      return items
    case .notVerified(let box, let reason):
      let top = center.y + blockExtentMM(symbol: symbol, boxMM: boxMM, caption: caption).top
      let width = notVerifiedBoxWidth(box)
      let height = notVerifiedBoxHeight
      // The border on the box's edge (PathBuilder takes metres).
      var border = PathBuilder()
      border.rect(
        in: DrawingFrame(origin: Point2(x: 0, y: 0), u: Point2(x: 1, y: 0), v: Point2(x: 0, y: 1)),
        (center.x - width / 2) / 1000, (top - height) / 1000, (center.x + width / 2) / 1000,
        top / 1000, radius: boxRadius * point / 1000)
      var items: [DrawingItem] = [
        .shape(
          DrawingShape(
            path: border.path,
            stroke: DrawingStroke(color: ChapterBrand.muted, width: boxBorder * point),
            layer: layer)),
        .text(
          DrawingText(
            box,
            position: DrawingPoint(
              x: center.x, y: baseline(lineTop: top - boxPaddingY * point)),
            size: captionSize * point, anchor: .center, color: ink, layer: layer)),
      ]
      if caption {
        items.append(
          captionText(
            reason, centerX: center.x, lineTop: top - height - captionGap * point, layer: layer))
      }
      return items
    }
  }

  /// Width and height of the block `items` draws for `symbol`, millimetres: for an arrow the
  /// box and, with the caption, 2 + 18 pt more and at least the widest caption line; for the
  /// not-verified box 15 pt tall, 26 pt with its reason.
  public static func blockSizeMM(symbol: NorthSymbol, boxMM: Double, caption: Bool)
    -> (width: Double, height: Double)
  {
    switch symbol {
    case .arrow(_, _, let line1, let line2):
      guard caption else { return (boxMM, boxMM) }
      let widest = max(captionWidth(line1), captionWidth(line2))
      return (max(boxMM, widest), boxMM + (captionGap + 2 * captionLine) * point)
    case .notVerified(let box, let reason):
      let width = notVerifiedBoxWidth(box)
      guard caption else { return (width, notVerifiedBoxHeight) }
      return (max(width, captionWidth(reason)), notVerifiedBlockHeight(caption: true))
    }
  }

  /// Top and bottom of the block `items` draws, millimetres above the centre of the symbol's
  /// box (the bottom is below it, negative). An arrow block hangs from the top of the box; the
  /// not-verified block (box, then the reason) is centred where the arrow block would be: on
  /// the box centre without a caption, 10 pt lower with one (half the caption's 2 + 18 pt).
  static func blockExtentMM(symbol: NorthSymbol, boxMM: Double, caption: Bool)
    -> (top: Double, bottom: Double)
  {
    switch symbol {
    case .arrow:
      let height = blockSizeMM(symbol: symbol, boxMM: boxMM, caption: caption).height
      return (boxMM / 2, boxMM / 2 - height)
    case .notVerified:
      let middle = caption ? -(captionGap + 2 * captionLine) / 2 * point : 0
      let half = notVerifiedBlockHeight(caption: caption) / 2
      return (middle + half, middle - half)
    }
  }

  // MARK: Pieces

  /// Ring, arrow and N in the box centred at `center`, turned counter-clockwise by `angleCCW`.
  private static func arrowItems(
    center: Point2, boxMM: Double, angleCCW: Double, approximate: Bool, page: DrawingColor,
    ink: DrawingColor, layer: DrawingLayer
  ) -> [DrawingItem] {
    let s = boxMM / 32
    let radians = angleCCW * .pi / 180
    let u = Point2(x: cos(radians), y: sin(radians))
    let v = u.leftNormal
    // Artboard units (y down, box origin top left) to page millimetres; PathBuilder takes
    // metres.
    func mm(_ x: Double, _ y: Double) -> Point2 {
      center + u * (s * (x - 16)) + v * (s * (16 - y))
    }
    func metres(_ p: Point2) -> Point2 { p * 0.001 }
    let line = 0.75 * s
    // The ring as an ellipse in the turned frame, so its dashes turn with it. It starts at its
    // rightmost point and runs clockwise on the page, as the artboard's SVG circle does, so
    // the dashes of an approximate reading fall where the artboard draws them.
    var ring = PathBuilder()
    ring.ellipse(
      in: DrawingFrame(origin: metres(mm(16, 18)), u: u, v: v * -1), cx: 0, cy: 0,
      rx: 10.5 * s / 1000, ry: 10.5 * s / 1000)
    var arrow = PathBuilder()
    arrow.polygon([mm(16, 6.5), mm(20.5, 25.5), mm(16, 22), mm(11.5, 25.5)].map(metres))
    let dash = approximate ? [1.6 * s, 1.6 * s] : []
    let letter = mm(16, 4.6)
    return [
      .shape(
        DrawingShape(
          path: ring.path, stroke: DrawingStroke(color: ink, width: line, dash: dash),
          layer: layer)),
      .shape(
        DrawingShape(
          path: arrow.path, fill: approximate ? page : ink,
          stroke: DrawingStroke(color: ink, width: line, join: .round), layer: layer)),
      .text(
        DrawingText(
          "N", position: DrawingPoint(x: letter.x, y: letter.y), size: 6 * s,
          rotationDegrees: angleCCW, anchor: .center, bold: true, color: ink, layer: layer)),
    ]
  }

  /// A caption line centred on `centerX` in its 9 pt line box from `lineTop` down.
  private static func captionText(
    _ text: String, centerX: Double, lineTop: Double, layer: DrawingLayer
  ) -> DrawingItem {
    .text(
      DrawingText(
        text, position: DrawingPoint(x: centerX, y: baseline(lineTop: lineTop)),
        size: captionSize * point, anchor: .center, color: ChapterBrand.muted, layer: layer))
  }

  /// Baseline of a 7.5 pt line in the 9 pt line box from `lineTop` down: capitals centred.
  private static func baseline(lineTop: Double) -> Double {
    lineTop - (captionLine / 2 + capHeight * captionSize / 2) * point
  }

  private static func captionWidth(_ text: String) -> Double {
    FontMetrics.width(text, size: captionSize * point)
  }

  private static var notVerifiedBoxHeight: Double {
    (2 * boxPaddingY + captionLine) * point
  }

  private static func notVerifiedBoxWidth(_ text: String) -> Double {
    captionWidth(text) + 2 * boxPaddingX * point
  }

  private static func notVerifiedBlockHeight(caption: Bool) -> Double {
    notVerifiedBoxHeight + (caption ? (captionGap + captionLine) * point : 0)
  }
}
