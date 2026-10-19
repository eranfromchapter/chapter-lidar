import CaptureContract
import Foundation

/// Totals over every room of a capture, in metres, square metres and cubic metres.
///
/// Definitions:
/// - Bedrooms, bathrooms: rooms whose type is bedroom, bathroom.
/// - Livable area: the sum of the rooms' floor areas.
/// - Exterior area (estimate): the area inside the outline of all rooms together, pushed out by
///   the assumed exterior wall thickness (`MeasurementSettings.exteriorWallThicknessM`) with
///   square corners. RoomPlan does not measure wall thickness, so this is always an estimate.
///   Gaps between rooms narrower than twice that thickness (interior walls) count as inside.
///   Computed as the livable area plus the band that the push adds, measured on a raster of
///   about 1 cm in the frame of the plan's dominant axis.
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

  /// Target raster cell of the exterior estimate, metres.
  static let exteriorCellM = 0.01
  /// Most raster cells the exterior estimate uses; a larger plan gets coarser cells.
  static let exteriorMaximumCells = 16_000_000

  /// Area that pushing the outline of all `polygons` together out by `thicknessM` adds, square
  /// metres. On a raster in the frame of the polygons' dominant axis, with a whole number r of
  /// cells per thickness: the cells whose centres lie in some polygon are grown by r cells in
  /// each axis direction (a square grow, which gives the square corners of a wall); the result
  /// is the number of cells added times the cell area. Along an edge of the outline the grow
  /// adds exactly r cells per row, so the band does not depend on where the edge falls in a
  /// cell.
  static func exteriorBandArea(_ polygons: [[Point2]], thicknessM: Double) -> Double {
    guard thicknessM > 0, !polygons.isEmpty else { return 0 }
    let frame = MetricsGeometry.Frame(angle: MetricsGeometry.dominantAngle(of: polygons))
    let local = polygons.map { $0.map(frame.local) }
    guard let bounds = MetricsGeometry.bounds(of: local.flatMap { $0 }) else { return 0 }

    var r = max(1, Int((thicknessM / exteriorCellM).rounded()))
    var cell = thicknessM / Double(r)
    var columns = 0
    var rows = 0
    while true {
      cell = thicknessM / Double(r)
      columns = Int(((bounds.width + 2 * thicknessM) / cell).rounded(.up)) + 4
      rows = Int(((bounds.height + 2 * thicknessM) / cell).rounded(.up)) + 4
      let cells = Double(columns) * Double(rows)
      if cells <= Double(exteriorMaximumCells) || r == 1 { break }
      r = max(1, Int(Double(r) * (Double(exteriorMaximumCells) / cells).squareRoot()))
    }
    let originX = bounds.minX - thicknessM - 2 * cell
    let originY = bounds.minY - thicknessM - 2 * cell

    var grid = [UInt8](repeating: 0, count: columns * rows)
    for row in 0..<rows {
      let y = originY + (Double(row) + 0.5) * cell
      for polygon in local {
        for span in MetricsGeometry.rowSpans(
          polygon, y: y, originX: originX, cell: cell, columns: columns)
        {
          for column in span { grid[row * columns + column] = 1 }
        }
      }
    }
    let inside = grid.reduce(0) { $0 + Int($1) }
    // Grow along rows, then along columns.
    grid = grow(grid, count: columns, lines: rows, step: 1, lineStep: columns, by: r)
    grid = grow(grid, count: rows, lines: columns, step: columns, lineStep: 1, by: r)
    let grown = grid.reduce(0) { $0 + Int($1) }
    return Double(grown - inside) * cell * cell
  }

  /// Sets every cell within `by` cells of a set cell along each line. Line `l` holds the cells
  /// `l * lineStep + i * step` for `i` in `0..<count`.
  private static func grow(
    _ grid: [UInt8], count: Int, lines: Int, step: Int, lineStep: Int, by r: Int
  ) -> [UInt8] {
    var result = grid
    for line in 0..<lines {
      let base = line * lineStep
      // Nearest set cell before and after each cell.
      var last = -r - 1
      for i in 0..<count {
        if grid[base + i * step] == 1 { last = i }
        if i - last <= r { result[base + i * step] = 1 }
      }
      var next = count + r
      for i in stride(from: count - 1, through: 0, by: -1) {
        if grid[base + i * step] == 1 { next = i }
        if next - i <= r { result[base + i * step] = 1 }
      }
    }
    return result
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
