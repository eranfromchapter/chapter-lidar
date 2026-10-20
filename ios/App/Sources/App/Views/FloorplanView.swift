import CaptureContract
import CaptureUI
import CoreGraphics
import Foundation
import ImageIO
import Observation
import PDFKit
import PlanExport
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private typealias Palette = ChapterTokens.Palette
private typealias Space = ChapterTokens.Space
private typealias Typo = ChapterTokens.Typography
private typealias Control = ChapterTokens.Control
private typealias Radius = ChapterTokens.Radius

/// Writes the Floorplan of one scan (PlanExport's `FloorplanWriter`) and the files to share:
/// `floorplan.pdf`, and `floorplan.png` drawn from that PDF at 300 dpi; and the plan alone for
/// the screen. Pure functions, run off the main actor.
enum FloorplanFiles {
  static let dpi: CGFloat = 300

  struct Failure: LocalizedError {
    var errorDescription: String?
  }

  /// The one-page Floorplan PDF.
  static func pdf(model: CaptureModel, address: String?, units: DisplayUnitSystem) throws -> Data {
    let options = FloorplanWriter.Options(address: address, units: UnitFormatter(system: units))
    return try FloorplanWriter.pdf(model: model, options: options)
  }

  /// The plan alone, laid out for a phone's width so its names and dimensions read at a glance
  /// (no title or footer: the screen has its own).
  static func screenPDF(model: CaptureModel, units: DisplayUnitSystem) throws -> Data {
    let options = FloorplanWriter.Options(units: UnitFormatter(system: units))
    return try FloorplanWriter.screenPDF(model: model, options: options)
  }

  /// The PDF's first page as a PNG at `dpi` on white, with that resolution in the file so it
  /// prints at the page's size.
  static func png(pdf: Data, dpi: CGFloat = dpi) throws -> Data {
    guard let provider = CGDataProvider(data: pdf as CFData),
      let document = CGPDFDocument(provider), let page = document.page(at: 1)
    else { throw Failure(errorDescription: "The floor plan PDF could not be read.") }
    let box = page.getBoxRect(.mediaBox)
    let scale = dpi / 72
    let width = Int((box.width * scale).rounded())
    let height = Int((box.height * scale).rounded())
    guard width > 0, height > 0,
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw Failure(errorDescription: "The floor plan image could not be drawn.") }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -box.minX, y: -box.minY)
    context.drawPDFPage(page)
    let out = NSMutableData()
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithData(
        out, UTType.png.identifier as CFString, 1, nil)
    else { throw Failure(errorDescription: "The floor plan image could not be written.") }
    let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw Failure(errorDescription: "The floor plan image could not be written.")
    }
    return out as Data
  }

  /// Writes `floorplan.pdf` and `floorplan.png` into `folder` (replacing earlier ones).
  static func write(pdf: Data, into folder: URL) throws -> [URL] {
    let png = try png(pdf: pdf)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let pdfURL = folder.appendingPathComponent("floorplan.pdf")
    let pngURL = folder.appendingPathComponent("floorplan.png")
    try pdf.write(to: pdfURL, options: .atomic)
    try png.write(to: pngURL, options: .atomic)
    return [pdfURL, pngURL]
  }
}

/// The Floorplan on screen: written for the chosen units, then its share files.
@MainActor @Observable
final class FloorplanModel {
  let model: CaptureModel
  let address: String?
  /// Where the share files go: one folder per scan and unit system, under the temporary folder.
  @ObservationIgnored private let exportName: String
  private(set) var units: DisplayUnitSystem
  private(set) var pdf: Data?
  /// The plan alone, shown on screen.
  private(set) var screen: Data?
  /// `floorplan.pdf` and `floorplan.png`, once written for the current units.
  private(set) var files: [URL] = []
  private(set) var isWriting = false
  private(set) var errorMessage: String?
  @ObservationIgnored private var generation = 0

  init(model: CaptureModel, address: String?, units: DisplayUnitSystem, exportName: String) {
    self.model = model
    self.address = address
    self.units = units
    self.exportName = exportName
  }

  /// Writes the plan in `units` (the current units when nil): first the screen version, shown
  /// at once, then the page PDF, the PNG and both files. A newer request makes an older one's
  /// results be dropped.
  func write(units newUnits: DisplayUnitSystem? = nil) async {
    if let newUnits { units = newUnits }
    generation += 1
    let current = generation
    let units = self.units
    let model = self.model
    let address = self.address
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("floorplan-\(exportName)", isDirectory: true)
      .appendingPathComponent(units.rawValue, isDirectory: true)
    isWriting = true
    files = []
    errorMessage = nil
    do {
      let screen = try await Task.detached(priority: .userInitiated) {
        try FloorplanFiles.screenPDF(model: model, units: units)
      }.value
      guard current == generation else { return }
      self.screen = screen
      let pdf = try await Task.detached(priority: .userInitiated) {
        try FloorplanFiles.pdf(model: model, address: address, units: units)
      }.value
      guard current == generation else { return }
      self.pdf = pdf
      let files = try await Task.detached(priority: .utility) {
        try FloorplanFiles.write(pdf: pdf, into: folder)
      }.value
      guard current == generation else { return }
      self.files = files
    } catch {
      guard current == generation else { return }
      errorMessage = "The floor plan could not be drawn: \(error.localizedDescription)"
    }
    isWriting = false
  }
}

/// The Floorplan card: the plan alone, filling the card (pinch to zoom, double-tap to zoom
/// in), a Units menu that rewrites it in feet-inches or metres, and Download, which shares the
/// full page as floorplan.pdf and a 300 dpi floorplan.png.
struct FloorplanView: View {
  let floorplan: FloorplanModel

  var body: some View {
    VStack(spacing: Space.s2) {
      HStack(spacing: Space.s2) {
        unitsMenu
        Spacer()
        download
      }
      ZStack {
        Color.white
        if let screen = floorplan.screen {
          PDFPageView(data: screen)
            .accessibilityLabel("Floor plan")
            .accessibilityIdentifier("floorplan.page")
        } else if let message = floorplan.errorMessage {
          Text(message).font(Typo.caption).foregroundStyle(Palette.blocked).padding()
        } else {
          ProgressView("Drawing the floor plan…")
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: Radius.card))
      .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))
      .overlay(alignment: .bottomTrailing) {
        if floorplan.screen != nil {
          Text("Pinch to zoom").font(Typo.caption).foregroundStyle(Palette.muted)
            .padding(Space.s2)
        }
      }
    }
  }

  private var unitsMenu: some View {
    Menu {
      Picker(
        "Units",
        selection: Binding(
          get: { floorplan.units },
          set: { units in Task { await floorplan.write(units: units) } })
      ) {
        Text("Imperial (ft-in)").tag(DisplayUnitSystem.imperial)
        Text("Metric (m)").tag(DisplayUnitSystem.metric)
      }
    } label: {
      chip {
        Image(systemName: "ruler")
        Text(floorplan.units == .imperial ? "ft-in" : "m")
        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
      }
    }
    .accessibilityLabel("Units, \(floorplan.units == .imperial ? "feet and inches" : "metres")")
    .accessibilityIdentifier("floorplan.units")
  }

  @ViewBuilder private var download: some View {
    if floorplan.files.isEmpty {
      chip {
        if floorplan.isWriting { ProgressView().controlSize(.small) }
        Image(systemName: "arrow.down.circle")
        Text("Download")
      }
      .opacity(0.5)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("floorplan.download")
      .accessibilityAddTraits(.isButton)
      .accessibilityHint("The files are being written.")
    } else {
      ShareLink(items: floorplan.files) {
        chip {
          Image(systemName: "arrow.down.circle")
          Text("Download")
        }
      }
      .accessibilityLabel("Download floor plan, PDF and PNG")
      .accessibilityIdentifier("floorplan.download")
    }
  }

  private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: 6) { content() }
      .font(Typo.sans(15, weight: .semibold))
      .foregroundStyle(Palette.ink)
      .padding(.horizontal, Space.s3)
      .frame(minHeight: Control.minTouch)
      .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.chip))
      .overlay(RoundedRectangle(cornerRadius: Radius.chip).stroke(Palette.line, lineWidth: 1))
  }
}

/// One PDF page in PDFKit's view, fitted to the view: pinch to zoom up to 8x, never smaller
/// than the whole page.
private struct PDFPageView: UIViewRepresentable {
  let data: Data

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> FittedPDFView {
    let view = FittedPDFView()
    view.displayMode = .singlePage
    view.displayDirection = .vertical
    view.pageShadowsEnabled = false
    view.backgroundColor = .white
    view.autoScales = true
    load(view, context: context)
    return view
  }

  func updateUIView(_ view: FittedPDFView, context: Context) {
    if context.coordinator.data != data { load(view, context: context) }
  }

  private func load(_ view: FittedPDFView, context: Context) {
    context.coordinator.data = data
    view.document = PDFDocument(data: data)
    view.autoScales = true
  }

  final class Coordinator {
    var data: Data?
  }
}

/// PDFView that keeps its zoom between the whole page and 8x the whole page.
final class FittedPDFView: PDFView {
  override func layoutSubviews() {
    super.layoutSubviews()
    let fit = scaleFactorForSizeToFit
    guard fit > 0 else { return }
    if minScaleFactor != fit { minScaleFactor = fit }
    if maxScaleFactor != fit * 8 { maxScaleFactor = fit * 8 }
  }
}
