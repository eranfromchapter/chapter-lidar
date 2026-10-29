import AppCore
import CaptureContract
import CaptureModelMapping
import CaptureUI
import ChapterUI
import FieldRules
import Foundation
import Observation
import PlanExport
import RoomPlan
import SceneKit
import SketchSolver
import SwiftUI
import UIKit

private typealias Palette = ChapterTokens.Palette
private typealias Space = ChapterTokens.Space
private typealias Typo = ChapterTokens.Typography
private typealias Control = ChapterTokens.Control
private typealias Radius = ChapterTokens.Radius

/// One scanned floor or area on this phone: the folder that holds its `roomplan.json`
/// (`<visit>/originals/Original Exports/<areaKey>/<captureId>/`), with the visit's address,
/// the capture's display units and the time it was captured when they are known.
struct ScanItem: Identifiable, Hashable {
  var folder: URL
  var title: String
  /// When `roomplan.json` was written.
  var date: Date
  var address: String? = nil
  var displayUnits: DisplayUnitSystem? = nil
  /// The capture time in the capture record.
  var capturedAt: Date? = nil
  /// The capture's own label in the capture record, when known. The plan is mapped with it,
  /// as the visit mapped it, so the rooms get the same labels and the names below apply.
  var captureLabel: String? = nil
  /// The operator's names for rooms of this scan (the visit's `room-names.json`).
  var roomNames: [RoomName] = []
  /// The capture's compass, for the Floorplan's north symbol (compass §6.3); nil for a scan
  /// without a capture record (nothing is drawn).
  var north: CompassState? = nil
  /// The plan sheet's title block, from the capture record as the package's `plan-sheet.pdf`
  /// has it; nil for a scan without a capture record (the sheet then says "not recorded").
  var planContext: PlanExportContext? = nil
  var id: String { folder.path }

  /// When the scan was made: the capture record's time, else the file's.
  var scanDate: Date { capturedAt ?? date }

  /// A sketch capture (spec F14): the folder holds `sketch-measurements.json`, not
  /// `roomplan.json`; its plan is solved from the measurements and it has no RoomPlan 3D model.
  var isSketch: Bool {
    FileManager.default.fileExists(
      atPath: folder.appendingPathComponent(ScanLibrary.sketchFile).path)
  }
}

/// One scan's folder as the viewer needs it (the Capture overview's floor rows, a v1 visit's
/// scans). Reads; changes nothing.
enum ScanLibrary {
  static let roomPlanFile = "roomplan.json"
  static let sketchFile = PackageLayout.sketchMeasurementsFileName

  static func item(
    folder: URL, title: String, address: String? = nil, displayUnits: DisplayUnitSystem? = nil,
    capturedAt: Date? = nil, captureLabel: String? = nil, roomNames: [RoomName] = []
  ) -> ScanItem? {
    // The scan's RoomPlan file, or a sketch capture's measurements (spec F14).
    let file = [roomPlanFile, sketchFile].map(folder.appendingPathComponent).first {
      FileManager.default.fileExists(atPath: $0.path)
    }
    guard let file,
      let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
      let date = values.contentModificationDate
    else { return nil }
    return ScanItem(
      folder: folder, title: title, date: date, address: address, displayUnits: displayUnits,
      capturedAt: capturedAt, captureLabel: captureLabel, roomNames: roomNames)
  }

  /// "floor-1" → "Floor 1".
  static func title(areaKey: String) -> String {
    let words = areaKey.split(whereSeparator: { $0 == "-" || $0 == "_" })
    return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
  }
}

/// Loads one scan for viewing: the plan sheet, the colour Floorplan and the measurements from our
/// own mapping, and (on request) a USDZ model from Apple's RoomPlan export for the 3D view.
@MainActor @Observable
final class ScanViewerModel {
  let item: ScanItem
  /// The plan sheet (`PlanSheetWriter`), the screen's main view.
  private(set) var planSheet: PlanSheetModel?
  /// The colour Floorplan (`FloorplanWriter`), written when its screen opens.
  private(set) var floorplan: FloorplanModel?
  private(set) var measurements: ScanMeasurements?
  private(set) var counts: String?
  private(set) var errorMessage: String?
  private(set) var isLoading = true
  private(set) var isExporting = false
  var modelURL: URL?

  init(item: ScanItem) {
    self.item = item
  }

  func load() async {
    defer { isLoading = false }
    let file = item.folder.appendingPathComponent(ScanLibrary.roomPlanFile)
    let label = item.captureLabel ?? item.title
    let names = item.roomNames
    let planContext = item.planContext
    // With the capture record's ids, as the package maps it, so the sheet shows the same rooms.
    let mapping = MappingContext(
      visitId: planContext.flatMap { LowercaseUUID(rawValue: $0.visitId) } ?? LowercaseUUID(),
      captureId: planContext.flatMap { LowercaseUUID(rawValue: $0.captureId) } ?? LowercaseUUID(),
      areaKey: planContext?.areaKey ?? "scan", label: label)
    let sketchFile = item.folder.appendingPathComponent(ScanLibrary.sketchFile)
    let isSketch = item.isSketch
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        let model: CaptureModel
        if isSketch {
          // A sketch capture: solved again from the measurements, with the operator's names
          // applied by room id as the package's capture model has them (VisitPackageBuilder).
          let measurements = try CaptureContractJSON.makeDecoder().decode(
            SketchMeasurements.self, from: try Data(contentsOf: sketchFile))
          var solved = try SketchSolver.solve(
            measurements, context: SketchSolveContext(label: mapping.label)
          ).model
          for (index, room) in RoomNaming.scannedRooms(of: solved).enumerated() {
            if let name = names.first(where: { RoomNaming.applies($0, to: room) }) {
              solved.rooms[index].label = name.name
            }
          }
          model = solved
        } else {
          let data = try Data(contentsOf: file)
          let document = try RoomPlanDocument.decode(from: data)
          // With the operator's room names, as the package's capture model has them.
          model = try RoomNaming.map(document, context: mapping, names: names).model
        }
        return (model, ScanMeasurements(model: model), model.walls.count, model.rooms.count)
      }.value
      measurements = result.1
      counts = "\(result.3) \(result.3 == 1 ? "room" : "rooms") \u{00B7} \(result.2) walls"
      self.floorplan = FloorplanModel(
        model: result.0, address: item.address, units: item.displayUnits ?? .imperial,
        capturedAt: item.scanDate, north: item.north, exportName: item.folder.lastPathComponent)
      let context =
        planContext
        ?? PlanExportContext(
          unrecordedScan: item.title, capturedAt: UTCTimestamp(item.scanDate),
          address: item.address, compass: item.north)
      let sheet = PlanSheetModel(
        model: result.0, context: context, exportName: item.folder.lastPathComponent)
      planSheet = sheet
      isLoading = false
      await sheet.write()
    } catch {
      errorMessage = "This scan could not be drawn: \(error.localizedDescription)"
    }
  }

  /// Exports Apple's 3D model of the scan once, then opens it in the 3D view. The cached file is
  /// named after the capture folder (the capture id), so it is found again after a relaunch.
  func open3D() async {
    let target = FileManager.default.temporaryDirectory
      .appendingPathComponent("scan-\(item.folder.lastPathComponent).usdz")
    if FileManager.default.fileExists(atPath: target.path) {
      modelURL = target
      return
    }
    isExporting = true
    defer { isExporting = false }
    let file = item.folder.appendingPathComponent(ScanLibrary.roomPlanFile)
    do {
      try await Task.detached(priority: .userInitiated) {
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          object["rooms"] != nil
        {
          try decoder.decode(CapturedStructure.self, from: data).export(
            to: target, exportOptions: .parametric)
        } else {
          try decoder.decode(CapturedRoom.self, from: data).export(
            to: target, exportOptions: .parametric)
        }
      }.value
      modelURL = target
    } catch {
      errorMessage = "The 3D model could not be made: \(error.localizedDescription)"
    }
  }
}

/// One scan, pushed from its floor row on the Capture overview (or from a v1 visit's scans): the
/// plan sheet (the package's `plan-sheet.pdf`, pinch to zoom, full screen, download), "Colour
/// floorplan" (the colour Floorplan with its units and download), the measurements and a 3D view
/// of the model. Inline title = the floor's label; the system back chevron returns (no "Done").
struct ScanViewer: View {
  @State private var model: ScanViewerModel
  @State private var showsColourFloorplan = false

  init(item: ScanItem) {
    _model = State(initialValue: ScanViewerModel(item: item))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text(subtitle)
          .chapterTextStyle(.subhead)
          .foregroundStyle(ChapterTheme.Color.muted)
          .lineLimit(2)

        if let sheet = model.planSheet {
          PlanSheetView(sheet: sheet)
        } else {
          ZStack {
            ChapterTheme.Color.surface
            if model.isLoading {
              VStack(spacing: 8) {
                ProgressView().tint(ChapterTheme.Color.muted)
                Text("Drawing the plan sheet\u{2026}")
                  .chapterTextStyle(.footnote)
                  .foregroundStyle(ChapterTheme.Color.muted)
              }
            } else {
              Text(model.errorMessage ?? "No plan sheet")
                .chapterTextStyle(.footnote)
                .foregroundStyle(ChapterTheme.Color.blocked).padding()
            }
          }
          .aspectRatio(PlanSheetFiles.aspect, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius))
          .overlay(
            RoundedRectangle(cornerRadius: ChapterTheme.Metric.cardRadius)
              .strokeBorder(ChapterTheme.Color.line, lineWidth: ChapterTheme.Metric.cardBorder))
        }

        Button {
          showsColourFloorplan = true
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "square.grid.3x3.square")
            Text("Colour floorplan")
          }
        }
        .buttonStyle(.chapter(.tinted))
        .disabled(model.floorplan == nil)
        .accessibilityHint("The plan alone in colour, with its units and download.")
        .accessibilityIdentifier("scan.colourFloorplan")

        if let scan = model.measurements {
          measurements(scan, units: model.floorplan?.units ?? .imperial)
        }

        // A sketch capture has no RoomPlan model to show in 3D; its mesh is in the package.
        if !model.item.isSketch {
          Button {
            Task { await model.open3D() }
          } label: {
            HStack(spacing: 8) {
              if model.isExporting { ProgressView().tint(ChapterTheme.Color.surface) }
              Image(systemName: "cube")
              Text(model.isExporting ? "Making the 3D model\u{2026}" : "View in 3D")
            }
          }
          .buttonStyle(.chapter(.primary))
          .disabled(model.isExporting)
          .accessibilityIdentifier("scan.view3D")
        }
      }
      .padding(.horizontal, ChapterTheme.Metric.screenPadding)
      .padding(.top, 8)
      .padding(.bottom, ChapterTheme.Metric.actionBarBottom)
      .chapterContentWidth()
    }
    .navigationTitle(model.item.title)
    .navigationBarTitleDisplayMode(.inline)
    .chapterBackChevronOnly()
    .chapterScreenBackground()
    .navigationDestination(isPresented: $showsColourFloorplan) {
      if let floorplan = model.floorplan {
        ColourFloorplanScreen(floorplan: floorplan)
      }
    }
    .fullScreenCover(item: $model.modelURL) { url in
      ModelViewer(url: url, title: model.item.title)
    }
    .task { await model.load() }
  }

  /// "Oct 20, 2026 at 14:12 · 12 rooms · 40 walls".
  private var subtitle: String {
    model.item.scanDate.formatted(date: .abbreviated, time: .shortened)
      + (model.counts.map { " \u{00B7} \($0)" } ?? "")
  }

  /// The measurements in the units the Floorplan is shown in, written as the plan writes them.
  private func measurements(_ scan: ScanMeasurements, units: DisplayUnitSystem) -> some View {
    let formatter = UnitFormatter(system: units)
    let length = { (millimetres: Double) in formatter.dimension(millimetres / 1000) }
    let ceiling: String = {
      let heights = scan.ceilingHeights.map(\.heightMm)
      guard let low = heights.min(), let high = heights.max() else { return "\u{2014}" }
      let lowText = length(low)
      let highText = length(high)
      return lowText == highText ? lowText : "\(lowText) \u{2013} \(highText)"
    }()
    return ChapterCard {
      MeasureRow(title: "Long distance A", value: scan.distanceAMm.map(length) ?? "\u{2014}")
      MeasureRow(title: "Long distance B", value: scan.distanceBMm.map(length) ?? "\u{2014}")
      MeasureRow(title: "Ceiling height", value: ceiling)
      MeasureRow(title: "Openings", value: scan.openingsSummary)
    }
  }
}

/// One measurement: label and value on one line, 40 pt, the scan viewer's compact rows.
private struct MeasureRow: View {
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: ChapterTheme.Metric.rowGap) {
      Text(title)
        .chapterTextStyle(.subhead)
        .foregroundStyle(ChapterTheme.Color.ink)
      Spacer(minLength: 8)
      Text(value)
        .chapterTextStyle(.subhead)
        .foregroundStyle(ChapterTheme.Color.muted)
        .multilineTextAlignment(.trailing)
    }
    .padding(.horizontal, ChapterTheme.Metric.rowPadding)
    .frame(minHeight: 40)
    .accessibilityElement(children: .combine)
  }
}

extension URL: @retroactive Identifiable {
  public var id: String { absoluteString }
}

/// The scan's 3D model on its own, on a light warm grey: drag to turn it, pinch to zoom, two
/// fingers to move it. There is no AR (camera) mode; Quick Look always offered one.
struct ModelViewer: View {
  let url: URL
  let title: String
  @State private var scene: SCNScene?
  @State private var camera: SCNNode?
  @State private var failed = false
  /// The full-screen view's size, which the model is framed for.
  @State private var size = CGSize.zero
  @Environment(\.dismiss) private var dismiss

  private let background = Color(uiColor: ModelStyle.backgroundColor)

  var body: some View {
    ZStack {
      background.ignoresSafeArea()
      if let scene, let camera {
        SceneView(
          scene: scene, pointOfView: camera,
          options: [.allowsCameraControl])
          .ignoresSafeArea()
          .accessibilityLabel("3D model of \(title)")
      } else if failed {
        Text("The 3D model could not be opened.").font(Typo.body).foregroundStyle(Palette.blocked)
      } else {
        ProgressView()
      }
    }
    .overlay(alignment: .top) {
      HStack {
        Button { dismiss() } label: {
          Image(systemName: "xmark").font(ChapterTheme.Font.bodyEmphasis)
            .frame(width: Control.minTouch, height: Control.minTouch)
        }
        .accessibilityLabel("Close")
        Spacer()
        Text(title).font(Typo.sans(15, weight: .semibold)).lineLimit(1)
        Spacer()
        Button { load() } label: {
          Image(systemName: "arrow.counterclockwise").font(ChapterTheme.Font.bodyEmphasis)
            .frame(width: Control.minTouch, height: Control.minTouch)
        }
        .accessibilityLabel("Reset view")
        ShareLink(item: url) {
          Image(systemName: "square.and.arrow.up").font(ChapterTheme.Font.bodyEmphasis)
            .frame(width: Control.minTouch, height: Control.minTouch)
        }
      }
      .foregroundStyle(Palette.ink)
      .padding(.horizontal, Space.s4)
      .background(background.opacity(0.9))
    }
    .background {
      GeometryReader { proxy in
        Color.clear
          .onAppear {
            size = proxy.size
            load()
          }
          .onChange(of: proxy.size) { _, new in size = new }
      }
      .ignoresSafeArea()
    }
  }

  /// Loads the model and styles it (`ModelStyle`): walls, floor, doors, windows and furniture
  /// rebuilt as a clean model, soft light, and a camera that fits the whole model to the view's
  /// shape. Called again by Reset view.
  private func load() {
    guard let loaded = try? SCNScene(url: url, options: nil) else {
      failed = true
      return
    }
    let aspect =
      size.width > 0 && size.height > 0
      ? Float(size.width / size.height) : ModelStyle.defaultAspect
    camera = ModelStyle.apply(to: loaded, background: ModelStyle.backgroundColor, aspect: aspect)
    scene = loaded
  }
}
