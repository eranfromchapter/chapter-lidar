import CaptureContract
import Foundation
import XCTest

/// Compass spec 13.1: the frame conventions of CompassMath against synthetic Core Motion
/// attitudes and ARKit camera poses built from a known heading, world yaw and device posture.
final class CompassMathTests: XCTestCase {
  typealias Matrix3 = CompassMath.Matrix3

  private let up = Vec3(x: 0, y: 1, z: 0)
  private let deviceX = Vec3(x: 1, y: 0, z: 0)
  private let deviceZ = Vec3(x: 0, y: 0, z: 1)

  /// R_N←W of a world whose −Z axis has bearing `heading`: X_W, Y_W, Z_W in N (+X north,
  /// +Y west, +Z up).
  private func referenceFromWorld(heading: Double) -> Matrix3 {
    let h = heading * .pi / 180
    return Matrix3(
      columns: Vec3(x: -sin(h), y: -cos(h), z: 0), Vec3(x: 0, y: 0, z: 1),
      Vec3(x: -cos(h), y: sin(h), z: 0))
  }

  /// Device postures as R_W←D before the world yaw: identity is upright portrait with the back
  /// camera looking along the world's −Z.
  private var postures: [(String, Matrix3)] {
    [
      ("upright", .identity),
      ("flat, screen up", Matrix3.rotation(about: deviceX, degrees: -90)),
      ("pitched 30°", Matrix3.rotation(about: deviceX, degrees: 30)),
      ("pitched 60°", Matrix3.rotation(about: deviceX, degrees: -60)),
      ("rolled 20°", Matrix3.rotation(about: deviceZ, degrees: 20)),
    ]
  }

  /// A paired sample: Core Motion's attitude matrix (reference to device) and ARKit's R_W←K.
  private func sample(heading: Double, yaw: Double, posture: Matrix3) -> (
    attitude: Matrix3, worldFromCamera: Matrix3, worldFromDevice: Matrix3
  ) {
    let worldFromDevice = Matrix3.rotation(about: up, degrees: yaw) * posture
    let referenceFromDevice = referenceFromWorld(heading: heading) * worldFromDevice
    let worldFromCamera = worldFromDevice * CompassMath.cameraFromDevice.transposed
    return (referenceFromDevice.transposed, worldFromCamera, worldFromDevice)
  }

  private func assertAngle(
    _ actual: Double?, _ expected: Double, accuracy: Double = 0.01, _ message: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    guard let actual else { return XCTFail("nil, expected \(expected): \(message)", file: file, line: line) }
    XCTAssertEqual(
      CompassMath.angularDistance(actual, expected), 0, accuracy: accuracy, message,
      file: file, line: line)
  }

  // MARK: Heading of the world frame

  func testWorldHeadingIsTheConstructedHeadingForEveryPostureAndWorldYaw() {
    var generator = SplitMix(seed: 7)
    for (name, posture) in postures {
      for _ in 0..<40 {
        let heading = generator.next() * 360
        let yaw = generator.next() * 360
        let s = sample(heading: heading, yaw: yaw, posture: posture)
        let r = CompassMath.referenceFromWorld(attitude: s.attitude, worldFromCamera: s.worldFromCamera)
        assertAngle(CompassMath.worldHeading(referenceFromWorld: r), heading, "\(name) H \(heading) ω \(yaw)")
      }
    }
  }

  func testCaptureHeadingAddsTheFrameYaw() {
    XCTAssertEqual(CompassMath.captureFrameYaw, 0)
    XCTAssertEqual(CompassMath.captureHeading(worldHeading: 212.4), 212.4)
    XCTAssertEqual(CompassMath.captureHeading(worldHeading: 350, frameYaw: 20), 10, accuracy: 1e-9)
    XCTAssertEqual(CompassMath.captureHeading(worldHeading: 10, frameYaw: -37), 333, accuracy: 1e-9)
  }

  func testCameraFromDeviceMapsTheAxes() {
    let k = CompassMath.cameraFromDevice
    XCTAssertEqual(k * Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 1, z: 0))
    XCTAssertEqual(k * Vec3(x: 0, y: 1, z: 0), Vec3(x: -1, y: 0, z: 0))
    XCTAssertEqual(k * Vec3(x: 0, y: 0, z: 1), Vec3(x: 0, y: 0, z: 1))
  }

  // MARK: Gravity checks

  func testGravityChecksPassForConsistentSamples() {
    for (name, posture) in postures {
      let s = sample(heading: 212.4, yaw: 33, posture: posture)
      let gravity = s.worldFromDevice.transposed * Vec3(x: 0, y: -1, z: 0)
      XCTAssertEqual(
        CompassMath.gravityErrorInReference(attitude: s.attitude, gravity: gravity), 0,
        accuracy: 1e-6, name)
      XCTAssertEqual(
        CompassMath.gravityErrorInWorld(worldFromCamera: s.worldFromCamera, gravity: gravity), 0,
        accuracy: 1e-6, name)
      XCTAssertTrue(
        CompassMath.passesGravityChecks(
          attitude: s.attitude, worldFromCamera: s.worldFromCamera, gravity: gravity), name)
    }
  }

  func testATransposedCoreMotionMatrixFailsTheGravityCheck() {
    for (name, posture) in postures where name != "flat, screen up" {
      let s = sample(heading: 212.4, yaw: 33, posture: posture)
      let gravity = s.worldFromDevice.transposed * Vec3(x: 0, y: -1, z: 0)
      XCTAssertFalse(
        CompassMath.passesGravityChecks(
          attitude: s.attitude.transposed, worldFromCamera: s.worldFromCamera, gravity: gravity),
        name)
    }
  }

  func testAWrongCameraMappingFailsTheGravityCheck() {
    let s = sample(heading: 90, yaw: 0, posture: .identity)
    let gravity = s.worldFromDevice.transposed * Vec3(x: 0, y: -1, z: 0)
    // ARKit's camera pose used as if it were the device pose (the K→D mapping forgotten).
    XCTAssertGreaterThan(
      CompassMath.gravityErrorInWorld(worldFromCamera: s.worldFromDevice, gravity: gravity), 45)
  }

  // MARK: Camera bearing during the scan and photo azimuth

  func testCameraBearingDuringTheScan() {
    for yaw in [0.0, 30, 90, 200, 359] {
      let s = sample(heading: 212.4, yaw: yaw, posture: .identity)
      assertAngle(CompassMath.cameraYaw(worldFromCamera: s.worldFromCamera), 360 - yaw, "ψ at ω \(yaw)")
      assertAngle(
        CompassMath.cameraBearing(worldHeading: 212.4, worldFromCamera: s.worldFromCamera),
        212.4 - yaw, "bearing at ω \(yaw)")
    }
    let looking = sample(heading: 0, yaw: -90, posture: .identity)
    assertAngle(
      CompassMath.cameraYaw(worldFromCamera: looking.worldFromCamera), 90,
      "turning right looks along +X, 90° clockwise from −Z")
    let flat = sample(heading: 0, yaw: 0, posture: Matrix3.rotation(about: deviceX, degrees: -90))
    XCTAssertNil(CompassMath.cameraYaw(worldFromCamera: flat.worldFromCamera), "camera looks down")
  }

  func testPhotoAzimuthFromCoreMotionAlone() {
    for (name, posture, valid) in [
      ("upright", Matrix3.identity, true),
      ("pitched 30°", Matrix3.rotation(about: deviceX, degrees: 30), true),
      ("pitched 59°", Matrix3.rotation(about: deviceX, degrees: -59), true),
      ("pitched 61°", Matrix3.rotation(about: deviceX, degrees: -61), false),
      ("flat, screen up", Matrix3.rotation(about: deviceX, degrees: -90), false),
    ] {
      let s = sample(heading: 100, yaw: 25, posture: posture)
      let azimuth = CompassMath.photoAzimuth(rotationMatrix: s.attitude)
      if valid {
        assertAngle(azimuth, 75, name)
      } else {
        XCTAssertNil(azimuth, name)
      }
    }
  }

  func testCameraAxisIsTheNegatedThirdRowOfTheAttitudeMatrix() {
    let m = Matrix3(m11: 1, m12: 2, m13: 3, m21: 4, m22: 5, m23: 6, m31: 7, m32: 8, m33: 9)
    XCTAssertEqual(CompassMath.cameraAxisInReference(rotationMatrix: m), Vec3(x: -7, y: -8, z: -9))
  }

  func testBearingOfReferenceDirections() {
    XCTAssertEqual(CompassMath.bearing(inReference: Vec3(x: 1, y: 0, z: 0)), 0)
    XCTAssertEqual(CompassMath.bearing(inReference: Vec3(x: 0, y: -1, z: 0)), 90)
    XCTAssertEqual(CompassMath.bearing(inReference: Vec3(x: -1, y: 0, z: 0)), 180)
    XCTAssertEqual(CompassMath.bearing(inReference: Vec3(x: 0, y: 1, z: 0)), 270)
  }

  func testCardinalSectors() {
    let cases: [(Double, PhotoDirection)] = [
      (0, .north), (44.9, .north), (45, .east), (85, .east), (134.9, .east), (135, .south),
      (224.9, .south), (225, .west), (314.9, .west), (315, .north), (359.9, .north), (-10, .north),
    ]
    for (bearing, direction) in cases {
      XCTAssertEqual(CompassMath.cardinal(bearing), direction, "\(bearing)")
    }
  }

  // MARK: Drawings (compass spec 2.5)

  func testArrowAngleTable() {
    let table: [(heading: Double, rho: Double, angle: Double)] = [
      (0, 0, 0), (90, 0, 90), (212.4, 0, 212.4), (90, -30, 60), (359.7, 0, 359.7),
      (350, 20, 10), (10, -20, 350),
    ]
    for row in table {
      XCTAssertEqual(
        CompassMath.arrowAngle(heading: row.heading, drawingRotationCCW: row.rho), row.angle,
        accuracy: 1e-9, "\(row)")
    }
  }

  // MARK: Angles

  func testWrapAndNormalize() {
    XCTAssertEqual(CompassMath.normalized(360), 0)
    XCTAssertEqual(CompassMath.normalized(-90), 270)
    XCTAssertEqual(CompassMath.normalized(725), 5)
    XCTAssertEqual(CompassMath.normalized(-1e-15), 0, "a tiny negative angle is not 360")
    XCTAssertEqual(CompassMath.wrap180(270), -90)
    XCTAssertEqual(CompassMath.wrap180(180), 180)
    XCTAssertEqual(CompassMath.wrap180(-180), 180)
    XCTAssertEqual(CompassMath.wrap90(179), -1)
    XCTAssertEqual(CompassMath.wrap90(-90), 90)
    XCTAssertEqual(CompassMath.wrap90(37), 37)
    XCTAssertEqual(CompassMath.wrap90(217), 37)
    XCTAssertEqual(CompassMath.angularDistance(359, 1), 2, accuracy: 1e-9)
    XCTAssertEqual(CompassMath.angularDistance(10, 200), 170, accuracy: 1e-9)
  }

  func testCircularMeanAcrossNorth() {
    assertAngle(CompassMath.circularMean([359, 1]), 0, accuracy: 1e-9, "359 and 1")
    assertAngle(CompassMath.circularMean([350, 10, 0]), 0, accuracy: 1e-9, "350, 10, 0")
    assertAngle(CompassMath.circularMean([210, 212, 214]), 212, accuracy: 1e-9, "near 212")
    XCTAssertNil(CompassMath.circularMean([]))
    XCTAssertNil(CompassMath.circularMean([0, 180]), "opposite bearings cancel")
    XCTAssertEqual(CompassMath.spread([359, 1, 3], around: 1), 2, accuracy: 1e-9)
  }

  func testStoredValues() {
    XCTAssertEqual(CompassMath.storedHeading(212.44), 212.4)
    XCTAssertEqual(CompassMath.storedHeading(212.46), 212.5)
    XCTAssertEqual(CompassMath.storedHeading(359.96), 0)
    XCTAssertEqual(CompassMath.storedHeading(-0.2), 359.8, accuracy: 1e-9)
    XCTAssertEqual(CompassMath.storedAccuracy(7.2), 8)
    XCTAssertEqual(CompassMath.storedAccuracy(8), 8)
    XCTAssertEqual(CompassMath.storedAccuracy(0.3), 1)
    XCTAssertEqual(CompassMath.wholeDegrees(359.5), 0)
    XCTAssertEqual(CompassMath.wholeDegrees(359.4), 359)
  }

  func testMatrixHelpers() {
    let r = Matrix3.rotation(about: up, degrees: 90)
    let v = r * Vec3(x: 0, y: 0, z: -1)
    XCTAssertEqual(v.x, -1, accuracy: 1e-12)
    XCTAssertEqual(v.z, 0, accuracy: 1e-12)
    let product = r * r.transposed
    for (actual, expected) in zip(
      [product.m11, product.m12, product.m13, product.m22, product.m33], [1.0, 0, 0, 1, 1])
    {
      XCTAssertEqual(actual, expected, accuracy: 1e-12)
    }
    let columns = Matrix3(
      columns: Vec3(x: 1, y: 4, z: 7), Vec3(x: 2, y: 5, z: 8), Vec3(x: 3, y: 6, z: 9))
    XCTAssertEqual(
      columns,
      Matrix3(rows: Vec3(x: 1, y: 2, z: 3), Vec3(x: 4, y: 5, z: 6), Vec3(x: 7, y: 8, z: 9)))
    XCTAssertEqual(columns.transposed.transposed, columns)
  }
}

/// Deterministic numbers in [0, 1) for the synthetic poses.
private struct SplitMix {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) / Double(UInt64(1) << 53)
  }
}
