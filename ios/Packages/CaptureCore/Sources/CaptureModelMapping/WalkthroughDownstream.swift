import CaptureContract

/// Walls, openings, objects and heights of a split walk-through (section 13 of the phase 3 spec).
struct WalkthroughDownstream {
  let plan: WalkthroughInput.Plan
  /// Room rings in room order, counter-clockwise in the plan.
  let rooms: [[P2]]
  let parameters: WalkthroughSplitter.Parameters

  /// Indexes of the rooms that contain `p`.
  func rooms(at p: P2) -> [Int] {
    rooms.indices.filter { Plan2D.contains(rooms[$0], p) }
  }

  /// The nearest room to `p` (ties to the lower index).
  func nearestRoom(_ p: P2) -> Int {
    var best: (distance: Double, room: Int)?
    for r in rooms.indices {
      let d = Plan2D.polyDist(rooms[r], p)
      if best == nil || d < best!.distance { best = (d, r) }
    }
    return best?.room ?? 0
  }

  /// Every source wall, in document order, split where room edges cross it or room corners touch
  /// it. Each piece lists the rooms on either side of it; neighbouring pieces with the same rooms
  /// are merged and pieces shorter than `minWallPiece` fold into their longer neighbour.
  func wallPieces() -> [WalkthroughSplitter.Split.WallPiece] {
    let p = parameters
    var pieces: [WalkthroughSplitter.Split.WallPiece] = []
    for wall in plan.walls {
      let a = wall.a
      let b = wall.b
      let length = Plan2D.dist(a, b)
      guard let d = Plan2D.unit(b - a) else {
        pieces.append(piece(wall, 0, 1, rooms: [nearestRoom(a)]))
        continue
      }
      let normal = P2(-d.y, d.x)
      var ts = [0.0, 1.0]
      for ring in rooms {
        let n = ring.count
        for i in 0..<n {
          let q0 = ring[i]
          let q1 = ring[(i + 1) % n]
          if let x = Plan2D.segSeg(a, b, q0, q1), 1e-9 < x.t, x.t < 1 - 1e-9, -1e-9 <= x.u,
            x.u <= 1 + 1e-9, let e = Plan2D.unit(q1 - q0), abs(Plan2D.cross(d, e)) > p.junctionSin
          {
            ts.append(x.t)
          }
          let (dd, t) = Plan2D.segPoint(q0, a, b)
          if dd <= p.junctionNear, 1e-9 < t, t < 1 - 1e-9 { ts.append(t) }
        }
      }
      ts.sort()
      var unique: [Double] = []
      for t in ts where unique.last != t { unique.append(t) }
      var spans: [(t0: Double, t1: Double, rooms: [Int])] = []
      for k in unique.indices.dropFirst() {
        let t0 = unique[k - 1]
        let t1 = unique[k]
        if (t1 - t0) * length < 1e-6 { continue }
        let m = a + (b - a) * ((t0 + t1) / 2)
        var ids = Set(rooms(at: m + normal * p.side)).union(rooms(at: m + normal * -p.side))
          .sorted()
        if ids.isEmpty { ids = [nearestRoom(m)] }
        spans.append((t0, t1, ids))
      }
      if spans.isEmpty { spans = [(0, 1, [nearestRoom(Plan2D.lerp(a, b, 0.5))])] }
      var merged = Self.mergeEqual(spans)
      while merged.count > 1 {
        let short = merged.indices.filter {
          (merged[$0].t1 - merged[$0].t0) * length < p.minWallPiece
        }
        guard
          let i = short.min(by: {
            (merged[$0].t1 - merged[$0].t0, $0) < (merged[$1].t1 - merged[$1].t0, $1)
          })
        else { break }
        let neighbours = [i - 1, i + 1].filter { merged.indices.contains($0) }
        let j = neighbours.max {
          (merged[$0].t1 - merged[$0].t0, -$0) < (merged[$1].t1 - merged[$1].t0, -$1)
        }!
        let lo = min(i, j)
        let hi = max(i, j)
        merged.replaceSubrange(lo...hi, with: [(merged[lo].t0, merged[hi].t1, merged[j].rooms)])
        merged = Self.mergeEqual(merged)
      }
      for span in merged { pieces.append(piece(wall, span.t0, span.t1, rooms: span.rooms)) }
    }
    return pieces
  }

  private static func mergeEqual(_ spans: [(t0: Double, t1: Double, rooms: [Int])])
    -> [(t0: Double, t1: Double, rooms: [Int])]
  {
    var merged: [(t0: Double, t1: Double, rooms: [Int])] = []
    for span in spans {
      if let last = merged.last, last.rooms == span.rooms {
        merged[merged.count - 1].t1 = span.t1
      } else {
        merged.append(span)
      }
    }
    return merged
  }

  private func piece(_ wall: WalkthroughInput.Wall, _ t0: Double, _ t1: Double, rooms: [Int])
    -> WalkthroughSplitter.Split.WallPiece
  {
    let length = Plan2D.dist(wall.a, wall.b)
    // The wall's own ends stay exact.
    let start = t0 == 0 ? wall.a : Plan2D.lerp(wall.a, wall.b, t0)
    let end = t1 == 1 ? wall.b : Plan2D.lerp(wall.a, wall.b, t1)
    return WalkthroughSplitter.Split.WallPiece(
      sourceWall: wall.index, startM: t0 * length, endM: t1 * length,
      start: Vector3(start.x, wall.baseY, start.y), end: Vector3(end.x, wall.baseY, end.y),
      rooms: rooms)
  }

  /// The wall piece of a door, window or opening: its parent wall as the mapper finds it
  /// (`OpeningAssignment`), then the piece of that wall under the opening centre. Nil when no
  /// wall qualifies.
  func place(
    _ surface: RoomPlanSurface, placements: [WallPlacement],
    pieces: [WalkthroughSplitter.Split.WallPiece],
    diagnostics: inout WalkthroughSplitter.Diagnostics
  ) -> WalkthroughSplitter.Split.OpeningPlacement? {
    guard let parent = OpeningAssignment.assign(surface, roomIndex: 0, walls: placements),
      let wallIndex = placements.firstIndex(where: { $0.id == parent.wall.id })
    else { return nil }
    let along = OpeningAssignment.offsetM(of: surface, on: parent.wall)
    let candidates = pieces.indices.filter { pieces[$0].sourceWall == wallIndex }
    guard let firstPiece = candidates.first, let lastPiece = candidates.last else { return nil }
    let index =
      candidates.first { pieces[$0].startM - 1e-9 <= along && along <= pieces[$0].endM + 1e-9 }
      ?? (along > pieces[lastPiece].endM ? lastPiece : firstPiece)
    let piece = pieces[index]
    let halfWidth = surface.dimension(0) / 2
    if candidates.count > 1, along - halfWidth > 0, along + halfWidth < pieces[lastPiece].endM,
      along - halfWidth < piece.startM - 0.01 || along + halfWidth > piece.endM + 0.01
    {
      diagnostics.straddlingOpenings.append(surface.identifier)
    }
    return .init(piece: index, offsetM: max(0, along - piece.startM))
  }

  /// The room of each object: the first room that contains its centre, else the room its
  /// footprint overlaps most, else the nearest room. An object on or in another object (a sink in
  /// a cabinet) takes the room of the object at the root of its parent chain (followed for at most
  /// 16 steps, and up to a parent that is not in the capture); in a cycle of parents each object
  /// keeps its own room.
  func objectRooms() -> [Int] {
    var own: [Int] = []
    for object in plan.objects {
      if let r = rooms(at: object.center).first {
        own.append(r)
        continue
      }
      let footprint = object.footprint
      var best: (overlap: Double, room: Int)?
      for r in rooms.indices {
        let clipped = Plan2D.clipConvex(rooms[r], footprint)
        let overlap = clipped.count >= 3 ? abs(Plan2D.area(clipped)) : 0
        if overlap > 1e-6, best == nil || overlap > best!.overlap { best = (overlap, r) }
      }
      own.append(best?.room ?? nearestRoom(object.center))
    }
    var indexOf: [String: Int] = [:]
    for object in plan.objects where indexOf[object.identifier] == nil {
      indexOf[object.identifier] = object.index
    }
    return plan.objects.map { object in
      var current = object.index
      var visited = [current]
      for _ in 0..<16 {
        guard let parentIdentifier = plan.objects[current].parentIdentifier,
          let parent = indexOf[parentIdentifier]
        else { break }
        if visited.contains(parent) { return own[object.index] }
        visited.append(parent)
        current = parent
      }
      return own[current]
    }
  }

  /// Per room: the tallest piece longer than 5 cm that bounds it, when within the height range;
  /// otherwise the scan's length-weighted median wall height, clamped to the range.
  func heights(pieces: [WalkthroughSplitter.Split.WallPiece]) -> [(
    heightM: Double, fromWalls: Bool
  )] {
    let p = parameters
    let walls = plan.walls.sorted { ($0.heightM, $0.index) < ($1.heightM, $1.index) }
    var total = 0.0
    for wall in walls { total += Plan2D.dist(wall.a, wall.b) }
    var median = p.heightDefault
    var accumulated = 0.0
    for wall in walls {
      accumulated += Plan2D.dist(wall.a, wall.b)
      if accumulated >= total / 2 {
        median = wall.heightM
        break
      }
    }
    let fallback = walls.isEmpty ? p.heightDefault : min(p.heightMax, max(p.heightMin, median))
    return rooms.indices.map { r in
      var tallest: Double?
      for piece in pieces where piece.rooms.contains(r) && piece.endM - piece.startM > 0.05 {
        let height = plan.walls[piece.sourceWall].heightM
        tallest = max(tallest ?? height, height)
      }
      if let tallest, p.heightMin <= tallest, tallest <= p.heightMax { return (tallest, true) }
      return (fallback, false)
    }
  }
}

extension CaptureModelMapper {
  /// The capture model of a walk-through split into rooms, or nil when `document` is not a
  /// walk-through or the split fails (the caller then maps it as one room).
  ///
  /// Pass 1 is the same as for every capture, with the same errors in the same order: walls
  /// (`wallHasNoLength`), then each door, window and opening's wall (`openingHasNoWall`).
  static func mapWalkthrough(_ document: RoomPlanDocument, context: MappingContext) throws
    -> CaptureModel?
  {
    guard WalkthroughInput.isWalkthrough(document) else { return nil }
    let room = document.rooms[0]
    var placements: [WallPlacement] = []
    for (index, surface) in room.walls.enumerated() {
      placements.append(try wallPlacement(surface, id: "wall-\(index + 1)", roomIndex: 0))
    }
    for surface in room.doors + room.windows + room.openings
    where OpeningAssignment.assign(surface, roomIndex: 0, walls: placements) == nil {
      throw MappingError.openingHasNoWall(surface: surface.identifier)
    }
    guard let split = WalkthroughSplitter.split(document: document, placements: placements) else {
      return nil
    }

    var model = CaptureModel(
      visitId: context.visitId, captureId: context.captureId, areaKey: context.areaKey,
      label: context.label, refs: context.refs)
    let labels = RoomTyping.labels(
      for: split.rooms.map(\.typing), captureLabel: context.label, overrides: context.roomLabels)
    for (index, splitRoom) in split.rooms.enumerated() {
      model.rooms.append(
        CaptureModel.Room(
          id: "room-\(index + 1)", label: labels[index],
          polygon: splitRoom.polygon.map(\.contractVec3), heightM: splitRoom.heightM.cleaned,
          type: splitRoom.typing.type, typeSource: splitRoom.typing.source))
    }
    for (index, piece) in split.wallPieces.enumerated() {
      let surface = room.walls[piece.sourceWall]
      model.walls.append(
        CaptureModel.Wall(
          id: "wall-\(index + 1)", start: piece.start.contractVec3, end: piece.end.contractVec3,
          heightM: placements[piece.sourceWall].heightM.cleaned,
          thicknessM: max(0, surface.dimension(2)).cleaned,
          roomIds: piece.rooms.map { "room-\($0 + 1)" }, confidence: surface.confidence))
    }

    for (surfaces, placed, kind) in [
      (room.doors, split.doors, "door"), (room.windows, split.windows, "window"),
      (room.openings, split.openings, "opening"),
    ] {
      for (index, surface) in surfaces.enumerated() {
        let placement = placed[index]
        let piece = split.wallPieces[placement.piece]
        let opening = CaptureModel.WallOpening(
          id: "\(kind)-\(index + 1)", wallId: "wall-\(placement.piece + 1)",
          offsetM: placement.offsetM.cleaned,
          bottomM: max(
            0,
            surface.transform.translation.y - surface.dimension(1) / 2
              - placements[piece.sourceWall].baseY
          ).cleaned,
          widthM: surface.dimension(0).cleaned, heightM: surface.dimension(1).cleaned,
          confidence: surface.confidence, isOpen: kind == "door" ? surface.category.isOpen : nil)
        switch kind {
        case "door": model.doors.append(opening)
        case "window": model.windows.append(opening)
        default: model.openings.append(opening)
        }
      }
    }

    var objectIdByIdentifier: [String: String] = [:]
    for (index, object) in room.objects.enumerated()
    where objectIdByIdentifier[object.identifier] == nil {
      objectIdByIdentifier[object.identifier] = "object-\(index + 1)"
    }
    for (index, object) in room.objects.enumerated() {
      let id = "object-\(index + 1)"
      let parentId = object.parentIdentifier.flatMap { objectIdByIdentifier[$0] }
      // The schema takes attribute values of 1 to 100 characters; others are left out.
      let attributes = object.attributes.filter {
        !$0.value.isEmpty && $0.value.unicodeScalars.count <= 100
      }
      model.objects.append(
        CaptureModel.DetectedObject(
          id: id, category: object.category.objectCategory,
          roomId: "room-\(split.objectRooms[index] + 1)",
          box: CaptureModel.OrientedBox(
            center: object.transform.translation.contractVec3,
            sizeM: Vector3(
              object.dimensions.count > 0 ? object.dimensions[0] : 0,
              object.dimensions.count > 1 ? object.dimensions[1] : 0,
              object.dimensions.count > 2 ? object.dimensions[2] : 0
            ).contractVec3,
            rotation: object.transform.rotation),
          confidence: object.confidence, attributes: attributes.isEmpty ? nil : attributes,
          parentId: parentId == id ? nil : parentId))
    }
    return model
  }
}
