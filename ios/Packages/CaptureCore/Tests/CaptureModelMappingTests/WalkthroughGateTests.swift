import CaptureContract
import CaptureTestSupport
import Foundation
import XCTest

@testable import CaptureModelMapping

/// Only walk-throughs are split (floorplan plan, phase 3): every other capture, and a walk-through
/// the splitter cannot split, maps exactly as before. The goldens in `Golden/` are the capture
/// models of the mapper at commit cd97c36, before walk-through splitting.
final class WalkthroughGateTests: XCTestCase {
  private static let goldenDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("Golden", isDirectory: true)

  private static func context() throws -> MappingContext {
    MappingContext(
      visitId: try XCTUnwrap(LowercaseUUID(rawValue: "6f1c2a8e-3b7d-4e59-9a14-2c8d5e7f0b31")),
      captureId: try XCTUnwrap(LowercaseUUID(rawValue: "9d4e7b12-5a3c-4f86-b2e1-7c0a9f3d6e58")),
      areaKey: "floor-1", label: "Floor 1")
  }

  /// Maps `document` and compares it with the golden `name`: the same model, and the same bytes
  /// when both are encoded as the app writes them.
  private func assertMatchesGolden(_ document: RoomPlanDocument, _ name: String) throws {
    let model = try CaptureModelMapper.map(document, context: try Self.context())
    let golden = try CaptureContractJSON.makeDecoder().decode(
      CaptureModel.self, from: Data(contentsOf: Self.goldenDirectory.appendingPathComponent(name)))
    XCTAssertEqual(model, golden, name)
    let encoder = CaptureContractJSON.makeEncoder()
    XCTAssertEqual(try encoder.encode(model), try encoder.encode(golden), name)
  }

  func testFixturesThatAreNotWalkthroughsMapExactlyAsBefore() throws {
    let generated = Fixtures.generatedDirectory
    let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: generated, includingPropertiesForKeys: nil))
    var files: [URL] = []
    for case let url as URL in enumerator
    where url.lastPathComponent == "roomplan.json" && !url.path.contains("/roomplan-only/") {
      files.append(url)
    }
    files.sort { $0.path < $1.path }
    var names: [String] = []
    for file in files {
      let parts = String(file.path.dropFirst(generated.path.count + 1)).components(separatedBy: "/")
      let name = "\(parts.prefix { $0 != "package" }.joined(separator: ".")).\(parts[parts.count - 3]).json"
      names.append(name)
      let document = try RoomPlanDocument.decode(from: Data(contentsOf: file))
      XCTAssertFalse(WalkthroughInput.isWalkthrough(document), name)
      try assertMatchesGolden(document, name)
    }
    XCTAssertEqual(
      names,
      [
        "box-room.floor-1.json", "broken.dimensions-3pct-off.floor-1.json", "broken.empty-file.floor-1.json",
        "broken.inches-as-metres.floor-1.json", "broken.las-bad-header.floor-1.json",
        "broken.missing-gltf-bin.floor-1.json", "broken.wrong-address.floor-1.json",
        "broken.z-up-mesh.floor-1.json", "l-shaped-room.floor-1.json", "two-floor-house.floor-1.json",
        "two-floor-house.floor-2.json", "two-room-apartment.floor-1.json",
      ])
  }

  func testWalkthroughsWithNothingToSplitAlongMapExactlyAsBefore() throws {
    for (name, document) in WalkthroughBuilder.unsplittable {
      XCTAssertTrue(WalkthroughInput.isWalkthrough(document), name)
      let placements = try document.rooms[0].walls.enumerated().map {
        try CaptureModelMapper.wallPlacement($1, id: "wall-\($0 + 1)", roomIndex: 0)
      }
      let result = WalkthroughSplitter.analyze(document: document, placements: placements)
      XCTAssertNil(result.split, name)
      XCTAssertEqual(result.diagnostics.fallbackReason, .singleRoom, name)
      XCTAssertEqual(result.diagnostics.unsplit.count, 1, name)
      try assertMatchesGolden(document, "walkthrough-fallback.\(name).json")
    }
  }

  func testGate() throws {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape)
    builder.addSection("livingRoom", at: (2, 3))
    XCTAssertFalse(WalkthroughInput.isWalkthrough(builder.document), "one section")
    builder.addSection("unidentified", at: (6, 1.5))
    XCTAssertTrue(WalkthroughInput.isWalkthrough(builder.document), "two sections, any label")

    var noCentre = builder
    noCentre.sections[1].center = nil
    XCTAssertFalse(WalkthroughInput.isWalkthrough(noCentre.document), "a section without a centre does not count")

    var otherStory = builder
    otherStory.sections[1].story = 1
    XCTAssertTrue(WalkthroughInput.isWalkthrough(otherStory.document), "sections on any story count")

    let structure = RoomPlanDocument(rooms: builder.document.rooms, isStructure: true)
    XCTAssertFalse(WalkthroughInput.isWalkthrough(structure), "a CapturedStructure")
    let twoRooms = RoomPlanDocument(rooms: builder.document.rooms + builder.document.rooms, isStructure: false)
    XCTAssertFalse(WalkthroughInput.isWalkthrough(twoRooms), "two rooms")

    var noFloor = builder.room
    noFloor.floors = []
    XCTAssertFalse(
      WalkthroughInput.isWalkthrough(RoomPlanDocument(rooms: [noFloor], isStructure: false)), "no floor outline")
    var noWalls = builder.room
    noWalls.walls = []
    XCTAssertFalse(WalkthroughInput.isWalkthrough(RoomPlanDocument(rooms: [noWalls], isStructure: false)), "no walls")
  }

  /// A walk-through throws the errors of every other capture, in the same order: a wall without
  /// length, then an opening without a wall (doors before windows before openings).
  func testWalkthroughErrorsAreTheSameAsBefore() throws {
    var builder = WalkthroughBuilder(outline: WalkthroughBuilder.lShape)
    builder.addWall((4, 0), (4, 3))
    builder.addSection("livingRoom", at: (2, 3))
    builder.addSection("kitchen", at: (6, 1.5))
    let context = try Self.context()
    XCTAssertEqual(try CaptureModelMapper.map(builder.document, context: context).rooms.count, 2)

    var noLength = builder.room
    noLength.walls[2].dimensions[0] = 0
    XCTAssertThrowsError(
      try CaptureModelMapper.map(RoomPlanDocument(rooms: [noLength], isStructure: false), context: context)
    ) {
      XCTAssertEqual($0 as? MappingError, .wallHasNoLength(surface: "WALL-0003"))
    }

    var lost = builder
    lost.addDoor(at: (1, 0), inWall: 0)
    var window = lost.doors[0]
    window.identifier = "WINDOW-0001"
    window.category = RoomPlanCategory(name: "window")
    window.parentIdentifier = nil
    window.transform.columns[3] = [20, 0, 20, 1]
    var door = lost.doors[0]
    door.identifier = "DOOR-0002"
    door.parentIdentifier = "NO-SUCH-WALL"
    door.transform.columns[3] = [30, 0, 30, 1]
    var room = lost.room
    room.windows = [window]
    room.doors.append(door)
    XCTAssertThrowsError(
      try CaptureModelMapper.map(RoomPlanDocument(rooms: [room], isStructure: false), context: context)
    ) {
      XCTAssertEqual($0 as? MappingError, .openingHasNoWall(surface: "DOOR-0002"), "doors first")
    }
    room.doors.removeLast()
    XCTAssertThrowsError(
      try CaptureModelMapper.map(RoomPlanDocument(rooms: [room], isStructure: false), context: context)
    ) {
      XCTAssertEqual($0 as? MappingError, .openingHasNoWall(surface: "WINDOW-0001"))
    }
    // The same capture as a structure (not split) throws the same errors.
    XCTAssertThrowsError(
      try CaptureModelMapper.map(RoomPlanDocument(rooms: [room], isStructure: true), context: context)
    ) {
      XCTAssertEqual($0 as? MappingError, .openingHasNoWall(surface: "WINDOW-0001"))
    }
  }
}
