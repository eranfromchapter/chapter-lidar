#if canImport(RoomPlan) && canImport(ARKit) && os(iOS)
  import ARKit
  import CaptureContract
  import CaptureCore
  import CaptureModelMapping
  import Foundation
  import Metal
  import RoomPlan
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

    public override init() {
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
      startSegment()
      startTimer()
      setState(.running)
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
        if segments.count == 1 {
          json = try RoomPlanAdapter.encode(segments[0])
        } else {
          let structure = try await StructureBuilder(options: [.beautifyObjects]).capturedStructure(
            from: segments)
          json = try RoomPlanAdapter.encode(structure)
        }
        let originals = RawOriginals(
          roomPlanJSON: json, depthSamples: depthSamples,
          cameraPoses: CameraPoseLog(intrinsics: intrinsics, frames: poseFrames),
          meshAnchors: meshAnchors.values.sorted { $0.identifier.uuidString < $1.identifier.uuidString }
            .compactMap(Self.rawMesh))
        setState(.finished)
        continuation.finish()
        return CaptureSessionResult(originals: originals, startedAt: startedAt, finishedAt: Date())
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
      Task { @MainActor in
        self.currentCounts = counts
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
      if let frame = arSession.currentFrame, frame.timestamp != lastFrameTimestamp {
        lastFrameTimestamp = frame.timestamp
        sample(frame)
      }
      emitProgress()
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
      roomSession?.stop(pauseARSession: true)
      roomSession = nil
      arSession.pause()
      setState(.failed(error.description))
      continuation.finish()
    }
  }
#endif
