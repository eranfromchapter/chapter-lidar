import CaptureContract
import FieldRules
import Foundation
import PhotoStore
import XCTest

/// AC3: a saved photo record has room, direction and subject, and the original file bytes are
/// unchanged. Uses an injected in-memory file store and test image bytes.
final class PhotoRecordTests: XCTestCase {
  private let floor1 = FieldControls.CaptureRef(
    captureId: LowercaseUUID(rawValue: "3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35")!, areaKey: "floor-1")
  private let floor2 = FieldControls.CaptureRef(
    captureId: LowercaseUUID(rawValue: "a81d5f03-6c2e-4b97-8d14-2f9e7b3c5a60")!, areaKey: "floor-2")
  private let takenAt = UTCTimestamp(rawValue: "2026-10-17T14:30:00Z")!

  /// A JPEG-shaped file with an EXIF APP1 segment: SOI, APP1("Exif"), a body, EOI. Bytes the
  /// store must never alter (a re-encode or metadata strip would change or drop them).
  private func jpegBytes(seed: UInt8 = 7) -> Data {
    var bytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x16]
    bytes +=
      Array("Exif".utf8) + [0x00, 0x00] + Array("MM".utf8) + [0x00, 0x2A, 0x00, 0x00, 0x00, 0x08]
    bytes += [0x00, 0x00, 0x00, 0x00]
    bytes += (0..<200).map { UInt8(truncatingIfNeeded: Int($0) &* 31 &+ Int(seed)) }
    bytes += [0xFF, 0xD9]
    return Data(bytes)
  }

  /// A HEIC-shaped file: an `ftyp` box with brand `heic`, then arbitrary payload.
  private func heicBytes() -> Data {
    var bytes: [UInt8] = [0x00, 0x00, 0x00, 0x18] + Array("ftypheic".utf8)
    bytes += [0x00, 0x00, 0x00, 0x00] + Array("mif1heic".utf8)
    bytes += (0..<120).map { UInt8(truncatingIfNeeded: Int($0) &* 13 &+ 5) }
    return Data(bytes)
  }

  private func labels(
    room: String = "Kitchen", direction: PhotoDirection = .east, subject: PhotoSubject = .cabinetry
  ) -> PackageManifest.PhotoLabels {
    PackageManifest.PhotoLabels(
      room: room, direction: direction, subject: subject, takenAt: takenAt)
  }

  func testSavedRecordHasRoomDirectionAndSubject() throws {
    let files = InMemoryPhotoFileStore()
    let store = try PhotoRecordStore(files: files)
    let record = try store.save(
      original: jpegBytes(), capture: floor1,
      labels: labels(room: "Kitchen", direction: .east, subject: .cabinetry))

    XCTAssertEqual(record.room, "Kitchen")
    XCTAssertEqual(record.direction, .east)
    XCTAssertEqual(record.subject, .cabinetry)
    XCTAssertEqual(record.takenAt, takenAt)
    XCTAssertEqual(record.captureId, floor1.captureId)
    XCTAssertEqual(record.areaKey, "floor-1")
    XCTAssertEqual(record.sequence, 1)
    XCTAssertEqual(record.format, .jpeg)
    XCTAssertEqual(record.mime, "image/jpeg")
    XCTAssertEqual(
      record.path, "Site Photos/floor-1/3f6c2a9e-8b1d-4c57-9e2a-6d4b1f0c7a35/photo-0001.jpg")
    XCTAssertEqual(store.records, [record])

    // The record encodes the three labels with the contract's wire names.
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: try CaptureContractJSON.makeEncoder().encode(record)) as? [String: Any])
    let encoded = try XCTUnwrap(json["labels"] as? [String: Any])
    XCTAssertEqual(encoded["room"] as? String, "Kitchen")
    XCTAssertEqual(encoded["direction"] as? String, "E")
    XCTAssertEqual(encoded["subject"] as? String, "cabinetry")
    XCTAssertEqual(encoded["takenAt"] as? String, "2026-10-17T14:30:00Z")
  }

  func testOriginalFileBytesAreUnchanged() throws {
    let files = InMemoryPhotoFileStore()
    let store = try PhotoRecordStore(files: files)
    let original = jpegBytes()
    let record = try store.save(original: original, capture: floor1, labels: labels())

    // The stored file is byte-for-byte what the camera delivered, EXIF segment included.
    let stored = try files.read(relativePath: record.path)
    XCTAssertEqual(stored, original)
    XCTAssertEqual(try store.originalData(for: record), original)
    XCTAssertEqual(record.bytes, Int64(original.count))
    XCTAssertEqual(record.sha256, SHA256.hexDigest(of: original))
    XCTAssertEqual(Array(stored.prefix(4)), [0xFF, 0xD8, 0xFF, 0xE1])
    XCTAssertNotNil(stored.range(of: Data("Exif".utf8)))
    XCTAssertTrue(store.isIntact(record))

    // Saving more photos never rewrites an earlier one.
    _ = try store.save(
      original: jpegBytes(seed: 9), capture: floor1, labels: labels(room: "Living"))
    XCTAssertEqual(try files.read(relativePath: record.path), original)

    // Any later change is detected.
    try files.write(Data(original.dropLast()), toRelativePath: record.path, replacingExisting: true)
    XCTAssertFalse(store.isIntact(record))
  }

  func testHEICIsKeptAsHEIC() throws {
    let files = InMemoryPhotoFileStore()
    let store = try PhotoRecordStore(files: files)
    let original = heicBytes()
    let record = try store.save(original: original, capture: floor2, labels: labels(room: "Bath 2"))
    XCTAssertEqual(record.format, .heic)
    XCTAssertEqual(record.mime, "image/heic")
    XCTAssertTrue(record.path.hasSuffix("/photo-0001.heic"))
    XCTAssertEqual(try files.read(relativePath: record.path), original)
  }

  func testPhotosAreNumberedPerCaptureAndSurviveReopening() throws {
    let files = InMemoryPhotoFileStore()
    var store = try PhotoRecordStore(files: files)
    XCTAssertEqual(store.nextSequence(captureId: floor1.captureId), 1)
    _ = try store.save(original: jpegBytes(seed: 1), capture: floor1, labels: labels())
    _ = try store.save(original: jpegBytes(seed: 2), capture: floor1, labels: labels())
    let other = try store.save(original: jpegBytes(seed: 3), capture: floor2, labels: labels())
    XCTAssertEqual(other.sequence, 1)
    XCTAssertEqual(store.nextSequence(captureId: floor1.captureId), 3)
    XCTAssertEqual(store.records(captureId: floor1.captureId).map(\.sequence), [1, 2])

    let saved = store.records
    store = try PhotoRecordStore(files: files)
    XCTAssertEqual(store.records, saved)
    XCTAssertEqual(store.nextSequence(captureId: floor1.captureId), 3)

    try files.write(
      Data("not json".utf8), toRelativePath: PhotoRecordStore.indexPath, replacingExisting: true)
    XCTAssertThrowsError(try PhotoRecordStore(files: files)) {
      XCTAssertEqual($0 as? PhotoStoreError, .corruptIndex)
    }
  }

  func testSavingFromTheLabelingScreenNeedsAllThreeLabels() throws {
    let store = try PhotoRecordStore(files: InMemoryPhotoFileStore())
    var draft = PhotoLabelDraft(room: "Kitchen")
    XCTAssertThrowsError(
      try store.save(original: jpegBytes(), capture: floor1, draft: draft, takenAt: takenAt)
    ) { XCTAssertEqual($0 as? PhotoStoreError, .incompleteLabels([.direction, .subject])) }
    XCTAssertTrue(store.records.isEmpty)

    draft.direction = .north
    draft.subject = .defect
    let record = try store.save(
      original: jpegBytes(), capture: floor1, draft: draft, takenAt: takenAt)
    XCTAssertEqual(record.labels.direction, .north)
    XCTAssertEqual(record.labels.subject, .defect)
  }

  func testNothingIsStoredWhenTheSaveIsRefused() throws {
    let files = InMemoryPhotoFileStore()
    let store = try PhotoRecordStore(files: files)
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    XCTAssertThrowsError(try store.save(original: png, capture: floor1, labels: labels())) {
      XCTAssertEqual($0 as? PhotoStoreError, .notAPhoto)
    }
    XCTAssertThrowsError(try store.save(original: Data(), capture: floor1, labels: labels())) {
      XCTAssertEqual($0 as? PhotoStoreError, .notAPhoto)
    }
    XCTAssertThrowsError(
      try store.save(original: jpegBytes(), capture: floor1, labels: labels(room: "   "))
    ) { XCTAssertEqual($0 as? PhotoStoreError, .invalidRoom) }
    XCTAssertThrowsError(
      try store.save(
        original: jpegBytes(),
        capture: FieldControls.CaptureRef(captureId: floor1.captureId, areaKey: "../x"),
        labels: labels())
    ) { XCTAssertEqual($0 as? PhotoStoreError, .invalidAreaKey("../x")) }
    XCTAssertTrue(store.records.isEmpty)
    XCTAssertEqual(files.paths, [])
  }

  func testDiskStoreWritesTheSameBytesAndRefusesEscapingPaths() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("photo-store-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try PhotoRecordStore(files: DiskPhotoFileStore(root: root))
    let original = heicBytes()
    let record = try store.save(original: original, capture: floor1, labels: labels())
    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(record.path)), original)

    let disk = DiskPhotoFileStore(root: root)
    XCTAssertThrowsError(
      try disk.write(Data([1]), toRelativePath: "../escape", replacingExisting: false))
    XCTAssertThrowsError(
      try disk.write(original, toRelativePath: record.path, replacingExisting: false)
    ) {
      XCTAssertEqual($0 as? PhotoStoreError, .fileExists(record.path))
    }
    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(record.path)), original)
  }

  func testFormatDetection() {
    XCTAssertEqual(PhotoFormat.detect(jpegBytes()), .jpeg)
    XCTAssertEqual(PhotoFormat.detect(heicBytes()), .heic)
    XCTAssertNil(PhotoFormat.detect(Data([0xFF, 0xD8])))
    XCTAssertNil(PhotoFormat.detect(Data("%PDF-1.7 not a photo".utf8)))
  }
}
