import CaptureContract
import Foundation
import MeshExport

/// Collects the triangles of the extruded model. Every face is a rectangle or a triangle given
/// with the direction its outside faces; the builder orders the corners so the triangle winding
/// is counter-clockwise seen from that side, which is what the writers and the station expect.
/// Vertices are not shared between faces: the mesh is small and the writers compute smooth
/// normals per vertex, so sharing across a box edge would only round the edge.
struct MeshBuilder {
  private(set) var positions: [SIMD3<Float>] = []
  private(set) var indices: [UInt32] = []

  /// The vertical direction of the model.
  static let up = SIMD3<Double>(0, 1, 0)

  /// A triangle whose corners are given counter-clockwise seen from its outside.
  mutating func addTriangle(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) {
    let base = UInt32(positions.count)
    positions.append(SIMD3<Float>(Float(a.x), Float(a.y), Float(a.z)))
    positions.append(SIMD3<Float>(Float(b.x), Float(b.y), Float(b.z)))
    positions.append(SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z)))
    indices.append(contentsOf: [base, base + 1, base + 2])
  }

  /// The parallelogram `origin`, `origin + u`, `origin + u + v`, `origin + v`, wound so that
  /// its normal points along `outward`.
  mutating func addRectangle(
    origin: SIMD3<Double>, u: SIMD3<Double>, v: SIMD3<Double>, outward: SIMD3<Double>
  ) {
    let normal = cross(u, v)
    guard dot(normal, normal) > 1e-18 else { return }
    let p0 = origin
    let p1 = origin + u
    let p2 = origin + u + v
    let p3 = origin + v
    if dot(normal, outward) >= 0 {
      addTriangle(p0, p1, p2)
      addTriangle(p0, p2, p3)
    } else {
      addTriangle(p0, p3, p2)
      addTriangle(p0, p2, p1)
    }
  }

  // MARK: - Rooms

  /// The floor of a room at Y 0 facing up and the ceiling underside at `heightM` facing down.
  mutating func addRoom(_ room: CaptureModel.Room) {
    let loop = room.polygon.map { SIMD2<Double>($0.x, -$0.z) }
    let triangles = EarClipping.triangulate(loop)
    guard !triangles.isEmpty, room.heightM > 0 else { return }
    for (i, j, k) in triangles {
      let a = loop[i]
      let b = loop[j]
      let c = loop[k]
      // Counter-clockwise in (x, −z) is counter-clockwise seen from +Y: the floor faces up.
      addTriangle(point(a, 0), point(b, 0), point(c, 0))
      addTriangle(point(a, room.heightM), point(c, room.heightM), point(b, room.heightM))
    }
  }

  private func point(_ plan: SIMD2<Double>, _ y: Double) -> SIMD3<Double> {
    SIMD3(plan.x, y, -plan.y)
  }

  // MARK: - Walls

  /// A wall as a closed box around its centreline, `thicknessM` across and `heightM` tall,
  /// with every opening cut through both faces. In the wall's own frame `along` runs from the
  /// start, `across` from −t/2 to +t/2 and `up` from the base; the two big faces are cut into
  /// rectangles around the openings, and each opening gets its jambs, sill and head so the box
  /// stays watertight.
  mutating func addWall(_ wall: CaptureModel.Wall, openings: [CaptureModel.WallOpening]) {
    let start = SIMD3<Double>(wall.start.x, wall.start.y, wall.start.z)
    let end = SIMD3<Double>(wall.end.x, wall.end.y, wall.end.z)
    let span = SIMD3<Double>(end.x - start.x, 0, end.z - start.z)
    let length = (span.x * span.x + span.z * span.z).squareRoot()
    let height = wall.heightM
    let thickness = max(wall.thicknessM, 0.001)
    guard length > 1e-6, height > 0 else { return }
    let along = span / length
    let across = SIMD3<Double>(-along.z, 0, along.x)
    let up = Self.up
    let base = SIMD3<Double>(start.x, start.y, start.z)
    func local(_ a: Double, _ c: Double, _ y: Double) -> SIMD3<Double> {
      base + along * a + across * c + up * y
    }

    let holes = openings.compactMap { opening -> Hole? in
      let a0 = max(0, opening.offsetM - opening.widthM / 2)
      let a1 = min(length, opening.offsetM + opening.widthM / 2)
      let y0 = max(0, opening.bottomM)
      let y1 = min(height, opening.bottomM + opening.heightM)
      guard a1 - a0 > 1e-6, y1 - y0 > 1e-6 else { return nil }
      return Hole(a0: a0, a1: a1, y0: y0, y1: y1)
    }

    // The two faces, each as the rectangles left around the openings.
    for side in [-1.0, 1.0] {
      let c = side * thickness / 2
      let outward = across * side
      for rectangle in Self.facePieces(length: length, height: height, holes: holes) {
        addRectangle(
          origin: local(rectangle.a0, c, rectangle.y0), u: along * (rectangle.a1 - rectangle.a0),
          v: up * (rectangle.y1 - rectangle.y0), outward: outward)
      }
    }

    // Jambs, sill and head of each opening face into the hole.
    for hole in holes {
      let width = hole.a1 - hole.a0
      let tall = hole.y1 - hole.y0
      addRectangle(
        origin: local(hole.a0, -thickness / 2, hole.y0), u: across * thickness, v: up * tall,
        outward: along)
      addRectangle(
        origin: local(hole.a1, -thickness / 2, hole.y0), u: across * thickness, v: up * tall,
        outward: -along)
      if hole.y0 > 1e-6 {
        addRectangle(
          origin: local(hole.a0, -thickness / 2, hole.y0), u: along * width, v: across * thickness,
          outward: up)
      }
      if hole.y1 < height - 1e-6 {
        addRectangle(
          origin: local(hole.a0, -thickness / 2, hole.y1), u: along * width, v: across * thickness,
          outward: -up)
      }
    }

    // Ends, top and bottom.
    addRectangle(
      origin: local(0, -thickness / 2, 0), u: across * thickness, v: up * height, outward: -along)
    addRectangle(
      origin: local(length, -thickness / 2, 0), u: across * thickness, v: up * height,
      outward: along)
    addRectangle(
      origin: local(0, -thickness / 2, height), u: along * length, v: across * thickness,
      outward: up)
    addRectangle(
      origin: local(0, -thickness / 2, 0), u: along * length, v: across * thickness, outward: -up)
  }

  struct Hole {
    var a0: Double
    var a1: Double
    var y0: Double
    var y1: Double
  }

  struct Piece {
    var a0: Double
    var a1: Double
    var y0: Double
    var y1: Double
  }

  /// The solid rectangles of a wall face `length` by `height` with `holes` cut out: the face is
  /// cut into vertical strips at every hole edge, and each strip keeps what is not covered by
  /// the holes that span it. Overlapping holes are merged within a strip.
  static func facePieces(length: Double, height: Double, holes: [Hole]) -> [Piece] {
    var cuts: [Double] = [0, length]
    for hole in holes {
      cuts.append(hole.a0)
      cuts.append(hole.a1)
    }
    cuts.sort()
    var pieces: [Piece] = []
    for index in 0..<(cuts.count - 1) {
      let s0 = cuts[index]
      let s1 = cuts[index + 1]
      guard s1 - s0 > 1e-9 else { continue }
      let covering = holes.filter { $0.a0 <= s0 + 1e-9 && $0.a1 >= s1 - 1e-9 }
        .map { (lo: $0.y0, hi: $0.y1) }
        .sorted { $0.lo < $1.lo }
      var cursor = 0.0
      for interval in covering {
        if interval.lo > cursor + 1e-9 {
          pieces.append(Piece(a0: s0, a1: s1, y0: cursor, y1: interval.lo))
        }
        cursor = max(cursor, interval.hi)
      }
      if height > cursor + 1e-9 {
        pieces.append(Piece(a0: s0, a1: s1, y0: cursor, y1: height))
      }
    }
    return pieces
  }
}

/// Ear clipping of a simple polygon in the plane, for the floor and ceiling of a room.
enum EarClipping {
  /// Index triples into `loop`, each counter-clockwise when `loop` is (and wound the same way
  /// as the input otherwise). Repeated and collinear points are skipped. A loop that cannot be
  /// clipped (self-intersecting) falls back to a fan so the room is never silently dropped.
  static func triangulate(_ loop: [SIMD2<Double>]) -> [(Int, Int, Int)] {
    guard loop.count >= 3 else { return [] }
    var remaining: [Int] = []
    for index in loop.indices {
      let previous = loop[(index + loop.count - 1) % loop.count]
      let current = loop[index]
      let next = loop[(index + 1) % loop.count]
      let a = current - previous
      let b = next - current
      let degenerate = planLength(a) < 1e-9 || abs(a.x * b.y - a.y * b.x) < 1e-12
      if !degenerate { remaining.append(index) }
    }
    guard remaining.count >= 3 else { return [] }
    if signedArea2(remaining.map { loop[$0] }) < 0 {
      remaining.reverse()
    }
    var triangles: [(Int, Int, Int)] = []
    var guardCount = 0
    while remaining.count > 3 {
      guardCount += 1
      guard guardCount <= loop.count * loop.count + 10, let ear = findEar(loop, remaining) else {
        // No ear: the outline is not simple. Fan from the first remaining point.
        for index in 1..<(remaining.count - 1) {
          triangles.append((remaining[0], remaining[index], remaining[index + 1]))
        }
        return triangles
      }
      let count = remaining.count
      triangles.append((remaining[(ear + count - 1) % count], remaining[ear], remaining[(ear + 1) % count]))
      remaining.remove(at: ear)
    }
    triangles.append((remaining[0], remaining[1], remaining[2]))
    return triangles
  }

  private static func findEar(_ loop: [SIMD2<Double>], _ remaining: [Int]) -> Int? {
    let count = remaining.count
    for position in 0..<count {
      let a = loop[remaining[(position + count - 1) % count]]
      let b = loop[remaining[position]]
      let c = loop[remaining[(position + 1) % count]]
      let ab = b - a
      let bc = c - b
      guard ab.x * bc.y - ab.y * bc.x > 1e-12 else { continue }  // reflex corner
      var empty = true
      for other in 0..<count
      where other != position && other != (position + count - 1) % count
        && other != (position + 1) % count
      {
        if contains(a, b, c, loop[remaining[other]]) {
          empty = false
          break
        }
      }
      if empty { return position }
    }
    return nil
  }

  private static func contains(
    _ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>, _ p: SIMD2<Double>
  ) -> Bool {
    func side(_ p1: SIMD2<Double>, _ p2: SIMD2<Double>, _ p3: SIMD2<Double>) -> Double {
      (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
    }
    let d1 = side(p, a, b)
    let d2 = side(p, b, c)
    let d3 = side(p, c, a)
    let negative = d1 < -1e-12 || d2 < -1e-12 || d3 < -1e-12
    let positive = d1 > 1e-12 || d2 > 1e-12 || d3 > 1e-12
    return !(negative && positive)
  }

  static func signedArea2(_ loop: [SIMD2<Double>]) -> Double {
    var sum = 0.0
    for index in loop.indices {
      let a = loop[index]
      let b = loop[(index + 1) % loop.count]
      sum += a.x * b.y - b.x * a.y
    }
    return sum
  }
}

@inline(__always)
private func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
  SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

@inline(__always)
private func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
  a.x * b.x + a.y * b.y + a.z * b.z
}

@inline(__always)
private func planLength(_ a: SIMD2<Double>) -> Double {
  (a.x * a.x + a.y * a.y).squareRoot()
}
