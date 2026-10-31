import CaptureContract
import CaptureModelMapping
import Foundation

/// One solve of a whole sketch (spec F14 Part 1): the input checked, every room solved in its
/// own frame by `RoomSolver`, the rooms placed by their shared walls, and the capture model
/// written with its walls as centrelines, its openings by offset, and the summary of the capture
/// record. Millimetres inside; the model is metres.
struct SketchSolveRun {
  let measurements: SketchMeasurements
  let context: SketchSolveContext

  private typealias Room = SketchMeasurements.Room

  func run() throws -> SketchSolveResult {
    let rooms = measurements.rooms
    guard !rooms.isEmpty else { throw SketchSolverError.noRooms }
    try checkIds(rooms)

    let solved = try rooms.map(RoomSolver.solve)
    let thickness = try wallThicknesses(rooms)
    let placed = try place(rooms, solved: solved, thickness: thickness)

    var modelRooms: [CaptureModel.Room] = []
    var modelWalls: [CaptureModel.Wall] = []
    var doors: [CaptureModel.WallOpening] = []
    var windows: [CaptureModel.WallOpening] = []
    var passages: [CaptureModel.WallOpening] = []
    var objects: [CaptureModel.DetectedObject] = []
    var notes: [SketchSolveNote] = []
    var ceilingAssumed = false
    var wallsMeasured = 0

    for (roomIndex, room) in rooms.enumerated() {
      notes.append(contentsOf: solved[roomIndex].notes)
      let corners = placed[roomIndex]
      let n = corners.count

      let ceilingMm: Double
      if let own = room.ceilingHeight ?? measurements.ceilingHeight, own.valueMm > 0 {
        ceilingMm = own.valueMm
      } else {
        ceilingMm = SketchDefaults.ceilingHeightMm
        ceilingAssumed = true
      }

      // The polygon is the inside faces; the mirror in RoomSolver made it counter-clockwise,
      // and the contract helper is the check that it stayed so through placement.
      let loop = PolygonMath.counterClockwise(corners.map { Vector3($0.x / 1000, 0, -$0.y / 1000) })
      modelRooms.append(
        CaptureModel.Room(
          id: room.id, label: room.label, polygon: loop.map(\.contractVec3),
          heightM: metres(ceilingMm), type: room.type,
          typeSource: room.type == nil ? nil : .operator))

      let mitres = mitrePoints(corners, thickness: thickness[roomIndex])
      for (wallIndex, wall) in room.walls.enumerated() {
        if wall.length?.measured == true { wallsMeasured += 1 }
        let a = corners[wallIndex]
        let b = corners[(wallIndex + 1) % n]
        let direction = (b - a).normalized ?? Plan2(1, 0)
        let t = thickness[roomIndex][wallIndex]
        var start = mitres[wallIndex]
        var end = mitres[(wallIndex + 1) % n]
        if (end - start).length < 1 {
          // A wall shorter than its thickness between two re-entrant corners: keep the
          // offset face without the mitre so the wall does not vanish.
          start = a + direction.rightNormal * (t / 2)
          end = b + direction.rightNormal * (t / 2)
        }
        modelWalls.append(
          CaptureModel.Wall(
            id: wall.id, start: start.floorVec3, end: end.floorVec3, heightM: metres(ceilingMm),
            thicknessM: metres(t), roomIds: [room.id],
            confidence: solved[roomIndex].walls[wallIndex].confidence))

        let placedOpenings = placeOpenings(
          room.openings.filter { $0.wallId == wall.id }, room: room, wall: wall,
          insideLength: (b - a).length, startExtension: (a - start).dot(direction),
          ceilingMm: ceilingMm, notes: &notes)
        for (kind, opening) in placedOpenings {
          switch kind {
          case .door: doors.append(opening)
          case .window: windows.append(opening)
          case .opening: passages.append(opening)
          }
        }
      }

      // Furniture drawn in the room (spec F16): boxes standing on the floor, reference only.
      objects.append(
        contentsOf: SketchFurniture.objects(
          room.furniture ?? [], roomId: room.id, roomHeightMm: ceilingMm))
    }

    if ceilingAssumed {
      notes.append(
        SketchSolveNote(
          kind: .ceilingAssumed,
          message:
            "No ceiling height was measured; \(Int(SketchDefaults.ceilingHeightMm)) mm assumed."))
    }

    let model = CaptureModel(
      visitId: measurements.visitId, captureId: measurements.captureId,
      areaKey: measurements.areaKey, label: context.label, rooms: modelRooms, walls: modelWalls,
      doors: doors, windows: windows, openings: passages, objects: objects, refs: context.refs)

    let limited = notes.contains { note in
      switch note.kind {
      case .wallEstimated, .cornerAssumedSquare, .ceilingAssumed: return true
      case .openingEstimated(_, let field): return field == .width || field == .position
      case .closureResidual(_, _, _, let grade): return grade != .pass
      case .wallDerivedFromClosure: return false
      }
    }
    let residual = solved.flatMap(\.closureResiduals).max().map { ($0 * 1000).rounded() / 1000 }
    let summary = CaptureRecord.Capture.SketchSummary(
      measurements: limited ? .limited : .complete, wallsMeasured: wallsMeasured,
      wallsEstimated: modelWalls.filter { $0.confidence == .low }.count,
      ceilingHeightSource: ceilingAssumed ? .assumed : .measured, closureResidualMm: residual)
    return SketchSolveResult(model: model, summary: summary, notes: notes)
  }

  // MARK: - Input checks

  /// Ids are unique per kind across the file: a room, a wall and an opening may not reuse an
  /// id of their own kind, since the capture model lists each kind in one array.
  private func checkIds(_ rooms: [Room]) throws {
    var roomIds: Set<String> = []
    var wallIds: Set<String> = []
    var openingIds: Set<String> = []
    var furnitureIds: Set<String> = []
    for room in rooms {
      guard roomIds.insert(room.id).inserted else { throw SketchSolverError.duplicateId(room.id) }
      for wall in room.walls {
        guard wallIds.insert(wall.id).inserted else { throw SketchSolverError.duplicateId(wall.id) }
      }
      for opening in room.openings {
        guard openingIds.insert(opening.id).inserted else {
          throw SketchSolverError.duplicateId(opening.id)
        }
        guard room.walls.contains(where: { $0.id == opening.wallId }) else {
          throw SketchSolverError.unknownWall(roomId: room.id, wallId: opening.wallId)
        }
      }
      for item in room.furniture ?? [] {
        guard furnitureIds.insert(item.id).inserted else {
          throw SketchSolverError.duplicateId(item.id)
        }
      }
    }
  }

  /// The earlier room and wall a `sharedWith` names, as indices.
  private func sharedTarget(
    of shared: SketchMeasurements.SharedWall, before roomIndex: Int, in rooms: [Room],
    roomId: String
  ) throws -> (room: Int, wall: Int) {
    guard let earlier = rooms.firstIndex(where: { $0.id == shared.roomId }), earlier < roomIndex,
      let wall = rooms[earlier].walls.firstIndex(where: { $0.id == shared.wallId })
    else {
      throw SketchSolverError.unknownSharedWall(roomId: roomId, wallId: shared.wallId)
    }
    return (earlier, wall)
  }

  // MARK: - Thickness and placement

  /// Interior 4.5 in, exterior 6 in; the two sides of a shared partition get the thicker of the
  /// two so their centrelines coincide.
  private func wallThicknesses(_ rooms: [Room]) throws -> [[Double]] {
    var thickness = rooms.map { room in
      room.walls.map { wall in
        wall.exterior == true
          ? SketchDefaults.exteriorWallThicknessMm : SketchDefaults.interiorWallThicknessMm
      }
    }
    for (roomIndex, room) in rooms.enumerated() {
      for (wallIndex, wall) in room.walls.enumerated() {
        guard let shared = wall.sharedWith else { continue }
        let target = try sharedTarget(of: shared, before: roomIndex, in: rooms, roomId: room.id)
        let t = max(thickness[roomIndex][wallIndex], thickness[target.room][target.wall])
        thickness[roomIndex][wallIndex] = t
        thickness[target.room][target.wall] = t
      }
    }
    return thickness
  }

  /// World corners of every room. A room with a `placement` (measured where it stands, an AR
  /// walkthrough, spec F15) is turned so wall 0 leaves at `angleDeg` and moved so corner 0 is at
  /// (`x`, `z`); `sharedWith` does not move it. Otherwise the first room keeps its own frame. A
  /// room that shares a wall is turned so that wall runs opposite to the earlier room's wall
  /// (both rooms are counter-clockwise) and moved so its inside face lies one thickness outside
  /// the earlier room's, centred along it. A room that shares nothing goes to the +x side of
  /// everything so far with a 1 m gap.
  private func place(_ rooms: [Room], solved: [SolvedRoom], thickness: [[Double]]) throws
    -> [[Plan2]]
  {
    var world: [[Plan2]] = []
    for (roomIndex, room) in rooms.enumerated() {
      let local = solved[roomIndex].corners
      let n = local.count
      var angle = 0.0
      var translation = Plan2.zero
      if let placement = room.placement {
        // The placement angle is counter-clockwise from +x seen from +Y, which is the plan's
        // own angle (plan y is model −z); the corner is in metres, the plan in millimetres.
        let localDirection = (local[1 % n] - local[0]).normalized ?? Plan2(1, 0)
        angle = placement.angleDeg * Double.pi / 180 - localDirection.angle
        let target = Plan2(placement.x * 1000, -placement.z * 1000)
        translation = target - local[0].rotated(by: angle)
      } else if roomIndex > 0 {
        if let wallIndex = room.walls.firstIndex(where: { $0.sharedWith != nil }),
          let shared = room.walls[wallIndex].sharedWith
        {
          let target = try sharedTarget(of: shared, before: roomIndex, in: rooms, roomId: room.id)
          let earlier = world[target.room]
          let a = earlier[target.wall]
          let b = earlier[(target.wall + 1) % earlier.count]
          let earlierDirection = (b - a).normalized ?? Plan2(1, 0)
          let outward = earlierDirection.rightNormal
          let targetMid = (a + b) * 0.5 + outward * thickness[roomIndex][wallIndex]
          let p = local[wallIndex]
          let q = local[(wallIndex + 1) % n]
          let localDirection = (q - p).normalized ?? Plan2(1, 0)
          angle = (-earlierDirection).angle - localDirection.angle
          translation = targetMid - ((p + q) * 0.5).rotated(by: angle)
        } else {
          let placedSoFar = world.flatMap { $0 }
          let maxX = placedSoFar.map(\.x).max() ?? 0
          let minY = placedSoFar.map(\.y).min() ?? 0
          let localMinX = local.map(\.x).min() ?? 0
          let localMinY = local.map(\.y).min() ?? 0
          translation = Plan2(maxX + 1000 - localMinX, minY - localMinY)
        }
      }
      world.append(local.map { $0.rotated(by: angle) + translation })
    }
    return world
  }

  // MARK: - Walls

  /// Where the centrelines of the two walls at each corner meet: each wall's inside face moved
  /// outward by half its thickness, intersected with the next. At a square convex corner that
  /// extends both centrelines by half a thickness past the corner; at a re-entrant corner it
  /// shortens them. A corner so sharp that the mitre would run away falls back to the offset
  /// point itself.
  private func mitrePoints(_ corners: [Plan2], thickness: [Double]) -> [Plan2] {
    let n = corners.count
    return (0..<n).map { corner in
      let previous = (corner + n - 1) % n
      let next = (corner + 1) % n
      let incoming = (corners[corner] - corners[previous]).normalized ?? Plan2(1, 0)
      let outgoing = (corners[next] - corners[corner]).normalized ?? Plan2(1, 0)
      let p1 = corners[previous] + incoming.rightNormal * (thickness[previous] / 2)
      let p2 = corners[corner] + outgoing.rightNormal * (thickness[corner] / 2)
      guard let meet = Plan2.intersection(p1, incoming, p2, outgoing) else { return p2 }
      let along = (meet - p2).dot(outgoing)
      let limit = 2 * max(thickness[previous], thickness[corner])
      return abs(along) <= limit ? meet : p2
    }
  }

  // MARK: - Openings

  /// The openings of one wall placed along its centreline (spec F14 1.3 and 1.5). Distances are
  /// measured from a corner along the inside face; the centreline starts `startExtension`
  /// before the start corner, so that is added to every offset.
  private func placeOpenings(
    _ openings: [SketchMeasurements.Opening], room: Room, wall: SketchMeasurements.Wall,
    insideLength: Double, startExtension: Double, ceilingMm: Double,
    notes: inout [SketchSolveNote]
  ) -> [(SketchOpeningKind, CaptureModel.WallOpening)] {
    let byOrder = openings.filter { $0.fromCornerDistance == nil }
    var result: [(SketchOpeningKind, CaptureModel.WallOpening)] = []
    for opening in openings {
      func note(_ field: SketchSolveNote.OpeningField, _ message: String) {
        notes.append(
          SketchSolveNote(
            kind: .openingEstimated(openingId: opening.id, field: field),
            message: "\(room.label): \(opening.id) \(message)"))
      }

      var width: Double
      if let entered = opening.width, entered.valueMm > 0 {
        width = entered.valueMm
        if !entered.measured { note(.width, "width is an \"about\" value, not measured.") }
      } else {
        width = defaultWidth(opening.kind)
        note(.width, "width not measured; \(Int(width)) mm assumed.")
      }
      if insideLength > 0 { width = min(width, insideLength) }

      var bottom = 0.0
      if opening.kind == .window {
        if let sill = opening.sill, sill.valueMm >= 0 {
          bottom = sill.valueMm
          if !sill.measured { note(.sill, "sill height is an \"about\" value, not measured.") }
        } else {
          bottom = SketchDefaults.windowSillMm
          note(.sill, "sill height not measured; \(Int(bottom)) mm assumed.")
        }
      }
      bottom = min(bottom, max(0, ceilingMm - 1))

      var height: Double
      if let entered = opening.height, entered.valueMm > 0 {
        height = entered.valueMm
        if !entered.measured { note(.height, "height is an \"about\" value, not measured.") }
      } else {
        height = opening.kind == .opening ? ceilingMm : defaultHeight(opening.kind)
        note(.height, "height not measured; \(Int(height)) mm assumed.")
      }
      height = max(1, min(height, ceilingMm - bottom))

      var centre: Double
      var positionMeasured = false
      if let distance = opening.fromCornerDistance {
        centre =
          opening.fromCorner == .start
          ? distance.valueMm + width / 2 : insideLength - distance.valueMm - width / 2
        positionMeasured = distance.measured
        if !distance.measured { note(.position, "position is an \"about\" value, not measured.") }
      } else {
        let index = byOrder.firstIndex(where: { $0.id == opening.id }) ?? 0
        centre = insideLength * Double(index + 1) / Double(byOrder.count + 1)
        note(.position, "position not measured; placed by order along \(wall.id).")
      }
      if insideLength >= width {
        centre = min(max(centre, width / 2), insideLength - width / 2)
      } else {
        centre = insideLength / 2
      }

      let confidence: DetectionConfidence =
        (opening.width?.measured == true && positionMeasured) ? .high : .low
      result.append(
        (
          opening.kind,
          CaptureModel.WallOpening(
            id: opening.id, wallId: wall.id, offsetM: metres(startExtension + centre),
            bottomM: metres(bottom), widthM: metres(width), heightM: metres(height),
            confidence: confidence)
        ))
    }
    return result
  }

  private func defaultWidth(_ kind: SketchOpeningKind) -> Double {
    switch kind {
    case .door: return SketchDefaults.doorWidthMm
    case .window: return SketchDefaults.windowWidthMm
    case .opening: return SketchDefaults.openingWidthMm
    }
  }

  private func defaultHeight(_ kind: SketchOpeningKind) -> Double {
    switch kind {
    case .door: return SketchDefaults.doorHeightMm
    case .window: return SketchDefaults.windowHeightMm
    case .opening: return SketchDefaults.doorHeightMm
    }
  }
}
