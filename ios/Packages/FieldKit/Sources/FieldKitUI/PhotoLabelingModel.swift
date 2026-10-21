#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import FieldRules
  import Foundation
  import Observation
  import PhotoStore

  /// State of the camera and "Label a photo" screens for one capture (floor or area), design v2
  /// (artboard 2d-1). A photo is taken, shown, labeled with room, direction and subject, then
  /// saved unchanged. The room stays selected for the next photo; the direction is pre-filled
  /// from the camera heading at the shutter when the compass allows it.
  @MainActor @Observable
  public final class PhotoLabelingModel {
    /// The capture; its rooms change when the operator renames them (`roomsRenamed`).
    public private(set) var capture: FieldCaptureOption
    public let store: PhotoRecordStore
    /// The camera heading at the shutter; nil: no pre-fill.
    public let heading: PhotoHeadingProviding?

    /// The photo just taken, not yet saved: the original bytes exactly as the camera delivered.
    public private(set) var pendingOriginal: Data?
    public var draft: PhotoLabelDraft
    /// Free-text room for a room that is not in the capture's room list (room picker).
    public var otherRoom = ""
    public private(set) var isCapturing = false
    public private(set) var errorMessage: String?
    /// Photos saved so far in this capture (drives the "Photo 14" counter).
    public private(set) var savedCount: Int
    /// The room the operator came for when the camera was opened from the checklist ("Take
    /// photo" on "Shower has no photo"); nil otherwise.
    public private(set) var targetRoom: String?
    /// Which rooms of this capture still need a photo: the checklist's rule
    /// (`PhotoCoverage`), kept up to date as photos are saved and rooms renamed.
    public private(set) var coverage: PhotoCoverage.Status
    /// When the pending photo was taken.
    public private(set) var takenAt: UTCTimestamp?

    private let capturePhoto: @Sendable () async throws -> Data
    private let now: @Sendable () -> UTCTimestamp
    private let date: @Sendable () -> Date
    private let timeZone: TimeZone

    /// - Parameters:
    ///   - capturePhoto: returns the original file bytes of a new photo (the app's own camera).
    ///   - initialRoom: preselects a room, for example the room the checklist says has no photo.
    ///     Without it the room of the capture's last saved photo is selected.
    ///   - heading: the camera heading for the "Looking toward" pre-fill.
    ///   - now, date: clocks (the photo's `takenAt`, and the age of a heading sample).
    ///   - timeZone: the zone of the time on the photo (the phone's).
    public init(
      capture: FieldCaptureOption,
      store: PhotoRecordStore,
      initialRoom: String? = nil,
      heading: PhotoHeadingProviding? = nil,
      capturePhoto: @escaping @Sendable () async throws -> Data,
      now: @escaping @Sendable () -> UTCTimestamp = { UTCTimestamp.now() },
      date: @escaping @Sendable () -> Date = { Date() },
      timeZone: TimeZone = .current
    ) {
      self.capture = capture
      self.store = store
      self.heading = heading
      self.capturePhoto = capturePhoto
      self.now = now
      self.date = date
      self.timeZone = timeZone
      let photos = store.records(captureId: capture.ref.captureId)
      self.savedCount = photos.count
      let trimmed = initialRoom?.trimmingCharacters(in: .whitespacesAndNewlines)
      let target = trimmed?.isEmpty == false ? trimmed : nil
      self.targetRoom = target
      self.draft = PhotoLabelDraft(room: target ?? photos.last?.room)
      self.coverage = PhotoCoverage.status(rooms: capture.rooms, photos: photos)
    }

    // MARK: Titles

    /// Number of the photo being labeled, or of the next one to take.
    public var photoNumber: Int { store.nextSequence(captureId: capture.ref.captureId) }

    /// "Photo 14 · Floor 1": the labeling screen's title.
    public var title: String { "Photo \(photoNumber) \u{00B7} \(capture.label)" }

    /// The viewfinder's title: "Shower · Photo 16 · Floor 1" when the camera was opened for a
    /// room from Before you leave, else `title`.
    public var headerTitle: String {
      guard let targetRoom else { return title }
      return "\(targetRoom) \u{00B7} \(title)"
    }

    /// `HEIC` or `JPEG`, the format of the pending photo; nil when it is not known.
    public var pendingFormat: PhotoFormat? { pendingOriginal.flatMap(PhotoFormat.detect) }

    /// `12:41 · original kept`, the pill on the photo: `takenAt` in the phone's time zone.
    public var takenAtText: String? {
      guard let takenAt else { return nil }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = timeZone
      formatter.dateFormat = "HH:mm"
      return formatter.string(from: takenAt.date)
    }

    // MARK: Labels

    /// Room chips: the first 4 rooms, then the selected room (or the room the operator came for)
    /// when it is further down the list (`RoomChips`), or a room typed under "Other room" that
    /// the scan does not have; `More` follows.
    public var primaryRooms: [String] {
      var rooms = RoomChips.primary(capture.rooms, target: draft.room ?? targetRoom)
      if let selected = draft.room?.trimmingCharacters(in: .whitespacesAndNewlines),
        !selected.isEmpty, !capture.rooms.contains(where: { isSame($0, selected) })
      {
        rooms.append(selected)
      }
      return rooms
    }

    private func isSame(_ a: String, _ b: String) -> Bool {
      PhotoCoverage.key(a) == PhotoCoverage.key(b)
    }

    /// True when the checklist still asks a photo of `room`.
    public func needsPhoto(_ room: String) -> Bool { coverage.needsPhoto(room) }

    /// True when `room` is the selected room (compared as the checklist compares rooms).
    public func isSelected(_ room: String) -> Bool {
      guard let selected = draft.room else { return false }
      return PhotoCoverage.key(selected) == PhotoCoverage.key(room)
    }

    /// The strip under the labels: the last photos of the selected room and their count.
    public var strip: PhotoStrip {
      PhotoStrip(photos: store.records(captureId: capture.ref.captureId), room: draft.room)
    }

    public var canSave: Bool { pendingOriginal != nil && draft.isComplete }

    /// What still has to be chosen before the photo can be saved, for example
    /// "Choose Looking toward and Subject to save."; nil when nothing is missing.
    public var missingHint: String? {
      guard pendingOriginal != nil else { return nil }
      let names = draft.missing.map(\.title)
      guard !names.isEmpty else { return nil }
      return "Choose \(ListFormatter.localizedString(byJoining: names)) to save."
    }

    public func chooseRoom(_ room: String) {
      draft.room = room
    }

    public func chooseDirection(_ direction: PhotoDirection) {
      draft.chooseDirection(direction)
    }

    public func chooseSubject(_ subject: PhotoSubject) {
      draft.subject = subject
    }

    /// Takes "Room not in the list" as the room; false when it is empty.
    @discardableResult
    public func useOtherRoom() -> Bool {
      let trimmed = otherRoom.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return false }
      draft.room = String(trimmed.prefix(PhotoLabelDraft.maximumRoomLength))
      otherRoom = ""
      return true
    }

    // MARK: Camera

    /// Starts the heading provider with the viewfinder.
    public func startHeading() { heading?.start() }

    public func stopHeading() { heading?.stop() }

    /// The shutter: the heading is sampled first (where the camera points now, not after the
    /// capture pipeline returns), then the photo is taken and the suggestion applied.
    public func takePhoto() async {
      guard !isCapturing else { return }
      isCapturing = true
      errorMessage = nil
      defer { isCapturing = false }
      let suggestion = PhotoDirection.fromCompass(heading?.currentSample(), now: date())
      do {
        let data = try await capturePhoto()
        takenAt = now()
        pendingOriginal = data
        draft.applyCompass(suggestion)
      } catch {
        errorMessage = userMessage(for: error)
      }
    }

    // MARK: Saving

    /// "Save and take next": saves the pending photo with its labels, then returns to the
    /// camera. The room stays selected; direction and subject start empty for the next photo.
    public func saveAndTakeNext() {
      _ = save()
    }

    /// "Done with photos": the same save; true when it succeeded (the step then closes), false
    /// with `errorMessage` set when it did not.
    @discardableResult
    public func saveAndFinish() -> Bool {
      save()
    }

    private func save() -> Bool {
      guard let original = pendingOriginal else { return false }
      do {
        _ = try store.save(
          original: original, capture: capture.ref, draft: draft, takenAt: takenAt ?? now())
        pendingOriginal = nil
        takenAt = nil
        draft = draft.forNextPhoto()
        savedCount = store.records(captureId: capture.ref.captureId).count
        errorMessage = nil
        refreshCoverage()
        return true
      } catch {
        errorMessage = userMessage(for: error)
        return false
      }
    }

    /// Throws away the photo that was just taken (not saved) to take it again. The room stays.
    public func discardPending() {
      pendingOriginal = nil
      takenAt = nil
      errorMessage = nil
      draft = draft.forNextPhoto()
    }

    /// The operator renamed rooms of this capture (the photo already labeled with an old name
    /// was relabeled by the app): the Room chips become `rooms`, and the chosen room and the
    /// room the operator came for follow their new names. A photo being labeled is kept.
    public func roomsRenamed(rooms: [String], renames: [(from: String, to: String)]) {
      func renamed(_ room: String?) -> String? {
        guard let room else { return nil }
        let key = PhotoCoverage.key(room)
        return renames.first { PhotoCoverage.key($0.from) == key }?.to ?? room
      }
      capture.rooms = rooms
      draft.room = renamed(draft.room)
      targetRoom = renamed(targetRoom)
      refreshCoverage()
    }

    private func refreshCoverage() {
      coverage = PhotoCoverage.status(
        rooms: capture.rooms, photos: store.records(captureId: capture.ref.captureId))
    }
  }
#endif
