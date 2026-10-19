#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import FieldRules
  import Foundation
  import Observation
  import PhotoStore

  /// State of the camera and "Photo labeling" screens for one capture (floor or area).
  /// A photo is taken, shown, labeled with room, direction and subject, then saved unchanged.
  @MainActor @Observable
  public final class PhotoLabelingModel {
    public let capture: FieldCaptureOption
    public let store: PhotoRecordStore

    /// The photo just taken, not yet saved: the original bytes exactly as the camera delivered.
    public private(set) var pendingOriginal: Data?
    public var draft: PhotoLabelDraft
    public var showsAllRooms = false
    public var showsMoreSubjects = false
    /// Free-text room for a room that is not in the capture's room list.
    public var otherRoom = ""
    public private(set) var isCapturing = false
    public private(set) var errorMessage: String?
    /// Photos saved so far in this capture (drives the "Photo 14" counter).
    public private(set) var savedCount: Int

    private let capturePhoto: @Sendable () async throws -> Data
    private let now: @Sendable () -> UTCTimestamp
    private var takenAt: UTCTimestamp?

    /// - Parameters:
    ///   - capturePhoto: returns the original file bytes of a new photo (the app's own camera).
    ///   - initialRoom: preselects a room, for example the room the checklist says has no photo.
    public init(
      capture: FieldCaptureOption,
      store: PhotoRecordStore,
      initialRoom: String? = nil,
      capturePhoto: @escaping @Sendable () async throws -> Data,
      now: @escaping @Sendable () -> UTCTimestamp = { UTCTimestamp.now() }
    ) {
      self.capture = capture
      self.store = store
      self.draft = PhotoLabelDraft(room: initialRoom)
      self.capturePhoto = capturePhoto
      self.now = now
      self.savedCount = store.records(captureId: capture.ref.captureId).count
    }

    /// Number shown in "Photo 14 of Floor 1": the photo being labeled, or the next to take.
    public var photoNumber: Int { store.nextSequence(captureId: capture.ref.captureId) }

    public var title: String { "Photo \(photoNumber) of \(capture.label)" }

    /// Room chips: up to three rooms, then More.
    public var primaryRooms: [String] { Array(capture.rooms.prefix(3)) }
    public var otherRooms: [String] { Array(capture.rooms.dropFirst(3)) }

    public var canSave: Bool { pendingOriginal != nil && draft.isComplete }

    /// What still has to be chosen before the photo can be saved, for example
    /// "Choose Looking toward and Subject to save."; nil when nothing is missing.
    public var missingHint: String? {
      guard pendingOriginal != nil else { return nil }
      let names = draft.missing.map(\.title)
      guard !names.isEmpty else { return nil }
      return "Choose \(ListFormatter.localizedString(byJoining: names)) to save."
    }

    public func takePhoto() async {
      guard !isCapturing else { return }
      isCapturing = true
      errorMessage = nil
      defer { isCapturing = false }
      do {
        let data = try await capturePhoto()
        takenAt = now()
        pendingOriginal = data
      } catch {
        errorMessage = userMessage(for: error)
      }
    }

    public func chooseRoom(_ room: String) {
      draft.room = room
    }

    public func useOtherRoom() {
      let trimmed = otherRoom.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      draft.room = trimmed
    }

    /// Saves the pending photo with its labels, then returns to the camera. The next photo keeps
    /// the room but must be labeled again for direction and subject.
    public func saveAndTakeNext() {
      guard let original = pendingOriginal else { return }
      do {
        _ = try store.save(
          original: original, capture: capture.ref, draft: draft, takenAt: takenAt ?? now())
        pendingOriginal = nil
        takenAt = nil
        draft = draft.forNextPhoto()
        showsMoreSubjects = false
        savedCount = store.records(captureId: capture.ref.captureId).count
        errorMessage = nil
      } catch {
        errorMessage = userMessage(for: error)
      }
    }

    /// Throws away the photo that was just taken (not saved) to take it again.
    public func discardPending() {
      pendingOriginal = nil
      takenAt = nil
    }
  }
#endif
