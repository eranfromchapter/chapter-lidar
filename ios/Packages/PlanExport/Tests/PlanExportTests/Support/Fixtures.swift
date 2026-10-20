import CaptureContract
import CaptureModelMapping
import Foundation
import PlanExport
import XCTest

/// Locations inside the repository, found from this file's path.
enum Repo {
  /// Repository root: the folder that holds `fixtures/generated/index.json`.
  static let root: URL = {
    var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while url.path != "/" {
      if FileManager.default.fileExists(
        atPath: url.appendingPathComponent("fixtures/generated/index.json").path)
      {
        return url
      }
      url.deleteLastPathComponent()
    }
    fatalError("fixtures/generated/index.json not found above \(#filePath)")
  }()

  static let packageRoot = root.appendingPathComponent("ios/Packages/PlanExport")

  /// Every generated file is written here so scripts/verify-exports.sh can check it.
  static let testOutput: URL = {
    let url = packageRoot.appendingPathComponent(".build/test-output")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  /// Writes `file` to `.build/test-output/<folder>/<fileName>`.
  @discardableResult
  static func write(_ file: ExportedFile, folder: String) throws -> URL {
    let directory = testOutput.appendingPathComponent(folder)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(file.fileName)
    try file.data.write(to: url)
    return url
  }
}

struct Truth: Decodable {
  struct Room: Decodable {
    var id: String
    var label: String
    var widthM: Double
    var lengthM: Double
    var heightM: Double
    var areaM2: Double
    var perimeterM: Double
  }
  struct Wall: Decodable {
    var id: String
    var lengthM: Double
  }
  struct Opening: Decodable {
    var id: String
    var kind: String
    var wallId: String
    var widthM: Double
  }
  struct Capture: Decodable {
    var captureId: String
    var areaKey: String
    var label: String
    var rooms: [Room]
    var walls: [Wall]
    var openings: [Opening]
  }
  var captures: [Capture]
}

/// One capture of a generated fixture with its model, record and truth.
struct FixtureCapture {
  var fixture: String
  var model: CaptureModel
  var record: CaptureRecord
  var truth: Truth.Capture

  /// Folder name for test output.
  var outputFolder: String { "\(fixture)/\(truth.areaKey)" }
}

enum Fixtures {
  static let names = ["box-room", "l-shaped-room", "two-room-apartment", "two-floor-house"]

  static func load(_ name: String) throws -> [FixtureCapture] {
    let base = Repo.root.appendingPathComponent("fixtures/generated/\(name)")
    let truth = try JSONDecoder().decode(
      Truth.self, from: Data(contentsOf: base.appendingPathComponent("truth.json")))
    let package = base.appendingPathComponent("package")
    let register = package.appendingPathComponent("Source Register")
    let visitFolder = try XCTUnwrap(
      FileManager.default.contentsOfDirectory(atPath: register.path).first)
    let record = try CaptureContractJSON.makeDecoder().decode(
      CaptureRecord.self,
      from: Data(
        contentsOf: register.appendingPathComponent("\(visitFolder)/capture-record.json")))
    return try truth.captures.map { capture in
      let url = package.appendingPathComponent(
        "Original Exports/\(capture.areaKey)/\(capture.captureId)/capture-model.json")
      let model = try CaptureContractJSON.makeDecoder().decode(
        CaptureModel.self, from: Data(contentsOf: url))
      return FixtureCapture(fixture: name, model: model, record: record, truth: capture)
    }
  }

  static func all() throws -> [FixtureCapture] {
    try names.flatMap { try load($0) }
  }
}

/// The synthetic whole-apartment walk-through (fixtures/generated/roomplan-only), mapped and
/// split into rooms by CaptureModelMapping as the app does: 7 rooms, interior walls that stop
/// short of their junctions, an open kitchen, doors, windows and 24 objects.
enum WalkthroughFixture {
  static let model: CaptureModel = {
    let url = Repo.root.appendingPathComponent(
      "fixtures/generated/roomplan-only/apartment-walkthrough/roomplan.json")
    do {
      let document = try RoomPlanDocument.decode(from: Data(contentsOf: url))
      return try CaptureModelMapper.map(
        document,
        context: MappingContext(
          visitId: LowercaseUUID(rawValue: "c1b6d1fb-17af-4f4a-877c-2565ef9bdb86")!,
          captureId: LowercaseUUID(rawValue: "22bfb513-226d-4eca-bde1-0b6cb0c84aad")!,
          areaKey: "apartment", label: "Apartment"))
    } catch {
      fatalError("apartment walk-through fixture: \(error)")
    }
  }()
}

/// A small model for synthetic cases: one rectangular room with four walls.
enum Synthetic {
  /// Rooms from outlines in model metres (x, z), with a wall along every room edge (shared
  /// edges once) and, when given, a door on the wall from `door.from` to `door.to`.
  static func rooms(
    _ rooms: [(label: String, type: RoomType, outline: [(Double, Double)])],
    door: (from: (Double, Double), to: (Double, Double))? = nil
  ) -> CaptureModel {
    var model = room(width: 1, length: 1)
    model.rooms = rooms.enumerated().map { index, room in
      CaptureModel.Room(
        id: "room-\(index + 1)", label: room.label,
        polygon: room.outline.map { Vec3(x: $0.0, y: 0, z: $0.1) }, heightM: 2.7,
        type: room.type, typeSource: .operator)
    }
    model.walls = []
    var seen: [((Double, Double), (Double, Double))] = []
    for room in rooms {
      for index in room.outline.indices {
        let a = room.outline[index]
        let b = room.outline[(index + 1) % room.outline.count]
        guard !seen.contains(where: { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) })
        else { continue }
        seen.append((a, b))
        model.walls.append(
          CaptureModel.Wall(
            id: "wall-\(model.walls.count + 1)", start: Vec3(x: a.0, y: 0, z: a.1),
            end: Vec3(x: b.0, y: 0, z: b.1), heightM: 2.7, thicknessM: 0))
      }
    }
    if let door {
      let index = seen.firstIndex {
        ($0.0 == door.from && $0.1 == door.to) || ($0.0 == door.to && $0.1 == door.from)
      }!
      let wall = model.walls[index]
      let length = hypot(door.to.0 - door.from.0, door.to.1 - door.from.1)
      model.doors = [
        CaptureModel.WallOpening(
          id: "door-1", wallId: wall.id, offsetM: length / 2, bottomM: 0, widthM: length,
          heightM: 2)
      ]
    }
    return model
  }

  /// Rooms side by side along x, each `length` deep, with one wall per edge.
  static func twoRooms(widths: [Double], length: Double) -> CaptureModel {
    var x = 0.0
    var outlines: [(label: String, type: RoomType, outline: [(Double, Double)])] = []
    for (index, width) in widths.enumerated() {
      outlines.append(
        ("Room \(index + 1)", .bedroom, [(x, 0), (x, length), (x + width, length), (x + width, 0)])
      )
      x += width
    }
    return rooms(outlines)
  }

  static func room(width: Double, length: Double, label: String = "Room", id: String = "room-1")
    -> CaptureModel
  {
    let corners = [(0.0, 0.0), (0.0, length), (width, length), (width, 0.0)]
    let polygon = corners.map { Vec3(x: $0.0, y: 0, z: $0.1) }
    var walls: [CaptureModel.Wall] = []
    for index in corners.indices {
      let a = corners[index]
      let b = corners[(index + 1) % corners.count]
      walls.append(
        CaptureModel.Wall(
          id: "wall-\(index + 1)", start: Vec3(x: a.0, y: 0, z: a.1),
          end: Vec3(x: b.0, y: 0, z: b.1), heightM: 2.7, thicknessM: 0, roomIds: [id]))
    }
    return CaptureModel(
      visitId: LowercaseUUID(rawValue: "c1b6d1fb-17af-4f4a-877c-2565ef9bdb86")!,
      captureId: LowercaseUUID(rawValue: "22bfb513-226d-4eca-bde1-0b6cb0c84aad")!,
      areaKey: "floor-1", label: "Floor 1",
      rooms: [CaptureModel.Room(id: id, label: label, polygon: polygon, heightM: 2.7)],
      walls: walls)
  }
}
