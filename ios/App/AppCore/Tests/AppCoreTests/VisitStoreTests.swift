import CaptureContract
import FieldRules
import Foundation
import PackageCore
import XCTest

@testable import AppCore

/// `visit.json` (phone-capture §5.2, §10.1 T-S1, critique R-26): round trip, atomic writes, the
/// revision fields, and the migration of workspaces the v1 app wrote (the owner's visits on the
/// phone must show up after the update).
final class VisitStoreTests: XCTestCase {
  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDown() {
    Fixtures.removeTemporaryDirectory(base)
  }

  private func record() -> CaptureRecord {
    Make.record([Make.capture("Floor 1", compass: Make.reading()), Make.capture("Floor 2")])
  }

  func testRoundTrip() throws {
    let workspace = VisitWorkspace.allocate(in: base)
    let record = record()
    var confirmation = NoRoomsSkippedConfirmation()
    confirmation.confirm(for: record)
    let file = VisitFile(
      createdAt: Make.time("2026-10-21T13:02:11Z"), updatedAt: Make.time("2026-10-21T14:40:03Z"),
      record: record, noRoomsSkipped: confirmation, isSealed: false)
    try VisitStore.save(file, to: workspace)
    XCTAssertEqual(try VisitStore.load(workspace), file)

    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: workspace.visitURL)) as? [String: Any])
    XCTAssertEqual(json["formatVersion"] as? Int, 1)
    XCTAssertEqual(json["createdAt"] as? String, "2026-10-21T13:02:11Z")
    XCTAssertEqual(json["isSealed"] as? Bool, false)
    XCTAssertNil(json["revision"], "absent for revision 1")
    let skipped = try XCTUnwrap(json["noRoomsSkipped"] as? [String: Any])
    XCTAssertEqual(
      (skipped["confirmedCaptureIds"] as? [String])?.sorted(),
      record.captures.map(\.captureId.rawValue).sorted())
    // The record keeps its compass fields (capture-record 1.1.0).
    let captures = try XCTUnwrap((json["record"] as? [String: Any])?["captures"] as? [[String: Any]])
    XCTAssertEqual(captures[0]["headingAccuracy"] as? Int, 8)
  }

  func testRevisionFieldsOnlyInRevisionMode() throws {
    let workspace = VisitWorkspace.allocate(in: base)
    let base = LowercaseUUID()
    let flow = VisitFlow(revisionOf: record(), base: base, baseRevision: 1)
    let started = Make.time("2026-10-21T15:00:00Z")
    let file = VisitFile(
      flow: flow, record: record(), createdAt: Make.time("2026-10-20T10:00:00Z"),
      now: Make.time("2026-10-21T16:00:00Z"), revisionStartedAt: started)
    XCTAssertEqual(file.revision, .init(number: 2, basePackageId: base, startedAt: started))
    XCTAssertFalse(file.isSealed, "a revision draft is not sealed (R-26)")
    try VisitStore.save(file, to: workspace)
    let loaded = try XCTUnwrap(try VisitStore.load(workspace))
    let resumed = loaded.flow(sealedRevision: 1)
    XCTAssertTrue(resumed.isRevisionMode)
    XCTAssertEqual(resumed.revision, 2)
    XCTAssertEqual(resumed.basePackageId, base)
    XCTAssertEqual(resumed.step, .overview)

    // Sealed: no revision object, and the flow resumes at the newest sealed revision.
    var sealedFlow = VisitFlow(revisionOf: record(), base: base, baseRevision: 1)
    try sealedFlow.reviewPackage(canFinish: true)
    try sealedFlow.sealed(packageId: LowercaseUUID())
    let sealed = VisitFile(
      flow: sealedFlow, record: record(), createdAt: started, now: started)
    XCTAssertNil(sealed.revision)
    XCTAssertTrue(sealed.isSealed)
    XCTAssertEqual(sealed.flow(sealedRevision: 2).revision, 2)
    XCTAssertTrue(sealed.flow(sealedRevision: 2).isReadOnly)
  }

  func testSaveIsAtomicAndReplacesTheFile() throws {
    let workspace = VisitWorkspace.allocate(in: base)
    var file = VisitFile(
      createdAt: Make.time("2026-10-21T13:00:00Z"), updatedAt: Make.time("2026-10-21T13:00:00Z"),
      record: record(), isSealed: false)
    try VisitStore.save(file, to: workspace)
    file.isSealed = true
    file.updatedAt = Make.time("2026-10-21T14:00:00Z")
    try VisitStore.save(file, to: workspace)
    XCTAssertEqual(try VisitStore.load(workspace)?.isSealed, true)
    let names = try FileManager.default.contentsOfDirectory(atPath: workspace.root.path)
    XCTAssertEqual(names, ["visit.json"], "no temporary file is left behind")
  }

  func testUnreadableFileIsAnErrorNotAnEmptyVisit() throws {
    let workspace = try VisitWorkspace.create(in: base)
    try Data("{".utf8).write(to: workspace.visitURL)
    XCTAssertThrowsError(try VisitStore.load(workspace))
    XCTAssertNil(VisitStore.loadOrMigrate(workspace), "a broken file is not overwritten")
    XCTAssertEqual(try Data(contentsOf: workspace.visitURL), Data("{".utf8))

    let future = try VisitWorkspace.create(in: base)
    try Data(#"{"formatVersion": 2}"#.utf8).write(to: future.visitURL)
    XCTAssertThrowsError(try VisitStore.load(future))
  }

  func testAbandonedNewCaptureLeavesNoFolder() throws {
    let workspace = VisitWorkspace.allocate(in: base)
    XCTAssertFalse(workspace.exists)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), [])
    XCTAssertNil(try VisitStore.load(workspace))
    XCTAssertNil(VisitStore.loadOrMigrate(workspace))
    XCTAssertFalse(workspace.exists, "reading creates nothing")
  }

  // MARK: Migration of v1 workspaces

  func testMigratesAV1VisitFromItsNewestDraft() throws {
    let visit = try FixtureVisit("box-room", in: base)
    let builder = VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0")
    _ = try builder.plan(record: visit.record, photos: visit.photos, controls: visit.controls)
    XCTAssertFalse(FileManager.default.fileExists(atPath: visit.workspace.visitURL.path))

    let file = try XCTUnwrap(VisitStore.loadOrMigrate(visit.workspace))
    // The draft's record, as the builder wrote it (capture-record 1.1.0).
    var expected = visit.record
    expected.schemaVersion = file.record.schemaVersion
    XCTAssertEqual(file.record, expected)
    XCTAssertFalse(file.isSealed)
    XCTAssertEqual(file.noRoomsSkipped, NoRoomsSkippedConfirmation(), "asked again")
    XCTAssertNil(file.revision)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: visit.workspace.visitURL.path), "written once")
    XCTAssertEqual(try VisitStore.load(visit.workspace), file)
    XCTAssertEqual(VisitStore.legacyScans(of: visit.workspace), [])
    // Nothing of the v1 workspace is moved or removed.
    XCTAssertFalse(try visit.originalDigests().isEmpty)
  }

  func testMigratesASealedV1VisitFromItsPackage() throws {
    let fixture = try SealedFixture(in: base)
    let file = try XCTUnwrap(VisitStore.loadOrMigrate(fixture.visit.workspace))
    XCTAssertTrue(file.isSealed)
    XCTAssertEqual(file.record.visitId, fixture.visit.record.visitId)
    XCTAssertEqual(file.updatedAt, Make.time("2026-01-25T15:00:00Z"))
    XCTAssertEqual(VisitStore.sealedPackages(of: fixture.visit.workspace).map(\.packageId), [
      fixture.sealed.packageId
    ])
    XCTAssertEqual(file.flow(sealedRevision: 1).step, .overview)
    XCTAssertTrue(file.flow(sealedRevision: 1).isReadOnly)
    // The v1 app sealed only once "Rooms not scanned" passed: the read-only overview must not
    // show it ■ Missing, which nothing on a sealed visit can fix.
    XCTAssertEqual(
      file.noRoomsSkipped.confirmedCaptureIds,
      Set(fixture.visit.record.captures.map(\.captureId)))
    XCTAssertTrue(file.flow(sealedRevision: 1).noRoomsSkippedConfirmed)
  }

  func testASealedFileWithoutTheTapCountsAsConfirmed() throws {
    // A sealed visit.json written by the first migration, before it kept the tap.
    let sealed = VisitFile(
      createdAt: Make.t1402, updatedAt: Make.t1402, record: record(), isSealed: true)
    XCTAssertNil(sealed.noRoomsSkipped.confirmedCaptureIds)
    XCTAssertTrue(sealed.flow(sealedRevision: 1).noRoomsSkippedConfirmed)
    // "Add to this capture" carries it over for the sealed floors; a new floor asks again.
    var revision = VisitFlow(
      revisionOf: sealed.record, base: LowercaseUUID(), baseRevision: 1,
      noRoomsSkipped: sealed.flow(sealedRevision: 1).noRoomsSkipped)
    XCTAssertTrue(revision.noRoomsSkippedConfirmed)
    try revision.addFloor()
    try revision.scanStarted()
    try revision.floorFinished(Make.record([Make.capture("Floor 3")]))
    XCTAssertFalse(revision.noRoomsSkippedConfirmed)

    // A recorded skipped room still decides: the item passes on its note, not on a tap.
    let skipped = VisitFile(
      createdAt: Make.t1402, updatedAt: Make.t1402,
      record: Make.record([Make.capture("Floor 1", omitted: ["Attic"])]), isSealed: true)
    XCTAssertFalse(skipped.flow(sealedRevision: 1).noRoomsSkippedConfirmed)

    // Not sealed: asked again, as the spec says for a visit migrated from its draft.
    let draft = VisitFile(
      createdAt: Make.t1402, updatedAt: Make.t1402, record: record(), isSealed: false)
    XCTAssertFalse(draft.flow(sealedRevision: nil).noRoomsSkippedConfirmed)
  }

  func testV1ScansWithoutACaptureRecordAreKeptAsLegacyScans() throws {
    let workspace = try VisitWorkspace.create(in: base)
    let folder = workspace.originalsRoot
      .appendingPathComponent("Original Exports/floor-1/\(LowercaseUUID().rawValue)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: folder.appendingPathComponent("roomplan.json"))

    XCTAssertNil(VisitStore.loadOrMigrate(workspace), "no capture record can be made up")
    XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.visitURL.path))
    let scans = VisitStore.legacyScans(of: workspace)
    XCTAssertEqual(scans.map(\.areaKey), ["floor-1"])
    XCTAssertEqual(scans.first?.folder.standardizedFileURL, folder.standardizedFileURL)

    // An empty v1 workspace (the v1 app made one at every launch) holds nothing.
    let empty = try VisitWorkspace.create(in: base)
    XCTAssertNil(VisitStore.loadOrMigrate(empty))
    XCTAssertEqual(VisitStore.legacyScans(of: empty), [])
  }

  // MARK: Field controls

  func testLoadsTheSavedFieldControls() throws {
    let visit = try FixtureVisit("two-floor-house", in: base)
    XCTAssertNil(try VisitStore.loadControls(visit.workspace, visitId: visit.record.visitId))
    try FieldControlsFile.write(visit.controls, intoPackageRoot: visit.workspace.controlsRoot)
    XCTAssertEqual(
      try VisitStore.loadControls(visit.workspace, visitId: visit.record.visitId), visit.controls)
  }

  func testWorkspacePaths() {
    let workspace = VisitWorkspace(root: URL(fileURLWithPath: "/v/abc", isDirectory: true))
    XCTAssertEqual(workspace.id, "abc")
    XCTAssertEqual(workspace.visitURL.path, "/v/abc/visit.json")
    XCTAssertEqual(
      workspace.stationStatusURL(packageId: "p1").path, "/v/abc/packages/p1.station-status.json")
  }
}
