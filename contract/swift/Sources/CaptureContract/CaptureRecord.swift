/// contract/schema/capture-record.schema.json: who captured what, where, when and how, for one
/// site visit at one property. A visit holds one or more captures; each capture is one floor or
/// area scanned in one mode, registered separately with its own `captureId`. Written as
/// `Source Register/{visitId}/capture-record.json`.
///
/// Reads schema 1.0.0 and 1.1.0 and always writes `CaptureRecordSchemaVersion.current`: 1.1.0
/// only adds optional fields (the compass reading of each capture), so every record is a valid
/// 1.1.0 document, while a 1.0.0 document may not carry the 1.1.0 fields.
public struct CaptureRecord: Hashable, Sendable, Codable {
  /// The version this record was read as; `.current` for a new record. Not written: see the type.
  public var schemaVersion: CaptureRecordSchemaVersion
  public var visitId: LowercaseUUID
  public var hub: HubProject
  public var address: Address
  public var `operator`: Operator
  public var device: Device
  public var app: AppInfo
  /// Start of the site visit (the visit date).
  public var visitedAt: UTCTimestamp
  /// Every capture made during the visit, one per floor or area scan.
  public var captures: [Capture]

  public init(
    schemaVersion: CaptureRecordSchemaVersion = .current,
    visitId: LowercaseUUID,
    hub: HubProject,
    address: Address,
    operator: Operator,
    device: Device,
    app: AppInfo,
    visitedAt: UTCTimestamp,
    captures: [Capture]
  ) {
    self.schemaVersion = schemaVersion
    self.visitId = visitId
    self.hub = hub
    self.address = address
    self.operator = `operator`
    self.device = device
    self.app = app
    self.visitedAt = visitedAt
    self.captures = captures
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, visitId, hub, address, `operator`, device, app, visitedAt, captures
  }

  // Decoding is synthesized: `schemaVersion` accepts every `CaptureRecordSchemaVersion`.

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(CaptureRecordSchemaVersion.current, forKey: .schemaVersion)
    try container.encode(visitId, forKey: .visitId)
    try container.encode(hub, forKey: .hub)
    try container.encode(address, forKey: .address)
    try container.encode(`operator`, forKey: .operator)
    try container.encode(device, forKey: .device)
    try container.encode(app, forKey: .app)
    try container.encode(visitedAt, forKey: .visitedAt)
    try container.encode(captures, forKey: .captures)
  }

  /// The HUB project this visit belongs to.
  public struct HubProject: Hashable, Sendable, Codable {
    /// HUB deal id, as returned by the HUB.
    public var dealId: String
    public var projectName: String?

    public init(dealId: String, projectName: String? = nil) {
      self.dealId = dealId
      self.projectName = projectName
    }
  }

  /// Property address from the HUB and whether the operator confirmed it on site.
  /// `confirmedAt` is present exactly when `confirmedOnSite` is true.
  public struct Address: Hashable, Sendable, Codable {
    /// Single-line address exactly as shown by the HUB.
    public var formatted: String
    public var confirmedOnSite: Bool
    public var confirmedAt: UTCTimestamp?

    public init(formatted: String, confirmedOnSite: Bool, confirmedAt: UTCTimestamp? = nil) {
      self.formatted = formatted
      self.confirmedOnSite = confirmedOnSite
      self.confirmedAt = confirmedAt
    }
  }

  /// The signed-in person who made the captures.
  public struct Operator: Hashable, Sendable, Codable {
    public var name: String
    /// Directory id of the signed-in user, when known.
    public var userId: String?

    public init(name: String, userId: String? = nil) {
      self.name = name
      self.userId = userId
    }
  }

  public struct Device: Hashable, Sendable, Codable {
    /// Hardware model identifier, for example iPhone17,1.
    public var model: String
    /// Human-readable model name, for example iPhone 16 Pro.
    public var marketingName: String?
    public var osName: DeviceOSName
    public var osVersion: String
    public var hasLidar: Bool

    public init(
      model: String, marketingName: String? = nil, osName: DeviceOSName, osVersion: String,
      hasLidar: Bool
    ) {
      self.model = model
      self.marketingName = marketingName
      self.osName = osName
      self.osVersion = osVersion
      self.hasLidar = hasLidar
    }
  }

  public struct AppInfo: Hashable, Sendable, Codable {
    /// Marketing version of Chapter Capture, for example 1.0.0.
    public var version: String
    public var build: String

    public init(version: String, build: String) {
      self.version = version
      self.build = build
    }
  }

  /// One floor or area scan, registered separately.
  public struct Capture: Hashable, Sendable, Codable {
    public var captureId: LowercaseUUID
    /// Stable path-safe key of the floor or area, for example floor-1.
    public var areaKey: String
    /// Floor or area label shown to people, for example Floor 1.
    public var label: String
    public var mode: CaptureMode
    public var units: Units
    /// Start of this capture (the capture date).
    public var capturedAt: UTCTimestamp
    public var finishedAt: UTCTimestamp?
    /// Notes on coverage, obscured surfaces and gaps. Empty when there is nothing to note.
    public var coverageNotes: String
    /// Rooms the operator chose not to scan. Empty when none.
    public var omittedRooms: [RoomNote]
    /// Rooms or spaces that could not be entered. Empty when none.
    public var inaccessibleRooms: [RoomNote]
    /// Compass bearing of this capture's −Z axis (plan up), degrees clockwise from north,
    /// `0 ..< 360`, one decimal (1.1.0). Nil when there is no reading.
    public var heading: Double?
    /// Accuracy of the reading in whole degrees, `1 ... 180` (1.1.0). Present exactly with `heading`.
    public var headingAccuracy: Int?
    /// True or magnetic north (1.1.0). Present exactly with `heading`.
    public var headingSource: HeadingSource?
    /// When the reading was taken (1.1.0). Present exactly with `heading`.
    public var headingRecordedAt: UTCTimestamp?
    /// Why there is no heading although the app tried (1.1.0). Never together with `heading`.
    public var headingIssue: HeadingIssue?

    public init(
      captureId: LowercaseUUID,
      areaKey: String,
      label: String,
      mode: CaptureMode,
      units: Units,
      capturedAt: UTCTimestamp,
      finishedAt: UTCTimestamp? = nil,
      coverageNotes: String = "",
      omittedRooms: [RoomNote] = [],
      inaccessibleRooms: [RoomNote] = [],
      heading: Double? = nil,
      headingAccuracy: Int? = nil,
      headingSource: HeadingSource? = nil,
      headingRecordedAt: UTCTimestamp? = nil,
      headingIssue: HeadingIssue? = nil
    ) {
      self.captureId = captureId
      self.areaKey = areaKey
      self.label = label
      self.mode = mode
      self.units = units
      self.capturedAt = capturedAt
      self.finishedAt = finishedAt
      self.coverageNotes = coverageNotes
      self.omittedRooms = omittedRooms
      self.inaccessibleRooms = inaccessibleRooms
      self.heading = heading
      self.headingAccuracy = headingAccuracy
      self.headingSource = headingSource
      self.headingRecordedAt = headingRecordedAt
      self.headingIssue = headingIssue
    }

    /// Records the result of the floor's compass reading: the four reading fields, or the issue
    /// (nil when the app could not tell why there is no reading), and clears the others. The
    /// heading is rounded to one decimal and kept in `0 ..< 360`; the accuracy is kept in
    /// `1 ... 180`, so the record stays valid against the schema.
    public mutating func setCompass(_ result: CompassResultValue) {
      switch result {
      case .reading(let heading, let accuracy, let source, let recordedAt):
        self.heading = CompassMath.storedHeading(heading)
        headingAccuracy = min(max(accuracy, 1), 180)
        headingSource = source
        headingRecordedAt = recordedAt
        headingIssue = nil
      case .none(let issue):
        heading = nil
        headingAccuracy = nil
        headingSource = nil
        headingRecordedAt = nil
        headingIssue = issue
      }
    }
  }

  /// Geometry is always metres; `display` is the unit system shown to the operator.
  public struct Units: Hashable, Sendable, Codable {
    public var length: LengthUnit
    public var display: DisplayUnitSystem

    public init(length: LengthUnit = .metres, display: DisplayUnitSystem) {
      self.length = length
      self.display = display
    }
  }

  public struct RoomNote: Hashable, Sendable, Codable {
    public var name: String
    public var reason: String?

    public init(name: String, reason: String? = nil) {
      self.name = name
      self.reason = reason
    }
  }
}
