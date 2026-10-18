import Foundation

/// A RoomPlan-only fixture (`fixtures/generated/roomplan-only/<name>`): one raw RoomPlan export
/// (`roomplan.json`) and its ground truth (`expected.json`), with no intake package around it.
/// `apartment-walkthrough` is a whole apartment scanned as one `CapturedRoom`, shaped like a real
/// iPhone export (see fixtures/generator/src/walkthrough.ts).
public struct RoomPlanOnlyFixture: Sendable {
  public let name: String
  public let directory: URL
  public let expected: Expected

  init(name: String) throws {
    self.name = name
    directory = Fixtures.roomPlanOnlyDirectory.appendingPathComponent(name, isDirectory: true)
    expected = try JSONDecoder().decode(
      Expected.self, from: Data(contentsOf: directory.appendingPathComponent("expected.json")))
  }

  /// The RoomPlan Codable JSON as committed.
  public func roomPlanData() throws -> Data {
    try Data(contentsOf: directory.appendingPathComponent("roomplan.json"))
  }

  /// `expected.json`. Plan points are [x, z] in metres in the capture frame of `roomplan.json`,
  /// at floor level `frame.floorY`. Indexes count in document order of `roomplan.json`.
  public struct Expected: Decodable, Sendable {
    public let fixture: String
    public let frame: Frame
    public let totals: Totals
    public let rooms: [Room]
    public let sections: [Section]
    public let walls: [Wall]
    public let openings: [Opening]
  }

  public struct Frame: Decodable, Sendable {
    /// Floor level in the capture frame (below the capture origin, as on a device).
    public let floorY: Double
    public let yawDeg: Double
    public let layoutOrigin: [Double]
  }

  public struct Totals: Decodable, Sendable {
    public let floorAreaM2: Double
    public let outlineCorners: Int
    public let outlinePerimeterM: Double
    public let outlineWithoutWallM: Double
    public let outlineWithoutWallFraction: Double
    public let walls: Int
    public let outlineWalls: Int
    public let interiorWalls: Int
    public let shortInteriorWallEnds: Int
    public let doors: Int
    public let openDoors: Int
    public let windows: Int
    public let openings: Int
    public let objects: Int
    public let sections: Int
  }

  /// One intended room of the scan.
  public struct Room: Decodable, Sendable {
    public let id: String
    public let label: String
    /// `living_room`, `kitchen`, `bedroom`, `bathroom`, `closet` or `hallway`.
    public let type: String
    public let areaM2: Double
    /// Counter-clockwise seen from +Y, first point not repeated.
    public let polygon: [[Double]]
    /// The RoomPlan section inside the room; nil when RoomPlan labelled none (a closet).
    public let section: SectionRef?
    public let objects: [ObjectRef]
  }

  public struct SectionRef: Decodable, Sendable {
    public let index: Int
    public let label: String
  }

  public struct ObjectRef: Decodable, Sendable {
    public let index: Int
    public let identifier: String
    public let category: String
  }

  public struct Section: Decodable, Sendable {
    public let index: Int
    public let label: String
    public let roomId: String
  }

  public struct Wall: Decodable, Sendable {
    public let index: Int
    public let identifier: String
    /// `outline` (on the floor outline) or `interior`.
    public let kind: String
    /// Rooms on either side of the wall.
    public let roomIds: [String]
    public let shortEnds: [ShortEnd]
  }

  /// A wall end that stops short of the junction it should meet.
  public struct ShortEnd: Decodable, Sendable {
    /// `start` or `end` (along the wall's local X axis).
    public let end: String
    public let junction: [Double]
    public let shortByM: Double
  }

  public struct Opening: Decodable, Sendable {
    /// `door`, `window` or `opening`.
    public let kind: String
    /// Index in the `doors`, `windows` or `openings` list.
    public let index: Int
    public let identifier: String
    public let wallIdentifier: String
    /// Doors only.
    public let isOpen: Bool?
    /// Rooms the opening belongs to or connects.
    public let roomIds: [String]
  }
}
