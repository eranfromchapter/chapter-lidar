import Foundation

/// Compass geometry shared by the scan-start reading (CaptureCore), the photo heading (FieldKit)
/// and every drawing of north (PlanExport). Pure Swift without simd, so it builds and is tested on
/// Linux; callers convert `CMRotationMatrix` and `simd_float4x4` to `Matrix3`.
///
/// Frames:
/// - W, ARKit world: right-handed, +Y up, yaw arbitrary with respect to north.
/// - C, capture frame (capture-model.json): expected equal to W (`captureFrameYaw`).
/// - P, plan frame: x = C.x, y = −C.z (seen from above, not mirrored).
/// - D, device (Core Motion): +X right edge (portrait), +Y top edge, +Z out of the screen.
/// - K, ARKit camera: +X = −Y_D, +Y = +X_D, +Z = +Z_D.
/// - N, Core Motion reference (`.xTrueNorthZVertical` / `.xMagneticNorthZVertical`): +X north,
///   +Y west, +Z up.
///
/// Rotations act on column vectors: `v_target = R_target←source · v_source`. Bearings are degrees
/// clockwise from north in `0 ..< 360`.
public enum CompassMath {
  /// A 3 × 3 matrix, `m{row}{column}`, the layout of `CMRotationMatrix`.
  public struct Matrix3: Hashable, Sendable {
    public var m11: Double, m12: Double, m13: Double
    public var m21: Double, m22: Double, m23: Double
    public var m31: Double, m32: Double, m33: Double

    public init(
      m11: Double, m12: Double, m13: Double,
      m21: Double, m22: Double, m23: Double,
      m31: Double, m32: Double, m33: Double
    ) {
      self.m11 = m11
      self.m12 = m12
      self.m13 = m13
      self.m21 = m21
      self.m22 = m22
      self.m23 = m23
      self.m31 = m31
      self.m32 = m32
      self.m33 = m33
    }

    public init(rows r1: Vec3, _ r2: Vec3, _ r3: Vec3) {
      self.init(
        m11: r1.x, m12: r1.y, m13: r1.z, m21: r2.x, m22: r2.y, m23: r2.z, m31: r3.x, m32: r3.y,
        m33: r3.z)
    }

    /// From three columns, for example the axes of a frame in another frame's coordinates (the
    /// upper-left 3 × 3 of `ARFrame.camera.transform` is `columns: columns.0, columns.1,
    /// columns.2`).
    public init(columns c1: Vec3, _ c2: Vec3, _ c3: Vec3) {
      self.init(
        m11: c1.x, m12: c2.x, m13: c3.x, m21: c1.y, m22: c2.y, m23: c3.y, m31: c1.z, m32: c2.z,
        m33: c3.z)
    }

    public static let identity = Matrix3(
      m11: 1, m12: 0, m13: 0, m21: 0, m22: 1, m23: 0, m31: 0, m32: 0, m33: 1)

    public var transposed: Matrix3 {
      Matrix3(
        m11: m11, m12: m21, m13: m31, m21: m12, m22: m22, m23: m32, m31: m13, m32: m23, m33: m33)
    }

    public static func * (a: Matrix3, b: Matrix3) -> Matrix3 {
      Matrix3(
        m11: a.m11 * b.m11 + a.m12 * b.m21 + a.m13 * b.m31,
        m12: a.m11 * b.m12 + a.m12 * b.m22 + a.m13 * b.m32,
        m13: a.m11 * b.m13 + a.m12 * b.m23 + a.m13 * b.m33,
        m21: a.m21 * b.m11 + a.m22 * b.m21 + a.m23 * b.m31,
        m22: a.m21 * b.m12 + a.m22 * b.m22 + a.m23 * b.m32,
        m23: a.m21 * b.m13 + a.m22 * b.m23 + a.m23 * b.m33,
        m31: a.m31 * b.m11 + a.m32 * b.m21 + a.m33 * b.m31,
        m32: a.m31 * b.m12 + a.m32 * b.m22 + a.m33 * b.m32,
        m33: a.m31 * b.m13 + a.m32 * b.m23 + a.m33 * b.m33)
    }

    public static func * (a: Matrix3, v: Vec3) -> Vec3 {
      Vec3(
        x: a.m11 * v.x + a.m12 * v.y + a.m13 * v.z,
        y: a.m21 * v.x + a.m22 * v.y + a.m23 * v.z,
        z: a.m31 * v.x + a.m32 * v.y + a.m33 * v.z)
    }

    /// The rotation by `degrees` about `axis` (right-hand rule; the axis need not be unit length).
    public static func rotation(about axis: Vec3, degrees: Double) -> Matrix3 {
      let length = (axis.x * axis.x + axis.y * axis.y + axis.z * axis.z).squareRoot()
      let (x, y, z) = (axis.x / length, axis.y / length, axis.z / length)
      let angle = degrees * .pi / 180
      let c = cos(angle)
      let s = sin(angle)
      let t = 1 - c
      return Matrix3(
        m11: t * x * x + c, m12: t * x * y - s * z, m13: t * x * z + s * y,
        m21: t * x * y + s * z, m22: t * y * y + c, m23: t * y * z - s * x,
        m31: t * x * z - s * y, m32: t * y * z + s * x, m33: t * z * z + c)
    }
  }

  // MARK: Frames and rotations

  /// R_K←D: X_D = +Y_K, Y_D = −X_K, Z_D = +Z_K.
  public static let cameraFromDevice = Matrix3(
    rows: Vec3(x: 0, y: -1, z: 0), Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 0, z: 1))

  /// Yaw φ from the ARKit world W to the capture frame C, degrees, added to the world heading.
  /// 0 while C = W (the working assumption until device test D1 says otherwise).
  public static let captureFrameYaw: Double = 0

  /// R_N←D from `CMDeviceMotion.attitude.rotationMatrix`, which maps the reference frame to the
  /// device (its rows are the device axes in reference coordinates).
  public static func referenceFromDevice(attitude: Matrix3) -> Matrix3 {
    attitude.transposed
  }

  /// R_W←D = R_W←K · R_K←D, with R_W←K the upper-left 3 × 3 of `ARFrame.camera.transform`.
  public static func worldFromDevice(worldFromCamera: Matrix3) -> Matrix3 {
    worldFromCamera * cameraFromDevice
  }

  /// R_N←W = R_N←D · transpose(R_W←D) from one Core Motion attitude and one ARKit camera pose
  /// taken at the same moment.
  public static func referenceFromWorld(attitude: Matrix3, worldFromCamera: Matrix3) -> Matrix3 {
    referenceFromDevice(attitude: attitude) * worldFromDevice(worldFromCamera: worldFromCamera)
      .transposed
  }

  /// Bearing of a horizontal direction given in N: east = −v.y (N's +Y is west), north = v.x.
  public static func bearing(inReference v: Vec3) -> Double {
    normalized(atan2(-v.y, v.x) * 180 / .pi)
  }

  /// H_W: bearing of the world's −Z axis (plan up) from R_N←W.
  public static func worldHeading(referenceFromWorld: Matrix3) -> Double {
    bearing(inReference: referenceFromWorld * Vec3(x: 0, y: 0, z: -1))
  }

  /// H_C = (H_W + φ) mod 360: the heading stored for the capture.
  public static func captureHeading(worldHeading: Double, frameYaw: Double = captureFrameYaw)
    -> Double
  {
    normalized(worldHeading + frameYaw)
  }

  /// Shortest horizontal part of the camera axis for a valid camera bearing during the scan.
  public static let minimumCameraHorizontal = 0.3
  /// Shortest horizontal part of the camera axis for a photo azimuth (camera at most 60° up or
  /// down).
  public static let minimumPhotoHorizontal = 0.5

  /// ψ: the camera's viewing direction clockwise from W's −Z seen from above, degrees in
  /// `0 ..< 360`; nil when the camera points steeply up or down.
  public static func cameraYaw(worldFromCamera: Matrix3) -> Double? {
    let f = worldFromCamera * Vec3(x: 0, y: 0, z: -1)
    guard (f.x * f.x + f.z * f.z).squareRoot() >= minimumCameraHorizontal else { return nil }
    return normalized(atan2(f.x, -f.z) * 180 / .pi)
  }

  /// Bearing the camera looks at during the scan: (H_W + ψ) mod 360.
  public static func cameraBearing(worldHeading: Double, worldFromCamera: Matrix3) -> Double? {
    cameraYaw(worldFromCamera: worldFromCamera).map { normalized(worldHeading + $0) }
  }

  /// The back camera's axis (device −Z) in the reference frame N, from
  /// `CMDeviceMotion.attitude.rotationMatrix`: (−m31, −m32, −m33).
  public static func cameraAxisInReference(rotationMatrix m: Matrix3) -> Vec3 {
    referenceFromDevice(attitude: m) * Vec3(x: 0, y: 0, z: -1)
  }

  /// Length of the horizontal part of a direction given in N.
  public static func horizontalComponent(inReference v: Vec3) -> Double {
    (v.x * v.x + v.y * v.y).squareRoot()
  }

  /// Bearing of the back camera from Core Motion alone (photos); nil when the camera points more
  /// than 60° up or down.
  public static func photoAzimuth(rotationMatrix: Matrix3) -> Double? {
    let u = cameraAxisInReference(rotationMatrix: rotationMatrix)
    guard horizontalComponent(inReference: u) >= minimumPhotoHorizontal else { return nil }
    return bearing(inReference: u)
  }

  // MARK: Convention checks

  /// Largest angle, degrees, between measured and expected gravity for a sample to be used.
  public static let gravityToleranceDegrees = 3.0

  /// Angle between gravity seen through Core Motion (R_N←D · g_D) and (0, 0, −1).
  public static func gravityErrorInReference(attitude: Matrix3, gravity: Vec3) -> Double {
    angleBetween(referenceFromDevice(attitude: attitude) * gravity, Vec3(x: 0, y: 0, z: -1))
  }

  /// Angle between gravity seen through ARKit (R_W←D · g_D) and (0, −1, 0).
  public static func gravityErrorInWorld(worldFromCamera: Matrix3, gravity: Vec3) -> Double {
    angleBetween(worldFromDevice(worldFromCamera: worldFromCamera) * gravity, Vec3(x: 0, y: -1, z: 0))
  }

  /// Both gravity checks of a paired sample: a transposed matrix or a wrong camera mapping fails.
  /// `gravity` is `CMDeviceMotion.gravity`, toward the Earth in D.
  public static func passesGravityChecks(
    attitude: Matrix3, worldFromCamera: Matrix3, gravity: Vec3
  ) -> Bool {
    gravityErrorInReference(attitude: attitude, gravity: gravity) <= gravityToleranceDegrees
      && gravityErrorInWorld(worldFromCamera: worldFromCamera, gravity: gravity)
        <= gravityToleranceDegrees
  }

  // MARK: Drawings

  /// A = (H + ρ) mod 360: the arrow angle counter-clockwise from "up" on a drawing that shows the
  /// plan turned counter-clockwise by ρ, and the bearing of "up" on it.
  public static func arrowAngle(heading: Double, drawingRotationCCW rho: Double) -> Double {
    normalized(heading + rho)
  }

  // MARK: Angles

  /// Degrees in `0 ..< 360`.
  public static func normalized(_ degrees: Double) -> Double {
    let turned = degrees.truncatingRemainder(dividingBy: 360)
    let positive = turned < 0 ? turned + 360 : turned
    return positive >= 360 ? 0 : positive
  }

  /// Degrees in `(−180, 180]`.
  public static func wrap180(_ degrees: Double) -> Double {
    let turned = normalized(degrees)
    return turned > 180 ? turned - 360 : turned
  }

  /// Degrees in `(−90, 90]`: a direction without its sense (surfaces re-fitted end for end).
  public static func wrap90(_ degrees: Double) -> Double {
    var turned = wrap180(degrees)
    if turned > 90 { turned -= 180 }
    if turned <= -90 { turned += 180 }
    return turned
  }

  /// Smallest angle between two bearings, `0 ... 180`.
  public static func angularDistance(_ a: Double, _ b: Double) -> Double {
    abs(wrap180(a - b))
  }

  /// Circular mean of bearings, in `0 ..< 360`; nil when empty or when they cancel out.
  public static func circularMean(_ bearings: [Double]) -> Double? {
    guard !bearings.isEmpty else { return nil }
    var sine = 0.0
    var cosine = 0.0
    for bearing in bearings {
      sine += sin(bearing * .pi / 180)
      cosine += cos(bearing * .pi / 180)
    }
    guard (sine * sine + cosine * cosine).squareRoot() > 1e-9 * Double(bearings.count) else {
      return nil
    }
    return normalized(atan2(sine, cosine) * 180 / .pi)
  }

  /// Largest angular distance of a bearing from `mean`.
  public static func spread(_ bearings: [Double], around mean: Double) -> Double {
    bearings.map { angularDistance($0, mean) }.max() ?? 0
  }

  /// A bearing rounded half up to a whole degree, mod 360 (`{HDG}`): 359.6 → 0, never 360.
  public static func wholeDegrees(_ degrees: Double) -> Int {
    Int(normalized((normalized(degrees) + 0.5).rounded(.down)))
  }

  /// The heading as stored: one decimal, in `0 ..< 360` (359.96 → 0.0).
  public static func storedHeading(_ degrees: Double) -> Double {
    normalized((normalized(degrees) * 10).rounded() / 10)
  }

  /// An accuracy as stored: whole degrees rounded up, at least 1.
  public static func storedAccuracy(_ degrees: Double) -> Int {
    max(1, Int(degrees.rounded(.up)))
  }

  /// The cardinal sector of a bearing: N [315, 45), E [45, 135), S [135, 225), W [225, 315).
  public static func cardinal(_ bearing: Double) -> PhotoDirection {
    let degrees = normalized(bearing)
    switch degrees {
    case 45..<135: return .east
    case 135..<225: return .south
    case 225..<315: return .west
    default: return .north
    }
  }

  private static func angleBetween(_ a: Vec3, _ b: Vec3) -> Double {
    let dot = a.x * b.x + a.y * b.y + a.z * b.z
    let lengths =
      (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() * (b.x * b.x + b.y * b.y + b.z * b.z)
      .squareRoot()
    guard lengths > 0 else { return 180 }
    return acos(min(1, max(-1, dot / lengths))) * 180 / .pi
  }
}
