import CaptureContract
import CaptureCore
import FieldRules
import Foundation
import PackageCore
import XCTest

@testable import AppCore

#if canImport(Observation)
  /// No location value reaches any file (phone-capture §4.1, §10.1 T-P1, compass AC7): a whole
  /// replay visit with a compass reading, from New capture to the sealed package with its
  /// `visit.json`, writes no latitude, longitude or other location field anywhere. The compass
  /// uses location only to turn magnetic into true north; the reading keeps the heading, its
  /// accuracy, source and time.
  @MainActor
  final class LocationNotStoredTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
      base = try Fixtures.temporaryDirectory()
    }

    override func tearDown() {
      Fixtures.removeTemporaryDirectory(base)
    }

    /// Keys a location could hide under, in any JSON object.
    private static let locationKeys: Set<String> = [
      "latitude", "longitude", "lat", "lon", "lng", "altitude", "coordinate", "coordinates",
      "location", "horizontalaccuracy", "verticalaccuracy", "gps",
    ]

    private func keys(_ value: Any) -> [String] {
      if let object = value as? [String: Any] {
        return object.keys.map { $0.lowercased() } + object.values.flatMap(keys)
      }
      if let array = value as? [Any] { return array.flatMap(keys) }
      return []
    }

    func testAReplayVisitWithACompassWritesNoLocation() async throws {
      let workspace = VisitWorkspace.allocate(in: base)
      let fixture = Fixtures.package("box-room")
      let originals = try XCTUnwrap(
        FileManager.default.enumerator(at: fixture, includingPropertiesForKeys: nil)?
          .compactMap { $0 as? URL }.first { $0.lastPathComponent == "roomplan.json" }
      ).deletingLastPathComponent()
      let source = try ReplaySource.load(directory: originals)
      let compass = FakeCompass(.verified)
      let project = HubProjectSummary(
        dealId: "fixture-deal-0001", projectName: "Fixture project",
        address: "100 Example Street, Testville, NY 00000")
      var finished: CaptureFlowResult?
      let model = CaptureFlowModel(
        draft: CaptureRecordDraft(
          operatorName: "Test Operator",
          device: DeviceInfo(model: "iPhone17,1", osName: .iOS, osVersion: "26.0", hasLidar: true),
          app: .init(version: "2.0.0", build: "1")),
        capabilities: DeviceCapabilities(
          model: "iPhone17,1", osName: .iOS, osVersion: "26.0",
          supportsSceneReconstructionMesh: true, roomPlanSupported: true),
        projectProvider: StaticHubProjectProvider([project]),
        originalsRoot: workspace.originalsRoot,
        makeSession: { _ in try ReplaySession(source: source, compass: compass.replayCompass) },
        compass: compass, onFinished: { finished = $0 })
      await model.loadProjects()
      model.choose(project)
      model.setAddressConfirmed(true)
      model.continueToSetup()
      await model.readCompassAgain()
      model.draft.mode = .room
      await model.startScan()
      for _ in 0..<500 where model.progress.counts.walls == 0 { await Task.yield() }
      await model.finishFloor()
      let result = try XCTUnwrap(finished)
      XCTAssertNotNil(result.record.captures[0].heading, "the visit has a compass reading")

      var flow = VisitFlow()
      try flow.scanStarted()
      try flow.floorFinished(result.record)
      try flow.photosDone()
      let record = try XCTUnwrap(flow.record)
      try VisitStore.save(
        VisitFile(flow: flow, record: record, createdAt: .now(), now: .now()), to: workspace)
      let controls = FieldControlsEditor(visitId: record.visitId).controls
      try FieldControlsFile.write(controls, intoPackageRoot: workspace.controlsRoot)
      let builder = VisitPackageBuilder(workspace: workspace, appVersion: "2.0.0")
      let plan = try builder.plan(record: record, photos: [], controls: controls)
      _ = try PackageAssembler().assemble(
        plan.draft, at: workspace.packageURL(packageId: plan.draft.packageId.rawValue))

      var checked = 0
      let enumerator = FileManager.default.enumerator(at: workspace.root, includingPropertiesForKeys: nil)
      while let url = enumerator?.nextObject() as? URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue,
          ["json", "csv", "svg", "dxf", "txt"].contains(url.pathExtension.lowercased())
        else { continue }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("latitude"), url.lastPathComponent)
        XCTAssertFalse(text.contains("longitude"), url.lastPathComponent)
        if url.pathExtension.lowercased() == "json",
          let json = try? JSONSerialization.jsonObject(with: data)
        {
          let found = Set(keys(json)).intersection(Self.locationKeys)
          XCTAssertEqual(found, [], url.lastPathComponent)
        }
        checked += 1
      }
      XCTAssertGreaterThan(checked, 5, "visit.json, capture record, controls, manifest, plans")
      XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.visitURL.path))
    }
  }
#endif
