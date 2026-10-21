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

  func testRenamesApplyAtOnceSoTwoRoomsCanSwap() throws {
    let store = try PhotoRecordStore(files: InMemoryPhotoFileStore())
    try save(store, floor1, room: "Bathroom", seed: 1)
    try save(store, floor1, room: "Closet", seed: 2)
    try store.relabelRooms(
      captureId: floor1.captureId, renames: [(from: "Bathroom", to: "Closet"), (from: "Closet", to: "Bathroom")])
    XCTAssertEqual(store.records.map(\.room), ["Closet", "Bathroom"])
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
