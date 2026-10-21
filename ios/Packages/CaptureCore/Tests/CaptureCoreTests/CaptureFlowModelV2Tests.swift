import CaptureContract
import CaptureCore
import CaptureTestSupport
import Foundation
import XCTest

#if canImport(Observation)
  /// The v2 behaviour of the capture flow: phone-capture §10.1 T-F1…T-F8 and compass §13.1
  /// `CaptureFlowModelTests` (with `ReplaySession` and `FakeCompass`).
  extension CaptureFlowModelTests {
    private struct FailingProvider: HubProjectProvider {
      struct Failure: Error, LocalizedError {
        var errorDescription: String? { "The station answered 503." }
      }
      let error: Error
      func projects() async throws -> [HubProjectSummary] { throw error }
      func listing() async throws -> HubProjectListing { throw error }
    }

    /// Waits for the event task to deliver what the session emitted.
    private func settle(_ condition: () -> Bool) async {
      for _ in 0..<500 where !condition() {
        await Task.yield()
      }
    }

    // MARK: T-F1 Continue

    func testContinueBlockers() async throws {
      XCTAssertEqual(try makeModel(lidar: false).continueBlocker, "This phone cannot scan")

      let model = try makeModel()
      await model.loadProjects()
      XCTAssertEqual(model.continueBlocker, "Choose a HUB project to continue")
      XCTAssertEqual(model.continueTitle, "Choose a HUB project to continue")
      model.choose(project)
      XCTAssertEqual(model.continueBlocker, "Confirm the address to continue")
      model.setAddressConfirmed(true)
      XCTAssertNil(model.continueBlocker)
      XCTAssertEqual(model.continueTitle, "Continue")

      let offline = try makeModel(
        provider: StaticHubProjectProvider([project], fetchedAt: Self.now, isOfflineCopy: true))
      await offline.loadProjects()
      offline.choose(project)
      offline.setAddressConfirmed(true)
      XCTAssertNil(offline.continueBlocker)
      XCTAssertEqual(offline.continueTitle, "Continue offline")

      let nothingSaved = try makeModel(
        provider: FailingProvider(error: HubProjectListingError.offlineWithoutSavedList))
      await nothingSaved.loadProjects()
      XCTAssertTrue(nothingSaved.isOfflineWithoutList)
      XCTAssertEqual(nothingSaved.continueBlocker, "Connect to load projects")
      XCTAssertEqual(
        nothingSaved.offlineBanner,
        "No connection and no projects saved on this phone. Connect once to load the HUB projects.")
    }

    func testAProjectListErrorIsShown() async throws {
      let model = try makeModel(provider: FailingProvider(error: FailingProvider.Failure()))
      await model.loadProjects()
      XCTAssertEqual(model.projectsError, "Could not load HUB projects: The station answered 503.")
      XCTAssertNil(model.offlineBanner)
      XCTAssertEqual(model.projects, [])
    }

    func testProjectRowAndRecordedRows() async throws {
      let model = try makeModel()
      XCTAssertEqual(model.projectRowTitle, "Choose a HUB project")
      XCTAssertEqual(model.projectRowSubtitle, "Projects come from the HUB")
      var updated = project
      updated.updatedAt = Self.now.addingTimeInterval(-120)
      model.choose(updated)
      XCTAssertEqual(model.projectRowTitle, "Fixture project")
      XCTAssertEqual(model.projectRowSubtitle, "Deal fixture-deal-0001 · from the HUB, updated 2 min ago")
      var unnamed = project
      unnamed.projectName = " "
      model.choose(unnamed)
      XCTAssertEqual(model.projectRowTitle, project.address, "R-29: the address without a name")
      XCTAssertEqual(model.projectRowSubtitle, "Deal fixture-deal-0001 · from the HUB")

      XCTAssertEqual(model.deviceText, "iPhone17,1 · LiDAR", "the identifier without a name")
      model.draft.device.marketingName = "iPhone 16 Pro"
      XCTAssertEqual(model.deviceText, "iPhone 16 Pro · LiDAR")
      XCTAssertEqual(try makeModel(lidar: false).deviceText, "iPhone17,1 · no LiDAR")
      XCTAssertEqual(model.appText, "1.0.0 (1)")
    }

    // MARK: T-F2 Start scan

    func testStartScanBlockers() throws {
      XCTAssertEqual(try makeModel(lidar: false).startScanBlocker, "This phone cannot scan")

      let model = try makeModel(existingAreaKeys: ["floor-1"])
      model.choose(project)
      model.setAddressConfirmed(true)
      XCTAssertEqual(model.draft.floorLabel, "Floor 2", "the next free name")
      model.draft.floorLabel = "  "
      XCTAssertEqual(model.startScanBlocker, "Enter the floor or area")
      model.draft.floorLabel = "—!"
      XCTAssertEqual(model.startScanBlocker, "Use letters or numbers in the name")
      model.draft.floorLabel = "Floor 1"
      XCTAssertEqual(model.startScanBlocker, "Floor 1 is already captured. Use another name")
      model.draft.floorLabel = "floor  1!"
      XCTAssertEqual(
        model.startScanBlocker, "floor  1! is already captured. Use another name",
        "the same area key")
      model.draft.floorLabel = "Floor 2"
      XCTAssertEqual(model.startScanBlocker, "Choose what you are scanning")
      model.draft.mode = .floor
      model.draft.coverageNotes = String(repeating: "x", count: 2001)
      XCTAssertEqual(
        model.startScanBlocker, "Coverage notes are too long (2000 characters at most)",
        "another validation error, without its final period")
      model.draft.coverageNotes = ""
      XCTAssertNil(model.startScanBlocker)
      XCTAssertEqual(model.startScanTitle, "Start scan")
      XCTAssertEqual(model.scanSetupCaption, "Fixture project", "adding a floor")
      XCTAssertEqual(try makeModel().scanSetupCaption, "Step 2 of 3")
    }

    func testADuplicateNameDoesNotStartTheScan() async throws {
      let made = MadeSessions()
      let model = try makeModel(made: made, existingAreaKeys: ["floor-1"])
      model.choose(project)
      model.setAddressConfirmed(true)
      model.draft.mode = .floor
      model.draft.floorLabel = "Floor 1"
      await model.startScan()
      XCTAssertEqual(made.count, 0)
      XCTAssertEqual(model.errorMessage, "Floor 1 is already captured. Use another name.")
      XCTAssertNotEqual(model.step, .scanning)
    }

    // MARK: T-F3 Floor name

    func testSuggestedFloorName() throws {
      XCTAssertEqual(CaptureFlowModel.suggestedFloorName(existing: []), "Floor 1")
      XCTAssertEqual(CaptureFlowModel.suggestedFloorName(existing: ["floor-1"]), "Floor 2")
      XCTAssertEqual(
        CaptureFlowModel.suggestedFloorName(existing: ["floor-1", "floor-2", "floor-3"]), "Floor 4")
      XCTAssertEqual(CaptureFlowModel.suggestedFloorName(existing: ["floor-2"]), "Floor 3")
      XCTAssertEqual(CaptureFlowModel.suggestedFloorName(existing: ["basement"]), "Floor 2")

      let model = try makeModel()
      XCTAssertEqual(model.draft.floorLabel, "Floor 1")
      model.existingAreaKeys = ["floor-1"]
      XCTAssertEqual(model.draft.floorLabel, "Floor 2", "the suggestion follows the visit")
      model.draft.floorLabel = "Basement"
      model.existingAreaKeys = ["floor-1", "floor-2"]
      XCTAssertEqual(model.draft.floorLabel, "Basement", "a typed name is kept")
    }

    // MARK: T-F4 Address

    func testAddressToggleOffAsksForTheAlert() throws {
      let model = try makeModel()
      model.choose(project)
      XCTAssertFalse(model.addressToggleChanged(isOn: true))
      XCTAssertEqual(model.draft.addressConfirmedAt, UTCTimestamp(Self.now))
      XCTAssertTrue(model.addressToggleChanged(isOn: false))
      XCTAssertNil(model.draft.addressConfirmedAt)
      XCTAssertFalse(model.addressToggleChanged(isOn: false), "already off")
    }

    func testProjectManagerCall() {
      var withPhone = project
      withPhone.projectManagerPhone = "+1 (212) 555-0142"
      XCTAssertEqual(withPhone.projectManagerCallURL?.absoluteString, "tel:+12125550142")
      XCTAssertNil(project.projectManagerCallURL, "no phone: the call is hidden")
      withPhone.projectManagerPhone = "ask the office"
      XCTAssertNil(withPhone.projectManagerCallURL)
    }

    // MARK: T-F5, T-F6 The compass reading of the scan

    private func finishedRecord(_ model: CaptureFlowModel) async throws -> CaptureRecord {
      await model.startScan()
      await settle { model.canFinishFloor }
      await model.finishFloor()
      XCTAssertNil(model.errorMessage)
      let record = try XCTUnwrap(model.result).record
      let schema = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-record.schema.json"))
      XCTAssertEqual(
        schema.validate(try JSON.parse(CaptureContractJSON.makeEncoder().encode(record))), [])
      return record
    }

    func testCompassReadingAttachedAtFinish() async throws {
      let compass = FakeCompass(.verified, clock: { Self.now })
      let model = try modelReadyToScan(compass: compass, replayCompass: compass.replayCompass)
      let capture = try await finishedRecord(model).captures[0]
      XCTAssertEqual(capture.heading, 212.4)
      XCTAssertEqual(capture.headingAccuracy, 8)
      XCTAssertEqual(capture.headingSource, .trueNorth)
      XCTAssertEqual(capture.headingRecordedAt, UTCTimestamp(Self.now.addingTimeInterval(2)))
      XCTAssertNil(capture.headingIssue)
      XCTAssertEqual(CompassState(capture), .verified(heading: 212.4, accuracy: 8))
    }

    func testARejectedReadingRecordsTheIssue() async throws {
      let model = try modelReadyToScan(
        replayCompass: ReplayCompass(reading: nil, issue: .rejected))
      let capture = try await finishedRecord(model).captures[0]
      XCTAssertNil(capture.heading)
      XCTAssertEqual(capture.headingIssue, .rejected)
      XCTAssertEqual(CompassState(capture), .notVerified(.rejected, accuracy: nil))
    }

    func testNoReadingRecordsNothing() async throws {
      let model = try modelReadyToScan()
      let capture = try await finishedRecord(model).captures[0]
      XCTAssertNil(capture.heading)
      XCTAssertNil(capture.headingAccuracy)
      XCTAssertNil(capture.headingSource)
      XCTAssertNil(capture.headingRecordedAt)
      XCTAssertNil(capture.headingIssue)
      XCTAssertEqual(CompassState(capture), .notVerified(.noReading, accuracy: nil))
    }

    func testTheStep2ReadingIsNotRecorded() async throws {
      let compass = FakeCompass(.verified, clock: { Self.now })
      let model = try modelReadyToScan(
        compass: compass,
        replayCompass: ReplayCompass(reading: .init(heading: 100, accuracy: 6, source: .trueNorth)))
      await model.readCompassAgain()
      XCTAssertEqual(
        model.compassPrecheck,
        .result(heading: 212.4, accuracy: 8, source: .trueNorth, readAt: Self.now))
      let capture = try await finishedRecord(model).captures[0]
      XCTAssertEqual(capture.heading, 100, "the scan's own reading, not the pre-check")
    }

    func testTheChipFollowsTheScan() async throws {
      let compass = FakeCompass(.approximate)
      let model = try modelReadyToScan(compass: compass, replayCompass: compass.replayCompass)
      XCTAssertEqual(model.liveCompass, .reading)
      await model.startScan()
      await settle { model.liveCompass != .reading }
      XCTAssertEqual(
        CompassPhoneText.chip(model.liveCompass).text, "N · magnetic · ±12°")
    }

    func testANoneScanShowsNotVerified() async throws {
      let model = try modelReadyToScan(replayCompass: FakeCompass(.none).replayCompass)
      await model.startScan()
      await settle { model.liveCompass != .reading }
      XCTAssertEqual(CompassPhoneText.chip(model.liveCompass).text, "N · not verified")
    }

    func testTryAgainDiscardsTheReading() async throws {
      var sessions: [FailingSession] = []
      let compass = FakeCompass(.verified)
      var first = true
      let source = try replaySource()
      let model = try modelReadyToScan(
        factory: {
          if first {
            first = false
            let failing = FailingSession(failure: .tooHot)
            sessions.append(failing)
            return failing
          }
          return try ReplaySession(source: source, autoPlay: false, compass: compass.replayCompass)
        })
      await model.startScan()
      await settle { model.scanFailed }
      XCTAssertEqual(model.livePhase, .stopped(CaptureSessionError.tooHot.description))
      XCTAssertEqual(model.recordingStatus.text, "Recording stopped")
      await model.retryScan()
      XCTAssertEqual(model.liveCompass, .reading, "the new session reads the compass again")
      XCTAssertEqual(sessions.count, 1)
    }

    // MARK: Pre-check

    func testThePrecheckRunsAndAsksForLocationOnce() async throws {
      let compass = FakeCompass(.verified, authorization: .notDetermined, clock: { Self.now })
      let model = try makeModel(compass: compass)
      XCTAssertEqual(model.compassPrecheck, .reading)
      await model.readCompassAgain()
      XCTAssertEqual(compass.authorizationRequests, 1)
      XCTAssertEqual(model.locationAuthorization, .authorized)
      XCTAssertEqual(
        model.compassPrecheck,
        .result(heading: 212.4, accuracy: 8, source: .trueNorth, readAt: Self.now))
      await model.readCompassAgain()
      XCTAssertEqual(compass.authorizationRequests, 1, "asked only once")
      XCTAssertEqual(compass.precheckCount, 2)
    }

    func testPrecheckWithoutACompass() async throws {
      let none = try makeModel()
      await none.readCompassAgain()
      XCTAssertEqual(none.compassPrecheck, .unavailable)

      let unavailable = try makeModel(compass: FakeCompass(.verified, isAvailable: false))
      await unavailable.readCompassAgain()
      XCTAssertEqual(unavailable.compassPrecheck, .unavailable)
      XCTAssertFalse(CompassPhoneText.row(unavailable.compassPrecheck, now: Self.now).showsReadAgain)
    }

    func testLocationOffAndSettings() async throws {
      let compass = FakeCompass(.approximate, authorization: .denied)
      let model = try makeModel(compass: compass)
      await model.readCompassAgain()
      XCTAssertTrue(model.isLocationOff)
      XCTAssertEqual(compass.authorizationRequests, 0, "never asked once denied")
      model.openLocationSettings()
      XCTAssertEqual(compass.settingsOpened, 1)
    }

    func testANewerReadAgainWins() async throws {
      let compass = FakeCompass(.verified, precheckDuration: .milliseconds(200), clock: { Self.now })
      let model = try makeModel(compass: compass)
      let first = Task { await model.readCompassAgain() }
      await settle { compass.precheckCount == 1 }
      first.cancel()
      await first.value
      XCTAssertEqual(model.compassPrecheck, .reading, "a cancelled pre-check leaves the row reading")
      await model.readCompassAgain()
      XCTAssertEqual(
        model.compassPrecheck,
        .result(heading: 212.4, accuracy: 8, source: .trueNorth, readAt: Self.now))
    }

    // MARK: T-F7 Tracking lost, pause, restart

    func testTrackingLostEventsAndRestart() async throws {
      let made = MadeSessions()
      let model = try modelReadyToScan(made: made, trackingLost: 2...3, autoPlay: false)
      await model.startScan()
      let session = try XCTUnwrap(made.last)
      XCTAssertFalse(model.canFinishFloor, "no wall yet: Finish floor is disabled")
      await session.advance()
      await session.advance()
      await settle { model.tracking.isLost }
      XCTAssertEqual(model.tracking, .lost(since: Self.now))
      XCTAssertEqual(model.livePhase, .trackingLost)
      XCTAssertFalse(model.canTogglePause, "Pause is disabled while tracking is lost")
      XCTAssertEqual(model.pausedText(now: Self.now.addingTimeInterval(6)), "Paused · 00:06")
      XCTAssertEqual(
        model.recordingStatus.text,
        "Recording paused · \(CaptureText.plural(model.progress.counts.walls, "wall", "walls")) kept")
      await session.advance()
      await session.advance()
      await settle { !model.tracking.isLost }
      XCTAssertEqual(model.livePhase, .scanning)
      XCTAssertTrue(model.canFinishFloor)

      await model.restartFloor()
      XCTAssertEqual(made.count, 2, "a new session")
      XCTAssertEqual(model.progress.counts.walls, 0, "the counts start again")
      XCTAssertEqual(model.tracking, .normal)
      XCTAssertEqual(model.step, .scanning)
    }

    func testPausedTextsAndRecordingLines() async throws {
      let model = try modelReadyToScan()
      XCTAssertFalse(model.canFinishFloor)
      await model.startScan()
      await settle { model.progress.counts.walls == 4 }
      XCTAssertEqual(model.recordingStatus.text, "Recording LiDAR depth and mesh · saved on this phone")
      XCTAssertNil(model.recordingStatus.dot)
      XCTAssertNil(model.pausedText(now: Self.now))
      await model.togglePause()
      XCTAssertEqual(model.livePhase, .paused)
      XCTAssertEqual(model.pausedText(now: Self.now.addingTimeInterval(12)), "Paused · 00:12")
      XCTAssertEqual(model.recordingStatus.text, "Recording paused · 4 walls kept")
      XCTAssertEqual(model.recordingStatus.dot, .partly)
      XCTAssertTrue(model.canTogglePause, "Resume")
      await model.togglePause()
      XCTAssertNil(model.pausedAt)
    }

    func testNothingCapturedShowsTheStoppedCard() async throws {
      let model = try modelReadyToScan(factory: { FailingSession() })
      await model.startScan()
      await model.finishFloor()
      XCTAssertEqual(
        model.livePhase,
        .stopped("Nothing was captured. Scan at least one wall before finishing."))
      XCTAssertNil(model.result)
    }

    // MARK: T-F8 Offline

    func testOfflineListing() async throws {
      let saved = Date(timeIntervalSince1970: 1_792_519_920)  // Oct 20, 2026 14:12 New York
      let twelve = (1...12).map {
        HubProjectSummary(dealId: "deal-\($0)", projectName: "Project \($0)", address: "\($0) Main St")
      }
      let model = try makeModel(
        provider: StaticHubProjectProvider(twelve, fetchedAt: saved, isOfflineCopy: true))
      await model.loadProjects()
      XCTAssertTrue(model.isOffline)
      XCTAssertEqual(model.projects.count, 12)
      XCTAssertEqual(
        model.offlineBanner,
        "No connection. Showing the 12 projects saved on this phone (updated Oct 20, 14:12). You "
          + "can scan offline; the upload waits for a connection.")
      model.choose(twelve[0])
      XCTAssertEqual(model.projectRowSubtitle, "Deal deal-1 · saved on this phone")

      let one = try makeModel(
        provider: StaticHubProjectProvider([project], fetchedAt: saved, isOfflineCopy: true))
      await one.loadProjects()
      XCTAssertTrue(try XCTUnwrap(one.offlineBanner).hasPrefix(
        "No connection. Showing the 1 project saved on this phone (updated "))

      let online = try makeModel()
      await online.loadProjects()
      XCTAssertNil(online.offlineBanner)
    }
  }
#endif
