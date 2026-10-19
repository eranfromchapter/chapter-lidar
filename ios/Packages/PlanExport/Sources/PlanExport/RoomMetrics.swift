import CaptureContract
import Foundation

/// Assumptions of the measurement engine that a person may want to change.
public struct MeasurementSettings: Hashable, Sendable {
  /// Width of door and window casing (trim), metres. Default 1 9/16 in.
  public var casingWidthM: Double
  /// Assumed thickness of the exterior walls, metres, for the exterior floor area estimate.
  /// RoomPlan does not measure wall thickness. Default 6 in.
  public var exteriorWallThicknessM: Double

  public static let defaultCasingWidthM = 1.5625 * UnitFormatter.metresPerInch
  public static let defaultExteriorWallThicknessM = 6 * UnitFormatter.metresPerInch

  public init(
    casingWidthM: Double = MeasurementSettings.defaultCasingWidthM,
    exteriorWallThicknessM: Double = MeasurementSettings.defaultExteriorWallThicknessM
  ) {
    self.casingWidthM = casingWidthM
    self.exteriorWallThicknessM = exteriorWallThicknessM
  }
}

/// Kind of a door, window or opening (a passage without a door).
public enum OpeningType: String, CaseIterable, Hashable, Sendable {
  case door
  case window
  case opening

  init(_ kind: OpeningKind) {
    switch kind {
    case .door: self = .door
    case .window: self = .window
    case .opening: self = .opening
    }
  }
}

/// A door, window or opening in one of a room's walled edges.
public struct OpeningMetrics: Hashable, Sendable {
  public var id: String
  public var type: OpeningType
  public var widthM: Double
  public var heightM: Double
  /// Height of the bottom above the wall base (0 for doors), metres.
  public var bottomM: Double
  /// Doors only: whether the door stood open during the scan.
  public var isOpen: Bool?
  /// Width x height, square metres.
  public var areaM2: Double
  /// Length of casing (trim) around one face of the opening, metres, with casing width c:
  /// a window 2(w + h) + 8c (four sides, mitred corners); a door or opening 2h + w + 4c (two
  /// sides and the head, no casing on the floor).
  public var casingLengthM: Double

  /// Casing length of a window `widthM` x `heightM` with casing `casingWidthM` wide.
  public static func windowCasingLength(widthM: Double, heightM: Double, casingWidthM: Double)
    -> Double
  {
    2 * (widthM + heightM) + 8 * casingWidthM
  }

  /// Casing length of a door or opening `widthM` x `heightM` with casing `casingWidthM` wide.
  public static func doorCasingLength(widthM: Double, heightM: Double, casingWidthM: Double)
    -> Double
  {
    2 * heightM + widthM + 4 * casingWidthM
  }
}

/// How a recognized object is listed in a room schedule.
public enum ObjectGroup: String, CaseIterable, Hashable, Sendable {
  /// Bed, sofa, chair, table, and storage that RoomPlan reports as a shelf.
  case furniture
  /// Built in: storage that RoomPlan reports as a cabinet (or does not type), sink, toilet,
  /// bathtub.
  case fixtures
  /// Refrigerator, oven, stove, dishwasher, washer-dryer, television.
  case appliances
  /// Everything else: fireplace, stairs, other.
  case other

  /// The group of an object of `category` with RoomPlan `attributes`.
  public static func of(_ category: ObjectCategory, attributes: [String: String]?) -> ObjectGroup {
    switch category {
    case .bed, .sofa, .chair, .table: return .furniture
    case .storage: return attributes?["StorageType"] == "shelf" ? .furniture : .fixtures
    case .sink, .toilet, .bathtub: return .fixtures
    case .refrigerator, .oven, .stove, .dishwasher, .washerDryer, .television: return .appliances
    case .fireplace, .stairs, .other: return .other
    }
  }
}

/// A recognized object in a room, with its box size.
public struct ObjectMetrics: Hashable, Sendable {
  public var id: String
  public var category: ObjectCategory
  public var group: ObjectGroup
  /// Name for schedules, for example `Cabinet`, `Shelf` or `Coffee table`.
  public var name: String
  /// Box size along the box's own axes, metres: width (x), height (y), depth (z).
  public var widthM: Double
  public var heightM: Double
  public var depthM: Double
  public var confidence: DetectionConfidence?
  /// The object this one sits on or in, if any.
  public var parentId: String?

  /// Schedule name of an object of `category` with RoomPlan `attributes`. Storage is a cabinet
  /// unless RoomPlan reports a shelf.
  public static func name(of category: ObjectCategory, attributes: [String: String]?) -> String {
    let attributes = attributes ?? [:]
    switch category {
    case .bathtub: return "Bathtub"
    case .bed: return "Bed"
    case .chair:
      switch attributes["ChairType"] {
      case "dining": return "Dining chair"
      case "swivel": return "Swivel chair"
      case "stool": return "Stool"
      default: return "Chair"
      }
    case .dishwasher: return "Dishwasher"
    case .fireplace: return "Fireplace"
    case .oven: return "Oven"
    case .refrigerator: return "Refrigerator"
    case .sink: return "Sink"
    case .sofa:
      switch attributes["SofaType"] {
      case "lShaped": return "L-shaped sofa"
      case "singleSeat": return "Armchair"
      default: return "Sofa"
      }
    case .stairs: return "Stairs"
    case .storage: return attributes["StorageType"] == "shelf" ? "Shelf" : "Cabinet"
    case .stove: return "Stove"
    case .table:
      switch attributes["TableType"] {
      case "coffee": return "Coffee table"
      case "dining": return "Dining table"
      default: return "Table"
      }
    case .television: return "Television"
    case .toilet: return "Toilet"
    case .washerDryer: return "Washer-dryer"
    case .other: return "Other object"
    }
  }
}

/// A room's ceiling height and how sure it is.
public struct CeilingHeight: Hashable, Sendable {
  /// What the height was taken from.
  public enum Basis: String, Hashable, Sendable {
    /// The walls along the room's outline.
    case roomWalls
    /// Every wall of the capture: the room's outline has no walls.
    case captureWalls
    /// The room's own height in the capture model: the capture has no walls at all.
    case roomRecord
  }

  /// Why a height is marked approximate.
  public enum Reason: String, Hashable, Sendable {
    /// Walls whose height differs from the median by more than `RoomMetrics.wallHeightSpreadM`
    /// cover more than `RoomMetrics.maximumOffHeightFraction` of the walled length.
    case wallHeightsDiffer
    /// Walls cover less than `RoomMetrics.minimumWalledFraction` of the outline.
    case fewWalls
    /// No wall runs along the outline.
    case noWalls
  }

  public var heightM: Double
  public var basis: Basis
  /// Empty when the height is not approximate.
  public var approximateReasons: [Reason]

  /// Reports print "(approx)" next to an approximate height and the volume made from it.
  public var isApproximate: Bool { !approximateReasons.isEmpty }
}

/// Measurements of one room of a capture, all in metres, square metres and cubic metres.
///
/// Definitions:
/// - Floor area: area enclosed by the room's floor outline (shoelace formula).
/// - Perimeter: length of the floor outline.
/// - Frame: the room's dominant axis, the direction (modulo 90 degrees) that most of its
///   outline runs along, to within 3 degrees (`MetricsGeometry.dominantAngle`).
/// - Bounding box (B): the smallest rectangle with sides along the frame that contains the
///   outline.
/// - Inscribed rectangle (I): the largest rectangle with sides along the frame that fits inside
///   the outline (`MetricsGeometry.largestInscribedRectangle`). Equal to B for a rectangular
///   room.
/// - Walled edges: the parts of the outline that a wall of the capture runs along: a wall
///   within `wallMatchDistanceM` of the edge and within `wallMatchAngleDegrees` of its
///   direction, clipped to the edge. Where walls overlap, the tallest counts.
/// - Ceiling height: the median wall height along the walled edges, each height weighted by
///   the length it covers. Approximate when walls whose height differs from that median by
///   more than `wallHeightSpreadM` cover more than `maximumOffHeightFraction` of the walled
///   length (so a short wall stub at another height does not count), or when walls cover less
///   than `minimumWalledFraction` of the perimeter. With no walled edge, the same median over
///   every wall of the capture (or, with no walls at all, the room's height in the model),
///   always approximate.
/// - Volume: floor area x ceiling height; approximate with the height.
/// - Wall area including openings: the sum over walled edges of length x wall height.
/// - Wall area excluding openings: that minus width x height of every door, window and opening
///   on a walled edge, never below zero. A door in a wall between two rooms counts for both.
/// - Openings: the doors, windows and openings whose middle lies on a walled edge, in the
///   order of the model (doors, windows, openings).
/// - Objects: the model's objects in this room (the object's room, or the room that contains
///   its centre), grouped by `ObjectGroup`.
/// - Casing: window and door casing lengths (`OpeningMetrics.casingLengthM`) summed over the
///   room's openings; openings without a door are cased like doors.
public struct RoomMetrics: Hashable, Sendable {
  public var roomId: String
  public var label: String
  public var type: RoomType?
  public var floorAreaM2: Double
  public var perimeterM: Double
  /// Direction of the room's dominant axis, radians counter-clockwise from plan +x, in
  /// (-pi/4, pi/4].
  public var frameAngleRadians: Double
  /// B: smallest rectangle along the frame that contains the room.
  public var boundingBox: MeasuredRectangle
  /// I: largest rectangle along the frame that fits inside the room.
  public var inscribed: MeasuredRectangle
  public var ceiling: CeilingHeight
  public var volumeM3: Double
  public var wallAreaIncludingOpeningsM2: Double
  public var wallAreaExcludingOpeningsM2: Double
  /// Length of the outline that has a wall.
  public var walledLengthM: Double
  public var openings: [OpeningMetrics]
  public var objects: [ObjectMetrics]
  /// Casing length of the room's windows.
  public var windowCasingM: Double
  /// Casing length of the room's doors and openings.
  public var doorCasingM: Double

  /// The room's objects in `group`, in model order.
  public func objects(in group: ObjectGroup) -> [ObjectMetrics] {
    objects.filter { $0.group == group }
  }

  /// A wall belongs to an outline edge when it lies within this distance of it, metres, and
  /// runs within `wallMatchAngleDegrees` of its direction.
  public static let wallMatchDistanceM = 0.10
  public static let wallMatchAngleDegrees = 5.0
  /// A wall height further than this from the median is off height, metres.
  public static let wallHeightSpreadM = 0.05
  /// Off-height walls covering more than this fraction of the walled length make the ceiling
  /// height approximate.
  public static let maximumOffHeightFraction = 0.1
  /// Walls covering less than this fraction of the perimeter make the height approximate.
  public static let minimumWalledFraction = 0.5

  /// Measurements of every room of `model`, in model order.
  public static func measure(
    _ model: CaptureModel, settings: MeasurementSettings = MeasurementSettings()
  ) throws -> [RoomMetrics] {
    measure(model, geometry: try PlanGeometry(model: model), settings: settings)
  }

  static func measure(
    _ model: CaptureModel, geometry: PlanGeometry, settings: MeasurementSettings
  ) -> [RoomMetrics] {
    let walls = model.walls.map {
      WallLine(start: Point2($0.start), end: Point2($0.end), heightM: max(0, $0.heightM))
    }
    let captureMedian = weightedMedian(walls.map { ($0.heightM, $0.start.distance(to: $0.end)) })
    let isOpenById = Dictionary(
      model.doors.map { ($0.id, $0.isOpen) }, uniquingKeysWith: { first, _ in first })
    let sourceObjects = Dictionary(
      model.objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    return geometry.rooms.enumerated().map { index, room in
      let source = index < model.rooms.count ? model.rooms[index] : nil
      let polygon = room.polygon
      let frame = MetricsGeometry.Frame(angle: MetricsGeometry.dominantAngle(of: [polygon]))
      let local = polygon.map(frame.local)
      let box = MetricsGeometry.bounds(of: local)!
      let inscribed = MetricsGeometry.largestInscribedRectangle(local) ?? box

      // Walled edges.
      var spans: [WalledSpan] = []
      var edges: [(a: Point2, b: Point2, spans: [WalledSpan])] = []
      for edgeIndex in polygon.indices {
        let a = polygon[edgeIndex]
        let b = polygon[(edgeIndex + 1) % polygon.count]
        let here = walledSpans(from: a, to: b, walls: walls)
        spans += here
        edges.append((a, b, here))
      }
      let walledLength = spans.reduce(0) { $0 + $1.length }
      let wallArea = spans.reduce(0) { $0 + $1.length * $1.heightM }

      // Ceiling height.
      let ceiling: CeilingHeight
      if walledLength <= MetricsGeometry.epsilon {
        let height = captureMedian ?? max(0, source?.heightM ?? 0)
        ceiling = CeilingHeight(
          heightM: height, basis: captureMedian == nil ? .roomRecord : .captureWalls,
          approximateReasons: [.noWalls])
      } else {
        let median = weightedMedian(spans.map { ($0.heightM, $0.length) }) ?? 0
        var reasons: [CeilingHeight.Reason] = []
        let offHeight = spans.filter {
          abs($0.heightM - median) > wallHeightSpreadM + MetricsGeometry.epsilon
        }.reduce(0) { $0 + $1.length }
        if offHeight > maximumOffHeightFraction * walledLength {
          reasons.append(.wallHeightsDiffer)
        }
        if walledLength < minimumWalledFraction * room.perimeterM - MetricsGeometry.epsilon {
          reasons.append(.fewWalls)
        }
        ceiling = CeilingHeight(heightM: median, basis: .roomWalls, approximateReasons: reasons)
      }

      // Openings on walled edges.
      var openings: [OpeningMetrics] = []
      for opening in geometry.openings
      where edges.contains(where: { isOpening(opening, onEdge: $0.a, $0.b, spans: $0.spans) }) {
        let type = OpeningType(opening.kind)
        let casing =
          type == .window
          ? OpeningMetrics.windowCasingLength(
            widthM: opening.widthM, heightM: opening.heightM, casingWidthM: settings.casingWidthM)
          : OpeningMetrics.doorCasingLength(
            widthM: opening.widthM, heightM: opening.heightM, casingWidthM: settings.casingWidthM)
        openings.append(
          OpeningMetrics(
            id: opening.id, type: type, widthM: opening.widthM, heightM: opening.heightM,
            bottomM: opening.bottomM,
            isOpen: type == .door ? isOpenById[opening.id] ?? nil : nil,
            areaM2: opening.widthM * opening.heightM, casingLengthM: casing))
      }
      let openingArea = openings.reduce(0) { $0 + $1.areaM2 }

      // Objects.
      let objects = geometry.objects.filter { $0.roomId == room.id }.map { object in
        let attributes = sourceObjects[object.id]?.attributes
        return ObjectMetrics(
          id: object.id, category: object.category,
          group: ObjectGroup.of(object.category, attributes: attributes),
          name: ObjectMetrics.name(of: object.category, attributes: attributes),
          widthM: object.sizeM.x, heightM: object.sizeM.y, depthM: object.sizeM.z,
          confidence: object.confidence, parentId: sourceObjects[object.id]?.parentId)
      }

      return RoomMetrics(
        roomId: room.id, label: room.label, type: source?.type, floorAreaM2: room.areaM2,
        perimeterM: room.perimeterM, frameAngleRadians: frame.angle,
        boundingBox: box.measured(in: frame), inscribed: inscribed.measured(in: frame),
        ceiling: ceiling, volumeM3: room.areaM2 * ceiling.heightM,
        wallAreaIncludingOpeningsM2: wallArea,
        wallAreaExcludingOpeningsM2: max(0, wallArea - openingArea), walledLengthM: walledLength,
        openings: openings, objects: objects,
        windowCasingM: openings.filter { $0.type == .window }.reduce(0) { $0 + $1.casingLengthM },
        doorCasingM: openings.filter { $0.type != .window }.reduce(0) { $0 + $1.casingLengthM })
    }
  }

  // MARK: Walled edges

  struct WallLine {
    var start: Point2
    var end: Point2
    var heightM: Double
  }

  /// A stretch of an outline edge with a wall, `from` and `to` in metres from the edge start.
  struct WalledSpan: Hashable {
    var from: Double
    var to: Double
    var heightM: Double
    var length: Double { to - from }
  }

  /// The stretches of the edge `a`-`b` that walls run along, in order, each with the height of
  /// the tallest wall there.
  static func walledSpans(from a: Point2, to b: Point2, walls: [WallLine]) -> [WalledSpan] {
    let length = a.distance(to: b)
    guard length > MetricsGeometry.epsilon else { return [] }
    let u = (b - a).unit
    let n = u.leftNormal
    let maxSine = sin(wallMatchAngleDegrees * .pi / 180)
    var intervals: [WalledSpan] = []
    for wall in walls {
      let direction = wall.end - wall.start
      let wallLength = direction.length
      guard wallLength > MetricsGeometry.epsilon else { continue }
      guard abs(u.x * direction.y - u.y * direction.x) / wallLength <= maxSine else { continue }
      let t0 = (wall.start - a).dot(u)
      let t1 = (wall.end - a).dot(u)
      guard abs(t1 - t0) > MetricsGeometry.epsilon else { continue }
      let from = max(0, min(t0, t1))
      let to = min(length, max(t0, t1))
      guard to - from > 1e-6 else { continue }
      // The clipped part of the wall must lie close to the edge.
      let close = [from, to].allSatisfy { t in
        let point = wall.start + direction * ((t - t0) / (t1 - t0))
        return abs((point - a).dot(n)) <= wallMatchDistanceM
      }
      if close { intervals.append(WalledSpan(from: from, to: to, heightM: wall.heightM)) }
    }
    guard !intervals.isEmpty else { return [] }
    let cuts = MetricsGeometry.distinctSorted(intervals.flatMap { [$0.from, $0.to] })
    var spans: [WalledSpan] = []
    for index in cuts.indices.dropLast() {
      let from = cuts[index]
      let to = cuts[index + 1]
      let middle = (from + to) / 2
      let covering = intervals.filter { $0.from <= middle && middle <= $0.to }
      guard let height = covering.map(\.heightM).max() else { continue }
      if let last = spans.last, last.heightM == height, abs(last.to - from) <= 1e-12 {
        spans[spans.count - 1].to = to
      } else {
        spans.append(WalledSpan(from: from, to: to, heightM: height))
      }
    }
    return spans
  }

  /// Whether the middle of `opening` lies on a walled stretch of the edge `a`-`b`, running
  /// along it.
  static func isOpening(_ opening: PlanOpening, onEdge a: Point2, _ b: Point2, spans: [WalledSpan])
    -> Bool
  {
    let length = a.distance(to: b)
    guard length > MetricsGeometry.epsilon, !spans.isEmpty else { return false }
    let u = (b - a).unit
    let along = opening.to - opening.from
    if along.length > MetricsGeometry.epsilon {
      let sine = abs(u.x * along.y - u.y * along.x) / along.length
      guard sine <= sin(wallMatchAngleDegrees * .pi / 180) else { return false }
    }
    let middle = (opening.from + opening.to) * 0.5
    guard abs((middle - a).dot(u.leftNormal)) <= wallMatchDistanceM else { return false }
    let t = (middle - a).dot(u)
    let slack = 0.01
    return spans.contains { t >= $0.from - slack && t <= $0.to + slack }
  }

  // MARK: Median

  /// Weighted median of `values` (value, weight): the smallest value at which the running
  /// weight, in ascending value order, reaches half the total; the mean of that value and the
  /// next when the running weight lands exactly on half. Nil when the total weight is zero.
  static func weightedMedian(_ values: [(Double, Double)]) -> Double? {
    let sorted = values.filter { $0.1 > 0 }.sorted { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
    let total = sorted.reduce(0) { $0 + $1.1 }
    guard total > 0 else { return nil }
    let half = total / 2
    var running = 0.0
    for (index, item) in sorted.enumerated() {
      running += item.1
      if abs(running - half) <= 1e-9 * total, index + 1 < sorted.count {
        return (item.0 + sorted[index + 1].0) / 2
      }
      if running >= half { return item.0 }
    }
    return sorted.last?.0
  }
}
