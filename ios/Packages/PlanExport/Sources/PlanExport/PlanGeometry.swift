import CaptureContract
import Foundation

/// A point in plan coordinates, metres. Plan x is the model's x and plan y is the model's -z, so
/// the plan reads the right way round when seen from above (+Y up) with plan y pointing up the sheet.
struct Point2: Hashable, Sendable {
  var x: Double
  var y: Double

  static func + (a: Point2, b: Point2) -> Point2 { Point2(x: a.x + b.x, y: a.y + b.y) }
  static func - (a: Point2, b: Point2) -> Point2 { Point2(x: a.x - b.x, y: a.y - b.y) }
  static func * (a: Point2, k: Double) -> Point2 { Point2(x: a.x * k, y: a.y * k) }

  var length: Double { (x * x + y * y).squareRoot() }

  func distance(to other: Point2) -> Double { (self - other).length }

  var unit: Point2 {
    let l = length
    return l > 0 ? Point2(x: x / l, y: y / l) : Point2(x: 1, y: 0)
  }

  /// Left-hand normal (90 degrees counter-clockwise).
  var leftNormal: Point2 { Point2(x: -y, y: x) }

  func dot(_ other: Point2) -> Double { x * other.x + y * other.y }

  init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  init(_ v: Vec3) {
    self.init(x: v.x, y: -v.z)
  }
}

struct PlanBounds: Hashable, Sendable {
  var minX: Double
  var minY: Double
  var maxX: Double
  var maxY: Double

  var width: Double { maxX - minX }
  var height: Double { maxY - minY }

  mutating func grow(_ point: Point2) {
    minX = Swift.min(minX, point.x)
    minY = Swift.min(minY, point.y)
    maxX = Swift.max(maxX, point.x)
    maxY = Swift.max(maxY, point.y)
  }
}

enum OpeningKind: String, Sendable {
  case door
  case window
  case opening
}

struct PlanWall: Sendable {
  var id: String
  var start: Point2
  var end: Point2
  var thickness: Double
  /// Rooms this wall bounds, merged over coincident walls (a shared partition bounds both rooms).
  var roomIds: [String]
  var length: Double { start.distance(to: end) }
}

struct PlanOpening: Sendable {
  var id: String
  var kind: OpeningKind
  var wallId: String
  /// Ends of the opening along its wall.
  var from: Point2
  var to: Point2
  var widthM: Double
  var heightM: Double
  var bottomM: Double
  var roomIds: [String]
  var wallThickness: Double
}

struct PlanRoom: Sendable {
  var id: String
  var label: String
  var polygon: [Point2]
  /// Extent along the room's X-most principal axis (bounding box for axis-aligned rooms).
  var widthM: Double
  var lengthM: Double
  var heightM: Double
  var areaM2: Double
  var perimeterM: Double
  /// A point inside the room for its label.
  var labelPoint: Point2
  var doorCount: Int
  var windowCount: Int
  var openingCount: Int
}

struct PlanObject: Sendable {
  var id: String
  var category: ObjectCategory
  var roomId: String?
  /// Footprint corners in order.
  var corners: [Point2]
  var center: Point2
  /// Box size along its local axes, metres (x, y = height, z).
  var sizeM: Vec3
  var confidence: DetectionConfidence?
}

/// Plan view of a `CaptureModel`: deduplicated walls, opening spans, room measurements and
/// object footprints, all in plan coordinates (metres). Shared by every writer.
struct PlanGeometry: Sendable {
  var walls: [PlanWall]
  var openings: [PlanOpening]
  var rooms: [PlanRoom]
  var objects: [PlanObject]
  /// Nil when there is nothing to draw.
  var bounds: PlanBounds?

  /// Walls closer than this at both ends are the same wall (a partition listed once per room).
  static let coincidenceTolerance = 0.002
  /// Opening with no room ids on its wall belongs to a room whose outline is this close.
  static let roomAttachDistance = 0.15

  init(model: CaptureModel) throws {
    func check(_ value: Double, _ what: String) throws {
      guard value.isFinite else {
        throw PlanExportError.invalidGeometry("\(what) is not a finite number")
      }
    }
    func check(_ v: Vec3, _ what: String) throws {
      try check(v.x, what)
      try check(v.y, what)
      try check(v.z, what)
    }

    // Walls, with coincident walls merged.
    var walls: [PlanWall] = []
    var wallIndexById: [String: Int] = [:]
    for wall in model.walls {
      try check(wall.start, "wall \(wall.id) start")
      try check(wall.end, "wall \(wall.id) end")
      try check(wall.thicknessM, "wall \(wall.id) thickness")
      let start = Point2(wall.start)
      let end = Point2(wall.end)
      let tolerance = PlanGeometry.coincidenceTolerance
      let match = walls.firstIndex { other in
        (other.start.distance(to: start) <= tolerance && other.end.distance(to: end) <= tolerance)
          || (other.start.distance(to: end) <= tolerance
            && other.end.distance(to: start) <= tolerance)
      }
      if let index = match {
        for id in wall.roomIds ?? [] where !walls[index].roomIds.contains(id) {
          walls[index].roomIds.append(id)
        }
        walls[index].thickness = max(walls[index].thickness, wall.thicknessM)
        wallIndexById[wall.id] = index
      } else {
        walls.append(
          PlanWall(
            id: wall.id, start: start, end: end, thickness: max(0, wall.thicknessM),
            roomIds: wall.roomIds ?? []))
        wallIndexById[wall.id] = walls.count - 1
      }
    }

    // Rooms.
    var rooms: [PlanRoom] = []
    for room in model.rooms {
      guard room.polygon.count >= 3 else {
        throw PlanExportError.invalidGeometry("room \(room.id) has fewer than 3 outline points")
      }
      for point in room.polygon { try check(point, "room \(room.id) outline") }
      try check(room.heightM, "room \(room.id) height")
      let polygon = room.polygon.map(Point2.init)
      let (width, length) = PlanGeometry.extents(of: polygon)
      rooms.append(
        PlanRoom(
          id: room.id, label: room.label, polygon: polygon, widthM: width, lengthM: length,
          heightM: room.heightM, areaM2: PlanGeometry.area(of: polygon),
          perimeterM: PlanGeometry.perimeter(of: polygon),
          labelPoint: PlanGeometry.labelPoint(of: polygon), doorCount: 0, windowCount: 0,
          openingCount: 0))
    }

    // Openings.
    var openings: [PlanOpening] = []
    func place(_ list: [CaptureModel.WallOpening], kind: OpeningKind) throws {
      for item in list {
        try check(item.offsetM, "\(item.id) offset")
        try check(item.widthM, "\(item.id) width")
        try check(item.heightM, "\(item.id) height")
        try check(item.bottomM, "\(item.id) bottom")
        guard let index = wallIndexById[item.wallId] else {
          throw PlanExportError.unknownWall(openingId: item.id, wallId: item.wallId)
        }
        let wall = walls[index]
        guard wall.length > 0 else { continue }
        // Use the wall as written for this opening so its offset runs from the right end.
        let source = model.walls.first { $0.id == item.wallId }
        let wallStart = source.map { Point2($0.start) } ?? wall.start
        let wallEnd = source.map { Point2($0.end) } ?? wall.end
        let direction = (wallEnd - wallStart).unit
        let from = wallStart + direction * (item.offsetM - item.widthM / 2)
        let to = wallStart + direction * (item.offsetM + item.widthM / 2)
        let tolerance = PlanGeometry.coincidenceTolerance
        let duplicate = openings.contains { other in
          other.kind == kind
            && ((other.from.distance(to: from) <= tolerance
              && other.to.distance(to: to) <= tolerance)
              || (other.from.distance(to: to) <= tolerance
                && other.to.distance(to: from) <= tolerance))
        }
        if duplicate { continue }
        var roomIds = wall.roomIds
        if roomIds.isEmpty {
          let middle = (from + to) * 0.5
          roomIds = rooms.filter {
            PlanGeometry.distanceToBoundary(of: $0.polygon, from: middle)
              <= PlanGeometry.roomAttachDistance
          }.map(\.id)
        }
        openings.append(
          PlanOpening(
            id: item.id, kind: kind, wallId: item.wallId, from: from, to: to,
            widthM: item.widthM, heightM: item.heightM, bottomM: item.bottomM, roomIds: roomIds,
            wallThickness: wall.thickness))
      }
    }
    try place(model.doors, kind: .door)
    try place(model.windows, kind: .window)
    try place(model.openings, kind: .opening)

    for index in rooms.indices {
      let id = rooms[index].id
      let here = openings.filter { $0.roomIds.contains(id) }
      rooms[index].doorCount = here.filter { $0.kind == .door }.count
      rooms[index].windowCount = here.filter { $0.kind == .window }.count
      rooms[index].openingCount = here.filter { $0.kind == .opening }.count
    }

    // Objects.
    var objects: [PlanObject] = []
    for object in model.objects {
      try check(object.box.center, "object \(object.id) centre")
      try check(object.box.sizeM, "object \(object.id) size")
      let box = object.box
      let q = box.rotation
      let norm = (q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w).squareRoot()
      let r = norm > 1e-9 ? Quaternion(x: q.x / norm, y: q.y / norm, z: q.z / norm, w: q.w / norm) : .identity
      func rotate(_ v: Vec3) -> Vec3 {
        // v' = v + 2 * cross(u, cross(u, v) + w * v), u = (x, y, z)
        let cx = r.y * v.z - r.z * v.y + r.w * v.x
        let cy = r.z * v.x - r.x * v.z + r.w * v.y
        let cz = r.x * v.y - r.y * v.x + r.w * v.z
        return Vec3(
          x: v.x + 2 * (r.y * cz - r.z * cy),
          y: v.y + 2 * (r.z * cx - r.x * cz),
          z: v.z + 2 * (r.x * cy - r.y * cx))
      }
      let hx = box.sizeM.x / 2
      let hz = box.sizeM.z / 2
      let corners = [(-1.0, -1.0), (-1.0, 1.0), (1.0, 1.0), (1.0, -1.0)].map { sx, sz -> Point2 in
        let local = rotate(Vec3(x: sx * hx, y: 0, z: sz * hz))
        return Point2(Vec3(x: box.center.x + local.x, y: 0, z: box.center.z + local.z))
      }
      let center = Point2(box.center)
      let roomId =
        object.roomId ?? rooms.first { PlanGeometry.contains($0.polygon, center) }?.id
      objects.append(
        PlanObject(
          id: object.id, category: object.category, roomId: roomId, corners: corners,
          center: center, sizeM: box.sizeM, confidence: object.confidence))
    }

    var bounds: PlanBounds?
    func grow(_ point: Point2) {
      if bounds == nil {
        bounds = PlanBounds(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y)
      } else {
        bounds?.grow(point)
      }
    }
    walls.forEach {
      grow($0.start)
      grow($0.end)
    }
    rooms.forEach { $0.polygon.forEach(grow) }
    objects.forEach { $0.corners.forEach(grow) }

    self.walls = walls
    self.openings = openings
    self.rooms = rooms
    self.objects = objects
    self.bounds = bounds
  }

  // MARK: Polygon maths

  /// Absolute shoelace area.
  static func area(of polygon: [Point2]) -> Double {
    var sum = 0.0
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      sum += a.x * b.y - b.x * a.y
    }
    return abs(sum) / 2
  }

  static func perimeter(of polygon: [Point2]) -> Double {
    var sum = 0.0
    for index in polygon.indices {
      sum += polygon[index].distance(to: polygon[(index + 1) % polygon.count])
    }
    return sum
  }

  /// Room width and length. For an outline whose edges all run along the plan axes this is the
  /// bounding box (x extent, then y extent). A rotated outline is measured along its longest
  /// edge and the edge normal, with width being the one closer to the plan x axis.
  static func extents(of polygon: [Point2]) -> (Double, Double) {
    var axisAligned = true
    var longest = (length: 0.0, direction: Point2(x: 1, y: 0))
    for index in polygon.indices {
      let edge = polygon[(index + 1) % polygon.count] - polygon[index]
      let length = edge.length
      guard length > 1e-9 else { continue }
      if abs(edge.x) > 0.0087 * length && abs(edge.y) > 0.0087 * length { axisAligned = false }
      if length > longest.length { longest = (length, edge.unit) }
    }
    func spread(along axis: Point2) -> Double {
      let projections = polygon.map { $0.dot(axis) }
      return (projections.max() ?? 0) - (projections.min() ?? 0)
    }
    if axisAligned {
      return (spread(along: Point2(x: 1, y: 0)), spread(along: Point2(x: 0, y: 1)))
    }
    let u = longest.direction
    let v = u.leftNormal
    let along = spread(along: u)
    let across = spread(along: v)
    return abs(u.x) >= abs(v.x) ? (along, across) : (across, along)
  }

  /// Ray casting, even-odd.
  static func contains(_ polygon: [Point2], _ point: Point2) -> Bool {
    var inside = false
    var previous = polygon.count - 1
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[previous]
      if (a.y > point.y) != (b.y > point.y),
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
      {
        inside.toggle()
      }
      previous = index
    }
    return inside
  }

  static func distanceToBoundary(of polygon: [Point2], from point: Point2) -> Double {
    var best = Double.infinity
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      let ab = b - a
      let lengthSquared = ab.dot(ab)
      let t = lengthSquared > 0 ? max(0, min(1, (point - a).dot(ab) / lengthSquared)) : 0
      best = min(best, point.distance(to: a + ab * t))
    }
    return best
  }

  /// Area centroid when it lies inside the outline, otherwise the middle of the longest inside
  /// stretch of the horizontal line through the centroid.
  static func labelPoint(of polygon: [Point2]) -> Point2 {
    var twiceArea = 0.0
    var cx = 0.0
    var cy = 0.0
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      let cross = a.x * b.y - b.x * a.y
      twiceArea += cross
      cx += (a.x + b.x) * cross
      cy += (a.y + b.y) * cross
    }
    let mean = Point2(
      x: polygon.map(\.x).reduce(0, +) / Double(polygon.count),
      y: polygon.map(\.y).reduce(0, +) / Double(polygon.count))
    guard abs(twiceArea) > 1e-12 else { return mean }
    let centroid = Point2(x: cx / (3 * twiceArea), y: cy / (3 * twiceArea))
    if contains(polygon, centroid) { return centroid }
    var crossings: [Double] = []
    for index in polygon.indices {
      let a = polygon[index]
      let b = polygon[(index + 1) % polygon.count]
      if (a.y > centroid.y) != (b.y > centroid.y) {
        crossings.append(a.x + (centroid.y - a.y) / (b.y - a.y) * (b.x - a.x))
      }
    }
    crossings.sort()
    var best: (Double, Double)?
    var index = 0
    while index + 1 < crossings.count {
      let span = (crossings[index], crossings[index + 1])
      if best == nil || span.1 - span.0 > best!.1 - best!.0 { best = span }
      index += 2
    }
    if let best { return Point2(x: (best.0 + best.1) / 2, y: centroid.y) }
    return mean
  }
}
