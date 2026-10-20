import AppCore
import CaptureContract
import CaptureModelMapping
import CaptureUI
import FieldRules
import Foundation
import Observation
import PlanExport
import RoomPlan
import SceneKit
import SwiftUI
import UIKit

private typealias Palette = ChapterTokens.Palette
private typealias Space = ChapterTokens.Space
private typealias Typo = ChapterTokens.Typography
private typealias Control = ChapterTokens.Control
private typealias Radius = ChapterTokens.Radius

/// One scanned floor or area on this phone: the folder that holds its `roomplan.json`
/// (`<visit>/originals/Original Exports/<areaKey>/<captureId>/`), with the visit's address and
/// the capture's display units when they are known.
struct ScanItem: Identifiable, Hashable {
  var folder: URL
  var title: String
  var date: Date
  var address: String? = nil
  var displayUnits: DisplayUnitSystem? = nil
  var id: String { folder.path }
}

/// Every scan on the phone, newest first. Reads the visit folders; changes nothing.
enum ScanLibrary {
  static let roomPlanFile = "roomplan.json"

  static func items(visitsRoot: URL) -> [ScanItem] {
    var items: [ScanItem] = []
    for visit in children(of: visitsRoot) {
      let record = record(visit: visit)
      let exports = visit.appendingPathComponent("originals/Original Exports", isDirectory: true)
      for area in children(of: exports) {
        for capture in children(of: area) {
          let units = record?.captures.first {
            $0.captureId.rawValue == capture.lastPathComponent
          }?.units.display
          if let item = item(
            folder: capture, title: title(areaKey: area.lastPathComponent),
            address: record?.address.formatted, displayUnits: units)
          {
            items.append(item)
          }
        }
      }
    }
    return items.sorted { $0.date > $1.date }
  }

  static func item(
    folder: URL, title: String, address: String? = nil, displayUnits: DisplayUnitSystem? = nil
  ) -> ScanItem? {
    let file = folder.appendingPathComponent(roomPlanFile)
    guard
      let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
      let date = values.contentModificationDate
    else { return nil }
    return ScanItem(
      folder: folder, title: title, date: date, address: address, displayUnits: displayUnits)
  }

  /// The newest capture record written for a visit (by "Package ready", under
  /// `drafts/<draft>/Source Register/<visitId>/`); nil before there is one.
  static func record(visit: URL) -> CaptureRecord? {
    var newest: (date: Date, url: URL)?
    for draft in children(of: VisitWorkspace(root: visit).draftsRoot) {
      let register = draft.appendingPathComponent(PackageFolder.sourceRegister.name)
      for folder in children(of: register) {
        let file = folder.appendingPathComponent(PackageLayout.captureRecordFileName)
        guard
          let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        else { continue }
        if newest == nil || date > newest!.date { newest = (date, file) }
      }
    }
    guard let url = newest?.url, let data = try? Data(contentsOf: url) else { return nil }
    return try? CaptureContractJSON.makeDecoder().decode(CaptureRecord.self, from: data)
  }

  /// What a folder holds; empty when it cannot be read.
  private static func children(of folder: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
      ?? []
  }

  /// "floor-1" → "Floor 1".
  static func title(areaKey: String) -> String {
    let words = areaKey.split(whereSeparator: { $0 == "-" || $0 == "_" })
    return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
  }
}

/// Loads one scan for viewing: the Floorplan and the measurements from our own mapping, and
/// (on request) a USDZ model from Apple's RoomPlan export for the 3D view.
@MainActor @Observable
final class ScanViewerModel {
  let item: ScanItem
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
    let title = item.title
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        let data = try Data(contentsOf: file)
        let document = try RoomPlanDocument.decode(from: data)
        let model = try CaptureModelMapper.map(
          document,
          context: MappingContext(
            visitId: LowercaseUUID(), captureId: LowercaseUUID(), areaKey: "scan", label: title))
        return (model, ScanMeasurements(model: model), model.walls.count, model.rooms.count)
      }.value
      measurements = result.1
      counts = "\(result.3) \(result.3 == 1 ? "room" : "rooms") \u{00B7} \(result.2) walls"
      let floorplan = FloorplanModel(
        model: result.0, address: item.address, units: item.displayUnits ?? .imperial,
        exportName: item.folder.lastPathComponent)
      self.floorplan = floorplan
      isLoading = false
      await floorplan.write()
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

/// One scan: the Floorplan (pinch to zoom, units, download), the measurements and a 3D view of
/// the model.
struct ScanViewer: View {
  @State private var model: ScanViewerModel
  @Environment(\.dismiss) private var dismiss

  init(item: ScanItem) {
    _model = State(initialValue: ScanViewerModel(item: item))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(model.item.title).font(Typo.serif(30)).foregroundStyle(Palette.ink)
          Text(model.item.date.formatted(date: .abbreviated, time: .shortened)
            + (model.counts.map { " \u{00B7} \($0)" } ?? ""))
            .font(Typo.caption).foregroundStyle(Palette.muted)
        }
        Spacer()
        Button("Done") { dismiss() }
          .font(Typo.sans(15, weight: .semibold)).foregroundStyle(Palette.ink)
          .frame(minHeight: Control.minTouch)
      }

      if let floorplan = model.floorplan {
        FloorplanView(floorplan: floorplan)
      } else {
        ZStack {
          Palette.surface
          if model.isLoading {
            ProgressView("Drawing the floor plan…")
          } else {
            Text(model.errorMessage ?? "No floor plan").font(Typo.caption)
              .foregroundStyle(Palette.blocked).padding()
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))
      }

      if let scan = model.measurements {
        measurements(scan, units: model.floorplan?.units ?? .imperial)
      }

      Button {
        Task { await model.open3D() }
      } label: {
        HStack(spacing: Space.s2) {
          if model.isExporting { ProgressView().tint(Palette.surface) }
          Image(systemName: "cube")
          Text(model.isExporting ? "Making the 3D model…" : "View in 3D")
        }
        .font(Typo.headline).foregroundStyle(Palette.surface)
        .frame(maxWidth: .infinity, minHeight: Control.primaryHeight)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: Radius.card))
      }
      .buttonStyle(.plain)
      .disabled(model.isExporting)
      .accessibilityIdentifier("scan.view3D")
    }
    .padding(.horizontal, 20)
    .padding(.top, Space.s4)
    .padding(.bottom, Space.s4)
    .background(Palette.ground.ignoresSafeArea())
    .fullScreenCover(item: $model.modelURL) { url in
      ModelViewer(url: url, title: model.item.title)
    }
    .task { await model.load() }
  }

  /// The measurements in the units the Floorplan is shown in, written as the plan writes them.
  private func measurements(_ scan: ScanMeasurements, units: DisplayUnitSystem) -> some View {
    let formatter = UnitFormatter(system: units)
    let length = { (millimetres: Double) in formatter.dimension(millimetres / 1000) }
    return VStack(spacing: 0) {
      row("Long distance A", scan.distanceAMm.map(length) ?? "\u{2014}")
      row("Long distance B", scan.distanceBMm.map(length) ?? "\u{2014}")
      row(
        "Ceiling height",
        {
          let heights = scan.ceilingHeights.map(\.heightMm)
          guard let low = heights.min(), let high = heights.max() else { return "\u{2014}" }
          let lowText = length(low)
          let highText = length(high)
          return lowText == highText ? lowText : "\(lowText) \u{2013} \(highText)"
        }())
      row("Openings", scan.openingsSummary)
    }
    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))
  }

  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).font(Typo.sans(15, weight: .semibold))
      Spacer()
      Text(value).font(Typo.sans(15))
    }
    .foregroundStyle(Palette.ink)
    .padding(.horizontal, Space.s4).padding(.vertical, 10)
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
          Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
            .frame(width: Control.minTouch, height: Control.minTouch)
        }
        .accessibilityLabel("Close")
        Spacer()
        Text(title).font(Typo.sans(15, weight: .semibold)).lineLimit(1)
        Spacer()
        Button { load() } label: {
          Image(systemName: "arrow.counterclockwise").font(.system(size: 17, weight: .semibold))
            .frame(width: Control.minTouch, height: Control.minTouch)
        }
        .accessibilityLabel("Reset view")
        ShareLink(item: url) {
          Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold))
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

/// "My scans": every scan on this phone, newest first.
struct MyScansView: View {
  let visitsRoot: URL
  @State private var items: [ScanItem] = []
  @State private var open: ScanItem?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("My scans").font(Typo.serif(30)).foregroundStyle(Palette.ink)
        Spacer()
        Button("Done") { dismiss() }
          .font(Typo.sans(15, weight: .semibold)).foregroundStyle(Palette.ink)
          .frame(minHeight: Control.minTouch)
      }
      if items.isEmpty {
        Text("No scans on this phone yet.").font(Typo.sans(15)).foregroundStyle(Palette.muted)
        Spacer()
      } else {
        ScrollView {
          ScanList(items: items) { open = $0 }
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, Space.s4)
    .background(Palette.ground.ignoresSafeArea())
    .task { items = ScanLibrary.items(visitsRoot: visitsRoot) }
    .sheet(item: $open) { ScanViewer(item: $0) }
  }
}

/// Rows of scans; tapping one calls `onOpen`.
struct ScanList: View {
  let items: [ScanItem]
  let onOpen: (ScanItem) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        Button { onOpen(item) } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(item.title).font(Typo.sans(17, weight: .semibold))
              Text(item.date.formatted(date: .abbreviated, time: .shortened))
                .font(Typo.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
          }
          .foregroundStyle(Palette.ink)
          .padding(.horizontal, Space.s4).padding(.vertical, 14)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if index < items.count - 1 { Rectangle().fill(Palette.nude).frame(height: 1) }
      }
    }
    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
    .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))
  }
}
