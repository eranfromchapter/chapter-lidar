#if canImport(ARKit) && os(iOS)
  import ARKit
  import CaptureContract
  import Foundation

  /// The walkthrough on a phone (spec F15 2): ARKit world tracking (gravity-aligned, +Y up,
  /// horizontal plane detection; no LiDAR needed). Each frame, on its own queue: the reticle
  /// is where the screen centre's ray meets the floor (the floor plane, infinite, when it is
  /// known, else an estimated horizontal plane not far above it), the floor is the lowest
  /// stable horizontal plane, and `WalkthroughRecorder` writes the video and the frame poses.
  /// The AR view shows the same `ARSession` (`arSession`).
  @MainActor
  public final class LiveWalkthroughSession: WalkthroughSession {
    /// Every iPhone with iOS 17 runs world tracking; false on the simulator.
    nonisolated public static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    public var isSupported: Bool { Self.isSupported }
    public let updates: AsyncStream<WalkthroughFrameUpdate>
    /// The session the AR view draws (`ARSCNView.session`).
    public let arSession = ARSession()

    private let processor: WalkthroughFrameProcessor
    private var configuration: ARWorldTrackingConfiguration?

    public init() {
      let (stream, continuation) = AsyncStream.makeStream(
        of: WalkthroughFrameUpdate.self, bufferingPolicy: .bufferingNewest(1))
      updates = stream
      processor = WalkthroughFrameProcessor(continuation: continuation)
      processor.session = arSession
      arSession.delegate = processor
      arSession.delegateQueue = processor.queue
    }

    public func start(recordingTo url: URL?, clockZero: TimeInterval) {
      guard Self.isSupported else { return }
      let configuration = ARWorldTrackingConfiguration()
      configuration.planeDetection = [.horizontal]
      configuration.worldAlignment = .gravity
      self.configuration = configuration
      processor.begin(recordingTo: url, clockZero: clockZero)
      arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    public func pause() {
      arSession.pause()
    }

    public func resume() {
      guard let configuration else { return }
      arSession.run(configuration)
    }

    public func stop() async -> WalkthroughRecording {
      arSession.pause()
      return await processor.finish()
    }
  }

  /// The ARSession delegate: everything runs on `queue`, so ARFrames are never kept past their
  /// callback (the video frame is copied into the recorder's own buffer).
  final class WalkthroughFrameProcessor: NSObject, ARSessionDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.hellochapter.walkthrough.frames", qos: .userInitiated)
    weak var session: ARSession?
    private let continuation: AsyncStream<WalkthroughFrameUpdate>.Continuation
    private var recorder: WalkthroughRecorder?
    private var clockZero: TimeInterval = 0
    /// Horizontal planes: their height and area.
    private var planes: [UUID: (y: Double, area: Double)] = [:]
    private var floor: (id: UUID, y: Double)?
    private var lastEmitted: TimeInterval = 0
    private var finished = false

    /// The reticle and the overlay follow at about 30 updates a second.
    static let updateInterval: TimeInterval = 1.0 / 30
    /// A plane is the floor once it is this large (square metres).
    static let stableFloorArea = 0.25
    /// An estimated hit this far above the floor is furniture, not the floor (metres).
    static let aboveFloorLimit = 0.25

    init(continuation: AsyncStream<WalkthroughFrameUpdate>.Continuation) {
      self.continuation = continuation
    }

    func begin(recordingTo url: URL?, clockZero: TimeInterval) {
      queue.sync {
        self.clockZero = clockZero
        self.finished = false
        if let url {
          self.recorder = WalkthroughRecorder(url: url, clockZero: clockZero)
        }
      }
    }

    func finish() async -> WalkthroughRecording {
      await withCheckedContinuation { (done: CheckedContinuation<WalkthroughRecording, Never>) in
        queue.async {
          self.finished = true
          guard let recorder = self.recorder else {
            done.resume(returning: .none)
            return
          }
          self.recorder = nil
          recorder.finish { done.resume(returning: $0) }
        }
      }
    }

    // MARK: ARSessionDelegate (on `queue`)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
      guard !finished else { return }
      let tracking = Self.tracking(frame.camera.trackingState)
      recorder?.append(frame, tracking: tracking)
      guard frame.timestamp - lastEmitted >= Self.updateInterval else { return }
      lastEmitted = frame.timestamp
      continuation.yield(update(for: frame, session: session, tracking: tracking))
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
      note(anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
      note(anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
      for anchor in anchors { planes[anchor.identifier] = nil }
      chooseFloor()
    }

    // MARK: Frames

    private func update(
      for frame: ARFrame, session: ARSession, tracking: (WalkthroughTracking, WalkthroughTrackingReason?)
    ) -> WalkthroughFrameUpdate {
      let transform = frame.camera.transform
      let origin = transform.columns.3
      let forward = transform.columns.2
      let direction = Vec3(x: Double(-forward.x), y: Double(-forward.y), z: Double(-forward.z))
      return WalkthroughFrameUpdate(
        time: frame.timestamp, cameraTransform: Self.columnMajor(transform),
        tracking: tracking.0, trackingReason: tracking.1,
        floorHit: tracking.0 == .normal ? floorHit(frame, session: session) : nil,
        rayOrigin: Vec3(x: Double(origin.x), y: Double(origin.y), z: Double(origin.z)),
        rayDirection: direction, floorY: floor?.y)
    }

    /// The screen centre on the floor: the floor plane (infinite) when it is known, else the
    /// first estimated horizontal plane, unless that is well above the floor (a table).
    private func floorHit(_ frame: ARFrame, session: ARSession) -> Vec3? {
      let centre = CGPoint(x: 0.5, y: 0.5)
      if let floor {
        let query = frame.raycastQuery(
          from: centre, allowing: .existingPlaneInfinite, alignment: .horizontal)
        if let hit = session.raycast(query).first(where: { $0.anchor?.identifier == floor.id }) {
          let p = hit.worldTransform.columns.3
          return Vec3(x: Double(p.x), y: floor.y, z: Double(p.z))
        }
      }
      let query = frame.raycastQuery(from: centre, allowing: .estimatedPlane, alignment: .horizontal)
      guard let hit = session.raycast(query).first else { return nil }
      let p = hit.worldTransform.columns.3
      let y = Double(p.y)
      if let floor, y - floor.y > Self.aboveFloorLimit { return nil }
      return Vec3(x: Double(p.x), y: floor?.y ?? y, z: Double(p.z))
    }

    private func note(_ anchors: [ARAnchor]) {
      for case let plane as ARPlaneAnchor in anchors where plane.alignment == .horizontal {
        let extent = plane.planeExtent
        let area = Double(extent.width) * Double(extent.height)
        let y = Double(plane.transform.columns.3.y) + Double(plane.center.y)
        planes[plane.identifier] = (y, area)
      }
      chooseFloor()
    }

    /// The floor: the lowest horizontal plane that is large enough.
    private func chooseFloor() {
      let stable = planes.filter { $0.value.area >= Self.stableFloorArea }
      guard let lowest = stable.min(by: { $0.value.y < $1.value.y }) else { return }
      floor = (lowest.key, lowest.value.y)
    }

    static func tracking(_ state: ARCamera.TrackingState)
      -> (WalkthroughTracking, WalkthroughTrackingReason?)
    {
      switch state {
      case .normal:
        return (.normal, nil)
      case .notAvailable:
        return (.notAvailable, nil)
      case .limited(let reason):
        switch reason {
        case .excessiveMotion: return (.limited, .excessiveMotion)
        case .insufficientFeatures: return (.limited, .insufficientFeatures)
        case .relocalizing: return (.limited, .relocalizing)
        case .initializing: return (.limited, .initializing)
        @unknown default: return (.limited, nil)
        }
      }
    }

    /// A transform as the log writes it: 16 numbers, column-major.
    static func columnMajor(_ m: simd_float4x4) -> [Double] {
      [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { column in
        [Double(column.x), Double(column.y), Double(column.z), Double(column.w)]
      }
    }
  }
#endif
