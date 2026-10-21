import CaptureContract
import FieldRules
import Foundation
import XCTest

/// AC5 (phone-field §3.6): "Looking toward" is pre-filled from the camera heading only with an
/// accuracy within 30° and the camera within 60° of horizontal.
final class CompassDirectionTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_792_000_000)

  /// `CMDeviceMotion.attitude.rotationMatrix` (reference → device: its rows are the device axes
  /// in the reference frame N, +X north, +Y west, +Z up) of a phone held upright in portrait, the
  /// back camera looking toward `bearing`, tilted up by `pitch` degrees.
  private func attitude(bearing: Double, pitch: Double = 0) -> CompassMath.Matrix3 {
    let b = bearing * .pi / 180
    let p = pitch * .pi / 180
    // The camera looks along −Z_D. Its direction in N: north = cos b cos p, west = −sin b cos p.
    let forward = Vec3(x: cos(b) * cos(p), y: -sin(b) * cos(p), z: sin(p))
    let back = Vec3(x: -forward.x, y: -forward.y, z: -forward.z)  // +Z_D
    // +Y_D (top edge) points up, tilted back by the pitch.
    let up = Vec3(x: -cos(b) * sin(p), y: sin(b) * sin(p), z: cos(p))
    // +X_D = Y_D × Z_D.
    let right = Vec3(
      x: up.y * back.z - up.z * back.y, y: up.z * back.x - up.x * back.z,
      z: up.x * back.y - up.y * back.x)
    return CompassMath.Matrix3(rows: right, up, back)
  }

  private func sample(
    bearing: Double, pitch: Double = 0, accuracy: Double? = 8, age: TimeInterval = 0.1,
    source: HeadingSource = .trueNorth
  ) -> PhotoHeadingSample {
    CameraAxis.sample(
      rotationMatrix: attitude(bearing: bearing, pitch: pitch), accuracy: accuracy, source: source,
      at: now.addingTimeInterval(-age))
  }

  func testUprightPhoneFacingEachCardinal() {
    for (bearing, direction) in [
      (0.0, PhotoDirection.north), (90, .east), (180, .south), (270, .west),
    ] {
      let heading = sample(bearing: bearing)
      XCTAssertEqual(heading.azimuthDegrees.truncatingRemainder(dividingBy: 360), bearing, accuracy: 0.01)
      XCTAssertEqual(heading.horizontalComponent, 1, accuracy: 1e-9)
      XCTAssertEqual(PhotoDirection.fromCompass(heading, now: now), direction, "\(bearing)°")
    }
  }

  func testAFlatPhoneOrASteepCameraGivesNoDirection() {
    // Lying flat, screen up: the camera looks at the floor.
    let flat = CompassMath.Matrix3.identity
    let down = CameraAxis.sample(rotationMatrix: flat, accuracy: 5, source: .trueNorth, at: now)
    XCTAssertEqual(down.horizontalComponent, 0, accuracy: 1e-9)
    XCTAssertNil(PhotoDirection.fromCompass(down, now: now))
    // 70° up (a ceiling photo): cos 70° = 0.34 < 0.5.
    XCTAssertNil(PhotoDirection.fromCompass(sample(bearing: 90, pitch: 70), now: now))
    // 55° up still counts: cos 55° = 0.57.
    XCTAssertEqual(PhotoDirection.fromCompass(sample(bearing: 90, pitch: 55), now: now), .east)
  }

  func testSectorBoundaries() {
    func direction(_ azimuth: Double) -> PhotoDirection? {
      PhotoDirection.fromCompass(
        PhotoHeadingSample(
          azimuthDegrees: azimuth, horizontalComponent: 1, accuracyDegrees: 8,
          source: .trueNorth, sampledAt: now),
        now: now)
    }
    XCTAssertEqual(direction(44.9), .north)
    XCTAssertEqual(direction(45), .east)
    XCTAssertEqual(direction(134.9), .east)
    XCTAssertEqual(direction(135), .south)
    XCTAssertEqual(direction(314.9), .west)
    XCTAssertEqual(direction(315), .north)
    XCTAssertEqual(direction(359.9), .north)
  }

  func testAccuracyLimit() {
    XCTAssertEqual(PhotoDirection.fromCompass(sample(bearing: 85, accuracy: 30), now: now), .east)
    XCTAssertNil(PhotoDirection.fromCompass(sample(bearing: 85, accuracy: 30.1), now: now))
    XCTAssertNil(PhotoDirection.fromCompass(sample(bearing: 85, accuracy: nil), now: now))
    // CLHeading reports a negative accuracy when it has none.
    XCTAssertNil(sample(bearing: 85, accuracy: -1).accuracyDegrees)
    XCTAssertNil(PhotoDirection.fromCompass(sample(bearing: 85, accuracy: -1), now: now))
  }

  func testAStaleSampleOrNoSampleGivesNoDirection() {
    XCTAssertEqual(PhotoDirection.fromCompass(sample(bearing: 85, age: 2), now: now), .east)
    XCTAssertNil(PhotoDirection.fromCompass(sample(bearing: 85, age: 2.1), now: now))
    XCTAssertNil(PhotoDirection.fromCompass(nil, now: now))
  }

  func testMagneticSamplesAreUsed() {
    XCTAssertEqual(
      PhotoDirection.fromCompass(sample(bearing: 200, source: .magnetic), now: now), .south)
  }
}
