import CaptureContract

/// Which captures are walk-throughs, and the plan view of one (floorplan plan, phase 3).
///
/// A walk-through is a whole apartment scanned as one `CapturedRoom`: one floor outline, many
/// walls, and a RoomPlan section (a label and a centre point, no shape) for each room RoomPlan
/// recognized. `WalkthroughSplitter` splits it into rooms; every other capture maps as before.
enum WalkthroughInput {
  /// True when the capture is one `CapturedRoom` with walls, a floor outline and two or more
  /// sections that have a centre (any label, including `unidentified`, on any story).
  static func isWalkthrough(_ document: RoomPlanDocument) -> Bool {
    guard !document.isStructure, document.rooms.count == 1 else { return false }
    let room = document.rooms[0]
    guard !room.walls.isEmpty, floorLoop(of: room) != nil else { return false }
    return room.sections.filter { $0.center != nil }.count >= 2
  }

  /// The floor outline the mapper uses (`CaptureModelMapper.outline`): the first floor with three
  /// or more corners, in the capture frame, with a repeated closing point dropped. Not yet wound.
  static func floorLoop(of room: RoomPlanRoom) -> [Vector3]? {
    for floor in room.floors {
      guard let corners = floor.polygonCorners, corners.count >= 3 else { continue }
      let points = corners.map { corner in
        floor.transform.apply(
          to: Vector3(
            corner.count > 0 ? corner[0] : 0, corner.count > 1 ? corner[1] : 0,
            corner.count > 2 ? corner[2] : 0))
      }
      let loop = PolygonMath.openLoop(points)
      if loop.count >= 3 { return loop }
    }
    return nil
  }

  /// A wall centreline in the plan, from the mapper's pass 1.
  struct Wall: Sendable {
    /// Position in `RoomPlanRoom.walls`.
    var index: Int
    var a: P2
    var b: P2
    var heightM: Double
    var baseY: Double
  }

  /// A section with a centre.
  struct Section: Sendable {
    /// Position in `RoomPlanRoom.sections`.
    var sectionIndex: Int
    var label: String
    var story: Int?
    var at: P2
    var centerY: Double
    var type: RoomType?
  }

  /// An object as the splitting sees it: centre, horizontal axis and footprint size.
  struct Object: Sendable {
    var index: Int
    var identifier: String
    var parentIdentifier: String?
    var category: ObjectCategory
    var center: P2
    var center3: Vector3
    /// Unit direction of the object's local x axis in the plan.
    var axis: P2
    /// Size along `axis` (dimension 0) and across it (dimension 2).
    var width: Double
    var depth: Double

    /// The room type only this kind of object has (toilet: bathroom), or nil.
    var definingType: RoomType? { WalkthroughInput.definingType(of: category) }

    /// The footprint rectangle, counter-clockwise.
    var footprint: [P2] {
      let halfW = width / 2
      let halfD = depth / 2
      var quad: [P2] = []
      for (sx, sz) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
        quad.append(
          P2(
            center.x + axis.x * sx * halfW - axis.y * sz * halfD,
            center.y + axis.y * sx * halfW + axis.x * sz * halfD))
      }
      return Plan2D.area(quad) >= 0 ? quad : quad.reversed()
    }
  }

  /// The plan view of a walk-through.
  struct Plan: Sendable {
    /// Floor outline, counter-clockwise in the plan.
    var outline: [P2]
    /// Height of the floor (y of the first outline corner).
    var floorY: Double
    var walls: [Wall]
    var sections: [Section]
    var objects: [Object]
  }

  /// The plan of `document`, which `isWalkthrough` accepted; walls from the mapper's pass 1.
  static func plan(of document: RoomPlanDocument, placements: [WallPlacement]) -> Plan? {
    guard let room = document.rooms.first, let loop = floorLoop(of: room) else { return nil }
    var outline = loop.map(P2.init)
    if Plan2D.area(outline) < 0 { outline.reverse() }
    let walls = placements.enumerated().map { index, placement in
      Wall(
        index: index, a: P2(placement.start), b: P2(placement.end), heightM: placement.heightM,
        baseY: placement.baseY)
    }
    var sections: [Section] = []
    for (index, section) in room.sections.enumerated() {
      guard let center = section.center else { continue }
      sections.append(
        Section(
          sectionIndex: index, label: section.label, story: section.story, at: P2(center),
          centerY: center.y, type: section.roomType))
    }
    let objects = room.objects.enumerated().map { index, object in
      let axis = object.transform.axis(0)
      return Object(
        index: index, identifier: object.identifier, parentIdentifier: object.parentIdentifier,
        category: object.category.objectCategory, center: P2(object.transform.translation),
        center3: object.transform.translation,
        axis: Plan2D.unit(P2(axis.x, axis.z)) ?? P2(1, 0),
        width: object.dimensions.count > 0 ? object.dimensions[0] : 0,
        depth: object.dimensions.count > 2 ? object.dimensions[2] : 0)
    }
    return Plan(
      outline: outline, floorY: loop[0].y, walls: walls, sections: sections, objects: objects)
  }

  /// The room type only `category` belongs to (`RoomTyping.defining`), or nil.
  static func definingType(of category: ObjectCategory) -> RoomType? {
    RoomTyping.defining.first { $0.categories.contains(category) }?.type
  }

  static let kitchenAppliances: Set<ObjectCategory> = [.stove, .oven, .refrigerator, .dishwasher]
  /// Objects that a cut through costs more: sofas and tables.
  static let bigObjects: Set<ObjectCategory> = [.sofa, .table]

  /// `quad` with each corner moved `distance` toward the corners' mean (stopping at the mean).
  static func shrink(_ quad: [P2], by distance: Double) -> [P2] {
    let c = ((quad[0] + quad[1]) + (quad[2] + quad[3])) * 0.25
    return quad.map { p in
      let v = p - c
      let length = Plan2D.norm(v)
      return length > 1e-9 ? c + v * (max(0, length - distance) / length) : p
    }
  }
}
