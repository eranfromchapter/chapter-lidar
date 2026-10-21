import Foundation

/// Whether ARKit is tracking the room, as the live scan shows it (phone-capture §3.4.1).
public enum TrackingStatus: Sendable, Equatable {
  case normal
  /// Tracking has been lost since `since` (when it stopped being normal). RoomPlan keeps running;
  /// this is not a pause by the operator.
  case lost(since: Date)

  public var isLost: Bool {
    if case .lost = self { return true }
    return false
  }
}

/// ARKit's tracking state of one frame, without ARKit (`ARCamera.TrackingState`).
public enum TrackingQuality: Sendable, Equatable {
  case normal
  case notAvailable
  /// `.limited(.relocalizing)`.
  case relocalizing
  /// Any other `.limited` reason (too fast, too dark, too little texture, initializing).
  case limited
}

/// Turns the tracking state of each 4 Hz tick into `TrackingStatus` (phone-capture §5.5): lost
/// after 1.0 s of `notAvailable` or relocalizing, or 3.0 s of any limited state; normal again
/// after 0.5 s of normal tracking. Sampling stops at once whenever a frame is not normal
/// (`isSampling`), so "Recording paused" is true.
public struct TrackingMonitor: Sendable {
  public static let lostAfterSevere: TimeInterval = 1.0
  public static let lostAfterLimited: TimeInterval = 3.0
  public static let normalAfter: TimeInterval = 0.5

  public private(set) var status: TrackingStatus = .normal
  /// False while the latest frame is not tracked normally: no depth, pose or mesh is taken.
  public private(set) var isSampling = true

  private var notNormalSince: (time: TimeInterval, date: Date)?
  private var severeSince: TimeInterval?
  private var normalSince: TimeInterval?

  public init() {}

  /// Takes the tracking state of a frame at `time` (seconds, any monotonic clock) and wall-clock
  /// `date`. Returns the new status when it changed.
  public mutating func update(_ quality: TrackingQuality, at time: TimeInterval, date: Date)
    -> TrackingStatus?
  {
    let previous = status
    if quality == .normal {
      isSampling = true
      severeSince = nil
      if status.isLost {
        if normalSince == nil { normalSince = time }
        if let normalSince, time - normalSince >= Self.normalAfter {
          status = .normal
          notNormalSince = nil
          self.normalSince = nil
        }
      } else {
        notNormalSince = nil
      }
    } else {
      isSampling = false
      normalSince = nil
      if notNormalSince == nil { notNormalSince = (time, date) }
      let isSevere = quality == .notAvailable || quality == .relocalizing
      if isSevere {
        if severeSince == nil { severeSince = time }
      } else {
        severeSince = nil
      }
      if !status.isLost, let onset = notNormalSince {
        let severeLong = severeSince.map { time - $0 >= Self.lostAfterSevere } ?? false
        if severeLong || time - onset.time >= Self.lostAfterLimited {
          status = .lost(since: onset.date)
        }
      }
    }
    return status == previous ? nil : status
  }
}
