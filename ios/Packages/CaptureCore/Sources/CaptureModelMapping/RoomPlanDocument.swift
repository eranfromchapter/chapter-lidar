import CaptureContract
import Foundation

// Codable mirror of the JSON that Apple's `CapturedRoom` and `CapturedStructure` encode to.
// On device the live session encodes the RoomPlan value with JSONEncoder and decodes it with
// this type, so the mapping code is the same on Linux (fixtures) and on the phone.
//
// Shape (see fixtures/generator/README.md):
//   - simd values are arrays: `dimensions` [x, y, z], `transform` 16 numbers, column after
//     column (Apple's `simd_float4x4` Codable shape; see `RoomPlanMatrix`).
//   - enum cases encode as `{ "<case>": { ...associated values } }`, for example
//     `{ "door": { "isOpen": false } }`, and confidence as `{ "high": {} }`.
//   - a wall surface has local X along the wall, local Y up; `dimensions` is [length, height, 0].
//   - doors, windows and openings carry `parentIdentifier` (the wall they sit in).
//   - floors carry `polygonCorners` in the floor's local frame.
//   - a room carries `story` and `sections`: `{ "story", "label", "center": [x, y, z] }`, a
//     labelled point with no shape. Labels are `livingRoom`, `bedroom`, `bathroom`, `kitchen`,
//     `diningRoom` and `unidentified`.
//   - objects carry `attributes` (name to string, for example `{ "StorageType": "cabinet" }`) and
//     `parentIdentifier` (the object they sit on or in).
//   - a structure is `{ "version", "rooms": [CapturedRoom], "sections" }`.
// Unknown keys are ignored, so newer RoomPlan versions still decode.

/// A decoded RoomPlan capture: one room, or the rooms of a structure.
public struct RoomPlanDocument: Sendable, Equatable {
  public var rooms: [RoomPlanRoom]
  /// True when the JSON was a `CapturedStructure` (a `rooms` list), false for one `CapturedRoom`.
  public var isStructure: Bool
  /// The structure's own sections (a `CapturedStructure` lists them besides each room's). Empty
  /// for one `CapturedRoom`, whose sections are in `rooms[0].sections`.
  public var sections: [RoomPlanSection]

  public init(rooms: [RoomPlanRoom], isStructure: Bool, sections: [RoomPlanSection] = []) {
    self.rooms = rooms
    self.isStructure = isStructure
    self.sections = sections
  }

  /// Decodes `CapturedRoom` or `CapturedStructure` JSON.
  public static func decode(from data: Data) throws -> RoomPlanDocument {
    let decoder = JSONDecoder()
    let probe = try decoder.decode(Probe.self, from: data)
    if probe.hasRooms {
      let structure = try decoder.decode(Structure.self, from: data)
      return RoomPlanDocument(
        rooms: structure.rooms, isStructure: true, sections: structure.sections)
    }
    let room = try decoder.decode(RoomPlanRoom.self, from: data)
    return RoomPlanDocument(rooms: [room], isStructure: false)
  }

  private struct Probe: Decodable {
    let hasRooms: Bool

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: AnyKey.self)
      hasRooms = container.contains(AnyKey("rooms"))
    }
  }

  private struct Structure: Decodable {
    let rooms: [RoomPlanRoom]
    let sections: [RoomPlanSection]

    private enum CodingKeys: String, CodingKey {
      case rooms, sections
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      rooms = try container.decode([RoomPlanRoom].self, forKey: .rooms)
      sections = (try? container.decodeIfPresent([RoomPlanSection].self, forKey: .sections)) ?? []
    }
  }
}

/// One `CapturedRoom`.
public struct RoomPlanRoom: Sendable, Equatable, Decodable {
  public var identifier: String?
  /// Floor of a multi-floor structure, 0 for the first; nil when RoomPlan wrote none.
  public var story: Int?
  public var walls: [RoomPlanSurface]
  public var doors: [RoomPlanSurface]
  public var windows: [RoomPlanSurface]
  public var openings: [RoomPlanSurface]
  public var floors: [RoomPlanSurface]
  public var objects: [RoomPlanObject]
  /// Labelled points RoomPlan placed in the room. A walk-through scan has one per room it
  /// recognized, all in this one `CapturedRoom`.
  public var sections: [RoomPlanSection]

  public init(
    identifier: String? = nil, story: Int? = nil, walls: [RoomPlanSurface] = [],
    doors: [RoomPlanSurface] = [], windows: [RoomPlanSurface] = [],
    openings: [RoomPlanSurface] = [], floors: [RoomPlanSurface] = [],
    objects: [RoomPlanObject] = [], sections: [RoomPlanSection] = []
  ) {
    self.identifier = identifier
    self.story = story
    self.walls = walls
    self.doors = doors
    self.windows = windows
    self.openings = openings
    self.floors = floors
    self.objects = objects
    self.sections = sections
  }

  private enum CodingKeys: String, CodingKey {
    case identifier, story, walls, doors, windows, openings, floors, objects, sections
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
    walls = try container.decodeIfPresent([RoomPlanSurface].self, forKey: .walls) ?? []
    doors = try container.decodeIfPresent([RoomPlanSurface].self, forKey: .doors) ?? []
    windows = try container.decodeIfPresent([RoomPlanSurface].self, forKey: .windows) ?? []
    openings = try container.decodeIfPresent([RoomPlanSurface].self, forKey: .openings) ?? []
    floors = try container.decodeIfPresent([RoomPlanSurface].self, forKey: .floors) ?? []
    objects = try container.decodeIfPresent([RoomPlanObject].self, forKey: .objects) ?? []
    // Story and sections only name rooms: a shape this code does not expect leaves them out
    // instead of failing the capture.
    story = try? container.decodeIfPresent(Int.self, forKey: .story)
    sections = (try? container.decodeIfPresent([RoomPlanSection].self, forKey: .sections)) ?? []
  }
}

/// A `CapturedRoom.Section`: a labelled point in the part of the scan RoomPlan recognized as one
/// kind of room. It has a centre but no shape.
public struct RoomPlanSection: Sendable, Equatable, Decodable {
  /// The label as RoomPlan wrote it: `livingRoom`, `bedroom`, `bathroom`, `kitchen`,
  /// `diningRoom`, `unidentified`, or a label from a newer RoomPlan.
  public var label: String
  public var story: Int?
  /// Centre in the same frame as the walls and floors; nil when RoomPlan wrote no point.
  public var center: Vector3?

  public init(label: String, story: Int? = nil, center: Vector3?) {
    self.label = label
    self.story = story
    self.center = center
  }

  private enum CodingKeys: String, CodingKey {
    case label, story, center
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? "unidentified"
    story = try? container.decodeIfPresent(Int.self, forKey: .story)
    let numbers = (try? container.decodeIfPresent([Double].self, forKey: .center)) ?? []
    center = numbers.count >= 3 ? Vector3(numbers[0], numbers[1], numbers[2]) : nil
  }

  /// The contract room type of the label; nil for `unidentified` and for labels this code does
  /// not know.
  public var roomType: RoomType? {
    switch label {
    case "livingRoom": return .livingRoom
    case "diningRoom": return .diningRoom
    case "kitchen": return .kitchen
    case "bedroom": return .bedroom
    case "bathroom": return .bathroom
    default: return nil
    }
  }
}

/// A wall, door, window, opening or floor (`CapturedRoom.Surface`).
public struct RoomPlanSurface: Sendable, Equatable, Decodable {
  public var identifier: String
  /// Identifier of the wall a door, window or opening sits in, when RoomPlan reports it.
  public var parentIdentifier: String?
  public var category: RoomPlanCategory
  public var confidence: DetectionConfidence?
  /// [x, y, z]; for a surface x is the width along the wall and y the height.
  public var dimensions: [Double]
  public var transform: Matrix4
  /// Floor outline in the floor's local frame.
  public var polygonCorners: [[Double]]?

  public init(
    identifier: String, parentIdentifier: String? = nil, category: RoomPlanCategory,
    confidence: DetectionConfidence? = nil, dimensions: [Double], transform: Matrix4,
    polygonCorners: [[Double]]? = nil
  ) {
    self.identifier = identifier
    self.parentIdentifier = parentIdentifier
    self.category = category
    self.confidence = confidence
    self.dimensions = dimensions
    self.transform = transform
    self.polygonCorners = polygonCorners
  }

  private enum CodingKeys: String, CodingKey {
    case identifier, parentIdentifier, category, confidence, dimensions, transform, polygonCorners
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    identifier = try container.decode(String.self, forKey: .identifier)
    parentIdentifier = try container.decodeIfPresent(String.self, forKey: .parentIdentifier)
    category = try container.decode(RoomPlanCategory.self, forKey: .category)
    confidence = try container.decodeIfPresent(RoomPlanCaseName.self, forKey: .confidence)
      .flatMap { DetectionConfidence(rawValue: $0.name) }
    dimensions = try container.decode([Double].self, forKey: .dimensions)
    transform = try container.decode(RoomPlanMatrix.self, forKey: .transform).matrix
    polygonCorners = try container.decodeIfPresent([[Double]].self, forKey: .polygonCorners)
  }

  /// Dimension `index`, or 0 when RoomPlan wrote fewer numbers.
  func dimension(_ index: Int) -> Double {
    dimensions.indices.contains(index) ? dimensions[index] : 0
  }
}

/// A recognized object (`CapturedRoom.Object`).
public struct RoomPlanObject: Sendable, Equatable, Decodable {
  public var identifier: String
  /// Identifier of the object this one sits on or in (a sink in a cabinet), when RoomPlan
  /// reports it.
  public var parentIdentifier: String?
  public var category: RoomPlanCategory
  public var confidence: DetectionConfidence?
  /// Box size along the object's local axes.
  public var dimensions: [Double]
  public var transform: Matrix4
  /// Attributes as RoomPlan wrote them, name to value, for example `["StorageType": "cabinet"]`.
  /// Empty when there are none.
  public var attributes: [String: String]

  public init(
    identifier: String, parentIdentifier: String? = nil, category: RoomPlanCategory,
    confidence: DetectionConfidence? = nil, dimensions: [Double], transform: Matrix4,
    attributes: [String: String] = [:]
  ) {
    self.identifier = identifier
    self.parentIdentifier = parentIdentifier
    self.category = category
    self.confidence = confidence
    self.dimensions = dimensions
    self.transform = transform
    self.attributes = attributes
  }

  private enum CodingKeys: String, CodingKey {
    case identifier, parentIdentifier, category, confidence, dimensions, transform, attributes
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    identifier = try container.decode(String.self, forKey: .identifier)
    parentIdentifier = try container.decodeIfPresent(String.self, forKey: .parentIdentifier)
    category = try container.decode(RoomPlanCategory.self, forKey: .category)
    confidence = try container.decodeIfPresent(RoomPlanCaseName.self, forKey: .confidence)
      .flatMap { DetectionConfidence(rawValue: $0.name) }
    dimensions = try container.decode([Double].self, forKey: .dimensions)
    transform = try container.decode(RoomPlanMatrix.self, forKey: .transform).matrix
    attributes = [:]
    // Only string values are kept, so an attribute of another shape in a newer RoomPlan does not
    // stop the whole capture from decoding.
    if container.contains(.attributes),
      let values = try? container.nestedContainer(keyedBy: AnyKey.self, forKey: .attributes)
    {
      for key in values.allKeys {
        if let value = try? values.decode(String.self, forKey: key) {
          attributes[key.stringValue] = value
        }
      }
    }
  }
}

/// `simd_float4x4` as Apple's Codable writes it inside `CapturedRoom`: one flat array of 16
/// numbers, column after column, so numbers 12, 13, 14 are the translation. This differs from
/// `Matrix4`'s own Codable shape (four column arrays), which the package files keep.
struct RoomPlanMatrix: Sendable, Equatable, Decodable {
  let matrix: Matrix4

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let numbers = try container.decode([Double].self)
    guard numbers.count == 16,
      let matrix = Matrix4(columns: stride(from: 0, to: 16, by: 4).map { Array(numbers[$0..<$0 + 4]) })
    else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Expected a simd_float4x4 as 16 numbers")
    }
    self.matrix = matrix
  }
}

/// A Swift enum case as Codable writes it when the case has associated values:
/// a one-key object whose key is the case name. `{ "high": {} }` is the case `high`.
struct RoomPlanCaseName: Sendable, Equatable, Decodable {
  let name: String

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AnyKey.self)
    guard let key = container.allKeys.sorted(by: { $0.stringValue < $1.stringValue }).first else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: container.codingPath,
          debugDescription: "Expected an enum case object with one key"))
    }
    name = key.stringValue
  }
}

/// `CapturedRoom.Surface.Category` and `CapturedRoom.Object.Category`: the case name, for example
/// `wall`, `door`, `table`, `washerDryer`.
public struct RoomPlanCategory: Sendable, Equatable, Decodable {
  public var name: String
  /// For a door: whether RoomPlan saw it open.
  public var isOpen: Bool?

  public init(name: String, isOpen: Bool? = nil) {
    self.name = name
    self.isOpen = isOpen
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: AnyKey.self)
    guard let key = container.allKeys.sorted(by: { $0.stringValue < $1.stringValue }).first else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: container.codingPath,
          debugDescription: "Expected a category object with one key"))
    }
    name = key.stringValue
    if let payload = try? container.nestedContainer(keyedBy: AnyKey.self, forKey: key) {
      isOpen = try payload.decodeIfPresent(Bool.self, forKey: AnyKey("isOpen"))
    } else {
      isOpen = nil
    }
  }

  /// Contract object category for an object, `other` for anything the contract does not list.
  var objectCategory: ObjectCategory {
    switch name {
    case "washerDryer": return .washerDryer
    default: return ObjectCategory(rawValue: name) ?? .other
    }
  }
}

struct AnyKey: CodingKey {
  let stringValue: String
  var intValue: Int? { nil }

  init(_ string: String) { stringValue = string }
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { nil }
}
