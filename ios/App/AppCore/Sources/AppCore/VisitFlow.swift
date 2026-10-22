import CaptureContract
import CaptureCore
import FieldRules
import Foundation

/// The screens of one site visit (design v2, critique R-25). The Capture overview is the hub:
/// capture record -> scan (per floor or area) -> photos -> overview; from the overview the photo
/// step, Field controls and Before you leave open and come back; the checklist gate leads to
/// Package ready (revision 1) or Revision n (revision mode); sealing leads to Package status.
public enum VisitStep: Hashable, Sendable {
  /// "New capture" and "What are you scanning?" (CaptureFlowModel steps 1 and 2): a new visit,
  /// or a further floor of this one.
  case captureRecord
  /// Live scan (or replay) of one floor or area.
  case scan
  /// Photo labeling for one capture. `initialRoom` preselects a room (from the checklist).
  case photos(captureId: LowercaseUUID, initialRoom: String?)
  /// Field controls.
  case controls
  /// Before you leave, scrolled to `focus` when given (the overview's Compass and Rooms not
  /// scanned rows).
  case checklist(focus: ChecklistItemID?)
  /// The Capture overview.
  case overview
  /// Package ready (revision 1).
  case packageReady
  /// Revision n (revision mode, n ≥ 2).
  case revisionReady
  /// Package status, then Verdict received, of one sealed package.
  case packageStatus(LowercaseUUID)
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

/// State machine of one visit (critique R-25: phone-capture §5.3 merged with phone-package
/// §9.1). Pure value type: the SwiftUI shell derives its navigation from `step` and calls the
/// events; every rule (the checklist gate, also in revision mode; no change after sealing; one
/// HUB project per visit) is enforced here and tested on Linux.
///
/// The photo step and Field controls go back to what opened them: the overview, or Before you
/// leave when they were opened from one of its rows ("Take photo", "Add"), so a fix made from
/// the checklist returns to it (phone-field §2).
public struct VisitFlow: Equatable, Sendable {
  public private(set) var step: VisitStep
  /// The visit's capture record: the first floor's record with every later floor appended (in
  /// revision mode: the base revision's captures and the new ones).
  public private(set) var record: CaptureRecord?
  /// True once the newest revision was sealed (assembled read-only). Nothing can change until
  /// "Add to this capture" opens revision n+1 (revision mode, where it is false again).
  public private(set) var isSealed: Bool
  /// The operator's "All rooms scanned" tap on the checklist. A new visit starts unconfirmed; the
  /// tap covers only the captures that existed when it was made (FieldRules' rule).
  public private(set) var noRoomsSkipped: NoRoomsSkippedConfirmation
  /// The revision being captured (revision mode) or the newest sealed one: 1 for a new visit.
  public private(set) var revision: Int
  /// The package this revision builds on (revision mode) or supersedes (a re-seal after Upload
  /// stopped); nil for revision 1.
  public private(set) var basePackageId: LowercaseUUID?
  /// True while revision n ≥ 2 is captured after a verdict ("Add to this capture").
  public private(set) var isRevisionMode: Bool
  /// The photo step or Field controls was opened from Before you leave and goes back to it.
  public private(set) var returnsToChecklist: Bool

  /// A new visit at "New capture".
  public init() {
    step = .captureRecord
    record = nil
    isSealed = false
    noRoomsSkipped = NoRoomsSkippedConfirmation()
    revision = 1
    basePackageId = nil
    isRevisionMode = false
    returnsToChecklist = false
  }

  /// A visit read back from its `visit.json` (the Captures home after a relaunch): at the
  /// Capture overview.
  public init(
    resuming record: CaptureRecord, noRoomsSkipped: NoRoomsSkippedConfirmation = .init(),
    isSealed: Bool, revision: Int = 1, basePackageId: LowercaseUUID? = nil,
    isRevisionMode: Bool = false
  ) {
    step = .overview
    self.record = record
    self.isSealed = isRevisionMode ? false : isSealed
    self.noRoomsSkipped = noRoomsSkipped
    self.revision = max(1, revision)
    self.basePackageId = basePackageId
    self.isRevisionMode = isRevisionMode
    returnsToChecklist = false
  }

  /// "Add to this capture" on Verdict received (phone-package §5.2): revision `baseRevision + 1`
  /// of the sealed `base`, at the Capture overview, editable again. `record` is the base
  /// revision's capture record; `noRoomsSkipped` the base revision's "All rooms scanned" tap,
  /// which keeps covering its captures (a new floor makes it ask again).
  public init(
    revisionOf record: CaptureRecord, base: LowercaseUUID, baseRevision: Int,
    noRoomsSkipped: NoRoomsSkippedConfirmation = NoRoomsSkippedConfirmation()
  ) {
    self.init(
      resuming: record, noRoomsSkipped: noRoomsSkipped, isSealed: false,
      revision: baseRevision + 1, basePackageId: base, isRevisionMode: true)
  }

  /// The value for `ChecklistInput.noRoomsSkippedConfirmed`: true only while the visit has the
  /// same captures as at the tap and none of them lists an omitted or inaccessible room.
  public var noRoomsSkippedConfirmed: Bool {
    guard let record else { return false }
    return noRoomsSkipped.isConfirmed(for: record)
  }

  /// Captures of the visit, in capture order.
  public var captures: [CaptureRecord.Capture] { record?.captures ?? [] }

  /// True while a further floor is being added to a visit that already has captures.
  public var isAddingFloor: Bool {
    (step == .captureRecord || step == .scan) && !captures.isEmpty
  }

  /// The visit is sealed and not reopened: the field screens are read-only (phone-field B4).
  public var isReadOnly: Bool { isSealed && !isRevisionMode }

  // MARK: Capture record and scan

  /// "Start scan" was accepted by the capture screens.
  public mutating func scanStarted() throws {
    try require([.captureRecord], "start a scan")
    step = .scan
  }

  /// The scan was cancelled; back to "What are you scanning?".
  public mutating func scanCancelled() throws {
    try require([.scan], "cancel a scan")
    step = .captureRecord
  }

  /// Back from "What are you scanning?" while adding a floor: the overview again, nothing added.
  public mutating func cancelAddFloor() throws {
    try require([.captureRecord], "stop adding a floor")
    guard !captures.isEmpty else {
      throw VisitFlowError.invalidTransition(from: step, event: "stop adding a floor")
    }
    step = .overview
  }

  /// "Finish floor": the floor's capture record (one capture) joins the visit, then photos of
  /// that capture. The first floor's record is the visit's record; later floors must be for the
  /// same HUB deal and address, and their capture is appended.
  public mutating func floorFinished(_ floorRecord: CaptureRecord) throws {
    try require([.scan], "finish a floor")
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
    returnsToChecklist = false
    step = .photos(captureId: capture.captureId, initialRoom: nil)
  }

  // MARK: Field work

  /// "Done" on the camera, or "Done with photos": back to the overview (or to Before you leave
  /// when the camera was opened from it).
  public mutating func photosDone() throws {
    guard case .photos = step else {
      throw VisitFlowError.invalidTransition(from: step, event: "finish photos")
    }
    leaveFieldScreen()
  }

  /// The overview's Photos row, or "Take photo" on Before you leave. Not after sealing (the
  /// overview opens Before you leave read-only instead).
  public mutating func openPhotos(captureId: LowercaseUUID, room: String?) throws {
    guard !isReadOnly else { throw VisitFlowError.alreadySealed }
    let fromChecklist = try requireOverviewOrChecklist("take photos")
    guard captures.contains(where: { $0.captureId == captureId }) else {
      throw VisitFlowError.unknownCapture(captureId)
    }
    returnsToChecklist = fromChecklist
    step = .photos(captureId: captureId, initialRoom: room)
  }

  /// The overview's Field controls row, or "Add" on Before you leave. After sealing it opens
  /// read-only.
  public mutating func openControls() throws {
    returnsToChecklist = try requireOverviewOrChecklist("open field controls")
    step = .controls
  }

  /// Back from Field controls: the overview (or Before you leave when opened from it).
  public mutating func controlsDone() throws {
    try require([.controls], "finish field controls")
    leaveFieldScreen()
  }

  /// The overview's Compass or Rooms not scanned row (or the Photos row of a sealed visit):
  /// Before you leave, scrolled to `focus`.
  public mutating func openChecklist(focus: ChecklistItemID? = nil) throws {
    try require([.overview], "open the checklist")
    returnsToChecklist = false
    step = .checklist(focus: focus)
  }

  /// "All rooms scanned" on the checklist's skipped-rooms row: the operator confirms that no
  /// room of the current captures was omitted or inaccessible.
  public mutating func confirmNoRoomsSkipped() throws {
    guard case .checklist = step else {
      throw VisitFlowError.invalidTransition(from: step, event: "confirm no rooms skipped")
    }
    guard !isReadOnly else { throw VisitFlowError.alreadySealed }
    guard let record else {
      throw VisitFlowError.invalidTransition(from: step, event: "confirm no rooms skipped")
    }
    noRoomsSkipped.confirm(for: record)
  }

  /// Back to the Capture overview from a screen it opened.
  public mutating func backToOverview() throws {
    switch step {
    case .photos, .controls, .checklist, .packageReady, .revisionReady, .packageStatus:
      returnsToChecklist = false
      step = .overview
    default:
      throw VisitFlowError.invalidTransition(from: step, event: "go back to the overview")
    }
  }

  // MARK: Package

  /// The overview's button or "Finish capture" on Before you leave: Package ready (revision 1)
  /// or Revision n (revision mode). Only a passing checklist leads there, in revision mode too.
  public mutating func reviewPackage(canFinish: Bool) throws {
    _ = try requireOverviewOrChecklist("review the package")
    guard !isReadOnly else { throw VisitFlowError.alreadySealed }
    guard record != nil else {
      throw VisitFlowError.invalidTransition(from: step, event: "review a package without captures")
    }
    guard canFinish else { throw VisitFlowError.checklistIncomplete }
    returnsToChecklist = false
    step = isRevisionMode ? .revisionReady : .packageReady
  }

  /// "Scan another floor or room": the next floor or area of the same visit. Not after sealing,
  /// except in revision mode.
  public mutating func addFloor() throws {
    guard !isReadOnly else { throw VisitFlowError.alreadySealed }
    try require([.overview, .packageReady, .revisionReady], "add a floor")
    returnsToChecklist = false
    step = .captureRecord
  }

  /// "Seal and upload" (or "Seal revision n and upload") succeeded: the package is read-only and
  /// its upload starts.
  public mutating func sealed(packageId: LowercaseUUID) throws {
    guard !isSealed else { throw VisitFlowError.alreadySealed }
    try require([.packageReady, .revisionReady], "seal")
    isSealed = true
    isRevisionMode = false
    step = .packageStatus(packageId)
  }

  /// "Re-seal as revision n+1" after Upload stopped: revision n+1, a full build superseding the
  /// stopped package, uploads instead (phone-package §4.2).
  public mutating func resealAfterFailure(newPackageId: LowercaseUUID) throws {
    guard case .packageStatus(let stopped) = step, isSealed else {
      throw VisitFlowError.invalidTransition(from: step, event: "re-seal")
    }
    basePackageId = stopped
    revision += 1
    step = .packageStatus(newPackageId)
  }

  /// The overview's "Upload status" or "Open the verdict" of a sealed visit.
  public mutating func showPackage(_ packageId: LowercaseUUID) throws {
    try require([.overview], "show the package")
    guard isSealed else {
      throw VisitFlowError.invalidTransition(from: step, event: "show a package before sealing")
    }
    step = .packageStatus(packageId)
  }

  // MARK: Private

  private mutating func leaveFieldScreen() {
    step = returnsToChecklist ? .checklist(focus: nil) : .overview
    returnsToChecklist = false
  }

  /// True when the step is Before you leave, false for the overview; throws otherwise.
  private func requireOverviewOrChecklist(_ event: String) throws -> Bool {
    switch step {
    case .overview: return false
    case .checklist: return true
    default: throw VisitFlowError.invalidTransition(from: step, event: event)
    }
  }

  private func require(_ expected: [VisitStep], _ event: String) throws {
    guard expected.contains(step) else {
      throw VisitFlowError.invalidTransition(from: step, event: event)
    }
  }
}

/// Where a tapped "Verdict: …" notification opens its package (`HomeModel.openPackage`). The
/// banner shows in the foreground too, so the tap can come while the operator scans another
/// capture: the open visit is never replaced while it holds work that is not on disk yet.
public enum PackageOpening: Equatable, Sendable {
  /// The open visit shows it in its own flow (a sealed visit's package): Package status, or
  /// Verdict received.
  case inOpenVisit
  /// On top of the screen the operator is on; the open visit stays as it is and Back returns to
  /// it (during a live scan, the package is there once the scan ends).
  case onTop
  /// The visit that holds it is opened in place of the open one, whose work is all on disk.
  case openItsVisit

  /// - Parameters:
  ///   - openVisitHoldsIt: the package is one of the open visit's.
  ///   - openVisitShowsIt: the open visit can show it in its flow (sealed, not being revised).
  ///   - openVisitHasWorkToLose: closing the open visit now would lose work (a live scan, an
  ///     unsaved New capture or floor, a photo or entry not saved).
  public static func decide(
    hasOpenVisit: Bool, openVisitHoldsIt: Bool, openVisitShowsIt: Bool,
    openVisitHasWorkToLose: Bool
  ) -> PackageOpening {
    guard hasOpenVisit else { return .openItsVisit }
    if openVisitHasWorkToLose { return .onTop }
    if openVisitHoldsIt { return openVisitShowsIt ? .inOpenVisit : .onTop }
    return .openItsVisit
  }
}
