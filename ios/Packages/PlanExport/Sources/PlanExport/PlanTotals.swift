import CaptureContract
import Foundation

/// Totals over every room of a capture, in metres, square metres and cubic metres.
///
/// Definitions:
/// - Bedrooms, bathrooms: rooms whose type is bedroom, bathroom.
/// - Livable area: the sum of the rooms' floor areas.
/// - Exterior area (estimate): the area inside the outline of all rooms together, pushed out by
///   the assumed exterior wall thickness (`MeasurementSettings.exteriorWallThicknessM`), each
///   wall along its own normal, with mitred (square) corners. RoomPlan does not measure wall
///   thickness, so this is always an estimate. Gaps between rooms narrower than twice that
///   thickness (interior walls) count as inside. Computed as the livable area plus the band
///   that the push adds (`exteriorBandArea`).
/// - Wall area: the sum of the rooms' wall areas excluding openings, so a wall between two
///   rooms counts once per side.
/// - Window area: width x height summed over every window of the capture, each once.
/// - Volume: the sum of the rooms' volumes; approximate when any room's is.
/// - Perimeter in rooms: the sum of the rooms' perimeters.
///
/// Every total is summed from unrounded room values and rounded only when printed, so a printed
/// total can differ in its last digit from the sum of the printed room values.
public struct PlanTotals: Hashable, Sendable {
  public var roomCount: Int
  public var bedrooms: Int
  public var bathrooms: Int
  public var livableAreaM2: Double
  /// Estimate; see the type.
  public var exteriorAreaEstimateM2: Double
  /// Exterior wall thickness the estimate assumes, metres.
  public var exteriorWallThicknessM: Double
  public var wallAreaM2: Double
  public var windowAreaM2: Double
  public var volumeM3: Double
  public var volumeIsApproximate: Bool
  public var perimeterM: Double

  /// Totals of `model`'s rooms.
  public init(_ model: CaptureModel, settings: MeasurementSettings = MeasurementSettings()) throws {
    let geometry = try PlanGeometry(model: model)
    self.init(
      rooms: RoomMetrics.measure(model, geometry: geometry, settings: settings),
      geometry: geometry, settings: settings)
  }

  init(rooms: [RoomMetrics], geometry: PlanGeometry, settings: MeasurementSettings) {
    let windows = geometry.openings.filter { $0.kind == .window }
    let polygons = geometry.rooms.map(\.polygon)
    self.init(
      rooms: rooms, windowAreaM2: windows.reduce(0) { $0 + $1.widthM * $1.heightM },
      exteriorBandM2: PlanTotals.exteriorBandArea(
        polygons, thicknessM: settings.exteriorWallThicknessM),
      exteriorWallThicknessM: settings.exteriorWallThicknessM)
  }

  init(
    rooms: [RoomMetrics], windowAreaM2: Double, exteriorBandM2: Double,
    exteriorWallThicknessM: Double
  ) {
    roomCount = rooms.count
    bedrooms = rooms.filter { $0.type == .bedroom }.count
    bathrooms = rooms.filter { $0.type == .bathroom }.count
    livableAreaM2 = rooms.reduce(0) { $0 + $1.floorAreaM2 }
    exteriorAreaEstimateM2 = livableAreaM2 + exteriorBandM2
    self.exteriorWallThicknessM = exteriorWallThicknessM
    wallAreaM2 = rooms.reduce(0) { $0 + $1.wallAreaExcludingOpeningsM2 }
    self.windowAreaM2 = windowAreaM2
    volumeM3 = rooms.reduce(0) { $0 + $1.volumeM3 }
    volumeIsApproximate = rooms.contains { $0.ceiling.isApproximate }
    perimeterM = rooms.reduce(0) { $0 + $1.perimeterM }
  }

  // MARK: Exterior band

  /// Tallest strip the exterior band is summed over, metres.
  static let exteriorStripM = 0.01

  /// A mitre longer than this many thicknesses (a corner sharper than about 29 degrees) is
  /// cut square across (bevelled), as a wall corner would be.
  static let exteriorMitreLimit = 4.0

  /// Area that pushing the outline of all `polygons` together out by `thicknessM` adds, square
  /// metres: every room outline is offset by `thicknessM`, each edge along its own outward
  /// normal with mitred (square) corners (`offsetPieces`), and the band is what the union of
  /// those offsets adds to the union of the rooms. So a slanted wall is pushed out by the
  /// thickness, not 1.41 thicknesses as a square grow along the plan's axes would at 45
  /// degrees. Summed over horizontal strips between the corners' heights, at most
  /// `exteriorStripM` tall, each the covered length across its middle (exact across, with no
  /// raster) times its height: exact when every edge runs along the plan's axes, and within a
  /// fraction of a square millimetre per corner otherwise.
  static func exteriorBandArea(_ polygons: [[Point2]], thicknessM: Double) -> Double {
    guard thicknessM > 0 else { return 0 }
    let rooms = polygons.filter { $0.count >= 3 }
    let grown = rooms + rooms.flatMap { offsetPieces($0, by: thicknessM) }
    let heights = MetricsGeometry.distinctSorted(grown.flatMap { $0.map(\.y) })
    var band = 0.0
    for (low, high) in zip(heights, heights.dropFirst()) {
      let steps = max(1, Int(((high - low) / exteriorStripM).rounded(.up)))
      let step = (high - low) / Double(steps)
      for index in 0..<steps {
        let y = low + (Double(index) + 0.5) * step
        band += (coveredLength(grown, at: y) - coveredLength(rooms, at: y)) * step
      }
    }
    return max(0, band)
  }

  /// Length of the horizontal line at height `y` that lies inside at least one of `polygons`
  /// (each taken by the even-odd rule).
  static func coveredLength(_ polygons: [[Point2]], at y: Double) -> Double {
    var spans: [(Double, Double)] = []
    for polygon in polygons {
      var crossings: [Double] = []
      for index in polygon.indices {
        let a = polygon[index]
        let b = polygon[(index + 1) % polygon.count]
        guard (a.y > y) != (b.y > y) else { continue }
        crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
      }
      crossings.sort()
      var index = 0
      while index + 1 < crossings.count {
        spans.append((crossings[index], crossings[index + 1]))
        index += 2
      }
    }
    spans.sort { $0.0 < $1.0 }
    var length = 0.0
    var current: (Double, Double)?
    for span in spans {
      if let open = current, span.0 <= open.1 {
        current = (open.0, max(open.1, span.1))
      } else {
        if let open = current { length += open.1 - open.0 }
        current = span
      }
    }
    if let open = current { length += open.1 - open.0 }
    return length
  }

  /// The pieces that, with `polygon`, make up its outward offset by `t` with mitred corners:
  /// for each edge the strip it sweeps when pushed out along its outward normal, and for each
  /// convex corner the mitre between the strips of its two edges (bevelled past
  /// `exteriorMitreLimit`). At a reflex corner the two strips overlap, which is the offset
  /// there.
  static func offsetPieces(_ polygon: [Point2], by t: Double) -> [[Point2]] {
    // Without repeated corners, which have no direction.
    let tiny = MetricsGeometry.epsilon
    var points: [Point2] = []
    for p in polygon where points.last.map({ $0.distance(to: p) > tiny }) ?? true {
      points.append(p)
    }
    if points.count > 1, points[0].distance(to: points[points.count - 1]) <= tiny {
      points.removeLast()
    }
    guard points.count >= 3 else { return [] }
    let area = Geo.signedArea(points)
    guard abs(area) > tiny else { return [] }
    // Counter-clockwise outlines have the outside on the right of each edge.
    let sign = area > 0 ? 1.0 : -1.0
    let count = points.count
    let directions = (0..<count).map { (points[($0 + 1) % count] - points[$0]).unit }
    let normals = directions.map { Point2(x: $0.y * sign, y: -$0.x * sign) }
    var pieces: [[Point2]] = []
    for index in 0..<count {
      let a = points[index]
      let b = points[(index + 1) % count]
      let n = normals[index]
      pieces.append([a, b, b + n * t, a + n * t])
    }
    for index in 0..<count {
      let previous = (index + count - 1) % count
      // Convex: the outline turns towards its inside.
      guard directions[previous].cross(directions[index]) * sign > 1e-12 else { continue }
      let v = points[index]
      let n1 = normals[previous]
      let n2 = normals[index]
      let cosine = n1.dot(n2)
      // The mitre point lies t / cos(half the turn) from the corner.
      let mitre = (2 / (1 + cosine)).squareRoot()
      if mitre <= exteriorMitreLimit {
        pieces.append([v, v + n1 * t, v + (n1 + n2) * (t / (1 + cosine)), v + n2 * t])
      } else {
        pieces.append([v, v + n1 * t, v + n2 * t])
      }
    }
    return pieces
  }
}

/// Room measurements and totals of one capture, with the settings they assume.
public struct PlanMetrics: Hashable, Sendable {
  public var settings: MeasurementSettings
  public var rooms: [RoomMetrics]
  public var totals: PlanTotals

  public init(_ model: CaptureModel, settings: MeasurementSettings = MeasurementSettings()) throws {
    let geometry = try PlanGeometry(model: model)
    self.settings = settings
    rooms = RoomMetrics.measure(model, geometry: geometry, settings: settings)
    totals = PlanTotals(rooms: rooms, geometry: geometry, settings: settings)
  }
}
