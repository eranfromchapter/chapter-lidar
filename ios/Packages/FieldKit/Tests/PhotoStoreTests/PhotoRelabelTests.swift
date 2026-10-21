import CaptureContract
import FieldRules
import Foundation
import PhotoStore
import XCTest

/// Photos follow a room rename: only the record's room label changes, never the photo file.
final class PhotoRelabelTests: XCTestCase {
  private let floor1 = FieldControls.CaptureRef(
    captureId: LowercaseUUID(rawValue: "3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35")!, areaKey: "floor-1")
  private let floor2 = FieldControls.CaptureRef(
    captureId: LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!, areaKey: "floor-2")
  private let takenAt = UTCTimestamp(rawValue: "2026-10-17T14:30:00Z")!

  private func jpeg(_ seed: UInt8) -> Data {
    var bytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x08] + Array("Exif".utf8) + [0, 0]
    bytes += (0..<64).map { UInt8(truncatingIfNeeded: Int($0) &* 7 &+ Int(seed)) }
    return Data(bytes + [0xFF, 0xD9])
  }

  @discardableResult
  private func save(
    _ store: PhotoRecordStore, _ capture: FieldControls.CaptureRef, room: String, seed: UInt8
  ) throws -> PhotoRecord {
    try store.save(
      original: jpeg(seed), capture: capture,
      labels: PackageManifest.PhotoLabels(
        room: room, direction: .east, subject: .fixture, takenAt: takenAt))
  }

  func testRecordsWithTheOldNameTakeTheNewOneAndFilesStayUntouched() throws {
    let files = InMemoryPhotoFileStore()
    let store = try PhotoRecordStore(files: files)
    let closet = try save(store, floor1, room: "Closet", seed: 1)
    try save(store, floor1, room: "Bedroom", seed: 2)
    try save(store, floor1, room: "  closet ", seed: 3)
    try save(store, floor2, room: "Closet", seed: 4)
    let photoFiles = files.paths.filter { $0.hasPrefix("Site Photos/") }
    let bytes = try photoFiles.map { try files.read(relativePath: $0) }

    let changed = try store.relabelRoom(captureId: floor1.captureId, from: "CLOSET", to: " Shower ")
    // Same normalisation as the checklist: trimmed, ignoring case.
    XCTAssertEqual(changed.map(\.sequence), [1, 3])
    XCTAssertEqual(changed.map(\.room), ["Shower", "Shower"])
    XCTAssertEqual(store.records.map(\.room), ["Shower", "Bedroom", "Shower", "Closet"], "other capture untouched")

    // Everything else of the record is the same: path, fingerprint, direction, subject, time.
    var expected = closet
    expected.labels.room = "Shower"
    XCTAssertEqual(store.records[0], expected)
    XCTAssertEqual(files.paths.filter { $0.hasPrefix("Site Photos/") }, photoFiles, "no file added, moved or removed")
    XCTAssertEqual(try photoFiles.map { try files.read(relativePath: $0) }, bytes, "originals byte for byte")
    XCTAssertTrue(store.records.allSatisfy(store.isIntact))

    // Written to photo-records.json: a reopened store has the new labels.
    XCTAssertEqual(try PhotoRecordStore(files: files).records, store.records)
    XCTAssertEqual(store.nextSequence(captureId: floor1.captureId), 4, "numbering unchanged")
  }

  func testRelabelAndRestoreKeepTheDirectionSource() throws {
    let files = InMemoryPhotoFileStore()
    let store = try PhotoRecordStore(files: files)
    let saved = try store.save(
      original: jpeg(9), capture: floor1,
      labels: PackageManifest.PhotoLabels(
        room: "Closet", direction: .south, subject: .fixture, takenAt: takenAt,
        directionSource: .compass))
    let before = store.records
    try store.relabelRoom(captureId: floor1.captureId, from: "Closet", to: "Shower")
    XCTAssertEqual(store.records[0].room, "Shower")
    XCTAssertEqual(store.records[0].labels.directionSource, .compass)
    XCTAssertEqual(try PhotoRecordStore(files: files).records[0].labels.directionSource, .compass)
    try store.restoreLabels(before)
    XCTAssertEqual(store.records[0].labels, saved.labels)
    XCTAssertTrue(store.isIntact(store.records[0]))
  }

  func testRenamesApplyAtOnceSoTwoRoomsCanSwap() throws {
    let store = try PhotoRecordStore(files: InMemoryPhotoFileStore())
    try save(store, floor1, room: "Bathroom", seed: 1)
    try save(store, floor1, room: "Closet", seed: 2)
    try store.relabelRooms(
      captureId: floor1.captureId, renames: [(from: "Bathroom", to: "Closet"), (from: "Closet", to: "Bathroom")])
    XCTAssertEqual(store.records.map(\.room), ["Closet", "Bathroom"])
  }

  /// The renames of two captures in one write: both or neither.
  func testSeveralCapturesAreRelabeledInOneWrite() throws {
    let files = CountingFileStore()
    let store = try PhotoRecordStore(files: files)
    try save(store, floor1, room: "Closet", seed: 1)
    try save(store, floor2, room: "Hall", seed: 2)
    try save(store, floor2, room: "Closet", seed: 3)
    let writes = files.indexWrites
    let changed = try store.relabelRooms([
      floor1.captureId: [(from: "Closet", to: "Shower")],
      floor2.captureId: [(from: "Hall", to: "Entry")],
    ])
    XCTAssertEqual(changed.map(\.room), ["Shower", "Entry"])
    XCTAssertEqual(store.records.map(\.room), ["Shower", "Entry", "Closet"])
    XCTAssertEqual(files.indexWrites, writes + 1, "one write of photo-records.json")

    // The write fails: no capture is relabeled, in memory or on disk.
    files.failIndexWrites = true
    XCTAssertThrowsError(
      try store.relabelRooms([
        floor1.captureId: [(from: "Shower", to: "Steam room")],
        floor2.captureId: [(from: "Entry", to: "Foyer")],
      ]))
    XCTAssertEqual(store.records.map(\.room), ["Shower", "Entry", "Closet"])
    files.failIndexWrites = false
    XCTAssertEqual(try PhotoRecordStore(files: files).records.map(\.room), ["Shower", "Entry", "Closet"])
  }

  /// Review of 2026-10-20: undoing a relabel by relabeling backwards also renamed a photo that
  /// already had the new name ("Shower", typed in "Other room") and changed "closet" to
  /// "Closet". `restoreLabels` puts back exactly the labels there were.
  func testRestoreLabelsPutsBackExactlyThePreviousLabels() throws {
    let files = InMemoryPhotoFileStore()
    let store = try PhotoRecordStore(files: files)
    try save(store, floor1, room: "Closet", seed: 1)
    try save(store, floor1, room: "Shower", seed: 2)
    try save(store, floor1, room: "closet", seed: 3)
    let before = store.records
    try store.relabelRoom(captureId: floor1.captureId, from: "Closet", to: "Shower")
    XCTAssertEqual(store.records.map(\.room), ["Shower", "Shower", "Shower"])

    // A photo saved after the relabel keeps its own label.
    try save(store, floor1, room: "Shower", seed: 4)
    try store.restoreLabels(before)
    XCTAssertEqual(store.records.map(\.room), ["Closet", "Shower", "closet", "Shower"])
    XCTAssertEqual(Array(store.records.prefix(3)), before)
    XCTAssertEqual(try PhotoRecordStore(files: files).records, store.records, "written")
    XCTAssertTrue(store.records.allSatisfy(store.isIntact))

    // Nothing to put back: the index is not rewritten.
    let index = try files.read(relativePath: PhotoRecordStore.indexPath)
    try store.restoreLabels(store.records)
    XCTAssertEqual(try files.read(relativePath: PhotoRecordStore.indexPath), index)
  }

  func testNothingChangesForANameNotInUseOrAnInvalidName() throws {
    let files = InMemoryPhotoFileStore()
    let store = try PhotoRecordStore(files: files)
    try save(store, floor1, room: "Bedroom", seed: 1)
    let index = try files.read(relativePath: PhotoRecordStore.indexPath)
    XCTAssertEqual(try store.relabelRoom(captureId: floor1.captureId, from: "Closet", to: "Shower"), [])
    XCTAssertEqual(try store.relabelRoom(captureId: floor1.captureId, from: "Bedroom", to: "Bedroom"), [])
    for invalid in ["", "   ", String(repeating: "x", count: 101)] {
      XCTAssertThrowsError(try store.relabelRoom(captureId: floor1.captureId, from: "Bedroom", to: invalid)) {
        XCTAssertEqual($0 as? PhotoStoreError, .invalidRoom)
      }
    }
    XCTAssertEqual(store.records.map(\.room), ["Bedroom"])
    XCTAssertEqual(try files.read(relativePath: PhotoRecordStore.indexPath), index, "index not rewritten")
    // A case-only rename is a change of the label.
    XCTAssertEqual(try store.relabelRoom(captureId: floor1.captureId, from: "Bedroom", to: "bedroom").count, 1)
    XCTAssertEqual(store.records.map(\.room), ["bedroom"])
  }
}

/// Files in memory that count the writes of the photo index and can refuse them.
private final class CountingFileStore: PhotoFileStore, @unchecked Sendable {
  private let files = InMemoryPhotoFileStore()
  private(set) var indexWrites = 0
  var failIndexWrites = false

  struct Refused: Error {}

  func write(_ data: Data, toRelativePath path: String, replacingExisting: Bool) throws {
    if path == PhotoRecordStore.indexPath {
      if failIndexWrites { throw Refused() }
      indexWrites += 1
    }
    try files.write(data, toRelativePath: path, replacingExisting: replacingExisting)
  }

  func read(relativePath path: String) throws -> Data { try files.read(relativePath: path) }
  func exists(relativePath path: String) -> Bool { files.exists(relativePath: path) }
  func remove(relativePath path: String) throws { try files.remove(relativePath: path) }
}
