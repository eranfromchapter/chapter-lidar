#if canImport(SwiftUI) && os(iOS)
  import CaptureContract
  import ChapterUI
  import SwiftUI

  /// The colour Floorplan of the Check screen drawn live from the solver's capture model: each
  /// room's outline filled (nude) and stroked, the walls as ink lines of their thickness, doors
  /// (ready), windows (limited) and openings (muted) as bars across their wall, and the room
  /// labels. Plan X runs right and plan up is −Z, as the plans draw it. Fitted to the canvas
  /// with a margin; nothing of PlanExport is used, so the screen is a preview, not the file.
  public struct SketchPlanCanvas: View {
    let model: CaptureModel

    public init(model: CaptureModel) {
      self.model = model
    }

    public var body: some View {
      Canvas { context, size in
        guard let frame = Self.planFrame(model, in: size) else { return }
        for room in model.rooms where room.polygon.count >= 3 {
          var path = Path()
          path.move(to: frame.point(room.polygon[0]))
          for point in room.polygon.dropFirst() { path.addLine(to: frame.point(point)) }
          path.closeSubpath()
          context.fill(path, with: .color(ChapterTheme.Color.nude))
          context.stroke(path, with: .color(ChapterTheme.Color.line), lineWidth: 1)
        }
        for wall in model.walls {
          var path = Path()
          path.move(to: frame.point(wall.start))
          path.addLine(to: frame.point(wall.end))
          let width = max(2, wall.thicknessM * frame.scale)
          let colour: Color =
            switch wall.confidence {
            case .low?: ChapterTheme.Color.limitedText
            default: ChapterTheme.Color.ink
            }
          context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: width, lineCap: .butt))
        }
        let openings: [(CaptureModel.WallOpening, Color)] =
          model.doors.map { ($0, ChapterTheme.Color.ready) }
          + model.windows.map { ($0, ChapterTheme.Color.limited) }
          + model.openings.map { ($0, ChapterTheme.Color.muted) }
        for (opening, colour) in openings {
          guard let wall = model.walls.first(where: { $0.id == opening.wallId }) else { continue }
          let length = Self.length(wall)
          guard length > 0 else { continue }
          let ux = (wall.end.x - wall.start.x) / length
          let uz = (wall.end.z - wall.start.z) / length
          let half = opening.widthM / 2
          let from = Vec3(
            x: wall.start.x + ux * (opening.offsetM - half), y: 0,
            z: wall.start.z + uz * (opening.offsetM - half))
          let to = Vec3(
            x: wall.start.x + ux * (opening.offsetM + half), y: 0,
            z: wall.start.z + uz * (opening.offsetM + half))
          var path = Path()
          path.move(to: frame.point(from))
          path.addLine(to: frame.point(to))
          let width = max(3, wall.thicknessM * frame.scale + 2)
          context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: width, lineCap: .butt))
        }
        for room in model.rooms where room.polygon.count >= 3 {
          let centre = Self.centroid(room.polygon)
          let text = Text(room.label)
            .font(ChapterTheme.Font.footnote)
            .foregroundStyle(ChapterTheme.Color.ink)
          context.draw(text, at: frame.point(centre), anchor: .center)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(accessibilityText))
      .accessibilityAddTraits(.isImage)
      .accessibilityIdentifier("sketch.plan")
    }

    private var accessibilityText: String {
      let rooms = model.rooms.map(\.label).joined(separator: ", ")
      return "Floorplan preview: \(model.rooms.count) rooms (\(rooms)), \(model.walls.count) walls, "
        + "\(model.doors.count) doors, \(model.windows.count) windows"
    }

    /// Plan metres to canvas points: scale to fit with a 12 pt margin, centred; −Z up.
    struct Frame {
      let scale: Double
      let offset: CGPoint
      let maxZ: Double

      func point(_ v: Vec3) -> CGPoint {
        CGPoint(x: offset.x + v.x * scale, y: offset.y + (maxZ - v.z) * scale)
      }
    }

    static func planFrame(_ model: CaptureModel, in size: CGSize) -> Frame? {
      var points = model.rooms.flatMap(\.polygon)
      points += model.walls.flatMap { [$0.start, $0.end] }
      guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
        let minZ = points.map(\.z).min(), let maxZ = points.map(\.z).max()
      else { return nil }
      // Explicit Doubles: `size` is CGFloat and Xcode 26.3 finds `/` ambiguous when mixed.
      let margin = 12.0
      let width: Double = max(maxX - minX, 0.1)
      let depth: Double = max(maxZ - minZ, 0.1)
      let availableWidth = Double(size.width) - 2 * margin
      let availableHeight = Double(size.height) - 2 * margin
      let scale: Double = min(availableWidth / width, availableHeight / depth)
      guard scale.isFinite, scale > 0 else { return nil }
      let offset = CGPoint(
        x: (Double(size.width) - width * scale) / 2 - minX * scale,
        y: (Double(size.height) - depth * scale) / 2)
      return Frame(scale: scale, offset: offset, maxZ: maxZ)
    }

    static func length(_ wall: CaptureModel.Wall) -> Double {
      let dx = wall.end.x - wall.start.x
      let dz = wall.end.z - wall.start.z
      return (dx * dx + dz * dz).squareRoot()
    }

    static func centroid(_ polygon: [Vec3]) -> Vec3 {
      let count = Double(polygon.count)
      return Vec3(
        x: polygon.map(\.x).reduce(0, +) / count, y: 0, z: polygon.map(\.z).reduce(0, +) / count)
    }
  }
#endif
