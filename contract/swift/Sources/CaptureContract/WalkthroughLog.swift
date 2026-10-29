/// contract/schema/walkthrough-log.schema.json: the raw record of one AR walkthrough capture
/// (spec F15): when it ran, the camera intrinsics, the camera pose of each recorded video frame,
/// the floor height, and every tap the operator made, room by room, with the scale check.
/// Written as `Original Exports/{areaKey}/{captureId}/walkthrough-log.json` (role
/// `walkthrough_log`) next to `walkthrough.mp4` (role `walkthrough_video`). Points and transforms
/// are in the walkthrough's own AR frame: metres, right-handed, +Y up. Times are seconds since
/// `startedAt`.
public struct WalkthroughLog: Hashable, Sendable, Codable {
  public var schemaVersion: WalkthroughLogSchemaVersion
  public var visitId: LowercaseUUID
  public var captureId: LowercaseUUID
  public var areaKey: String
  public var startedAt: UTCTimestamp
  public var finishedAt: UTCTimestamp
  /// The recorded video; nil when nothing was recorded.
  public var video: Video?
  /// Camera intrinsics of the recorded frames, in pixels of the video.
  public var intrinsics: Intrinsics?
  /// Height of the floor plane the corner taps lie on.
  public var floorY: Double
  /// The camera pose of each recorded video frame, in time order.
  public var frames: [Frame]
  public var rooms: [Room]
  /// The tape length of one walked wall; every length is scaled by tape / AR length.
  public var scaleCheck: ScaleCheck?

  public init(
    schemaVersion: WalkthroughLogSchemaVersion = .current, visitId: LowercaseUUID,
    captureId: LowercaseUUID, areaKey: String, startedAt: UTCTimestamp, finishedAt: UTCTimestamp,
    video: Video? = nil, intrinsics: Intrinsics? = nil, floorY: Double, frames: [Frame] = [],
    rooms: [Room], scaleCheck: ScaleCheck? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.visitId = visitId
    self.captureId = captureId
    self.areaKey = areaKey
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.video = video
    self.intrinsics = intrinsics
    self.floorY = floorY
    self.frames = frames
    self.rooms = rooms
    self.scaleCheck = scaleCheck
  }

  public struct Video: Hashable, Sendable, Codable {
    /// Package path of the video (role `walkthrough_video`).
    public var path: String
    public var width: Int
    public var height: Int
    public var framesPerSecond: Double

    public init(path: String, width: Int, height: Int, framesPerSecond: Double) {
      self.path = path
      self.width = width
      self.height = height
      self.framesPerSecond = framesPerSecond
    }
  }

  public struct Intrinsics: Hashable, Sendable, Codable {
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double
    public var width: Int
    public var height: Int

    public init(fx: Double, fy: Double, cx: Double, cy: Double, width: Int, height: Int) {
      self.fx = fx
      self.fy = fy
      self.cx = cx
      self.cy = cy
      self.width = width
      self.height = height
    }
  }

  public struct Frame: Hashable, Sendable, Codable {
    /// Seconds since `startedAt`.
    public var t: Double
    /// Camera-to-world transform, 16 numbers column-major.
    public var transform: [Double]
    public var tracking: WalkthroughTracking

    public init(t: Double, transform: [Double], tracking: WalkthroughTracking) {
      self.t = t
      self.transform = transform
      self.tracking = tracking
    }
  }

  /// One tap: the point, when, and how well ARKit was tracking.
  public struct Tap: Hashable, Sendable, Codable {
    public var p: Vec3
    /// Seconds since `startedAt`.
    public var t: Double
    public var tracking: WalkthroughTracking

    public init(p: Vec3, t: Double, tracking: WalkthroughTracking = .normal) {
      self.p = p
      self.t = t
      self.tracking = tracking
    }
  }

  /// A length typed by the operator (the scale check). Always measured with a tape.
  public struct Length: Hashable, Sendable, Codable {
    public var valueMm: Double
    public var enteredUnit: EnteredUnit
    public var enteredText: String

    public init(valueMm: Double, enteredUnit: EnteredUnit, enteredText: String) {
      self.valueMm = valueMm
      self.enteredUnit = enteredUnit
      self.enteredText = enteredText
    }
  }

  public struct Room: Hashable, Sendable, Codable {
    public var id: String
    public var label: String
    public var type: RoomType?
    public var method: WalkthroughMethod
    /// `corners`: the corner taps in walking order (at least three).
    public var corners: [Tap]?
    /// `corners`: the tap back on the first corner that closed the room.
    public var closingTap: Tap?
    /// `walls`: per wall, in walking order, two or more taps along its base.
    public var walls: [[Tap]]?
    /// Taps where a wall meets the ceiling.
    public var ceiling: [Tap]
    public var openings: [Opening]

    public init(
      id: String, label: String, type: RoomType? = nil, method: WalkthroughMethod,
      corners: [Tap]? = nil, closingTap: Tap? = nil, walls: [[Tap]]? = nil, ceiling: [Tap] = [],
      openings: [Opening] = []
    ) {
      self.id = id
      self.label = label
      self.type = type
      self.method = method
      self.corners = corners
      self.closingTap = closingTap
      self.walls = walls
      self.ceiling = ceiling
      self.openings = openings
    }
  }

  public struct Opening: Hashable, Sendable, Codable {
    public var id: String
    public var kind: SketchOpeningKind
    /// Wall `i` runs from corner `i` to corner `i + 1`.
    public var wallIndex: Int
    /// At the floor for a door or opening, on the wall plane for a window.
    public var leftJamb: Tap
    public var rightJamb: Tap
    /// The top of the opening, on the wall plane.
    public var head: Tap?
    /// Windows only: the sill, on the wall plane.
    public var sill: Tap?

    public init(
      id: String, kind: SketchOpeningKind, wallIndex: Int, leftJamb: Tap, rightJamb: Tap,
      head: Tap? = nil, sill: Tap? = nil
    ) {
      self.id = id
      self.kind = kind
      self.wallIndex = wallIndex
      self.leftJamb = leftJamb
      self.rightJamb = rightJamb
      self.head = head
      self.sill = sill
    }
  }

  public struct ScaleCheck: Hashable, Sendable, Codable {
    public var roomId: String
    /// Wall `i` runs from corner `i` to corner `i + 1`.
    public var wallIndex: Int
    public var tape: Length

    public init(roomId: String, wallIndex: Int, tape: Length) {
      self.roomId = roomId
      self.wallIndex = wallIndex
      self.tape = tape
    }
  }
}
