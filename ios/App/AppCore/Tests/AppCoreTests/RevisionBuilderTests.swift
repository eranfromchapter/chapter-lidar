import CaptureContract
import CaptureCore
import FieldRules
import Foundation
import PackageCore
import PhotoStore
import XCTest

@testable import AppCore

/// Revision n from the visit's files (phone-package §9.4, §13.1 RevisionBuilderTests (a)–(g)):
/// what is carried over, replaced, added and removed, and what the Revision n screen says.
final class RevisionBuilderTests: XCTestCase {
  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDownWithError() throws {
    if let base { Fixtures.removeTemporaryDirectory(base) }
  }

  private func savePhoto(
    _ fixture: SealedFixture, capture: CaptureRecord.Capture, room: String,
    subject: PhotoSubject = .ceiling
  ) throws -> PhotoRecord {
    let store = try PhotoRecordStore(files: DiskPhotoFileStore(root: fixture.visit.workspace.photosRoot))
    let original = try store.originalData(for: fixture.visit.photos[0])
    return try store.save(
      original: original,
      capture: FieldControls.CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey),
      labels: PackageManifest.PhotoLabels(
        room: room, direction: .east, subject: subject, takenAt: Make.t1402,
        directionSource: .manual))
  }

  private func baseDigests(_ sealed: SealedPackage) -> [String: String] {
    Dictionary(sealed.manifest.files.map { ($0.path, $0.sha256) }, uniquingKeysWith: { a, _ in a })
  }

  /// (a) and (g): a new photo only.
  func testAPhotoOnlyRevisionCarriesEveryBaseFile() throws {
    let fixture = try SealedFixture("two-floor-house", in: base)
    let floor1 = try XCTUnwrap(fixture.visit.record.captures.first)
    let photo = try savePhoto(fixture, capture: floor1, room: "Living Room")
    let plan = try fixture.builder.revisionPlan(
      base: fixture.sealed, record: fixture.visit.record, photos: fixture.visit.photos + [photo],
      controls: fixture.visit.controls)

    XCTAssertEqual(plan.draft.revision, 2)
    XCTAssertEqual(plan.draft.supersedesPackageId, fixture.sealed.packageId)
    let changes = plan.changes
    XCTAssertEqual(changes.addedPaths, [photo.path])
    XCTAssertEqual(changes.changedPaths, [], "capture record, controls and plans unchanged")
    XCTAssertEqual(changes.uploadCount, 1)
    XCTAssertEqual(changes.rows.map(\.title), ["1 photo"])
    XCTAssertEqual(changes.rows.map(\.detail), ["Living Room \u{00B7} ceiling"])
    let count = fixture.sealed.manifest.files.count
    XCTAssertEqual(changes.manifestDetail, "\(count) \u{2192} \(count + 1) entries")
    XCTAssertEqual(changes.unchangedTitle, "Floor 1 and Floor 2 scans, 2 photos, \(PackageReview.controlCount(fixture.visit.controls)) controls")
    // Every base file is carried over from the sealed package with its fingerprint.
    let digests = baseDigests(fixture.sealed)
    for entry in plan.draft.entries where entry.path != photo.path {
      XCTAssertEqual(entry.input.expected?.sha256, digests[entry.path], entry.path)
      XCTAssertTrue(entry.input.source.path.hasPrefix(fixture.sealed.root.path), entry.path)
    }
    let sealed = try PackageAssembler().assemble(
      plan.draft, at: fixture.visit.workspace.packageURL(packageId: plan.draft.packageId.rawValue))
    XCTAssertEqual(sealed.manifest.files.count, count + 1)
    XCTAssertEqual(try Fixtures.manifestValidator().validate(jsonData: sealed.manifestData), [])
  }

  /// (b): a new one-room capture.
  func testANewCaptureAddsItsFilesAndChangesTheRecord() throws {
    let fixture = try SealedFixture("two-room-apartment", in: base)
    let originals = Fixtures.package("box-room")
    let boxRecord = try FixtureVisit("box-room", in: base).record
    let boxCapture = try XCTUnwrap(boxRecord.captures.first)
    let closet = CaptureRecord.Capture(
      captureId: LowercaseUUID(), areaKey: "room-1", label: "Primary closet", mode: .room,
      units: boxCapture.units, capturedAt: Make.time("2026-05-20T10:00:00Z"))
    let folder = fixture.builder.originalsDirectory(of: closet)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in ["roomplan.json", "depth-samples.bin"] {
      try FileManager.default.copyItem(
        at: Fixtures.url(
          originals,
          "Original Exports/\(boxCapture.areaKey)/\(boxCapture.captureId.rawValue)/\(name)"),
        to: folder.appendingPathComponent(name))
    }
    let record = try fixture.visit.record.appending(closet)
    let plan = try fixture.builder.revisionPlan(
      base: fixture.sealed, record: record, photos: fixture.visit.photos,
      controls: fixture.visit.controls)

    let changes = plan.changes
    let recordPath = try XCTUnwrap(fixture.sealed.manifest.files.first { $0.role == .captureRecord }?.path)
    XCTAssertTrue(changes.changedPaths.contains(recordPath))
    let added = plan.draft.entries.filter { $0.input.capture?.captureId == closet.captureId }
    XCTAssertEqual(Set(changes.addedPaths), Set(added.map(\.path)))
    XCTAssertFalse(added.isEmpty)
    XCTAssertEqual(changes.rows.first?.title, "Primary closet")
    XCTAssertEqual(
      changes.rows.first?.detail,
      "Scanned \u{00B7} one room \u{00B7} \(PackageText.plural(added.count, "file", "files"))")
    let baseLabel = try XCTUnwrap(fixture.visit.record.captures.first?.label)
    XCTAssertTrue(changes.unchangedTitle?.hasPrefix("\(baseLabel) scan") ?? false)
    let digests = baseDigests(fixture.sealed)
    for entry in plan.draft.entries where entry.input.capture?.captureId != closet.captureId
      && entry.path != recordPath
    {
      XCTAssertEqual(entry.input.expected?.sha256, digests[entry.path], "\(entry.path) carried over")
    }
  }

  /// (c): a new ceiling height.
  func testANewControlChangesTheControlsFile() throws {
    let fixture = try SealedFixture(in: base)
    let capture = try XCTUnwrap(fixture.visit.record.captures.first)
    var controls = fixture.visit.controls
    controls.ceilingHeights.append(
      FieldControls.CeilingHeight(
        id: "ceiling-room-4", capture: .init(captureId: capture.captureId, areaKey: capture.areaKey),
        room: "Room 4",
        measurement: .init(
          valueMm: 2490, enteredUnit: .mm, enteredText: "2490", method: .tape,
          recordedAt: Make.t1402)))
    let plan = try fixture.builder.revisionPlan(
      base: fixture.sealed, record: fixture.visit.record, photos: fixture.visit.photos,
      controls: controls,
      baseNextActions: ["Tape-measure the Room 4 ceiling height on the next visit."])
    let controlsPath = try XCTUnwrap(
      fixture.sealed.manifest.files.first { $0.role == .fieldControls }?.path)
    XCTAssertEqual(plan.changes.changedPaths, [controlsPath])
    XCTAssertEqual(plan.changes.addedPaths, [])
    XCTAssertEqual(plan.changes.rows.map(\.title), ["Room 4 ceiling height"])
    // "Field control · 2,490 mm · 8' 2"" with phone-field's LengthFormatter v2.
    XCTAssertEqual(plan.changes.rows.map(\.detail), ["Field control \u{00B7} \(LengthFormatter.both(2490))"])
    XCTAssertEqual(plan.changes.rows.first?.method, .tape)
    XCTAssertEqual(
      plan.changes.rows.first?.answersNextAction,
      "Tape-measure the Room 4 ceiling height on the next visit.")
    XCTAssertEqual(
      plan.changes.footnote,
      "Only the 1 new or changed file is uploaded. The station checks the whole package and "
        + "issues a new verdict and spatial report.")
  }

  /// (d): a renamed room of a sealed floor redraws that floor's plans; nothing else changes.
  func testARenamedRoomRedrawsTheFloorsPlansOnly() throws {
    let fixture = try SealedFixture(in: base)
    let capture = try XCTUnwrap(fixture.visit.record.captures.first)
    var rooms = VisitRooms(builder: fixture.builder)
    try rooms.load(capture, visitId: fixture.visit.record.visitId)
    let room = try XCTUnwrap(rooms.rooms[capture.captureId]?.first)
    var names = VisitRoomNames()
    names.setName(
      "Shower", roomId: room.id, derivedLabel: room.derivedLabel, footprint: room.footprint,
      captureId: capture.captureId)
    let plan = try fixture.builder.revisionPlan(
      base: fixture.sealed, record: fixture.visit.record, photos: fixture.visit.photos,
      controls: fixture.visit.controls, roomNames: names)

    let roles = Dictionary(plan.draft.entries.map { ($0.path, $0.input.role) }, uniquingKeysWith: { a, _ in a })
    let changedRoles = Set(plan.changes.changedPaths.compactMap { roles[$0] })
    XCTAssertTrue(changedRoles.contains(.captureModel))
    XCTAssertTrue(changedRoles.contains(.roomsCSV))
    XCTAssertTrue(
      changedRoles.isSubset(of: [.captureModel, .planDXF, .roomsCSV, .planPDF, .planPNG, .planSVG]),
      "raw originals, LAS, record, controls and photos stay: \(changedRoles)")
    XCTAssertEqual(plan.changes.addedPaths, [])
    XCTAssertEqual(plan.changes.removedPaths, [])
    let row = try XCTUnwrap(plan.changes.rows.first)
    XCTAssertEqual(row.title, "\(capture.label) room names")
    XCTAssertEqual(row.kind, .changed)
    XCTAssertEqual(
      row.detail,
      "\(room.derivedLabel) \u{2192} Shower \u{00B7} "
        + PackageText.plural(plan.changes.changedPaths.count, "file", "files"))
    // The redrawn files derive from the new model.
    let model = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .captureModel })
    let csv = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .roomsCSV })
    XCTAssertEqual(csv.input.derivedFrom, [model.path])
    XCTAssertTrue(try String(contentsOf: csv.input.source, encoding: .utf8).contains("Shower"))
  }

  /// (e): a 1.0.0 base with the phone report.
  func testALegacyBaseLosesThePhoneReport() throws {
    let visit = try FixtureVisit("legacy-1.0.0", in: base)
    let legacy = try legacyCopy(in: visit.workspace)
    let builder = VisitPackageBuilder(workspace: visit.workspace, appVersion: "2.0.0")
    let plan = try builder.revisionPlan(
      base: legacy, record: visit.record, photos: visit.photos, controls: visit.controls)
    let report = try XCTUnwrap(legacy.manifest.files.first { $0.role == .spatialReportPDF }?.path)
    XCTAssertTrue(plan.changes.removedPaths.contains(report))
    XCTAssertFalse(plan.draft.entries.contains { $0.input.role.isRetired })
    let row = try XCTUnwrap(plan.changes.rows.last)
    XCTAssertEqual(row.title, "Spatial report PDF from the phone")
    XCTAssertEqual(row.detail, "Retired \u{00B7} the station makes the spatial report \u{00B7} 1 file")
    XCTAssertEqual(row.kind, .removed)
    XCTAssertEqual(row.subject, .retiredFile)
    let sealed = try PackageAssembler().assemble(
      plan.draft, at: visit.workspace.packageURL(packageId: plan.draft.packageId.rawValue))
    XCTAssertEqual(sealed.manifest.schemaVersion, .v1_2)
    XCTAssertEqual(try Fixtures.manifestValidator().validate(jsonData: sealed.manifestData), [])
  }

  /// (f): nothing changed.
  func testNoChangeHasNothingToSeal() throws {
    let fixture = try SealedFixture(in: base)
    let plan = try fixture.builder.revisionPlan(
      base: fixture.sealed, record: fixture.visit.record, photos: fixture.visit.photos,
      controls: fixture.visit.controls)
    XCTAssertEqual(plan.changes.uploadCount, 0)
    XCTAssertTrue(plan.changes.rows.isEmpty)
    XCTAssertEqual(plan.changes.sealButtonTitle, "No changes to seal")
    XCTAssertEqual(plan.changes.unchangedPaths.count, fixture.sealed.manifest.files.count)
  }

  func testAFullRebuildForAReSeal() throws {
    let fixture = try SealedFixture(in: base)
    let plan = try fixture.builder.rebuildPlan(
      revision: 2, supersedes: fixture.sealed.packageId, record: fixture.visit.record,
      photos: fixture.visit.photos, controls: fixture.visit.controls)
    XCTAssertEqual(plan.draft.revision, 2)
    XCTAssertEqual(plan.draft.supersedesPackageId, fixture.sealed.packageId)
    XCTAssertEqual(plan.review.revision, 2)
    XCTAssertEqual(
      plan.draft.entries.map(\.path), fixture.plan.draft.entries.map(\.path), "the same files")
    XCTAssertFalse(
      plan.draft.entries.contains { $0.input.source.path.hasPrefix(fixture.sealed.root.path) },
      "never from the sealed copy")
    XCTAssertThrowsError(
      try fixture.builder.rebuildPlan(
        revision: 1, supersedes: fixture.sealed.packageId, record: fixture.visit.record,
        photos: [], controls: fixture.visit.controls))
  }

  func testOriginalsOnThePhone() throws {
    let fixture = try SealedFixture(in: base)
    XCTAssertTrue(fixture.builder.hasOriginals(of: fixture.visit.record))
    try FileManager.default.removeItem(at: fixture.visit.workspace.originalsRoot)
    XCTAssertFalse(fixture.builder.hasOriginals(of: fixture.visit.record))
    XCTAssertFalse(fixture.builder.hasOriginals(of: Make.record([])))
  }

  /// The legacy fixture package, copied into the workspace's packages folder read-only.
  private func legacyCopy(in workspace: VisitWorkspace) throws -> SealedPackage {
    let manifest = try FixtureVisit.manifest(of: Fixtures.package("legacy-1.0.0"))
    let root = workspace.packageURL(packageId: manifest.packageId.rawValue)
    try FileManager.default.createDirectory(
      at: workspace.packagesRoot, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: Fixtures.package("legacy-1.0.0"), to: root)
    return try SealedPackage.open(at: root)
  }
}

final class PendingUploadsTests: XCTestCase {
  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDownWithError() throws {
    if let base { Fixtures.removeTemporaryDirectory(base) }
  }

  func testSupersededPackagesAreNeverResumed() throws {
    let fixture = try SealedFixture(in: base)
    XCTAssertEqual(PendingUploads.find(visitsRoot: base).count, 1)
    var state = UploadState(package: fixture.sealed, dealId: "D")
    state.supersededBy = LowercaseUUID()
    try UploadStateStore(url: UploadStateStore.defaultURL(forPackageAt: fixture.sealed.root)).save(state)
    XCTAssertTrue(PendingUploads.find(visitsRoot: base).isEmpty)
  }

  func testLegacyPackagesAreStillFound() throws {
    let workspace = try VisitWorkspace.create(in: base)
    let manifest = try FixtureVisit.manifest(of: Fixtures.package("legacy-1.0.0"))
    try FileManager.default.createDirectory(at: workspace.packagesRoot, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
      at: Fixtures.package("legacy-1.0.0"),
      to: workspace.packageURL(packageId: manifest.packageId.rawValue))
    let pending = PendingUploads.find(visitsRoot: base)
    XCTAssertEqual(pending.map(\.package.packageId), [manifest.packageId])
    XCTAssertEqual(pending.first?.package.manifest.schemaVersion, .v1)
    XCTAssertNotNil(pending.first?.dealId)
  }
}
