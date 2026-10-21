import CaptureContract
import Foundation

/// The last second of Core Motion samples (compass §3.3 step 1). Core Motion delivers on its own
/// queue and the scan pairs on the main actor, so the ring is locked.
public final class CompassMotionRing: @unchecked Sendable {
  /// Seconds of samples kept, back from the newest.
  public let span: TimeInterval
  private let lock = NSLock()
  private var samples: [CompassMotionSample] = []

  public init(span: TimeInterval = 1.0) {
    self.span = span
  }

  /// Adds a sample and drops those older than `span` before it.
  public func append(_ sample: CompassMotionSample) {
    lock.lock()
    defer { lock.unlock() }
    samples.append(sample)
    let oldest = sample.timestamp - span
    if let first = samples.firstIndex(where: { $0.timestamp >= oldest }), first > 0 {
      samples.removeFirst(first)
    }
  }

  /// The sample nearest to `timestamp` within the pairing tolerance.
  public func nearest(to timestamp: TimeInterval, tolerance: TimeInterval = CompassPair.pairingTolerance)
    -> CompassMotionSample?
  {
    lock.lock()
    defer { lock.unlock() }
    return CompassMotionSample.nearest(in: samples, to: timestamp, tolerance: tolerance)
  }

  /// The newest sample.
  public var latest: CompassMotionSample? {
    lock.lock()
    defer { lock.unlock() }
    return samples.last
  }

  public var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return samples.count
  }

  public func removeAll() {
    lock.lock()
    defer { lock.unlock() }
    samples.removeAll()
  }
}

/// One line of device test D0 (compass §13.5): the bearing `CompassMath` gives from Core Motion
/// next to Core Location's heading, and the Core Motion gravity check. Pure, so the arithmetic
/// of the harness is tested on Linux; `CompassDeviceCheck` (CaptureCompass) records the lines.
public struct CompassDeviceCheckLine: Hashable, Sendable, Codable {
  /// How the phone is held: flat (its top edge is horizontal) or upright (the back camera is).
  public enum Posture: String, Hashable, Sendable, Codable {
    case flat
    case upright
    /// Neither axis is level enough to compare.
    case steep
  }

  /// Seconds since the recording started.
  public var time: TimeInterval
  public var posture: Posture
  /// `CompassMath` bearing of the top edge (flat) or of the back camera (upright), degrees.
  public var bearing: Double?
  /// `CLHeading.trueHeading` (negative when invalid) and `magneticHeading`.
  public var trueHeading: Double
  public var magneticHeading: Double
  public var headingAccuracy: Double
  /// North of the Core Motion reference frame.
  public var source: HeadingSource
  /// Signed difference bearing − Core Location heading of the same north, degrees in (−180, 180].
  public var difference: Double?
  /// Angle between gravity through Core Motion and straight down (≤ 3° passes).
  public var gravityError: Double

  public init(
    time: TimeInterval, motion: CompassMotionSample, heading: CompassHeadingSample
  ) {
    let referenceFromDevice = CompassMath.referenceFromDevice(attitude: motion.attitude)
    let top = referenceFromDevice * Vec3(x: 0, y: 1, z: 0)
    let camera = CompassMath.cameraAxisInReference(rotationMatrix: motion.attitude)
    let level = CompassMath.minimumPhotoHorizontal
    let posture: Posture
    let bearing: Double?
    if CompassMath.horizontalComponent(inReference: top) >= 0.9 {
      posture = .flat
      bearing = CompassMath.bearing(inReference: top)
    } else if CompassMath.horizontalComponent(inReference: camera) >= level {
      posture = .upright
      bearing = CompassMath.bearing(inReference: camera)
    } else {
      posture = .steep
      bearing = nil
    }
    let reference = motion.source == .trueNorth ? heading.trueHeading : heading.magneticHeading
    self.time = time
    self.posture = posture
    self.bearing = bearing
    self.trueHeading = heading.trueHeading
    self.magneticHeading = heading.magneticHeading
    self.headingAccuracy = heading.accuracy
    self.source = motion.source
    self.difference =
      bearing.flatMap { reference >= 0 && heading.isValid ? CompassMath.wrap180($0 - reference) : nil }
    self.gravityError = CompassMath.gravityErrorInReference(
      attitude: motion.attitude, gravity: motion.gravity)
  }
}

/// The summary of a D0 recording: pass when every compared line agrees within 3° and every
/// gravity check passes.
public struct CompassDeviceCheckReport: Hashable, Sendable, Codable {
  public static let agreement = 3.0

  public var lines: [CompassDeviceCheckLine]
  public var compared: Int
  public var meanAbsoluteDifference: Double?
  public var maxAbsoluteDifference: Double?
  public var gravityFailures: Int
  public var passes: Bool

  public init(lines: [CompassDeviceCheckLine]) {
    self.lines = lines
    let differences = lines.compactMap(\.difference).map(abs)
    compared = differences.count
    meanAbsoluteDifference =
      differences.isEmpty ? nil : differences.reduce(0, +) / Double(differences.count)
    maxAbsoluteDifference = differences.max()
    gravityFailures = lines.filter { $0.gravityError > CompassMath.gravityToleranceDegrees }.count
    passes =
      compared > 0 && (maxAbsoluteDifference ?? .infinity) <= Self.agreement && gravityFailures == 0
  }
}
