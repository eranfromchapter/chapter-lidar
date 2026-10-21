import CaptureContract
import CaptureCore
import Foundation

/// Synthetic, self-consistent ARKit poses and Core Motion attitudes for the compass tests: a
/// world W whose −Z axis has bearing `worldHeading`, and a phone held upright in portrait whose
/// camera looks `cameraYaw` degrees clockwise from W's −Z, pitched by `pitch` (positive up).
enum CompassPoses {
  typealias Matrix3 = CompassMath.Matrix3

  /// R_N←W for a world whose −Z axis has bearing `heading` (+Y up maps to N's +Z up).
  static func referenceFromWorld(heading: Double) -> Matrix3 {
    let h = heading * .pi / 180
    return Matrix3(
      columns: Vec3(x: -sin(h), y: -cos(h), z: 0), Vec3(x: 0, y: 0, z: 1),
      Vec3(x: -cos(h), y: sin(h), z: 0))
  }

  /// R_W←K of an upright portrait phone whose camera looks at `yaw` (clockwise from W's −Z seen
  /// from above), pitched up by `pitch` about the camera's horizontal axis.
  static func worldFromCamera(yaw: Double, pitch: Double = 0) -> Matrix3 {
    let y = yaw * .pi / 180
    // Camera axes of the level pose: X_K down, Y_K to the right, Z_K back toward the operator.
    let level = Matrix3(
      columns: Vec3(x: 0, y: -1, z: 0), Vec3(x: cos(y), y: 0, z: sin(y)),
      Vec3(x: -sin(y), y: 0, z: cos(y)))
    // Pitching up turns about the camera's right axis (Y_K) by the right-hand rule.
    let right = level * Vec3(x: 0, y: 1, z: 0)
    return Matrix3.rotation(about: right, degrees: pitch) * level
  }

  /// `CMAttitude.rotationMatrix` (reference → device) of that pose, and gravity in the device.
  static func motion(
    worldHeading: Double, worldFromCamera: Matrix3, timestamp: TimeInterval,
    rotationRate: Double = 0, calibrated: Bool = true, source: HeadingSource = .trueNorth
  ) -> CompassMotionSample {
    let referenceFromDevice =
      referenceFromWorld(heading: worldHeading)
      * CompassMath.worldFromDevice(worldFromCamera: worldFromCamera)
    let attitude = referenceFromDevice.transposed
    return CompassMotionSample(
      timestamp: timestamp, attitude: attitude, gravity: attitude * Vec3(x: 0, y: 0, z: -1),
      rotationRate: rotationRate, magneticFieldCalibrated: calibrated, source: source)
  }

  static let start = Date(timeIntervalSince1970: 1_792_245_500)

  /// A pair at `time` seconds into the scan (4 Hz ticks), `compassHeading` being what the
  /// compass says W's −Z is (true or magnetic per `source`).
  static func pair(
    at time: TimeInterval, compassHeading: Double = 212.4, cameraYaw: Double = 40,
    accuracy: Double = 8, source: HeadingSource = .trueNorth, rotationRate: Double = 0,
    trackingNormal: Bool = true, calibrated: Bool = true, runningTime: TimeInterval? = nil,
    headingAge: TimeInterval = 0.1
  ) -> CompassPair {
    let camera = worldFromCamera(yaw: cameraYaw)
    let date = start.addingTimeInterval(time)
    return CompassPair(
      timestamp: 1000 + time, runningTime: runningTime ?? time, date: date,
      trackingNormal: trackingNormal, worldFromCamera: camera,
      motion: motion(
        worldHeading: compassHeading, worldFromCamera: camera, timestamp: 1000 + time,
        rotationRate: rotationRate, calibrated: calibrated, source: source),
      heading: CompassHeadingSample(
        date: date.addingTimeInterval(-headingAge), trueHeading: source == .trueNorth ? 100 : -1,
        magneticHeading: 90, accuracy: accuracy))
  }

  /// Eight pairs, 0.25 s apart, from `time`.
  static func window(
    from time: TimeInterval, compassHeadings: [Double]? = nil, accuracy: Double = 8,
    source: HeadingSource = .trueNorth
  ) -> [CompassPair] {
    (0..<8).map { index in
      pair(
        at: time + Double(index) * 0.25, compassHeading: compassHeadings?[index] ?? 212.4,
        cameraYaw: 40 + Double(index) * 3, accuracy: accuracy, source: source)
    }
  }
}
