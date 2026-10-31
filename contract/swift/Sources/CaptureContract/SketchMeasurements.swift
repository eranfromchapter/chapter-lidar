/// contract/schema/sketch-measurements.schema.json: what the operator entered for one sketch
/// capture (spec F14): the rooms as drawn, the walls around each room in order, the lengths,
/// diagonals and openings that were measured, and the ceiling height. The sketch solver turns
/// this into the capture model; the file is kept unchanged as the capture's original, next to
/// the sketch image, as `Original Exports/{areaKey}/{captureId}/sketch-measurements.json`
/// (role `sketch_measurements`). Lengths are millimetres with the unit and text entered.
public struct SketchMeasurements: Hashable, Sendable, Codable {
  public var schemaVersion: SketchMeasurementsSchemaVersion
  public var visitId: LowercaseUUID
  public var captureId: LowercaseUUID
  public var areaKey: String
  /// The unit system the operator worked in.
  public var displayUnits: DisplayUnitSystem
  /// What the operator measured from.
  public var source: Source
  /// Floor-to-ceiling height of the floor, used by every room without its own. Nil when the
  /// operator did not measure it: the solver assumes 2440 mm and the capture is limited.
  public var ceilingHeight: Length?
  public var rooms: [Room]

  public init(
    schemaVersion: SketchMeasurementsSchemaVersion = .current,
    visitId: LowercaseUUID,
    captureId: LowercaseUUID,
    areaKey: String,
    displayUnits: DisplayUnitSystem,
    source: Source,
    ceilingHeight: Length? = nil,
    rooms: [Room]
  ) {
    self.schemaVersion = schemaVersion
    self.visitId = visitId
    self.captureId = captureId
    self.areaKey = areaKey
    self.displayUnits = displayUnits
    self.source = source
    self.ceilingHeight = ceilingHeight
    self.rooms = rooms
  }

  /// What the operator measured from. `path` is present exactly when `kind` is not `none`.
  public struct Source: Hashable, Sendable, Codable {
    public var kind: SketchSourceKind
    /// Package path of the sketch image (role `sketch_image`), or of the walkthrough log.
    public var path: String?
    /// Package path of what Claude read from the sketch (role `sketch_interpretation`, F16).
    public var interpretation: String?

    public init(kind: SketchSourceKind, path: String? = nil, interpretation: String? = nil) {
      self.kind = kind
      self.path = path
      self.interpretation = interpretation
    }
  }

  /// Furniture drawn in a room (spec F16), in the capture frame. Reference geometry only.
  public struct Furniture: Hashable, Sendable, Codable {
    public var id: String
    public var category: ObjectCategory
    /// Centre in the capture frame, metres.
    public var x: Double
    public var z: Double
    public var widthM: Double
    public var depthM: Double
    /// Nil: a height by category.
    public var heightM: Double?
    /// Rotation about +Y, counter-clockwise seen from +Y, degrees.
    public var angleDeg: Double

    public init(
      id: String, category: ObjectCategory, x: Double, z: Double, widthM: Double, depthM: Double,
      heightM: Double? = nil, angleDeg: Double = 0
    ) {
      self.id = id
      self.category = category
      self.x = x
      self.z = z
      self.widthM = widthM
      self.depthM = depthM
      self.heightM = heightM
      self.angleDeg = angleDeg
    }
  }

  /// One entered length. `measured` false is an "about" value the operator estimated by eye.
  public struct Length: Hashable, Sendable, Codable {
    public var valueMm: Double
    public var enteredUnit: EnteredUnit
    /// The value exactly as the operator entered it, in `enteredUnit`.
    public var enteredText: String
    /// True when read from a tape or laser (or printed on the existing plan).
    public var measured: Bool

    public init(valueMm: Double, enteredUnit: EnteredUnit, enteredText: String, measured: Bool) {
      self.valueMm = valueMm
      self.enteredUnit = enteredUnit
      self.enteredText = enteredText
      self.measured = measured
    }
  }

  public struct Room: Hashable, Sendable, Codable {
    public var id: String
    /// Room name as the operator wrote it, for example Kitchen.
    public var label: String
    /// What the room is used for, when the operator chose it.
    public var type: RoomType?
    /// The walls around the room in order, counter-clockwise seen from above as drawn. Corner
    /// `i` is the start of wall `i`; the last wall ends at corner 0.
    public var walls: [Wall]
    /// Corner-to-corner distances measured through the room. Empty when none.
    public var diagonals: [Diagonal]
    /// Doors, windows and openings in this room's walls. Empty when none.
    public var openings: [Opening]
    /// This room's ceiling height when it differs from the floor's.
    public var ceilingHeight: Length?
    /// Where the room sits in the capture frame when it was measured there (an AR walkthrough):
    /// the solver keeps it there instead of placing it by `sharedWith`.
    public var placement: Placement?
    /// Furniture drawn in the room (spec F16).
    public var furniture: [Furniture]?

    public init(
      id: String, label: String, type: RoomType? = nil, walls: [Wall], diagonals: [Diagonal] = [],
      openings: [Opening] = [], ceilingHeight: Length? = nil, placement: Placement? = nil,
      furniture: [Furniture]? = nil
    ) {
      self.id = id
      self.label = label
      self.type = type
      self.walls = walls
      self.diagonals = diagonals
      self.openings = openings
      self.ceilingHeight = ceilingHeight
      self.placement = placement
      self.furniture = furniture
    }
  }

  /// Corner 0 at (`x`, `z`) metres in the capture frame and wall 0 leaving it at `angleDeg`,
  /// counter-clockwise from +x seen from +Y.
  public struct Placement: Hashable, Sendable, Codable {
    public var x: Double
    public var z: Double
    public var angleDeg: Double

    public init(x: Double, z: Double, angleDeg: Double) {
      self.x = x
      self.z = z
      self.angleDeg = angleDeg
    }
  }

  public struct Wall: Hashable, Sendable, Codable {
    public var id: String
    /// The wall's length along the inside face. Nil when the operator did not enter one.
    public var length: Length?
    /// The corner at the end of this wall. Nil means `left` (a square convex corner).
    public var turn: SketchTurn?
    /// True for an exterior wall. Nil means interior.
    public var exterior: Bool?
    /// The wall of an earlier room that is the other side of the same partition.
    public var sharedWith: SharedWall?

    public init(
      id: String, length: Length? = nil, turn: SketchTurn? = nil, exterior: Bool? = nil,
      sharedWith: SharedWall? = nil
    ) {
      self.id = id
      self.length = length
      self.turn = turn
      self.exterior = exterior
      self.sharedWith = sharedWith
    }
  }

  public struct SharedWall: Hashable, Sendable, Codable {
    public var roomId: String
    public var wallId: String

    public init(roomId: String, wallId: String) {
      self.roomId = roomId
      self.wallId = wallId
    }
  }

  public struct Diagonal: Hashable, Sendable, Codable {
    /// Index of the first corner (the start of wall `from`).
    public var from: Int
    /// Index of the second corner; not `from` or a neighbour of it.
    public var to: Int
    public var length: Length

    public init(from: Int, to: Int, length: Length) {
      self.from = from
      self.to = to
      self.length = length
    }
  }

  public struct Opening: Hashable, Sendable, Codable {
    public var id: String
    public var kind: SketchOpeningKind
    /// The wall of this room the opening is in.
    public var wallId: String
    /// Clear width. Nil: the solver uses a default, estimated.
    public var width: Length?
    /// Height of the opening. Nil: the solver uses a default, estimated.
    public var height: Length?
    /// Windows only: height of the sill above the floor. Nil: 914 mm, estimated.
    public var sill: Length?
    /// Which corner of the wall `fromCornerDistance` is measured from.
    public var fromCorner: SketchWallCorner
    /// Distance from that corner to the nearest jamb. Nil: placed by order, estimated.
    public var fromCornerDistance: Length?

    public init(
      id: String, kind: SketchOpeningKind, wallId: String, width: Length? = nil,
      height: Length? = nil, sill: Length? = nil, fromCorner: SketchWallCorner,
      fromCornerDistance: Length? = nil
    ) {
      self.id = id
      self.kind = kind
      self.wallId = wallId
      self.width = width
      self.height = height
      self.sill = sill
      self.fromCorner = fromCorner
      self.fromCornerDistance = fromCornerDistance
    }
  }
}
