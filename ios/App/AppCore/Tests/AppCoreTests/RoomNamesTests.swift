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
    let closet = RoomFootprint(areaM2: 1.85, centerX: 0.8, centerZ: 5.3)
    names.setName(" Shower ", roomId: "room-3", derivedLabel: "Closet", footprint: closet, captureId: captureId)
    names.setName("Bedroom", roomId: "room-1", derivedLabel: "Bedroom", footprint: nil, captureId: captureId)
    XCTAssertEqual(
      names.names(for: captureId),
      [RoomName(roomId: "room-3", derivedLabel: "Closet", name: "Shower", footprint: closet)],
      "the derived label itself is no name")
    try names.save(to: workspace)
    XCTAssertEqual(workspace.roomNamesURL, workspace.root.appendingPathComponent("room-names.json"))
    XCTAssertEqual(try VisitRoomNames.load(from: VisitWorkspace(root: workspace.root)), names)

    // Renaming again replaces the entry; a blank name removes it.
    names.setName("Steam shower", roomId: "room-3", derivedLabel: "Closet", footprint: closet, captureId: captureId)
    XCTAssertEqual(names.names(for: captureId).map(\.name), ["Steam shower"])
    names.setName("  ", roomId: "room-3", derivedLabel: "Closet", footprint: closet, captureId: captureId)
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
      sheet.changes, captures: visit.record.captures, visitId: visit.record.visitId, photos: photos
    ).models
    XCTAssertEqual(models[capture.captureId]?.rooms.map(\.label), ["Shower"])
    XCTAssertEqual(models[capture.captureId]?.rooms.map(\.type), [.bathroom])
    XCTAssertEqual(models[capture.captureId]?.rooms.map(\.typeSource), [.operator])
    XCTAssertEqual(rooms.labels(of: capture.captureId), ["Shower"])
    // Kept with where the room is: the 4 x 3 m box room.
    let saved = try XCTUnwrap(rooms.names.names(for: capture.captureId).first)
    XCTAssertEqual(saved.footprint?.areaM2 ?? 0, 12, accuracy: 0.01)
    XCTAssertEqual(saved.footprint, rooms.rooms[capture.captureId]?.first?.footprint)
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
    names.setName("Shower", roomId: "room-1", derivedLabel: "Closet", footprint: nil, captureId: capture.captureId)
    names.setName("Pantry", roomId: "room-2", derivedLabel: "Room 2", footprint: nil, captureId: capture.captureId)
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

  // MARK: Review of 2026-10-20

  private func ref(_ capture: CaptureRecord.Capture) -> FieldControls.CaptureRef {
    FieldControls.CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey)
  }

  private func save(
    _ photos: PhotoRecordStore, _ capture: CaptureRecord.Capture, room: String, from visit: FixtureVisit
  ) throws {
    try photos.save(
      original: try photos.originalData(for: visit.photos[0]), capture: ref(capture),
      labels: PackageManifest.PhotoLabels(
        room: room, direction: .north, subject: .general, takenAt: visit.photos[0].takenAt))
  }

  private func measurement() -> FieldControls.Measurement {
    FieldControls.Measurement(
      valueMm: 2400, enteredUnit: .mm, enteredText: "2400", method: .tape,
      recordedAt: UTCTimestamp(rawValue: "2026-10-20T18:00:00Z")!)
  }

  /// A control measured in the room before the rename takes the new name, so the package's
  /// controls name the capture model's room (the field-controls schema) and the station's scale
  /// check finds the room a distance spans.
  func testControlsMeasuredInTheRoomFollowTheRename() throws {
    let visit = try FixtureVisit("box-room", in: base)
    let capture = try capture(visit)
    let photos = try PhotoRecordStore(files: DiskPhotoFileStore(root: visit.workspace.photosRoot))
    var editor = FieldControlsEditor(visitId: visit.record.visitId)
    try editor.setDistance(
      capture: ref(capture), axis: .a, from: "Room 1 west wall", to: "Room 1 east wall",
      measurement: measurement())
    try editor.setCeilingHeight(capture: ref(capture), room: "room 1", measurement: measurement())
    var rooms = VisitRooms(builder: VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0"))
    try rooms.load(capture, visitId: visit.record.visitId)

    var written: [FieldControls] = []
    let result = try rooms.rename(
      [RoomRename(captureId: capture.captureId, roomId: "room-1", scannedLabel: "Room 1", from: "Room 1", to: "Shower")],
      captures: visit.record.captures, visitId: visit.record.visitId, photos: photos,
      controls: editor.controls, writeControls: { written.append($0) })
    let controls = try XCTUnwrap(result.controls)
    XCTAssertEqual(written, [controls])
    XCTAssertEqual(controls.distances.map(\.from), ["Shower west wall"])
    XCTAssertEqual(controls.distances.map(\.to), ["Shower east wall"])
    XCTAssertEqual(controls.ceilingHeights.map(\.room), ["Shower"])
    XCTAssertEqual(FieldControlsValidator.issues(for: controls, knownCaptures: [ref(capture)]), [])

    // A rename no control names writes no controls.
    written = []
    let again = try rooms.rename(
      [RoomRename(captureId: capture.captureId, roomId: "room-1", scannedLabel: "Room 1", from: "Shower", to: "Steam room")],
      captures: visit.record.captures, visitId: visit.record.visitId, photos: photos,
      controls: FieldControlsEditor(visitId: visit.record.visitId).controls, writeControls: { written.append($0) })
    XCTAssertNil(again.controls)
    XCTAssertEqual(written, [])
  }

  /// A step that fails undoes the steps before it exactly: the photo labels come back as they
  /// were (also a photo already called by the new name, and one in lower case), and so does
  /// the names file.
  func testAFailedStepPutsBackExactlyWhatWasThere() throws {
    let visit = try FixtureVisit("box-room", in: base)
    let capture = try capture(visit)
    let files = RefusingFileStore(root: visit.workspace.photosRoot)
    let photos = try PhotoRecordStore(files: files)
    try save(photos, capture, room: "Room 1", from: visit)
    try save(photos, capture, room: "Shower", from: visit)  // typed in "Other room" earlier
    try save(photos, capture, room: "room 1", from: visit)
    let labels = photos.records.map(\.room)
    XCTAssertEqual(labels, ["Test Room", "Room 1", "Shower", "room 1"])
    var editor = FieldControlsEditor(visitId: visit.record.visitId)
    try editor.setCeilingHeight(capture: ref(capture), room: "Room 1", measurement: measurement())
    let builder = VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0")
    var rooms = VisitRooms(builder: builder)
    try rooms.load(capture, visitId: visit.record.visitId)
    // A name given earlier, which must survive the failed rename.
    let earlier = VisitRoomNames(captures: [
      "00000000-0000-4000-8000-00000000abcd": [RoomName(roomId: "room-1", derivedLabel: "Room 1", name: "Den")]
    ])
    try earlier.save(to: visit.workspace)
    rooms = VisitRooms(builder: builder)
    try rooms.load(capture, visitId: visit.record.visitId)
    let shower = RoomRename(
      captureId: capture.captureId, roomId: "room-1", scannedLabel: "Room 1", from: "Room 1", to: "Shower")

    struct Refused: Error {}
    // 1. The controls cannot be written: the photos and the names are put back.
    XCTAssertThrowsError(
      try rooms.rename(
        [shower], captures: visit.record.captures, visitId: visit.record.visitId, photos: photos,
        controls: editor.controls, writeControls: { _ in throw Refused() }))
    XCTAssertEqual(photos.records.map(\.room), labels, "not relabeled backwards: Shower stays, room 1 stays")
    XCTAssertEqual(try PhotoRecordStore(files: files).records.map(\.room), labels, "and on disk")
    XCTAssertEqual(try VisitRoomNames.load(from: visit.workspace), earlier)
    XCTAssertEqual(rooms.labels(of: capture.captureId), ["Room 1"])
    XCTAssertEqual(rooms.names, earlier)

    // 2. The photo index cannot be written: nothing is relabeled, the names are put back.
    files.refuseIndex = true
    XCTAssertThrowsError(
      try rooms.rename(
        [shower], captures: visit.record.captures, visitId: visit.record.visitId, photos: photos))
    files.refuseIndex = false
    XCTAssertEqual(photos.records.map(\.room), labels)
    XCTAssertEqual(try VisitRoomNames.load(from: visit.workspace), earlier)
    XCTAssertEqual(rooms.labels(of: capture.captureId), ["Room 1"])

    // And when nothing fails, it goes through.
    try rooms.rename(
      [shower], captures: visit.record.captures, visitId: visit.record.visitId, photos: photos,
      controls: editor.controls, writeControls: { _ in })
    XCTAssertEqual(photos.records.map(\.room), ["Test Room", "Shower", "Shower", "Shower"])
  }

  /// From the checklist the sheet holds every capture; the renames of both are saved, and their
  /// photos relabeled in one write.
  func testRoomsOfTwoCapturesAreRenamedTogether() throws {
    let visit = try FixtureVisit("two-floor-house", in: base)
    XCTAssertEqual(visit.record.captures.count, 2)
    let photos = try PhotoRecordStore(files: DiskPhotoFileStore(root: visit.workspace.photosRoot))
    var rooms = VisitRooms(builder: VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0"))
    for capture in visit.record.captures {
      try rooms.load(capture, visitId: visit.record.visitId)
      try save(photos, capture, room: try XCTUnwrap(rooms.labels(of: capture.captureId).first), from: visit)
    }
    var sheet = rooms.draft(for: visit.record.captures, photos: photos.records)
    XCTAssertEqual(sheet.captures.count, 2)
    let first = try XCTUnwrap(sheet.captures[0].rooms.first)
    let second = try XCTUnwrap(sheet.captures[1].rooms.first)
    sheet.setName("Front room", room: first.id)
    sheet.setName("Landing", room: second.id)
    let result = try rooms.rename(
      sheet.changes, captures: visit.record.captures, visitId: visit.record.visitId, photos: photos)
    XCTAssertEqual(Set(result.models.keys), Set(visit.record.captures.map(\.captureId)))
    XCTAssertEqual(rooms.labels(of: first.captureId).first, "Front room")
    XCTAssertEqual(rooms.labels(of: second.captureId).first, "Landing")
    XCTAssertEqual(Array(photos.records.suffix(2)).map(\.room), ["Front room", "Landing"])
  }

  /// The sheet says which rooms still need a photo and opens at the room it is asked for.
  func testTheSheetMarksRoomsWithoutAPhotoAndOpensAtTheFocusRoom() throws {
    let visit = try FixtureVisit("box-room", in: base)
    let capture = try capture(visit)
    var rooms = VisitRooms(builder: VisitPackageBuilder(workspace: visit.workspace, appVersion: "1.0.0"))
    try rooms.load(capture, visitId: visit.record.visitId)
    let room = try XCTUnwrap(rooms.draft(for: visit.record.captures).rooms.first)
    // The fixture's photo is labeled "Test Room": Room 1 has none.
    let draft = rooms.draft(
      for: visit.record.captures, photos: visit.photos, focus: (capture.captureId, " room 1"))
    XCTAssertEqual(draft.rooms.map(\.needsPhoto), [true])
    XCTAssertEqual(draft.focusRoomId, room.id)
    XCTAssertNil(rooms.draft(for: visit.record.captures, focus: (capture.captureId, "Garage")).focusRoomId)
    let photo = visit.photos[0]
    var labeled = photo
    labeled.labels.room = "Room 1"
    XCTAssertEqual(rooms.draft(for: visit.record.captures, photos: [labeled]).rooms.map(\.needsPhoto), [false])
  }
}

/// Photo files on disk whose index writes can be refused.
private final class RefusingFileStore: PhotoFileStore, @unchecked Sendable {
  private let disk: DiskPhotoFileStore
  var refuseIndex = false

  struct Refused: Error {}

  init(root: URL) { disk = DiskPhotoFileStore(root: root) }

  func write(_ data: Data, toRelativePath path: String, replacingExisting: Bool) throws {
    if refuseIndex, path == PhotoRecordStore.indexPath { throw Refused() }
    try disk.write(data, toRelativePath: path, replacingExisting: replacingExisting)
  }

  func read(relativePath path: String) throws -> Data { try disk.read(relativePath: path) }
  func exists(relativePath path: String) -> Bool { disk.exists(relativePath: path) }
  func remove(relativePath path: String) throws { try disk.remove(relativePath: path) }
}
