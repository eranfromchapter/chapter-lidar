import CaptureModelMapping
import Foundation

/// A recording to play back: the raw originals of a scan.
public struct ReplaySource: Sendable, Equatable {
  public var originals: RawOriginals

  public init(originals: RawOriginals) {
    self.originals = originals
  }

  /// Loads a folder that holds `roomplan.json` (generated fixture package) or
  /// `raw-roomplan.json` (debug export), plus `depth-samples.bin` and optionally
  /// `camera-poses.json`.
  public static func load(directory: URL) throws -> ReplaySource {
    ReplaySource(originals: try RawOriginalsWriter.read(from: directory))
  }
}

/// A `CaptureSession` that plays back a recording. Progress counts grow in `steps` equal steps;
/// the last step has the totals of the recording. With `autoPlay` (the default) `start` and
/// `resume` play to the end at once; with `autoPlay: false` a test calls `advance()` for each step.
///
/// Scripts for tests and UI tests:
/// - `compass`: right after `.stateChanged(.running)` the chip reads `.compass(.reading)`; from
///   step 1 it shows the script's reading (or `.notVerified`), and `finish()` returns its result.
///   Without a script the session reads no compass (`.none(issue: nil)`), as before.
/// - `trackingLost`: steps during which tracking is lost (`.tracking(.lost(since:))` on entering
///   the range, `.tracking(.normal)` on leaving it).
public actor ReplaySession: CaptureSession {
  public nonisolated let events: AsyncStream<CaptureSessionEvent>
  private let continuation: AsyncStream<CaptureSessionEvent>.Continuation

  private let source: ReplaySource
  private let document: RoomPlanDocument
  private let steps: Int
  private let autoPlay: Bool
  private let clock: @Sendable () -> Date
  private let compass: ReplayCompass?
  private let trackingLost: ClosedRange<Int>?

  public private(set) var state: CaptureSessionState = .idle
  private var step = 0
  private var startedAt: Date?
  private var compassShown = false
  private var isTrackingLost = false

  /// Throws when the recording's RoomPlan JSON cannot be decoded.
  public init(
    source: ReplaySource, steps: Int = 10, autoPlay: Bool = true,
    clock: @escaping @Sendable () -> Date = { Date() }, compass: ReplayCompass? = nil,
    trackingLost: ClosedRange<Int>? = nil
  ) throws {
    self.source = source
    self.document = try RoomPlanDocument.decode(from: source.originals.roomPlanJSON)
    self.steps = max(1, steps)
    self.autoPlay = autoPlay
    self.clock = clock
    self.compass = compass
    self.trackingLost = trackingLost
    (events, continuation) = AsyncStream.makeStream(of: CaptureSessionEvent.self)
  }

  public func start(_ configuration: CaptureSessionConfiguration) async throws {
    guard state == .idle else {
      throw CaptureSessionError.invalidState("The scan has already started.")
    }
    startedAt = clock()
    step = 0
    setState(.running)
    if compass != nil { continuation.yield(.compass(.reading)) }
    continuation.yield(.instruction(.normal))
    continuation.yield(.progress(progress(forStep: 0)))
    if autoPlay { playToEnd() }
  }

  public func pause() async throws {
    guard state == .running else {
      throw CaptureSessionError.invalidState("Only a running scan can be paused.")
    }
    setState(.paused)
  }

  public func resume() async throws {
    guard state == .paused else {
      throw CaptureSessionError.invalidState("Only a paused scan can be resumed.")
    }
    setState(.running)
    if autoPlay { playToEnd() }
  }

  /// Plays one step. Returns false when the recording is already at its end or the scan is not running.
  @discardableResult
  public func advance() -> Bool {
    guard state == .running, step < steps else { return false }
    step += 1
    if let compass, !compassShown, let startedAt {
      compassShown = true
      let readAt = startedAt.addingTimeInterval(compass.recordedAfter)
      continuation.yield(.compass(compass.liveState(at: readAt)))
    }
    if let trackingLost {
      let lost = trackingLost.contains(step)
      if lost != isTrackingLost {
        isTrackingLost = lost
        continuation.yield(.tracking(lost ? .lost(since: clock()) : .normal))
      }
    }
    continuation.yield(.progress(progress(forStep: step)))
    return true
  }

  public func finish() async throws -> CaptureSessionResult {
    guard state == .running || state == .paused, let startedAt else {
      throw CaptureSessionError.invalidState("There is no scan to finish.")
    }
    setState(.finishing)
    // Finishing plays the rest of the recording, so the result always holds all of it.
    step = steps
    continuation.yield(.progress(progress(forStep: steps)))
    guard !document.rooms.isEmpty, document.rooms.contains(where: { !$0.walls.isEmpty }) else {
      setState(.failed(CaptureSessionError.noRoomsCaptured.description))
      continuation.finish()
      throw CaptureSessionError.noRoomsCaptured
    }
    setState(.finished)
    continuation.finish()
    return CaptureSessionResult(
      originals: source.originals, startedAt: startedAt, finishedAt: clock(),
      compass: compass?.result(startedAt: startedAt) ?? .none(issue: nil))
  }

  public func cancel() async {
    guard state != .finished, state != .idle else { return }
    setState(.idle)
    continuation.finish()
  }

  private func playToEnd() {
    while advance() {}
  }

  private func setState(_ new: CaptureSessionState) {
    state = new
    continuation.yield(.stateChanged(new))
  }

  private func progress(forStep step: Int) -> ScanProgress {
    func part(_ total: Int) -> Int { step >= steps ? total : total * step / steps }
    let totals = ScanCounts(document: document)
    return ScanProgress(
      counts: ScanCounts(
        walls: part(totals.walls), doors: part(totals.doors), windows: part(totals.windows),
        rooms: part(totals.rooms), openings: part(totals.openings), objects: part(totals.objects)),
      elapsed: Double(step),
      depthSampleCount: part(source.originals.depthSamples.count),
      meshAnchorCount: part(source.originals.meshAnchors.count))
  }
}
