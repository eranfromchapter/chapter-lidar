/// contract/schema/field-controls.schema.json: independent dimensions and levels measured on
/// site with tape or laser during one visit, never copied from the scan. Values are stored in
/// millimetres with the unit and text the operator entered. Written as
/// `Field Measurements/{visitId}/field-controls.json`. Every list is present; empty means none.
public struct FieldControls: Hashable, Sendable, Codable {
  public var schemaVersion: SchemaVersion
  public var visitId: LowercaseUUID
  /// Long distances per floor. Axis B is perpendicular to axis A on the same floor.
  public var distances: [Distance]
  public var ceilingHeights: [CeilingHeight]
  /// Measured opening dimensions.
  public var openings: [Opening]
  /// Floor-to-floor levels between the captures of two floors.
  public var floorToFloor: [FloorToFloor]
  /// Shared landmarks visible from two or more captures.
  public var landmarks: [Landmark]

  public init(
    schemaVersion: SchemaVersion = .current,
    visitId: LowercaseUUID,
    distances: [Distance] = [],
    ceilingHeights: [CeilingHeight] = [],
    openings: [Opening] = [],
    floorToFloor: [FloorToFloor] = [],
    landmarks: [Landmark] = []
  ) {
    self.schemaVersion = schemaVersion
    self.visitId = visitId
    self.distances = distances
    self.ceilingHeights = ceilingHeights
    self.openings = openings
    self.floorToFloor = floorToFloor
    self.landmarks = landmarks
  }

  /// The capture a control belongs to, as registered in the capture record.
  public struct CaptureRef: Hashable, Sendable, Codable {
    public var captureId: LowercaseUUID
    public var areaKey: String

    public init(captureId: LowercaseUUID, areaKey: String) {
      self.captureId = captureId
      self.areaKey = areaKey
    }
  }

  public struct Measurement: Hashable, Sendable, Codable {
    /// Measured value in millimetres.
    public var valueMm: Double
    public var enteredUnit: EnteredUnit
    /// The value exactly as the operator entered it, in `enteredUnit`.
    public var enteredText: String
    public var method: MeasurementMethod
    public var recordedAt: UTCTimestamp

    public init(
      valueMm: Double, enteredUnit: EnteredUnit, enteredText: String, method: MeasurementMethod,
      recordedAt: UTCTimestamp
    ) {
      self.valueMm = valueMm
      self.enteredUnit = enteredUnit
      self.enteredText = enteredText
      self.method = method
      self.recordedAt = recordedAt
    }
  }

  public struct Distance: Hashable, Sendable, Codable {
    public var id: String
    public var capture: CaptureRef
    public var axis: DistanceAxis
    /// Start point in words, for example Kitchen east wall.
    public var from: String
    /// End point in words, for example Living west wall.
    public var to: String
    public var measurement: Measurement

    public init(
      id: String, capture: CaptureRef, axis: DistanceAxis, from: String, to: String,
      measurement: Measurement
    ) {
      self.id = id
      self.capture = capture
      self.axis = axis
      self.from = from
      self.to = to
      self.measurement = measurement
    }
  }

  public struct CeilingHeight: Hashable, Sendable, Codable {
    public var id: String
    public var capture: CaptureRef
    /// Room label, matching the capture model room label.
    public var room: String
    /// Where in the room it was measured, when it matters.
    public var location: String?
    public var measurement: Measurement

    public init(
      id: String, capture: CaptureRef, room: String, location: String? = nil,
      measurement: Measurement
    ) {
      self.id = id
      self.capture = capture
      self.room = room
      self.location = location
      self.measurement = measurement
    }
  }

  /// Measured dimensions of one opening (the schema's `openingControl`).
  public struct Opening: Hashable, Sendable, Codable {
    public var id: String
    public var capture: CaptureRef
    public var room: String
    /// Which opening, for example Entry door.
    public var label: String
    public var width: Measurement
    public var height: Measurement?

    public init(
      id: String, capture: CaptureRef, room: String, label: String, width: Measurement,
      height: Measurement? = nil
    ) {
      self.id = id
      self.capture = capture
      self.room = room
      self.label = label
      self.width = width
      self.height = height
    }
  }

  public struct FloorToFloor: Hashable, Sendable, Codable {
    public var id: String
    /// Capture of the lower floor.
    public var lower: CaptureRef
    /// Capture of the upper floor.
    public var upper: CaptureRef
    /// Where it was measured, for example At stair.
    public var location: String
    /// Finished floor of the lower floor to finished floor of the upper floor.
    public var measurement: Measurement

    public init(
      id: String, lower: CaptureRef, upper: CaptureRef, location: String, measurement: Measurement
    ) {
      self.id = id
      self.lower = lower
      self.upper = upper
      self.location = location
      self.measurement = measurement
    }
  }

  public struct Landmark: Hashable, Sendable, Codable {
    public var id: String
    /// What the landmark is, for example Stair newel post.
    public var label: String
    public var description: String?
    /// Captures the landmark is visible in; two or more different captures.
    public var captures: [CaptureRef]
    /// Site photos showing the landmark (package-relative paths).
    public var photoPaths: [String]?

    public init(
      id: String, label: String, description: String? = nil, captures: [CaptureRef],
      photoPaths: [String]? = nil
    ) {
      self.id = id
      self.label = label
      self.description = description
      self.captures = captures
      self.photoPaths = photoPaths
    }
  }
}
