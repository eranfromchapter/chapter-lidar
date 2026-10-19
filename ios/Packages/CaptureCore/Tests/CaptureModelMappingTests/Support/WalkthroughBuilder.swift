import CaptureContract
import CaptureModelMapping
import Foundation

/// Small walk-through captures for tests: one `CapturedRoom` with a floor outline, walls,
/// sections and objects, given in plan coordinates (x, z) at floor level `floorY`. Identifiers
/// are numbered, so a capture built twice is the same.
struct WalkthroughBuilder {
  var floorY = -1.31
  var wallHeight = 2.49
  var outline: [(Double, Double)]
  var walls: [RoomPlanSurface] = []
  var doors: [RoomPlanSurface] = []
  var sections: [RoomPlanSection] = []
  var objects: [RoomPlanObject] = []

  /// A capture whose floor is `outline`, with a wall along each outline edge unless
  /// `wallsAlongOutline` is false.
  init(outline: [(Double, Double)], wallsAlongOutline: Bool = true) {
    self.outline = outline
    if wallsAlongOutline {
      for i in outline.indices { addWall(outline[i], outline[(i + 1) % outline.count]) }
    }
  }

  /// A wall from `a` to `b` standing on the floor.
  mutating func addWall(_ a: (Double, Double), _ b: (Double, Double), height: Double? = nil) {
    let h = height ?? wallHeight
    let dx = b.0 - a.0
    let dz = b.1 - a.1
    let length = (dx * dx + dz * dz).squareRoot()
    let ux = dx / length
    let uz = dz / length
    walls.append(
      RoomPlanSurface(
        identifier: String(format: "WALL-%04d", walls.count + 1), category: RoomPlanCategory(name: "wall"),
        confidence: .high, dimensions: [length, h, 0],
        transform: Matrix4(columns: [
          [ux, 0, uz, 0], [0, 1, 0, 0], [-uz, 0, ux, 0],
          [(a.0 + b.0) / 2, floorY + h / 2, (a.1 + b.1) / 2, 1],
        ])!))
  }

  /// A closed door of `width` centred at `at` in wall `wall` (its position in `walls`).
  mutating func addDoor(at point: (Double, Double), width: Double = 0.8, inWall wall: Int) {
    doors.append(
      RoomPlanSurface(
        identifier: String(format: "DOOR-%04d", doors.count + 1), parentIdentifier: walls[wall].identifier,
        category: RoomPlanCategory(name: "door", isOpen: false), confidence: .high,
        dimensions: [width, 2.0, 0],
        transform: Matrix4(columns: [
          walls[wall].transform.columns[0], [0, 1, 0, 0], walls[wall].transform.columns[2],
          [point.0, floorY + 1.0, point.1, 1],
        ])!))
  }

  mutating func addSection(_ label: String, at point: (Double, Double)) {
    sections.append(RoomPlanSection(label: label, story: 0, center: Vector3(point.0, floorY + 1.25, point.1)))
  }

  /// An object of `size` (along x, up, along z) centred at `at`; returns its identifier.
  @discardableResult
  mutating func addObject(
    _ category: String, at point: (Double, Double), size: (Double, Double, Double) = (0.6, 0.9, 0.6),
    parent: String? = nil
  ) -> String {
    let identifier = String(format: "OBJECT-%04d", objects.count + 1)
    objects.append(
      RoomPlanObject(
        identifier: identifier, parentIdentifier: parent, category: RoomPlanCategory(name: category),
        confidence: .high, dimensions: [size.0, size.1, size.2],
        transform: Matrix4(columns: [
          [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [point.0, floorY + size.1 / 2, point.1, 1],
        ])!))
    return identifier
  }

  var room: RoomPlanRoom {
    let floor = RoomPlanSurface(
      identifier: "FLOOR-0001", category: RoomPlanCategory(name: "floor"), confidence: .high,
      dimensions: [0, 0, 0],
      transform: Matrix4(columns: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, floorY, 0, 1]])!,
      polygonCorners: outline.map { [$0.0, 0, $0.1] })
    return RoomPlanRoom(
      identifier: "ROOM-0001", story: 0, walls: walls, doors: doors, floors: [floor], objects: objects,
      sections: sections)
  }

  var document: RoomPlanDocument { RoomPlanDocument(rooms: [room], isStructure: false) }

  /// The L-shaped floor of the cut tests: an 8 x 3 m strip with a 4 x 3 m wing on its left half.
  static let lShape: [(Double, Double)] = [(0, 0), (8, 0), (8, 3), (4, 3), (4, 6), (0, 6)]

  /// A plain 8 x 5 m rectangle.
  static let rectangle: [(Double, Double)] = [(0, 0), (8, 0), (8, 5), (0, 5)]
}
