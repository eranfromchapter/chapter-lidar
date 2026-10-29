import CaptureContract
import FieldRules
import Foundation
import PackageCore
import PhotoStore
import XCTest

@testable import AppCore

/// From the phone's files to "Package ready", sealing and the station's confirmation, with the
/// real StationClient and the bridge talking to the in-process UI-test station. Merges the
/// expectations of phone-package §11 (no phone report, manifest 1.1.0), plan-sheet (the plan
/// sheet PDF per capture) and phone-field AC8 (every photo keeps its `directionSource`).
final class PackagePipelineTests: XCTestCase {
  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDownWithError() throws {
    // Sealed packages are read-only; make them writable so the temporary folder can go.
    if let base { Fixtures.removeTemporaryDirectory(base) }
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
      // One plan sheet PDF per capture: `plan-sheet.pdf` from the plan-sheet track's PlanExport
      // on (`plan.pdf` from the PlanExport before it).
      let sheets = plan.draft.entries.filter {
        $0.input.role == .planPDF && $0.input.capture?.captureId == capture.captureId
      }
      XCTAssertEqual(sheets.count, 1)
      XCTAssertTrue(
        ["plan-sheet.pdf", "plan.pdf"].contains(sheets.first?.input.fileName ?? ""),
        "plan sheet named \(sheets.first?.input.fileName ?? "-")")
      for name in [
        "roomplan.json", "depth-samples.bin", "capture-model.json", "plan.dxf", "rooms.csv",
        "plan.png", "plan.svg", "points.las",
      ] {
        XCTAssertTrue(paths.contains(folder + name), "missing \(folder + name)")
      }
      XCTAssertTrue(
        paths.contains("Site Photos/\(capture.areaKey)/\(capture.captureId.rawValue)/photo-0001.jpg"))
    }
    // The phone's spatial report is retired: the station makes the spatial report.
    XCTAssertFalse(paths.contains { $0.hasSuffix("spatial-report.pdf") })
    XCTAssertFalse(plan.draft.entries.contains { $0.input.role.isRetired })
    // No mesh anchors in the fixture recording: no GLB/OBJ (never invented), LAS from the depth.
    XCTAssertFalse(paths.contains { $0.hasSuffix("mesh.glb") })
    let las = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .pointCloudLAS })
    XCTAssertEqual(las.input.derivedFrom.count, 1)
    XCTAssertTrue(las.input.derivedFrom[0].hasSuffix("depth-samples.bin"))
    let model = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .captureModel })
    XCTAssertTrue(model.input.derivedFrom[0].hasSuffix("roomplan.json"))

    let review = plan.review
    XCTAssertEqual(review.captureCountText, "2 floors")
    XCTAssertEqual(review.revision, 1)
    XCTAssertEqual(review.exportGroups.map(\.label), ["Floor 1", "Floor 2"])
    XCTAssertEqual(review.exportGroups.map(\.fileCount), [9, 9])
    XCTAssertEqual(
      review.exportGroups[0].rows,
      [
        PackageReview.ExportRow(
          kind: .plans, label: "Plan DXF \u{00B7} rooms CSV \u{00B7} plan sheet PDF, PNG, SVG",
          count: 5),
        PackageReview.ExportRow(
          kind: .raw,
          label: "Point cloud LAS \u{00B7} raw RoomPlan + depth \u{00B7} capture model", count: 4),
      ])
    XCTAssertEqual(review.photoCount, 2)
    XCTAssertEqual(review.manifestEntries, paths.count)
    // Floor 1 has a verified compass reading in the fixture, Floor 2 none.
    XCTAssertEqual(review.compassText, "compass: Floor 1 only")
    XCTAssertEqual(
      review.subtitle,
      "\(visit.record.address.formatted) \u{00B7} 2 floors \u{00B7} revision 1 \u{00B7} "
        + "\(paths.count) files \u{00B7} \(ByteText.format(review.totalBytes))")
    XCTAssertTrue(
      review.sealNote.hasSuffix(
        "later changes create revision 2. The station makes the spatial report."))
    let everything = [review.subtitle, review.sealNote] + review.exportGroups.flatMap(\.rows).map(\.label)
    XCTAssertFalse(everything.contains { $0.localizedCaseInsensitiveContains("spatial report pdf") })
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

  /// phone-field AC8 and phone-package §13.5 AC1: the sealed manifest is 1.1.0, valid against
  /// the schema, holds no retired role, and every photo keeps the direction source it was saved
  /// with.
  func testSealedManifestIs1_1_0AndEveryPhotoKeepsItsDirectionSource() throws {
    let visit = try FixtureVisit("sample-424", in: base)
    let saved = Dictionary(
      visit.photos.map { ($0.path, $0.labels.directionSource) }, uniquingKeysWith: { first, _ in first })
    XCTAssertTrue(saved.values.contains(.compass))
    XCTAssertTrue(saved.values.contains(.manual))
    let plan = try VisitPackageBuilder(workspace: visit.workspace, appVersion: "2.0.0").plan(
      record: visit.record, photos: visit.photos, controls: visit.controls)
    let sealed = try PackageAssembler().assemble(
      plan.draft, at: visit.workspace.packageURL(packageId: plan.draft.packageId.rawValue))

    XCTAssertEqual(sealed.manifest.schemaVersion, .v1_2)
    XCTAssertEqual(try JSON.parse(sealed.manifestData)["schemaVersion"]?.string, "1.2.0")
    XCTAssertEqual(try Fixtures.manifestValidator().validate(jsonData: sealed.manifestData), [])
    XCTAssertFalse(sealed.manifest.files.contains { $0.role.isRetired })
    let photos = sealed.manifest.files.filter { $0.role == .photo }
    XCTAssertEqual(photos.count, visit.photos.count)
    for photo in photos {
      XCTAssertEqual(photo.photo?.directionSource, saved[photo.path] ?? nil, photo.path)
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
    XCTAssertEqual(coordinator.snapshot.title, "Uploading")
    coordinator.start()
    // The coordinator keeps following the station until a verdict; the stub stays at
    // checks_queued, so stop once the station status is known.
    let deadline = Date().addingTimeInterval(30)
    while coordinator.snapshot.station == nil || coordinator.snapshot.activity == .uploading
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
    XCTAssertEqual(final.phase, .uploaded)
    XCTAssertEqual(final.title, "Uploaded")
    XCTAssertEqual(final.caption, "The station has every file. Checks run next.")
    XCTAssertEqual(final.progress.fraction, 1)
    XCTAssertEqual(final.progress.percentText, "100%")
    XCTAssertTrue(final.progress.rows.allSatisfy { $0.status == .confirmed })
    XCTAssertNotNil(final.state.registeredAt, "the station registered the package")
    let timeline = final.timeline()
    XCTAssertEqual(timeline.rows.map(\.state), [.done, .inProgress, .pending, .pending])
    XCTAssertEqual(timeline.row(.checks)?.detail, "Queued")
    XCTAssertEqual(
      timeline.row(.published)?.accessibilityLabel, "Published to the HUB, not yet",
      "HUB publication is never claimed without the station saying so")
    // Every intermediate snapshot before the station's seal answer was unconfirmed.
    XCTAssertTrue(snapshots.all.dropLast().contains { !$0.isConfirmedByStation })
    // The station status is cached next to the package.
    let cache = try XCTUnwrap(try StationStatusStore(packageRoot: sealed.root).load())
    XCTAssertEqual(cache.stage, .checksQueued)
    XCTAssertEqual(
      cache.links?.review, "https://uitest-review.invalid/packages/\(sealed.packageId.rawValue)")
    XCTAssertEqual(
      cache.links?.openInHub,
      URL(string: "https://uitest-hub.invalid/deals/\(visit.record.hub.dealId)"),
      "the stub station has the HUB deal URL configured")

    // Originals are untouched, and the sealed package still matches its manifest.
    XCTAssertEqual(try visit.originalDigests(), before)
    XCTAssertTrue(sealed.verify().isEmpty)

    // A confirmed package is no longer pending.
    XCTAssertTrue(PendingUploads.find(visitsRoot: base).isEmpty)
  }

  /// The verdict, the checks and the HUB publication come from the station; the coordinator stops
  /// following once the publication is final, and posts the notification once.
  func testTheVerdictAndThePublicationAreFollowedAndCached() async throws {
    let visit = try FixtureVisit("box-room", in: base)
    let plan = try VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0").plan(
      record: visit.record, photos: visit.photos, controls: visit.controls)
    let sealed = try PackageAssembler().assemble(
      plan.draft, at: visit.workspace.packageURL(packageId: plan.draft.packageId.rawValue))
    let clock = TestClock()
    let storage = UITestBlobStorage()
    let client = StationAPI(
      configuration: try .init(stationURL: UITestStationTransport.stationURL),
      tokenProvider: UITestTokenProvider(),
      transport: UITestStationTransport(
        storage: storage, options: UITestStationOptions(verdict: .limited), now: { clock.now }))
    let notifications = NotificationLog()
    let coordinator = UploadCoordinator(
      package: sealed, dealId: visit.record.hub.dealId,
      service: StationUploadService(client: client),
      transport: UITestBlobTransport(storage: storage),
      statusSource: StationStatusSource(client: client),
      sleep: { seconds in clock.advance(seconds) }, now: { clock.now },
      onVerdict: { notifications.append($0) })
    coordinator.start()
    await coordinator.waitUntilIdle()

    let final = coordinator.snapshot
    XCTAssertEqual(final.phase, .verdict)
    XCTAssertEqual(final.title, "Fixture box-room", "the project title (critique R-29)")
    XCTAssertEqual(final.navigationCaption, "Revision 1")
    let verdict = try XCTUnwrap(final.verdict)
    XCTAssertEqual(verdict.outcome, .limited)
    XCTAssertEqual(
      verdict.sentence(published: final.isPublished),
      "Usable for preliminary existing-condition plans, with 2 limitations. Details: spatial "
        + "report in the HUB.")
    XCTAssertEqual(final.station?.publication?.status, .published)
    let rows = final.timeline(now: clock.now, timeZone: TimeZone(identifier: "UTC")!).rows
    XCTAssertEqual(rows.map(\.id), [.checks, .verdict, .published])
    XCTAssertEqual(rows.map(\.state), [.done, .done, .done])
    XCTAssertEqual(rows[1].title, "Verdict \u{00B7} Limited")
    XCTAssertEqual(rows[1].shape, .triangle)

    XCTAssertEqual(notifications.all.count, 1)
    XCTAssertEqual(notifications.all.first?.title, "Verdict: Limited")
    XCTAssertEqual(
      notifications.all.first?.body,
      "Fixture box-room \u{00B7} revision 1. Details: spatial report in the HUB.")
    let cache = try XCTUnwrap(try StationStatusStore(packageRoot: sealed.root).load())
    XCTAssertEqual(cache.verdict, verdict)
    XCTAssertEqual(cache.notifiedVerdictId, verdict.verdictId)
    XCTAssertTrue(cache.isSettled)

    // A new coordinator (the next launch) starts from the cache and posts nothing again.
    let again = UploadCoordinator(
      package: sealed, dealId: visit.record.hub.dealId,
      service: StationUploadService(client: client),
      transport: UITestBlobTransport(storage: storage),
      statusSource: StationStatusSource(client: client),
      sleep: { seconds in clock.advance(seconds) }, now: { clock.now },
      onVerdict: { notifications.append($0) })
    XCTAssertEqual(again.snapshot.verdict, verdict)
    XCTAssertEqual(again.snapshot.phase, .verdict)
    again.start()
    await again.waitUntilIdle()
    XCTAssertEqual(notifications.all.count, 1)
  }

  /// Revision 2 after "Add to this capture": only the new photo goes up; the station carries
  /// every other file over from revision 1 (phone-package §13.5 AC7).
  func testRevision2UploadsOnlyTheNewFile() async throws {
    let visit = try FixtureVisit("box-room", in: base)
    let builder = VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0")
    let first = try builder.plan(record: visit.record, photos: visit.photos, controls: visit.controls)
    let sealed1 = try PackageAssembler().assemble(
      first.draft, at: visit.workspace.packageURL(packageId: first.draft.packageId.rawValue))
    let storage = UITestBlobStorage()
    let client = StationAPI(
      configuration: try .init(stationURL: UITestStationTransport.stationURL),
      tokenProvider: UITestTokenProvider(), transport: UITestStationTransport(storage: storage))
    func coordinator(_ package: SealedPackage) -> UploadCoordinator {
      UploadCoordinator(
        package: package, dealId: visit.record.hub.dealId,
        service: StationUploadService(client: client),
        transport: UITestBlobTransport(storage: storage),
        statusSource: StationStatusSource(client: client), sleep: { _ in }, pollInterval: 0)
    }
    let one = coordinator(sealed1)
    one.start()
    try await waitForConfirmation(one)
    one.cancel()

    // One more photo of the box room.
    let store = try PhotoRecordStore(files: DiskPhotoFileStore(root: visit.workspace.photosRoot))
    let capture = try XCTUnwrap(visit.record.captures.first)
    var labels = try XCTUnwrap(visit.photos.first?.labels)
    labels.subject = .ceiling
    let added = try store.save(
      original: try Data(contentsOf: visit.workspace.photosRoot.appendingPathComponent(
        visit.photos[0].path)),
      capture: FieldControls.CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey),
      labels: labels)
    let revision = try builder.revisionPlan(
      base: sealed1, record: visit.record, photos: visit.photos + [added],
      controls: visit.controls)
    XCTAssertEqual(revision.changes.uploadCount, 1)
    XCTAssertEqual(
      revision.changes.footnote,
      "Only the 1 new file is uploaded. The station checks the whole package and issues a new "
        + "verdict and spatial report.")
    let sealed2 = try PackageAssembler().assemble(
      revision.draft, at: visit.workspace.packageURL(packageId: revision.draft.packageId.rawValue))
    XCTAssertEqual(sealed2.manifest.revision, 2)
    XCTAssertEqual(sealed2.manifest.supersedesPackageId, sealed1.packageId)

    let two = coordinator(sealed2)
    two.start()
    try await waitForConfirmation(two)
    two.cancel()
    let state = two.snapshot.state
    XCTAssertEqual(state.carriedOver, Set(sealed1.manifest.files.map(\.path)))
    XCTAssertEqual(
      Set(sealed2.manifest.files.map(\.path)).subtracting(state.carriedOver), [added.path])
    XCTAssertTrue(two.snapshot.progress.rows.allSatisfy { $0.status == .confirmed })
    XCTAssertEqual(two.snapshot.progress.bytesTotal, added.bytes, "carried-over files not counted")
    XCTAssertTrue(two.snapshot.subtitle.contains("revision 2 \u{00B7} 1 new or changed file \u{00B7}"))
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

  private func waitForConfirmation(
    _ coordinator: UploadCoordinator, file: StaticString = #filePath, line: UInt = #line
  ) async throws {
    let deadline = Date().addingTimeInterval(30)
    while !coordinator.snapshot.isConfirmedByStation {
      if case .failed(let message) = coordinator.snapshot.activity {
        return XCTFail(message, file: file, line: line)
      }
      guard Date() < deadline else { return XCTFail("upload did not finish", file: file, line: line) }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
  }
}

final class SnapshotLog: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [UploadSnapshot] = []
  func append(_ snapshot: UploadSnapshot) { lock.withLock { items.append(snapshot) } }
  var all: [UploadSnapshot] { lock.withLock { items } }
}

final class NotificationLog: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [VerdictNotification] = []
  func append(_ notification: VerdictNotification) { lock.withLock { items.append(notification) } }
  var all: [VerdictNotification] { lock.withLock { items } }
}

/// A clock the tests move: the coordinator's sleeps advance it, and the stub station reads it.
final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current: Date

  init(_ start: Date = Date(timeIntervalSince1970: 1_792_243_200)) {
    current = start
  }

  var now: Date { lock.withLock { current } }

  func advance(_ seconds: TimeInterval) {
    lock.withLock { current = current.addingTimeInterval(seconds) }
  }
}
