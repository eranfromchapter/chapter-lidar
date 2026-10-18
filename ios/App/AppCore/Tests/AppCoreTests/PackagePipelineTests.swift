import CaptureContract
import Foundation
import PackageCore
import XCTest

@testable import AppCore

/// From the phone's files to "Package ready", sealing and the station's confirmation, with the
/// real StationClient and the bridge talking to the in-process UI-test station.
final class PackagePipelineTests: XCTestCase {
  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDownWithError() throws {
    // Sealed packages are read-only; make them writable so the temporary folder can go.
    if let base {
      let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
      while let url = enumerator?.nextObject() as? URL {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
      }
      try? FileManager.default.removeItem(at: base)
    }
  }

  func testTwoFloorVisitBuildsTheGuidesLayoutAndReview() throws {
    let visit = try FixtureVisit("two-floor-house", in: base)
    let plan = try VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0").plan(
      record: visit.record, photos: visit.photos, controls: visit.controls)

    let paths = plan.draft.entries.map(\.path)
    let visitId = visit.record.visitId.rawValue
    XCTAssertEqual(paths.first, "Source Register/\(visitId)/capture-record.json")
    XCTAssertTrue(paths.contains("Field Measurements/\(visitId)/field-controls.json"))
    for capture in visit.record.captures {
      let folder = "Original Exports/\(capture.areaKey)/\(capture.captureId.rawValue)/"
      for name in [
        "roomplan.json", "depth-samples.bin", "capture-model.json", "plan.dxf", "rooms.csv",
        "plan.pdf", "spatial-report.pdf", "plan.png", "plan.svg", "points.las",
      ] {
        XCTAssertTrue(paths.contains(folder + name), "missing \(folder + name)")
      }
      XCTAssertTrue(
        paths.contains("Site Photos/\(capture.areaKey)/\(capture.captureId.rawValue)/photo-0001.jpg"))
    }
    // No mesh anchors in the fixture recording: no GLB/OBJ (never invented), LAS from the depth.
    XCTAssertFalse(paths.contains { $0.hasSuffix("mesh.glb") })
    let las = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .pointCloudLAS })
    XCTAssertEqual(las.input.derivedFrom.count, 1)
    XCTAssertTrue(las.input.derivedFrom[0].hasSuffix("depth-samples.bin"))
    let model = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .captureModel })
    XCTAssertTrue(model.input.derivedFrom[0].hasSuffix("roomplan.json"))

    let review = plan.review
    XCTAssertEqual(review.captureCount, 2)
    XCTAssertEqual(review.revision, 1)
    XCTAssertEqual(review.captures.map(\.label), ["Floor 1", "Floor 2"])
    XCTAssertEqual(review.captures.map(\.fileCount), [10, 10])
    XCTAssertEqual(
      review.captures[0].kinds,
      "Plan DXF \u{00B7} Rooms CSV \u{00B7} Plan PDF \u{00B7} Spatial Report PDF \u{00B7} Plan PNG and SVG \u{00B7} LAS \u{00B7} raw RoomPlan + depth"
    )
    XCTAssertEqual(review.photoCount, 2)
    XCTAssertEqual(review.manifestEntries, paths.count)
    XCTAssertTrue(review.subtitle.hasSuffix("\u{00B7} 2 floors \u{00B7} revision 1"))
    XCTAssertTrue(review.sealNote.hasSuffix("changes create revision 2."))
  }

  func testCaptureModelUsesTheVisitIdsForEveryFloor() throws {
    let visit = try FixtureVisit("two-floor-house", in: base)
    let builder = VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0")
    for capture in visit.record.captures {
      let model = try builder.captureModel(of: capture, visitId: visit.record.visitId)
      XCTAssertEqual(model.visitId, visit.record.visitId)
      XCTAssertEqual(model.captureId, capture.captureId)
      XCTAssertEqual(model.areaKey, capture.areaKey)
    }
  }

  func testSealUploadAndStationConfirmationKeepOriginalsByteIdentical() async throws {
    let visit = try FixtureVisit("box-room", in: base)
    let before = try visit.originalDigests()
    let plan = try VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0").plan(
      record: visit.record, photos: visit.photos, controls: visit.controls)
    let sealed = try PackageAssembler().assemble(
      plan.draft, at: visit.workspace.packageURL(packageId: plan.draft.packageId.rawValue))
    XCTAssertTrue(sealed.verify().isEmpty)
    XCTAssertTrue(sealed.isReadOnly())

    let storage = UITestBlobStorage()
    let client = StationAPI(
      configuration: try .init(stationURL: UITestStationTransport.stationURL),
      tokenProvider: UITestTokenProvider(), transport: UITestStationTransport(storage: storage))
    let snapshots = SnapshotLog()
    let coordinator = UploadCoordinator(
      package: sealed, dealId: visit.record.hub.dealId,
      service: StationUploadService(client: client),
      transport: UITestBlobTransport(storage: storage),
      statusSource: StationStatusSource(client: client), sleep: { _ in },
      pollInterval: 0, onChange: { snapshots.append($0) })

    // Nothing is confirmed before the upload ran.
    XCTAssertFalse(coordinator.snapshot.isConfirmedByStation)
    coordinator.start()
    // The coordinator keeps following the station until a verdict; the stub stays at
    // checks_queued, so stop once the station status is known.
    let deadline = Date().addingTimeInterval(30)
    while coordinator.snapshot.stage == nil || coordinator.snapshot.activity == .uploading
      || coordinator.snapshot.activity == .starting
    {
      if case .failed(let message) = coordinator.snapshot.activity { return XCTFail(message) }
      guard Date() < deadline else { return XCTFail("upload did not finish") }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    coordinator.cancel()

    let final = coordinator.snapshot
    XCTAssertEqual(final.activity, .confirmed)
    XCTAssertTrue(final.isConfirmedByStation)
    XCTAssertEqual(final.stage, .checksQueued)
    XCTAssertEqual(final.progress.fraction, 1)
    XCTAssertEqual(final.progress.percentText, "100%")
    XCTAssertTrue(final.progress.rows.allSatisfy { $0.status == .verified })
    XCTAssertEqual(
      final.station.steps.map(\.done), [true, true, false, false],
      "Registered and Checks queued done; no verdict yet; HUB publication never claimed")
    // Every intermediate snapshot before the station's seal answer was unconfirmed.
    XCTAssertTrue(snapshots.all.dropLast().contains { !$0.isConfirmedByStation })

    // Originals are untouched, and the sealed package still matches its manifest.
    XCTAssertEqual(try visit.originalDigests(), before)
    XCTAssertTrue(sealed.verify().isEmpty)

    // A confirmed package is no longer pending.
    XCTAssertTrue(PendingUploads.find(visitsRoot: base).isEmpty)
  }

  func testSealedButNotUploadedPackageIsPendingWithItsDeal() throws {
    let visit = try FixtureVisit("box-room", in: base)
    let plan = try VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0").plan(
      record: visit.record, photos: visit.photos, controls: visit.controls)
    _ = try PackageAssembler().assemble(
      plan.draft, at: visit.workspace.packageURL(packageId: plan.draft.packageId.rawValue))
    let pending = PendingUploads.find(visitsRoot: base)
    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending.first?.dealId, visit.record.hub.dealId)
    XCTAssertEqual(pending.first?.package.packageId, plan.draft.packageId)
  }

  func testMeshFromAnchorsAppliesEachTransform() throws {
    let translate = try XCTUnwrap(
      Matrix4Columns.make([[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [2, 3, 4, 1]]))
    let anchors = [
      RawMeshAnchorFactory.make(
        transform: translate, vertices: [0, 0, 0, 1, 0, 0, 0, 1, 0], triangles: [0, 1, 2]),
      RawMeshAnchorFactory.make(
        transform: translate, vertices: [0, 0, 0, 0, 0, 1, 1, 0, 0], triangles: [0, 1, 2]),
    ]
    let mesh = try XCTUnwrap(VisitPackageBuilder.mesh(from: anchors))
    XCTAssertEqual(mesh.positions.first, SIMD3<Float>(2, 3, 4))
    XCTAssertEqual(mesh.positions[1], SIMD3<Float>(3, 3, 4))
    XCTAssertEqual(mesh.indices, [0, 1, 2, 3, 4, 5])
    XCTAssertNil(VisitPackageBuilder.mesh(from: []))
  }
}

final class SnapshotLog: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [UploadSnapshot] = []
  func append(_ snapshot: UploadSnapshot) { lock.withLock { items.append(snapshot) } }
  var all: [UploadSnapshot] { lock.withLock { items } }
}
