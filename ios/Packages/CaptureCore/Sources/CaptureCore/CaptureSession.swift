import CaptureContract
import CaptureModelMapping
import Foundation

public enum CaptureSessionState: Sendable, Equatable {
  case idle
  case running
  case paused
  case finishing
  case finished
  case failed(String)
}

/// Counts shown on the live scan screen.
public struct ScanCounts: Sendable, Equatable {
  public var walls: Int
  public var doors: Int
  public var windows: Int
  public var rooms: Int
  public var openings: Int
  public var objects: Int

  public init(walls: Int = 0, doors: Int = 0, windows: Int = 0, rooms: Int = 0, openings: Int = 0, objects: Int = 0) {
    self.walls = walls
    self.doors = doors
    self.windows = windows
    self.rooms = rooms
    self.openings = openings
    self.objects = objects
  }

  public init(document: RoomPlanDocument) {
    self.init(
      walls: document.rooms.reduce(0) { $0 + $1.walls.count },
      doors: document.rooms.reduce(0) { $0 + $1.doors.count },
      windows: document.rooms.reduce(0) { $0 + $1.windows.count },
      rooms: document.rooms.count,
      openings: document.rooms.reduce(0) { $0 + $1.openings.count },
      objects: document.rooms.reduce(0) { $0 + $1.objects.count })
  }
}

public struct ScanProgress: Sendable, Equatable {
  public var counts: ScanCounts
  /// Seconds the scan has been running (paused time is not counted).
  public var elapsed: TimeInterval
  public var depthSampleCount: Int
  public var meshAnchorCount: Int

  public init(counts: ScanCounts = ScanCounts(), elapsed: TimeInterval = 0, depthSampleCount: Int = 0, meshAnchorCount: Int = 0) {
    self.counts = counts
    self.elapsed = elapsed
    self.depthSampleCount = depthSampleCount
    self.meshAnchorCount = meshAnchorCount
  }
}

/// Guidance from RoomPlan while scanning.
public enum ScanInstruction: String, Sendable, Equatable, CaseIterable {
  case normal
  case moveCloseToWall
  case moveAwayFromWall
  case slowDown
  case turnOnLight
  case lowTexture

  /// Shown on the live scan screen. `normal` is the design's own hint.
  public var message: String {
    switch self {
    case .normal: return "Move slowly along the walls"
    case .moveCloseToWall: return "Move closer to the wall"
    case .moveAwayFromWall: return "Move away from the wall"
    case .slowDown: return "Slow down"
    case .turnOnLight: return "Turn on a light"
    case .lowTexture: return "Point at a surface with more detail"
    }
  }
}

public enum CaptureSessionEvent: Sendable, Equatable {
  case stateChanged(CaptureSessionState)
  case progress(ScanProgress)
  case instruction(ScanInstruction)
}

public struct CaptureSessionConfiguration: Sendable, Equatable {
  public var mode: CaptureMode
  /// Depth points below this ARConfidenceLevel raw value are dropped when sampling.
  public var minimumDepthConfidence: UInt8

  public init(mode: CaptureMode, minimumDepthConfidence: UInt8 = DepthSample.mediumConfidence) {
    self.mode = mode
    self.minimumDepthConfidence = minimumDepthConfidence
  }
}

public enum CaptureSessionError: Error, Equatable, CustomStringConvertible {
  case invalidState(String)
  case deviceNotSupported(String)
  case scanFailed(String)
  case noRoomsCaptured
  /// The phone is too hot to scan (RoomPlan's deviceTooHot, or a serious thermal state).
  case tooHot
  /// World tracking was lost and RoomPlan stopped.
  case trackingLost
  /// The area is larger than RoomPlan can hold in one scan.
  case areaTooLarge

  public var description: String {
    switch self {
    case .invalidState(let message): return message
    case .deviceNotSupported(let message): return message
    case .scanFailed(let message): return "The scan failed: \(message)"
    case .noRoomsCaptured: return "Nothing was captured. Scan at least one wall before finishing."
    case .tooHot:
      return "The phone is too hot to scan. Let it cool down for a few minutes, out of the sun and "
        + "out of its case, then tap Try again."
    case .trackingLost:
      return "The phone lost track of the room. Tap Try again, turn the lights on and move slowly."
    case .areaTooLarge:
      return "This area is too large for one scan. Finish this floor and scan the rest as another area."
    }
  }

  /// True for a failure that ends the scan; the screen then offers Try again.
  public var endsTheScan: Bool {
    switch self {
    case .scanFailed, .tooHot, .trackingLost, .areaTooLarge: return true
    case .invalidState, .deviceNotSupported, .noRoomsCaptured: return false
    }
  }
}

/// What a finished scan hands to the rest of the app.
public struct CaptureSessionResult: Sendable, Equatable {
  public var originals: RawOriginals
  public var startedAt: Date
  public var finishedAt: Date

  public init(originals: RawOriginals, startedAt: Date, finishedAt: Date) {
    self.originals = originals
    self.startedAt = startedAt
    self.finishedAt = finishedAt
  }

  /// The RoomPlan capture decoded from the original JSON.
  public func roomPlanDocument() throws -> RoomPlanDocument {
    try RoomPlanDocument.decode(from: originals.roomPlanJSON)
  }

  /// The contract `CaptureModel` of this scan.
  public func captureModel(context: MappingContext) throws -> CaptureModel {
    try CaptureModelMapper.map(try roomPlanDocument(), context: context)
  }
}

/// One scan of one floor or area. The live implementation (RoomPlan + ARKit) is in the
/// `CaptureRoomPlan` target; `ReplaySession` plays back a recording so everything above it can
/// be tested without a device.
///
/// Flow: `start`, then any number of `pause` and `resume` (each pause ends a RoomPlan segment
/// of the same floor; a whole floor is joined from its segments), then `finish`.
public protocol CaptureSession: AnyObject, Sendable {
  /// State changes, progress and guidance. Finishes when the session ends. One consumer.
  var events: AsyncStream<CaptureSessionEvent> { get }

  func start(_ configuration: CaptureSessionConfiguration) async throws
  func pause() async throws
  func resume() async throws
  /// Stops the scan and returns the originals. Throws `noRoomsCaptured` for an empty scan.
  func finish() async throws -> CaptureSessionResult
  /// Stops without a result. Nothing is written.
  func cancel() async
}
