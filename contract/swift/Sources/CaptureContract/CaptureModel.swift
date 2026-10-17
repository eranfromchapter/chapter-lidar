/// contract/schema/capture-model.schema.json: normalized geometry of one capture (one floor or
/// area scan), the single input of every plan and mesh exporter. Written as
/// `Original Exports/{areaKey}/{captureId}/capture-model.json` with role `capture_model`.
/// Lengths in metres; right-handed with +Y up, so plan coordinates are X and Z. Coordinates are
/// in this capture's own local frame.
public struct CaptureModel: Hashable, Sendable, Codable {
  public var schemaVersion: SchemaVersion
  public var visitId: LowercaseUUID
  public var captureId: LowercaseUUID
  public var areaKey: String
  public var label: String
  public var coordinateSystem: CoordinateSystem
  public var rooms: [Room]
  public var walls: [Wall]
  public var doors: [WallOpening]
  public var windows: [WallOpening]
  /// Openings without a door or window (passages, arches).
  public var openings: [WallOpening]
  public var objects: [DetectedObject]
  /// Package files of the same capture that this geometry was derived from or is accompanied by.
  public var refs: [SourceRef]

  public init(
    schemaVersion: SchemaVersion = .current,
    visitId: LowercaseUUID,
    captureId: LowercaseUUID,
    areaKey: String,
    label: String,
    coordinateSystem: CoordinateSystem = CoordinateSystem(),
    rooms: [Room] = [],
    walls: [Wall] = [],
    doors: [WallOpening] = [],
    windows: [WallOpening] = [],
    openings: [WallOpening] = [],
    objects: [DetectedObject] = [],
    refs: [SourceRef] = []
  ) {
    self.schemaVersion = schemaVersion
    self.visitId = visitId
    self.captureId = captureId
    self.areaKey = areaKey
    self.label = label
    self.coordinateSystem = coordinateSystem
    self.rooms = rooms
    self.walls = walls
    self.doors = doors
    self.windows = windows
    self.openings = openings
    self.objects = objects
    self.refs = refs
  }

  /// Always metres, right-handed, +Y up.
  public struct CoordinateSystem: Hashable, Sendable, Codable {
    public var units: LengthUnit
    public var handedness: Handedness
    public var up: UpAxis

    public init(
      units: LengthUnit = .metres, handedness: Handedness = .right, up: UpAxis = .positiveY
    ) {
      self.units = units
      self.handedness = handedness
      self.up = up
    }
  }

  public struct Room: Hashable, Sendable, Codable {
    public var id: String
    /// Room label shown to people, for example Kitchen.
    public var label: String
    /// Floor outline as a closed loop at floor level (first point not repeated),
    /// counter-clockwise seen from +Y.
    public var polygon: [Vec3]
    /// Floor-to-ceiling height in metres.
    public var heightM: Double

    public init(id: String, label: String, polygon: [Vec3], heightM: Double) {
      self.id = id
      self.label = label
      self.polygon = polygon
      self.heightM = heightM
    }
  }

  public struct Wall: Hashable, Sendable, Codable {
    public var id: String
    /// Wall centreline start at the wall base.
    public var start: Vec3
    /// Wall centreline end at the wall base.
    public var end: Vec3
    public var heightM: Double
    public var thicknessM: Double
    /// Rooms this wall bounds.
    public var roomIds: [String]?
    public var confidence: DetectionConfidence?

    public init(
      id: String, start: Vec3, end: Vec3, heightM: Double, thicknessM: Double,
      roomIds: [String]? = nil, confidence: DetectionConfidence? = nil
    ) {
      self.id = id
      self.start = start
      self.end = end
      self.heightM = heightM
      self.thicknessM = thicknessM
      self.roomIds = roomIds
      self.confidence = confidence
    }
  }

  /// Door, window or opening placed in its parent wall.
  public struct WallOpening: Hashable, Sendable, Codable {
    public var id: String
    /// Id of the parent wall in the same file.
    public var wallId: String
    /// Distance along the wall from its start to the centre of the opening.
    public var offsetM: Double
    /// Height of the bottom of the opening above the wall base (0 for doors).
    public var bottomM: Double
    public var widthM: Double
    public var heightM: Double
    public var confidence: DetectionConfidence?

    public init(
      id: String, wallId: String, offsetM: Double, bottomM: Double, widthM: Double,
      heightM: Double, confidence: DetectionConfidence? = nil
    ) {
      self.id = id
      self.wallId = wallId
      self.offsetM = offsetM
      self.bottomM = bottomM
      self.widthM = widthM
      self.heightM = heightM
      self.confidence = confidence
    }
  }

  /// Recognized object with an oriented bounding box. Reference geometry only.
  public struct DetectedObject: Hashable, Sendable, Codable {
    public var id: String
    public var category: ObjectCategory
    public var roomId: String?
    public var box: OrientedBox
    public var confidence: DetectionConfidence?

    public init(
      id: String, category: ObjectCategory, roomId: String? = nil, box: OrientedBox,
      confidence: DetectionConfidence? = nil
    ) {
      self.id = id
      self.category = category
      self.roomId = roomId
      self.box = box
      self.confidence = confidence
    }
  }

  public struct OrientedBox: Hashable, Sendable, Codable {
    public var center: Vec3
    /// Box size along the box's local axes, in metres.
    public var sizeM: Vec3
    /// Unit rotation quaternion.
    public var rotation: Quaternion

    public init(center: Vec3, sizeM: Vec3, rotation: Quaternion = .identity) {
      self.center = center
      self.sizeM = sizeM
      self.rotation = rotation
    }
  }

  public struct SourceRef: Hashable, Sendable, Codable {
    public var role: GeometrySourceRole
    /// Path relative to the package root.
    public var path: String

    public init(role: GeometrySourceRole, path: String) {
      self.role = role
      self.path = path
    }
  }
}
