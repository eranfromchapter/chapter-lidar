import CaptureContract
import CaptureCore
import FieldRules
import Foundation
import PackageCore
import PhotoStore
import XCTest

@testable import AppCore

/// The owner's visits on the phone survive the update: workspaces the v1 app itself wrote
/// (`Fixtures/v1-visits`: manifest and capture record 1.0.0 with the retired phone report, upload
/// state `formatVersion` 1, a draft, scans without a capture record, room names) are listed on
/// the Captures home, migrated to `visit.json` without moving or deleting a file, and reopen
/// with their field controls, photos and room names.
final class V1VisitFixtureTests: XCTestCase {
  private var root: URL!
  private let utc = TimeZone(identifier: "UTC")!

  /// `f6b847e1`: sealed, uploaded, checks queued.
  private let uploaded = "f6b847e1-fb8e-440b-8238-d580b8294691"
  /// `6da18f1c`: the same visit sealed, never uploaded.
  private let neverUploaded = "6da18f1c-3747-4b77-a29f-9a0004dfef42"
  /// `93d1fdf7`: two floors at "Package ready", not sealed.
  private let drafted = "93d1fdf7-13d5-49be-8c18-fdf983ed8711"
  /// `5bf80999`: two scans, no capture record.
  private let scansOnly = "5bf80999-3fb4-4fa8-85d7-1e702ee3a0a6"
  /// An empty folder, as the v1 app made at every launch.
  private let empty = "1dec1151-97f2-4c6c-a8e8-17098723821b"

  /// `Fixtures/v1-visits`, next to this file.
  private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/v1-visits", isDirectory: true)

  override func setUpWithError() throws {
    let base = try Fixtures.temporaryDirectory()
    root = base.appendingPathComponent("FieldTestVisits", isDirectory: true)
    try FileManager.default.copyItem(at: Self.fixture, to: root)
    try FileManager.default.removeItem(at: root.appendingPathComponent("README.md"))
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent(empty, isDirectory: true), withIntermediateDirectories: true)
  }

  override func tearDown() {
    Fixtures.removeTemporaryDirectory(root.deletingLastPathComponent())
  }

  private func workspace(_ id: String) -> VisitWorkspace {
    VisitWorkspace(root: root.appendingPathComponent(id, isDirectory: true))
  }

  /// Every file of the visits folder with its bytes.
  private func files() throws -> [String: Data] {
    var files: [String: Data] = [:]
    let prefix = root.resolvingSymlinksInPath().path
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    while let url = enumerator?.nextObject() as? URL {
      guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
        continue
      }
      let path = url.resolvingSymlinksInPath().path
      files[String(path.dropFirst(prefix.count))] = try Data(contentsOf: url)
    }
    return files
  }

  func testTheFixtureIsWhatTheV1AppWrote() throws {
    let package = try XCTUnwrap(VisitStore.sealedPackages(of: workspace(uploaded)).first)
    XCTAssertEqual(package.manifest.schemaVersion.rawValue, "1.0.0")
    XCTAssertTrue(package.manifest.files.contains { $0.role == .spatialReportPDF })
    XCTAssertEqual(SealedPackageSummary.captureRecord(of: package)?.schemaVersion.rawValue, "1.0.0")
    let state = try Data(
      contentsOf: UploadStateStore.defaultURL(forPackageAt: package.root))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: state) as? [String: Any])
    XCTAssertEqual(json["formatVersion"] as? Int, 1)
    for id in [uploaded, neverUploaded, drafted, scansOnly, empty] {
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: workspace(id).visitURL.path), "\(id): no visit.json")
    }
  }

  func testTheCapturesHomeListsEveryV1Visit() throws {
    let state = CaptureLibrary.load(visitsRoot: root, operatorName: "Field test", timeZone: utc)
    XCTAssertTrue(state.sealed.isEmpty, "no verdict yet")
    let rows = Dictionary(uniqueKeysWithValues: state.inProgress.map { ($0.id, $0) })
    XCTAssertEqual(
      Set(rows.keys), [uploaded, neverUploaded, drafted, scansOnly], "the empty one is left out")

    let confirmed = try XCTUnwrap(rows[uploaded])
    XCTAssertEqual(confirmed.title, "Fixture box-room")
    XCTAssertEqual(confirmed.subtitle, "1 room · uploaded · checks running")
    XCTAssertEqual(confirmed.status, RowStatusValue(.waiting, "Checking"))

    let waiting = try XCTUnwrap(rows[neverUploaded])
    XCTAssertTrue(waiting.subtitle.hasPrefix("1 room · uploading · "), waiting.subtitle)
    XCTAssertEqual(waiting.progress, 0, "its upload resumes from the start")

    let draft = try XCTUnwrap(rows[drafted])
    XCTAssertEqual(draft.subtitle, "2 floors · not sealed yet")
    XCTAssertEqual(draft.destination, .overview)

    let scans = try XCTUnwrap(rows[scansOnly])
    XCTAssertTrue(scans.title.hasPrefix("Scan of "), scans.title)
    XCTAssertEqual(scans.subtitle, "2 scans · no HUB project recorded")
    XCTAssertTrue(try XCTUnwrap(CaptureLibrary.visit(workspace(scansOnly))).isLegacyScansOnly)
  }

  func testMigrationWritesVisitJSONAndMovesNothing() throws {
    let before = try files()
    _ = CaptureLibrary.visits(visitsRoot: root)
    let after = try files()
    let written = Set(after.keys).subtracting(before.keys)
    XCTAssertEqual(
      written,
      ["/\(uploaded)/visit.json", "/\(neverUploaded)/visit.json", "/\(drafted)/visit.json"])
    for (path, data) in before {
      XCTAssertEqual(after[path], data, "\(path) is unchanged")
    }
    // A second read finds the files and writes nothing more.
    _ = CaptureLibrary.visits(visitsRoot: root)
    XCTAssertEqual(try files(), after)
  }

  func testASealedV1VisitOpensReadOnlyWithAllRoomsScanned() throws {
    let workspace = workspace(uploaded)
    let file = try XCTUnwrap(VisitStore.loadOrMigrate(workspace))
    XCTAssertTrue(file.isSealed)
    XCTAssertNil(file.revision)
    XCTAssertEqual(file.record.schemaVersion.rawValue, "1.0.0", "the record is kept as sealed")
    XCTAssertEqual(
      file.noRoomsSkipped.confirmedCaptureIds, Set(file.record.captures.map(\.captureId)),
      "the v1 app sealed only once Rooms not scanned passed")

    let packages = VisitStore.sealedPackages(of: workspace)
    let flow = file.flow(sealedRevision: packages.last?.manifest.revision)
    XCTAssertTrue(flow.isReadOnly)
    XCTAssertEqual(flow.revision, 1)
    XCTAssertTrue(flow.noRoomsSkippedConfirmed)
    let controls = try XCTUnwrap(
      try VisitStore.loadControls(workspace, visitId: file.record.visitId))
    let checklist = ChecklistRules.evaluate(
      ChecklistInput(
        record: file.record, capturedRooms: [:], photos: [], controls: controls,
        noRoomsSkippedConfirmed: flow.noRoomsSkippedConfirmed),
      policy: .shipping)
    let skipped = try XCTUnwrap(checklist.item(.skippedRoomsRecorded))
    XCTAssertTrue(skipped.passed, "no ■ Missing that a read-only visit cannot fix")
    XCTAssertEqual(skipped.detail, "All rooms scanned")
    XCTAssertNil(try StationStatusStore(packageRoot: packages[0].root).load())
  }

  func testADraftedV1VisitResumesWithItsControlsPhotosAndRoomNames() throws {
    let workspace = workspace(drafted)
    let file = try XCTUnwrap(VisitStore.loadOrMigrate(workspace))
    XCTAssertFalse(file.isSealed)
    XCTAssertEqual(file.record.captures.map(\.label), ["Floor 1", "Floor 2"])
    XCTAssertEqual(file.noRoomsSkipped, NoRoomsSkippedConfirmation(), "asked again")
    let flow = file.flow(sealedRevision: nil)
    XCTAssertFalse(flow.isReadOnly)
    XCTAssertEqual(flow.step, .overview)

    let controls = try VisitStore.loadControls(workspace, visitId: file.record.visitId)
    XCTAssertEqual(controls?.visitId, file.record.visitId)
    let photos = try PhotoRecordStore(files: DiskPhotoFileStore(root: workspace.photosRoot))
    XCTAssertEqual(photos.records.count, 2)
    let names = try VisitRoomNames.load(from: workspace)
    let floor1 = try XCTUnwrap(file.record.captures.first?.captureId)
    XCTAssertEqual(names.names(for: floor1).map(\.name), ["Shower"])
  }

  func testV1ScansWithoutACaptureRecordStayScans() throws {
    let workspace = workspace(scansOnly)
    XCTAssertNil(VisitStore.loadOrMigrate(workspace), "no capture record is made up")
    XCTAssertEqual(
      Set(VisitStore.legacyScans(of: workspace).map(\.areaKey)), ["floor-1", "floor-2"])
    XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.visitURL.path))
  }
}
