import CaptureContract
import CaptureUI
import ChapterUI
import Foundation
import Observation
import PlanExport
import SwiftUI
import UIKit

private typealias Palette = ChapterTokens.Palette
private typealias Space = ChapterTokens.Space
private typealias Typo = ChapterTokens.Typography
private typealias Control = ChapterTokens.Control
private typealias Radius = ChapterTokens.Radius

/// Writes the plan sheet of one scan (PlanExport's `PlanSheetWriter`, the Tabloid 11 x 17 in
/// page the package carries as `plan-sheet.pdf`) and the file to share. Pure functions, run off
/// the main actor.
enum PlanSheetFiles {
  /// The aspect of the sheet: 1224 x 792 pt, landscape.
  static let aspect: CGFloat = 1224.0 / 792.0
  /// The sheet's page colour (#FAF5EE), around the page on screen too.
  static let page = UIColor(red: 0xFA / 255, green: 0xF5 / 255, blue: 0xEE / 255, alpha: 1)

  static func pdf(model: CaptureModel, context: PlanExportContext) throws -> Data {
    try PlanSheetWriter.write(model: model, context: context).file.data
  }

  /// Writes `plan-sheet.pdf` into `folder` (replacing an earlier one).
  static func write(pdf: Data, into folder: URL) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(PlanSheetWriter.fileName)
    try pdf.write(to: url, options: .atomic)
    return url
  }
}

/// The plan sheet on screen: written once (it is always imperial, whatever the Floorplan's
/// units), then its share file.
@MainActor @Observable
final class PlanSheetModel {
  let model: CaptureModel
  /// The title block's data: the capture record's, as the package's sheet has it, or
  /// "not recorded" for a scan without one.
  let context: PlanExportContext
  @ObservationIgnored private let exportName: String
  private(set) var pdf: Data?
  /// `plan-sheet.pdf`, once written.
  private(set) var file: URL?
  private(set) var errorMessage: String?

  init(model: CaptureModel, context: PlanExportContext, exportName: String) {
    self.model = model
    self.context = context
    self.exportName = exportName
  }

  func write() async {
    let model = self.model
    let context = self.context
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("plan-sheet-\(exportName)", isDirectory: true)
    errorMessage = nil
    do {
      let pdf = try await Task.detached(priority: .userInitiated) {
        try PlanSheetFiles.pdf(model: model, context: context)
      }.value
      self.pdf = pdf
      file = try await Task.detached(priority: .utility) {
        try PlanSheetFiles.write(pdf: pdf, into: folder)
      }.value
    } catch {
      errorMessage = "The plan sheet could not be drawn: \(error.localizedDescription)"
    }
  }
}

/// The plan sheet card: the whole sheet at its own shape (pinch to zoom, double-tap to zoom in),
/// Full screen, and Download, which shares plan-sheet.pdf.
struct PlanSheetView: View {
  let sheet: PlanSheetModel
  @State private var showsFullScreen = false

  var body: some View {
    VStack(spacing: Space.s2) {
      ZStack {
        Color(uiColor: PlanSheetFiles.page)
        if let pdf = sheet.pdf {
          PDFPageView(data: pdf, maxZoom: 12, background: PlanSheetFiles.page, edgeToEdge: true)
            .accessibilityLabel("Plan sheet")
            .accessibilityIdentifier("plansheet.page")
        } else if let message = sheet.errorMessage {
          Text(message).font(Typo.caption).foregroundStyle(Palette.blocked).padding()
        } else {
          PlanSheetProgress()
        }
      }
      .aspectRatio(PlanSheetFiles.aspect, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: Radius.card))
      .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))

      HStack(spacing: Space.s2) {
        Button {
          showsFullScreen = true
        } label: {
          PlanChip {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
            Text("Full screen")
          }
        }
        .buttonStyle(.plain)
        .disabled(sheet.pdf == nil)
        .accessibilityIdentifier("plansheet.fullScreen")
        Spacer()
        PlanSheetDownload(sheet: sheet)
      }
    }
    .fullScreenCover(isPresented: $showsFullScreen) {
      PlanSheetFullScreen(sheet: sheet)
    }
  }
}

/// "Drawing the plan sheet…" in Inter.
private struct PlanSheetProgress: View {
  var body: some View {
    VStack(spacing: Space.s2) {
      ProgressView().tint(Palette.muted)
      Text("Drawing the plan sheet\u{2026}").font(Typo.caption).foregroundStyle(Palette.muted)
    }
  }
}

/// Download: shares plan-sheet.pdf once it is written; dimmed until then.
private struct PlanSheetDownload: View {
  let sheet: PlanSheetModel

  var body: some View {
    if let file = sheet.file {
      ShareLink(item: file) {
        PlanChip {
          Image(systemName: "arrow.down.circle")
          Text("Download")
        }
      }
      .accessibilityLabel("Download plan sheet, PDF")
      .accessibilityIdentifier("plansheet.download")
    } else {
      PlanChip {
        if sheet.errorMessage == nil { ProgressView().controlSize(.small).tint(Palette.muted) }
        Image(systemName: "arrow.down.circle")
        Text("Download")
      }
      .opacity(0.5)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("plansheet.download")
      .accessibilityAddTraits(.isButton)
      .accessibilityHint("The plan sheet is being written.")
    }
  }
}

/// A 44 pt chip in Inter SemiBold, ink on surface (no system tint).
struct PlanChip<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 6) { content }
      .font(Typo.sans(15, weight: .semibold))
      .foregroundStyle(Palette.ink)
      .padding(.horizontal, Space.s3)
      .frame(minHeight: Control.minTouch)
      .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.chip))
      .overlay(RoundedRectangle(cornerRadius: Radius.chip).stroke(Palette.line, lineWidth: 1))
  }
}

/// The plan sheet on the whole screen. The app is portrait, so the landscape sheet is turned a
/// quarter clockwise to fill it: turn the phone to read it. "Upright" turns it back. Pinch to
/// zoom; Download shares plan-sheet.pdf.
struct PlanSheetFullScreen: View {
  let sheet: PlanSheetModel
  @State private var turned = true
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: Space.s2) {
        Button { dismiss() } label: {
          Image(systemName: "xmark").font(ChapterTheme.Font.bodyEmphasis)
            .frame(width: Control.minTouch, height: Control.minTouch)
        }
        .accessibilityLabel("Close")
        .accessibilityIdentifier("plansheet.fullScreen.close")
        Spacer()
        Text(sheet.context.floorLabel).font(Typo.sans(15, weight: .semibold)).lineLimit(1)
        Spacer()
        Button { turned.toggle() } label: {
          Image(systemName: turned ? "rotate.left" : "rotate.right")
            .font(ChapterTheme.Font.bodyEmphasis)
            .frame(width: Control.minTouch, height: Control.minTouch)
        }
        .accessibilityLabel(turned ? "Upright" : "Turn to fill the screen")
        .accessibilityIdentifier("plansheet.fullScreen.rotate")
        if let file = sheet.file {
          ShareLink(item: file) {
            Image(systemName: "square.and.arrow.up").font(ChapterTheme.Font.bodyEmphasis)
              .frame(width: Control.minTouch, height: Control.minTouch)
          }
          .accessibilityLabel("Download plan sheet, PDF")
        }
      }
      .foregroundStyle(Palette.ink)
      .padding(.horizontal, Space.s4)

      ZStack {
        Color(uiColor: PlanSheetFiles.page)
        if let pdf = sheet.pdf {
          PDFPageView(
            data: pdf, rotation: turned ? 90 : 0, maxZoom: 12, background: PlanSheetFiles.page,
            edgeToEdge: true)
            .accessibilityLabel("Plan sheet")
            .accessibilityIdentifier("plansheet.fullScreen.page")
        }
      }
      .overlay(alignment: .bottom) {
        Text(turned ? "Turn the phone to read the sheet" : "Pinch to zoom")
          .font(Typo.caption).foregroundStyle(Palette.muted)
          .padding(.horizontal, Space.s3).padding(.vertical, Space.s1)
          .background(Palette.surface.opacity(0.9), in: Capsule())
          .padding(.bottom, Space.s3)
      }
    }
    .background(Palette.surface.ignoresSafeArea())
  }
}

/// The colour Floorplan (`FloorplanWriter`), opened from the plan sheet's screen: the plan
/// alone with its Units choice and its own Download (floorplan.pdf and floorplan.png), written
/// when the screen first opens.
struct ColourFloorplanScreen: View {
  let floorplan: FloorplanModel

  var body: some View {
    FloorplanView(floorplan: floorplan)
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .padding(.top, 8)
      .padding(.bottom, ChapterTheme.Metric.actionBarBottom)
      .chapterContentWidth()
      .navigationTitle("Colour floorplan")
      .navigationBarTitleDisplayMode(.inline)
      .chapterBackChevronOnly()
      .chapterScreenBackground()
      .task {
        if floorplan.screen == nil, !floorplan.isWriting { await floorplan.write() }
      }
  }
}
