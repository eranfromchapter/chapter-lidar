import Foundation

/// Minimal PDF 1.7 writer: pages of vector lines, polylines, rectangles and text in the
/// standard fonts Helvetica (F1) and Helvetica-Bold (F2) with WinAnsi encoding. Content streams
/// are uncompressed so every string stays extractable as text. Coordinates are points with the
/// origin at the bottom-left of the page.
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
