import CaptureContract
import Foundation

/// A scripted walkthrough (UI tests, the simulator): the camera stands at `eye` and looks at
/// one scripted point after the other, one per "advance" (each tap of +). A point on the floor
/// (`y` within 1 cm of `floorY`) is where the reticle sits; a point higher up is where the
/// centre ray meets a wall, so the screen finds it the way it does on the phone.
public struct WalkthroughReplayScript: Codable, Sendable, Equatable {
  public var floorY: Double
  /// Where the camera stands for every point (inside the room, at eye height).
  public var eye: Vec3
  public var points: [Point]

  public struct Point: Codable, Sendable, Equatable {
    /// What the screen centre points at.
    public var target: Vec3
    /// Tracking while pointing there; normal when absent.
    public var tracking: WalkthroughTracking?
    /// What the point is, for the reader of the script ("corner 1", "window 1 sill").
    public var note: String?

    public init(target: Vec3, tracking: WalkthroughTracking? = nil, note: String? = nil) {
      self.target = target
      self.tracking = tracking
      self.note = note
    }
  }

  public init(floorY: Double, eye: Vec3, points: [Point]) {
    self.floorY = floorY
    self.eye = eye
    self.points = points
  }

  public static func load(from url: URL) throws -> WalkthroughReplayScript {
    try JSONDecoder().decode(WalkthroughReplayScript.self, from: Data(contentsOf: url))
  }
}

/// The walkthrough session of the UI tests and the simulator (spec F15 2): plays a
/// `WalkthroughReplayScript`, one point per `advance()`; records no video, only one frame pose
/// per point played. After the last point the camera keeps looking at it.
@MainActor
public final class ReplayWalkthroughSession: WalkthroughSession {
  public let isSupported = true
  public let updates: AsyncStream<WalkthroughFrameUpdate>
  public let script: WalkthroughReplayScript
  /// The point the camera looks at now.
  public private(set) var index = 0
  public private(set) var isRunning = false

  private let continuation: AsyncStream<WalkthroughFrameUpdate>.Continuation
  private var clockZero: TimeInterval = 0
  private var frames: [WalkthroughLog.Frame] = []
  private let clock: () -> TimeInterval

  public init(script: WalkthroughReplayScript, clock: @escaping () -> TimeInterval = WalkthroughClock.now) {
    self.script = script
    self.clock = clock
    (updates, continuation) = AsyncStream.makeStream(
      of: WalkthroughFrameUpdate.self, bufferingPolicy: .bufferingNewest(1))
  }

  public func start(recordingTo url: URL?, clockZero: TimeInterval) {
    self.clockZero = clockZero
    isRunning = true
    emit()
  }

  public func pause() {
    isRunning = false
  }

  public func resume() {
    isRunning = true
    emit()
  }

  public func stop() async -> WalkthroughRecording {
    isRunning = false
    continuation.finish()
    return WalkthroughRecording(frames: frames)
  }

  public func advance() {
    guard index + 1 < script.points.count else { return }
    index += 1
    emit()
  }

  /// The update for the current point.
  public func currentUpdate() -> WalkthroughFrameUpdate? {
    guard script.points.indices.contains(index) else { return nil }
    let point = script.points[index]
    let eye = WPoint(script.eye)
    let target = WPoint(point.target)
    var direction = target - eye
    let length = direction.length
    direction = length > 1e-9 ? direction * (1 / length) : WPoint(0, 0, -1)
    var floorHit: Vec3?
    if abs(point.target.y - script.floorY) < 0.01 {
      floorHit = Vec3(x: point.target.x, y: script.floorY, z: point.target.z)
    }
    let tracking = point.tracking ?? .normal
    return WalkthroughFrameUpdate(
      time: clock(), cameraTransform: WalkthroughSpace.lookTransform(eye: eye, direction: direction),
      tracking: tracking, trackingReason: tracking == .normal ? nil : .excessiveMotion,
      floorHit: tracking == .normal ? floorHit : nil, rayOrigin: script.eye,
      rayDirection: direction.vec3, floorY: script.floorY)
  }

  private func emit() {
    guard isRunning, let update = currentUpdate() else { return }
    frames.append(
      WalkthroughLog.Frame(
        t: max(0, update.time - clockZero), transform: update.cameraTransform,
        tracking: update.tracking))
    continuation.yield(update)
  }
}
