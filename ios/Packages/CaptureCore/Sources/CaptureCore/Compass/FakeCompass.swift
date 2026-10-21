import CaptureContract
import Foundation

/// The compass of a scan played back by `ReplaySession`: what the scan finds and when.
public struct ReplayCompass: Hashable, Sendable {
  /// A reading of the capture's −Z axis.
  public struct Reading: Hashable, Sendable {
    public var heading: Double
    public var accuracy: Int
    public var source: HeadingSource

    public init(heading: Double, accuracy: Int, source: HeadingSource) {
      self.heading = heading
      self.accuracy = accuracy
      self.source = source
    }
  }

  /// The reading, or nil for none.
  public var reading: Reading?
  /// Why there is none (nil: no issue known).
  public var issue: HeadingIssue?
  /// Seconds after the start of the scan at which the reading is taken.
  public var recordedAfter: TimeInterval
  /// The bearing the camera looks at, for the chip's arrow.
  public var cameraBearing: Double?

  public init(
    reading: Reading?, issue: HeadingIssue? = nil, recordedAfter: TimeInterval = 2,
    cameraBearing: Double? = nil
  ) {
    self.reading = reading
    self.issue = issue
    self.recordedAfter = recordedAfter
    self.cameraBearing = cameraBearing
  }

  /// The live state once the reading is found.
  public func liveState(at date: Date) -> CompassLiveState {
    guard let reading else { return .notVerified }
    let state = CompassState(
      reading: reading.heading, accuracy: reading.accuracy, source: reading.source, at: date)
    return state.isUsable ? .result(state, cameraBearing: cameraBearing) : .notVerified
  }

  /// What Finish floor records for a scan that started at `startedAt`.
  public func result(startedAt: Date) -> CompassResult {
    guard let reading else { return .none(issue: issue) }
    return .reading(
      heading: reading.heading, accuracy: reading.accuracy, source: reading.source,
      recordedAt: UTCTimestamp(startedAt.addingTimeInterval(recordedAfter)))
  }
}

/// A scripted compass for unit tests, snapshots and the UI-test launch argument
/// `-ChapterUITestCompass verified|approximate|none` (critique R-24). It scripts the pre-check,
/// the scan reading (`replayCompass`, for `ReplaySession`) and the photo camera bearing:
///
/// | Script | Pre-check | Scan | Photo camera |
/// |---|---|---|---|
/// | `verified` | 212.4° ±8 true | 212.4° ±8 true | 85° ±8 true ("E") |
/// | `approximate` | 212.4° ±12 magnetic | 212.4° ±12 magnetic | 85° ±12 magnetic |
/// | `none` | not calibrated | no reading | none |
@MainActor
public final class FakeCompass: CompassProviding {
  public enum Script: String, CaseIterable, Sendable {
    case verified
    case approximate
    case none
  }

  /// The heading of every scripted reading.
  public nonisolated static let heading = 212.4
  public nonisolated static let verifiedAccuracy = 8
  public nonisolated static let approximateAccuracy = 12
  /// The photo camera's scripted bearing (phone-field §15.3: "E").
  public nonisolated static let cameraBearing = 85.0

  public let script: Script
  public var isAvailable: Bool
  public var authorization: CompassAuthorization
  /// How long a pre-check takes (none: at once).
  public var precheckDuration: Duration?
  public private(set) var precheckCount = 0
  public private(set) var authorizationRequests = 0
  public private(set) var settingsOpened = 0
  public private(set) var isCameraHeadingRunning = false
  private let clock: @Sendable () -> Date

  public init(
    _ script: Script, isAvailable: Bool = true, authorization: CompassAuthorization = .authorized,
    precheckDuration: Duration? = nil, clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.script = script
    self.isAvailable = isAvailable
    self.authorization = authorization
    self.precheckDuration = precheckDuration
    self.clock = clock
  }

  /// The script named by a launch argument value; nil for an unknown one.
  public convenience init?(launchArgument value: String, clock: @escaping @Sendable () -> Date = { Date() }) {
    guard let script = Script(rawValue: value) else { return nil }
    self.init(script, clock: clock)
  }

  public func requestAuthorization() {
    authorizationRequests += 1
    if authorization == .notDetermined { authorization = .authorized }
  }

  public func precheck() async -> CompassPrecheckState {
    precheckCount += 1
    if let precheckDuration {
      try? await Task.sleep(for: precheckDuration)
      if Task.isCancelled { return .notCalibrated }
    }
    guard isAvailable else { return .unavailable }
    switch script {
    case .verified:
      return .result(
        heading: Self.heading, accuracy: Self.verifiedAccuracy, source: .trueNorth, readAt: clock())
    case .approximate:
      return .result(
        heading: Self.heading, accuracy: Self.approximateAccuracy, source: .magnetic,
        readAt: clock())
    case .none:
      return .notCalibrated
    }
  }

  public func openSettings() {
    settingsOpened += 1
  }

  public func startCameraHeading() {
    isCameraHeadingRunning = true
  }

  public func stopCameraHeading() {
    isCameraHeadingRunning = false
  }

  public func cameraSample() -> CompassCameraSample? {
    switch script {
    case .verified:
      return CompassCameraSample(
        azimuth: Self.cameraBearing, horizontalComponent: 1,
        accuracy: Double(Self.verifiedAccuracy), source: .trueNorth, sampledAt: clock())
    case .approximate:
      return CompassCameraSample(
        azimuth: Self.cameraBearing, horizontalComponent: 1,
        accuracy: Double(Self.approximateAccuracy), source: .magnetic, sampledAt: clock())
    case .none:
      return nil
    }
  }

  /// The scan's compass for `ReplaySession(source:compass:)`.
  public nonisolated var replayCompass: ReplayCompass {
    switch script {
    case .verified:
      return ReplayCompass(
        reading: .init(heading: Self.heading, accuracy: Self.verifiedAccuracy, source: .trueNorth),
        cameraBearing: Self.heading)
    case .approximate:
      return ReplayCompass(
        reading: .init(
          heading: Self.heading, accuracy: Self.approximateAccuracy, source: .magnetic),
        cameraBearing: Self.heading)
    case .none:
      return ReplayCompass(reading: nil)
    }
  }
}
