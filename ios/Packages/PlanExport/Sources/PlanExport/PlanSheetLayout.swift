import CaptureContract
import Foundation

/// Page items of the plan sheet, built in points from the top-left corner of the page as the
/// artboard measures them (x right, y down) and written with the PDF's y up.
struct SheetItems {
  static let pageWidth = 1224.0
  static let pageHeight = 792.0

  var items: [DrawingItem] = []

  static func y(_ top: Double) -> Double { pageHeight - top }

  static func rectPath(x: Double, top: Double, width: Double, height: Double) -> DrawingPath {
    let (x0, x1) = (x, x + width)
    let (y0, y1) = (y(top + height), y(top))
    return DrawingPath(elements: [
      .move(DrawingPoint(x: x0, y: y0)), .line(DrawingPoint(x: x1, y: y0)),
      .line(DrawingPoint(x: x1, y: y1)), .line(DrawingPoint(x: x0, y: y1)), .close,
    ])
  }

  mutating func fill(x: Double, top: Double, width: Double, height: Double, _ color: DrawingColor) {
    items.append(
      .shape(
        DrawingShape(
          path: SheetItems.rectPath(x: x, top: top, width: width, height: height), fill: color,
          layer: .sheet)))
  }

  mutating func stroke(
    x: Double, top: Double, width: Double, height: Double, _ color: DrawingColor,
    lineWidth: Double, dash: [Double] = [], fill: DrawingColor? = nil
  ) {
    items.append(
      .shape(
        DrawingShape(
          path: SheetItems.rectPath(x: x, top: top, width: width, height: height), fill: fill,
          stroke: DrawingStroke(color: color, width: lineWidth, dash: dash), layer: .sheet)))
  }

  /// A rectangle with rounded corners, stroked.
  mutating func roundedRect(
    x: Double, top: Double, width: Double, height: Double, radius: Double,
    _ color: DrawingColor, lineWidth: Double
  ) {
    // PathBuilder takes metres and writes millimetres: points / 1000 come out as points.
    var builder = PathBuilder()
    builder.rect(
      in: DrawingFrame(origin: Point2(x: 0, y: 0), u: Point2(x: 1, y: 0), v: Point2(x: 0, y: 1)),
      x / 1000, SheetItems.y(top + height) / 1000, (x + width) / 1000, SheetItems.y(top) / 1000,
      radius: radius / 1000)
    items.append(
      .shape(
        DrawingShape(
          path: builder.path, stroke: DrawingStroke(color: color, width: lineWidth),
          layer: .sheet)))
  }

  /// A straight line from (x0, top0) to (x1, top1).
  mutating func line(
    _ x0: Double, _ top0: Double, _ x1: Double, _ top1: Double, _ color: DrawingColor,
    width: Double, dash: [Double] = []
  ) {
    items.append(
      .shape(
        DrawingShape(
          path: DrawingPath(elements: [
            .move(DrawingPoint(x: x0, y: SheetItems.y(top0))),
            .line(DrawingPoint(x: x1, y: SheetItems.y(top1))),
          ]), stroke: DrawingStroke(color: color, width: width, dash: dash), layer: .sheet)))
  }

  /// One line of text in its line box from `lineTop`, `lineHeight` tall, capitals centred in it
  /// (plan-sheet §3.1): baseline = top + height / 2 + cap height × size / 2.
  mutating func text(
    _ string: String, x: Double, lineTop: Double, lineHeight: Double, size: Double,
    font: DrawingFont = .interRegular, color: DrawingColor = ChapterBrand.Sheet.ink,
    anchor: DrawingTextAnchor = .leading, tracking: Double = 0
  ) {
    guard !string.isEmpty else { return }
    let baseline = lineTop + lineHeight / 2 + FontMetrics.capHeight(font) * size / 2
    items.append(
      .text(
        DrawingText(
          string, position: DrawingPoint(x: x, y: SheetItems.y(baseline)), size: size,
          anchor: anchor, font: font, letterSpacing: tracking, color: color, layer: .sheet)))
  }

  /// Width of `string` as `text` draws it.
  static func width(_ string: String, size: Double, font: DrawingFont, tracking: Double = 0)
    -> Double
  {
    FontMetrics.width(string, size: size, font: font)
      + tracking * Double(max(0, Format.composed(string).unicodeScalars.count - 1))
  }
}

/// Measured text helpers of the sheet: wrapping at spaces and cutting with ASCII "...".
enum SheetText {
  /// `text` cut with "..." when it is wider than `width` points.
  static func cut(
    _ text: String, size: Double, font: DrawingFont, width: Double, tracking: Double = 0
  ) -> String {
    func measure(_ s: String) -> Double {
      SheetItems.width(s, size: size, font: font, tracking: tracking)
    }
    if measure(text) <= width { return text }
    var characters = Array(text)
    while !characters.isEmpty {
      characters.removeLast()
      let shorter = String(characters).trimmingCharacters(in: .whitespaces) + "..."
      if measure(shorter) <= width { return shorter }
    }
    return "..."
  }

  /// Greedy word wrap by measured width; a word wider than the line is broken by characters.
  static func wrap(
    _ text: String, size: Double, font: DrawingFont, width: Double, tracking: Double = 0
  ) -> [String] {
    func measure(_ s: String) -> Double {
      SheetItems.width(s, size: size, font: font, tracking: tracking)
    }
    var lines: [String] = []
    var current = ""
    for word in text.split(separator: " ", omittingEmptySubsequences: true) {
      var word = String(word)
      while measure(word) > width, word.count > 1 {
        var head = ""
        for character in word {
          if measure(head + String(character)) > width, !head.isEmpty { break }
          head.append(character)
        }
        if !current.isEmpty {
          lines.append(current)
          current = ""
        }
        lines.append(head)
        word = String(word.dropFirst(head.count))
      }
      let candidate = current.isEmpty ? word : current + " " + word
      if measure(candidate) <= width || current.isEmpty {
        current = candidate
      } else {
        lines.append(current)
        current = word
      }
    }
    if !current.isEmpty || lines.isEmpty { lines.append(current) }
    return lines
  }

  /// `wrap`, at most `maxLines` lines: the rest joined onto the last line and cut with "...".
  static func fit(
    _ text: String, size: Double, font: DrawingFont, width: Double, maxLines: Int,
    tracking: Double = 0
  ) -> [String] {
    let lines = wrap(text, size: size, font: font, width: width, tracking: tracking)
    guard lines.count > maxLines, maxLines > 0 else { return lines }
    let rest = lines[(maxLines - 1)...].joined(separator: " ")
    return Array(lines.prefix(maxLines - 1))
      + [cut(rest, size: size, font: font, width: width, tracking: tracking)]
  }
}

/// What the title block says about the capture's rooms.
struct PlanSheetSummary: Hashable, Sendable {
  /// Sum of the rooms' floor areas (rounded once when printed); nil without rooms.
  var floorAreaM2: Double?
  /// Rooms with an outline and an area.
  var scannedRooms: Int

  init(metrics: PlanMetrics) {
    let rooms = metrics.rooms.filter { $0.floorAreaM2 > 0 }
    scannedRooms = rooms.count
    floorAreaM2 = rooms.isEmpty ? nil : metrics.totals.livableAreaM2
  }

  init(floorAreaM2: Double?, scannedRooms: Int) {
    self.floorAreaM2 = floorAreaM2
    self.scannedRooms = scannedRooms
  }
}

/// The plan sheet's page around the drawing (plan-sheet §3.2, §3.5–3.7): the page colour, the
/// border and the rule at x 912, the footnote under the drawing, and the title block (x
/// 936–1164, y 60–732) as a stack of blocks: A header (logo, sheet id), B title, C data rows,
/// D note card, E rooms not scanned (only when there are any), F legend, G scale and north,
/// and H the footer pinned to the bottom. The gap between blocks is 14 pt, less when the
/// blocks need it (never under 8 pt; then the list of rooms not scanned is cut short, then the
/// title lines). Pure: the same inputs give the same items.
struct PlanSheetLayout {
  /// A block of the title block: its name, top and height, points from the page's top.
  struct Block: Hashable, Sendable {
    var name: String
    var top: Double
    var height: Double
    var bottom: Double { top + height }
  }

  static let blockX = 936.0
  static let blockWidth = 228.0
  static let blockRight = 1164.0
  static let blockTop = 60.0
  static let blockBottom = 732.0
  static let maximumGap = 14.0
  static let minimumGap = 8.0
  static let footnoteX = 60.0
  static let footnoteWidth = 560.0
  static let footnoteBottom = 736.0
  static let footnoteLine = 9.0
  static let logoHeight = 36.0

  /// The production footnote (plan-sheet §3.5).
  static let footnote =
    "Walls, openings and object boxes come from the LiDAR scan. Doors are drawn without swing "
    + "(not recorded). Room dimensions are bounding boxes. Wall thickness is not measured: "
    + "walls are drawn 4.5 in thick inside and 6 in outside, and overall dimensions include it."
  static let statement =
    "Generated by Chapter Capture from an on-site LiDAR scan. Measurements are scan estimates "
    + "and may differ from real conditions. This sheet is not a survey and does not certify "
    + "any property model or measurement. Verify on site before planning or construction."
  static let title = "Existing-condition plan"
  static let noteTitle = "Made on site, before the station checks"
  static let noteBody =
    "The station verdict and the capture checks are in the Chapter spatial report for this "
    + "capture. This sheet has no verdict."
  static let notScannedClosing = "Rooms not scanned have no geometry and are not drawn."
  static let tagline = "It's about time."
  static let website = "hellochapter.com"

  /// The footnote sentence of a plan larger than the sheet at the last rung of its ladder.
  static func tooBigSentence(scaleDenominator: Int) -> String {
    "The plan is larger than this sheet at 1:\(scaleDenominator) and is cut at the frame. "
      + "plan.dxf holds the whole floor."
  }

  /// Title block blocks in order, with where they were placed.
  var blocks: [Block]
  var footer: Block
  var gap: Double
  /// Rooms not scanned listed, and how many were left for the overflow line.
  var notScannedShown: [String]
  var notScannedOverflow: Int
  var footnoteLines: [String]
  /// Everything of the page except the drawing, points (y up).
  var items: [DrawingItem]

  var footnoteTop: Double {
    PlanSheetLayout.footnoteBottom - PlanSheetLayout.footnoteLine * Double(footnoteLines.count)
  }

  func block(_ name: String) -> Block? { blocks.first { $0.name == name } }

  /// The footnote's lines for a sheet whose plan is (or is not) cut at the frame.
  static func footnoteLines(tooBig: Bool, scaleDenominator: Int) -> [String] {
    let text =
      footnote + (tooBig ? " " + tooBigSentence(scaleDenominator: scaleDenominator) : "")
    return SheetText.wrap(text, size: 7.5, font: .interRegular, width: footnoteWidth)
  }

  // MARK: Making

  static func make(
    context: PlanExportContext, summary: PlanSheetSummary, scaleDenominator: Int,
    north: NorthSymbol, tooBig: Bool
  ) -> PlanSheetLayout {
    let palette = ChapterBrand.Sheet.self
    let x = blockX
    let right = blockRight
    let width = blockWidth
    let caps = Locale(identifier: "en_US_POSIX")

    // A: header row.
    let sheetId = "SHEET \(context.sheetNumber) · \(context.floorLabel.uppercased(with: caps))"
    let idWidth = width - ChapterLogo.width(height: logoHeight) - 8
    let idLines = SheetText.fit(
      sheetId, size: 8.25, font: .interRegular, width: idWidth, maxLines: 2, tracking: 1.5)
    let headerHeight = 36.0

    // B: title group.
    let titleLines = SheetText.wrap(title, size: 25.5, font: .timesRoman, width: width)
    let line1Text = "\(context.floorLabel) · \(context.projectTitle)"
    var line1 = SheetText.fit(
      line1Text, size: 11.25, font: .interRegular, width: width, maxLines: 2)
    let confirmed = context.addressConfirmedOnSite
    // Line 2: the address as its own text run, then the confirmation; broken before " · "
    // when it does not fit on one line.
    var line2: [[(text: String, x: Double)]]
    if context.titleShowsAddress {
      let words = confirmed ? "Address confirmed on site" : "Address not confirmed on site"
      line2 = SheetText.fit(words, size: 9, font: .interRegular, width: width, maxLines: 2)
        .map { [($0, x)] }
    } else {
      let suffix = confirmed ? "address confirmed on site" : "address not confirmed on site"
      let address = context.address
      let whole = "\(address) · \(suffix)"
      let addressWidth = SheetItems.width(address, size: 9, font: .interRegular)
      if SheetItems.width(whole, size: 9, font: .interRegular) <= width {
        line2 = [[(address, x), (" · \(suffix)", x + addressWidth)]]
      } else if addressWidth <= width {
        line2 = [[(address, x)], [(suffix, x)]]
      } else {
        line2 = SheetText.fit(whole, size: 9, font: .interRegular, width: width, maxLines: 2)
          .map { [($0, x)] }
      }
    }

    // C: data rows.
    struct Row {
      var label: String
      var value: String
      var font: DrawingFont
      var size: Double
    }
    func valueWidth(_ label: String) -> Double {
      width - SheetItems.width(label, size: 9, font: .interRegular) - 8
    }
    var rows: [Row] = []
    do {
      let label = "HUB deal"
      let available = valueWidth(label)
      let size = SheetItems.width(context.dealId, size: 9, font: .courier) <= available ? 9 : 7.5
      rows.append(
        Row(
          label: label,
          value: SheetText.cut(context.dealId, size: size, font: .courier, width: available),
          font: .courier, size: size))
    }
    rows.append(Row(label: "Capture id", value: context.captureId, font: .courier, size: 7.5))
    do {
      let label = "Captured"
      let date = "\(context.capturedDateText) · "
      let available = valueWidth(label) - SheetItems.width(date, size: 9, font: .interRegular)
      let name = SheetText.cut(
        context.operatorName, size: 9, font: .interRegular, width: max(0, available))
      rows.append(Row(label: label, value: date + name, font: .interRegular, size: 9))
    }
    do {
      let label = "Device"
      let lidar = context.hasLidar ? " · LiDAR" : ""
      let text = "\(context.deviceName)\(lidar) · app \(context.appShortVersion)"
      rows.append(
        Row(
          label: label,
          value: SheetText.cut(text, size: 9, font: .interRegular, width: valueWidth(label)),
          font: .interRegular, size: 9))
    }
    let mode: String
    switch context.mode {
    case .room: mode = "One room"
    case .floor: mode = "Whole floor"
    case .exterior: mode = "Exterior"
    }
    rows.append(Row(label: "Mode", value: mode, font: .interRegular, size: 9))
    let area =
      summary.floorAreaM2.map {
        "\(UnitFormatter.sheetArea($0)) · \(UnitFormatter.sheetMetricArea($0))"
      } ?? "not captured"
    rows.append(Row(label: "Floor area, sum of rooms", value: area, font: .interRegular, size: 9))
    let notScanned = context.omittedRooms.count + context.inaccessibleRooms.count
    var roomsText =
      summary.scannedRooms > 0 ? "\(summary.scannedRooms) scanned" : "none recognized"
    if notScanned > 0 { roomsText += " · \(notScanned) not scanned" }
    rows.append(Row(label: "Rooms", value: roomsText, font: .interRegular, size: 9))
    let rowHeight = 20.75
    let dataHeight = rowHeight * Double(rows.count)

    // D: note card.
    let noteTextWidth = 206.5
    let noteBody = SheetText.wrap(
      self.noteBody, size: 8.25, font: .interRegular, width: noteTextWidth)
    let noteHeight = 0.75 + 8 + 11 + 3 + 10.5 * Double(noteBody.count) + 8 + 0.75

    // E: rooms not scanned.
    let notScannedRows: [String] =
      context.omittedRooms.map { note in
        "\(note.name) · \(note.reason.flatMap { $0.isEmpty ? nil : $0 } ?? "skipped")"
      }
      + context.inaccessibleRooms.map { note in
        "\(note.name) · \(note.reason.flatMap { $0.isEmpty ? nil : $0 } ?? "could not enter")"
      }
    func notScannedHeight(rows: Int, overflow: Bool) -> Double {
      9 + 3 + 13.5 * Double(rows) + (overflow ? 13.5 : 0) + 9
    }

    // F: legend; G: scale and north; H: footer.
    let legendHeight = 69.0
    let scaleNorthHeight = 60.0
    let statement = SheetText.wrap(self.statement, size: 8.25, font: .interRegular, width: width)
    let footerHeight = 0.75 + 12 + 10.5 * Double(statement.count) + 8 + 13

    // Stacking (plan-sheet §3.7).
    func titleHeight(_ l1: Int, _ l2: Int) -> Double {
      28 * Double(titleLines.count) + 4 + 14 * Double(l1) + 4 + 11 * Double(l2)
    }
    var shownRows = notScannedRows.count
    var overflow = 0
    func heights() -> [(String, Double)] {
      var list: [(String, Double)] = [
        ("A", headerHeight), ("B", titleHeight(line1.count, line2.count)), ("C", dataHeight),
        ("D", noteHeight),
      ]
      if !notScannedRows.isEmpty {
        list.append(("E", notScannedHeight(rows: shownRows, overflow: overflow > 0)))
      }
      list += [("F", legendHeight), ("G", scaleNorthHeight)]
      return list
    }
    let available = blockBottom - blockTop
    func gapFor(_ list: [(String, Double)]) -> Double {
      (available - list.map(\.1).reduce(0, +) - footerHeight) / Double(list.count)
    }
    var gap = min(maximumGap, gapFor(heights()))
    if gap < minimumGap {
      gap = minimumGap
      if !notScannedRows.isEmpty {
        var k = notScannedRows.count
        while k > 0 {
          k -= 1
          shownRows = k
          overflow = notScannedRows.count - k
          if gapFor(heights()) >= minimumGap { break }
        }
      }
      if gapFor(heights()) < minimumGap {
        if line1.count > 1 {
          line1 = [
            SheetText.cut(
              line1.joined(separator: " ") + " ...", size: 11.25, font: .interRegular,
              width: width)
          ]
        }
        if line2.count > 1 {
          let joined = line2.map { $0.map(\.text).joined() }.joined(separator: " ")
          line2 = [[(SheetText.cut(joined, size: 9, font: .interRegular, width: width), x)]]
        }
      }
    }
    var blocks: [Block] = []
    var top = blockTop
    for (name, height) in heights() {
      blocks.append(Block(name: name, top: top, height: height))
      top += height + gap
    }
    let footer = Block(
      name: "H", top: blockBottom - footerHeight, height: footerHeight)

    // Drawing.
    var page = SheetItems()
    // Page, border and the rule between the drawing and the title block.
    page.fill(x: 0, top: 0, width: SheetItems.pageWidth, height: SheetItems.pageHeight,
      palette.surface)
    page.stroke(
      x: 36.375, top: 36.375, width: 1151.25, height: 719.25, palette.muted, lineWidth: 0.75)
    page.fill(x: 912, top: 36, width: 0.75, height: 720, palette.muted)

    // Footnote.
    let footnote = footnoteLines(tooBig: tooBig, scaleDenominator: scaleDenominator)
    let footnoteTop = footnoteBottom - footnoteLine * Double(footnote.count)
    for (index, line) in footnote.enumerated() {
      page.text(
        line, x: footnoteX, lineTop: footnoteTop + footnoteLine * Double(index),
        lineHeight: footnoteLine, size: 7.5, color: palette.muted)
    }

    for block in blocks {
      let y = block.top
      switch block.name {
      case "A":
        page.items += ChapterLogo.items(
          x: x, y: SheetItems.y(y + logoHeight), height: logoHeight)
        for (index, line) in idLines.enumerated() {
          page.text(
            line, x: right, lineTop: y + 6 + 10 * Double(index), lineHeight: 10, size: 8.25,
            color: palette.muted, anchor: .trailing, tracking: 1.5)
        }
      case "B":
        var lineTop = y
        for line in titleLines {
          page.text(line, x: x, lineTop: lineTop, lineHeight: 28, size: 25.5, font: .timesRoman)
          lineTop += 28
        }
        lineTop += 4
        for line in line1 {
          page.text(line, x: x, lineTop: lineTop, lineHeight: 14, size: 11.25)
          lineTop += 14
        }
        lineTop += 4
        for runs in line2 {
          for run in runs {
            page.text(
              run.text, x: run.x, lineTop: lineTop, lineHeight: 11, size: 9, color: palette.muted)
          }
          lineTop += 11
        }
      case "C":
        for (index, row) in rows.enumerated() {
          let rowTop = y + rowHeight * Double(index)
          page.text(
            row.label, x: x, lineTop: rowTop + 4.5, lineHeight: 11, size: 9, color: palette.muted)
          page.text(
            row.value, x: right, lineTop: rowTop + 4.5, lineHeight: 11, size: row.size,
            font: row.font, anchor: .trailing)
          page.fill(x: x, top: rowTop + 20, width: width, height: 0.75, palette.line)
        }
      case "D":
        page.roundedRect(
          x: x + 0.375, top: y + 0.375, width: width - 0.75, height: block.height - 0.75,
          radius: 6, palette.line, lineWidth: 0.75)
        let textX = x + 10.75
        page.text(
          noteTitle, x: textX, lineTop: y + 8.75, lineHeight: 11, size: 9, font: .interSemiBold)
        for (index, line) in noteBody.enumerated() {
          page.text(
            line, x: textX, lineTop: y + 8.75 + 11 + 3 + 10.5 * Double(index), lineHeight: 10.5,
            size: 8.25, color: palette.muted)
        }
      case "E":
        page.text(
          "NOT SCANNED", x: x, lineTop: y, lineHeight: 9, size: 7.5, color: palette.muted,
          tracking: 1.5)
        var lineTop = y + 9 + 3
        for row in notScannedRows.prefix(shownRows) {
          page.text(
            SheetText.cut(row, size: 8.25, font: .interRegular, width: width), x: x,
            lineTop: lineTop, lineHeight: 10.5, size: 8.25)
          lineTop += 13.5
        }
        if overflow > 0 {
          page.text(
            "+\(overflow) more, listed in the spatial report", x: x, lineTop: lineTop,
            lineHeight: 10.5, size: 8.25, color: palette.muted)
          lineTop += 13.5
        }
        page.text(
          notScannedClosing, x: x, lineTop: lineTop, lineHeight: 9, size: 7.5,
          color: palette.muted)
      case "F":
        drawLegend(on: &page, top: y)
      case "G":
        drawScale(on: &page, x: x, top: y + scaleNorthHeight - 42, n: scaleDenominator)
        drawNorth(on: &page, symbol: north, right: right, bottom: y + scaleNorthHeight)
      default:
        break
      }
    }

    // H: footer.
    page.fill(x: x, top: footer.top, width: width, height: 0.75, palette.line)
    var lineTop = footer.top + 0.75 + 12
    for line in statement {
      page.text(line, x: x, lineTop: lineTop, lineHeight: 10.5, size: 8.25, color: palette.muted)
      lineTop += 10.5
    }
    lineTop += 8
    page.text(tagline, x: x, lineTop: lineTop, lineHeight: 13, size: 11.25, font: .timesItalic)
    page.text(
      website, x: right, lineTop: lineTop, lineHeight: 13, size: 8.25, color: palette.muted,
      anchor: .trailing)

    return PlanSheetLayout(
      blocks: blocks, footer: footer, gap: gap,
      notScannedShown: Array(notScannedRows.prefix(shownRows)), notScannedOverflow: overflow,
      footnoteLines: footnote, items: page.items)
  }

  // MARK: Legend, scale, north

  /// The legend (block F): kicker, then 4 rows × 2 columns (x 936 and 1044), each a 24 pt
  /// swatch and its label 31 pt to the right.
  static func drawLegend(on page: inout SheetItems, top: Double) {
    let palette = ChapterBrand.Sheet.self
    page.text(
      "LEGEND", x: blockX, lineTop: top, lineHeight: 9, size: 7.5, color: palette.muted,
      tracking: 1.5)
    let columns = [blockX, 1044.0]
    let labels = [
      ["Wall, scanned", "Window"], ["Door, no swing", "Open passage"],
      ["Object, box", "Low confidence"], ["Fixture symbol", "Habitable · wet · other"],
    ]
    for (row, pair) in labels.enumerated() {
      let rowTop = top + 9 + 5 + 15 * Double(row)
      for (column, label) in pair.enumerated() {
        let sx = columns[column]
        let swatchHeight = row == 3 && column == 0 ? 10.0 : 8.0
        let st = rowTop + (10 - swatchHeight) / 2
        switch (row, column) {
        case (0, 0):
          page.fill(x: sx, top: st + 1.5, width: 24, height: 5, palette.ink)
        case (0, 1):
          page.line(sx, st + 3, sx + 24, st + 3, palette.ink, width: 0.6)
          page.line(sx, st + 5, sx + 24, st + 5, palette.ink, width: 0.6)
        case (1, _):
          page.fill(x: sx, top: st + 1.5, width: 5, height: 5, palette.ink)
          page.fill(x: sx + 19, top: st + 1.5, width: 5, height: 5, palette.ink)
          page.line(
            sx + 5, st + 4, sx + 19, st + 4, palette.muted, width: 0.5,
            dash: column == 1 ? [2, 2] : [])
        case (2, _):
          page.stroke(
            x: sx + 4, top: st + 0.5, width: 16, height: 7, palette.muted, lineWidth: 0.6,
            dash: column == 1 ? [1.8, 1.2] : [], fill: palette.surface)
        case (3, 0):
          page.stroke(
            x: sx + 1, top: st + 0.5, width: 9, height: 9, palette.muted, lineWidth: 0.6,
            fill: palette.surface)
          var burners = PathBuilder()
          for (cx, cy) in [(3.6, 3.2), (7.4, 3.2), (3.6, 6.8), (7.4, 6.8)] {
            burners.circle(
              center: Point2(x: (sx + cx) / 1000, y: SheetItems.y(st + cy) / 1000),
              radius: 1.3 / 1000)
          }
          page.items.append(
            .shape(
              DrawingShape(
                path: burners.path, stroke: DrawingStroke(color: palette.muted, width: 0.5),
                layer: .sheet)))
          page.stroke(
            x: sx + 14, top: st + 0.5, width: 8, height: 2.5, palette.muted, lineWidth: 0.6,
            fill: palette.surface)
          var bowl = PathBuilder()
          bowl.ellipse(
            in: DrawingFrame(
              origin: Point2(x: (sx + 18) / 1000, y: SheetItems.y(st + 6.4) / 1000),
              u: Point2(x: 1, y: 0), v: Point2(x: 0, y: 1)), cx: 0, cy: 0, rx: 3.6 / 1000,
            ry: 3 / 1000)
          page.items.append(
            .shape(
              DrawingShape(
                path: bowl.path, fill: palette.surface,
                stroke: DrawingStroke(color: palette.muted, width: 0.6), layer: .sheet)))
        default:
          for (index, color) in [palette.nude, palette.wet, palette.ground].enumerated() {
            let cell = (x: sx + 8 * Double(index), top: st)
            page.items.append(
              .shape(
                DrawingShape(
                  path: SheetItems.rectPath(x: cell.x, top: cell.top, width: 8, height: 8),
                  fill: color, stroke: DrawingStroke(color: palette.line, width: 0.4),
                  layer: .sheet)))
          }
        }
        page.text(label, x: sx + 31, lineTop: rowTop, lineHeight: 10, size: 8.25)
      }
    }
  }

  /// Feet a scale bar of 86.4 pt (30.48 mm on paper) stands for at 1:`n`.
  static func scaleBarFeet(_ n: Int) -> Double { Double(n) / 10 }

  /// "2.5", "5", "10", "25": half the bar, as few digits as it needs.
  static func feetText(_ feet: Double) -> String {
    feet == feet.rounded() ? String(Int(feet)) : Format.compact(feet)
  }

  /// The scale block (part of G), its top at `top`: kicker, the 86.4 pt bar (first half
  /// solid), tick labels and the ratio line.
  static func drawScale(on page: inout SheetItems, x: Double, top: Double, n: Int) {
    let palette = ChapterBrand.Sheet.self
    page.text(
      "SCALE", x: x, lineTop: top, lineHeight: 9, size: 7.5, color: palette.muted, tracking: 1.5)
    let barTop = top + 9 + 6
    let half = 43.2
    page.fill(x: x + 0.5, top: barTop + 0.5, width: half, height: 5, palette.ink)
    page.fill(x: x + 0.5 + half, top: barTop + 0.5, width: half, height: 5, palette.surface)
    page.stroke(
      x: x + 0.5, top: barTop + 0.5, width: 2 * half, height: 5, palette.ink, lineWidth: 0.6)
    let feet = scaleBarFeet(n)
    let ticksTop = barTop + 6 + 3
    page.text("0", x: x + 0.5, lineTop: ticksTop, lineHeight: 9, size: 7.5, font: .courier)
    page.text(
      feetText(feet / 2), x: x + 0.5 + half, lineTop: ticksTop, lineHeight: 9, size: 7.5,
      font: .courier, anchor: .center)
    page.text(
      "\(feetText(feet)) ft", x: x + 0.5 + 2 * half, lineTop: ticksTop, lineHeight: 9, size: 7.5,
      font: .courier, anchor: .trailing)
    page.text(
      "1:\(n) at 11 x 17 in", x: x, lineTop: ticksTop + 9, lineHeight: 9, size: 7.5,
      font: .courier)
  }

  /// The north block (part of G), 40 pt, right-aligned at `right` with its foot at `bottom`.
  static func drawNorth(
    on page: inout SheetItems, symbol: NorthSymbol, right: Double, bottom: Double
  ) {
    let mm = 25.4 / 72
    let box = 40 * mm
    let size = NorthArrow.blockSizeMM(symbol: symbol, boxMM: box, caption: true)
    let extent = NorthArrow.blockExtentMM(symbol: symbol, boxMM: box, caption: true)
    let centerX = right - size.width / mm / 2
    let centerY = SheetItems.y(bottom) - extent.bottom / mm
    let place = SheetTransform(scale: 1 / mm, dx: 0, dy: 0)
    page.items += NorthArrow.items(
      symbol: symbol, centerMM: DrawingPoint(x: centerX * mm, y: centerY * mm), boxMM: box,
      page: ChapterBrand.Sheet.surface, caption: true, ink: ChapterBrand.Sheet.ink, layer: .sheet
    ).map(place.apply)
  }
}
