import CaptureContract
import Foundation

/// One Core Motion device-motion sample, as `CompassService` keeps them (the last 1.0 s).
public struct CompassMotionSample: Hashable, Sendable {
  /// Seconds since boot (`CMDeviceMotion.timestamp`, the clock of `ARFrame.timestamp`).
  public var timestamp: TimeInterval
  /// `CMDeviceMotion.attitude.rotationMatrix` (reference → device).
  public var attitude: CompassMath.Matrix3
  /// `CMDeviceMotion.gravity`, toward the Earth, in the device frame.
  public var gravity: Vec3
  /// Magnitude of `CMDeviceMotion.rotationRate`, rad/s.
  public var rotationRate: Double
  /// False while `magneticField.accuracy` is `.uncalibrated`.
  public var magneticFieldCalibrated: Bool
  /// North of the reference frame in use (`.xTrueNorthZVertical` or `.xMagneticNorthZVertical`).
  public var source: HeadingSource

  public init(
    timestamp: TimeInterval, attitude: CompassMath.Matrix3, gravity: Vec3, rotationRate: Double,
    magneticFieldCalibrated: Bool, source: HeadingSource
  ) {
    self.timestamp = timestamp
    self.attitude = attitude
    self.gravity = gravity
    self.rotationRate = rotationRate
    self.magneticFieldCalibrated = magneticFieldCalibrated
    self.source = source
  }

  /// The sample nearest to `timestamp` when it is at most `tolerance` away (compass §3.3 step 1:
  /// 25 ms); both clocks are seconds since boot.
  public static func nearest(
    in samples: [CompassMotionSample], to timestamp: TimeInterval,
    tolerance: TimeInterval = CompassPair.pairingTolerance
  ) -> CompassMotionSample? {
    guard let best = samples.min(by: { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) })
    else { return nil }
    return abs(best.timestamp - timestamp) <= tolerance ? best : nil
  }
}

/// One `CLHeading` update: only its accuracy is used during the scan; the pre-check shows its
/// heading. `trueHeading` and `accuracy` are negative when invalid, as Core Location reports.
public struct CompassHeadingSample: Hashable, Sendable {
  public var date: Date
  public var trueHeading: Double
  public var magneticHeading: Double
  public var accuracy: Double

  public init(date: Date, trueHeading: Double, magneticHeading: Double, accuracy: Double) {
    self.date = date
    self.trueHeading = trueHeading
    self.magneticHeading = magneticHeading
    self.accuracy = accuracy
  }

  public var isValid: Bool { accuracy >= 0 }
}

/// Why a paired sample was not used (counted for the debug log and device test D1).
public enum CompassDropReason: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
  /// ARKit tracking was not normal.
  case trackingNotNormal
  /// The phone turned faster than 0.35 rad/s.
  case turning
  /// A gravity check failed (a transposed matrix or a wrong camera mapping, compass §2.2).
  case gravity
  /// No `CLHeading` younger than 2 s with a valid accuracy.
  case noHeading
  /// Core Motion's magnetic field was uncalibrated.
  case uncalibrated
}

/// An ARKit frame paired with the Core Motion sample nearest to it (compass §3.3 steps 1–2).
public struct CompassPair: Hashable, Sendable {
  /// Pairing window between `ARFrame.timestamp` and `CMDeviceMotion.timestamp`.
  public static let pairingTolerance: TimeInterval = 0.025
  /// Fastest turn of the phone for a usable pair, rad/s (20°/s).
  public static let maxRotationRate = 0.35
  /// Oldest `CLHeading` whose accuracy still counts.
  public static let maxHeadingAge: TimeInterval = 2

  /// `ARFrame.timestamp`, seconds since boot.
  public var timestamp: TimeInterval
  /// Running time of the scan at the frame; paused time is not counted.
  public var runningTime: TimeInterval
  /// Wall clock at the frame (`headingRecordedAt`).
  public var date: Date
  public var trackingNormal: Bool
  /// Upper-left 3 × 3 of `ARFrame.camera.transform` (R_W←K).
  public var worldFromCamera: CompassMath.Matrix3
  public var motion: CompassMotionSample
  /// The latest `CLHeading`, if any.
  public var heading: CompassHeadingSample?

  public init(
    timestamp: TimeInterval, runningTime: TimeInterval, date: Date, trackingNormal: Bool,
    worldFromCamera: CompassMath.Matrix3, motion: CompassMotionSample,
    heading: CompassHeadingSample?
  ) {
    self.timestamp = timestamp
    self.runningTime = runningTime
    self.date = date
    self.trackingNormal = trackingNormal
    self.worldFromCamera = worldFromCamera
    self.motion = motion
    self.heading = heading
  }

  /// The accuracy of the latest heading when it is valid and younger than 2 s.
  public var headingAccuracy: Double? {
    guard let heading, heading.isValid, abs(date.timeIntervalSince(heading.date)) < Self.maxHeadingAge
    else { return nil }
    return heading.accuracy
  }

  /// Why the pair cannot be used, or nil (compass §3.3 step 2).
  public var dropReason: CompassDropReason? {
    if !trackingNormal { return .trackingNotNormal }
    if motion.rotationRate >= Self.maxRotationRate { return .turning }
    if !CompassMath.passesGravityChecks(
      attitude: motion.attitude, worldFromCamera: worldFromCamera, gravity: motion.gravity)
    {
      return .gravity
    }
    if headingAccuracy == nil { return .noHeading }
    if !motion.magneticFieldCalibrated { return .uncalibrated }
    return nil
  }

  /// H_W: the bearing of the ARKit world's −Z axis from this pair (compass §2.3).
  public var worldHeading: Double {
    CompassMath.worldHeading(
      referenceFromWorld: CompassMath.referenceFromWorld(
        attitude: motion.attitude, worldFromCamera: worldFromCamera))
  }
}

/// What the scan-start reading did, for the debug log and the device tests (D1). Never holds a
/// location.
public struct CompassDiagnostics: Hashable, Sendable, Codable {
  /// Frames paired with a motion sample.
  public var pairs = 0
  /// Frames without a motion sample within 25 ms.
  public var unpaired = 0
  /// Paired frames dropped, per reason.
  public var dropped: [CompassDropReason: Int] = [:]
  public var windowsAccepted = 0
  public var windowsRejected = 0
  /// More than half of the pairs of the first 10 s failed a gravity check (compass §2.2:
  /// `compass.convention_mismatch`).
  public var conventionMismatch = false
  /// φ applied at Finish floor (compass §3.4), the surfaces matched and whether they agreed.
  public var frameYaw: Double?
  public var frameMatches = 0
  public var frameConsensus = false

  public init() {}
}
