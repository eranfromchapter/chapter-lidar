import CaptureContract
import Foundation

/// The scan-start reading of one floor (compass §3.3 steps 2–9), fed by `LiveCaptureSession`
/// with every ARKit frame it could pair with Core Motion. Pure, so it is tested on Linux.
///
/// - A window is 8 consecutive valid pairs within 3.0 s; an invalid pair, a gap over 1 s or a
///   change of north (the authorisation changed) starts a new one.
/// - Its value: H_W = circular mean of the pairs' bearings; spread = the largest distance from
///   it; accuracy = ⌈max `headingAccuracy`⌉ (at least 1); north of the reference frame; time of
///   the last pair. The window is rejected when spread > max(5°, accuracy): the compass moved
///   while the phone did not.
/// - The best accepted window wins: verified > approximate > not verified, then the lower
///   accuracy, then the later one. A verified window ends the attempt.
/// - Attempts run through the first 30 s of running time, then go on silently until Finish
///   floor (the world frame stays the same for the whole floor).
public struct HeadingWindow: Sendable {
  public static let pairsPerWindow = 8
  public static let windowSpan: TimeInterval = 3.0
  public static let maxGap: TimeInterval = 1.0
  /// Running time of the start period (paused time not counted).
  public static let startPeriod: TimeInterval = 30
  /// The smallest spread limit of the consistency test, degrees.
  public static let minimumSpreadLimit = 5.0
  /// Running time over which gravity failures are judged (compass §2.2).
  public static let conventionCheckPeriod: TimeInterval = 10

  /// One accepted window.
  public struct Window: Hashable, Sendable {
    /// H_W, degrees in `0 ..< 360`.
    public var worldHeading: Double
    public var accuracy: Int
    public var source: HeadingSource
    public var recordedAt: UTCTimestamp
    public var spread: Double
    /// The state of the reading under the shared thresholds.
    public var state: CompassState
  }

  /// The best accepted window so far.
  public private(set) var best: Window?
  public private(set) var diagnostics = CompassDiagnostics()
  /// True once a verified window was accepted: no more pairs are taken.
  public var isDone: Bool { best?.state.rank == 2 }
  /// Set when the phone has no usable compass (compass §1.5 `unavailable`).
  public private(set) var isUnavailable = false

  private var run: [CompassPair] = []
  private var runningTime: TimeInterval = 0
  private var sawValidHeading = false
  private var sawCalibratedField = false
  private var conventionPairs = 0
  private var conventionFailures = 0
  private var conventionJudged = false

  public init() {}

  /// The phone has no compass or no north-referenced device motion: the result is
  /// `unavailable`.
  public mutating func markUnavailable() {
    isUnavailable = true
  }

  /// A frame for which no motion sample was found within 25 ms.
  public mutating func addUnpaired() {
    diagnostics.unpaired += 1
  }

  /// Takes one paired frame. Returns true when the best window changed.
  @discardableResult
  public mutating func add(_ pair: CompassPair) -> Bool {
    diagnostics.pairs += 1
    advance(runningTime: pair.runningTime)
    if pair.headingAccuracy != nil { sawValidHeading = true }
    if pair.motion.magneticFieldCalibrated { sawCalibratedField = true }
    let reason = pair.dropReason
    judgeConvention(pair, reason: reason)
    guard !isDone else { return false }
    if let reason {
      diagnostics.dropped[reason, default: 0] += 1
      run.removeAll()
      return false
    }
    if let last = run.last,
      pair.timestamp - last.timestamp > Self.maxGap || pair.motion.source != last.motion.source
    {
      run.removeAll()
    }
    run.append(pair)
    while let first = run.first, pair.timestamp - first.timestamp > Self.windowSpan {
      run.removeFirst()
    }
    guard run.count >= Self.pairsPerWindow else { return false }
    let window = run
    run.removeAll()
    return consider(window)
  }

  /// Moves the running time on (each tick, paused time not counted). Returns true once, when
  /// the start period ends.
  @discardableResult
  public mutating func advance(runningTime time: TimeInterval) -> Bool {
    let wasInStartPeriod = runningTime < Self.startPeriod
    runningTime = max(runningTime, time)
    return wasInStartPeriod && runningTime >= Self.startPeriod
  }

  /// True during the first 30 s of running time.
  public var isInStartPeriod: Bool { runningTime < Self.startPeriod }

  /// The chip's state (compass §5.2) with the camera of `worldFromCamera`, if any.
  public func liveState(worldFromCamera: CompassMath.Matrix3?) -> CompassLiveState {
    if let best, best.state.isUsable {
      let bearing = worldFromCamera.flatMap {
        CompassMath.cameraBearing(worldHeading: best.worldHeading, worldFromCamera: $0)
      }
      return .result(best.state, cameraBearing: bearing)
    }
    return isInStartPeriod ? .reading : .notVerified
  }

  /// What Finish floor records: the best window turned into the capture frame by `frameYaw`
  /// (compass §3.4), or no reading with the issue of §1.5 (unavailable > not calibrated >
  /// rejected). There is always an issue: a capture record 1.1.0 capture with neither a reading
  /// nor an issue is one scanned before the app read the compass (the station does not grade it).
  /// No compass sample was ever paired with a frame (no compass service, or Core Motion delivered
  /// nothing): unavailable. Samples came but never made an accepted window (too few in a row,
  /// tracking not normal, turning, a gravity or heading-age failure): rejected, the readings could
  /// not be matched to the scan.
  public func result(frameYaw: Double = CompassMath.captureFrameYaw) -> CompassResult {
    if let best {
      return .reading(
        heading: CompassMath.storedHeading(
          CompassMath.captureHeading(worldHeading: best.worldHeading, frameYaw: frameYaw)),
        accuracy: best.accuracy, source: best.source, recordedAt: best.recordedAt)
    }
    if isUnavailable || diagnostics.pairs == 0 { return .none(issue: .unavailable) }
    if !sawValidHeading || !sawCalibratedField { return .none(issue: .notCalibrated) }
    return .none(issue: .rejected)
  }

  // MARK: Private

  /// Steps 4–6: the window's value, the consistency test and the best-of rule.
  private mutating func consider(_ window: [CompassPair]) -> Bool {
    let bearings = window.map(\.worldHeading)
    guard let last = window.last, let mean = CompassMath.circularMean(bearings) else {
      diagnostics.windowsRejected += 1
      return false
    }
    let spread = CompassMath.spread(bearings, around: mean)
    let accuracy = CompassMath.storedAccuracy(window.compactMap(\.headingAccuracy).max() ?? 0)
    guard spread <= max(Self.minimumSpreadLimit, Double(accuracy)) else {
      diagnostics.windowsRejected += 1
      return false
    }
    diagnostics.windowsAccepted += 1
    let source = last.motion.source
    let candidate = Window(
      worldHeading: mean, accuracy: accuracy, source: source,
      recordedAt: UTCTimestamp(last.date), spread: spread,
      state: CompassState(reading: mean, accuracy: accuracy, source: source, at: last.date))
    guard let best else {
      self.best = candidate
      return true
    }
    let better =
      candidate.state.rank > best.state.rank
      || (candidate.state.rank == best.state.rank && candidate.accuracy <= best.accuracy)
    if better { self.best = candidate }
    return better
  }

  /// Compass §2.2: when more than half of the pairs of the first 10 s fail a gravity check, the
  /// matrix conventions are wrong on this phone (`diagnostics.conventionMismatch`).
  private mutating func judgeConvention(_ pair: CompassPair, reason: CompassDropReason?) {
    guard !conventionJudged else { return }
    if pair.runningTime > Self.conventionCheckPeriod {
      conventionJudged = true
      diagnostics.conventionMismatch =
        conventionPairs > 0 && Double(conventionFailures) > Double(conventionPairs) / 2
      return
    }
    // Only pairs the earlier gates let through say anything about the matrices.
    guard reason != .trackingNotNormal, reason != .turning else { return }
    conventionPairs += 1
    if reason == .gravity { conventionFailures += 1 }
  }
}
