import Foundation

/// Result of `MeshDecimator.decimate`.
public struct DecimationResult: Sendable {
  public var mesh: TriangleMesh
  public var inputFaces: Int
  public var outputFaces: Int
  public var faceBudget: Int
  /// False when no more safe collapses were possible and the mesh is still above the budget.
  public var reachedBudget: Bool
}

/// Reduces a mesh to a face budget with quadric error edge collapse.
///
/// Planar regions collapse first (zero error), while corners, creases and open borders carry
/// large quadric error, so flat walls, floors and their edges survive. Vertices at the same
/// position are welded before the work and split again at creases afterwards, so normals stay
/// sharp across wall/floor corners. A mesh within the budget is returned unchanged.
public enum MeshDecimator {
  /// Default face budget of the export (1.5 million faces).
  public static let defaultFaceBudget = 1_500_000

  /// Welding tolerance: vertices closer than this (per axis grid cell) are the same vertex.
  static let weldCell: Double = 1e-5

  public static func decimate(
    _ input: TriangleMesh,
    faceBudget: Int = defaultFaceBudget,
    creaseAngleDegrees: Double = 35
  ) throws -> DecimationResult {
    try input.validate()
    guard faceBudget >= 4 else {
      throw MeshExportError.invalidOption("face budget must be at least 4")
    }
    let inputFaces = input.triangleCount
    if inputFaces <= faceBudget {
      return DecimationResult(
        mesh: input, inputFaces: inputFaces, outputFaces: inputFaces, faceBudget: faceBudget,
        reachedBudget: true)
    }
    var work = WorkMesh(input)
    work.collapse(toFaces: faceBudget)
    let mesh = work.makeMesh(creaseAngleDegrees: creaseAngleDegrees)
    return DecimationResult(
      mesh: mesh, inputFaces: inputFaces, outputFaces: mesh.triangleCount, faceBudget: faceBudget,
      reachedBudget: mesh.triangleCount <= faceBudget)
  }
}

// MARK: - Quadric

private struct Quadric {
  // A = [[a0 a1 a2],[a1 a3 a4],[a2 a4 a5]], b = [b0 b1 b2], c.
  var a0 = 0.0, a1 = 0.0, a2 = 0.0, a3 = 0.0, a4 = 0.0, a5 = 0.0
  var b0 = 0.0, b1 = 0.0, b2 = 0.0
  var c = 0.0

  /// Adds weight * (plane distance)^2 for the plane n . p + d = 0 (n is a unit vector).
  mutating func addPlane(_ n: SIMD3<Double>, _ d: Double, weight w: Double) {
    a0 += w * n.x * n.x
    a1 += w * n.x * n.y
    a2 += w * n.x * n.z
    a3 += w * n.y * n.y
    a4 += w * n.y * n.z
    a5 += w * n.z * n.z
    b0 += w * d * n.x
    b1 += w * d * n.y
    b2 += w * d * n.z
    c += w * d * d
  }

  static func + (l: Quadric, r: Quadric) -> Quadric {
    Quadric(
      a0: l.a0 + r.a0, a1: l.a1 + r.a1, a2: l.a2 + r.a2, a3: l.a3 + r.a3, a4: l.a4 + r.a4,
      a5: l.a5 + r.a5, b0: l.b0 + r.b0, b1: l.b1 + r.b1, b2: l.b2 + r.b2, c: l.c + r.c)
  }

  func error(at p: SIMD3<Double>) -> Double {
    let x = a0 * p.x + a1 * p.y + a2 * p.z
    let y = a1 * p.x + a3 * p.y + a4 * p.z
    let z = a2 * p.x + a4 * p.y + a5 * p.z
    return p.x * x + p.y * y + p.z * z + 2 * (b0 * p.x + b1 * p.y + b2 * p.z) + c
  }

  /// The error-minimising point, if A is well conditioned.
  func optimum() -> SIMD3<Double>? {
    let trace = a0 + a3 + a5
    guard trace > 0 else { return nil }
    let det =
      a0 * (a3 * a5 - a4 * a4) - a1 * (a1 * a5 - a4 * a2) + a2 * (a1 * a4 - a3 * a2)
    guard abs(det) > 1e-7 * trace * trace * trace else { return nil }
    let inv = 1.0 / det
    let i00 = (a3 * a5 - a4 * a4) * inv
    let i01 = (a2 * a4 - a1 * a5) * inv
    let i02 = (a1 * a4 - a2 * a3) * inv
    let i11 = (a0 * a5 - a2 * a2) * inv
    let i12 = (a1 * a2 - a0 * a4) * inv
    let i22 = (a0 * a3 - a1 * a1) * inv
    return SIMD3(
      -(i00 * b0 + i01 * b1 + i02 * b2),
      -(i01 * b0 + i11 * b1 + i12 * b2),
      -(i02 * b0 + i12 * b1 + i22 * b2))
  }
}

// MARK: - Heap

private struct Candidate {
  var cost: Double
  var a: Int32
  var b: Int32
  var versionA: Int32
  var versionB: Int32
  var position: SIMD3<Double>
}

private struct MinHeap {
  var items: [Candidate] = []

  var isEmpty: Bool { items.isEmpty }

  mutating func push(_ item: Candidate) {
    items.append(item)
    var child = items.count - 1
    while child > 0 {
      let parent = (child - 1) / 2
      if items[parent].cost <= items[child].cost { break }
      items.swapAt(parent, child)
      child = parent
    }
  }

  mutating func pop() -> Candidate? {
    guard !items.isEmpty else { return nil }
    let top = items[0]
    let last = items.removeLast()
    if !items.isEmpty {
      items[0] = last
      var parent = 0
      let count = items.count
      while true {
        let left = parent * 2 + 1
        let right = left + 1
        var smallest = parent
        if left < count && items[left].cost < items[smallest].cost { smallest = left }
        if right < count && items[right].cost < items[smallest].cost { smallest = right }
        if smallest == parent { break }
        items.swapAt(parent, smallest)
        parent = smallest
      }
    }
    return top
  }
}

// MARK: - Welded working mesh

private struct CellKey: Hashable {
  var x: Int64
  var y: Int64
  var z: Int64
}

private struct WorkMesh {
  var positions: [SIMD3<Double>] = []
  var colorSum: [SIMD3<Double>] = []
  var colorWeight: [Double] = []
  var hasColors = false
  var faces: [SIMD3<Int32>] = []
  var alive: [Bool] = []
  var aliveCount = 0
  var vertexFaces: [[Int32]] = []
  var vertexAlive: [Bool] = []
  var version: [Int32] = []
  var quadrics: [Quadric] = []
  /// Edges with more than two faces: never collapsed.
  var lockedVertices: [Bool] = []
  var heap = MinHeap()

  init(_ input: TriangleMesh) {
    hasColors = !input.colors.isEmpty
    // Weld by position.
    var cells: [CellKey: Int32] = [:]
    cells.reserveCapacity(input.positions.count)
    var remap = [Int32](repeating: 0, count: input.positions.count)
    for (index, p) in input.positions.enumerated() {
      let key = CellKey(
        x: Int64((Double(p.x) / MeshDecimator.weldCell).rounded()),
        y: Int64((Double(p.y) / MeshDecimator.weldCell).rounded()),
        z: Int64((Double(p.z) / MeshDecimator.weldCell).rounded()))
      if let existing = cells[key] {
        remap[index] = existing
      } else {
        let id = Int32(positions.count)
        cells[key] = id
        remap[index] = id
        positions.append(SIMD3(Double(p.x), Double(p.y), Double(p.z)))
        colorSum.append(.zero)
        colorWeight.append(0)
      }
      if hasColors {
        let c = input.colors[index]
        let id = Int(remap[index])
        colorSum[id] += SIMD3(Double(c.r), Double(c.g), Double(c.b))
        colorWeight[id] += 1
      }
    }
    faces.reserveCapacity(input.triangleCount)
    var corner = 0
    while corner + 2 < input.indices.count {
      let a = remap[Int(input.indices[corner])]
      let b = remap[Int(input.indices[corner + 1])]
      let c = remap[Int(input.indices[corner + 2])]
      corner += 3
      if a == b || b == c || a == c { continue }
      faces.append(SIMD3(a, b, c))
    }
    alive = [Bool](repeating: true, count: faces.count)
    aliveCount = faces.count
    vertexAlive = [Bool](repeating: true, count: positions.count)
    version = [Int32](repeating: 0, count: positions.count)
    lockedVertices = [Bool](repeating: false, count: positions.count)
    vertexFaces = [[Int32]](repeating: [], count: positions.count)
    for (index, f) in faces.enumerated() {
      vertexFaces[Int(f.x)].append(Int32(index))
      vertexFaces[Int(f.y)].append(Int32(index))
      vertexFaces[Int(f.z)].append(Int32(index))
    }
    buildQuadrics()
  }

  static func edgeKey(_ a: Int32, _ b: Int32) -> UInt64 {
    let lo = UInt64(UInt32(Swift.min(a, b)))
    let hi = UInt64(UInt32(Swift.max(a, b)))
    return (lo << 32) | hi
  }

  mutating func buildQuadrics() {
    quadrics = [Quadric](repeating: Quadric(), count: positions.count)
    var edgeFaces: [UInt64: Int32] = [:]
    edgeFaces.reserveCapacity(faces.count * 2)
    for f in faces {
      for (u, v) in [(f.x, f.y), (f.y, f.z), (f.z, f.x)] {
        edgeFaces[WorkMesh.edgeKey(u, v), default: 0] += 1
      }
    }
    for f in faces {
      let p0 = positions[Int(f.x)]
      let p1 = positions[Int(f.y)]
      let p2 = positions[Int(f.z)]
      let cross = cross3(p1 - p0, p2 - p0)
      let twiceArea = length3(cross)
      guard twiceArea > 1e-18 else { continue }
      let n = cross / twiceArea
      let d = -dot3(n, p0)
      let area = twiceArea / 2
      quadrics[Int(f.x)].addPlane(n, d, weight: area)
      quadrics[Int(f.y)].addPlane(n, d, weight: area)
      quadrics[Int(f.z)].addPlane(n, d, weight: area)
      for (u, v) in [(f.x, f.y), (f.y, f.z), (f.z, f.x)] {
        let count = edgeFaces[WorkMesh.edgeKey(u, v)] ?? 0
        if count == 1 {
          // Border edge: a plane through the edge, perpendicular to the face, weighted strongly.
          let edge = positions[Int(v)] - positions[Int(u)]
          let length = length3(edge)
          guard length > 1e-12 else { continue }
          let side = cross3(edge / length, n)
          let sideLength = length3(side)
          guard sideLength > 1e-12 else { continue }
          let bn = side / sideLength
          let bd = -dot3(bn, positions[Int(u)])
          let weight = 100 * length * length
          quadrics[Int(u)].addPlane(bn, bd, weight: weight)
          quadrics[Int(v)].addPlane(bn, bd, weight: weight)
        } else if count > 2 {
          lockedVertices[Int(u)] = true
          lockedVertices[Int(v)] = true
        }
      }
    }
  }

  /// Builds the collapse candidate of edge (a, b).
  func candidate(_ a: Int32, _ b: Int32) -> Candidate {
    let q = quadrics[Int(a)] + quadrics[Int(b)]
    let pa = positions[Int(a)]
    let pb = positions[Int(b)]
    var best = pa
    var bestError = q.error(at: pa)
    let errorB = q.error(at: pb)
    if errorB < bestError {
      best = pb
      bestError = errorB
    }
    let mid = (pa + pb) * 0.5
    let errorMid = q.error(at: mid)
    if errorMid < bestError {
      best = mid
      bestError = errorMid
    }
    let length = length3(pb - pa)
    if let optimum = q.optimum(), length3(optimum - mid) <= 2 * length {
      let errorOptimum = q.error(at: optimum)
      if errorOptimum < bestError {
        best = optimum
        bestError = errorOptimum
      }
    }
    return Candidate(
      cost: Swift.max(0, bestError) + 1e-12 * length * length,
      a: a, b: b, versionA: version[Int(a)], versionB: version[Int(b)], position: best)
  }

  func neighbors(of v: Int32) -> [Int32] {
    var result: [Int32] = []
    for faceId in vertexFaces[Int(v)] {
      let f = faces[Int(faceId)]
      for other in [f.x, f.y, f.z] where other != v && !result.contains(other) {
        result.append(other)
      }
    }
    return result
  }

  /// Can edge (a, b) collapse to `p` without breaking topology or flipping a face?
  func isCollapseValid(_ a: Int32, _ b: Int32, to p: SIMD3<Double>) -> Bool {
    if lockedVertices[Int(a)] || lockedVertices[Int(b)] { return false }
    // Link condition: shared neighbours must be exactly the opposite corners of the edge faces.
    var shared = 0
    for faceId in vertexFaces[Int(a)] {
      let f = faces[Int(faceId)]
      if f.x == b || f.y == b || f.z == b { shared += 1 }
    }
    guard shared >= 1 && shared <= 2 else { return false }
    let neighborsA = neighbors(of: a)
    let neighborsB = neighbors(of: b)
    var common = 0
    for n in neighborsA where n != b && neighborsB.contains(n) { common += 1 }
    guard common == shared else { return false }
    // Flip check on the faces that survive.
    for (v, other) in [(a, b), (b, a)] {
      for faceId in vertexFaces[Int(v)] {
        let f = faces[Int(faceId)]
        if f.x == other || f.y == other || f.z == other { continue }
        let before0 = positions[Int(f.x)]
        let before1 = positions[Int(f.y)]
        let before2 = positions[Int(f.z)]
        let oldNormal = cross3(before1 - before0, before2 - before0)
        let after0 = f.x == v ? p : before0
        let after1 = f.y == v ? p : before1
        let after2 = f.z == v ? p : before2
        let newNormal = cross3(after1 - after0, after2 - after0)
        let oldLength = length3(oldNormal)
        let newLength = length3(newNormal)
        if newLength < 1e-14 || oldLength < 1e-14 { return false }
        if dot3(oldNormal, newNormal) / (oldLength * newLength) < 0.2 { return false }
      }
    }
    return true
  }

  mutating func pushEdges(of v: Int32) {
    for n in neighbors(of: v) {
      heap.push(candidate(v, n))
    }
  }

  mutating func collapse(toFaces target: Int) {
    var seen = Set<UInt64>()
    seen.reserveCapacity(faces.count * 2)
    for f in faces {
      for (u, v) in [(f.x, f.y), (f.y, f.z), (f.z, f.x)] {
        let key = WorkMesh.edgeKey(u, v)
        if seen.insert(key).inserted {
          heap.push(candidate(Swift.min(u, v), Swift.max(u, v)))
        }
      }
    }
    while aliveCount > target, let entry = heap.pop() {
      let a = entry.a
      let b = entry.b
      guard vertexAlive[Int(a)], vertexAlive[Int(b)],
        version[Int(a)] == entry.versionA, version[Int(b)] == entry.versionB
      else { continue }
      guard isCollapseValid(a, b, to: entry.position) else { continue }
      apply(a, b, to: entry.position)
      pushEdges(of: a)
    }
  }

  /// Merges b into a at position p.
  mutating func apply(_ a: Int32, _ b: Int32, to p: SIMD3<Double>) {
    for faceId in vertexFaces[Int(b)] {
      let index = Int(faceId)
      guard alive[index] else { continue }
      var f = faces[index]
      if f.x == a || f.y == a || f.z == a {
        // The face collapses with the edge.
        alive[index] = false
        aliveCount -= 1
        let third = f.x != a && f.x != b ? f.x : (f.y != a && f.y != b ? f.y : f.z)
        vertexFaces[Int(third)].removeAll { $0 == faceId }
        vertexFaces[Int(a)].removeAll { $0 == faceId }
      } else {
        if f.x == b { f.x = a }
        if f.y == b { f.y = a }
        if f.z == b { f.z = a }
        faces[index] = f
        vertexFaces[Int(a)].append(faceId)
      }
    }
    vertexFaces[Int(b)].removeAll()
    vertexAlive[Int(b)] = false
    positions[Int(a)] = p
    quadrics[Int(a)] = quadrics[Int(a)] + quadrics[Int(b)]
    colorSum[Int(a)] += colorSum[Int(b)]
    colorWeight[Int(a)] += colorWeight[Int(b)]
    version[Int(a)] += 1
    version[Int(b)] += 1
  }

  /// Compacts the result and splits vertices at creases so normals stay sharp.
  func makeMesh(creaseAngleDegrees: Double) -> TriangleMesh {
    let cosCrease = cos(creaseAngleDegrees * .pi / 180)
    var faceNormals = [SIMD3<Double>](repeating: .zero, count: faces.count)
    for (index, f) in faces.enumerated() where alive[index] {
      faceNormals[index] = cross3(
        positions[Int(f.y)] - positions[Int(f.x)], positions[Int(f.z)] - positions[Int(f.x)])
    }
    var outPositions: [SIMD3<Float>] = []
    var outNormals: [SIMD3<Float>] = []
    var outColors: [RGB8] = []
    var outIndices = [UInt32](repeating: 0, count: faces.count * 3)
    var cornerOf = [Int: UInt32]()  // face * 3 + corner -> output vertex
    cornerOf.reserveCapacity(aliveCount * 3)

    struct Cluster {
      var reference: SIMD3<Double>
      var sum: SIMD3<Double>
      var output: UInt32
    }
    for v in 0..<positions.count where vertexAlive[v] && !vertexFaces[v].isEmpty {
      var clusters: [Cluster] = []
      var assignments: [(face: Int32, corner: Int, cluster: Int)] = []
      for faceId in vertexFaces[v] {
        let index = Int(faceId)
        guard alive[index] else { continue }
        let f = faces[index]
        let corner = f.x == Int32(v) ? 0 : (f.y == Int32(v) ? 1 : 2)
        let normal = faceNormals[index]
        let length = length3(normal)
        let unit = length > 0 ? normal / length : SIMD3(0, 1, 0)
        var found = -1
        for (ci, cluster) in clusters.enumerated() where dot3(cluster.reference, unit) >= cosCrease {
          found = ci
          break
        }
        if found < 0 {
          clusters.append(Cluster(reference: unit, sum: .zero, output: 0))
          found = clusters.count - 1
        }
        clusters[found].sum += normal
        assignments.append((faceId, corner, found))
      }
      let color: RGB8? =
        hasColors && colorWeight[v] > 0
        ? RGB8(
          r: UInt8(Swift.min(255, (colorSum[v].x / colorWeight[v]).rounded())),
          g: UInt8(Swift.min(255, (colorSum[v].y / colorWeight[v]).rounded())),
          b: UInt8(Swift.min(255, (colorSum[v].z / colorWeight[v]).rounded())))
        : nil
      for ci in clusters.indices {
        clusters[ci].output = UInt32(outPositions.count)
        let p = positions[v]
        outPositions.append(SIMD3(Float(p.x), Float(p.y), Float(p.z)))
        let n = clusters[ci].sum
        let length = length3(n)
        let unit = length > 0 ? n / length : SIMD3(0, 1, 0)
        outNormals.append(SIMD3(Float(unit.x), Float(unit.y), Float(unit.z)))
        if hasColors { outColors.append(color ?? RGB8(r: 255, g: 255, b: 255)) }
      }
      for assignment in assignments {
        cornerOf[Int(assignment.face) * 3 + assignment.corner] = clusters[assignment.cluster].output
      }
    }
    var written = 0
    for (index, _) in faces.enumerated() where alive[index] {
      outIndices[written] = cornerOf[index * 3] ?? 0
      outIndices[written + 1] = cornerOf[index * 3 + 1] ?? 0
      outIndices[written + 2] = cornerOf[index * 3 + 2] ?? 0
      written += 3
    }
    outIndices.removeLast(outIndices.count - written)
    return TriangleMesh(
      positions: outPositions, normals: outNormals, colors: outColors, indices: outIndices)
  }
}
