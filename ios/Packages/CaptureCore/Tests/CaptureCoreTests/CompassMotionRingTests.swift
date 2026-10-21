import CaptureContract
import CaptureCore
import Foundation
import XCTest

/// The motion ring of the scan-start reading and the arithmetic of device test D0.
final class CompassMotionRingTests: XCTestCase {
  private func motion(at time: TimeInterval) -> CompassMotionSample {
    CompassPoses.motion(
      worldHeading: 212.4, worldFromCamera: CompassPoses.worldFromCamera(yaw: 0), timestamp: time)
  }

  func testTheRingKeepsOneSecondAndPairsWithin25Milliseconds() throws {
    let ring = CompassMotionRing()
    for index in 0..<120 { ring.append(motion(at: 100 + Double(index) / 60)) }
    XCTAssertEqual(ring.count, 61, "the last second at 60 Hz")
    XCTAssertEqual(try XCTUnwrap(ring.latest).timestamp, 100 + 119.0 / 60, accuracy: 1e-9)
    let nearest = ring.nearest(to: 101.5)
    XCTAssertEqual(try XCTUnwrap(nearest).timestamp, 101.5, accuracy: 1.0 / 120)
    XCTAssertNil(ring.nearest(to: 102.1), "more than 25 ms after the newest sample")
    XCTAssertNil(ring.nearest(to: 100.5), "older than the ring")
    ring.removeAll()
    XCTAssertNil(ring.latest)
  }

  /// A phone lying flat with its top edge toward `bearing` (degrees clockwise from north).
  private func flat(toward bearing: Double, source: HeadingSource) -> CompassMotionSample {
    let h = bearing * .pi / 180
    let top = Vec3(x: cos(h), y: -sin(h), z: 0)  // N: +X north, +Y west
    let up = Vec3(x: 0, y: 0, z: 1)
    // Right-handed device axes: X (right edge) = Y × Z.
    let right = Vec3(
      x: top.y * up.z - top.z * up.y, y: top.z * up.x - top.x * up.z,
      z: top.x * up.y - top.y * up.x)
    let attitude = CompassMath.Matrix3(columns: right, top, up).transposed
    return CompassMotionSample(
      timestamp: 5, attitude: attitude, gravity: attitude * Vec3(x: 0, y: 0, z: -1),
      rotationRate: 0, magneticFieldCalibrated: true, source: source)
  }

  func testAFlatPhoneComparesItsTopEdge() throws {
    let heading = CompassHeadingSample(
      date: Date(), trueHeading: 213.9, magneticHeading: 200, accuracy: 6)
    let line = CompassDeviceCheckLine(
      time: 1, motion: flat(toward: 212.4, source: .trueNorth), heading: heading)
    XCTAssertEqual(line.posture, .flat)
    XCTAssertEqual(try XCTUnwrap(line.bearing), 212.4, accuracy: 1e-6)
    XCTAssertEqual(try XCTUnwrap(line.difference), -1.5, accuracy: 1e-6)
    XCTAssertEqual(line.gravityError, 0, accuracy: 1e-6)

    let report = CompassDeviceCheckReport(lines: [line])
    XCTAssertTrue(report.passes)
    XCTAssertEqual(try XCTUnwrap(report.maxAbsoluteDifference), 1.5, accuracy: 1e-6)

    var off = line
    off.difference = 4
    XCTAssertFalse(CompassDeviceCheckReport(lines: [line, off]).passes, "beyond 3 degrees")
    var tilted = line
    tilted.gravityError = 5
    XCTAssertFalse(CompassDeviceCheckReport(lines: [tilted]).passes, "a gravity check failed")
    XCTAssertFalse(CompassDeviceCheckReport(lines: []).passes, "nothing compared")
  }

  func testAnUprightPhoneComparesItsCamera() throws {
    // Upright portrait, the camera toward 85 (magnetic north frame).
    let sample = CompassPoses.motion(
      worldHeading: 85, worldFromCamera: CompassPoses.worldFromCamera(yaw: 0), timestamp: 1,
      source: .magnetic)
    let line = CompassDeviceCheckLine(
      time: 0, motion: sample,
      heading: CompassHeadingSample(date: Date(), trueHeading: -1, magneticHeading: 86, accuracy: 9))
    XCTAssertEqual(line.posture, .upright)
    XCTAssertEqual(try XCTUnwrap(line.bearing), 85, accuracy: 1e-6)
    XCTAssertEqual(try XCTUnwrap(line.difference), -1, accuracy: 1e-6, "against the magnetic heading")
  }

  func testAnInvalidCoreLocationHeadingIsNotCompared() {
    let line = CompassDeviceCheckLine(
      time: 0, motion: flat(toward: 10, source: .trueNorth),
      heading: CompassHeadingSample(date: Date(), trueHeading: -1, magneticHeading: 5, accuracy: -1))
    XCTAssertNotNil(line.bearing)
    XCTAssertNil(line.difference)
  }
}
