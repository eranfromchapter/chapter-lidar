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
/// (`<visit>/originals/Original Exports/<areaKey>/<captureId>/`).
struct ScanItem: Identifiable, Hashable {
  var folder: URL
  var title: String
  var date: Date
  var id: String { folder.path }
}

/// Every scan on the phone, newest first. Reads the visit folders; changes nothing.
enum ScanLibrary {
  static let roomPlanFile = "roomplan.json"

  static func items(visitsRoot: URL) -> [ScanItem] {
    let files = FileManager.default
    guard let visits = try? files.contentsOfDirectory(at: visitsRoot, includingPropertiesForKeys: nil)
    else { return [] }
    var items: [ScanItem] = []
    for visit in visits {
      let exports = visit.appendingPathComponent("originals/Original Exports", isDirectory: true)
      for area in (try? files.contentsOfDirectory(at: exports, includingPropertiesForKeys: nil)) ?? [] {
        for capture in (try? files.contentsOfDirectory(at: area, includingPropertiesForKeys: nil)) ?? [] {
          if let item = item(folder: capture, title: title(areaKey: area.lastPathComponent)) {
            items.append(item)
          }
        }
      }
    }
    return items.sorted { $0.date > $1.date }
  }

  static func item(folder: URL, title: String) -> ScanItem? {
    let file = folder.appendingPathComponent(roomPlanFile)
    guard
      let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
      let date = values.contentModificationDate
    else { return nil }
    return ScanItem(folder: folder, title: title, date: date)
  }

  /// "floor-1" → "Floor 1".
  static func title(areaKey: String) -> String {
    let words = areaKey.split(whereSeparator: { $0 == "-" || $0 == "_" })
    return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
  }
}

/// Loads one scan for viewing: the floor plan image and the measurements from our own mapping,
/// and (on request) a USDZ model from Apple's RoomPlan export for the 3D view.
@MainActor @Observable
final class ScanViewerModel {
  let item: ScanItem
  private(set) var plan: UIImage?
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
        let png = try PNGWriter.write(model: model, displayUnits: .imperial).data
        return (png, ScanMeasurements(model: model), model.walls.count, model.rooms.count)
      }.value
      plan = UIImage(data: result.0)
      measurements = result.1
      counts = "\(result.3) \(result.3 == 1 ? "room" : "rooms") \u{00B7} \(result.2) walls"
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

/// One scan: the floor plan (pinch to zoom), the measurements and a 3D view of the model.
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

      ZStack {
        Palette.surface
        if let plan = model.plan {
          ZoomableImage(image: plan)
        } else if model.isLoading {
          ProgressView("Drawing the floor plan…")
        } else {
          Text(model.errorMessage ?? "No floor plan").font(Typo.caption)
            .foregroundStyle(Palette.blocked).padding()
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: Radius.card))
      .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Palette.line, lineWidth: 1))
      .overlay(alignment: .bottomTrailing) {
        if model.plan != nil {
          Text("Pinch to zoom").font(Typo.caption).foregroundStyle(Palette.muted)
            .padding(Space.s2)
        }
      }

      if let scan = model.measurements { measurements(scan) }

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

  private func measurements(_ scan: ScanMeasurements) -> some View {
    VStack(spacing: 0) {
      row("Long distance A", scan.distanceAMm.map(LengthFormatter.both) ?? "\u{2014}")
      row("Long distance B", scan.distanceBMm.map(LengthFormatter.both) ?? "\u{2014}")
      row(
        "Ceiling height",
        {
          let heights = scan.ceilingHeights.map(\.heightMm)
          guard let low = heights.min(), let high = heights.max() else { return "\u{2014}" }
          return low == high
            ? LengthFormatter.both(low) : LengthFormatter.millimetreRange(low, high)
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

/// The scan's 3D model on its own, on a bright background: drag to turn it, pinch to zoom, two
/// fingers to move it. There is no AR (camera) mode; Quick Look always offered one.
struct ModelViewer: View {
  let url: URL
  let title: String
  @State private var scene: SCNScene?
  @State private var camera: SCNNode?
  @State private var failed = false
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ZStack {
      Palette.surface.ignoresSafeArea()
      if let scene, let camera {
        SceneView(
          scene: scene, pointOfView: camera,
          options: [.allowsCameraControl, .autoenablesDefaultLighting])
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
      .background(Palette.surface.opacity(0.9))
    }
    .task { load() }
  }

  /// Loads the model with a bright background and soft light, and points a camera at it from
  /// above at an angle so the whole model is in view. Called again by Reset view.
  private func load() {
    guard let loaded = try? SCNScene(url: url, options: nil) else {
      failed = true
      return
    }
    loaded.background.contents = UIColor(Palette.surface)
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 600
    loaded.rootNode.addChildNode(ambient)

    let (low, high) = loaded.rootNode.boundingBox
    let center = SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2)
    let size = max(high.x - low.x, high.y - low.y, high.z - low.z, 0.5)
    let node = SCNNode()
    node.camera = SCNCamera()
    node.camera?.fieldOfView = 45
    node.camera?.zNear = 0.01
    node.camera?.zFar = Double(size) * 20
    node.position = SCNVector3(center.x + size * 0.9, center.y + size * 1.1, center.z + size * 0.9)
    node.look(at: center)
    loaded.rootNode.addChildNode(node)
    scene = loaded
    camera = node
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

/// A UIScrollView image view: pinch to zoom, pan, double-tap to zoom in or back out.
private struct ZoomableImage: UIViewRepresentable {
  let image: UIImage

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> UIScrollView {
    let scroll = UIScrollView()
    scroll.delegate = context.coordinator
    scroll.minimumZoomScale = 1
    scroll.maximumZoomScale = 8
    scroll.showsHorizontalScrollIndicator = false
    scroll.showsVerticalScrollIndicator = false
    let imageView = UIImageView(image: image)
    imageView.contentMode = .scaleAspectFit
    imageView.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(imageView)
    NSLayoutConstraint.activate([
      imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
      imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
      imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
    ])
    context.coordinator.imageView = imageView
    let doubleTap = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
    doubleTap.numberOfTapsRequired = 2
    scroll.addGestureRecognizer(doubleTap)
    return scroll
  }

  func updateUIView(_ scroll: UIScrollView, context: Context) {
    context.coordinator.imageView?.image = image
  }

  final class Coordinator: NSObject, UIScrollViewDelegate {
    weak var imageView: UIImageView?

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc func doubleTapped(_ gesture: UITapGestureRecognizer) {
      guard let scroll = gesture.view as? UIScrollView else { return }
      if scroll.zoomScale > 1 {
        scroll.setZoomScale(1, animated: true)
      } else {
        let point = gesture.location(in: imageView)
        let size = CGSize(width: scroll.bounds.width / 3, height: scroll.bounds.height / 3)
        scroll.zoom(
          to: CGRect(
            origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size),
          animated: true)
      }
    }
  }
}
