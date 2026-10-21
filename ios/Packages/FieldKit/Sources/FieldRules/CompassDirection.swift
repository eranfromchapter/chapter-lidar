import CaptureContract
import Foundation

// The camera heading at the shutter, for the "Looking toward" pre-fill of a photo (phone-field
// §3.6, compass §5.5). This is the direction the back camera points when the photo is taken,
// not the floor's scan-start compass reading. The attitude convention is the contract's
// (`CompassMath.cameraAxisInReference`); nothing here repeats it.

/// One heading sample of the back camera.
public struct PhotoHeadingSample: Hashable, Sendable {
  /// Camera axis, degrees clockwise from north, `0 ..< 360`.
  public var azimuthDegrees: Double
  /// Length of the horizontal part of the unit camera axis, `0 ... 1` (1: camera level, 0:
  /// pointing straight up or down).
  public var horizontalComponent: Double
  /// `CLHeading.headingAccuracy`, degrees; nil when the compass reports none (negative).
  public var accuracyDegrees: Double?
  /// True or magnetic north.
  public var source: HeadingSource
  public var sampledAt: Date

  public init(
    azimuthDegrees: Double, horizontalComponent: Double, accuracyDegrees: Double?,
    source: HeadingSource, sampledAt: Date
  ) {
    self.azimuthDegrees = azimuthDegrees
    self.horizontalComponent = horizontalComponent
    self.accuracyDegrees = accuracyDegrees.flatMap { $0 >= 0 ? $0 : nil }
    self.source = source
    self.sampledAt = sampledAt
  }
}

/// The back camera's axis from a Core Motion attitude.
public enum CameraAxis {
  /// The sample of `CMDeviceMotion.attitude.rotationMatrix` (reference → device, reference
  /// frame `.xTrueNorthZVertical` for `.trueNorth`, `.xMagneticNorthZVertical` for `.magnetic`),
  /// with the compass accuracy (`CLHeading.headingAccuracy`, negative = invalid) and its time.
  public static func sample(
    rotationMatrix: CompassMath.Matrix3, accuracy: Double?, source: HeadingSource, at time: Date
  ) -> PhotoHeadingSample {
    let axis = CompassMath.cameraAxisInReference(rotationMatrix: rotationMatrix)
    return PhotoHeadingSample(
      azimuthDegrees: CompassMath.bearing(inReference: axis),
      horizontalComponent: min(1, CompassMath.horizontalComponent(inReference: axis)),
      accuracyDegrees: accuracy, source: source, sampledAt: time)
  }
}

extension PhotoDirection {
  /// The newest sample may be at most this old at the shutter.
  public static let compassSampleMaxAge: TimeInterval = 2
  /// Worst compass accuracy, degrees, that still pre-fills (north-arrow v2 "not verified" limit).
  public static let compassMaxAccuracy = Double(CompassThresholds.approximateMax)

  /// The cardinal the compass suggests for a photo taken `now`, or nil when there is no sample,
  /// the sample is older than 2 s, the accuracy is invalid or worse than ±30°, or the camera
  /// points more than 60° up or down (a ceiling photo). Magnetic samples are used too: the
  /// operator can change the choice, and the caption says it came from the compass. Sectors: N
  /// [315, 45), E [45, 135), S [135, 225), W [225, 315).
  public static func fromCompass(_ sample: PhotoHeadingSample?, now: Date) -> PhotoDirection? {
    guard let sample, now.timeIntervalSince(sample.sampledAt) <= compassSampleMaxAge,
      let accuracy = sample.accuracyDegrees, accuracy <= compassMaxAccuracy,
      sample.horizontalComponent >= CompassMath.minimumPhotoHorizontal
    else { return nil }
    return CompassMath.cardinal(sample.azimuthDegrees)
  }
}
