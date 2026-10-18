import CaptureContract
import CaptureModelMapping
import CaptureTestSupport
import Foundation
import XCTest

/// Whole-apartment walk-through scans: RoomPlan reports the whole apartment as one room. The
/// synthetic fixture runs everywhere; real exports run only on a machine that has them.
final class WalkthroughScanTests: XCTestCase {
  func testSyntheticWalkthroughMapsAsOneRoomWithTheWholeOutline() throws {
    let fixture = try Fixtures.roomPlanOnly("apartment-walkthrough")
    let expected = fixture.expected
    let document = try RoomPlanDocument.decode(from: fixture.roomPlanData())
    XCTAssertFalse(document.isStructure)
    let model = try CaptureModelMapper.map(document, context: try Self.context())

    // Today the mapper keeps a walk-through as one room with the floor outline.
    let room = try XCTUnwrap(model.rooms.first)
    XCTAssertEqual(model.rooms.count, 1)
    XCTAssertEqual(room.polygon.count, expected.totals.outlineCorners)
    let polygon = room.polygon.map { Vector3($0.x, $0.y, $0.z) }
    XCTAssertEqual(PolygonMath.area(polygon), expected.totals.floorAreaM2, accuracy: 0.001)
    XCTAssertLessThan(PolygonMath.signedArea(polygon), 0, "counter-clockwise from +Y")
    XCTAssertTrue(room.polygon.allSatisfy { abs($0.y - expected.frame.floorY) < 1e-5 }, "at floor level")
    XCTAssertTrue(model.walls.allSatisfy { abs($0.start.y - expected.frame.floorY) < 1e-5 }, "walls stand on the floor")

    XCTAssertEqual(model.walls.count, expected.totals.walls)
    XCTAssertEqual(model.doors.count, expected.totals.doors)
    XCTAssertEqual(model.windows.count, expected.totals.windows)
    XCTAssertEqual(model.openings.count, expected.totals.openings)
    XCTAssertEqual(model.objects.count, expected.totals.objects)

    // Each door, window and opening sits in the wall RoomPlan named (walls are numbered in
    // document order).
    let wallIds = Dictionary(
      uniqueKeysWithValues: expected.walls.map { ($0.identifier, "wall-\($0.index + 1)") })
    let mapped = ["door": model.doors, "window": model.windows, "opening": model.openings]
    for opening in expected.openings {
      let mappedOpening = try XCTUnwrap(mapped[opening.kind]?[opening.index], opening.identifier)
      XCTAssertEqual(mappedOpening.wallId, wallIds[opening.wallIdentifier], opening.identifier)
    }
  }

  func testSyntheticWalkthroughKeepsDoorStatesAttributesAndParents() throws {
    let fixture = try Fixtures.roomPlanOnly("apartment-walkthrough")
    let document = try RoomPlanDocument.decode(from: fixture.roomPlanData())
    let model = try CaptureModelMapper.map(document, context: try Self.context())

    // Doors open or closed as RoomPlan saw them; windows and openings carry no isOpen.
    let doors = fixture.expected.openings.filter { $0.kind == "door" }.sorted { $0.index < $1.index }
    XCTAssertEqual(model.doors.map(\.isOpen), doors.map(\.isOpen))
    XCTAssertEqual(model.doors.filter { $0.isOpen == true }.count, fixture.expected.totals.openDoors)
    XCTAssertTrue((model.windows + model.openings).allSatisfy { $0.isOpen == nil })

    // Attributes as RoomPlan wrote them, left out when there are none.
    let raw = document.rooms[0].objects
    XCTAssertEqual(model.objects.map(\.attributes), raw.map { $0.attributes.isEmpty ? nil : $0.attributes })
    XCTAssertTrue(model.objects.contains { $0.category == .storage && $0.attributes?["StorageType"] == "cabinet" })
    XCTAssertTrue(model.objects.contains { $0.category == .table && $0.attributes?["TableType"] == "coffee" })

    // Parents: the model id of the object RoomPlan names (a sink in a cabinet, a chair at a table).
    let idByIdentifier = Dictionary(
      uniqueKeysWithValues: raw.enumerated().map { ($1.identifier, "object-\($0 + 1)") })
    XCTAssertEqual(model.objects.map(\.parentId), raw.map { $0.parentIdentifier.flatMap { idByIdentifier[$0] } })
    XCTAssertEqual(model.objects.compactMap(\.parentId).count, 4)
    let byId = Dictionary(uniqueKeysWithValues: model.objects.map { ($0.id, $0) })
    for object in model.objects where object.category == .sink {
      XCTAssertEqual(object.parentId.flatMap { byId[$0] }?.category, .storage, object.id)
    }

    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
    XCTAssertEqual(validator.validate(try encodedJSON(model)), [])
  }

  /// Real RoomPlan exports kept on this machine only (they are never committed). Set
  /// CHAPTER_REAL_ROOMPLAN_DIR to a folder; every `roomplan.json` below it must decode with
  /// `RoomPlanDocument`, map with `CaptureModelMapper` and validate against the schema:
  ///
  ///   CHAPTER_REAL_ROOMPLAN_DIR="/path/to/exports" \
  ///     swift test --package-path ios/Packages/CaptureCore --filter WalkthroughScanTests
  ///
  /// Skipped when the variable is not set (CI and every other machine).
  func testRealExportsDecodeAndMap() throws {
    guard let path = ProcessInfo.processInfo.environment["CHAPTER_REAL_ROOMPLAN_DIR"], !path.isEmpty
    else {
      throw XCTSkip("CHAPTER_REAL_ROOMPLAN_DIR is not set; point it at a folder of real RoomPlan exports to run this test")
    }
    let root = URL(fileURLWithPath: path, isDirectory: true)
    let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var files: [URL] = []
    for case let url as URL in enumerator where url.lastPathComponent == "roomplan.json" {
      files.append(url)
    }
    files.sort { $0.path < $1.path }
    XCTAssertFalse(files.isEmpty, "no roomplan.json under \(path)")

    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
    for file in files {
      let name = String(file.path.dropFirst(root.path.count))
      do {
        let document = try RoomPlanDocument.decode(from: Data(contentsOf: file))
        let model = try CaptureModelMapper.map(document, context: try Self.context())
        XCTAssertFalse(model.rooms.isEmpty, name)
        XCTAssertFalse(model.walls.isEmpty, name)
        XCTAssertEqual(validator.validate(try encodedJSON(model)), [], name)
        print(
          "\(name): \(document.rooms.count) RoomPlan room(s) -> \(model.rooms.count) room(s), "
            + "\(model.walls.count) walls, \(model.doors.count) doors, \(model.windows.count) windows, "
            + "\(model.openings.count) openings, \(model.objects.count) objects")

        XCTAssertTrue(model.doors.allSatisfy { $0.isOpen != nil }, "\(name): RoomPlan reports isOpen on every door")
        let objectIds = Set(model.objects.map(\.id))
        XCTAssertTrue(model.objects.allSatisfy { $0.parentId.map(objectIds.contains) ?? true }, name)
        print(
          "  \(model.doors.filter { $0.isOpen == true }.count) of \(model.doors.count) doors open, "
            + "\(model.objects.filter { $0.attributes != nil }.count) objects with attributes, "
            + "\(model.objects.filter { $0.parentId != nil }.count) with a parent")
      } catch {
        XCTFail("\(name): \(error)")
      }
    }
  }

  private static func context() throws -> MappingContext {
    MappingContext(
      visitId: try XCTUnwrap(LowercaseUUID(rawValue: "6f1c2a8e-3b7d-4e59-9a14-2c8d5e7f0b31")),
      captureId: try XCTUnwrap(LowercaseUUID(rawValue: "9d4e7b12-5a3c-4f86-b2e1-7c0a9f3d6e58")),
      areaKey: "apartment", label: "Apartment")
  }
}
