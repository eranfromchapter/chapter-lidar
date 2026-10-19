import CaptureContract
import CaptureModelMapping
import CaptureTestSupport
import Foundation
import XCTest

/// Whole-apartment walk-through scans: RoomPlan reports the whole apartment as one room, and the
/// mapper splits it into rooms (floorplan plan, phase 3). The synthetic fixture runs everywhere;
/// real exports run only on a machine that has them.
final class WalkthroughScanTests: XCTestCase {
  private func mapFixture() throws -> (
    fixture: RoomPlanOnlyFixture, document: RoomPlanDocument, model: CaptureModel, split: WalkthroughSplitter.Split
  ) {
    let fixture = try Fixtures.roomPlanOnly("apartment-walkthrough")
    let document = try RoomPlanDocument.decode(from: fixture.roomPlanData())
    let model = try CaptureModelMapper.map(document, context: try Walkthrough.context())
    let split = try XCTUnwrap(try Walkthrough.split(document))
    return (fixture, document, model, split)
  }

  /// Our room id for each room id of expected.json: the room that contains the expected room's
  /// section, and the closet (which has no section) by its type.
  private func roomMatch(
    _ expected: RoomPlanOnlyFixture.Expected, _ document: RoomPlanDocument, _ model: CaptureModel
  ) throws -> [String: String] {
    var match: [String: String] = [:]
    for section in expected.sections {
      let center = try XCTUnwrap(document.rooms[0].sections[section.index].center)
      let ours = model.rooms.filter { PolygonMath.contains($0.polygon.map { Vector3($0.x, $0.y, $0.z) }, center) }
      XCTAssertEqual(ours.count, 1, "section \(section.index) is in exactly one room")
      match[section.roomId] = ours.first?.id
    }
    match["closet"] = model.rooms.first { $0.type == .closet }?.id
    XCTAssertEqual(Set(match.values).count, expected.rooms.count)
    return match
  }

  func testSyntheticWalkthroughSplitsIntoRooms() throws {
    let (fixture, document, model, _) = try mapFixture()
    let expected = fixture.expected
    XCTAssertFalse(document.isStructure)
    XCTAssertEqual(model.rooms.count, 7)
    XCTAssertEqual(
      model.rooms.map(\.label), ["Bedroom 1", "Kitchen", "Living Room", "Hallway", "Bathroom", "Bedroom 2", "Closet"])
    XCTAssertEqual(model.rooms.map(\.type), [.bedroom, .kitchen, .livingRoom, .hallway, .bathroom, .bedroom, .closet])
    XCTAssertEqual(
      model.rooms.map(\.typeSource),
      [.roomplanSection, .roomplanSection, .roomplanSection, .inferred, .roomplanSection, .roomplanSection, .inferred])

    let match = try roomMatch(expected, document, model)
    var areaSum = 0.0
    for expectedRoom in expected.rooms {
      let room = try XCTUnwrap(model.rooms.first { $0.id == match[expectedRoom.id] }, expectedRoom.id)
      let polygon = room.polygon.map { Vector3($0.x, $0.y, $0.z) }
      let truth = expectedRoom.polygon.map { Vector3($0[0], expected.frame.floorY, $0[1]) }
      XCTAssertEqual(polygon.count, truth.count, expectedRoom.id)
      XCTAssertLessThanOrEqual(Walkthrough.hausdorff(polygon, truth), 1e-5, expectedRoom.id)
      XCTAssertEqual(PolygonMath.area(polygon), expectedRoom.areaM2, accuracy: 1e-4, expectedRoom.id)
      XCTAssertLessThan(PolygonMath.signedArea(polygon), 0, "\(expectedRoom.id) is counter-clockwise from +Y")
      XCTAssertTrue(
        polygon.allSatisfy { abs($0.y - expected.frame.floorY) < 1e-6 }, "\(expectedRoom.id) at floor level")
      XCTAssertEqual(room.type?.rawValue, expectedRoom.type, expectedRoom.id)
      areaSum += PolygonMath.area(polygon)
    }
    XCTAssertEqual(areaSum, expected.totals.floorAreaM2, accuracy: 1e-4)
    XCTAssertTrue(model.rooms.allSatisfy { $0.heightM == 2.49 }, "every room is as high as its walls")

    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
    XCTAssertEqual(validator.validate(try encodedJSON(model)), [])
  }

  func testSyntheticWalkthroughWallsOpeningsAndObjects() throws {
    let (fixture, document, model, split) = try mapFixture()
    let expected = fixture.expected
    let match = try roomMatch(expected, document, model)
    let expectedId = Dictionary(uniqueKeysWithValues: match.map { ($1, $0) })

    // Walls: only source wall 20 runs past a room junction (the living room and the kitchen both
    // open onto the hall through it); later ids shift by one.
    XCTAssertEqual(model.walls.count, 32)
    XCTAssertEqual(split.wallPieces.map(\.sourceWall), Array(0...20) + [20] + Array(21...30))
    XCTAssertEqual(model.walls[20].roomIds, ["room-3", "room-4"])
    XCTAssertEqual(model.walls[21].roomIds, ["room-2", "room-4"])
    XCTAssertEqual(split.wallPieces[20].endM - split.wallPieces[20].startM, 2.5, accuracy: 1e-6)
    XCTAssertEqual(split.wallPieces[21].endM - split.wallPieces[21].startM, 0.7, accuracy: 1e-6)
    let placements = try Walkthrough.placements(document)
    for expectedWall in expected.walls {
      let pieces = split.wallPieces.indices.filter { split.wallPieces[$0].sourceWall == expectedWall.index }
      let rooms = Set(pieces.flatMap { model.walls[$0].roomIds ?? [] }).compactMap { expectedId[$0] }.sorted()
      XCTAssertEqual(rooms, expectedWall.roomIds.sorted(), "wall \(expectedWall.index)")
      var length = 0.0
      for piece in pieces { length += split.wallPieces[piece].endM - split.wallPieces[piece].startM }
      XCTAssertEqual(length, placements[expectedWall.index].lengthM, accuracy: 1e-6)
      for (a, b) in zip(pieces, pieces.dropFirst()) {
        XCTAssertNotEqual(
          model.walls[a].roomIds, model.walls[b].roomIds, "neighbouring pieces of wall \(expectedWall.index)")
      }
    }
    XCTAssertTrue(model.walls.allSatisfy { abs($0.start.y - expected.frame.floorY) < 1e-5 }, "walls stand on the floor")
    // Each piece lies on its source wall, from startM to endM, and the pieces of one wall meet.
    for (index, piece) in split.wallPieces.enumerated() {
      let wall = placements[piece.sourceWall]
      for (point, along) in [(piece.start, piece.startM), (piece.end, piece.endM)] {
        let truth = wall.start + (wall.end - wall.start) * (along / wall.lengthM)
        XCTAssertEqual((point - truth).length, 0, accuracy: 1e-9, "piece \(index)")
      }
      if index > 0, split.wallPieces[index - 1].sourceWall == piece.sourceWall {
        XCTAssertEqual(model.walls[index - 1].end, model.walls[index].start, "pieces \(index) and \(index + 1)")
      }
    }
    XCTAssertEqual(model.walls[20].end, model.walls[21].start)
    XCTAssertTrue(split.rooms.allSatisfy(\.heightFromWalls))
    XCTAssertEqual(model.walls.map(\.heightM), split.wallPieces.map { placements[$0.sourceWall].heightM })
    XCTAssertEqual(
      model.walls.map(\.thicknessM),
      split.wallPieces.map { max(0, document.rooms[0].walls[$0.sourceWall].dimensions[2]) })

    // Openings: on the piece of their wall, with the offset from the piece start.
    XCTAssertEqual(model.doors.count, expected.totals.doors)
    XCTAssertEqual(model.windows.count, expected.totals.windows)
    XCTAssertEqual(model.openings.count, expected.totals.openings)
    let placed: [(String, Double)] =
      (model.doors + model.windows + model.openings).map { ($0.wallId, $0.offsetM) }
    let truth: [(String, Double)] = [
      ("wall-26", 0.58), ("wall-28", 0.62), ("wall-1", 1.2), ("wall-25", 0.5), ("wall-7", 0.6),
      ("wall-24", 1.2), ("wall-20", 1.7), ("wall-3", 1.6), ("wall-30", 1.0), ("wall-21", 1.1),
    ]
    for (index, (wallId, offset)) in placed.enumerated() {
      XCTAssertEqual(wallId, truth[index].0, "opening \(index)")
      XCTAssertEqual(offset, truth[index].1, accuracy: 1e-4, "opening \(index)")
    }
    let mapped = ["door": model.doors, "window": model.windows, "opening": model.openings]
    for opening in expected.openings {
      let mappedOpening = try XCTUnwrap(mapped[opening.kind]?[opening.index], opening.identifier)
      let wall = try XCTUnwrap(model.walls.first { $0.id == mappedOpening.wallId })
      XCTAssertEqual(
        (wall.roomIds ?? []).compactMap { expectedId[$0] }.sorted(), opening.roomIds.sorted(), opening.identifier)
      // The piece is a piece of the wall RoomPlan named.
      let piece = try XCTUnwrap(model.walls.firstIndex { $0.id == mappedOpening.wallId })
      XCTAssertEqual(document.rooms[0].walls[split.wallPieces[piece].sourceWall].identifier, opening.wallIdentifier)
    }
    XCTAssertTrue(split.diagnostics.straddlingOpenings.isEmpty)

    // Objects: in the room they stand in.
    XCTAssertEqual(model.objects.count, expected.totals.objects)
    for expectedRoom in expected.rooms {
      for object in expectedRoom.objects {
        XCTAssertEqual(model.objects[object.index].roomId, match[expectedRoom.id], "\(object.category) \(object.index)")
      }
    }
  }

  func testSyntheticWalkthroughOpeningsAndObjectsMatchTheCaptureMappedWhole() throws {
    // The same capture as a CapturedStructure is not split. Every field of an opening or object
    // must be the same except where it is (wall, offset along it, room).
    let (_, document, model, _) = try mapFixture()
    let whole = try CaptureModelMapper.map(
      RoomPlanDocument(rooms: document.rooms, isStructure: true), context: try Walkthrough.context())
    XCTAssertEqual(whole.rooms.count, 1)
    func placeless(_ openings: [CaptureModel.WallOpening]) -> [CaptureModel.WallOpening] {
      openings.map {
        var opening = $0
        opening.wallId = ""
        opening.offsetM = 0
        return opening
      }
    }
    XCTAssertEqual(placeless(model.doors), placeless(whole.doors))
    XCTAssertEqual(placeless(model.windows), placeless(whole.windows))
    XCTAssertEqual(placeless(model.openings), placeless(whole.openings))
    XCTAssertTrue(model.windows.allSatisfy { $0.bottomM > 0.5 }, "the windows have sills")
    XCTAssertEqual(
      model.objects.map { object -> CaptureModel.DetectedObject in
        var object = object
        object.roomId = nil
        return object
      },
      whole.objects.map { object -> CaptureModel.DetectedObject in
        var object = object
        object.roomId = nil
        return object
      })
  }

  func testSyntheticWalkthroughRoomsAreAsHighAsTheirWalls() throws {
    let fixture = try Fixtures.roomPlanOnly("apartment-walkthrough")
    let document = try RoomPlanDocument.decode(from: fixture.roomPlanData())
    let floorY = fixture.expected.frame.floorY
    func withHeights(_ height: (Int) -> Double) -> RoomPlanDocument {
      var changed = document
      for index in changed.rooms[0].walls.indices {
        let h = height(index)
        changed.rooms[0].walls[index].dimensions[1] = h
        changed.rooms[0].walls[index].transform.columns[3][1] = floorY + h / 2
      }
      return changed
    }
    let context = try Walkthrough.context()
    // Implausible heights stay as measured, as when the capture is not split, so the station
    // flags them instead of seeing 2.0 or 6.0 m.
    for h in [1.95, 6.4] {
      let changed = withHeights { _ in h }
      let model = try CaptureModelMapper.map(changed, context: context)
      let whole = try CaptureModelMapper.map(
        RoomPlanDocument(rooms: changed.rooms, isStructure: true), context: context)
      XCTAssertEqual(model.rooms.count, 7)
      XCTAssertEqual(model.rooms.map(\.heightM), Array(repeating: h, count: 7))
      XCTAssertEqual(whole.rooms.map(\.heightM), [h])
      XCTAssertTrue(try XCTUnwrap(try Walkthrough.split(changed)).rooms.allSatisfy(\.heightFromWalls))
    }
    // One 6.4 m outline wall: the room it bounds takes it, the others keep their 2.49 m.
    let tallWall = 2
    let bedroom = try XCTUnwrap(fixture.expected.walls.first { $0.index == tallWall }?.roomIds.first)
    let changed = withHeights { $0 == tallWall ? 6.4 : 2.49 }
    let model = try CaptureModelMapper.map(changed, context: context)
    let match = try roomMatch(fixture.expected, changed, model)
    for room in model.rooms {
      XCTAssertEqual(room.heightM, room.id == match[bedroom] ? 6.4 : 2.49, room.label)
    }
  }

  func testSyntheticWalkthroughKeepsDoorStatesAttributesAndParents() throws {
    let fixture = try Fixtures.roomPlanOnly("apartment-walkthrough")
    let document = try RoomPlanDocument.decode(from: fixture.roomPlanData())
    let model = try CaptureModelMapper.map(document, context: try Walkthrough.context())

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

    // Parents: the model id of the object RoomPlan names (a sink in a cabinet, a chair at a table),
    // and in the same room.
    let idByIdentifier = Dictionary(
      uniqueKeysWithValues: raw.enumerated().map { ($1.identifier, "object-\($0 + 1)") })
    XCTAssertEqual(model.objects.map(\.parentId), raw.map { $0.parentIdentifier.flatMap { idByIdentifier[$0] } })
    XCTAssertEqual(model.objects.compactMap(\.parentId).count, 4)
    let byId = Dictionary(uniqueKeysWithValues: model.objects.map { ($0.id, $0) })
    for object in model.objects where object.category == .sink {
      XCTAssertEqual(object.parentId.flatMap { byId[$0] }?.category, .storage, object.id)
    }
    for object in model.objects {
      guard let parent = object.parentId.flatMap({ byId[$0] }) else { continue }
      XCTAssertEqual(object.roomId, parent.roomId, object.id)
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
    let validator = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
    for (name, url) in try Self.realExports() {
      do {
        let document = try RoomPlanDocument.decode(from: Data(contentsOf: url))
        let model = try CaptureModelMapper.map(document, context: try Walkthrough.context())
        XCTAssertFalse(model.rooms.isEmpty, name)
        XCTAssertFalse(model.walls.isEmpty, name)
        XCTAssertEqual(validator.validate(try encodedJSON(model)), [], name)
        print(
          "\(name): \(document.rooms.count) RoomPlan room(s) -> \(model.rooms.count) room(s), "
            + "\(model.walls.count) walls, \(model.doors.count) doors, \(model.windows.count) windows, "
            + "\(model.openings.count) openings, \(model.objects.count) objects")

        // Room names: unique labels; a type comes with its source; a room whose sections name two
        // or more types carries the capture label and no type, and a room whose sections name one
        // type has that type.
        XCTAssertEqual(Set(model.rooms.map(\.label)).count, model.rooms.count, name)
        let sections = document.rooms.flatMap(\.sections) + document.sections
        for room in model.rooms {
          XCTAssertFalse(room.label.isEmpty, name)
          XCTAssertEqual(room.type == nil, room.typeSource == nil, name)
          let polygon = room.polygon.map { Vector3($0.x, $0.y, $0.z) }
          let inside = sections.filter { $0.center.map { PolygonMath.contains(polygon, $0) } ?? false }
          let types = inside.compactMap(\.roomType)
          if types.count > 1 {
            XCTAssertTrue(room.label.hasPrefix("Apartment"), name)
            XCTAssertNil(room.type, name)
          } else if let type = types.first {
            XCTAssertEqual(room.type, type, name)
            XCTAssertEqual(room.typeSource, .roomplanSection, name)
          }
          let area = PolygonMath.area(polygon)
          print(
            "  \(room.id) \"\(room.label)\": type \(room.type?.rawValue ?? "none")"
              + " (\(room.typeSource?.rawValue ?? "-")), \(String(format: "%.2f", area)) m2, height \(room.heightM),"
              + " sections \(inside.map(\.label))")
        }

        XCTAssertTrue(model.doors.allSatisfy { $0.isOpen != nil }, "\(name): RoomPlan reports isOpen on every door")
        let objectIds = Set(model.objects.map(\.id))
        XCTAssertTrue(model.objects.allSatisfy { $0.parentId.map(objectIds.contains) ?? true }, name)
        let roomIds = Set(model.rooms.map(\.id))
        XCTAssertTrue(model.objects.allSatisfy { $0.roomId.map(roomIds.contains) ?? false }, name)
        XCTAssertTrue(
          model.walls.allSatisfy { !($0.roomIds ?? []).isEmpty && Set($0.roomIds ?? []).isSubset(of: roomIds) }, name)
        print(
          "  \(model.doors.filter { $0.isOpen == true }.count) of \(model.doors.count) doors open, "
            + "\(model.objects.filter { $0.attributes != nil }.count) objects with attributes, "
            + "\(model.objects.filter { $0.parentId != nil }.count) with a parent")
      } catch {
        XCTFail("\(name): \(error)")
      }
    }
  }

  /// The two real walk-throughs of one apartment that the splitting was tuned on (phase 3 spec),
  /// recognized by their walls and sections. Areas within 0.01 m2; ids, types and labels exact.
  func testRealWalkthroughsSplitAsExpected() throws {
    struct Expected {
      var rooms: [(label: String, type: RoomType?, source: RoomTypeSource?, area: Double)]
      var margins: [(margin: Double, approximate: Bool)]
    }
    let exportA = Expected(
      rooms: [
        ("Bedroom 1", .bedroom, .roomplanSection, 18.4823), ("Bedroom 2", .bedroom, .roomplanSection, 14.5296),
        ("Kitchen", .kitchen, .roomplanSection, 4.7008), ("Living Room", .livingRoom, .inferred, 29.7242),
        ("Bathroom", .bathroom, .roomplanSection, 3.3268), ("Room 6", nil, nil, 3.5098),
      ], margins: [])
    let exportB = Expected(
      rooms: [
        ("Living Room", .livingRoom, .roomplanSection, 27.5564), ("Bedroom", .bedroom, .roomplanSection, 14.4809),
        ("Bathroom", .bathroom, .roomplanSection, 3.2893), ("Kitchen", .kitchen, .inferred, 4.6983),
      ], margins: [(0.432, true), (1.654, false)])
    var seen: [String] = []
    for (name, url) in try Self.realExports() {
      let document = try RoomPlanDocument.decode(from: Data(contentsOf: url))
      guard document.rooms.count == 1 else { continue }
      let labels = document.rooms[0].sections.map(\.label)
      let expected: Expected
      switch (document.rooms[0].walls.count, labels) {
      case (36, ["bedroom", "bedroom", "kitchen", "unidentified", "bathroom"]):
        expected = exportA
        seen.append("A")
      case (24, ["livingRoom", "bedroom", "bathroom"]):
        expected = exportB
        seen.append("B")
      default:
        continue
      }
      let model = try CaptureModelMapper.map(document, context: try Walkthrough.context())
      XCTAssertEqual(model.rooms.map(\.id), expected.rooms.indices.map { "room-\($0 + 1)" }, name)
      XCTAssertEqual(model.rooms.map(\.label), expected.rooms.map(\.label), name)
      XCTAssertEqual(model.rooms.map(\.type), expected.rooms.map(\.type), name)
      XCTAssertEqual(model.rooms.map(\.typeSource), expected.rooms.map(\.source), name)
      for (room, truth) in zip(model.rooms, expected.rooms) {
        XCTAssertEqual(
          PolygonMath.area(room.polygon.map { Vector3($0.x, $0.y, $0.z) }), truth.area, accuracy: 0.01,
          "\(name) \(room.label)")
      }
      XCTAssertEqual(model.walls.count, document.rooms[0].walls.count, "\(name): no wall runs past a room junction")
      let diagnostics = try Walkthrough.analyze(document).diagnostics
      XCTAssertEqual(diagnostics.cuts.count, expected.margins.count, name)
      for (cut, truth) in zip(diagnostics.cuts, expected.margins) {
        XCTAssertEqual(try XCTUnwrap(cut.margin), truth.margin, accuracy: 0.02, "\(name) \(cut.tag)")
        XCTAssertEqual(cut.approximate, truth.approximate, "\(name) \(cut.tag)")
      }
      if expected.rooms.count == 6 {
        // The room without a section is closed off by joining two wall stubs 0.86 m apart.
        XCTAssertEqual(diagnostics.enclosures.map(\.tag), ["stub-stub"], name)
        XCTAssertEqual(try XCTUnwrap(diagnostics.enclosures.first).virtualLengthM, 0.861, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(diagnostics.enclosures.first).wallLengthM, 2.939, accuracy: 0.001)
        // A section names the kitchen, so its appliances add no seed.
        XCTAssertEqual(diagnostics.objectSeeds, 0, name)
      } else {
        // No section names the kitchen; its refrigerator and stove do.
        XCTAssertEqual(diagnostics.objectSeeds, 1, name)
        let byId = Dictionary(uniqueKeysWithValues: model.objects.map { ($0.id, $0) })
        let chairs = model.objects.filter { $0.category == .chair && $0.parentId != nil }
        XCTAssertEqual(chairs.count, 4, name)
        XCTAssertTrue(chairs.allSatisfy { $0.roomId == "room-4" && byId[$0.parentId!]?.roomId == "room-4" }, name)
      }
    }
    print("real walk-throughs checked: \(seen)")
    // A folder of other exports is fine for testRealExportsDecodeAndMap; here it checks nothing,
    // which must not read as a pass.
    if seen.isEmpty {
      throw XCTSkip("neither real walk-through A nor B is under CHAPTER_REAL_ROOMPLAN_DIR")
    }
  }

  /// The `roomplan.json` files under CHAPTER_REAL_ROOMPLAN_DIR, by path; skips the test when the
  /// variable is not set.
  private static func realExports() throws -> [(name: String, url: URL)] {
    guard let path = ProcessInfo.processInfo.environment["CHAPTER_REAL_ROOMPLAN_DIR"], !path.isEmpty
    else {
      throw XCTSkip(
        "CHAPTER_REAL_ROOMPLAN_DIR is not set; point it at a folder of real RoomPlan exports to run this test")
    }
    let root = URL(fileURLWithPath: path, isDirectory: true)
    let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var files: [URL] = []
    for case let url as URL in enumerator where url.lastPathComponent == "roomplan.json" {
      files.append(url)
    }
    files.sort { $0.path < $1.path }
    XCTAssertFalse(files.isEmpty, "no roomplan.json under \(path)")
    return files.map { (String($0.path.dropFirst(root.path.count)), $0) }
  }
}
