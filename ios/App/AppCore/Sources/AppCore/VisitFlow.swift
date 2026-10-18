import CaptureContract
import CaptureCore
import Foundation

/// The screens of one site visit, in the order of the frozen design:
/// capture record -> scan (per floor or area) -> photos -> field controls -> before you leave
/// (checklist gate) -> package ready (seal) -> uploading and station status.
public enum VisitStep: Hashable, Sendable {
  /// "New capture" and "What are you scanning?" (CaptureFlowModel steps 1 and 2).
  case captureRecord
  /// Live scan (or replay) of one floor or area.
  case scan
  /// Photo labeling for one capture. `initialRoom` preselects a room (from the checklist).
  case photos(captureId: LowercaseUUID, initialRoom: String?)
  case controls
  case checklist
  case packageReady
  case uploading
}

/// A refused flow event. The screen state does not change.
public enum VisitFlowError: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidTransition(from: VisitStep, event: String)
  /// "Before you leave" still has failing items.
  case checklistIncomplete
  /// The package is sealed; changes need a new revision.
  case alreadySealed
  /// A later floor was captured for another HUB project or address.
  case differentProject
  /// The capture id or area key is already in the visit.
  case duplicateCapture(areaKey: String)
  case unknownCapture(LowercaseUUID)

  public var description: String {
    switch self {
    case .invalidTransition(let from, let event): return "cannot \(event) from \(from)"
    case .checklistIncomplete: return "Fix the checklist items before finishing."
    case .alreadySealed: return "The package is sealed. Changes need a new revision."
    case .differentProject: return "Every floor of a visit must be for the same HUB project."
    case .duplicateCapture(let areaKey): return "\(areaKey) is already captured in this visit."
    case .unknownCapture(let id): return "capture \(id.rawValue) is not in this visit"
    }
  }
}

/// State machine of one visit. Pure value type: the SwiftUI shell renders `step` and calls the
/// events; every rule (no skipping the checklist, no change after sealing, one HUB project per
/// visit) is enforced here and tested on Linux.
public struct VisitFlow: Equatable, Sendable {
  public private(set) var step: VisitStep = .captureRecord
  /// The visit's capture record: the first floor's record with every later floor appended.
  public private(set) var record: CaptureRecord?
  /// True once the package was sealed (assembled read-only). Nothing can be added after that.
  public private(set) var isSealed = false

  public init() {}

  /// Captures of the visit, in capture order.
  public var captures: [CaptureRecord.Capture] { record?.captures ?? [] }

  /// True while a further floor is being added to a visit that already has captures.
  public var isAddingFloor: Bool { step == .captureRecord && !captures.isEmpty }

  // MARK: Capture record and scan

  /// "Start scan" was accepted by the capture screens.
  public mutating func scanStarted() throws {
    try require(.captureRecord, "start a scan")
    step = .scan
  }

  /// The scan was cancelled; back to "What are you scanning?".
  public mutating func scanCancelled() throws {
    try require(.scan, "cancel a scan")
    step = .captureRecord
  }

  /// "Finish floor": the floor's capture record (one capture) joins the visit, then photos of
  /// that capture. The first floor's record is the visit's record; later floors must be for the
  /// same HUB deal and address, and their capture is appended.
  public mutating func floorFinished(_ floorRecord: CaptureRecord) throws {
    try require(.scan, "finish a floor")
    guard floorRecord.captures.count == 1, let capture = floorRecord.captures.first else {
      throw VisitFlowError.invalidTransition(from: step, event: "finish a floor without one capture")
    }
    if let record {
      guard record.hub.dealId == floorRecord.hub.dealId,
        record.address.formatted == floorRecord.address.formatted
      else { throw VisitFlowError.differentProject }
      guard
        !record.captures.contains(where: {
          $0.captureId == capture.captureId || $0.areaKey == capture.areaKey
        })
      else { throw VisitFlowError.duplicateCapture(areaKey: capture.areaKey) }
      self.record = try record.appending(capture)
    } else {
      record = floorRecord
    }
    step = .photos(captureId: capture.captureId, initialRoom: nil)
  }

  // MARK: Field work

  /// "Done" on the camera: on to field controls.
  public mutating func photosDone() throws {
    guard case .photos = step else {
      throw VisitFlowError.invalidTransition(from: step, event: "finish photos")
    }
    step = .controls
  }

  /// "Continue" on field controls: on to "Before you leave".
  public mutating func controlsDone() throws {
    try require(.controls, "finish field controls")
    step = .checklist
  }

  /// "Take photo" on a checklist row.
  public mutating func takePhoto(captureId: LowercaseUUID, room: String?) throws {
    try require(.checklist, "take a photo")
    guard captures.contains(where: { $0.captureId == captureId }) else {
      throw VisitFlowError.unknownCapture(captureId)
    }
    step = .photos(captureId: captureId, initialRoom: room)
  }

  /// "Add controls" on a checklist row.
  public mutating func addControls() throws {
    try require(.checklist, "add controls")
    step = .controls
  }

  /// The checklist's finish button. Only a passing checklist leads to "Package ready".
  public mutating func checklistFinished(canFinish: Bool) throws {
    try require(.checklist, "finish the checklist")
    guard canFinish else { throw VisitFlowError.checklistIncomplete }
    step = .packageReady
  }

  // MARK: Package

  /// "Add more rooms": scan another floor or area of the same visit. Not after sealing.
  public mutating func addMoreRooms() throws {
    guard !isSealed else { throw VisitFlowError.alreadySealed }
    try require(.packageReady, "add more rooms")
    step = .captureRecord
  }

  /// "Seal and upload" succeeded: the package is read-only and the upload starts.
  public mutating func sealed() throws {
    guard !isSealed else { throw VisitFlowError.alreadySealed }
    try require(.packageReady, "seal")
    isSealed = true
    step = .uploading
  }

  private func require(_ expected: VisitStep, _ event: String) throws {
    guard step == expected else {
      throw VisitFlowError.invalidTransition(from: step, event: event)
    }
  }
}
