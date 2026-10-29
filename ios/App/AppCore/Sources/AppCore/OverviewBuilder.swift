import CaptureContract
import CaptureCore
import FieldRules
import Foundation

/// The Capture overview from one visit (phone-capture §3.5, critique R-21, R-25, R-37, R-38,
/// G-2): the floor rows, the four "Before you leave" rows from FieldRules' checklist, the
/// controls list and the compass summary, and the bottom button. Pure, so every word is tested
/// on Linux; the screen (`CaptureOverviewScreen`) only draws the result.
public enum OverviewBuilder {
  /// A floor's scan as the overview knows it.
  public enum FloorScan: Hashable, Sendable {
    /// The model is being mapped (a visit reopened after a relaunch): "Loading…".
    case loading
    /// Mapped: its measurements (the standard policy's "controls from the scan").
    case mapped(ScanMeasurements?)
    /// The model could not be mapped; the originals are kept.
    case failed
  }

  /// The visit as the overview needs it.
  public struct Input: Sendable {
    public var record: CaptureRecord
    /// Room labels of each capture (renamed labels), from its model.
    public var rooms: [LowercaseUUID: [String]]
    /// Each capture's scan; a capture not in here is `.loading`.
    public var scans: [LowercaseUUID: FloorScan]
    public var photos: [PhotoRecord]
    public var controls: FieldControls
    /// FieldRules' checklist of the visit (the same report Before you leave shows).
    public var checklist: ChecklistReport
    public var policy: ChecklistPolicy
    /// The flow: sealed, revision mode, revision number.
    public var flow: VisitFlow
    /// The newest sealed package has a station verdict ("Open the verdict").
    public var newestPackageHasVerdict: Bool
    public var now: Date
    public var timeZone: TimeZone

    public init(
      record: CaptureRecord, rooms: [LowercaseUUID: [String]],
      scans: [LowercaseUUID: FloorScan], photos: [PhotoRecord], controls: FieldControls,
      checklist: ChecklistReport, policy: ChecklistPolicy = .shipping, flow: VisitFlow,
      newestPackageHasVerdict: Bool = false, now: Date = Date(), timeZone: TimeZone = .current
    ) {
      self.record = record
      self.rooms = rooms
      self.scans = scans
      self.photos = photos
      self.controls = controls
      self.checklist = checklist
      self.policy = policy
      self.flow = flow
      self.newestPackageHasVerdict = newestPackageHasVerdict
      self.now = now
      self.timeZone = timeZone
    }
  }

  public static func make(_ input: Input) -> CaptureOverviewState {
    let record = input.record
    let flow = input.flow
    let sealState: CaptureOverviewState.SealState =
      flow.isRevisionMode
      ? .revisionDraft(revision: flow.revision)
      : flow.isSealed ? .sealed(revision: flow.revision) : .notSealed
    return CaptureOverviewState(
      title: ProjectTitle.of(record), dealId: record.hub.dealId,
      subtitle: CaptureOverviewState.subtitle(
        visitedAt: record.visitedAt.date, now: input.now, operatorName: record.operator.name,
        sealState: sealState, timeZone: input.timeZone),
      floors: floorRows(input), canAddFloor: !flow.isReadOnly,
      checks: [photosRow(input), controlsRow(input), compassRow(input), skippedRoomsRow(input)],
      button: button(input))
  }

  // MARK: Floors

  static func floorRows(_ input: Input) -> [CaptureOverviewState.FloorRow] {
    let record = input.record
    let floors = controlsFloors(input)
    let sections = ControlsList.sections(
      floors: floors, controls: input.controls, policy: input.policy)
    let photoGaps = input.checklist.item(.photoPerRoom).gaps
    let controlGaps = input.checklist.item(.minimumControls).gaps
    return record.captures.map { capture in
      let label = capture.label.trimmingCharacters(in: .whitespaces)
      switch input.scans[capture.captureId] ?? .loading {
      case .loading:
        return .loading(areaKey: capture.areaKey, label: label)
      case .failed:
        return .unreadable(areaKey: capture.areaKey, label: label, mode: capture.mode)
      case .mapped:
        let section = sections.first { $0.target == .floor(capture.captureId) }
        let word = section.map { ControlsList.floorState($0, policy: input.policy).rawValue }
        let hasPhotoGap = photoGaps.contains { gap in
          switch gap {
          case .roomWithoutPhoto(let gapCapture, _), .captureWithoutPhoto(let gapCapture):
            return gapCapture == capture.label || gapCapture == label
          default: return false
          }
        }
        let hasControlGap = controlGaps.contains { gap in
          switch gap {
          case .missingDistance(let gapCapture, _), .missingCeilingHeight(let gapCapture):
            return gapCapture == label
          default: return false
          }
        }
        let rooms = input.rooms[capture.captureId]?.count ?? 0
        let photos = input.photos.filter { $0.captureId == capture.captureId }.count
        // Exterior captures need no field controls (ControlsList leaves them out).
        let controls = word ?? "not needed"
        guard capture.source.isMeasuredPlan else {
          return .scanned(
            areaKey: capture.areaKey, label: label, mode: capture.mode, rooms: rooms,
            photos: photos, controls: controls, isDone: !hasPhotoGap && !hasControlGap)
        }
        return sketchRow(
          areaKey: capture.areaKey, label: label, mode: capture.mode, source: capture.source,
          isLimited: capture.sketch?.measurements == .limited, rooms: rooms, photos: photos,
          controls: controls, isDone: !hasPhotoGap && !hasControlGap)
      }
    }
  }

  /// A sketch capture's floor row (spec F14 1.5, 2.4): "[Mode] · sketch[ · limited] · [R] rooms
  /// · [P] photos · controls [STATE]", the scanned row's words with the source after the mode
  /// and "limited" when the solver estimated something. The controls word says "from the
  /// sketch" where a scan says "from the scan". An AR walkthrough (spec F15) says "walked" and
  /// "from the walkthrough".
  static func sketchRow(
    areaKey: String, label: String, mode: CaptureMode, source: CaptureSource = .sketch,
    isLimited: Bool, rooms: Int, photos: Int, controls: String, isDone: Bool
  ) -> CaptureOverviewState.FloorRow {
    let walked = source == .walkthrough
    let scanned = CaptureOverviewState.FloorRow.scanned(
      areaKey: areaKey, label: label, mode: mode, rooms: rooms, photos: photos,
      controls: controls == FloorControlsState.fromScan.rawValue
        ? (walked ? "from the walkthrough" : "from the sketch") : controls,
      isDone: isDone)
    var parts = scanned.subtitle.components(separatedBy: " · ")
    let word = walked ? "walked" : "sketch"
    parts.insert(isLimited ? "\(word) · limited" : word, at: 1)
    return CaptureOverviewState.FloorRow(
      id: scanned.id, title: scanned.title, subtitle: parts.joined(separator: " · "),
      status: scanned.status)
  }

  /// The captures as the controls list sees them, with each one's rooms and scan.
  static func controlsFloors(_ input: Input) -> [ControlsFloor] {
    input.record.captures.map { capture in
      var scan: ScanMeasurements?
      if case .mapped(let measured) = input.scans[capture.captureId] { scan = measured }
      return ControlsFloor(
        capture: capture, rooms: input.rooms[capture.captureId] ?? [], scan: scan)
    }
  }

  // MARK: Before you leave

  static func photosRow(_ input: Input) -> CaptureOverviewState.CheckRow {
    let item = input.checklist.item(.photoPerRoom)
    guard !item.passed else {
      return .init(.photos, subtitle: "Every room has a photo", status: .init(.done, "Done"))
    }
    return .init(
      .photos, subtitle: photoGapText(item.gaps), status: .init(.missing, "Missing"))
  }

  /// "Bath 2 has no photo", "Floor 2 has no photo", "Kitchen and 3 more rooms have no photo".
  public static func photoGapText(_ gaps: [ChecklistGap]) -> String {
    var subjects: [String] = []
    var allRooms = true
    for gap in gaps {
      switch gap {
      case .roomWithoutPhoto(_, let room): subjects.append(room)
      case .captureWithoutPhoto(let capture):
        subjects.append(capture)
        allRooms = false
      default: continue
      }
    }
    guard let first = subjects.first else { return "" }
    if subjects.count == 1 { return "\(first) has no photo" }
    let more = subjects.count - 1
    return allRooms
      ? "\(first) and \(more) more \(more == 1 ? "room" : "rooms") have no photo"
      : "\(first) and \(more) more have no photo"
  }

  /// Where the Photos row leads: the first gap's capture and room, else the last capture.
  public static func photoTarget(record: CaptureRecord, checklist: ChecklistReport) -> (
    captureId: LowercaseUUID, room: String?
  )? {
    for gap in checklist.item(.photoPerRoom).gaps {
      switch gap {
      case .roomWithoutPhoto(let label, let room):
        if let capture = capture(labelled: label, in: record) { return (capture.captureId, room) }
      case .captureWithoutPhoto(let label):
        if let capture = capture(labelled: label, in: record) { return (capture.captureId, nil) }
      default: continue
      }
    }
    return record.captures.last.map { ($0.captureId, nil) }
  }

  static func controlsRow(_ input: Input) -> CaptureOverviewState.CheckRow {
    let item = input.checklist.item(.minimumControls)
    guard !item.passed else {
      // The standard policy passes on the scan's own values and says so, as Before you leave
      // does; the manual policy's minimum set is complete.
      let subtitle =
        input.policy.manualControlsRequired ? "Minimum set complete" : item.detail
      return .init(.controls, subtitle: subtitle, status: .init(.done, "Done"))
    }
    return .init(
      .controls, subtitle: controlsGapText(item.gaps, floorCount: floorCount(input)),
      status: .init(.missing, "Missing"))
  }

  /// The failing Field controls subtitle (critique R-37): the gaps between floors only (`Floor
  /// to floor`, `1 landmark`), joined "X missing", "X and Y missing", "X, Y and Z missing", "X, Y
  /// and 2 more missing"; when only floors miss controls, `Missing on Floor 2` (`Floor 1 and
  /// Floor 2`, `Floor 1, Floor 2 and Floor 3`). The floor rows show the per-floor gaps.
  public static func controlsGapText(_ gaps: [ChecklistGap], floorCount: Int) -> String {
    let showPair = floorCount > 2
    var between: [String] = []
    var floors: [String] = []
    for gap in gaps {
      switch gap {
      case .missingFloorToFloor:
        between.append(gap.compactText(showCapture: false, showPair: showPair))
      case .missingLandmarks(let lower, let upper, let have, let need):
        let missing = max(1, need - have)
        between.append(
          "\(missing) \(missing == 1 ? "landmark" : "landmarks")"
            + (showPair ? " between \(lower) and \(upper)" : ""))
      case .missingDistance(let capture, _), .missingCeilingHeight(let capture):
        if !floors.contains(capture) { floors.append(capture) }
      default: continue
      }
    }
    if !between.isEmpty { return "\(join(between, limit: 3)) missing" }
    guard !floors.isEmpty else { return "" }
    return "Missing on \(join(floors, limit: Int.max))"
  }

  /// "A", "A and B", "A, B and C"; beyond `limit` items "A, B and 3 more".
  static func join(_ items: [String], limit: Int) -> String {
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    case 2: return "\(items[0]) and \(items[1])"
    default:
      if items.count > limit {
        return "\(items[0]), \(items[1]) and \(items.count - 2) more"
      }
      return items.dropLast().joined(separator: ", ") + " and \(items.last!)"
    }
  }

  static func compassRow(_ input: Input) -> CaptureOverviewState.CheckRow {
    let entries = input.checklist.compass.isEmpty
      ? CompassSummary.entries(record: input.record) : input.checklist.compass
    // Sketch and walkthrough captures only (spec F14 1.7, F15 5): no scan frame to read a
    // heading into; the plan is oriented as drawn or walked and no compass is asked for.
    if entries.isEmpty, !input.record.captures.isEmpty {
      return .init(
        .compass, subtitle: CompassSummary.noScanDetail(input.record.captures),
        status: .init(.waiting, "Not needed"))
    }
    let overview = CompassSummary.overview(entries)
    if overview == .verified {
      return .init(.compass, subtitle: "Every floor verified", status: .init(.done, "Verified"))
    }
    // ▲, never ■: the compass is recommended, not required.
    return .init(
      .compass, subtitle: CompassSummary.short(entries), status: .init(.partly, overview.word))
  }

  static func skippedRoomsRow(_ input: Input) -> CaptureOverviewState.CheckRow {
    let item = input.checklist.item(.skippedRoomsRecorded)
    guard item.passed else {
      let subtitle =
        item.gaps.contains(.skippedRoomsNotRecorded)
        ? "Record skipped rooms, or confirm none were skipped" : item.detail
      return .init(.skippedRooms, subtitle: subtitle, status: .init(.missing, "Missing"))
    }
    let notes = input.record.captures.flatMap { $0.omittedRooms + $0.inaccessibleRooms }
    guard let first = notes.first else {
      return .init(.skippedRooms, subtitle: "All rooms scanned", status: .init(.done, "Recorded"))
    }
    var subtitle = first.name
    if let reason = first.reason, !reason.isEmpty { subtitle += " \u{00B7} \(reason)" }
    if notes.count > 1 { subtitle += ", +\(notes.count - 1) more" }
    return .init(.skippedRooms, subtitle: subtitle, status: .init(.done, "Recorded"))
  }

  // MARK: Button

  /// The bottom button (phone-capture addendum A4): "Fix N items" while blocking items fail
  /// (the compass never counts), "Review the package" / "Review revision R" when they pass,
  /// "Upload status" / "Open the verdict" once sealed.
  static func button(_ input: Input) -> CaptureOverviewState.ReviewButton {
    let flow = input.flow
    if flow.isReadOnly {
      return input.newestPackageHasVerdict ? .openVerdict : .uploadStatus
    }
    let blocking = input.checklist.blockingItems.count
    if blocking > 0 { return .fix(items: blocking) }
    return flow.isRevisionMode ? .reviewRevision(flow.revision) : .reviewPackage
  }

  // MARK: Private

  private static func floorCount(_ input: Input) -> Int {
    ControlsList.floors(input.record.captures.map { ControlsFloor(capture: $0) }).count
  }

  private static func capture(labelled label: String, in record: CaptureRecord)
    -> CaptureRecord.Capture?
  {
    let trimmed = label.trimmingCharacters(in: .whitespaces)
    return record.captures.first {
      $0.label == label || $0.label.trimmingCharacters(in: .whitespaces) == trimmed
    }
  }
}
