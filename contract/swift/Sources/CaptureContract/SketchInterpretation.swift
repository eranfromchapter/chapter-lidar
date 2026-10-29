/// contract/schema/sketch-interpretation.schema.json: what Claude read from a photo of a
/// floor-plan sketch (spec F16). Returned by `POST /v1/sketch-interpretations` and kept in the
/// package as `Original Exports/{areaKey}/{captureId}/sketch-interpretation.json` (role
/// `sketch_interpretation`). `reading` is Claude's structured output: every property is present
/// and an absent value is `null`, so this type writes `null` for nil (the one exception to the
/// contract's "omitted, never null"). Drawing coordinates: origin top-left, x right, y down, the
/// image's longer side is 1000 units.
public struct SketchInterpretation: Hashable, Sendable, Codable {
  public var schemaVersion: SketchInterpretationSchemaVersion
  /// The Claude model that read the sketch.
  public var model: String
  public var interpretedAt: UTCTimestamp
  /// Pixel size of the photo as sent.
  public var image: ImageSize
  public var reading: Reading

  public init(
    schemaVersion: SketchInterpretationSchemaVersion = .current, model: String,
    interpretedAt: UTCTimestamp, image: ImageSize, reading: Reading
  ) {
    self.schemaVersion = schemaVersion
    self.model = model
    self.interpretedAt = interpretedAt
    self.image = image
    self.reading = reading
  }

  public struct ImageSize: Hashable, Sendable, Codable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
      self.width = width
      self.height = height
    }
  }

  /// A point in drawing coordinates.
  public struct Point: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }
  }

  public struct Reading: Hashable, Sendable, Codable {
    /// False when the image is not a floor plan or a sketch of one.
    public var isFloorPlan: Bool
    /// Why the drawing could not be read fully, or nil.
    public var problem: String?
    public var dimensionUnits: SketchDimensionUnits
    /// A ceiling height written on the drawing, in millimetres.
    public var ceilingHeightMm: Double?
    public var rooms: [Room]
    /// Every dimension written on the drawing.
    public var dimensions: [Dimension]

    public init(
      isFloorPlan: Bool, problem: String? = nil, dimensionUnits: SketchDimensionUnits,
      ceilingHeightMm: Double? = nil, rooms: [Room], dimensions: [Dimension] = []
    ) {
      self.isFloorPlan = isFloorPlan
      self.problem = problem
      self.dimensionUnits = dimensionUnits
      self.ceilingHeightMm = ceilingHeightMm
      self.rooms = rooms
      self.dimensions = dimensions
    }

    private enum CodingKeys: String, CodingKey {
      case isFloorPlan, problem, dimensionUnits, ceilingHeightMm, rooms, dimensions
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(isFloorPlan, forKey: .isFloorPlan)
      try container.encode(problem, forKey: .problem)
      try container.encode(dimensionUnits, forKey: .dimensionUnits)
      try container.encode(ceilingHeightMm, forKey: .ceilingHeightMm)
      try container.encode(rooms, forKey: .rooms)
      try container.encode(dimensions, forKey: .dimensions)
    }
  }

  public struct Room: Hashable, Sendable, Codable {
    public var label: String
    public var type: RoomType?
    /// The floor outline at the inside face of the walls, in order, first corner not repeated.
    public var corners: [Point]
    public var openings: [Opening]
    public var furniture: [Furniture]

    public init(
      label: String, type: RoomType? = nil, corners: [Point], openings: [Opening] = [],
      furniture: [Furniture] = []
    ) {
      self.label = label
      self.type = type
      self.corners = corners
      self.openings = openings
      self.furniture = furniture
    }

    private enum CodingKeys: String, CodingKey {
      case label, type, corners, openings, furniture
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(label, forKey: .label)
      try container.encode(type, forKey: .type)
      try container.encode(corners, forKey: .corners)
      try container.encode(openings, forKey: .openings)
      try container.encode(furniture, forKey: .furniture)
    }
  }

  public struct Opening: Hashable, Sendable, Codable {
    public var kind: SketchOpeningKind
    /// Wall `i` runs from corner `i` to corner `i + 1`.
    public var wall: Int
    /// Where the opening starts along the wall, 0 at corner `i`, 1 at corner `i + 1`.
    public var start: Double
    public var end: Double

    public init(kind: SketchOpeningKind, wall: Int, start: Double, end: Double) {
      self.kind = kind
      self.wall = wall
      self.start = start
      self.end = end
    }
  }

  public struct Furniture: Hashable, Sendable, Codable {
    public var category: ObjectCategory
    public var label: String?
    public var center: Point
    /// Drawing units.
    public var width: Double
    public var depth: Double
    /// Degrees clockwise in the drawing.
    public var angleDeg: Double

    public init(
      category: ObjectCategory, label: String? = nil, center: Point, width: Double, depth: Double,
      angleDeg: Double = 0
    ) {
      self.category = category
      self.label = label
      self.center = center
      self.width = width
      self.depth = depth
      self.angleDeg = angleDeg
    }

    private enum CodingKeys: String, CodingKey {
      case category, label, center, width, depth, angleDeg
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(category, forKey: .category)
      try container.encode(label, forKey: .label)
      try container.encode(center, forKey: .center)
      try container.encode(width, forKey: .width)
      try container.encode(depth, forKey: .depth)
      try container.encode(angleDeg, forKey: .angleDeg)
    }
  }

  public struct Dimension: Hashable, Sendable, Codable {
    /// The label exactly as written.
    public var text: String
    public var valueMm: Double?
    /// Index of the room it measures.
    public var room: Int?
    /// Index of the wall of that room it measures.
    public var wall: Int?

    public init(text: String, valueMm: Double? = nil, room: Int? = nil, wall: Int? = nil) {
      self.text = text
      self.valueMm = valueMm
      self.room = room
      self.wall = wall
    }

    private enum CodingKeys: String, CodingKey {
      case text, valueMm, room, wall
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(text, forKey: .text)
      try container.encode(valueMm, forKey: .valueMm)
      try container.encode(room, forKey: .room)
      try container.encode(wall, forKey: .wall)
    }
  }
}
