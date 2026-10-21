import CaptureContract
import Foundation

/// The pre-check's arithmetic (compass §3.2), fed with `CLHeading` updates by `CompassService`:
/// a 2.0 s window opens at the first valid update; the result is the last valid update's
/// heading (`trueHeading` when it is valid, else `magneticHeading`, and north follows) with the
/// largest valid accuracy of the window, rounded up, read at the window's end. No valid update
/// within 5 s of the start gives `notCalibrated`.
public struct PrecheckReading: Sendable {
  public static let window: TimeInterval = 2
  public static let giveUp: TimeInterval = 5

  public let startedAt: Date
  private var windowStart: Date?
  private var last: CompassHeadingSample?
  private var maxAccuracy: Double = 0

  public init(startedAt: Date) {
    self.startedAt = startedAt
  }

  /// Takes one update; returns the result when it closes the window.
  public mutating func add(_ sample: CompassHeadingSample) -> CompassPrecheckState? {
    if let windowStart, sample.date >= windowStart.addingTimeInterval(Self.window) {
      return poll(now: sample.date)
    }
    guard sample.isValid else { return poll(now: sample.date) }
    if windowStart == nil { windowStart = sample.date }
    last = sample
    maxAccuracy = max(maxAccuracy, sample.accuracy)
    return nil
  }

  /// The result once the window is over or the 5 s are up, else nil.
  public func poll(now: Date) -> CompassPrecheckState? {
    guard let windowStart, let last else {
      return now.timeIntervalSince(startedAt) >= Self.giveUp ? .notCalibrated : nil
    }
    let end = windowStart.addingTimeInterval(Self.window)
    guard now >= end else { return nil }
    let isTrue = last.trueHeading >= 0
    return .result(
      heading: CompassMath.normalized(isTrue ? last.trueHeading : last.magneticHeading),
      accuracy: CompassMath.storedAccuracy(maxAccuracy),
      source: isTrue ? .trueNorth : .magnetic, readAt: end)
  }
}
