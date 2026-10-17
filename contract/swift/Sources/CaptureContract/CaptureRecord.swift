/// contract/schema/capture-record.schema.json: who captured what, where, when and how, for one
/// site visit at one property. A visit holds one or more captures; each capture is one floor or
/// area scanned in one mode, registered separately with its own `captureId`. Written as
/// `Source Register/{visitId}/capture-record.json`.
public struct CaptureRecord: Hashable, Sendable, Codable {
  public var schemaVersion: SchemaVersion
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
    schemaVersion: SchemaVersion = .current,
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
      inaccessibleRooms: [RoomNote] = []
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
