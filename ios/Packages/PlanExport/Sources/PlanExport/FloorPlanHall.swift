import Foundation

/// Floor that no room covers but that walls and an opening close in: a passage the scan left
/// out of the rooms (say between a living room and the bathroom it leads to), or a hole
/// between rooms. Without it the drawing shows outdoors there. Found on a grid of `cell`
/// metres: the rooms and walls, closed up by `reach` (gaps narrower than twice that are
/// filled, square corners stay square), less what was there; a filled region is kept when it
/// is at least `minimumArea` and touches a door or an opening, or is closed in all round.
/// Where a region meets unscanned ground (no wall, room or opening there) its edge is given
/// as straight runs at least `minimumEdge` long, for a thin line that closes the floor.
/// Plan metres.
struct HallFill {
  var cell = 0.025
  var reach = 0.5
  var minimumArea = 0.25
  var minimumEdge = 0.15

  /// Rectangles covering each region, with the room the region opens to (nil when none) and
  /// its edges against unscanned ground.
  func regions(
    rooms: [[Point2]], walls: [[Point2]], openings: [(a: Point2, b: Point2, normal: Point2,
      lo: Double, hi: Double)]
  ) -> [(rects: [[Point2]], room: Int?, edges: [(Point2, Point2)])] {
    let shapes = rooms + walls
    let points = shapes.flatMap { $0 }
    guard let first = points.first else { return [] }
    var low = first
    var high = first
    for p in points {
      low = Point2(x: min(low.x, p.x), y: min(low.y, p.y))
      high = Point2(x: max(high.x, p.x), y: max(high.y, p.y))
    }
    let pad = reach + 2 * cell
    low = low - Point2(x: pad, y: pad)
    high = high + Point2(x: pad, y: pad)
    let width = Int(((high.x - low.x) / cell).rounded(.up)) + 1
    let height = Int(((high.y - low.y) / cell).rounded(.up)) + 1
    guard width > 0, height > 0, width * height < 4_000_000 else { return [] }
    func center(_ i: Int, _ j: Int) -> Point2 {
      Point2(x: low.x + (Double(i) + 0.5) * cell, y: low.y + (Double(j) + 0.5) * cell)
    }

    // Rooms and walls, by scanlines through the cell centres (even-odd per shape).
    var solid = [Bool](repeating: false, count: width * height)
    for shape in shapes where shape.count >= 3 {
      for j in 0..<height {
        let y = low.y + (Double(j) + 0.5) * cell
        var crossings: [Double] = []
        for index in shape.indices {
          let a = shape[index]
          let b = shape[(index + 1) % shape.count]
          if (a.y > y) != (b.y > y) {
            crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
          }
        }
        crossings.sort()
        var k = 0
        while k + 1 < crossings.count {
          let i0 = max(0, Int(((crossings[k] - low.x) / cell - 0.5).rounded(.up)))
          let i1 = min(width - 1, Int(((crossings[k + 1] - low.x) / cell - 0.5).rounded(.down)))
          if i0 <= i1 { for i in i0...i1 { solid[j * width + i] = true } }
          k += 2
        }
      }
    }

    // Closing with a square: grow by `reach`, then shrink by it.
    let r = max(1, Int((reach / cell).rounded()))
    func filter(_ grid: [Bool], grow: Bool) -> [Bool] {
      var out = grid
      // Along rows, then along columns, with running counts.
      for pass in 0..<2 {
        let source = out
        let (outer, inner) = pass == 0 ? (height, width) : (width, height)
        for o in 0..<outer {
          var prefix = [Int](repeating: 0, count: inner + 1)
          for q in 0..<inner {
            let index = pass == 0 ? o * width + q : q * width + o
            prefix[q + 1] = prefix[q] + (source[index] ? 1 : 0)
          }
          for q in 0..<inner {
            let a = max(0, q - r)
            let b = min(inner - 1, q + r)
            let count = prefix[b + 1] - prefix[a]
            let index = pass == 0 ? o * width + q : q * width + o
            out[index] = grow ? count > 0 : count == 2 * r + 1
          }
        }
      }
      return out
    }
    let closed = filter(filter(solid, grow: true), grow: false)

    // Regions of the added floor.
    var region = [Int](repeating: -1, count: width * height)
    var results: [(rects: [[Point2]], room: Int?, edges: [(Point2, Point2)])] = []
    var next = 0
    for start in 0..<(width * height) where closed[start] && !solid[start] && region[start] < 0 {
      var stack = [start]
      region[start] = next
      var members: [Int] = []
      var open = false
      while let index = stack.popLast() {
        members.append(index)
        let i = index % width
        let j = index / width
        for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
          let ni = i + di
          let nj = j + dj
          guard ni >= 0, nj >= 0, ni < width, nj < height else {
            open = true
            continue
          }
          let neighbour = nj * width + ni
          if !closed[neighbour] { open = true }
          if closed[neighbour] && !solid[neighbour] && region[neighbour] < 0 {
            region[neighbour] = next
            stack.append(neighbour)
          }
        }
      }
      next += 1
      guard Double(members.count) * cell * cell >= minimumArea else { continue }
      // The door or opening it touches, and the room on the far side of it.
      var room: Int?
      var touches = false
      for opening in openings {
        let along = (opening.b - opening.a)
        let length = along.length
        guard length > 1e-6 else { continue }
        let d = along.unit
        let hit = members.contains { index in
          let p = center(index % width, index / width)
          let s = (p - opening.a).dot(d)
          let t = (p - opening.a).dot(opening.normal)
          return s > -cell && s < length + cell && t > opening.lo - 2 * cell
            && t < opening.hi + 2 * cell
        }
        guard hit else { continue }
        touches = true
        let middle = (opening.a + opening.b) * 0.5
        for side in [opening.hi + 0.1, opening.lo - 0.1] {
          let p = middle + opening.normal * side
          if let found = rooms.firstIndex(where: { PlanGeometry.contains($0, p) }) {
            room = room ?? found
          }
        }
      }
      guard touches || !open else { continue }
      // Rectangles: runs along each row, merged with the same run on the rows above.
      func rectangle(_ i0: Int, _ i1: Int, _ j0: Int, _ j1: Int) -> [Point2] {
        let x0 = low.x + Double(i0) * cell
        let x1 = low.x + Double(i1 + 1) * cell
        let y0 = low.y + Double(j0) * cell
        let y1 = low.y + Double(j1 + 1) * cell
        return [
          Point2(x: x0, y: y0), Point2(x: x1, y: y0), Point2(x: x1, y: y1),
          Point2(x: x0, y: y1),
        ]
      }
      var runs: [Int: [(Int, Int)]] = [:]
      let set = Set(members)
      for j in Set(members.map { $0 / width }).sorted() {
        var i = 0
        var row: [(Int, Int)] = []
        while i < width {
          if set.contains(j * width + i) {
            var e = i
            while e + 1 < width && set.contains(j * width + e + 1) { e += 1 }
            row.append((i, e))
            i = e + 1
          } else {
            i += 1
          }
        }
        runs[j] = row
      }
      var rects: [[Point2]] = []
      var openRuns: [String: (i0: Int, i1: Int, j0: Int)] = [:]
      let rows = runs.keys.sorted()
      var previousRow: Int?
      for j in rows {
        var current: [String: (i0: Int, i1: Int, j0: Int)] = [:]
        for (i0, i1) in runs[j]! {
          let key = "\(i0)/\(i1)"
          if previousRow == j - 1, let run = openRuns[key] {
            current[key] = run
            openRuns[key] = nil
          } else {
            current[key] = (i0, i1, j)
          }
        }
        for run in openRuns.values {
          rects.append(rectangle(run.i0, run.i1, run.j0, previousRow!))
        }
        openRuns = current
        previousRow = j
      }
      for run in openRuns.values.sorted(by: { ($0.j0, $0.i0) < ($1.j0, $1.i0) }) {
        rects.append(rectangle(run.i0, run.i1, run.j0, previousRow!))
      }
      rects.sort { ($0[0].y, $0[0].x) < ($1[0].y, $1[0].x) }
      // Cell sides facing ground outside the closing, joined into straight runs along each
      // grid line: rows of horizontal sides (below and above each cell), then columns.
      var edges: [(Point2, Point2)] = []
      func outside(_ i: Int, _ j: Int) -> Bool {
        i < 0 || j < 0 || i >= width || j >= height || !closed[j * width + i]
      }
      for horizontal in [true, false] {
        for side in [-1, 1] {
          var runs: [Int: [Int]] = [:]
          for index in members {
            let i = index % width
            let j = index / width
            let faces = horizontal ? outside(i, j + side) : outside(i + side, j)
            guard faces else { continue }
            let line = horizontal ? j : i
            runs[line, default: []].append(horizontal ? i : j)
          }
          for line in runs.keys.sorted() {
            let steps = runs[line]!.sorted()
            var first = steps[0]
            var last = steps[0]
            for step in steps.dropFirst() + [Int.max] {
              if step == last + 1 {
                last = step
                continue
              }
              let length = Double(last - first + 1) * cell
              if length >= minimumEdge {
                let across = Double(line) + (side > 0 ? 1 : 0)
                if horizontal {
                  let y = low.y + across * cell
                  edges.append(
                    (
                      Point2(x: low.x + Double(first) * cell, y: y),
                      Point2(x: low.x + Double(last + 1) * cell, y: y)
                    ))
                } else {
                  let x = low.x + across * cell
                  edges.append(
                    (
                      Point2(x: x, y: low.y + Double(first) * cell),
                      Point2(x: x, y: low.y + Double(last + 1) * cell)
                    ))
                }
              }
              first = step
              last = step
            }
          }
        }
      }
      results.append((rects, room, edges))
    }
    return results
  }
}
