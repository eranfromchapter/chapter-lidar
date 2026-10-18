import CaptureContract
import CaptureCore
import CaptureTestSupport
import Foundation
import XCTest

#if canImport(Observation)
  import Observation

  @MainActor
  final class CaptureFlowModelTests: XCTestCase {
    private let project = HubProjectSummary(
      dealId: "fixture-deal-0001", projectName: "Fixture project",
      address: "100 Example Street, Testville, NY 00000", updatedAt: nil)

    private func temporaryDirectory() -> URL {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("FlowTests-\(UUID().uuidString)")
      addTeardownBlock { try? FileManager.default.removeItem(at: url) }
      return url
    }

    /// Holds the session the factory made without keeping it alive.
    private final class MadeSessions {
      weak var last: ReplaySession?
      var count = 0
    }

    private func makeModel(
      lidar: Bool = true, fixture: String = "box-room", made: MadeSessions? = nil,
      onFinished: @escaping @MainActor (CaptureFlowResult) -> Void = { _ in }
    ) throws -> CaptureFlowModel {
      let fixtureData = try Fixtures.load(fixture)
      let source = ReplaySource(
        originals: RawOriginals(
          roomPlanJSON: try fixtureData.roomPlanData(),
          depthSamples: try DepthSamplesCodec.decode(fixtureData.depthSamplesData())))
      let draft = CaptureRecordDraft(
        operatorName: "Test Operator",
        device: DeviceInfo(model: "iPhone17,1", osName: .iOS, osVersion: "26.0.1", hasLidar: lidar),
        app: CaptureRecord.AppInfo(version: "1.0.0", build: "1"))
      return CaptureFlowModel(
        draft: draft,
        capabilities: DeviceCapabilities(
          model: "iPhone17,1", osName: .iOS, osVersion: "26.0.1", supportsSceneReconstructionMesh: lidar,
          roomPlanSupported: true),
        projectProvider: StaticHubProjectProvider([project]), originalsRoot: temporaryDirectory(),
        makeSession: { _ in
          let session = try ReplaySession(source: source)
          made?.last = session
          made?.count += 1
          return session
        },
        clock: { Date(timeIntervalSince1970: 1_792_245_500) }, onFinished: onFinished)
    }

    func testContinueNeedsAProjectAndAConfirmedAddress() async throws {
      let model = try makeModel()
      XCTAssertFalse(model.canContinueToSetup)
      await model.loadProjects()
      XCTAssertEqual(model.projects, [project])
      model.choose(project)
      XCTAssertFalse(model.canContinueToSetup, "address not confirmed yet")
      model.continueToSetup()
      XCTAssertEqual(model.step, .newCapture)
      model.setAddressConfirmed(true)
      XCTAssertTrue(model.canContinueToSetup)
      model.continueToSetup()
      XCTAssertEqual(model.step, .scanSetup)
      model.back()
      XCTAssertEqual(model.step, .newCapture)
    }

    func testStartScanIsRefusedWithoutFloorLabelAndMode() async throws {
      let model = try makeModel()
      model.choose(project)
      model.setAddressConfirmed(true)
      model.continueToSetup()
      XCTAssertFalse(model.canStartScan)
      await model.startScan()
      XCTAssertEqual(model.step, .scanSetup)
      XCTAssertNotNil(model.errorMessage)
      model.draft.floorLabel = "Floor 1"
      XCTAssertFalse(model.canStartScan, "mode still missing")
      model.draft.mode = .floor
      XCTAssertTrue(model.canStartScan)
    }

    func testDeviceWithoutLidarCannotContinue() async throws {
      let model = try makeModel(lidar: false)
      model.choose(project)
      model.setAddressConfirmed(true)
      XCTAssertFalse(model.gate.isSupported)
      XCTAssertTrue(try XCTUnwrap(model.gate.message).contains("LiDAR"))
      XCTAssertFalse(model.canContinueToSetup)
      XCTAssertFalse(model.hasLidar)
    }

    func testFullFlowWritesOriginalsAndMapsTheModel() async throws {
      var delivered: CaptureFlowResult?
      let model = try makeModel { delivered = $0 }
      model.choose(project)
      model.setAddressConfirmed(true)
      model.continueToSetup()
      model.draft.floorLabel = "Floor 1"
      model.draft.mode = .floor
      model.draft.coverageNotes = "Furniture covers the south wall."
      model.addOmittedRoom(name: "Primary closet", reason: "locked")
      XCTAssertEqual(model.draft.omittedRooms, [CaptureRecord.RoomNote(name: "Primary closet", reason: "locked")])

      await model.startScan()
      XCTAssertEqual(model.step, .scanning)
      XCTAssertNil(model.errorMessage)
      XCTAssertEqual(model.scanTitle, "Floor 1 · Whole floor")

      await model.togglePause()
      XCTAssertTrue(model.isPaused)
      await model.togglePause()
      XCTAssertFalse(model.isPaused)

      await model.finishFloor()
      XCTAssertNil(model.errorMessage)
      XCTAssertEqual(model.step, .finished)
      let result = try XCTUnwrap(model.result)
      XCTAssertEqual(delivered?.record, result.record)

      // Record: one capture, finished, address confirmed, notes kept.
      XCTAssertEqual(result.record.captures.count, 1)
      XCTAssertEqual(result.record.captures[0].areaKey, "floor-1")
      XCTAssertNotNil(result.record.captures[0].finishedAt)
      XCTAssertEqual(result.record.captures[0].omittedRooms.first?.name, "Primary closet")
      let schema = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-record.schema.json"))
      XCTAssertEqual(
        schema.validate(try JSON.parse(CaptureContractJSON.makeEncoder().encode(result.record))), [])

      // Originals: in the package folder layout, unchanged.
      XCTAssertTrue(result.originalsDirectory.path.hasSuffix(
        "Original Exports/floor-1/\(result.record.captures[0].captureId.rawValue)"))
      XCTAssertEqual(
        try Data(contentsOf: result.originalsDirectory.appendingPathComponent("roomplan.json")),
        try Fixtures.load("box-room").roomPlanData())

      // Capture model: mapped, valid against its schema, refs point at the originals.
      let capturedModel = try XCTUnwrap(result.captureModel)
      XCTAssertNil(result.mappingError)
      XCTAssertEqual(capturedModel.walls.count, 4)
      XCTAssertEqual(capturedModel.visitId, result.record.visitId)
      XCTAssertEqual(capturedModel.refs.map(\.role), [.rawRoomplanJSON, .rawDepth])
      let modelSchema = try SchemaValidator(schemaURL: Fixtures.schemaURL("capture-model.schema.json"))
      XCTAssertEqual(
        modelSchema.validate(try JSON.parse(CaptureContractJSON.makeEncoder().encode(capturedModel))), [])
    }

    // MARK: Current session (the host shows its camera feed)

    private func modelReadyToScan(made: MadeSessions) throws -> CaptureFlowModel {
      let model = try makeModel(made: made)
      model.choose(project)
      model.setAddressConfirmed(true)
      model.continueToSetup()
      model.draft.floorLabel = "Floor 1"
      model.draft.mode = .floor
      return model
    }

    /// The flow drops the session when it ends; the event task lets go of it a moment later.
    private func waitUntilReleased(_ made: MadeSessions, file: StaticString = #filePath, line: UInt = #line) async {
      for _ in 0..<200 where made.last != nil {
        try? await Task.sleep(nanoseconds: 10_000_000)
      }
      XCTAssertNil(made.last, "the session (and a live session's ARSession) is still retained", file: file, line: line)
    }

    func testCurrentSessionIsNilBeforeStart() throws {
      let made = MadeSessions()
      let model = try modelReadyToScan(made: made)
      XCTAssertNil(model.currentSession)
      XCTAssertEqual(made.count, 0)
    }

    func testCurrentSessionIsTheFactorySessionWhileScanningAndPaused() async throws {
      let made = MadeSessions()
      let model = try modelReadyToScan(made: made)
      await model.startScan()
      XCTAssertEqual(model.step, .scanning)
      let made1 = try XCTUnwrap(made.last)
      XCTAssertTrue(try XCTUnwrap(model.currentSession) === made1)

      await model.togglePause()
      XCTAssertTrue(model.isPaused)
      XCTAssertTrue(try XCTUnwrap(model.currentSession) === made1)

      await model.togglePause()
      XCTAssertFalse(model.isPaused)
      XCTAssertTrue(try XCTUnwrap(model.currentSession) === made1)
      XCTAssertEqual(made.count, 1)
    }

    func testCurrentSessionIsNilAfterFinish() async throws {
      let made = MadeSessions()
      let model = try modelReadyToScan(made: made)
      await model.startScan()
      XCTAssertNotNil(model.currentSession)
      await model.finishFloor()
      XCTAssertNil(model.errorMessage)
      XCTAssertEqual(model.step, .finished)
      XCTAssertNil(model.currentSession)
      await waitUntilReleased(made)
    }

    func testCurrentSessionIsNilAfterCancel() async throws {
      let made = MadeSessions()
      let model = try modelReadyToScan(made: made)
      await model.startScan()
      XCTAssertNotNil(model.currentSession)
      await model.cancelScan()
      XCTAssertEqual(model.step, .scanSetup)
      XCTAssertNil(model.currentSession)
      await waitUntilReleased(made)

      // A new scan gets a new session.
      await model.startScan()
      XCTAssertEqual(made.count, 2)
      XCTAssertTrue(try XCTUnwrap(model.currentSession) === made.last)
    }

    /// A view that reads `currentSession` is told when scanning starts and when it ends.
    func testCurrentSessionChangesAreObservable() async throws {
      let made = MadeSessions()
      let model = try modelReadyToScan(made: made)

      final class Flag: @unchecked Sendable { var changed = false }
      func track() -> Flag {
        let flag = Flag()
        withObservationTracking({ _ = model.currentSession }, onChange: { flag.changed = true })
        return flag
      }

      let onStart = track()
      await model.startScan()
      XCTAssertTrue(onStart.changed, "starting the scan is not observable")

      let onCancel = track()
      await model.cancelScan()
      XCTAssertTrue(onCancel.changed, "cancelling the scan is not observable")

      await model.startScan()
      let onFinish = track()
      await model.finishFloor()
      XCTAssertTrue(onFinish.changed, "finishing the floor is not observable")
    }

    func testElapsedTextAndModeTitles() throws {
      let model = try makeModel()
      XCTAssertEqual(model.elapsedText, "00:00")
      XCTAssertEqual(CaptureFlowModel.modeTitle(.room), "One room")
      XCTAssertEqual(CaptureFlowModel.modeTitle(.floor), "Whole floor")
      XCTAssertEqual(CaptureFlowModel.modeTitle(.exterior), "Exterior")
      XCTAssertEqual(ScanInstruction.normal.message, "Move slowly along the walls")
    }

    func testAppInfoIsNormalized() {
      XCTAssertEqual(CaptureRecord.AppInfo.normalized(version: "1.2", build: "7"), CaptureRecord.AppInfo(version: "1.2.0", build: "7"))
      XCTAssertEqual(CaptureRecord.AppInfo.normalized(version: "1", build: "7")?.version, "1.0.0")
      XCTAssertNil(CaptureRecord.AppInfo.normalized(version: "1.2.3.4", build: "7"))
      XCTAssertNil(CaptureRecord.AppInfo.normalized(version: "beta", build: "7"))
      XCTAssertNil(CaptureRecord.AppInfo.normalized(version: "1.0.0", build: nil))
    }
  }
#endif
