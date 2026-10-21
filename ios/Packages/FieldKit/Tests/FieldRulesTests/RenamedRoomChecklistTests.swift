import CaptureContract
import FieldRules
import Foundation
import PhotoStore
import XCTest

/// Field report 2026-10-20: a hotel room split into Bedroom, Bathroom and a 1.85 m2 "Closet"
/// that is really a shower. "Before you leave" asked for a Closet photo. After renaming
/// Closet to Shower, the room list says Shower and the photos labeled Closet follow the name.
final class RenamedRoomChecklistTests: XCTestCase {
  private let mexico = Fixtures.floor1

  /// A JPEG-shaped file (SOI ... EOI); the store only checks the container.
  private func jpeg(_ seed: UInt8) -> Data {
    Data([0xFF, 0xD8, 0xFF, 0xE0, seed, seed &+ 1, 0xFF, 0xD9])
  }

  private func input(rooms: [String], photos: [PhotoRecord]) -> ChecklistInput {
    ChecklistInput(
      record: Fixtures.record(captures: [
        Fixtures.capture(mexico.captureId, areaKey: "floor-1", label: "Room Mexico")
      ]),
      capturedRooms: [mexico.captureId: rooms], photos: photos,
      controls: FieldControlsEditor(visitId: Fixtures.visitId).controls,
      noRoomsSkippedConfirmed: true)
  }

  private func save(_ store: PhotoRecordStore, room: String, seed: UInt8) throws {
    _ = try store.save(
      original: jpeg(seed), capture: mexico,
      labels: PackageManifest.PhotoLabels(
        room: room, direction: .north, subject: .general, takenAt: Fixtures.t0))
  }

  func testClosetRenamedShowerWithAClosetPhotoPasses() throws {
    let files = InMemoryPhotoFileStore()
    let store = try PhotoRecordStore(files: files)
    try save(store, room: "Bedroom", seed: 1)
    try save(store, room: "Bathroom", seed: 2)
    try save(store, room: "Closet", seed: 3)
    let before = ChecklistRules.evaluate(input(rooms: ["Bedroom", "Bathroom", "Closet"], photos: store.records))
    XCTAssertTrue(before.item(.photoPerRoom).passed)

    // The capture model now says Shower; until the photo follows, Shower has none.
    let renamedRooms = ["Bedroom", "Bathroom", "Shower"]
    let stale = ChecklistRules.evaluate(input(rooms: renamedRooms, photos: store.records))
    XCTAssertEqual(
      stale.item(.photoPerRoom).gaps, [.roomWithoutPhoto(capture: "Room Mexico", room: "Shower")])
    XCTAssertEqual(stale.item(.photoPerRoom).detail, "Shower has no photo")

    let originals = files.paths.filter { $0.hasPrefix("Site Photos/") }.map { try! files.read(relativePath: $0) }
    let changed = try store.relabelRoom(captureId: mexico.captureId, from: " closet", to: "Shower")
    XCTAssertEqual(changed.map(\.sequence), [3])
    let after = ChecklistRules.evaluate(input(rooms: renamedRooms, photos: store.records))
    XCTAssertTrue(after.item(.photoPerRoom).passed)
    XCTAssertEqual(after.item(.photoPerRoom).detail, "3 photos, 3 rooms covered")
    XCTAssertTrue(after.canFinish)
    XCTAssertEqual(
      PhotoCoverage.status(rooms: renamedRooms, photos: store.records).text, "Every room has a photo")
    // The photo files are the same bytes.
    XCTAssertEqual(
      files.paths.filter { $0.hasPrefix("Site Photos/") }.map { try! files.read(relativePath: $0) }, originals)
    XCTAssertTrue(store.records.allSatisfy(store.isIntact))
  }

  /// photo-records.json after a relabel: every record's labels are a valid manifest `photo`.
  func testTheRelabeledIndexIsValidAgainstTheManifestSchema() throws {
    let files = InMemoryPhotoFileStore()
    let store = try PhotoRecordStore(files: files)
    try save(store, room: "Closet", seed: 1)
    try save(store, room: "Bedroom", seed: 2)
    try store.relabelRoom(
      captureId: mexico.captureId, from: "Closet", to: String(repeating: "s", count: 100))
    XCTAssertThrowsError(
      try store.relabelRoom(
        captureId: mexico.captureId, from: "Bedroom", to: String(repeating: "s", count: 101)))

    let index = try files.read(relativePath: PhotoRecordStore.indexPath)
    let records = try XCTUnwrap(JSONSerialization.jsonObject(with: index) as? [[String: Any]])
    XCTAssertEqual(records.count, 2)
    let schema = try JSONSchemaValidator.loadSchema(named: "manifest.schema.json")
    for (offset, record) in records.enumerated() {
      let labels = try XCTUnwrap(record["labels"])
      XCTAssertEqual(
        try schema.validate(labels, against: ["$ref": "#/$defs/photo"], path: "$[\(offset)].labels"), [])
    }
    XCTAssertEqual(
      try PhotoRecordStore(files: files).records.map(\.room), [String(repeating: "s", count: 100), "Bedroom"])
  }
}
