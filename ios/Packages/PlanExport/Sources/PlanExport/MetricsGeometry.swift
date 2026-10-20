import Foundation

/// A point in plan coordinates, metres: x is the model's x and y is the model's -z, so the plan
/// reads the right way round when seen from above with y pointing up the sheet.
public struct PlanPoint: Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  init(_ point: Point2) {
    self.init(x: point.x, y: point.y)
  }
}

/// A rectangle in plan coordinates whose sides run along a measurement frame: the frame's first
/// axis points `angleRadians` counter-clockwise from plan +x, its second axis 90 degrees further.
public struct MeasuredRectangle: Hashable, Sendable {
  /// Side along the frame's first axis, metres.
  public var alongM: Double
  /// Side along the frame's second axis, metres.
  public var acrossM: Double
  /// Centre in plan coordinates.
  public var center: PlanPoint
  /// Direction of the frame's first axis, radians counter-clockwise from plan +x, in
  /// (-pi/4, pi/4].
  public var angleRadians: Double
  /// Corners in plan coordinates, counter-clockwise, starting at the corner that is lowest along
  /// both frame axes.
  public var corners: [PlanPoint]

  /// The longer side, metres.
  public var longM: Double { max(alongM, acrossM) }
  /// The shorter side, metres.
  public var shortM: Double { min(alongM, acrossM) }
  public var areaM2: Double { alongM * acrossM }
}

/// Plane geometry of the measurement engine (`RoomMetrics`, `PlanTotals`): the dominant axis of
/// outlines, rectangles in that frame, the largest inscribed rectangle and raster fills.
enum MetricsGeometry {
  /// Outlines with at most this many corners get the exact inscribed-rectangle search; larger
  /// ones a raster of `rasterCellM`.
  static let exactSearchVertexLimit = 64
  /// Raster cell of the inscribed-rectangle search for large outlines, metres.
  static let rasterCellM = 0.01
  /// Coordinates closer than this are the same coordinate, metres.
  static let epsilon = 1e-9

  /// Axes turned by `angle` radians counter-clockwise from the plan axes.
  struct Frame: Hashable, Sendable {
    let angle: Double
    let u: Point2
    let v: Point2

    init(angle: Double) {
      self.angle = angle
      u = Point2(x: cos(angle), y: sin(angle))
      v = Point2(x: -sin(angle), y: cos(angle))
    }

    /// Plan point to frame coordinates.
    func local(_ point: Point2) -> Point2 { Point2(x: point.dot(u), y: point.dot(v)) }

    /// Frame coordinates to plan point.
    func plan(_ point: Point2) -> Point2 { u * point.x + v * point.y }
  }

  /// An axis-aligned rectangle in frame coordinates.
  struct Box: Hashable, Sendable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var area: Double { width * height }
    var transposed: Box { Box(minX: minY, minY: minX, maxX: maxY, maxY: maxX) }

    func measured(in frame: Frame) -> MeasuredRectangle {
      let corners = [
        Point2(x: minX, y: minY), Point2(x: maxX, y: minY), Point2(x: maxX, y: maxY),
        Point2(x: minX, y: maxY),
      ].map { PlanPoint(frame.plan($0)) }
      return MeasuredRectangle(
        alongM: width, acrossM: height,
        center: PlanPoint(frame.plan(Point2(x: (minX + maxX) / 2, y: (minY + maxY) / 2))),
        angleRadians: frame.angle, corners: corners)
    }

    /// Whether `self` is the better inscribed rectangle: larger area; on equal area (within
    /// 1e-9 m²) the squarer one (longer short side), then the one further down and left.
    func isBetter(than other: Box) -> Bool {
      if abs(area - other.area) > 1e-9 { return area > other.area }
      let short = min(width, height)
      let otherShort = min(other.width, other.height)
      if abs(short - otherShort) > MetricsGeometry.epsilon { return short > otherShort }
      if abs(minX - other.minX) > MetricsGeometry.epsilon { return minX < other.minX }
      return minY < other.minY - MetricsGeometry.epsilon
    }
  }

  // MARK: Dominant axis

  /// Edges within this angle of the dominant axis (modulo 90 degrees) run along it, radians.
  static let axisToleranceRadians = 3.0 * .pi / 180

  /// Direction, radians in (-pi/4, pi/4], that the outlines' edges run along, with directions
  /// taken modulo 90 degrees so that edges at right angles to each other agree: of the edge
  /// directions, the one that the most outline length runs along to within
  /// `axisToleranceRadians`, refined to the length-weighted mean direction of those edges. A
  /// short slanted edge therefore does not turn the axis. Zero when there are no edges.
  static func dominantAngle(of polygons: [[Point2]]) -> Double {
    // Each edge as (direction modulo 90 degrees in (-pi/4, pi/4], length).
    var edges: [(angle: Double, length: Double)] = []
    for polygon in polygons {
      for index in polygon.indices {
        let edge = polygon[(index + 1) % polygon.count] - polygon[index]
        let length = edge.length
        guard length > epsilon else { continue }
        edges.append((axisAngle(atan2(edge.y, edge.x)), length))
      }
    }
    // Circular distance between two directions modulo 90 degrees.
    func apart(_ a: Double, _ b: Double) -> Double {
      let difference = abs(a - b).truncatingRemainder(dividingBy: .pi / 2)
      return min(difference, .pi / 2 - difference)
    }
    var best: (angle: Double, support: Double)?
    for candidate in edges {
      let support = edges.filter { apart($0.angle, candidate.angle) <= axisToleranceRadians }
        .reduce(0) { $0 + $1.length }
      if best.map({ support > $0.support + epsilon }) ?? true {
        best = (candidate.angle, support)
      }
    }
    guard let best else { return 0 }
    // Length-weighted mean of the supporting directions, each taken four times round.
    var sine = 0.0
    var cosine = 0.0
    for edge in edges where apart(edge.angle, best.angle) <= axisToleranceRadians {
      sine += edge.length * sin(4 * edge.angle)
      cosine += edge.length * cos(4 * edge.angle)
    }
    let angle = axisAngle(atan2(sine, cosine) / 4)
    return abs(angle) < epsilon ? 0 : angle
  }

  /// `angle` modulo 90 degrees, in (-pi/4, pi/4].
  static func axisAngle(_ angle: Double) -> Double {
    var result = angle.truncatingRemainder(dividingBy: .pi / 2)
    if result > .pi / 4 { result -= .pi / 2 }
    if result <= -.pi / 4 { result += .pi / 2 }
    return result
  }

  /// Bounding box of `points` (frame coordinates); nil when there are none.
  static func bounds(of points: [Point2]) -> Box? {
    guard let first = points.first else { return nil }
    var box = Box(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
    for point in points.dropFirst() {
      box.minX = min(box.minX, point.x)
      box.minY = min(box.minY, point.y)
      box.maxX = max(box.maxX, point.x)
      box.maxY = max(box.maxY, point.y)
    }
    return box
  }

  // MARK: Largest inscribed rectangle

  /// Side positions per axis tried between the outermost corners, besides the corners
  /// themselves, when an edge runs off the frame axes.
  static let slantedSearchSteps = 96
  /// Rounds of the local search round the best of those, each four times finer.
  static let slantedSearchRounds = 8

  /// The largest axis-aligned rectangle inside `polygon` (frame coordinates); nil when the
  /// outline encloses no area.
  ///
  /// Up to `exactSearchVertexLimit` corners, a slab search: for a pair of x positions, the
  /// tallest rectangle spanning them is found exactly from the y ranges that the edges crossing
  /// that x range block; the same again with x and y swapped. When every edge runs along a frame
  /// axis, the sides of the largest rectangle lie on corner coordinates, so the pairs of corner
  /// coordinates give it exactly. A slanted edge (a chamfer, a bay, a wedge) can hold a side
  /// anywhere, so then `slantedSearchSteps` evenly spaced positions are tried as well and the
  /// best pair is refined locally (`slantedSearchRounds`); every candidate lies inside the
  /// outline (to rounding), so the result is never larger than the true rectangle and is
  /// short of it by at most a few micrometres per side. More corners: a raster of
  /// `rasterCellM` cells, a cell counting as inside when its centre is. Equal areas are
  /// decided by `Box.isBetter(than:)`.
  static func largestInscribedRectangle(_ polygon: [Point2]) -> Box? {
    guard polygon.count >= 3 else { return nil }
    if polygon.count <= exactSearchVertexLimit {
      let byX = sweepInscribed(polygon)
      let byY = sweepInscribed(polygon.map { Point2(x: $0.y, y: $0.x) })?.transposed
      return better(byX, byY)
    }
    return rasterInscribed(polygon, cell: rasterCellM)
  }

  static func better(_ a: Box?, _ b: Box?) -> Box? {
    guard let a else { return b }
    guard let b else { return a }
    return b.isBetter(than: a) ? b : a
  }

  /// Whether the edge `a`-`b` runs along a frame axis (to rounding).
  static func isAlongAxis(_ a: Point2, _ b: Point2) -> Bool {
    let dx = abs(b.x - a.x)
    let dy = abs(b.y - a.y)
    return min(dx, dy) <= 1e-9 * max(dx, dy, 1)
  }

  /// The largest rectangle with its left and right sides at chosen x positions; see
  /// `largestInscribedRectangle`.
  static func sweepInscribed(_ polygon: [Point2]) -> Box? {
    let edges = polygon.indices.map { (polygon[$0], polygon[($0 + 1) % polygon.count]) }
    let corners = distinctSorted(polygon.map(\.x))
    guard let low = corners.first, let high = corners.last, high - low > epsilon,
      let extent = bounds(of: polygon)
    else { return nil }
    var best: Box?
    // A slab can hold no more than its width times the outline's height.
    func consider(_ left: Double, _ right: Double) {
      guard right - left > epsilon else { return }
      if let current = best, (right - left) * extent.height < current.area - 1e-9 { return }
      best = better(best, slabInscribed(polygon, edges: edges, left: left, right: right))
    }
    for i in corners.indices {
      for j in (i + 1)..<corners.count { consider(corners[i], corners[j]) }
    }
    guard edges.contains(where: { !isAlongAxis($0.0, $0.1) }) else { return best }

    // Slanted edges: evenly spaced sides too, then a local search round the best pair.
    var step = (high - low) / Double(slantedSearchSteps)
    let xs = distinctSorted(
      corners + (1..<slantedSearchSteps).map { low + step * Double($0) })
    for i in xs.indices {
      for j in (i + 1)..<xs.count { consider(xs[i], xs[j]) }
    }
    for _ in 0..<slantedSearchRounds {
      guard let current = best else { break }
      let offsets = (-4...4).map { step * Double($0) / 4 }
      let lefts = offsets.map { min(high, max(low, current.minX + $0)) }
      let rights = offsets.map { min(high, max(low, current.maxX + $0)) }
      for left in lefts {
        for right in rights { consider(left, right) }
      }
      step /= 4
    }
    return best
  }

  /// The best rectangle spanning `left`...`right` (frame x): the tallest gap between the y
  /// ranges that the edges crossing the open x range block, whose middle lies inside; nil when
  /// there is none.
  static func slabInscribed(
    _ polygon: [Point2], edges: [(Point2, Point2)], left: Double, right: Double
  ) -> Box? {
    // Edges inside the open x range block the y values they pass through.
    var blocked: [(Double, Double)] = []
    for (a, b) in edges {
      if let range = yRange(of: a, b, between: left + epsilon, and: right - epsilon) {
        blocked.append(range)
      }
    }
    blocked.sort { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
    // Free gaps between the merged blocked ranges.
    var best: Box?
    var top = -Double.infinity
    for range in blocked {
      if top.isFinite, range.0 > top + epsilon {
        let candidate = Box(minX: left, minY: top, maxX: right, maxY: range.0)
        let middle = Point2(x: (left + right) / 2, y: (top + range.0) / 2)
        if best.map({ candidate.isBetter(than: $0) }) ?? true,
          PlanGeometry.contains(polygon, middle)
        {
          best = candidate
        }
      }
      top = max(top, range.1)
    }
    return best
  }

  /// The y values that the segment `a`-`b` takes for x in [`low`, `high`]; nil when it has no
  /// part there.
  static func yRange(of a: Point2, _ b: Point2, between low: Double, and high: Double)
    -> (Double, Double)?
  {
    guard low <= high else { return nil }
    let dx = b.x - a.x
    if abs(dx) < 1e-12 {
      guard a.x >= low, a.x <= high else { return nil }
      return (min(a.y, b.y), max(a.y, b.y))
    }
    let t0 = (low - a.x) / dx
    let t1 = (high - a.x) / dx
    let from = max(0, min(t0, t1))
    let to = min(1, max(t0, t1))
    guard from <= to else { return nil }
    let y0 = a.y + (b.y - a.y) * from
    let y1 = a.y + (b.y - a.y) * to
    return (min(y0, y1), max(y0, y1))
  }

  /// Sorted values with those within `epsilon` of the previous kept value dropped.
  static func distinctSorted(_ values: [Double]) -> [Double] {
    var result: [Double] = []
    for value in values.sorted() where result.last.map({ value - $0 > epsilon }) ?? true {
      result.append(value)
    }
    return result
  }

  /// Largest rectangle of inside cells of a raster over `polygon`; see
  /// `largestInscribedRectangle`.
  static func rasterInscribed(_ polygon: [Point2], cell: Double) -> Box? {
    guard let box = bounds(of: polygon), box.width > 0, box.height > 0 else { return nil }
    let columns = Int((box.width / cell).rounded(.up))
    let rows = Int((box.height / cell).rounded(.up))
    var heights = [Int](repeating: 0, count: columns)
    var inside = [Bool](repeating: false, count: columns)
    var best: Box?
    for row in 0..<rows {
      for index in inside.indices { inside[index] = false }
      let y = box.minY + (Double(row) + 0.5) * cell
      for span in rowSpans(polygon, y: y, originX: box.minX, cell: cell, columns: columns) {
        for column in span { inside[column] = true }
      }
      for column in 0..<columns { heights[column] = inside[column] ? heights[column] + 1 : 0 }
      // Largest rectangle under the histogram of `heights`, with a stack of rising bars.
      var stack: [Int] = []
      for column in 0...columns {
        let height = column < columns ? heights[column] : 0
        while let last = stack.last, heights[last] >= height {
          stack.removeLast()
          let barHeight = heights[last]
          guard barHeight > 0 else { continue }
          let first = (stack.last ?? -1) + 1
          let candidate = Box(
            minX: box.minX + Double(first) * cell,
            minY: box.minY + Double(row - barHeight + 1) * cell,
            maxX: box.minX + Double(column) * cell, maxY: box.minY + Double(row + 1) * cell)
          if best.map({ candidate.isBetter(than: $0) }) ?? true { best = candidate }
        }
        if column < columns { stack.append(column) }
      }
    }
    return best
  }

  // MARK: Raster fill

  /// Columns of the row at `y` whose cell centres lie inside `polygon` (even-odd rule), as
  /// half-open column ranges clamped to `0..<columns`. Column `i` has its centre at
  /// `originX + (i + 0.5) * cell`. An edge is crossed the same way whichever room lists it, so
  /// two outlines that share an edge leave no gap and no overlap.
  static func rowSpans(
    _ polygon: [Point2], y: Double, originX: Double, cell: Double, columns: Int
  ) -> [Range<Int>] {
    var crossings: [Double] = []
    for index in polygon.indices {
      var a = polygon[index]
      var b = polygon[(index + 1) % polygon.count]
      guard (a.y > y) != (b.y > y) else { continue }
      if (b.x, b.y) < (a.x, a.y) { swap(&a, &b) }
      crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
    }
    crossings.sort()
    var spans: [Range<Int>] = []
    var index = 0
    while index + 1 < crossings.count {
      let start = ((crossings[index] - originX) / cell - 0.5).rounded(.up)
      let end = ((crossings[index + 1] - originX) / cell - 0.5).rounded(.up)
      let lower = Int(max(0, min(Double(columns), start)))
      let upper = Int(max(0, min(Double(columns), end)))
      if lower < upper { spans.append(lower..<upper) }
      index += 2
    }
    return spans
  }
}
