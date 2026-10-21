#if canImport(CoreLocation) && canImport(CoreMotion) && canImport(UIKit) && os(iOS)
  import CaptureCompass
  import CaptureContract
  import CaptureCore
  import Foundation
  import XCTest

  /// `CompassService` where it can run without a phone: the simulator has no magnetometer, so
  /// the service must say so and never hang (compass §1.5 `unavailable`).
  @MainActor
  final class CompassServiceTests: XCTestCase {
    func testTheSimulatorHasNoCompass() async throws {
      #if !targetEnvironment(simulator)
        throw XCTSkip("simulator only")
      #else
        let service = CompassService()
        XCTAssertFalse(service.isAvailable)
        XCTAssertTrue(service.isUnavailableForScan)
        let state = await service.precheck()
        XCTAssertEqual(state, .unavailable)
        XCTAssertNil(service.cameraSample())
      #endif
    }

    func testSensorsStartAndStopInPairs() {
      let service = CompassService()
      service.startScanSensors()
      service.startCameraHeading()
      service.stopCameraHeading()
      service.stopScanSensors()
      // One more stop than starts is harmless.
      service.stopScanSensors()
      XCTAssertNil(service.motionRing.latest)
      XCTAssertNil(service.latestHeading)
    }
  }

  /// Device test D0 (compass §13.5, docs/qa/compass-device-tests.md): run on a phone with
  /// `COMPASS_D0_SECONDS` set (xcodebuild: `TEST_RUNNER_COMPASS_D0_SECONDS=30`); the lines and
  /// the summary are attached to the result bundle as `compass-d0.json`. Skipped elsewhere.
  @MainActor
  final class CompassDeviceCheckTests: XCTestCase {
    func testD0RecordsCompassMathNextToCoreLocation() async throws {
      let environment = ProcessInfo.processInfo.environment
      guard let value = environment["COMPASS_D0_SECONDS"], let seconds = Double(value) else {
        throw XCTSkip("device test D0: set COMPASS_D0_SECONDS on a phone")
      }
      let service = CompassService()
      guard service.isAvailable else { throw XCTSkip("no compass on this device") }
      service.requestAuthorization()
      let report = await CompassDeviceCheck(service: service).record(seconds: seconds)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let attachment = XCTAttachment(
        data: try encoder.encode(report), uniformTypeIdentifier: "public.json")
      attachment.name = "compass-d0.json"
      attachment.lifetime = .keepAlways
      add(attachment)
      XCTAssertGreaterThan(report.compared, 0, "hold the phone flat or upright")
      XCTAssertTrue(
        report.passes,
        "max difference \(report.maxAbsoluteDifference ?? -1)°, gravity failures \(report.gravityFailures)")
    }
  }
#endif
