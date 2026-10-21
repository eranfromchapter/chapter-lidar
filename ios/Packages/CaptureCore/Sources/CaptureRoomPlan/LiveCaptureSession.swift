#if canImport(RoomPlan) && canImport(ARKit) && os(iOS)
  import ARKit
  import CaptureCompass
  import CaptureContract
  import CaptureCore
  import CaptureModelMapping
  import Foundation
  import Metal
  import RoomPlan
  import os
  import simd

  /// The live scan: Apple RoomPlan and ARKit LiDAR behind the `CaptureSession` API.
  ///
  /// - One `ARSession` is shared by every RoomPlan segment. `pause()` ends the current segment
  ///   (`RoomCaptureSession.stop(pauseARSession: false)`, so world tracking continues), and
  ///   `resume()` starts the next segment on the same ARSession. `finish()` joins the segments
  ///   of the floor with `StructureBuilder`. One segment gives a `CapturedRoom`, several give a
  ///   `CapturedStructure`; either is encoded with RoomPlan's own Codable and kept as the raw original.
  /// - While scanning, a 4 Hz timer reads `arSession.currentFrame` and samples scene depth
  ///   (confidence of medium or better), camera pose and intrinsics, and collects the latest
  ///   `ARMeshAnchor` geometry.
  ///
  /// The depth and mesh sampling reads the frames of the ARSession that RoomPlan runs. If RoomPlan's
  /// own configuration does not provide `sceneDepth` or scene reconstruction on a device, the
  /// originals hold empty depth and mesh; the live counts show `depthSampleCount` and
  /// `meshAnchorCount` so that is visible during a scan.
  ///
  /// Tracking (phone-capture §5.5): each tick reads `frame.camera.trackingState` into a
  /// `TrackingMonitor` and emits `.tracking` when it is lost or back. While a frame is not
  /// tracked normally nothing is sampled, so no depth, pose or mesh comes from a drifting frame.
  ///
  /// Compass (compass §3.3, §3.4): with the app's `CompassService`, each tick pairs the frame
  /// with the Core Motion sample nearest to it (25 ms) and feeds a `HeadingWindow`; the chip
  /// follows as `.compass` events. Pause and resume keep the ARSession, so the reading stays
  /// valid; a new session reads again. At `finish()` the frame check compares the surfaces of
  /// RoomPlan's last live update with the final result and the reading goes into
  /// `CaptureSessionResult.compass`. Without a compass service the result is no reading, with
  /// the issue `unavailable` (no compass sample reached the scan).
  @MainActor
  public final class LiveCaptureSession: NSObject, CaptureSession, RoomCaptureSessionDelegate {
    public nonisolated let events: AsyncStream<CaptureSessionEvent>
    private let continuation: AsyncStream<CaptureSessionEvent>.Continuation

    /// The ARSession shared by all segments.
    public let arSession = ARSession()

    /// Apple's RoomPlan view on the shared ARSession: the camera feed with the live outline of
    /// walls, doors, windows and objects, and RoomPlan's own coaching ("Move closer", "Slow
    /// down", relocalization). `CaptureSessionPreview` shows it. Every segment runs this view's
    /// `captureSession`, so the outline follows the scan.
    public private(set) lazy var captureView: RoomCaptureView = RoomCaptureView(
      frame: .zero, arSession: arSession)

    /// Most depth points kept per capture (16 bytes each in `depth-samples.bin`).
    static let maxDepthSamples = 3_000_000
    /// Every `depthStride`-th pixel of the 256 x 192 depth map is sampled.
    static let depthStride = 8
    static let tickInterval: TimeInterval = 0.25

    private var state: CaptureSessionState = .idle
    private var configuration: CaptureSessionConfiguration?
    private var startedAt: Date?

    private var roomSession: RoomCaptureSession?
    private var pendingEnd: CheckedContinuation<CapturedRoomData, Error>?
    private var segments: [CapturedRoom] = []
    private var completedCounts = ScanCounts()
    private var currentCounts = ScanCounts()

    private var tickTimer: Timer?
    private var lastTick = Date()
    private var elapsed: TimeInterval = 0
    private var baseFrameTimestamp: TimeInterval?
    private var lastFrameTimestamp: TimeInterval = -1

    private var depthSamples: [DepthSample] = []
    private var poseFrames: [CameraPose] = []
    private var intrinsics: CameraIntrinsics?
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]

    private let compass: CompassService?
    private var headingWindow = HeadingWindow()
    private var lastCompassState: CompassLiveState?
    private var tracking = TrackingMonitor()
    /// Plan-frame yaw of every surface in RoomPlan's last live update, by identifier.
    private var liveSurfaceYaws: [String: Double] = [:]
    private var compassSensorsRunning = false
    nonisolated static let log = Logger(subsystem: "com.hellochapter.capture", category: "compass")

    /// `compass`: the app's one compass; nil reads none.
    public init(compass: CompassService? = nil) {
      self.compass = compass
      (events, continuation) = AsyncStream.makeStream(of: CaptureSessionEvent.self)
      super.init()
    }

    // MARK: CaptureSession

    public func start(_ configuration: CaptureSessionConfiguration) async throws {
      guard state == .idle else {
        throw CaptureSessionError.invalidState("The scan has already started.")
      }
      if let message = DeviceGate.evaluate(DeviceCapabilities.current()).message {
        throw CaptureSessionError.deviceNotSupported(message)
      }
      // RoomPlan stops a second into the scan with deviceTooHot when the phone is hot; say so
      // before starting (field test, 2026-10-19, after several scans in a row).
      switch ProcessInfo.processInfo.thermalState {
      case .serious, .critical: throw CaptureSessionError.tooHot
      default: break
      }
      self.configuration = configuration
      startedAt = Date()
      segments = []
      completedCounts = ScanCounts()
      depthSamples = []
      poseFrames = []
      intrinsics = nil
      meshAnchors = [:]
      elapsed = 0
      baseFrameTimestamp = nil
      lastFrameTimestamp = -1
      headingWindow = HeadingWindow()
      lastCompassState = nil
      tracking = TrackingMonitor()
      liveSurfaceYaws = [:]
      startCompass()
      startSegment()
      startTimer()
      setState(.running)
      emitCompass(worldFromCamera: nil)
      continuation.yield(.instruction(.normal))
      emitProgress()
    }

    public func pause() async throws {
      guard state == .running else {
        throw CaptureSessionError.invalidState("Only a running scan can be paused.")
      }
      stopTimer()
      try await endSegment(pauseARSession: false)
      setState(.paused)
      emitProgress()
    }

    public func resume() async throws {
      guard state == .paused else {
        throw CaptureSessionError.invalidState("Only a paused scan can be resumed.")
      }
      startSegment()
      startTimer()
      setState(.running)
    }

    public func finish() async throws -> CaptureSessionResult {
      guard state == .running || state == .paused, let startedAt else {
        throw CaptureSessionError.invalidState("There is no scan to finish.")
      }
      let wasRunning = state == .running
      stopTimer()
      setState(.finishing)
      do {
        if wasRunning {
          try await endSegment(pauseARSession: true)
        } else {
          arSession.pause()
        }
        guard segments.contains(where: { !$0.walls.isEmpty }) else {
          throw CaptureSessionError.noRoomsCaptured
        }
        let json: Data
        let finalYaws: [String: Double]
        if segments.count == 1 {
          json = try RoomPlanAdapter.encode(segments[0])
          finalYaws = Self.surfaceYaws(of: segments[0])
        } else {
          let structure = try await StructureBuilder(options: [.beautifyObjects]).capturedStructure(
            from: segments)
          json = try RoomPlanAdapter.encode(structure)
          finalYaws = Self.surfaceYaws(of: structure)
        }
        let (compassResult, diagnostics) = finishCompass(finalYaws: finalYaws)
        let originals = RawOriginals(
          roomPlanJSON: json, depthSamples: depthSamples,
          cameraPoses: CameraPoseLog(intrinsics: intrinsics, frames: poseFrames),
          meshAnchors: meshAnchors.values.sorted { $0.identifier.uuidString < $1.identifier.uuidString }
            .compactMap(Self.rawMesh))
        setState(.finished)
        continuation.finish()
        return CaptureSessionResult(
          originals: originals, startedAt: startedAt, finishedAt: Date(), compass: compassResult,
          compassDiagnostics: diagnostics)
      } catch let error as CaptureSessionError {
        failed(error)
        throw error
      } catch {
        let wrapped = CaptureSessionError.scanFailed(error.localizedDescription)
        failed(wrapped)
        throw wrapped
      }
    }

    public func cancel() async {
      guard state != .idle, state != .finished else { return }
      stopTimer()
      stopCompass()
      roomSession?.stop(pauseARSession: true)
      roomSession = nil
      arSession.pause()
      pendingEnd?.resume(throwing: CancellationError())
      pendingEnd = nil
      state = .idle
      continuation.yield(.stateChanged(.idle))
      continuation.finish()
    }

    // MARK: Segments

    private func startSegment() {
      let session: RoomCaptureSession = captureView.captureSession
      session.delegate = self
      var roomConfiguration = RoomCaptureSession.Configuration()
      roomConfiguration.isCoachingEnabled = true
      roomSession = session
      currentCounts = ScanCounts()
      session.run(configuration: roomConfiguration)
    }

    /// Stops the current RoomPlan segment, waits for its data and builds the `CapturedRoom`.
    private func endSegment(pauseARSession: Bool) async throws {
      guard let session = roomSession else { return }
      let data: CapturedRoomData
      do {
        data = try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<CapturedRoomData, Error>) in
          pendingEnd = continuation
          session.stop(pauseARSession: pauseARSession)
        }
      } catch {
        roomSession = nil
        throw Self.sessionError(error)
      }
      roomSession = nil
      do {
        let room = try await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: data)
        segments.append(room)
        completedCounts = Self.sum(completedCounts, RoomPlanAdapter.counts(of: room))
        currentCounts = ScanCounts()
      } catch {
        throw CaptureSessionError.scanFailed(error.localizedDescription)
      }
    }

    // MARK: RoomCaptureSessionDelegate

    nonisolated public func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
      let counts = RoomPlanAdapter.counts(of: room)
      let yaws = Self.surfaceYaws(of: room)
      Task { @MainActor in
        self.currentCounts = counts
        // Per segment the last update wins; earlier segments keep theirs (identifiers differ).
        self.liveSurfaceYaws.merge(yaws) { _, new in new }
        self.emitProgress()
      }
    }

    nonisolated public func captureSession(
      _ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction
    ) {
      let mapped: ScanInstruction
      switch instruction {
      case .moveCloseToWall: mapped = .moveCloseToWall
      case .moveAwayFromWall: mapped = .moveAwayFromWall
      case .slowDown: mapped = .slowDown
      case .turnOnLight: mapped = .turnOnLight
      case .lowTexture: mapped = .lowTexture
      case .normal: mapped = .normal
      @unknown default: mapped = .normal
      }
      Task { @MainActor in self.continuation.yield(.instruction(mapped)) }
    }

    nonisolated public func captureSession(
      _ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?
    ) {
      Task { @MainActor in
        if let pending = self.pendingEnd {
          self.pendingEnd = nil
          if let error {
            pending.resume(throwing: error)
          } else {
            pending.resume(returning: data)
          }
        } else if let error {
          // RoomPlan ended the scan on its own.
          self.failed(Self.sessionError(error))
        }
      }
    }

    // MARK: Sampling

    private func startTimer() {
      lastTick = Date()
      tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.tick() }
      }
    }

    private func stopTimer() {
      tickTimer?.invalidate()
      tickTimer = nil
    }

    private func tick() {
      guard state == .running else { return }
      let now = Date()
      elapsed += now.timeIntervalSince(lastTick)
      lastTick = now
      let startPeriodEnded = headingWindow.advance(runningTime: elapsed)
      var worldFromCamera: CompassMath.Matrix3?
      if let frame = arSession.currentFrame, frame.timestamp != lastFrameTimestamp {
        lastFrameTimestamp = frame.timestamp
        if let status = tracking.update(
          Self.quality(frame.camera.trackingState), at: frame.timestamp, date: now)
        {
          continuation.yield(.tracking(status))
        }
        // Nothing is taken from a frame that is not tracked normally ("Recording paused").
        if tracking.isSampling { sample(frame) }
        let camera = Self.rotation(frame.camera.transform)
        worldFromCamera = camera
        pairCompass(frame, worldFromCamera: camera, date: now)
      }
      if worldFromCamera != nil || startPeriodEnded {
        emitCompass(worldFromCamera: worldFromCamera)
      }
      emitProgress()
    }

    // MARK: Compass

    private func startCompass() {
      guard let compass else { return }
      if compass.isUnavailableForScan { headingWindow.markUnavailable() }
      compass.startScanSensors()
      compassSensorsRunning = true
    }

    private func stopCompass() {
      guard compassSensorsRunning, let compass else { return }
      compass.stopScanSensors()
      compassSensorsRunning = false
    }

    /// Pairs the frame with Core Motion (compass §3.3 steps 1–2) and feeds the window.
    private func pairCompass(_ frame: ARFrame, worldFromCamera: CompassMath.Matrix3, date: Date) {
      guard let compass, compassSensorsRunning, !headingWindow.isDone else { return }
      guard let motion = compass.motionRing.nearest(to: frame.timestamp) else {
        headingWindow.addUnpaired()
        return
      }
      let pair = CompassPair(
        timestamp: frame.timestamp, runningTime: elapsed, date: date,
        trackingNormal: frame.camera.trackingState == .normal, worldFromCamera: worldFromCamera,
        motion: motion, heading: compass.latestHeading)
      let wasMismatch = headingWindow.diagnostics.conventionMismatch
      headingWindow.add(pair)
      if headingWindow.diagnostics.conventionMismatch, !wasMismatch {
        // Compass §2.2: a transposed matrix or a wrong camera mapping on this phone. The bad
        // pairs are dropped, so no wrong heading is recorded; the log makes it visible.
        Self.log.fault("compass.convention_mismatch: most pairs of the first 10 s fail gravity")
      }
    }

    /// Emits the chip's state when it changed (the camera bearing changes it at every tick).
    private func emitCompass(worldFromCamera: CompassMath.Matrix3?) {
      var state = headingWindow.liveState(worldFromCamera: worldFromCamera)
      // Keep the last bearing while the camera points steeply up or down, or between frames.
      if case .result(let compassState, nil) = state, let last = lastCompassState?.cameraBearing {
        state = .result(compassState, cameraBearing: last)
      }
      guard state != lastCompassState else { return }
      lastCompassState = state
      continuation.yield(.compass(state))
    }

    /// The frame check and the recorded reading (compass §3.3 step 9, §3.4).
    private func finishCompass(finalYaws: [String: Double]) -> (CompassResult, CompassDiagnostics) {
      stopCompass()
      let check = FrameCheck.frameYaw(live: liveSurfaceYaws, final: finalYaws)
      if check.consensus, abs(check.frameYaw) > FrameCheck.logThreshold {
        Self.log.notice(
          "compass.frame_yaw \(check.frameYaw, format: .fixed(precision: 2)) deg, \(check.matches) surfaces")
      }
      var diagnostics = headingWindow.diagnostics
      diagnostics.frameYaw = check.frameYaw
      diagnostics.frameMatches = check.matches
      diagnostics.frameConsensus = check.consensus
      let result = headingWindow.result(frameYaw: check.frameYaw)
      Self.log.info(
        "compass: \(String(describing: result), privacy: .public); pairs \(diagnostics.pairs), windows \(diagnostics.windowsAccepted) accepted, \(diagnostics.windowsRejected) rejected")
      return (result, diagnostics)
    }

    /// Plan-frame yaw of every surface and object of a room or structure (compass §3.4).
    nonisolated static func surfaceYaws(of room: CapturedRoom) -> [String: Double] {
      yaws(
        surfaces: room.walls + room.doors + room.windows + room.openings,
        objects: room.objects)
    }

    nonisolated static func surfaceYaws(of structure: CapturedStructure) -> [String: Double] {
      yaws(
        surfaces: structure.walls + structure.doors + structure.windows + structure.openings,
        objects: structure.objects)
    }

    private nonisolated static func yaws(
      surfaces: [CapturedRoom.Surface], objects: [CapturedRoom.Object]
    ) -> [String: Double] {
      var yaws: [String: Double] = [:]
      for surface in surfaces {
        let x = surface.transform.columns.0
        yaws[surface.identifier.uuidString] = FrameCheck.yaw(columnX: Double(x.x), z: Double(x.z))
      }
      for object in objects {
        let x = object.transform.columns.0
        yaws[object.identifier.uuidString] = FrameCheck.yaw(columnX: Double(x.x), z: Double(x.z))
      }
      return yaws
    }

    /// The upper-left 3 × 3 of a transform: R_W←K for the camera.
    nonisolated static func rotation(_ m: simd_float4x4) -> CompassMath.Matrix3 {
      func vector(_ c: SIMD4<Float>) -> Vec3 {
        Vec3(x: Double(c.x), y: Double(c.y), z: Double(c.z))
      }
      return CompassMath.Matrix3(
        columns: vector(m.columns.0), vector(m.columns.1), vector(m.columns.2))
    }

    nonisolated static func quality(_ state: ARCamera.TrackingState) -> TrackingQuality {
      switch state {
      case .normal: return .normal
      case .notAvailable: return .notAvailable
      case .limited(.relocalizing): return .relocalizing
      case .limited: return .limited
      }
    }

    private func sample(_ frame: ARFrame) {
      let base = baseFrameTimestamp ?? frame.timestamp
      baseFrameTimestamp = base
      poseFrames.append(
        CameraPose(timestamp: frame.timestamp - base, transform: Self.matrix(frame.camera.transform)))
      if intrinsics == nil {
        let k = frame.camera.intrinsics
        intrinsics = CameraIntrinsics(
          fx: Double(k[0][0]), fy: Double(k[1][1]), cx: Double(k[2][0]), cy: Double(k[2][1]),
          imageWidth: Int(frame.camera.imageResolution.width),
          imageHeight: Int(frame.camera.imageResolution.height))
      }
      for anchor in frame.anchors {
        if let mesh = anchor as? ARMeshAnchor {
          meshAnchors[mesh.identifier] = mesh
        }
      }
      sampleDepth(frame)
    }

    /// Unprojects a grid of depth pixels into the capture frame (+Y up, metres). ARKit's camera
    /// looks down -Z with +Y up, and image rows run downwards, so y and z change sign.
    private func sampleDepth(_ frame: ARFrame) {
      guard depthSamples.count < Self.maxDepthSamples, let depth = frame.sceneDepth,
        let confidenceMap = depth.confidenceMap, let minimum = configuration?.minimumDepthConfidence
      else { return }
      let depthMap = depth.depthMap
      let image = frame.capturedImage
      CVPixelBufferLockBaseAddress(depthMap, .readOnly)
      CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
      CVPixelBufferLockBaseAddress(image, .readOnly)
      defer {
        CVPixelBufferUnlockBaseAddress(image, .readOnly)
        CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
      }
      guard let depthBase = CVPixelBufferGetBaseAddress(depthMap),
        let confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap)
      else { return }
      let width = CVPixelBufferGetWidth(depthMap)
      let height = CVPixelBufferGetHeight(depthMap)
      let depthRowBytes = CVPixelBufferGetBytesPerRow(depthMap)
      let confidenceRowBytes = CVPixelBufferGetBytesPerRow(confidenceMap)
      let imageWidth = CVPixelBufferGetWidthOfPlane(image, 0)
      let imageHeight = CVPixelBufferGetHeightOfPlane(image, 0)
      let scale = Float(imageWidth) / Float(width)
      let k = frame.camera.intrinsics
      let fx = k[0][0]
      let fy = k[1][1]
      let cx = k[2][0]
      let cy = k[2][1]
      let transform = frame.camera.transform

      for row in stride(from: 0, to: height, by: Self.depthStride) {
        let depthRow = depthBase.advanced(by: row * depthRowBytes).assumingMemoryBound(to: Float32.self)
        let confidenceRow = confidenceBase.advanced(by: row * confidenceRowBytes).assumingMemoryBound(
          to: UInt8.self)
        for column in stride(from: 0, to: width, by: Self.depthStride) {
          let distance = depthRow[column]
          let confidence = confidenceRow[column]
          guard distance.isFinite, distance > 0, confidence >= minimum else { continue }
          let px = (Float(column) + 0.5) * scale
          let py = (Float(row) + 0.5) * scale
          let local = SIMD4<Float>(
            (px - cx) * distance / fx, -(py - cy) * distance / fy, -distance, 1)
          let world = transform * local
          let color = Self.rgb(
            of: image, x: min(imageWidth - 1, Int(px)), y: min(imageHeight - 1, Int(py)))
          depthSamples.append(
            DepthSample(
              x: world.x, y: world.y, z: world.z, red: color.r, green: color.g, blue: color.b,
              confidence: confidence))
        }
      }
    }

    /// RGB of a pixel of `ARFrame.capturedImage` (bi-planar YCbCr 4:2:0, full range, BT.601).
    /// The buffer must be locked by the caller.
    private nonisolated static func rgb(of image: CVPixelBuffer, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
      guard CVPixelBufferGetPlaneCount(image) >= 2,
        let luma = CVPixelBufferGetBaseAddressOfPlane(image, 0),
        let chroma = CVPixelBufferGetBaseAddressOfPlane(image, 1)
      else { return (0, 0, 0) }
      let lumaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
      let chromaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(image, 1)
      let yValue = Float(luma.load(fromByteOffset: y * lumaRowBytes + x, as: UInt8.self))
      let chromaOffset = (y / 2) * chromaRowBytes + (x / 2) * 2
      let cb = Float(chroma.load(fromByteOffset: chromaOffset, as: UInt8.self)) - 128
      let cr = Float(chroma.load(fromByteOffset: chromaOffset + 1, as: UInt8.self)) - 128
      func clamp(_ value: Float) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }
      return (
        clamp(yValue + 1.402 * cr), clamp(yValue - 0.344136 * cb - 0.714136 * cr),
        clamp(yValue + 1.772 * cb)
      )
    }

    // MARK: Mesh

    /// ARMeshAnchor geometry as raw floats and indexes, in the anchor's local frame.
    nonisolated static func rawMesh(_ anchor: ARMeshAnchor) -> RawMeshAnchor? {
      let geometry = anchor.geometry
      let vertexSource = geometry.vertices
      let faces = geometry.faces
      guard faces.indexCountPerPrimitive == 3, faces.bytesPerIndex == 4 || faces.bytesPerIndex == 2 else {
        return nil
      }
      var vertices: [Float] = []
      vertices.reserveCapacity(vertexSource.count * 3)
      let vertexBase = vertexSource.buffer.contents()
      for index in 0..<vertexSource.count {
        let pointer = vertexBase.advanced(by: vertexSource.offset + vertexSource.stride * index)
        vertices.append(pointer.loadUnaligned(as: Float.self))
        vertices.append(pointer.loadUnaligned(fromByteOffset: 4, as: Float.self))
        vertices.append(pointer.loadUnaligned(fromByteOffset: 8, as: Float.self))
      }
      var triangles: [UInt32] = []
      triangles.reserveCapacity(faces.count * 3)
      let faceBase = faces.buffer.contents()
      for index in 0..<(faces.count * 3) {
        let pointer = faceBase.advanced(by: index * faces.bytesPerIndex)
        triangles.append(
          faces.bytesPerIndex == 4
            ? pointer.loadUnaligned(as: UInt32.self) : UInt32(pointer.loadUnaligned(as: UInt16.self)))
      }
      return RawMeshAnchor(
        identifier: anchor.identifier.uuidString.lowercased(), transform: matrix(anchor.transform),
        vertices: vertices, triangles: triangles)
    }

    // MARK: Helpers

    nonisolated static func matrix(_ m: simd_float4x4) -> Matrix4 {
      Matrix4(columns: [m.columns.0, m.columns.1, m.columns.2, m.columns.3].map { column in
        [Double(column.x), Double(column.y), Double(column.z), Double(column.w)]
      })!
    }

    private nonisolated static func sum(_ a: ScanCounts, _ b: ScanCounts) -> ScanCounts {
      ScanCounts(
        walls: a.walls + b.walls, doors: a.doors + b.doors, windows: a.windows + b.windows,
        rooms: a.rooms + b.rooms, openings: a.openings + b.openings, objects: a.objects + b.objects)
    }

    private func emitProgress() {
      continuation.yield(
        .progress(
          ScanProgress(
            counts: Self.sum(completedCounts, currentCounts), elapsed: elapsed,
            depthSampleCount: depthSamples.count, meshAnchorCount: meshAnchors.count)))
    }

    /// The app's error for a RoomPlan error, with plain wording for the cases an operator can act
    /// on.
    nonisolated static func sessionError(_ error: any Error) -> CaptureSessionError {
      switch error as? RoomCaptureSession.CaptureError {
      case .deviceTooHot?: return .tooHot
      case .worldTrackingFailure?: return .trackingLost
      case .exceedSceneSizeLimit?: return .areaTooLarge
      default: return .scanFailed(error.localizedDescription)
      }
    }

    private func setState(_ new: CaptureSessionState) {
      state = new
      continuation.yield(.stateChanged(new))
    }

    private func failed(_ error: CaptureSessionError) {
      stopTimer()
      stopCompass()
      roomSession?.stop(pauseARSession: true)
      roomSession = nil
      arSession.pause()
      setState(.failed(error.description))
      continuation.finish()
    }
  }
#endif
