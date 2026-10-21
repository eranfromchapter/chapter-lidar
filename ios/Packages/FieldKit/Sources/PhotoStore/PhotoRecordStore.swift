import CaptureContract
import FieldRules
import Foundation

public enum PhotoStoreError: Error, Equatable, Sendable, CustomStringConvertible {
  /// The bytes are not a JPEG or HEIC file.
  case notAPhoto
  case incompleteLabels([PhotoLabelField])
  case invalidRoom
  case invalidAreaKey(String)
  case invalidPath(String)
  case fileExists(String)
  case fileMissing(String)
  /// The file read back after writing differs from the bytes that were given.
  case writeVerificationFailed(String)
  case corruptIndex

  public var description: String {
    switch self {
    case .notAPhoto: return "The file is not a JPEG or HEIC photograph."
    case .incompleteLabels(let fields):
      return "Choose " + fields.map { $0.title.lowercased() }.joined(separator: ", ") + " first."
    case .invalidRoom: return "The room label must be 1 to 100 characters."
    case .invalidAreaKey(let key): return "'\(key)' is not a valid floor or area key."
    case .invalidPath(let path): return "'\(path)' is not a valid package-relative path."
    case .fileExists(let path): return "\(path) already exists and is not replaced."
    case .fileMissing(let path): return "\(path) is missing."
    case .writeVerificationFailed(let path):
      return "\(path) did not match the photo that was taken."
    case .corruptIndex: return "The photo index could not be read."
    }
  }
}

/// Saves site photographs and remembers their labels.
///
/// The original file bytes are written exactly as received (HEIC or JPEG with EXIF, as produced
/// by the camera): no re-encoding, resizing, cropping, stripping or rotating. After writing, the
/// file is read back and compared; a mismatch removes it and throws. The labels live in an index
/// file (`photo-records.json`, outside the `Site Photos` folder) and in the returned records.
///
/// Path of a photo: `Site Photos/{areaKey}/{captureId}/photo-0014.heic` (layout.json).
public final class PhotoRecordStore: @unchecked Sendable {
  public static let indexPath = "photo-records.json"

  private let files: PhotoFileStore
  private let lock = NSLock()
  private var saved: [PhotoRecord]

  /// Opens the store and loads the index if one exists. Throws `corruptIndex` when it cannot be
  /// read, rather than starting empty and hiding saved photos.
  public init(files: PhotoFileStore) throws {
    self.files = files
    if files.exists(relativePath: Self.indexPath) {
      do {
        let data = try files.read(relativePath: Self.indexPath)
        saved = try CaptureContractJSON.makeDecoder().decode([PhotoRecord].self, from: data)
      } catch {
        throw PhotoStoreError.corruptIndex
      }
    } else {
      saved = []
    }
  }

  /// Every saved photo in the order it was saved.
  public var records: [PhotoRecord] {
    lock.lock()
    defer { lock.unlock() }
    return saved
  }

  public func records(captureId: LowercaseUUID) -> [PhotoRecord] {
    records.filter { $0.captureId == captureId }
  }

  /// Number the next photo of this capture will get (the screen's "Photo 14").
  public func nextSequence(captureId: LowercaseUUID) -> Int {
    (records(captureId: captureId).map(\.sequence).max() ?? 0) + 1
  }

  /// Saves the unchanged original with its labels.
  public func save(
    original: Data,
    capture: FieldControls.CaptureRef,
    labels: PackageManifest.PhotoLabels
  ) throws -> PhotoRecord {
    guard let format = PhotoFormat.detect(original) else { throw PhotoStoreError.notAPhoto }
    guard FieldControlsValidator.isValidAreaKey(capture.areaKey) else {
      throw PhotoStoreError.invalidAreaKey(capture.areaKey)
    }
    let room = labels.room.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !room.isEmpty, room.count <= PhotoLabelDraft.maximumRoomLength else {
      throw PhotoStoreError.invalidRoom
    }

    lock.lock()
    defer { lock.unlock() }

    let sequence =
      (saved.filter { $0.captureId == capture.captureId }.map(\.sequence).max() ?? 0) + 1
    let number = String(sequence)
    let padded = String(repeating: "0", count: max(0, 4 - number.count)) + number
    let path =
      "\(PackageFolder.sitePhotos.name)/\(capture.areaKey)/\(capture.captureId.rawValue)/"
      + "photo-\(padded).\(format.fileExtension)"

    try files.write(original, toRelativePath: path, replacingExisting: false)
    do {
      guard try files.read(relativePath: path) == original else {
        throw PhotoStoreError.writeVerificationFailed(path)
      }
      var stored = labels
      stored.room = room
      let record = PhotoRecord(
        captureId: capture.captureId,
        areaKey: capture.areaKey,
        sequence: sequence,
        path: path,
        format: format,
        sha256: SHA256.hexDigest(of: original),
        bytes: Int64(original.count),
        labels: stored)
      let index = try CaptureContractJSON.makeEncoder(prettyPrinted: true)
        .encode(saved + [record])
      try files.write(index, toRelativePath: Self.indexPath, replacingExisting: true)
      saved.append(record)
      return record
    } catch {
      try? files.remove(relativePath: path)
      throw error
    }
  }

  /// Saves from the labeling screen's choices; throws `incompleteLabels` listing what is missing.
  public func save(
    original: Data,
    capture: FieldControls.CaptureRef,
    draft: PhotoLabelDraft,
    takenAt: UTCTimestamp
  ) throws -> PhotoRecord {
    guard let labels = draft.labels(takenAt: takenAt) else {
      throw PhotoStoreError.incompleteLabels(draft.missing)
    }
    return try save(original: original, capture: capture, labels: labels)
  }

  /// Relabels the photos of one capture after its rooms were renamed: a record whose room is
  /// the `from` of a rename (compared as the checklist compares rooms, `PhotoCoverage.key`:
  /// trimmed, ignoring case) gets that rename's `to`. All renames apply at once, to the labels
  /// as they were, so two rooms can swap names. Only the records change, in memory and in
  /// `photo-records.json`; no photo file is read, written or moved, so every original stays
  /// byte for byte what the camera delivered (and its recorded SHA-256 and size still match).
  ///
  /// Throws `invalidRoom` (and changes nothing) when a new name is blank or longer than 100
  /// characters or Unicode scalars (the manifest schema's room label). Returns the records
  /// that changed, in save order.
  @discardableResult
  public func relabelRooms(
    captureId: LowercaseUUID, renames: [(from: String, to: String)]
  ) throws -> [PhotoRecord] {
    try relabelRooms([captureId: renames])
  }

  /// `relabelRooms(captureId:renames:)` for the renames of several captures (by capture id), in
  /// one write of `photo-records.json`: either every capture's photos are relabeled or, when
  /// the write fails, none is.
  @discardableResult
  public func relabelRooms(_ renamesByCapture: [LowercaseUUID: [(from: String, to: String)]])
    throws -> [PhotoRecord]
  {
    var targets: [LowercaseUUID: [String: String]] = [:]
    for (captureId, renames) in renamesByCapture {
      var capture: [String: String] = [:]
      for rename in renames {
        let to = rename.to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !to.isEmpty, to.count <= PhotoLabelDraft.maximumRoomLength,
          to.unicodeScalars.count <= PhotoLabelDraft.maximumRoomLength
        else { throw PhotoStoreError.invalidRoom }
        let from = PhotoCoverage.key(rename.from)
        // The first rename of a room wins; renaming a room to its own label changes nothing.
        if capture[from] == nil, !from.isEmpty { capture[from] = to }
      }
      targets[captureId] = capture
    }

    lock.lock()
    defer { lock.unlock() }
    var next = saved
    var changed: [PhotoRecord] = []
    for index in next.indices {
      guard let capture = targets[next[index].captureId],
        let to = capture[PhotoCoverage.key(next[index].room)], next[index].room != to
      else { continue }
      next[index].labels.room = to
      changed.append(next[index])
    }
    guard !changed.isEmpty else { return [] }
    try writeIndex(next)
    return changed
  }

  /// Puts back the labels the photos had in `previous` (records as `records` returned them
  /// earlier, matched by path), for example to undo a relabel when a later step of a rename
  /// failed. Exactly those labels come back, whatever a relabel did; a photo saved since keeps
  /// its own, and no photo file is touched.
  public func restoreLabels(_ previous: [PhotoRecord]) throws {
    let labels = Dictionary(previous.map { ($0.path, $0.labels) }, uniquingKeysWith: { a, _ in a })
    lock.lock()
    defer { lock.unlock() }
    var next = saved
    for index in next.indices {
      if let old = labels[next[index].path] { next[index].labels = old }
    }
    guard next != saved else { return }
    try writeIndex(next)
  }

  /// Writes `records` as the index, then keeps them. The caller holds `lock`.
  private func writeIndex(_ records: [PhotoRecord]) throws {
    let index = try CaptureContractJSON.makeEncoder(prettyPrinted: true).encode(records)
    try files.write(index, toRelativePath: Self.indexPath, replacingExisting: true)
    saved = records
  }

  /// `relabelRooms(captureId:renames:)` for one room.
  @discardableResult
  public func relabelRoom(captureId: LowercaseUUID, from: String, to: String) throws
    -> [PhotoRecord]
  {
    try relabelRooms(captureId: captureId, renames: [(from: from, to: to)])
  }

  /// The original bytes of a saved photo, exactly as stored.
  public func originalData(for record: PhotoRecord) throws -> Data {
    try files.read(relativePath: record.path)
  }

  /// True when the stored file still has the size and SHA-256 recorded when it was saved.
  public func isIntact(_ record: PhotoRecord) -> Bool {
    guard let data = try? files.read(relativePath: record.path) else { return false }
    return Int64(data.count) == record.bytes && SHA256.hexDigest(of: data) == record.sha256
  }
}
