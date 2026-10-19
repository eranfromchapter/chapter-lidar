import Foundation

/// Minimal PDF 1.7 writer: pages of vector lines, polylines, rectangles, Bezier paths (arcs,
/// circles) and text in the standard fonts Helvetica (F1) and Helvetica-Bold (F2) with WinAnsi
/// encoding. Gray or RGB colour, dash patterns, line caps and joins, and clipping. Content
/// streams are uncompressed so every string stays extractable as text. Coordinates are points
/// with the origin at the bottom-left of the page.
final class PDFPage {
  let width: Double
  let height: Double
  private(set) var content: [UInt8] = []

  init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }

  enum Anchor {
    case leading
    case center
    case trailing
  }

  private func emit(_ text: String) {
    content.append(contentsOf: Array(text.utf8))
  }

  private static func num(_ value: Double) -> String {
    Format.fixed(value, 3)
  }

  func setStrokeGray(_ gray: Double) { emit("\(PDFPage.num(gray)) G\n") }
  func setFillGray(_ gray: Double) { emit("\(PDFPage.num(gray)) g\n") }
  func setLineWidth(_ points: Double) { emit("\(PDFPage.num(points)) w\n") }

  /// Straight line in the current stroke colour and width.
  func line(_ a: (Double, Double), _ b: (Double, Double)) {
    emit(
      "\(PDFPage.num(a.0)) \(PDFPage.num(a.1)) m \(PDFPage.num(b.0)) \(PDFPage.num(b.1)) l S\n")
  }

  /// Open or closed polyline, stroked and/or filled with the current colours.
  func polyline(_ points: [(Double, Double)], closed: Bool, stroke: Bool, fill: Bool) {
    guard let first = points.first else { return }
    var text = "\(PDFPage.num(first.0)) \(PDFPage.num(first.1)) m"
    for point in points.dropFirst() {
      text += " \(PDFPage.num(point.0)) \(PDFPage.num(point.1)) l"
    }
    let paint: String
    switch (stroke, fill, closed) {
    case (true, true, true): paint = "b"
    case (true, true, false): paint = "B"
    case (false, true, true): paint = "f"
    case (false, true, false): paint = "f"
    case (true, false, true): paint = "s"
    case (true, false, false): paint = "S"
    case (false, false, _): paint = "n"
    }
    emit(text + " \(paint)\n")
  }

  func rect(x: Double, y: Double, width: Double, height: Double, stroke: Bool, fill: Bool) {
    let paint = stroke && fill ? "B" : stroke ? "S" : fill ? "f" : "n"
    emit(
      "\(PDFPage.num(x)) \(PDFPage.num(y)) \(PDFPage.num(width)) \(PDFPage.num(height)) re \(paint)\n"
    )
  }

  // MARK: Colour, dashes, caps, joins and graphics state

  // Everything below only adds operators to the stream; the grayscale calls above are unchanged,
  // so pages that never use them write the same bytes as before.

  /// Stroke colour, components 0...1 (`RG`).
  func setStrokeRGB(_ red: Double, _ green: Double, _ blue: Double) {
    emit("\(PDFPage.unit(red)) \(PDFPage.unit(green)) \(PDFPage.unit(blue)) RG\n")
  }

  /// Fill colour, components 0...1 (`rg`). Text is painted in the fill colour.
  func setFillRGB(_ red: Double, _ green: Double, _ blue: Double) {
    emit("\(PDFPage.unit(red)) \(PDFPage.unit(green)) \(PDFPage.unit(blue)) rg\n")
  }

  /// Dash pattern in points (`d`): alternating on and off lengths, starting `phase` points into
  /// the pattern. An empty array is a solid line.
  func setDash(_ lengths: [Double], phase: Double = 0) {
    let body = lengths.map { PDFPage.num(max(0, $0)) }.joined(separator: " ")
    emit("[\(body)] \(PDFPage.num(phase)) d\n")
  }

  enum LineCap: Int {
    case butt = 0
    case round = 1
    case square = 2
  }

  enum LineJoin: Int {
    case miter = 0
    case round = 1
    case bevel = 2
  }

  func setLineCap(_ cap: LineCap) { emit("\(cap.rawValue) J\n") }
  func setLineJoin(_ join: LineJoin) { emit("\(join.rawValue) j\n") }
  func setMiterLimit(_ limit: Double) { emit("\(PDFPage.num(max(1, limit))) M\n") }

  /// Saves the graphics state (`q`): colours, line style and clipping path.
  func saveState() { emit("q\n") }
  /// Restores the state saved by the matching `saveState` (`Q`).
  func restoreState() { emit("Q\n") }

  // MARK: Paths

  /// How a path is painted.
  enum Paint {
    case fill
    case fillEvenOdd
    case stroke
    case fillStroke
    case fillEvenOddStroke

    var op: String {
      switch self {
      case .fill: return "f"
      case .fillEvenOdd: return "f*"
      case .stroke: return "S"
      case .fillStroke: return "B"
      case .fillEvenOddStroke: return "B*"
      }
    }
  }

  /// Path of lines and cubic Bezier curves in page points, one or more subpaths.
  struct Path {
    enum Element {
      case move(Double, Double)
      case line(Double, Double)
      /// Control point 1, control point 2, end point.
      case curve(Double, Double, Double, Double, Double, Double)
      case close
    }

    var elements: [Element] = []

    mutating func move(_ x: Double, _ y: Double) { elements.append(.move(x, y)) }
    mutating func line(_ x: Double, _ y: Double) { elements.append(.line(x, y)) }
    mutating func curve(
      _ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double
    ) {
      elements.append(.curve(c1x, c1y, c2x, c2y, x, y))
    }
    mutating func close() { elements.append(.close) }

    /// Circular arc from `start` to `end` degrees (counter-clockwise when `end` > `start`),
    /// as cubic Beziers of at most 90 degrees each. Starts with a line to the first point, or a
    /// move when the path is empty or `move` is true.
    mutating func arc(
      centerX: Double, centerY: Double, radius: Double, startDegrees: Double,
      endDegrees: Double, move: Bool = false
    ) {
      let segments = PDFPage.arcBeziers(
        centerX: centerX, centerY: centerY, radius: radius, startDegrees: startDegrees,
        endDegrees: endDegrees)
      let start = PDFPage.arcPoint(centerX, centerY, radius, startDegrees)
      if move || elements.isEmpty {
        self.move(start.0, start.1)
      } else {
        line(start.0, start.1)
      }
      for s in segments { curve(s.0, s.1, s.2, s.3, s.4, s.5) }
    }

    /// Closed circle as four Bezier quarter arcs, counter-clockwise from 0 degrees.
    mutating func circle(centerX: Double, centerY: Double, radius: Double) {
      arc(
        centerX: centerX, centerY: centerY, radius: radius, startDegrees: 0, endDegrees: 360,
        move: true)
      close()
    }
  }

  /// Writes `path` and paints it.
  func path(_ path: Path, paint: Paint) {
    guard !path.elements.isEmpty else { return }
    emit(PDFPage.operators(path) + " \(paint.op)\n")
  }

  /// Intersects the clipping path with `path` (`W n` or `W* n`). Wrap in `saveState` and
  /// `restoreState` to end the clip.
  func clip(_ path: Path, evenOdd: Bool = false) {
    guard !path.elements.isEmpty else { return }
    emit(PDFPage.operators(path) + (evenOdd ? " W* n\n" : " W n\n"))
  }

  /// Circle filled and/or stroked with the current colours.
  func circle(centerX: Double, centerY: Double, radius: Double, paint: Paint) {
    var p = Path()
    p.circle(centerX: centerX, centerY: centerY, radius: radius)
    path(p, paint: paint)
  }

  private static func operators(_ path: Path) -> String {
    var parts: [String] = []
    for element in path.elements {
      switch element {
      case .move(let x, let y): parts.append("\(num(x)) \(num(y)) m")
      case .line(let x, let y): parts.append("\(num(x)) \(num(y)) l")
      case .curve(let a, let b, let c, let d, let e, let f):
        parts.append("\(num(a)) \(num(b)) \(num(c)) \(num(d)) \(num(e)) \(num(f)) c")
      case .close: parts.append("h")
      }
    }
    return parts.joined(separator: " ")
  }

  /// Colour component with four decimals, clamped to 0...1.
  private static func unit(_ value: Double) -> String {
    Format.fixed(max(0, min(1, value)), 4)
  }

  static func arcPoint(_ cx: Double, _ cy: Double, _ r: Double, _ degrees: Double)
    -> (Double, Double)
  {
    let a = degrees * .pi / 180
    return (cx + r * cos(a), cy + r * sin(a))
  }

  /// Cubic Bezier segments (control 1, control 2, end) for a circular arc, each spanning at most
  /// 90 degrees. The control distance 4/3 tan(theta/4) keeps the radius error below 0.03 %.
  static func arcBeziers(
    centerX: Double, centerY: Double, radius: Double, startDegrees: Double, endDegrees: Double
  ) -> [(Double, Double, Double, Double, Double, Double)] {
    let sweep = endDegrees - startDegrees
    guard abs(sweep) > 1e-9, radius > 0 else { return [] }
    let count = max(1, Int((abs(sweep) / 90).rounded(.up)))
    let step = sweep / Double(count) * .pi / 180
    let k = 4.0 / 3.0 * tan(step / 4)
    var out: [(Double, Double, Double, Double, Double, Double)] = []
    var angle = startDegrees * .pi / 180
    for _ in 0..<count {
      let next = angle + step
      let (c0, s0, c1, s1) = (cos(angle), sin(angle), cos(next), sin(next))
      out.append(
        (
          centerX + radius * (c0 - k * s0), centerY + radius * (s0 + k * c0),
          centerX + radius * (c1 + k * s1), centerY + radius * (s1 - k * c1),
          centerX + radius * c1, centerY + radius * s1
        ))
      angle = next
    }
    return out
  }

  /// Draws `text` with its baseline start, centre or end at (x, y), turned counter-clockwise by
  /// `rotation` degrees. Uses the current fill colour.
  func text(
    _ text: String, x: Double, y: Double, size: Double, bold: Bool = false,
    anchor: Anchor = .leading, rotation: Double = 0
  ) {
    let clean = Format.singleLine(text)
    guard !clean.isEmpty else { return }
    let width = FontMetrics.width(clean, size: size, bold: bold)
    let shift: Double
    switch anchor {
    case .leading: shift = 0
    case .center: shift = -width / 2
    case .trailing: shift = -width
    }
    let radians = rotation * .pi / 180
    let c = cos(radians)
    let s = sin(radians)
    let startX = x + shift * c
    let startY = y + shift * s
    emit("BT /\(bold ? "F2" : "F1") \(PDFPage.num(size)) Tf ")
    emit(
      "\(Format.fixed(c, 5)) \(Format.fixed(s, 5)) \(Format.fixed(-s, 5)) \(Format.fixed(c, 5)) "
        + "\(PDFPage.num(startX)) \(PDFPage.num(startY)) Tm (")
    content.append(contentsOf: PDFPage.encode(clean))
    emit(") Tj ET\n")
  }

  // MARK: WinAnsi

  private static let winAnsiSpecials: [UInt32: UInt8] = [
    0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, 0x2020: 0x86,
    0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C,
    0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95,
    0x2013: 0x96, 0x2014: 0x97, 0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B,
    0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
  ]

  /// WinAnsi byte for a character, `?` when it has none.
  static func winAnsi(_ scalar: Unicode.Scalar) -> UInt8 {
    let value = scalar.value
    if value >= 0x20 && value <= 0x7E { return UInt8(value) }
    if value >= 0xA0 && value <= 0xFF { return UInt8(value) }
    return winAnsiSpecials[value] ?? UInt8(ascii: "?")
  }

  /// Bytes of a PDF literal string body: parentheses and backslash escaped, bytes above 0x7E
  /// written as octal escapes so the stream stays 7-bit.
  static func encode(_ text: String) -> [UInt8] {
    var out: [UInt8] = []
    for scalar in text.unicodeScalars {
      let byte = winAnsi(scalar)
      switch byte {
      case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "\\"):
        out.append(UInt8(ascii: "\\"))
        out.append(byte)
      case 0x7F...0xFF:
        out.append(UInt8(ascii: "\\"))
        let octal = String(byte, radix: 8)
        out.append(contentsOf: Array(octal.utf8))
      default:
        out.append(byte)
      }
    }
    return out
  }
}

struct PDFDocument {
  var title: String
  var author: String
  var subject: String
  var creator: String
  /// PDF date string, for example `D:20261017140211Z`.
  var creationDate: String
  var pages: [PDFPage] = []

  /// Serialises the document with a correct cross-reference table.
  func render() -> Data {
    // Object numbers: 1 catalog, 2 pages, 3 Helvetica, 4 Helvetica-Bold, 5 info,
    // then page and content stream pairs.
    var objects: [[UInt8]] = []
    func ascii(_ text: String) -> [UInt8] { Array(text.utf8) }
    func string(_ text: String) -> String {
      "(" + String(decoding: PDFPage.encode(text), as: UTF8.self) + ")"
    }
    let pageCount = pages.count
    let kids = (0..<pageCount).map { "\(6 + $0 * 2) 0 R" }.joined(separator: " ")
    objects.append(ascii("<< /Type /Catalog /Pages 2 0 R /Lang (en-US) >>"))
    objects.append(ascii("<< /Type /Pages /Kids [\(kids)] /Count \(pageCount) >>"))
    objects.append(
      ascii("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"))
    objects.append(
      ascii(
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>"))
    objects.append(
      ascii(
        "<< /Title \(string(title)) /Author \(string(author)) /Subject \(string(subject)) "
          + "/Creator \(string(creator)) /Producer \(string(creator)) "
          + "/CreationDate (\(creationDate)) >>"))
    for (index, page) in pages.enumerated() {
      let contentNumber = 7 + index * 2
      objects.append(
        ascii(
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(Format.fixed(page.width, 3)) "
            + "\(Format.fixed(page.height, 3))] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> "
            + "/Contents \(contentNumber) 0 R >>"))
      var stream = ascii("<< /Length \(page.content.count) >>\nstream\n")
      stream.append(contentsOf: page.content)
      stream.append(contentsOf: ascii("endstream"))
      objects.append(stream)
    }

    var out: [UInt8] = ascii("%PDF-1.7\n")
    out.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
    var offsets: [Int] = []
    for (index, body) in objects.enumerated() {
      offsets.append(out.count)
      out.append(contentsOf: ascii("\(index + 1) 0 obj\n"))
      out.append(contentsOf: body)
      out.append(contentsOf: ascii("\nendobj\n"))
    }
    let xrefStart = out.count
    var xref = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
      xref += String(repeating: "0", count: 10 - String(offset).count) + String(offset)
      xref += " 00000 n \n"
    }
    xref +=
      "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R /Info 5 0 R >>\nstartxref\n\(xrefStart)\n%%EOF\n"
    out.append(contentsOf: ascii(xref))
    return Data(out)
  }
}
