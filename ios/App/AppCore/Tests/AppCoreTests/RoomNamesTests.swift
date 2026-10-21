import CaptureContract
import CaptureModelMapping
import FieldRules
import Foundation
import PhotoStore
import XCTest

@testable import AppCore

/// The operator renames a room (field report 2026-10-20: "Closet" was a shower). The name is
/// kept per visit on the phone, goes into the capture model and the package, and the photos
/// already labeled with the old name follow it.
final class RoomNamesTests: XCTestCase {
  private var base: URL!

  override func setUpWithError() throws {
    base = try Fixtures.temporaryDirectory()
  }

  override func tearDownWithError() throws {
    if let base { try? FileManager.default.removeItem(at: base) }
  }

  private func capture(_ visit: FixtureVisit) throws -> CaptureRecord.Capture {
    try XCTUnwrap(visit.record.captures.first)
  }

  func testNamesSurviveReopeningAndAreKeptOutsideThePackageFolders() throws {
    let workspace = try VisitWorkspace.create(in: base)
    let captureId = try XCTUnwrap(LowercaseUUID(rawValue: "eb6af76e-0000-4000-8000-000000000001"))
    var names = VisitRoomNames()
    names.setName(" Shower ", roomId: "room-3", derivedLabel: "Closet", captureId: captureId)
    names.setName("Bedroom", roomId: "room-1", derivedLabel: "Bedroom", captureId: captureId)
    XCTAssertEqual(
      names.names(for: captureId), [RoomName(roomId: "room-3", derivedLabel: "Closet", name: "Shower")],
      "the derived label itself is no name")
    try names.save(to: workspace)
    XCTAssertEqual(workspace.roomNamesURL, workspace.root.appendingPathComponent("room-names.json"))
    XCTAssertEqual(try VisitRoomNames.load(from: VisitWorkspace(root: workspace.root)), names)

    // Renaming again replaces the entry; a blank name removes it.
    names.setName("Steam shower", roomId: "room-3", derivedLabel: "Closet", captureId: captureId)
    XCTAssertEqual(names.names(for: captureId).map(\.name), ["Steam shower"])
    names.setName("  ", roomId: "room-3", derivedLabel: "Closet", captureId: captureId)
    XCTAssertEqual(names.names(for: captureId), [])
    XCTAssertEqual(names.captures, [:])

    // A visit without names; a file that cannot be read is an error, not an empty list.
    XCTAssertEqual(try VisitRoomNames.load(from: try VisitWorkspace.create(in: base)), VisitRoomNames())
    try Data("not json".utf8).write(to: workspace.roomNamesURL)
    XCTAssertThrowsError(try VisitRoomNames.load(from: workspace))
  }

  func testRenameReachesTheModelThePhotosAndThePackage() throws {
    let visit = try FixtureVisit("box-room", in: base)
    let capture = try capture(visit)
    let builder = VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0")
    let photos = try PhotoRecordStore(files: DiskPhotoFileStore(root: visit.workspace.photosRoot))
    // A second photo labeled with the room's label from the scan, "Room 1".
    let fixturePhoto = try photos.originalData(for: visit.photos[0])
    try photos.save(
      original: fixturePhoto, capture: FieldControls.CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey),
      labels: PackageManifest.PhotoLabels(room: "room 1", direction: .east, subject: .fixture, takenAt: visit.photos[0].takenAt))
    // The scan and photo originals; the photo index is the one file a rename rewrites.
    func originals() throws -> [String: String] {
      try visit.originalDigests().filter { !$0.key.hasSuffix("/" + PhotoRecordStore.indexPath) }
    }
    let digests = try originals()
    XCTAssertEqual(digests.count, 4)

    var rooms = VisitRooms(builder: builder)
    try rooms.load(capture, visitId: visit.record.visitId)
    XCTAssertEqual(rooms.labels(of: capture.captureId), ["Room 1"])
    let draft = rooms.draft(for: visit.record.captures)
    XCTAssertEqual(draft.rooms.map(\.scannedLabel), ["Room 1"])
    XCTAssertEqual(draft.rooms.first?.detail, "12.0 m\u{00B2}", "the 4 x 3 m box room, in the capture's units")

    var sheet = draft
    sheet.setName("Shower", room: try XCTUnwrap(sheet.rooms.first).id)
    let models = try rooms.rename(
      sheet.changes, captures: visit.record.captures, visitId: visit.record.visitId, photos: photos)
    XCTAssertEqual(models[capture.captureId]?.rooms.map(\.label), ["Shower"])
    XCTAssertEqual(models[capture.captureId]?.rooms.map(\.type), [.bathroom])
    XCTAssertEqual(models[capture.captureId]?.rooms.map(\.typeSource), [.operator])
    XCTAssertEqual(rooms.labels(of: capture.captureId), ["Shower"])
    XCTAssertEqual(photos.records.map(\.room), ["Test Room", "Shower"], "only the photo of the old name")
    XCTAssertEqual(try originals(), digests, "no original changed")

    // "Before you leave" with the new name passes for the photo labeled Room 1.
    let report = ChecklistRules.evaluate(
      ChecklistInput(
        record: visit.record, capturedRooms: [capture.captureId: rooms.labels(of: capture.captureId)],
        photos: photos.records, controls: visit.controls, noRoomsSkippedConfirmed: true))
    XCTAssertTrue(report.item(.photoPerRoom).passed, report.item(.photoPerRoom).detail)

    // The names are on disk: a reopened visit maps the same.
    var reopened = VisitRooms(builder: builder)
    try reopened.load(capture, visitId: visit.record.visitId)
    XCTAssertEqual(reopened.labels(of: capture.captureId), ["Shower"])
    XCTAssertEqual(reopened.rooms[capture.captureId]?.first?.derivedLabel, "Room 1")

    // The package: the capture model, the plans drawn from it and the photo labels.
    let plan = try builder.plan(
      record: visit.record, photos: photos.records, controls: visit.controls, roomNames: reopened.names)
    let modelEntry = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .captureModel })
    let model = try CaptureContractJSON.makeDecoder().decode(
      CaptureModel.self, from: Data(contentsOf: modelEntry.input.source))
    XCTAssertEqual(model.rooms.map(\.label), ["Shower"])
    XCTAssertEqual(model.rooms.map(\.typeSource), [.operator])
    let csv = try XCTUnwrap(plan.draft.entries.first { $0.input.role == .roomsCSV })
    XCTAssertTrue(try String(contentsOf: csv.input.source, encoding: .utf8).contains("Shower"))
    XCTAssertEqual(
      plan.draft.entries.filter { $0.input.role == .photo }.compactMap(\.input.photo?.room), ["Test Room", "Shower"])
    XCTAssertFalse(plan.draft.entries.contains { $0.path.hasSuffix(VisitRoomNames.fileName) }, "app-private")
  }

  /// A name given for one split is not applied after the scan splits differently: the entry's
  /// derived label no longer matches the room with its id.
  func testANameForAnotherSplitIsIgnored() throws {
    let visit = try FixtureVisit("box-room", in: base)
    let capture = try capture(visit)
    var names = VisitRoomNames()
    names.setName("Shower", roomId: "room-1", derivedLabel: "Closet", captureId: capture.captureId)
    names.setName("Pantry", roomId: "room-2", derivedLabel: "Room 2", captureId: capture.captureId)
    try names.save(to: visit.workspace)
    var rooms = VisitRooms(builder: VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0"))
    let model = try rooms.load(capture, visitId: visit.record.visitId)
    XCTAssertEqual(model.rooms.map(\.label), ["Room 1"])
    XCTAssertEqual(model.rooms.map(\.typeSource), [nil])
  }

  func testNothingChangesWhenTheNamesCannotBeSaved() throws {
    let visit = try FixtureVisit("box-room", in: base)
    let capture = try capture(visit)
    let builder = VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0")
    let photos = try PhotoRecordStore(files: DiskPhotoFileStore(root: visit.workspace.photosRoot))
    var rooms = VisitRooms(builder: builder)
    try rooms.load(capture, visitId: visit.record.visitId)
    // A folder where the file goes: the write fails.
    try FileManager.default.createDirectory(at: visit.workspace.roomNamesURL, withIntermediateDirectories: true)
    let rename = RoomRename(
      captureId: capture.captureId, roomId: "room-1", scannedLabel: "Room 1", from: "Room 1", to: "Shower")
    XCTAssertThrowsError(
      try rooms.rename([rename], captures: visit.record.captures, visitId: visit.record.visitId, photos: photos))
    XCTAssertEqual(rooms.labels(of: capture.captureId), ["Room 1"])
    XCTAssertEqual(rooms.names, VisitRoomNames())
  }
}
