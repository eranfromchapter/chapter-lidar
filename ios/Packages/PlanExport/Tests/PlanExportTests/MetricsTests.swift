import CaptureContract
import Foundation
import XCTest

@testable import PlanExport

/// Inches to metres.
private func inches(_ value: Double) -> Double { value * UnitFormatter.metresPerInch }

/// Models built from room outlines given as model (x, z) pairs.
private enum Outlines {
  struct Room {
    var id: String
    var label: String
    var type: RoomType?
    var corners: [(Double, Double)]
    var heightM: Double = 2.7
    /// Wall height per edge (edge i runs from corner i to corner i + 1); nil leaves the edge
    /// without a wall. Empty: every edge gets a wall of `heightM`.
    var wallHeights: [Double?] = []
  }

  static func model(_ rooms: [Room]) -> CaptureModel {
    var walls: [CaptureModel.Wall] = []
    var modelRooms: [CaptureModel.Room] = []
    for room in rooms {
      let points = room.corners.map { Vec3(x: $0.0, y: 0, z: $0.1) }
      modelRooms.append(
        CaptureModel.Room(
          id: room.id, label: room.label, polygon: points, heightM: room.heightM, type: room.type,
          typeSource: room.type == nil ? nil : .operator))
      for index in points.indices {
        let height =
          room.wallHeights.isEmpty
          ? room.heightM : index < room.wallHeights.count ? room.wallHeights[index] : nil
        guard let height else { continue }
        walls.append(
          CaptureModel.Wall(
            id: "\(room.id)-wall-\(index + 1)", start: points[index],
            end: points[(index + 1) % points.count], heightM: height, thicknessM: 0,
            roomIds: [room.id]))
      }
    }
    return CaptureModel(
      visitId: LowercaseUUID(rawValue: "c1b6d1fb-17af-4f4a-877c-2565ef9bdb86")!,
      captureId: LowercaseUUID(rawValue: "22bfb513-226d-4eca-bde1-0b6cb0c84aad")!,
      areaKey: "floor-1", label: "Floor 1", rooms: modelRooms, walls: walls)
  }
}

final class RoomMetricsTests: XCTestCase {
  func testBoxRoomInscribedRectangleIsTheBoundingBox() throws {
    let capture = try XCTUnwrap(Fixtures.load("box-room").first)
    let room = try XCTUnwrap(try PlanMetrics(capture.model).rooms.first)
    XCTAssertEqual(room.frameAngleRadians, 0)
    XCTAssertEqual(room.inscribed, room.boundingBox)
    XCTAssertEqual(room.boundingBox.alongM, 4, accuracy: 1e-9)
    XCTAssertEqual(room.boundingBox.acrossM, 3, accuracy: 1e-9)
    XCTAssertEqual(room.floorAreaM2, 12, accuracy: 1e-9)
    XCTAssertEqual(room.perimeterM, 14, accuracy: 1e-9)
    XCTAssertEqual(room.ceiling.heightM, 2.7, accuracy: 1e-9)
    XCTAssertEqual(room.ceiling.basis, .roomWalls)
    XCTAssertFalse(room.ceiling.isApproximate)
    XCTAssertEqual(room.volumeM3, 32.4, accuracy: 1e-9)
    XCTAssertEqual(room.walledLengthM, 14, accuracy: 1e-9)
    // 14 m of wall 2.7 m high, less a 0.9 x 2.1 m door and a 1.2 x 1.2 m window.
    XCTAssertEqual(room.wallAreaIncludingOpeningsM2, 37.8, accuracy: 1e-9)
    XCTAssertEqual(room.wallAreaExcludingOpeningsM2, 37.8 - 1.89 - 1.44, accuracy: 1e-9)
    XCTAssertEqual(room.openings.map(\.id), ["door-1", "window-1"])
    XCTAssertEqual(room.openings.map(\.type), [.door, .window])
    XCTAssertEqual(room.openings[0].areaM2, 1.89, accuracy: 1e-9)
    XCTAssertEqual(room.openings[1].areaM2, 1.44, accuracy: 1e-9)
  }

  func testRotatedRoomIsMeasuredAlongItsOwnAxis() throws {
    let angle = 30.0 * .pi / 180
    // A 4 x 3 m room turned 30 degrees counter-clockwise on the plan (plan y is model -z).
    let corners = [(0.0, 0.0), (0.0, -3.0), (4.0, -3.0), (4.0, 0.0)].map { x, y in
      (x * cos(angle) - y * sin(angle), -(x * sin(angle) + y * cos(angle)))
    }
    let model = Outlines.model([.init(id: "room-1", label: "Room", corners: corners)])
    let room = try XCTUnwrap(try PlanMetrics(model).rooms.first)
    XCTAssertEqual(room.frameAngleRadians, angle, accuracy: 1e-9)
    XCTAssertEqual(room.boundingBox.alongM, 4, accuracy: 1e-9)
    XCTAssertEqual(room.boundingBox.acrossM, 3, accuracy: 1e-9)
    XCTAssertEqual(room.inscribed.alongM, 4, accuracy: 1e-9)
    XCTAssertEqual(room.inscribed.acrossM, 3, accuracy: 1e-9)
    XCTAssertEqual(room.inscribed.center.x, room.boundingBox.center.x, accuracy: 1e-9)
    XCTAssertEqual(room.inscribed.center.y, room.boundingBox.center.y, accuracy: 1e-9)
    XCTAssertEqual(room.floorAreaM2, 12, accuracy: 1e-9)
    XCTAssertEqual(room.wallAreaIncludingOpeningsM2, 14 * 2.7, accuracy: 1e-9)
  }

  func testLShapedFixtureInscribedRectangle() throws {
    // 6 x 4 m with a 3 x 2 m corner removed: 6 x 2 m and 3 x 4 m both fit (12 m²); the
    // squarer one wins the tie.
    let capture = try XCTUnwrap(Fixtures.load("l-shaped-room").first)
    let room = try XCTUnwrap(try PlanMetrics(capture.model).rooms.first)
    XCTAssertEqual(room.boundingBox.alongM, 6, accuracy: 1e-9)
    XCTAssertEqual(room.boundingBox.acrossM, 4, accuracy: 1e-9)
    XCTAssertEqual(room.inscribed.alongM, 3, accuracy: 1e-9)
    XCTAssertEqual(room.inscribed.acrossM, 4, accuracy: 1e-9)
    // Plan x 0...3, plan y -4...0 (model z 0...4).
    XCTAssertEqual(room.inscribed.center.x, 1.5, accuracy: 1e-9)
    XCTAssertEqual(room.inscribed.center.y, -2, accuracy: 1e-9)
    XCTAssertEqual(room.floorAreaM2, 18, accuracy: 1e-9)
    XCTAssertEqual(room.perimeterM, 20, accuracy: 1e-9)
  }

  func testLShapedRoomWithOneLargestRectangleExactAndRaster() throws {
    // 6 x 4 m with a 2 x 2 m corner removed: the largest rectangle is 4 x 4 m.
    let corners = [(0.0, 0.0), (0.0, 4.0), (4.0, 4.0), (4.0, 2.0), (6.0, 2.0), (6.0, 0.0)]
    let model = Outlines.model([.init(id: "room-1", label: "L", corners: corners)])
    let exact = try XCTUnwrap(try PlanMetrics(model).rooms.first?.inscribed)
    XCTAssertEqual(exact.alongM, 4, accuracy: 1e-9)
    XCTAssertEqual(exact.acrossM, 4, accuracy: 1e-9)
    XCTAssertEqual(exact.center.x, 2, accuracy: 1e-9)
    XCTAssertEqual(exact.center.y, -2, accuracy: 1e-9)

    // The same outline with every edge cut into 20 pieces has more than 64 corners and is
    // searched on a 1 cm raster.
    var dense: [(Double, Double)] = []
    for index in corners.indices {
      let a = corners[index]
      let b = corners[(index + 1) % corners.count]
      for step in 0..<20 {
        let t = Double(step) / 20
        dense.append((a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t))
      }
    }
    XCTAssertGreaterThan(dense.count, MetricsGeometry.exactSearchVertexLimit)
    let denseModel = Outlines.model([.init(id: "room-1", label: "L", corners: dense)])
    let raster = try XCTUnwrap(try PlanMetrics(denseModel).rooms.first?.inscribed)
    XCTAssertEqual(raster.alongM, 4, accuracy: 0.011)
    XCTAssertEqual(raster.acrossM, 4, accuracy: 0.011)
    XCTAssertEqual(raster.center.x, 2, accuracy: 0.011)
    XCTAssertEqual(raster.center.y, -2, accuracy: 0.011)
  }

  func testWallAreaCountsOnlyEdgesWithWalls() throws {
    // 4 x 3 m; edges: x = 0 (3 m), z = 3 (4 m), x = 4 (3 m), z = 0 (4 m). No wall on z = 3.
    let corners = [(0.0, 0.0), (0.0, 3.0), (4.0, 3.0), (4.0, 0.0)]
    let model = Outlines.model([
      .init(id: "room-1", label: "Room", corners: corners, wallHeights: [2.7, nil, 2.7, 2.7])
    ])
    let room = try XCTUnwrap(try PlanMetrics(model).rooms.first)
    XCTAssertEqual(room.walledLengthM, 10, accuracy: 1e-9)
    XCTAssertEqual(room.wallAreaIncludingOpeningsM2, 27, accuracy: 1e-9)
    XCTAssertEqual(room.wallAreaExcludingOpeningsM2, 27, accuracy: 1e-9)
    XCTAssertEqual(room.ceiling.heightM, 2.7, accuracy: 1e-9)
    XCTAssertFalse(room.ceiling.isApproximate)
  }

  func testCeilingHeightIsTheLengthWeightedMedianWithApproxFlags() throws {
    let corners = [(0.0, 0.0), (0.0, 3.0), (4.0, 3.0), (4.0, 0.0)]
    func ceiling(_ heights: [Double?]) throws -> CeilingHeight {
      let model = Outlines.model([
        .init(id: "room-1", label: "Room", corners: corners, wallHeights: heights)
      ])
      return try XCTUnwrap(try PlanMetrics(model).rooms.first).ceiling
    }
    // 3 m of wall at 2.9 m and 7 m at 2.7 m: median 2.7 m; 30 % of the walls are off height.
    let differ = try ceiling([2.9, nil, 2.7, 2.7])
    XCTAssertEqual(differ.heightM, 2.7, accuracy: 1e-9)
    XCTAssertEqual(differ.approximateReasons, [.wallHeightsDiffer])
    // Walls on 6 of 14 m.
    let few = try ceiling([2.6, nil, 2.6, nil])
    XCTAssertEqual(few.heightM, 2.6, accuracy: 1e-9)
    XCTAssertEqual(few.approximateReasons, [.fewWalls])

    // A short stub at another height (2 % of the walls) does not make the height approximate.
    var model = Outlines.model([.init(id: "room-1", label: "Room", corners: corners)])
    model.walls.append(
      CaptureModel.Wall(
        id: "stub", start: Vec3(x: 0, y: 0, z: 0.1), end: Vec3(x: 0, y: 0, z: 0.4), heightM: 3.2,
        thicknessM: 0))
    let stub = try XCTUnwrap(try PlanMetrics(model).rooms.first)
    XCTAssertEqual(stub.ceiling.heightM, 2.7, accuracy: 1e-9)
    XCTAssertFalse(stub.ceiling.isApproximate)
    // The tallest wall counts where walls overlap.
    XCTAssertEqual(stub.wallAreaIncludingOpeningsM2, 14 * 2.7 + 0.3 * 0.5, accuracy: 1e-9)

    XCTAssertEqual(RoomMetrics.weightedMedian([(2.6, 1), (2.8, 1)])!, 2.7, accuracy: 1e-12)
    XCTAssertEqual(RoomMetrics.weightedMedian([(2.8, 2), (2.6, 1)]), 2.8)
    XCTAssertNil(RoomMetrics.weightedMedian([]))
  }

  func testCeilingHeightFallsBackWhenTheRoomHasNoWalls() throws {
    let walled = Outlines.Room(
      id: "room-1", label: "Walled", corners: [(0, 0), (0, 3), (4, 3), (4, 0)], heightM: 2.6)
    let open = Outlines.Room(
      id: "room-2", label: "Open", corners: [(10, 0), (10, 2), (12, 2), (12, 0)], heightM: 2.4,
      wallHeights: [nil, nil, nil, nil])
    let rooms = try PlanMetrics(Outlines.model([walled, open])).rooms
    // The capture's walls give the height.
    XCTAssertEqual(rooms[1].ceiling.heightM, 2.6, accuracy: 1e-9)
    XCTAssertEqual(rooms[1].ceiling.basis, .captureWalls)
    XCTAssertEqual(rooms[1].ceiling.approximateReasons, [.noWalls])
    XCTAssertEqual(rooms[1].volumeM3, 4 * 2.6, accuracy: 1e-9)
    XCTAssertEqual(rooms[1].wallAreaIncludingOpeningsM2, 0)

    // No walls anywhere: the room's own height.
    let alone = try XCTUnwrap(try PlanMetrics(Outlines.model([open])).rooms.first)
    XCTAssertEqual(alone.ceiling.heightM, 2.4, accuracy: 1e-9)
    XCTAssertEqual(alone.ceiling.basis, .roomRecord)
    XCTAssertTrue(alone.ceiling.isApproximate)
  }

  func testOpeningsInAWallBetweenTwoRoomsCountForBoth() throws {
    let capture = try XCTUnwrap(Fixtures.load("two-room-apartment").first)
    let metrics = try PlanMetrics(capture.model)
    let living = metrics.rooms[0]
    let bedroom = metrics.rooms[1]
    XCTAssertEqual(living.openings.map(\.id), ["door-1", "window-1", "opening-1"])
    XCTAssertEqual(bedroom.openings.map(\.id), ["door-1", "window-2"])
    // 18 m and 14 m of wall 2.7 m high, less their openings.
    XCTAssertEqual(living.wallAreaIncludingOpeningsM2, 18 * 2.7, accuracy: 1e-9)
    XCTAssertEqual(living.wallAreaExcludingOpeningsM2, 48.6 - 1.89 - 1.8 - 2.1, accuracy: 1e-9)
    XCTAssertEqual(bedroom.wallAreaExcludingOpeningsM2, 37.8 - 1.89 - 1.44, accuracy: 1e-9)

    let c = MeasurementSettings.defaultCasingWidthM
    XCTAssertEqual(living.windowCasingM, 2 * (1.5 + 1.2) + 8 * c, accuracy: 1e-9)
    // The door and the passage opening are cased like doors.
    XCTAssertEqual(
      living.doorCasingM, (2 * 2.1 + 0.9 + 4 * c) + (2 * 2.1 + 1.0 + 4 * c), accuracy: 1e-9)

    let totals = metrics.totals
    XCTAssertEqual(totals.roomCount, 2)
    XCTAssertEqual(totals.livableAreaM2, 32, accuracy: 1e-9)
    XCTAssertEqual(totals.windowAreaM2, 1.8 + 1.44, accuracy: 1e-9)
    XCTAssertEqual(
      totals.wallAreaM2, living.wallAreaExcludingOpeningsM2 + bedroom.wallAreaExcludingOpeningsM2,
      accuracy: 1e-9)
    XCTAssertEqual(totals.perimeterM, 32, accuracy: 1e-9)
    XCTAssertEqual(totals.volumeM3, 32 * 2.7, accuracy: 1e-9)
    XCTAssertFalse(totals.volumeIsApproximate)
    // The 8 x 4 m outline pushed out by 6 in on every side.
    let t = MeasurementSettings.defaultExteriorWallThicknessM
    XCTAssertEqual(totals.exteriorAreaEstimateM2, (8 + 2 * t) * (4 + 2 * t), accuracy: 0.01)
    XCTAssertEqual(totals.exteriorWallThicknessM, t)
  }

  func testObjectsAreGroupedAndNamed() throws {
    var model = Synthetic.room(width: 4, length: 3)
    let cases: [(ObjectCategory, [String: String]?, ObjectGroup, String)] = [
      (.bed, nil, .furniture, "Bed"),
      (.sofa, ["SofaType": "rectangular"], .furniture, "Sofa"),
      (.chair, ["ChairType": "swivel"], .furniture, "Swivel chair"),
      (.table, ["TableType": "coffee"], .furniture, "Coffee table"),
      (.storage, ["StorageType": "shelf"], .furniture, "Shelf"),
      (.storage, ["StorageType": "cabinet"], .fixtures, "Cabinet"),
      (.storage, nil, .fixtures, "Cabinet"),
      (.sink, nil, .fixtures, "Sink"),
      (.toilet, nil, .fixtures, "Toilet"),
      (.bathtub, nil, .fixtures, "Bathtub"),
      (.refrigerator, nil, .appliances, "Refrigerator"),
      (.oven, nil, .appliances, "Oven"),
      (.stove, nil, .appliances, "Stove"),
      (.dishwasher, nil, .appliances, "Dishwasher"),
      (.washerDryer, nil, .appliances, "Washer-dryer"),
      (.television, nil, .appliances, "Television"),
      (.fireplace, nil, .other, "Fireplace"),
      (.stairs, nil, .other, "Stairs"),
      (.other, nil, .other, "Other object"),
    ]
    model.objects = cases.enumerated().map { index, item in
      CaptureModel.DetectedObject(
        id: "object-\(index + 1)", category: item.0,
        box: CaptureModel.OrientedBox(
          center: Vec3(x: 2, y: 0.5, z: 1.5), sizeM: Vec3(x: 0.5, y: 1, z: 0.25)),
        attributes: item.1, parentId: index == 7 ? "object-6" : nil)
    }
    // An object outside every room is in no room.
    model.objects.append(
      CaptureModel.DetectedObject(
        id: "outside", category: .chair,
        box: CaptureModel.OrientedBox(
          center: Vec3(x: 9, y: 0.5, z: 9), sizeM: Vec3(x: 1, y: 1, z: 1))))
    let room = try XCTUnwrap(try PlanMetrics(model).rooms.first)
    XCTAssertEqual(room.objects.count, cases.count)
    for (object, item) in zip(room.objects, cases) {
      XCTAssertEqual(object.category, item.0)
      XCTAssertEqual(object.group, item.2, "\(item.0)")
      XCTAssertEqual(object.name, item.3)
      XCTAssertEqual(object.widthM, 0.5)
      XCTAssertEqual(object.heightM, 1)
      XCTAssertEqual(object.depthM, 0.25)
    }
    XCTAssertEqual(room.objects[7].parentId, "object-6")
    XCTAssertEqual(room.objects(in: .furniture).count, 5)
    XCTAssertEqual(room.objects(in: .fixtures).count, 5)
    XCTAssertEqual(room.objects(in: .appliances).count, 6)
    XCTAssertEqual(room.objects(in: .other).count, 3)
  }

  func testMetricsAreDeterministicAndFinite() throws {
    for capture in try Fixtures.all() {
      let first = try PlanMetrics(capture.model)
      let second = try PlanMetrics(capture.model)
      XCTAssertEqual(first, second, capture.fixture)
      for room in first.rooms {
        let values = [
          room.floorAreaM2, room.perimeterM, room.boundingBox.alongM, room.boundingBox.acrossM,
          room.inscribed.alongM, room.inscribed.acrossM, room.ceiling.heightM, room.volumeM3,
          room.wallAreaIncludingOpeningsM2, room.wallAreaExcludingOpeningsM2,
        ]
        XCTAssertTrue(values.allSatisfy(\.isFinite), "\(capture.fixture) \(room.roomId)")
        XCTAssertLessThanOrEqual(room.inscribed.areaM2, room.floorAreaM2 + 1e-9)
        XCTAssertLessThanOrEqual(room.floorAreaM2, room.boundingBox.areaM2 + 1e-9)
      }
      XCTAssertEqual(
        try PlanTotals(capture.model), first.totals, "PlanTotals agrees with PlanMetrics")
      XCTAssertEqual(try RoomMetrics.measure(capture.model), first.rooms)
    }
  }
}

/// The measurements against the Polycam Spatial Report of the same apartment.
final class PolycamReferenceTests: XCTestCase {
  func testCasingFormulasReproducePolycamsCasingLengths() throws {
    let c = MeasurementSettings.defaultCasingWidthM
    XCTAssertEqual(c, inches(1.5625), accuracy: 1e-15)
    // Bedroom 2: window 6' 3.0" x 5' 5.2", door 2' 8.5" x 6' 9.3".
    let window = OpeningMetrics.windowCasingLength(
      widthM: inches(75.0), heightM: inches(65.2), casingWidthM: c)
    XCTAssertEqual(UnitFormatter.length(window, style: .feetInchesTenths), "24' 4.9\"")
    let door = OpeningMetrics.doorCasingLength(
      widthM: inches(32.5), heightM: inches(81.3), casingWidthM: c)
    XCTAssertEqual(UnitFormatter.length(door, style: .feetInchesTenths), "16' 9.4\"")

    // The same through a room's casing totals.
    var model = Synthetic.room(width: 4, length: 3)
    model.windows = [
      CaptureModel.WallOpening(
        id: "window-1", wallId: "wall-2", offsetM: 2, bottomM: 0.8, widthM: inches(75.0),
        heightM: inches(65.2))
    ]
    model.doors = [
      CaptureModel.WallOpening(
        id: "door-1", wallId: "wall-4", offsetM: 1, bottomM: 0, widthM: inches(32.5),
        heightM: inches(81.3))
    ]
    let room = try XCTUnwrap(try PlanMetrics(model).rooms.first)
    let format = UnitFormatter(system: .imperial)
    XCTAssertEqual(format.length(room.windowCasingM), "24' 4.9\"")
    XCTAssertEqual(format.length(room.doorCasingM), "16' 9.4\"")

    // Every casing line of the report, from its printed opening sizes (inches). The printed
    // sizes are rounded to 0.1 in, so each opening may be off by its share of that.
    let lines: [(String, windows: [(Double, Double)], doors: [(Double, Double)], Double)] = [
      ("Living Room windows", [(77.1, 61.7)], [], 290.2),
      ("Living Room doors", [], [(33.9, 84.2), (30.2, 79.5), (24.9, 85.1)], 605.5),
      ("Bedroom 1 windows", [(77.1, 65.3)], [], 297.5),
      ("Bedroom 1 doors", [], [(30.2, 79.5), (23.4, 80.9), (24.1, 78.0)], 573.4),
      ("Bedroom 2 windows", [(75.0, 65.2)], [], 292.9),
      ("Bedroom 2 doors", [], [(32.5, 81.3)], 201.4),
      ("Kitchen doors", [], [(29.7, 97.2)], 230.3),
      ("Bathroom 1 doors", [], [(32.5, 81.3), (30.3, 85.7)], 409.5),
      ("Bathroom 2 doors", [], [(24.9, 85.1)], 201.3),
      ("Closet doors", [], [(24.1, 78.0)], 186.4),
    ]
    for (name, windows, doors, printed) in lines {
      let length =
        windows.reduce(0) {
          $0 + OpeningMetrics.windowCasingLength(
            widthM: inches($1.0), heightM: inches($1.1), casingWidthM: c)
        }
        + doors.reduce(0) {
          $0 + OpeningMetrics.doorCasingLength(
            widthM: inches($1.0), heightM: inches($1.1), casingWidthM: c)
        }
      let slack = 0.05 + 0.2 * Double(windows.count) + 0.15 * Double(doors.count)
      XCTAssertEqual(length / inches(1), printed, accuracy: slack, name)
    }
  }

  /// Polycam's room schedule: name, type, floor area (ft²), perimeter (in), room volume (ft³)
  /// and whether its height is marked approximate; then the overview it prints. The areas and
  /// perimeters here are unrounded values that print as the schedule does; heights follow from
  /// the volumes.
  func testTotalsRulesReproducePolycamsOverviewFromItsSchedule() throws {
    typealias Printed = (area: String, perimeter: String, height: String)
    let schedule:
      [(name: String, type: RoomType, areaFt2: Double, perimeterIn: Double, volumeFt3: Double,
        approx: Bool, printed: Printed)] = [
        (
          "Living Room", .livingRoom, 300.06, 1156.18, 2476.67, false,
          ("300.1", "96' 4.2\"", "8' 3.0\"")
        ),
        ("Bedroom 1", .bedroom, 192.08, 778.08, 1585.38, false, ("192.1", "64' 10.1\"", "8' 3.0\"")
        ),
        ("Bedroom 2", .bedroom, 152.08, 604.48, 1255.24, false, ("152.1", "50' 4.5\"", "8' 3.0\"")),
        ("Kitchen", .kitchen, 47.71, 331.68, 393.72, false, ("47.7", "27' 7.7\"", "8' 3.0\"")),
        ("Bathroom 1", .bathroom, 43.79, 364.68, 361.43, true, ("43.8", "30' 4.7\"", "8' 3.0\"")),
        ("Bathroom 2", .bathroom, 35.60, 291.48, 214.27, true, ("35.6", "24' 3.5\"", "6' 0.2\"")),
        ("Closet", .closet, 14.52, 185.98, 119.80, true, ("14.5", "15' 6.0\"", "8' 3.0\"")),
      ]
    // Windows of the report's Openings tables: (room, area ft²).
    let windows = [(0, 33.04), (1, 34.98), (2, 33.94)]

    var rooms: [Outlines.Room] = []
    var openings: [CaptureModel.WallOpening] = []
    for (index, row) in schedule.enumerated() {
      // A rectangle a x b with the room's area and perimeter, 20 m from the previous room.
      let area = row.areaFt2 * UnitFormatter.squareMetresPerSquareFoot
      let half = inches(row.perimeterIn) / 2
      let root = (half * half - 4 * area).squareRoot()
      let a = (half + root) / 2
      let b = (half - root) / 2
      let height = row.volumeFt3 * UnitFormatter.cubicMetresPerCubicFoot / area
      let x = Double(index) * 20
      // Approximate rooms get one short side 10 cm higher (more than 10 % of the walls).
      let heights: [Double?] = [height, row.approx ? height + 0.1 : height, height, height]
      rooms.append(
        .init(
          id: "room-\(index + 1)", label: row.name, type: row.type,
          corners: [(x, 0), (x + a, 0), (x + a, b), (x, b)], heightM: height,
          wallHeights: heights))
      if let window = windows.first(where: { $0.0 == index }) {
        let width = inches(77.1)
        openings.append(
          CaptureModel.WallOpening(
            id: "window-\(openings.count + 1)", wallId: "room-\(index + 1)-wall-1",
            offsetM: a / 2, bottomM: 0.8, widthM: width,
            heightM: window.1 * UnitFormatter.squareMetresPerSquareFoot / width))
      }
    }
    var model = Outlines.model(rooms)
    model.windows = openings
    let metrics = try PlanMetrics(model)
    let format = UnitFormatter(system: .imperial)

    for (room, row) in zip(metrics.rooms, schedule) {
      XCTAssertEqual(format.area(room.floorAreaM2), "\(row.printed.area) ft\u{00B2}", row.name)
      XCTAssertEqual(format.length(room.perimeterM), row.printed.perimeter, row.name)
      XCTAssertEqual(format.length(room.ceiling.heightM), row.printed.height, row.name)
      let volume = UnitFormatter.decimals(row.volumeFt3, places: 2)!
      XCTAssertEqual(format.volume(room.volumeM3), "\(volume) ft\u{00B3}", row.name)
      XCTAssertEqual(room.ceiling.isApproximate, row.approx, row.name)
    }

    // The overview: printed totals are sums of unrounded room values, rounded once.
    let totals = metrics.totals
    XCTAssertEqual(totals.bedrooms, 2)
    XCTAssertEqual(totals.bathrooms, 2)
    XCTAssertEqual(format.area(totals.livableAreaM2), "785.8 ft\u{00B2}")
    // The printed room areas add up to 785.9; Polycam's overview also says 785.8.
    let printedSum = schedule.reduce(0) { $0 + Double($1.printed.area)! }
    XCTAssertEqual(UnitFormatter.decimals(printedSum, places: 1), "785.9")
    XCTAssertEqual(format.volume(totals.volumeM3), "6406.51 ft\u{00B3}")
    XCTAssertTrue(totals.volumeIsApproximate)
    XCTAssertEqual(format.length(totals.perimeterM), "309' 4.6\"")
    XCTAssertEqual(format.area(totals.windowAreaM2), "102.0 ft\u{00B2}")
    XCTAssertEqual(
      totals.wallAreaM2, metrics.rooms.reduce(0) { $0 + $1.wallAreaExcludingOpeningsM2 },
      accuracy: 1e-9)
    // Polycam's room wall areas (excluding openings) add up to its total in the same way.
    let polycamWallAreas = [614.5, 460.5, 351.1, 201.1, 192.6, 150.6, 125.8]
    XCTAssertEqual(polycamWallAreas.reduce(0, +), 2096.1, accuracy: 7 * 0.05)
  }
}

final class PlanTotalsTests: XCTestCase {
  /// The synthetic walk-through apartment: seven rooms turned -14.2 degrees, whose outlines
  /// tile the apartment outline.
  private struct Walkthrough: Decodable {
    struct Frame: Decodable {
      var floorY: Double
      var yawDeg: Double
    }
    struct Totals: Decodable {
      var floorAreaM2: Double
      var outlinePerimeterM: Double
    }
    struct Room: Decodable {
      var id: String
      var label: String
      var type: String
      var areaM2: Double
      var polygon: [[Double]]
    }
    var frame: Frame
    var totals: Totals
    var rooms: [Room]
  }

  func testWalkthroughApartmentTotalsAndExteriorEstimate() throws {
    let url = Repo.root.appendingPathComponent(
      "fixtures/generated/roomplan-only/apartment-walkthrough/expected.json")
    let expected = try JSONDecoder().decode(Walkthrough.self, from: Data(contentsOf: url))
    let model = CaptureModel(
      visitId: LowercaseUUID(rawValue: "c1b6d1fb-17af-4f4a-877c-2565ef9bdb86")!,
      captureId: LowercaseUUID(rawValue: "22bfb513-226d-4eca-bde1-0b6cb0c84aad")!,
      areaKey: "apartment", label: "Apartment",
      rooms: expected.rooms.map { room in
        CaptureModel.Room(
          id: room.id, label: room.label,
          polygon: room.polygon.map { Vec3(x: $0[0], y: expected.frame.floorY, z: $0[1]) },
          heightM: 2.5, type: RoomType(rawValue: room.type), typeSource: .roomplanSection)
      })
    let metrics = try PlanMetrics(model)
    let yaw = expected.frame.yawDeg * .pi / 180
    // The fixture's coordinates are rounded to the micrometre.
    for (room, source) in zip(metrics.rooms, expected.rooms) {
      XCTAssertEqual(room.floorAreaM2, source.areaM2, accuracy: 1e-4, room.label)
      // The living room's one slanted edge does not turn its axis.
      XCTAssertEqual(room.frameAngleRadians, yaw, accuracy: 1e-5, room.label)
      if source.polygon.count == 4 {
        XCTAssertEqual(room.inscribed.alongM, room.boundingBox.alongM, accuracy: 1e-5)
        XCTAssertEqual(room.inscribed.acrossM, room.boundingBox.acrossM, accuracy: 1e-5)
        XCTAssertEqual(room.inscribed.areaM2, room.floorAreaM2, accuracy: 1e-4)
      }
      // The inscribed rectangle lies inside the room.
      let outline = source.polygon.map { Point2(Vec3(x: $0[0], y: 0, z: $0[1])) }
      for corner in room.inscribed.corners {
        let point = Point2(x: corner.x, y: corner.y)
        XCTAssertTrue(
          PlanGeometry.contains(outline, point)
            || PlanGeometry.distanceToBoundary(of: outline, from: point) < 1e-9, room.label)
      }
      // No walls in this model: the rooms keep their own height, marked approximate.
      XCTAssertEqual(room.ceiling.basis, .roomRecord)
    }
    let totals = metrics.totals
    XCTAssertEqual(totals.roomCount, 7)
    XCTAssertEqual(totals.bedrooms, 2)
    XCTAssertEqual(totals.bathrooms, 1)
    XCTAssertEqual(totals.livableAreaM2, expected.totals.floorAreaM2, accuracy: 1e-4)
    // An outline whose corners are all right angles, pushed out by t with square corners,
    // grows by perimeter x t + 4 t².
    let t = MeasurementSettings.defaultExteriorWallThicknessM
    XCTAssertEqual(
      totals.exteriorAreaEstimateM2,
      expected.totals.floorAreaM2 + expected.totals.outlinePerimeterM * t + 4 * t * t,
      accuracy: 0.05)
  }

  func testExteriorEstimateFillsInteriorWallGapsAndScalesWithThickness() throws {
    // Two 3 x 3 m rooms 10 cm apart (an interior wall): the outline is 6.1 x 3 m.
    let rooms: [Outlines.Room] = [
      .init(id: "room-1", label: "A", corners: [(0, 0), (0, 3), (3, 3), (3, 0)]),
      .init(id: "room-2", label: "B", corners: [(3.1, 0), (3.1, 3), (6.1, 3), (6.1, 0)]),
    ]
    let model = Outlines.model(rooms)
    let t = MeasurementSettings.defaultExteriorWallThicknessM
    let totals = try PlanTotals(model)
    XCTAssertEqual(totals.livableAreaM2, 18, accuracy: 1e-9)
    XCTAssertEqual(totals.exteriorAreaEstimateM2, (6.1 + 2 * t) * (3 + 2 * t), accuracy: 0.01)
    let none = try PlanTotals(model, settings: MeasurementSettings(exteriorWallThicknessM: 0))
    XCTAssertEqual(none.exteriorAreaEstimateM2, 18, accuracy: 1e-9)
    let thick = try PlanTotals(model, settings: MeasurementSettings(exteriorWallThicknessM: 0.3))
    XCTAssertEqual(thick.exteriorAreaEstimateM2, 6.7 * 3.6, accuracy: 0.02)
  }
}

final class UnitFormatterTests: XCTestCase {
  func testLengthStyles() {
    // 73.96 in.
    let length = inches(73.96)
    let expected: [(LengthStyle, String)] = [
      (.feetInchesTenths, "6' 2.0\""), (.feetInches, "6' 2\""), (.inches, "74\""),
      (.decimalFeet, "6.16'"), (.metres, "1.88 m"), (.centimetres, "188 cm"),
      (.millimetres, "1879 mm"),
    ]
    for (style, text) in expected {
      XCTAssertEqual(UnitFormatter.length(length, style: style), text, style.rawValue)
    }
  }

  func testFeetInchesRoundAsAWhole() {
    XCTAssertEqual(UnitFormatter.length(inches(11.96), style: .feetInchesTenths), "1' 0.0\"")
    XCTAssertEqual(UnitFormatter.length(inches(11.6), style: .feetInches), "1' 0\"")
    XCTAssertEqual(UnitFormatter.length(inches(120.04), style: .feetInchesTenths), "10' 0.0\"")
    XCTAssertEqual(UnitFormatter.length(0, style: .feetInchesTenths), "0' 0.0\"")
    XCTAssertEqual(UnitFormatter.length(inches(-0.01), style: .feetInchesTenths), "0' 0.0\"")
    XCTAssertEqual(UnitFormatter.length(-inches(74), style: .feetInchesTenths), "-6' 2.0\"")
    XCTAssertEqual(UnitFormatter.length(inches(3712.56), style: .feetInchesTenths), "309' 4.6\"")
    // Halves round away from zero, also after a trip through metres.
    XCTAssertEqual(UnitFormatter.length(inches(201.35), style: .feetInchesTenths), "16' 9.4\"")
    XCTAssertEqual(UnitFormatter.length(inches(0.25), style: .feetInchesTenths), "0' 0.3\"")
    XCTAssertEqual(UnitFormatter.length(.nan, style: .metres), "-")
    XCTAssertEqual(UnitFormatter.length(.infinity, style: .feetInchesTenths), "-")
  }

  func testAreasAndVolumes() {
    let squareFoot = UnitFormatter.squareMetresPerSquareFoot
    let cubicFoot = UnitFormatter.cubicMetresPerCubicFoot
    XCTAssertEqual(UnitFormatter.squareFeet(300.06 * squareFoot), "300.1 ft\u{00B2}")
    XCTAssertEqual(UnitFormatter.squareFeet(785.84 * squareFoot), "785.8 ft\u{00B2}")
    XCTAssertEqual(UnitFormatter.squareFeet(0), "0.0 ft\u{00B2}")
    XCTAssertEqual(UnitFormatter.cubicFeet(6406.51 * cubicFoot), "6406.51 ft\u{00B3}")
    XCTAssertEqual(UnitFormatter.cubicFeet(119.8 * cubicFoot), "119.80 ft\u{00B3}")
    XCTAssertEqual(UnitFormatter.squareMetres(27.8802), "27.88 m\u{00B2}")
    XCTAssertEqual(UnitFormatter.cubicMetres(70.134), "70.13 m\u{00B3}")
    XCTAssertEqual(UnitFormatter.cubicMetres(0.004), "0.00 m\u{00B3}")

    let imperial = UnitFormatter(system: .imperial)
    XCTAssertEqual(imperial.lengthStyle, .feetInchesTenths)
    XCTAssertEqual(imperial.length(inches(73.96)), "6' 2.0\"")
    XCTAssertEqual(imperial.area(300.06 * squareFoot), "300.1 ft\u{00B2}")
    XCTAssertEqual(imperial.volume(6406.51 * cubicFoot), "6406.51 ft\u{00B3}")
    let metric = UnitFormatter(system: .metric)
    XCTAssertEqual(metric.lengthStyle, .metres)
    XCTAssertEqual(metric.length(1.878584), "1.88 m")
    XCTAssertEqual(metric.area(27.8802), "27.88 m\u{00B2}")
    XCTAssertEqual(metric.volume(70.134), "70.13 m\u{00B3}")
    let millimetres = UnitFormatter(system: .metric, lengthStyle: .millimetres)
    XCTAssertEqual(millimetres.length(1.878584), "1879 mm")
  }
}
