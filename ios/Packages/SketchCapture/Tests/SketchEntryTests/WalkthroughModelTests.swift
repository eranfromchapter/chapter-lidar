import CaptureContract
import CaptureTestSupport
import Foundation
import SketchEntry
import SketchSolver
import Walkthrough
import WalkthroughUI
import XCTest

#if canImport(Observation)
  /// The AR walkthrough's guided steps (spec F15 2) with the replay session: the UI test's
  /// bedroom script (ios/App/Sources/App/Debug/UITestWalkthroughBedroom.json) walks one room
  /// with four corners, the closing tap, the ceiling, a door and a window into a log that
  /// validates against `walkthrough-log.schema.json`, converts and solves Complete; Undo,
  /// tracking, wall picking and "Tap each wall".
  @MainActor
  final class WalkthroughModelTests: XCTestCase {
    static let visitId = LowercaseUUID(rawValue: "7c4e1b9a-2d3f-4a68-9b5c-e0f1a2b3c4d5")!
    static let captureId = LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!

    static var bedroomScript: WalkthroughReplayScript {
      get throws {
        try WalkthroughReplayScript.load(
          from: Fixtures.repositoryRoot.appendingPathComponent(
            "ios/App/Sources/App/Debug/UITestWalkthroughBedroom.json"))
      }
    }

    /// A clock that moves one second per reading, shared by the session and the model.
    final class TestClock: @unchecked Sendable {
      var now = 1000.0
      func read() -> TimeInterval {
        now += 1
        return now
      }
    }

    func replay(_ script: WalkthroughReplayScript, clock: TestClock) -> ReplayWalkthroughSession {
      ReplayWalkthroughSession(script: script, clock: clock.read)
    }

    func model(
      _ session: any WalkthroughSession, clock: TestClock, units: DisplayUnitSystem = .imperial
    ) -> WalkthroughModel {
      WalkthroughModel(
        visitId: Self.visitId, captureId: Self.captureId, floorLabel: "Floor 1",
        areaKey: "floor-1", mode: .floor, displayUnits: units, session: session,
        clock: clock.read)
    }

    /// The replay's current point reaches the model (the session's stream, or directly).
    func show(_ session: ReplayWalkthroughSession, to model: WalkthroughModel) {
      if let update = session.currentUpdate() { model.receive(update) }
    }

    /// Taps + `count` times, the replay advancing after each tap.
    func tap(
      _ model: WalkthroughModel, _ session: ReplayWalkthroughSession, times count: Int = 1,
      file: StaticString = #filePath, line: UInt = #line
    ) {
      for _ in 0..<count {
        show(session, to: model)
        XCTAssertTrue(model.canTap, "+ enabled at \(model.step)", file: file, line: line)
        model.tap()
      }
    }

    func startBedroom(_ model: WalkthroughModel) {
      model.start()
      model.roomName = "Bedroom"
      model.roomType = .bedroom
      model.startRoom()
    }

    // MARK: The bedroom script

    func testTheBedroomScriptWalksOneRoomAndSolvesComplete() async throws {
      let clock = TestClock()
      let session = replay(try Self.bedroomScript, clock: clock)
      let model = model(session, clock: clock)
      XCTAssertEqual(model.step, .roomName)
      startBedroom(model)
      XCTAssertEqual(model.step, .corners)
      show(session, to: model)
      XCTAssertEqual(model.instruction, "Point at a floor corner and tap +")

      tap(model, session, times: 4)
      XCTAssertEqual(model.currentRoom?.corners?.count, 4)
      show(session, to: model)
      XCTAssertEqual(model.instruction, WalkthroughText.closeOnFirst, "the closing tap is near")
      tap(model, session)
      XCTAssertEqual(model.step, .ceiling, "the closing tap closed the room")
      XCTAssertNotNil(model.currentRoom?.closingTap)
      tap(model, session)
      XCTAssertEqual(model.step, .openings)
      XCTAssertEqual(model.currentRoom?.ceiling.first?.p.y ?? 0, 2.44, accuracy: 1e-9)

      model.addOpening(.door)
      XCTAssertEqual(model.step, .opening(.door, .leftJamb))
      tap(model, session, times: 3)
      model.addOpening(.window)
      XCTAssertEqual(model.step, .opening(.window, .leftJamb))
      tap(model, session, times: 2)
      XCTAssertEqual(model.step, .opening(.window, .sill))
      tap(model, session, times: 2)
      XCTAssertEqual(model.step, .openings)

      let room = try XCTUnwrap(model.rooms.first)
      XCTAssertEqual(room.openings.map(\.id), ["door-1", "window-1"])
      XCTAssertEqual(room.openings.map(\.wallIndex), [2, 0], "door in wall 3, window in wall 1")
      let window = room.openings[1]
      XCTAssertEqual(window.leftJamb.p.x, 1.5, accuracy: 1e-9)
      XCTAssertEqual(window.leftJamb.p.y, 1.5, accuracy: 1e-9)
      XCTAssertEqual(window.leftJamb.p.z, 0, accuracy: 1e-9, "on the plane of wall 1")
      XCTAssertEqual(window.sill?.p.y ?? 0, 0.9, accuracy: 1e-9)
      XCTAssertEqual(room.openings[0].head?.p.y ?? 0, 2.03, accuracy: 1e-9)

      // The live outline: four corners, closed, walls of 4 m and 3 m.
      let outline = try XCTUnwrap(model.outline.first)
      XCTAssertTrue(outline.isClosed)
      let lengths = WalkthroughModel.wallLengths(outline.corners, closed: true)
      XCTAssertEqual(lengths.count, 4)
      XCTAssertEqual(lengths[0], 4, accuracy: 1e-9)
      XCTAssertEqual(lengths[1], 3, accuracy: 1e-9)

      // Done: Check the scale lists the walls with their walked lengths.
      XCTAssertTrue(model.canFinishWalking)
      model.finishWalking()
      XCTAssertEqual(model.phase, .scale)
      XCTAssertEqual(model.scaleWalls.count, 4)
      let wall1 = try XCTUnwrap(model.scaleWalls.first)
      XCTAssertEqual(wall1.id, "room-1.0")
      XCTAssertEqual(wall1.walkedMm, 4000, accuracy: 40)
      XCTAssertTrue(wall1.title(units: .imperial).hasPrefix("Bedroom · wall 1 · 13' "), wall1.title(units: .imperial))
      XCTAssertTrue(wall1.title(units: .imperial).hasSuffix(" walked"))
      XCTAssertFalse(model.canApplyScale)
      model.scaleWallId = wall1.id
      model.tape = SketchLengthField(text: "13' 1.5\"", unit: .ftIn)
      XCTAssertTrue(model.canApplyScale)
      model.applyScale()
      XCTAssertEqual(model.phase, .check)
      XCTAssertNil(model.solveError)
      XCTAssertEqual(model.completenessWord, "Complete")
      XCTAssertEqual(model.conversion?.summary.scaleSource, .tape)
      XCTAssertNotNil(model.scaleText)
      XCTAssertTrue(model.canFinish)

      // Finish floor: the final log, with the replay's frames, converted again.
      let finished = try await model.finish()
      XCTAssertEqual(finished.log.rooms.count, 1)
      XCTAssertEqual(finished.log.scaleCheck?.tape.valueMm ?? 0, 4000.5, accuracy: 1e-9)
      XCTAssertNil(finished.log.video, "the replay records no video")
      XCTAssertNil(finished.videoURL)
      XCTAssertFalse(finished.log.frames.isEmpty)
      XCTAssertEqual(finished.conversion.measurements.source.kind, .arWalkthrough)
      XCTAssertEqual(
        finished.conversion.measurements.source.path,
        "Original Exports/floor-1/\(Self.captureId.rawValue)/walkthrough-log.json")
      XCTAssertFalse(finished.conversion.summary.recorded)
      XCTAssertFalse(finished.result.isLimited)
      XCTAssertEqual(finished.result.model.rooms.first?.label, "Bedroom")
      XCTAssertEqual(finished.result.model.doors.count, 1)
      XCTAssertEqual(finished.result.model.windows.count, 1)

      // The log validates against the schema.
      let data = try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(finished.log)
      let validator = try SchemaValidator(
        schemaURL: Fixtures.schemaURL("walkthrough-log.schema.json"))
      XCTAssertEqual(try validator.validate(jsonData: data), [])
    }

    // MARK: Undo

    func testUndoRemovesTheLastTapAndReopensTheRoom() throws {
      let clock = TestClock()
      let session = replay(try Self.bedroomScript, clock: clock)
      let model = model(session, clock: clock)
      XCTAssertFalse(model.canUndo)
      startBedroom(model)
      tap(model, session, times: 2)
      XCTAssertEqual(model.currentRoom?.corners?.count, 2)
      model.undo()
      XCTAssertEqual(model.currentRoom?.corners?.count, 1)
      // The replay goes on with its script: corners 3 and 4, then the closing tap.
      tap(model, session, times: 3)
      XCTAssertEqual(model.step, .ceiling)
      model.undo()
      XCTAssertEqual(model.step, .corners, "Undo takes the closing tap back")
      XCTAssertNil(model.currentRoom?.closingTap)
      XCTAssertEqual(model.currentRoom?.corners?.count, 3)
    }

    // MARK: Tracking and targets

    func testTheTapNeedsNormalTrackingAndAPoint() throws {
      let clock = TestClock()
      let session = replay(try Self.bedroomScript, clock: clock)
      let model = model(session, clock: clock)
      startBedroom(model)
      XCTAssertFalse(model.canTap)
      XCTAssertEqual(model.trackingMessage, WalkthroughText.starting)
      let base = try XCTUnwrap(session.currentUpdate())

      var limited = base
      limited.tracking = .limited
      limited.trackingReason = .excessiveMotion
      model.receive(limited)
      XCTAssertFalse(model.canTap)
      XCTAssertEqual(model.trackingMessage, "Move slower")
      limited.trackingReason = .insufficientFeatures
      model.receive(limited)
      XCTAssertEqual(model.trackingMessage, "More light")

      var noFloor = base
      noFloor.floorHit = nil
      model.receive(noFloor)
      XCTAssertFalse(model.canTap)
      XCTAssertEqual(model.trackingMessage, "Point at the floor")

      model.receive(base)
      XCTAssertTrue(model.canTap)
      XCTAssertNil(model.trackingMessage)
      model.tap()
      XCTAssertFalse(model.canTap, "no second tap until the next frame")
    }

    /// The ceiling and window points are where the centre ray meets the wall it reaches first
    /// within that wall's extent; a ray that meets no wall gives no point.
    func testWallPointsAreOnTheFirstWallTheRayMeets() throws {
      let clock = TestClock()
      let session = replay(try Self.bedroomScript, clock: clock)
      let model = model(session, clock: clock)
      startBedroom(model)
      tap(model, session, times: 5)
      XCTAssertEqual(model.step, .ceiling)
      show(session, to: model)
      let target = try XCTUnwrap(model.target)
      XCTAssertEqual(target.x, 2.0, accuracy: 1e-9)
      XCTAssertEqual(target.y, 2.44, accuracy: 1e-9)
      XCTAssertEqual(target.z, -3.0, accuracy: 1e-9)

      // Looking up through the ceiling meets no wall.
      var up = try XCTUnwrap(session.currentUpdate())
      up.rayDirection = Vec3(x: 0, y: 1, z: 0)
      model.receive(up)
      XCTAssertNil(model.target)
      XCTAssertEqual(model.trackingMessage, WalkthroughText.pointAtWall)

      // Looking at a corner from inside: the nearer wall wins.
      var corner = up
      corner.rayDirection = Vec3(x: 0.6, y: 0, z: -0.8)  // towards wall 3 (z = −3) before x = 4
      model.receive(corner)
      let hit = try XCTUnwrap(model.target)
      XCTAssertEqual(hit.z, -3.0, accuracy: 1e-9)
      XCTAssertEqual(hit.x, 2.0 + 0.6 * 1.5 / 0.8, accuracy: 1e-9)
    }

    // MARK: Tap each wall

    func testTapEachWallClosesFromTheWallLines() async throws {
      // Two points along the base of each wall of the 4 × 3 m room, kept clear of the corners.
      let points: [Vec3] = [
        Vec3(x: 0.5, y: 0, z: 0), Vec3(x: 3.5, y: 0, z: 0),
        Vec3(x: 4, y: 0, z: -0.5), Vec3(x: 4, y: 0, z: -2.5),
        Vec3(x: 3.5, y: 0, z: -3), Vec3(x: 0.5, y: 0, z: -3),
        Vec3(x: 0, y: 0, z: -2.5), Vec3(x: 0, y: 0, z: -0.5),
        Vec3(x: 2, y: 2.5, z: -3),
      ]
      let script = WalkthroughReplayScript(
        floorY: 0, eye: Vec3(x: 2, y: 1.5, z: -1.5),
        points: points.map { WalkthroughReplayScript.Point(target: $0) })
      let clock = TestClock()
      let session = replay(script, clock: clock)
      let model = model(session, clock: clock, units: .metric)
      model.start()
      model.roomName = "Closet"
      model.roomMethod = .walls
      model.startRoom()
      XCTAssertEqual(model.step, .walls)
      tap(model, session, times: 5)
      XCTAssertFalse(model.canCloseWalls, "two walls and a half")
      tap(model, session)
      XCTAssertTrue(model.canCloseWalls, "three walls can close")
      tap(model, session, times: 2)
      XCTAssertTrue(model.canCloseWalls)
      model.closeWalls()
      XCTAssertEqual(model.step, .ceiling)
      let outline = try XCTUnwrap(model.outline.first)
      XCTAssertEqual(outline.corners.count, 4)
      let lengths = WalkthroughModel.wallLengths(outline.corners, closed: true)
      XCTAssertEqual(lengths.reduce(0, +), 14, accuracy: 1e-6)
      tap(model, session)
      model.finishWalking()
      model.skipScale()
      XCTAssertNil(model.solveError)
      XCTAssertEqual(model.conversion?.summary.scaleSource, .ar)
      let finished = try await model.finish()
      XCTAssertEqual(finished.result.model.rooms.count, 1)
      XCTAssertEqual(finished.log.rooms.first?.walls?.count, 4)
    }

    /// The second room may use the first room's ceiling instead of a tap (the converter gives
    /// a room without ceiling taps the ceiling of the room before it).
    func testTheNextRoomCanUseTheSameCeiling() throws {
      let clock = TestClock()
      let session = replay(try Self.bedroomScript, clock: clock)
      let model = model(session, clock: clock)
      startBedroom(model)
      tap(model, session, times: 6)
      XCTAssertEqual(model.step, .openings)
      XCTAssertNil(model.sameCeilingRoom)
      model.nextRoom()
      XCTAssertEqual(model.step, .roomName)
      XCTAssertTrue(model.canFinishWalking, "Done on the card of a room not started")
      model.undo()
      XCTAssertEqual(model.step, .openings, "Undo goes back to the room before")
    }
  }

  /// How do you want to measure? (spec F15 2, F16 2).
  @MainActor
  final class MeasureMethodTests: XCTestCase {
    func testPhotographingASketchIsTheDefault() {
      let model = MeasureMethodModel(canWalk: true)
      XCTAssertEqual(model.method, .photo)
      XCTAssertEqual(MeasureMethod.allCases, [.photo, .walk, .sketch], "the screen's order")
      XCTAssertEqual(model.continueTitle, "Photograph the sketch")
      XCTAssertTrue(model.asksFloor)
      model.choose(.walk)
      XCTAssertEqual(model.continueTitle, "Walk the rooms")
      model.choose(.sketch)
      XCTAssertEqual(model.continueTitle, "Continue")
      XCTAssertFalse(model.asksFloor)
    }

    func testAPhoneThatCannotTrackPhotographsOrEntersASketch() {
      let model = MeasureMethodModel(canWalk: false)
      XCTAssertEqual(model.method, .photo)
      XCTAssertTrue(model.canContinue)
      model.choose(.walk)
      XCTAssertEqual(model.method, .photo)
      model.choose(.sketch)
      XCTAssertEqual(model.method, .sketch)
      XCTAssertTrue(model.canContinue)
    }

    func testThePhotoAndTheWalkNeedAFreeFloorName() {
      let model = MeasureMethodModel(canWalk: true, existingAreaKeys: ["floor-1"])
      XCTAssertEqual(model.continueTitle, "Floor 1 is already captured. Use another name")
      model.floorLabel = "Floor 2"
      XCTAssertTrue(model.canContinue)
      model.floorLabel = "  "
      XCTAssertEqual(model.continueTitle, "Enter the floor or area")
      model.floorLabel = "Basement"
      model.mode = nil
      XCTAssertEqual(model.continueTitle, "Choose what the sketch shows")
      model.choose(.walk)
      XCTAssertEqual(model.continueTitle, "Choose what you are walking")
    }
  }

  /// Finish floor's files (spec F15 2): the log, the measurements and the video.
  final class WalkthroughFloorWriterTests: XCTestCase {
    func testTheOriginalsAreWrittenOnceWithTheVideoMoved() throws {
      let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("walkthrough-writer-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: root) }
      let folder = root.appendingPathComponent("capture", isDirectory: true)
      let video = root.appendingPathComponent("recording.mp4")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try Data([0, 0, 0, 24]).write(to: video)
      let visit = LowercaseUUID()
      let capture = LowercaseUUID()
      let log = WalkthroughLog(
        visitId: visit, captureId: capture, areaKey: "floor-1", startedAt: .now(),
        finishedAt: .now(), floorY: 0, rooms: [])
      let measurements = SketchMeasurements(
        visitId: visit, captureId: capture, areaKey: "floor-1", displayUnits: .metric,
        source: SketchMeasurements.Source(kind: .arWalkthrough, path: "x"), rooms: [])
      let written = try WalkthroughFloorWriter.write(
        log: log, measurements: measurements, video: video, to: folder)
      XCTAssertEqual(
        written.map(\.fileName), ["walkthrough.mp4", "walkthrough-log.json", "sketch-measurements.json"])
      XCTAssertFalse(FileManager.default.fileExists(atPath: video.path), "moved")
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("walkthrough.mp4").path))
      XCTAssertThrowsError(
        try WalkthroughFloorWriter.write(log: log, measurements: measurements, video: nil, to: folder)
      ) { error in
        XCTAssertEqual(error as? SketchFloorWriterError, .alreadyWritten("walkthrough-log.json"))
      }
      XCTAssertEqual(
        WalkthroughFloorWriter.videoPackagePath(areaKey: "floor-1", captureId: capture),
        "Original Exports/floor-1/\(capture.rawValue)/walkthrough.mp4")
    }
  }
#endif
