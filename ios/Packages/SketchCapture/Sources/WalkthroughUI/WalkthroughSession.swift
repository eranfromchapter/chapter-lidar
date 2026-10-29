import CaptureContract
import Foundation

// The AR session behind the walkthrough screen (spec F15 2), as a protocol so the screen and
// its model run with ARKit on a phone (`LiveWalkthroughSession`) and with a scripted replay in
// UI tests and on the simulator, where ARKit does not run (`ReplayWalkthroughSession`).
// Foundation only: the model and the replay are tested on Linux and macOS.

/// Why ARKit tracking is limited, as the screen says it ("Move slower", "More light").
public enum WalkthroughTrackingReason: String, Sendable, Equatable {
  case initializing
  case excessiveMotion
  case insufficientFeatures
  case relocalizing
}

/// One camera frame as the walkthrough needs it: where the camera is, how well it is tracked,
/// where the centre of the screen meets the floor, and the centre ray for points on a wall.
public struct WalkthroughFrameUpdate: Sendable, Equatable {
  /// Seconds on the system uptime clock (`ProcessInfo.systemUptime`, the clock of
  /// `ARFrame.timestamp`).
  public var time: TimeInterval
  /// Camera-to-world, 16 numbers column-major (the log's frame transform).
  public var cameraTransform: [Double]
  public var tracking: WalkthroughTracking
  /// Why tracking is limited; nil when normal.
  public var trackingReason: WalkthroughTrackingReason?
  /// Where the screen-centre reticle sits on the floor; nil when no floor is under it.
  public var floorHit: Vec3?
  /// The ray through the screen centre: the camera position and its unit viewing direction.
  public var rayOrigin: Vec3
  public var rayDirection: Vec3
  /// Height of the floor plane (the lowest stable horizontal plane); nil until one is found.
  public var floorY: Double?

  public init(
    time: TimeInterval, cameraTransform: [Double], tracking: WalkthroughTracking,
    trackingReason: WalkthroughTrackingReason? = nil, floorHit: Vec3?, rayOrigin: Vec3,
    rayDirection: Vec3, floorY: Double?
  ) {
    self.time = time
    self.cameraTransform = cameraTransform
    self.tracking = tracking
    self.trackingReason = trackingReason
    self.floorHit = floorHit
    self.rayOrigin = rayOrigin
    self.rayDirection = rayDirection
    self.floorY = floorY
  }
}

/// What a session recorded when it stopped: the video file (when it finished), its size and
/// rate, the intrinsics scaled to the video, and the pose of every recorded frame.
public struct WalkthroughRecording: Sendable {
  /// The finished video; nil when nothing was recorded or the recording failed.
  public var videoURL: URL?
  public var width: Int
  public var height: Int
  public var framesPerSecond: Double
  public var intrinsics: WalkthroughLog.Intrinsics?
  /// One per recorded frame, `t` in seconds since the walkthrough started.
  public var frames: [WalkthroughLog.Frame]
  /// Why the video is missing or short ("The video could not be written: …"); nil when fine.
  public var problem: String?

  public init(
    videoURL: URL? = nil, width: Int = 0, height: Int = 0, framesPerSecond: Double = 0,
    intrinsics: WalkthroughLog.Intrinsics? = nil, frames: [WalkthroughLog.Frame] = [],
    problem: String? = nil
  ) {
    self.videoURL = videoURL
    self.width = width
    self.height = height
    self.framesPerSecond = framesPerSecond
    self.intrinsics = intrinsics
    self.frames = frames
    self.problem = problem
  }

  public static let none = WalkthroughRecording()
}

/// An AR session for the walkthrough. The model starts it once, reads `updates` for as long
/// as it lives, pauses it while the scale and check screens are up and stops it at Finish
/// floor (which finishes the recording).
@MainActor
public protocol WalkthroughSession: AnyObject {
  /// The phone runs ARKit world tracking (`ARWorldTrackingConfiguration.isSupported`; every
  /// iPhone with iOS 17). Always true for the replay.
  var isSupported: Bool { get }
  /// Every frame, newest kept when the reader is slow. One reader.
  var updates: AsyncStream<WalkthroughFrameUpdate> { get }
  /// Starts tracking and, with `recordingTo`, the video (`walkthrough.mp4`) and the frame
  /// log. `clockZero` is the uptime the walkthrough's times count from.
  func start(recordingTo url: URL?, clockZero: TimeInterval)
  func pause()
  func resume()
  /// Stops tracking and finishes the recording. Never throws: a recording error is reported
  /// in `WalkthroughRecording.problem` and the taps stay.
  func stop() async -> WalkthroughRecording
  /// The operator tapped +: a replay moves to its next scripted point; the live session does
  /// nothing.
  func advance()
}

extension WalkthroughSession {
  public func advance() {}
}

/// The uptime clock of the walkthrough's times.
public enum WalkthroughClock {
  public static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
