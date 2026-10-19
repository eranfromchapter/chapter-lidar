import CaptureContract
import CaptureModelMapping
import Foundation
import XCTest

/// Helpers for the walk-through splitting tests (floorplan plan, phase 3).
enum Walkthrough {
  static func context(label: String = "Apartment") throws -> MappingContext {
    MappingContext(
      visitId: try XCTUnwrap(LowercaseUUID(rawValue: "6f1c2a8e-3b7d-4e59-9a14-2c8d5e7f0b31")),
      captureId: try XCTUnwrap(LowercaseUUID(rawValue: "9d4e7b12-5a3c-4f86-b2e1-7c0a9f3d6e58")),
      areaKey: "apartment", label: label)
  }

  /// The mapper's pass-1 walls of a one-room capture.
  static func placements(_ document: RoomPlanDocument) throws -> [WallPlacement] {
    try document.rooms[0].walls.enumerated().map {
      try CaptureModelMapper.wallPlacement($1, id: "wall-\($0 + 1)", roomIndex: 0)
    }
  }

  static func analyze(
    _ document: RoomPlanDocument, _ parameters: WalkthroughSplitter.Parameters = .init()
  ) throws -> (split: WalkthroughSplitter.Split?, diagnostics: WalkthroughSplitter.Diagnostics) {
    WalkthroughSplitter.analyze(document: document, placements: try placements(document), parameters: parameters)
  }

  static func split(_ document: RoomPlanDocument, _ parameters: WalkthroughSplitter.Parameters = .init()) throws
    -> WalkthroughSplitter.Split?
  {
    try analyze(document, parameters).split
  }

  /// Labels of the split rooms, as the mapper derives them.
  static func labels(_ split: WalkthroughSplitter.Split, captureLabel: String = "Apartment") -> [String] {
    RoomTyping.labels(for: split.rooms.map(\.typing), captureLabel: captureLabel)
  }

  /// (label, area to 0.01 m2) of each room, in room order.
  static func summary(_ split: WalkthroughSplitter.Split?) -> [String] {
    guard let split else { return ["no split"] }
    return zip(labels(split), split.rooms).map { "\($0) \(String(format: "%.2f", $1.areaM2))" }
  }

  // MARK: Perturbations of a one-room capture (as in the prototype's battery)

  /// Ends and unit direction of a wall in plan (x, z).
  static func ends(_ wall: RoomPlanSurface) -> (a: (Double, Double), b: (Double, Double), u: (Double, Double)) {
    let m = wall.transform.columns
    let n = (m[0][0] * m[0][0] + m[0][2] * m[0][2]).squareRoot()
    let u = (m[0][0] / n, m[0][2] / n)
    let c = (m[3][0], m[3][2])
    let h = wall.dimensions[0] / 2
    return ((c.0 - u.0 * h, c.1 - u.1 * h), (c.0 + u.0 * h, c.1 + u.1 * h), u)
  }

  /// The wall moved to run from `a` to `b` (its direction is kept).
  static func setWall(_ wall: inout RoomPlanSurface, _ a: (Double, Double), _ b: (Double, Double)) {
    wall.transform.columns[3][0] = (a.0 + b.0) / 2
    wall.transform.columns[3][2] = (a.1 + b.1) / 2
    wall.dimensions[0] = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
  }

  /// Each wall end moved along the wall and the whole wall moved sideways, each by up to `sigma`.
  static func jitter(_ document: RoomPlanDocument, sigma: Double, seed: UInt64) -> RoomPlanDocument {
    var document = document
    var rng = SplitMix64(seed: seed)
    for index in document.rooms[0].walls.indices {
      let (a, b, u) = ends(document.rooms[0].walls[index])
      let n = (-u.1, u.0)
      let da = rng.uniform(-sigma, sigma)
      let db = rng.uniform(-sigma, sigma)
      let dl = rng.uniform(-sigma, sigma)
      setWall(
        &document.rooms[0].walls[index], (a.0 - u.0 * da + n.0 * dl, a.1 - u.1 * da + n.1 * dl),
        (b.0 + u.0 * db + n.0 * dl, b.1 + u.1 * db + n.1 * dl))
    }
    return document
  }

  /// Walls, doors, windows and objects in a shuffled order.
  static func shuffled(_ document: RoomPlanDocument, seed: UInt64) -> RoomPlanDocument {
    var document = document
    var rng = SplitMix64(seed: seed)
    rng.shuffle(&document.rooms[0].walls)
    rng.shuffle(&document.rooms[0].doors)
    rng.shuffle(&document.rooms[0].windows)
    rng.shuffle(&document.rooms[0].objects)
    return document
  }

  /// The whole capture turned by `theta` about +Y and moved by (tx, tz).
  static func moved(_ document: RoomPlanDocument, theta: Double, tx: Double, tz: Double) -> RoomPlanDocument {
    let c = cos(theta)
    let s = sin(theta)
    let r = [[c, 0, -s, 0], [0, 1, 0, 0], [s, 0, c, 0], [tx, 0, tz, 1]]
    func apply(_ m: Matrix4) -> Matrix4 {
      var columns = [[Double]](repeating: [0, 0, 0, 0], count: 4)
      for j in 0..<4 {
        for i in 0..<4 {
          var sum = 0.0
          for k in 0..<4 { sum += r[k][i] * m.columns[j][k] }
          columns[j][i] = sum
        }
      }
      return Matrix4(columns: columns)!
    }
    var room = document.rooms[0]
    for i in room.walls.indices { room.walls[i].transform = apply(room.walls[i].transform) }
    for i in room.doors.indices { room.doors[i].transform = apply(room.doors[i].transform) }
    for i in room.windows.indices { room.windows[i].transform = apply(room.windows[i].transform) }
    for i in room.openings.indices { room.openings[i].transform = apply(room.openings[i].transform) }
    for i in room.floors.indices { room.floors[i].transform = apply(room.floors[i].transform) }
    for i in room.objects.indices { room.objects[i].transform = apply(room.objects[i].transform) }
    for i in room.sections.indices {
      guard let p = room.sections[i].center else { continue }
      room.sections[i].center = Vector3(c * p.x + s * p.z + tx, p.y, -s * p.x + c * p.z + tz)
    }
    return RoomPlanDocument(rooms: [room], isStructure: false)
  }

  /// Without wall `identifier` and the openings RoomPlan put in it.
  static func dropping(_ document: RoomPlanDocument, wall identifier: String) -> RoomPlanDocument {
    var room = document.rooms[0]
    room.walls.removeAll { $0.identifier == identifier }
    room.doors.removeAll { $0.parentIdentifier == identifier }
    room.windows.removeAll { $0.parentIdentifier == identifier }
    room.openings.removeAll { $0.parentIdentifier == identifier }
    return RoomPlanDocument(rooms: [room], isStructure: false)
  }

  /// Hausdorff distance between two rings in plan, vertex to boundary both ways.
  static func hausdorff(_ a: [Vector3], _ b: [Vector3]) -> Double {
    func distance(_ p: Vector3, _ ring: [Vector3]) -> Double {
      var best = Double.infinity
      for i in ring.indices {
        let s = ring[i]
        let e = ring[(i + 1) % ring.count]
        let dx = e.x - s.x
        let dz = e.z - s.z
        let l2 = dx * dx + dz * dz
        let t = l2 > 0 ? max(0, min(1, ((p.x - s.x) * dx + (p.z - s.z) * dz) / l2)) : 0
        let qx = s.x + dx * t - p.x
        let qz = s.z + dz * t - p.z
        best = min(best, (qx * qx + qz * qz).squareRoot())
      }
      return best
    }
    return max(a.map { distance($0, b) }.max() ?? 0, b.map { distance($0, a) }.max() ?? 0)
  }
}
