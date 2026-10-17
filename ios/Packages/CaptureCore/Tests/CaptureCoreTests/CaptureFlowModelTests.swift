import CaptureContract
import CaptureCore
import CaptureTestSupport
import Foundation
import XCTest

#if canImport(Observation)
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

    private func makeModel(
      lidar: Bool = true, fixture: String = "box-room", onFinished: @escaping @MainActor (CaptureFlowResult) -> Void = { _ in }
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
        makeSession: { _ in try ReplaySession(source: source) },
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
