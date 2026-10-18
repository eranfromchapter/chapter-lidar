import CaptureContract
import Foundation

/// Spatial Report PDF: capture metadata, a per-room table (dimensions, area, height, openings,
/// recognized objects), an openings table and an objects table. Letter landscape, Helvetica text.
/// The report says that it is not a photo survey and that reported areas are not verified
/// construction quantities. Every page footer carries the address and the capture id.
public enum SpatialReportWriter {
  public static let fileName = "spatial-report.pdf"

  public static let statement =
    "This report lists measurements and recognized objects from one LiDAR capture. It is not a "
    + "photo survey and contains no site photographs. Reported areas are not verified "
    + "construction quantities. Check key dimensions against independent field measurements "
    + "before relying on them."

  public static func write(model: CaptureModel, context: PlanExportContext) throws
    -> ExportedFile
  {
    let geometry = try PlanGeometry(model: model)
    let flow = PDFFlow(width: 792, height: 612, margin: 36)

    flow.heading("Spatial Report", size: 20)
    flow.paragraph(context.address, size: 11, bold: true)
    flow.space(4)
    flow.paragraph(statement, size: 8.5)
    flow.space(8)

    // Capture details.
    flow.heading("Capture details", size: 12)
    var details: [(String, String)] = [
      ("Address", context.address),
      (
        "Address confirmed on site",
        context.addressConfirmedOnSite
          ? "Yes" + (context.addressConfirmedAt.map { " (\($0.rawValue))" } ?? "") : "No"
      ),
      ("Project", context.projectLine),
      ("Floor or area", "\(context.floorLabel) (\(context.areaKey))"),
      ("Capture id", context.captureId),
      ("Visit id", context.visitId),
      ("Capture mode", context.mode.rawValue),
      ("Captured at", "\(context.capturedAt.rawValue) (UTC)"),
    ]
    if let finished = context.finishedAt { details.append(("Finished at", "\(finished.rawValue) (UTC)")) }
    details += [
      ("Operator", context.operatorName),
      ("Device", context.deviceDescription),
      ("App version", context.appVersion),
      ("Display units", context.displayUnits.rawValue),
      ("Coverage notes", context.coverageNotes.isEmpty ? "None recorded" : context.coverageNotes),
      ("Rooms not scanned", noteList(context.omittedRooms)),
      ("Rooms not accessible", noteList(context.inaccessibleRooms)),
    ]
    flow.table(
      columns: [.init(title: "", width: 150, bold: true), .init(title: "", width: 570)],
      rows: details.map { [$0.0, $0.1] }, header: false)
    flow.space(10)

    // Rooms.
    flow.heading("Rooms", size: 12)
    if geometry.rooms.isEmpty {
      flow.paragraph("No rooms were recognized in this capture.", size: 9)
    } else {
      let objectsByRoom = Dictionary(grouping: geometry.objects) { $0.roomId ?? "" }
      var rows: [[String]] = []
      for room in geometry.rooms {
        let summary = Dictionary(
          grouping: objectsByRoom[room.id] ?? [], by: { $0.category.rawValue })
        let objects =
          summary.keys.sorted().map { key in
            let count = summary[key]?.count ?? 0
            let name = key.replacingOccurrences(of: "_", with: " ")
            return count > 1 ? "\(name) x\(count)" : name
          }.joined(separator: ", ")
        rows.append([
          "\(room.label)\n(\(room.id))",
          dimension(room.widthM),
          dimension(room.lengthM),
          dimension(room.heightM),
          "\(Format.fixed(room.areaM2, 2)) m\u{00B2}\n\(Format.squareFeet(squareMetres: room.areaM2)) sq ft",
          dimension(room.perimeterM),
          String(room.doorCount),
          String(room.windowCount),
          String(room.openingCount),
          objects.isEmpty ? "None" : objects,
        ])
      }
      flow.table(
        columns: [
          .init(title: "Room", width: 96, bold: true), .init(title: "Width", width: 70),
          .init(title: "Length", width: 70), .init(title: "Height", width: 70),
          .init(title: "Floor area", width: 64), .init(title: "Perimeter", width: 70),
          .init(title: "Doors", width: 38), .init(title: "Windows", width: 52),
          .init(title: "Openings", width: 54), .init(title: "Recognized objects", width: 136),
        ], rows: rows, header: true)
      let total = geometry.rooms.reduce(0) { $0 + $1.areaM2 }
      flow.space(4)
      flow.paragraph(
        "Total reported floor area: \(Format.fixed(total, 2)) m\u{00B2} "
          + "(\(Format.squareFeet(squareMetres: total)) sq ft). "
          + "Width and length are the room extent along the plan axes. Openings are passages "
          + "without a door or window. A door or window in a wall shared by two rooms counts "
          + "for both.",
        size: 7.5)
    }
    flow.space(10)

    // Openings.
    flow.heading("Doors, windows and openings", size: 12)
    if geometry.openings.isEmpty {
      flow.paragraph("None recognized.", size: 9)
    } else {
      let roomLabels = Dictionary(geometry.rooms.map { ($0.id, $0.label) }) { first, _ in first }
      let rows = geometry.openings.map { opening -> [String] in
        [
          opening.id, opening.kind.rawValue, opening.wallId, dimension(opening.widthM),
          dimension(opening.heightM), dimension(opening.bottomM),
          opening.roomIds.compactMap { roomLabels[$0] }.joined(separator: ", "),
        ]
      }
      flow.table(
        columns: [
          .init(title: "Id", width: 90, bold: true), .init(title: "Type", width: 70),
          .init(title: "Wall", width: 80), .init(title: "Width", width: 100),
          .init(title: "Height", width: 100), .init(title: "Bottom above floor", width: 100),
          .init(title: "Rooms", width: 180),
        ], rows: rows, header: true)
    }
    flow.space(10)

    // Objects.
    flow.heading("Recognized objects", size: 12)
    if geometry.objects.isEmpty {
      flow.paragraph("None recognized.", size: 9)
    } else {
      let roomLabels = Dictionary(geometry.rooms.map { ($0.id, $0.label) }) { first, _ in first }
      let rows = geometry.objects.map { object -> [String] in
        [
          object.id,
          object.category.rawValue.replacingOccurrences(of: "_", with: " "),
          object.roomId.flatMap { roomLabels[$0] } ?? "-",
          footprint(widthM: object.sizeM.x, depthM: object.sizeM.z),
          dimension(object.sizeM.y),
          object.confidence?.rawValue ?? "-",
        ]
      }
      flow.table(
        columns: [
          .init(title: "Id", width: 80, bold: true), .init(title: "Category", width: 100),
          .init(title: "Room", width: 130), .init(title: "Footprint (width x depth)", width: 210),
          .init(title: "Height", width: 110), .init(title: "Confidence", width: 90),
        ], rows: rows, header: true)
      flow.space(4)
      flow.paragraph(
        "Objects are oriented bounding boxes: reference geometry only, not a complete inventory.",
        size: 7.5)
    }

    flow.footer(
      left: "Chapter Capture Spatial Report - \(context.address)",
      right: "Capture \(context.captureId)")

    var document = PDFDocument(
      title: "Spatial Report - \(context.floorLabel) - \(context.address)",
      author: context.operatorName,
      subject: "Spatial Report, capture \(context.captureId)",
      creator: "\(PlanExportInfo.generator) \(PlanExportInfo.generatorVersion)",
      creationDate: context.pdfDate)
    document.pages = flow.pages
    return ExportedFile(
      fileName: fileName, role: .spatialReportPDF, mime: "application/pdf",
      data: document.render())
  }

  /// Whole millimetres and feet-inches on two lines.
  private static func dimension(_ metres: Double) -> String {
    "\(Format.millimetres(metres)) mm\n\(Format.feetInches(millimetres: metres * 1000))"
  }

  /// Width x depth: whole millimetres on the first line, feet-inches on the second.
  private static func footprint(widthM: Double, depthM: Double) -> String {
    "\(Format.millimetres(widthM)) x \(Format.millimetres(depthM)) mm\n"
      + "\(Format.feetInches(millimetres: widthM * 1000)) x "
      + Format.feetInches(millimetres: depthM * 1000)
  }

  private static func noteList(_ notes: [CaptureRecord.RoomNote]) -> String {
    if notes.isEmpty { return "None" }
    return notes.map { note in
      note.reason.map { "\(note.name) (\($0))" } ?? note.name
    }.joined(separator: "; ")
  }
}

/// Top-down page layout for text and tables. Coordinates are points; `y` runs down from the top.
final class PDFFlow {
  struct Column {
    var title: String
    var width: Double
    var bold = false
  }

  let width: Double
  let height: Double
  let margin: Double
  private(set) var pages: [PDFPage] = []
  private var page: PDFPage
  private var y: Double

  /// Space kept free at the bottom of each page for the footer.
  private let footerSpace = 24.0

  init(width: Double, height: Double, margin: Double) {
    self.width = width
    self.height = height
    self.margin = margin
    page = PDFPage(width: width, height: height)
    pages = [page]
    y = margin
  }

  private var bottom: Double { height - margin - footerSpace }

  private func newPage() {
    page = PDFPage(width: width, height: height)
    pages.append(page)
    y = margin
  }

  private func ensure(_ needed: Double) {
    if y + needed > bottom { newPage() }
  }

  /// Baseline in PDF coordinates for a text line whose top is at `top` (down from page top).
  private func baseline(_ top: Double, size: Double) -> Double {
    height - top - size * 0.8
  }

  func space(_ amount: Double) { y += amount }

  func heading(_ text: String, size: Double) {
    // Keep a heading with the start of what follows it.
    ensure(size * 2.4 + 60)
    page.setFillGray(0)
    page.text(text, x: margin, y: baseline(y, size: size), size: size, bold: true)
    y += size * 1.5
  }

  func paragraph(_ text: String, size: Double, bold: Bool = false) {
    let lineHeight = size * 1.3
    for line in PlanPDFWriter.wrap(text, size: size, width: width - 2 * margin, bold: bold) {
      ensure(lineHeight)
      page.setFillGray(0)
      page.text(line, x: margin, y: baseline(y, size: size), size: size, bold: bold)
      y += lineHeight
    }
  }

  func table(columns: [Column], rows: [[String]], header: Bool) {
    let size = 8.0
    let lineHeight = size * 1.25
    let pad = 3.0
    let totalWidth = columns.reduce(0) { $0 + $1.width }

    func lines(_ row: [String], bold: Bool = false) -> [[String]] {
      row.enumerated().map { index, text in
        PlanPDFWriter.wrap(
          text, size: size, width: columns[index].width - 2 * pad,
          bold: bold || columns[index].bold)
      }
    }
    func rowHeightOf(_ cells: [[String]]) -> Double {
      Double(cells.map(\.count).max() ?? 1) * lineHeight + 2 * pad
    }
    func draw(_ cells: [[String]], bold: Bool, fill: Double?) {
      let rowHeight = rowHeightOf(cells)
      let top = y
      if let fill {
        page.setFillGray(fill)
        page.rect(
          x: margin, y: height - top - rowHeight, width: totalWidth, height: rowHeight,
          stroke: false, fill: true)
      }
      page.setStrokeGray(0.6)
      page.setLineWidth(0.4)
      page.rect(
        x: margin, y: height - top - rowHeight, width: totalWidth, height: rowHeight,
        stroke: true, fill: false)
      var x = margin
      for (index, cellLines) in cells.enumerated() {
        if index > 0 {
          page.line((x, height - top), (x, height - top - rowHeight))
        }
        page.setFillGray(0)
        for (lineIndex, line) in cellLines.enumerated() {
          page.text(
            line, x: x + pad,
            y: baseline(top + pad + Double(lineIndex) * lineHeight, size: size), size: size,
            bold: bold || columns[index].bold)
        }
        x += columns[index].width
      }
      y += rowHeight
    }

    let headerCells = lines(columns.map(\.title), bold: true)
    if header {
      ensure(rowHeightOf(headerCells) + lineHeight * 2 + 2 * pad)
      draw(headerCells, bold: true, fill: 0.88)
    }
    for row in rows {
      let cells = lines(row)
      if y + rowHeightOf(cells) > bottom {
        newPage()
        if header { draw(headerCells, bold: true, fill: 0.88) }
      }
      draw(cells, bold: false, fill: nil)
    }
  }

  /// Footer on every page: `left`, then `right` and the page number at the right edge.
  func footer(left: String, right: String) {
    let size = 7.0
    for (index, page) in pages.enumerated() {
      page.setStrokeGray(0.6)
      page.setLineWidth(0.4)
      page.line((margin, margin + 8), (width - margin, margin + 8))
      page.setFillGray(0.25)
      page.text(left, x: margin, y: margin - 2, size: size)
      page.text(
        "\(right) - page \(index + 1) of \(pages.count)", x: width - margin, y: margin - 2,
        size: size, anchor: .trailing)
    }
  }
}
