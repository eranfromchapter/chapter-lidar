import CaptureContract
import CaptureCore
import CaptureModelMapping
import CaptureTestSupport
import Foundation
import XCTest

final class ReplaySessionTests: XCTestCase {
  private func source(_ name: String) throws -> ReplaySource {
    let fixture = try Fixtures.load(name)
    return ReplaySource(
      originals: RawOriginals(
        roomPlanJSON: try fixture.roomPlanData(),
        depthSamples: try DepthSamplesCodec.decode(fixture.depthSamplesData())))
  }

  private func collect(_ session: ReplaySession) async -> [CaptureSessionEvent] {
    var events: [CaptureSessionEvent] = []
    for await event in session.events { events.append(event) }
    return events
  }

  func testPlaybackReportsGrowingCountsAndEndsWithTheTotals() async throws {
    let session = try ReplaySession(source: try source("two-room-apartment"), steps: 4)
    try await session.start(CaptureSessionConfiguration(mode: .floor))
    let result = try await session.finish()
    let events = await collect(session)

    let progress = events.compactMap { event -> ScanProgress? in
      if case .progress(let value) = event { return value }
      return nil
    }
    XCTAssertGreaterThanOrEqual(progress.count, 5)
    XCTAssertEqual(progress.first?.counts, ScanCounts())
    for pair in zip(progress, progress.dropFirst()) {
      XCTAssertLessThanOrEqual(pair.0.counts.walls, pair.1.counts.walls)
    }
    let last = try XCTUnwrap(progress.last)
    XCTAssertEqual(last.counts.walls, 8)
    XCTAssertEqual(last.counts.doors, 1)
    XCTAssertEqual(last.counts.windows, 2)
    XCTAssertEqual(last.counts.rooms, 2)
    XCTAssertEqual(last.depthSampleCount, result.originals.depthSamples.count)

    XCTAssertEqual(
      events.compactMap { event -> CaptureSessionState? in
        if case .stateChanged(let state) = event { return state }
        return nil
      }, [.running, .finishing, .finished])
    XCTAssertTrue(events.contains(.instruction(.normal)))
  }

  func testResultCarriesTheRecordedOriginalsAndMapsToACaptureModel() async throws {
    let fixture = try Fixtures.load("box-room")
    let session = try ReplaySession(source: try source("box-room"))
    try await session.start(CaptureSessionConfiguration(mode: .room))
    let result = try await session.finish()
    XCTAssertEqual(result.originals.roomPlanJSON, try fixture.roomPlanData())
    let context = MappingContext(
      visitId: try XCTUnwrap(LowercaseUUID(rawValue: fixture.visitId)),
      captureId: try XCTUnwrap(LowercaseUUID(rawValue: try XCTUnwrap(fixture.captureTruth()["captureId"]?.string))),
      areaKey: "floor-1", label: "Floor 1", roomLabels: ["Test Room"])
    let model = try result.captureModel(context: context)
    XCTAssertEqual(model.walls.count, 4)
    XCTAssertEqual(model.rooms[0].label, "Test Room")
    XCTAssertGreaterThanOrEqual(result.finishedAt, result.startedAt)
  }

  func testStepByStepPlaybackWithPause() async throws {
    let session = try ReplaySession(source: try source("box-room"), steps: 2, autoPlay: false)
    try await session.start(CaptureSessionConfiguration(mode: .room))
    var state = await session.state
    XCTAssertEqual(state, .running)
    let first = await session.advance()
    XCTAssertTrue(first)
    try await session.pause()
    state = await session.state
    XCTAssertEqual(state, .paused)
    let whilePaused = await session.advance()
    XCTAssertFalse(whilePaused, "a paused scan does not advance")
    try await session.resume()
    let second = await session.advance()
    XCTAssertTrue(second)
    let afterEnd = await session.advance()
    XCTAssertFalse(afterEnd)
    _ = try await session.finish()
  }

  func testCompassScriptRightAfterRunningThenItsReadingAndResult() async throws {
    let start = Date(timeIntervalSince1970: 1_792_245_500)
    let session = try ReplaySession(
      source: try source("box-room"), steps: 2, clock: { start },
      compass: ReplayCompass(
        reading: .init(heading: 212.4, accuracy: 8, source: .trueNorth), cameraBearing: 30))
    try await session.start(CaptureSessionConfiguration(mode: .room))
    let result = try await session.finish()
    let events = await collect(session)
    XCTAssertEqual(Array(events.prefix(2)), [.stateChanged(.running), .compass(.reading)])
    let compass = events.compactMap { event -> CompassLiveState? in
      if case .compass(let value) = event { return value }
      return nil
    }
    XCTAssertEqual(
      compass, [.reading, .result(.verified(heading: 212.4, accuracy: 8), cameraBearing: 30)])
    XCTAssertEqual(
      result.compass,
      .reading(
        heading: 212.4, accuracy: 8, source: .trueNorth,
        recordedAt: UTCTimestamp(start.addingTimeInterval(2))))
  }

  func testWithoutACompassScriptTheScanReadsNone() async throws {
    let session = try ReplaySession(source: try source("box-room"))
    try await session.start(CaptureSessionConfiguration(mode: .room))
    let result = try await session.finish()
    let events = await collect(session)
    XCTAssertFalse(events.contains { if case .compass = $0 { return true } else { return false } })
    XCTAssertEqual(result.compass, .none(issue: nil))
    XCTAssertEqual(result.compass.recorded, .none(issue: .unavailable), "what Finish floor records")
  }

  func testTrackingLostScript() async throws {
    let start = Date(timeIntervalSince1970: 1_792_245_500)
    let session = try ReplaySession(
      source: try source("box-room"), steps: 5, clock: { start }, trackingLost: 2...3)
    try await session.start(CaptureSessionConfiguration(mode: .room))
    _ = try await session.finish()
    let tracking = await collect(session).compactMap { event -> TrackingStatus? in
      if case .tracking(let value) = event { return value }
      return nil
    }
    XCTAssertEqual(tracking, [.lost(since: start), .normal])
  }

  func testStateErrors() async throws {
    let session = try ReplaySession(source: try source("box-room"))
    do {
      _ = try await session.finish()
      XCTFail("finish before start must fail")
    } catch {
      guard case .invalidState = error as? CaptureSessionError else { return XCTFail("\(error)") }
    }
    do {
      try await session.pause()
      XCTFail("pause before start must fail")
    } catch {}
    try await session.start(CaptureSessionConfiguration(mode: .room))
    do {
      try await session.start(CaptureSessionConfiguration(mode: .room))
      XCTFail("second start must fail")
    } catch {}
    do {
      try await session.resume()
      XCTFail("resume while running must fail")
    } catch {}
    _ = try await session.finish()
  }

  func testCancelEndsTheEventStreamWithoutAResult() async throws {
    let session = try ReplaySession(source: try source("box-room"), autoPlay: false)
    try await session.start(CaptureSessionConfiguration(mode: .room))
    await session.cancel()
    let events = await collect(session)
    XCTAssertEqual(events.last, .stateChanged(.idle))
  }

  func testEmptyScanFailsWithNoRoomsCaptured() async throws {
    let empty = ReplaySource(originals: RawOriginals(roomPlanJSON: Data(#"{"version":2,"walls":[],"doors":[],"windows":[],"openings":[],"floors":[],"objects":[]}"#.utf8)))
    let session = try ReplaySession(source: empty)
    try await session.start(CaptureSessionConfiguration(mode: .room))
    do {
      _ = try await session.finish()
      XCTFail("an empty scan must not finish")
    } catch {
      XCTAssertEqual(error as? CaptureSessionError, .noRoomsCaptured)
    }
  }

  func testUnreadableRecordingIsRefusedAtCreation() {
    XCTAssertThrowsError(try ReplaySession(source: ReplaySource(originals: RawOriginals(roomPlanJSON: Data("not json".utf8)))))
  }

  func testRecordingLoadsFromAGeneratedPackageFolder() throws {
    let folder = try Fixtures.load("two-room-apartment").captureDirectory()
    let loaded = try ReplaySource.load(directory: folder)
    XCTAssertFalse(loaded.originals.depthSamples.isEmpty)
    XCTAssertEqual(try RoomPlanDocument.decode(from: loaded.originals.roomPlanJSON).rooms.count, 2)
  }
}

final class DeviceGateTests: XCTestCase {
  private func capabilities(lidar: Bool = true, roomPlan: Bool = true, os: String = "26.0.1") -> DeviceCapabilities {
    DeviceCapabilities(
      model: "iPhone17,1", osName: .iOS, osVersion: os, supportsSceneReconstructionMesh: lidar,
      roomPlanSupported: roomPlan)
  }

  func testSupportedDevicePasses() {
    let result = DeviceGate.evaluate(capabilities())
    XCTAssertTrue(result.isSupported)
    XCTAssertNil(result.message)
  }

  func testDeviceWithoutLidarGetsAClearMessage() {
    let result = DeviceGate.evaluate(capabilities(lidar: false))
    XCTAssertEqual(result.failures, [.noLidar])
    XCTAssertTrue(try XCTUnwrap(result.message).contains("LiDAR"))
  }

  func testRoomPlanUnsupportedAndOldOS() {
    XCTAssertEqual(DeviceGate.evaluate(capabilities(roomPlan: false)).failures, [.roomPlanUnsupported])
    XCTAssertEqual(DeviceGate.evaluate(capabilities(os: "16.7")).failures, [.osTooOld(minimumMajor: 17)])
    XCTAssertEqual(
      DeviceGate.evaluate(capabilities(lidar: false, roomPlan: false, os: "16.0")).failures.count, 3)
  }
}
