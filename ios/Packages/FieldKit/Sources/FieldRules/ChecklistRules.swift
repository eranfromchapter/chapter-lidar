import CaptureContract
import Foundation

// The before-leaving checklist (design v2, artboard 2d-4). Pure rules over the capture record,
// the saved photos and the field controls; nothing here touches the file system, a camera or the
// UI. "Finish capture" is blocked until `ChecklistReport.canFinish`, and `ChecklistReport.gaps`
// lists exactly what is missing. The compass item is advisory: it is shown, never blocks.

/// Everything the checklist looks at.
public struct ChecklistInput: Sendable {
  public var record: CaptureRecord
  /// Room labels of each capture, from its capture model (`CaptureModel.rooms[].label`).
  /// A capture with no entry or an empty list needs at least one photo of any kind.
  public var capturedRooms: [LowercaseUUID: [String]]
  public var photos: [PhotoRecord]
  public var controls: FieldControls
  /// The operator confirmed that every room was scanned (none omitted or inaccessible). Needed
  /// only when the capture record lists no room not scanned.
  public var noRoomsSkippedConfirmed: Bool
  /// The compass of a capture when the caller knows better than its stored reading; a capture
  /// not in here is evaluated from the record (`CaptureCompassStatus(capture:)`, the contract's
  /// evaluator; a 1.0.0 record has no reading: `notRead`).
  public var compass: [LowercaseUUID: CaptureCompassStatus]

  public init(
    record: CaptureRecord,
    capturedRooms: [LowercaseUUID: [String]] = [:],
    photos: [PhotoRecord] = [],
    controls: FieldControls,
    noRoomsSkippedConfirmed: Bool = false,
    compass: [LowercaseUUID: CaptureCompassStatus] = [:]
  ) {
    self.record = record
    self.capturedRooms = capturedRooms
    self.photos = photos
    self.controls = controls
    self.noRoomsSkippedConfirmed = noRoomsSkippedConfirmed
    self.compass = compass
  }
}

/// Tunable minimums. `standard` is the shipping rule set.
public struct ChecklistPolicy: Hashable, Sendable {
  /// Shared landmarks needed between each pair of consecutive floors. Two landmarks fix both the
  /// position and the rotation of one floor against the next.
  public var minimumLandmarksPerFloorPair: Int
  /// True: the tape or laser controls below must be recorded before the visit can finish.
  /// False (standard, decided by Eran 2026-10-18): the LiDAR scan provides the measurements and
  /// tape or laser checks are optional; the item passes and counts the checks that exist.
  public var manualControlsRequired: Bool

  public init(minimumLandmarksPerFloorPair: Int = 2, manualControlsRequired: Bool = false) {
    self.minimumLandmarksPerFloorPair = minimumLandmarksPerFloorPair
    self.manualControlsRequired = manualControlsRequired
  }

  public static let standard = ChecklistPolicy()
  /// Every floor needs its tape or laser controls (the original rule, drawn in design v2).
  public static let manualControls = ChecklistPolicy(manualControlsRequired: true)

  /// The policy the app ships with: the one constant that switches the Field controls list and
  /// Before you leave between the two renderings (owner question Q-A; default kept at
  /// `.standard`, the scan provides the measurements).
  public static let shipping: ChecklistPolicy = .standard
}

public enum ChecklistItemID: String, CaseIterable, Sendable {
  case floorsLabeled
  case skippedRoomsRecorded
  case photoPerRoom
  case minimumControls
  case compass
  case visitDetails

  /// Wording of the checklist row (design v2, artboard 2d-4).
  public var title: String {
    switch self {
    case .floorsLabeled: return "Every floor and area labeled"
    case .skippedRoomsRecorded: return "Rooms not scanned recorded"
    case .photoPerRoom: return "A photo for every room"
    case .minimumControls: return "Minimum field controls"
    case .compass: return "Compass reading"
    case .visitDetails: return "Device, mode, date, operator"
    }
  }

  /// Blocking items stop "Finish capture"; the compass is recommended, not required.
  public var severity: ChecklistSeverity {
    self == .compass ? .advisory : .blocking
  }
}

/// Whether a failing item stops the package.
public enum ChecklistSeverity: String, Sendable {
  /// ■ when failing; counted in "Fix 2 items to finish".
  case blocking
  /// ▲ when failing; shown, never counted, never blocks.
  case advisory
}

/// One thing that is missing. Equatable so tests and the UI can compare exactly.
public enum ChecklistGap: Hashable, Sendable {
  public enum SkippedKind: String, Hashable, Sendable {
    case omitted
    case inaccessible
  }

  public enum VisitDetail: Hashable, Sendable {
    case device
    case operatingSystem
    case operatorName
    case visitDate
    case captureDate(capture: String)
  }

  case noCaptures
  case unlabeledCapture(areaKey: String)
  case skippedRoomsNotRecorded
  case skippedRoomWithoutName(SkippedKind)
  case skippedRoomWithoutReason(room: String)
  case roomWithoutPhoto(capture: String, room: String)
  case captureWithoutPhoto(capture: String)
  case missingDistance(capture: String, axis: DistanceAxis)
  case missingCeilingHeight(capture: String)
  case missingFloorToFloor(lower: String, upper: String)
  case missingLandmarks(lower: String, upper: String, have: Int, need: Int)
  case missingDetail(VisitDetail)

  /// Plain-language text. `showCapture` adds the floor name to per-floor control gaps and
  /// `showPair` adds the two floors to floor-to-floor gaps; they are set only when the visit has
  /// more than one floor (more than two for `showPair`), so the usual text stays short
  /// ("Bath 2 has no photo", "Floor to floor missing"). A missing-photo gap always carries its
  /// capture in the case payload; its text does not repeat it.
  public func text(showCapture: Bool, showPair: Bool) -> String {
    func on(_ capture: String) -> String { showCapture ? " on \(capture)" : "" }
    switch self {
    case .noCaptures:
      return "No floor or area has been captured"
    case .unlabeledCapture(let areaKey):
      return "Capture \(areaKey) has no label"
    case .skippedRoomsNotRecorded:
      return "Record rooms not scanned, or confirm there are none"
    case .skippedRoomWithoutName:
      return "A room not scanned has no name"
    case .skippedRoomWithoutReason(let room):
      return "\(room): reason missing"
    case .roomWithoutPhoto(_, let room):
      return "\(room) has no photo"
    case .captureWithoutPhoto(let capture):
      return "\(capture) has no photo"
    case .missingDistance(let capture, let axis):
      return "Long distance \(axis.rawValue) missing\(on(capture))"
    case .missingCeilingHeight(let capture):
      return "Ceiling height missing\(on(capture))"
    case .missingFloorToFloor(let lower, let upper):
      return showPair
        ? "Floor to floor missing between \(lower) and \(upper)" : "Floor to floor missing"
    case .missingLandmarks(let lower, let upper, let have, let need):
      return showPair
        ? "\(have) of \(need) landmarks between \(lower) and \(upper)"
        : "\(have) of \(need) landmarks"
    case .missingDetail(let detail):
      switch detail {
      case .device: return "Device model missing"
      case .operatingSystem: return "Operating system version missing"
      case .operatorName: return "Operator missing"
      case .visitDate: return "Visit date missing"
      case .captureDate(let capture): return "Capture date missing for \(capture)"
      }
    }
  }

  /// The short wording of a "Minimum field controls" gap on Before you leave (phone-field §6.3):
  /// `Long distance A` (`Long distance A on Floor 2` with more than one floor), `Ceiling height`,
  /// `Floor to floor` (`Floor to floor between Floor 2 and Floor 3` with more than two floors),
  /// `1 of 2 landmarks`. Other gaps use `text`. A floor missing A, B and its ceiling height at
  /// once reads `Floor 2 set` (`ChecklistRules`).
  public func compactText(showCapture: Bool, showPair: Bool) -> String {
    switch self {
    case .missingDistance(let capture, let axis):
      return "Long distance \(axis.rawValue)" + (showCapture ? " on \(capture)" : "")
    case .missingCeilingHeight(let capture):
      return "Ceiling height" + (showCapture ? " on \(capture)" : "")
    case .missingFloorToFloor(let lower, let upper):
      return "Floor to floor" + (showPair ? " between \(lower) and \(upper)" : "")
    case .missingLandmarks(let lower, let upper, let have, let need):
      return "\(have) of \(need) landmarks" + (showPair ? " between \(lower) and \(upper)" : "")
    default:
      return text(showCapture: showCapture, showPair: showPair)
    }
  }
}

extension ChecklistGap: CustomStringConvertible {
  public var description: String { text(showCapture: true, showPair: true) }
}

public struct ChecklistItem: Hashable, Sendable {
  public let id: ChecklistItemID
  public let passed: Bool
  /// Second line of the row: what was found, or what is missing.
  public let detail: String
  /// Exactly what is missing; empty when `passed`, and always empty for the advisory compass
  /// item (its detail says which captures are not verified).
  public let gaps: [ChecklistGap]

  public init(id: ChecklistItemID, passed: Bool, detail: String, gaps: [ChecklistGap]) {
    self.id = id
    self.passed = passed
    self.detail = detail
    self.gaps = gaps
  }

  public var title: String { id.title }
  public var severity: ChecklistSeverity { id.severity }
  /// A failing blocking item: ■, red detail, counted in "Fix 2 items to finish".
  public var isBlocking: Bool { !passed && severity == .blocking }
}

/// Raised when finishing is attempted while the checklist has gaps.
public struct ChecklistBlockedError: Error, Equatable, Sendable, CustomStringConvertible {
  public let gaps: [ChecklistGap]
  public var description: String {
    "The before-leaving checklist is not complete: "
      + gaps.map(\.description).joined(separator: "; ")
  }
}

public struct ChecklistReport: Hashable, Sendable {
  /// One item per `ChecklistItemID`, in checklist order.
  public let items: [ChecklistItem]
  /// Every capture's compass, in record order: the compass item's detail; "Read" takes the
  /// first capture that is not verified.
  public let compass: [CompassSummary.Entry]

  public init(items: [ChecklistItem], compass: [CompassSummary.Entry] = []) {
    self.items = items
    self.compass = compass
  }

  /// Every item that did not pass, the advisory compass included.
  public var failedItems: [ChecklistItem] { items.filter { !$0.passed } }
  /// The failing items that stop the package (the compass never does).
  public var blockingItems: [ChecklistItem] { items.filter(\.isBlocking) }
  /// "Finish capture" is allowed when every blocking item passes.
  public var canFinish: Bool { blockingItems.isEmpty }
  /// Every missing thing across all items, in checklist order.
  public var gaps: [ChecklistGap] { items.flatMap(\.gaps) }

  /// Label of the primary button: "Finish capture" or "Fix 2 items to finish" (blocking items
  /// only).
  public var finishButtonTitle: String {
    let count = blockingItems.count
    if count == 0 { return "Finish capture" }
    return "Fix \(count) \(count == 1 ? "item" : "items") to finish"
  }

  public func item(_ id: ChecklistItemID) -> ChecklistItem {
    items.first { $0.id == id }!
  }

  /// The first capture whose compass is not verified (what "Read" would read); nil when all are.
  public var firstCaptureWithoutVerifiedCompass: LowercaseUUID? {
    compass.first { $0.status != .verified }?.captureId
  }

  /// Throws `ChecklistBlockedError` listing every gap unless the blocking items passed. The
  /// compass is ignored.
  public func requireCanFinish() throws {
    guard canFinish else { throw ChecklistBlockedError(gaps: gaps) }
  }
}

public enum ChecklistRules {
  public static func evaluate(
    _ input: ChecklistInput, policy: ChecklistPolicy = .shipping
  ) -> ChecklistReport {
    let captures = input.record.captures
    let wording = Wording(showCapture: captures.count > 1, showPair: captures.count > 2)
    let compass = CompassSummary.entries(record: input.record, overrides: input.compass)
    return ChecklistReport(
      items: [
        floorsLabeled(captures, wording),
        skippedRooms(captures, input, wording),
        photoPerRoom(captures, input, wording),
        minimumControls(captures, input, policy),
        compassItem(compass, captures: captures),
        visitDetails(input, wording),
      ],
      compass: compass)
  }

  /// The caption at the right of Before you leave's navigation bar (phone-field §6.1): the HUB
  /// project name, else the address up to its first comma (`618 Valley Street`).
  public static func propertyCaption(_ record: CaptureRecord) -> String {
    if let name = record.hub.projectName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    {
      return name
    }
    let address = record.address.formatted
    let street = address.split(separator: ",", maxSplits: 1).first.map(String.init) ?? address
    return street.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  struct Wording {
    var showCapture: Bool
    var showPair: Bool
  }

  private static func item(
    _ id: ChecklistItemID, gaps: [ChecklistGap], passedDetail: String, _ wording: Wording
  ) -> ChecklistItem {
    let detail =
      gaps.isEmpty
      ? passedDetail
      : gaps.map { $0.text(showCapture: wording.showCapture, showPair: wording.showPair) }
        .joined(separator: " \u{00B7} ")
    return ChecklistItem(id: id, passed: gaps.isEmpty, detail: detail, gaps: gaps)
  }

  private static func isBlank(_ text: String?) -> Bool {
    text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
  }

  // MARK: 1 Every floor and area labeled

  private static func floorsLabeled(
    _ captures: [CaptureRecord.Capture], _ wording: Wording
  ) -> ChecklistItem {
    var gaps: [ChecklistGap] = []
    if captures.isEmpty { gaps.append(.noCaptures) }
    for capture in captures where isBlank(capture.label) {
      gaps.append(.unlabeledCapture(areaKey: capture.areaKey))
    }
    return item(
      .floorsLabeled, gaps: gaps,
      passedDetail: captures.map { $0.label.trimmingCharacters(in: .whitespaces) }
        .joined(separator: ", "), wording)
  }

  // MARK: 2 Rooms not scanned recorded

  private static func skippedRooms(
    _ captures: [CaptureRecord.Capture], _ input: ChecklistInput, _ wording: Wording
  ) -> ChecklistItem {
    var gaps: [ChecklistGap] = []
    var found: [String] = []
    let notes =
      captures.flatMap { capture in
        capture.omittedRooms.map { (ChecklistGap.SkippedKind.omitted, $0) }
          + capture.inaccessibleRooms.map { (ChecklistGap.SkippedKind.inaccessible, $0) }
      }
    for (kind, note) in notes {
      if isBlank(note.name) {
        gaps.append(.skippedRoomWithoutName(kind))
      } else if isBlank(note.reason) {
        gaps.append(.skippedRoomWithoutReason(room: note.name))
      } else {
        found.append("\(note.name) \u{00B7} \(note.reason ?? "")")
      }
    }
    if notes.isEmpty && !input.noRoomsSkippedConfirmed && !captures.isEmpty {
      gaps.append(.skippedRoomsNotRecorded)
    }
    return item(
      .skippedRoomsRecorded, gaps: gaps,
      passedDetail: found.isEmpty ? "All rooms scanned" : found.joined(separator: "; "), wording)
  }

  // MARK: 3 A photo for every room

  /// Per capture, `PhotoCoverage` (the photo step shows the same rule): every room of its
  /// capture model needs a photo labeled with its name; a capture without a room list needs a
  /// photo of any kind.
  private static func photoPerRoom(
    _ captures: [CaptureRecord.Capture], _ input: ChecklistInput, _ wording: Wording
  ) -> ChecklistItem {
    var gaps: [ChecklistGap] = []
    var roomCount = 0
    for capture in captures {
      let coverage = PhotoCoverage.status(
        rooms: input.capturedRooms[capture.captureId] ?? [],
        photos: input.photos.filter { $0.captureId == capture.captureId })
      roomCount += coverage.rooms.count
      if coverage.needsAnyPhoto { gaps.append(.captureWithoutPhoto(capture: capture.label)) }
      for room in coverage.roomsWithoutPhoto {
        gaps.append(.roomWithoutPhoto(capture: capture.label, room: room))
      }
    }
    let total = input.photos.count
    return item(
      .photoPerRoom, gaps: gaps,
      passedDetail: "\(total) \(total == 1 ? "photo" : "photos")"
        + (roomCount > 0 ? ", \(roomCount) \(roomCount == 1 ? "room" : "rooms") covered" : ""),
      wording)
  }

  // MARK: 4 Minimum field controls

  /// Per floor or area (every capture except `exterior`): long distance A, long distance B and
  /// one ceiling height. For each pair of consecutive floors (by capture time): one
  /// floor-to-floor level and the policy's number of shared landmarks. The gaps come from
  /// `ControlsList.gaps` in the order of the Field controls list, so both screens agree; the
  /// detail is the short wording of phone-field §6.3 (`Floor to floor · 1 of 2 landmarks ·
  /// Floor 2 set`).
  private static func minimumControls(
    _ captures: [CaptureRecord.Capture], _ input: ChecklistInput, _ policy: ChecklistPolicy
  ) -> ChecklistItem {
    let controls = input.controls
    guard policy.manualControlsRequired else {
      let checks =
        controls.distances.count + controls.ceilingHeights.count + controls.openings.count
        + controls.floorToFloor.count + controls.landmarks.count
      // A visit of sketch or walkthrough captures only (spec F14, F15): the measurements are
      // the operator's.
      let measured = measuredBy(captures)
      let detail =
        checks == 0
        ? measured
        : "\(measured) \u{00B7} \(checks) tape or laser \(checks == 1 ? "check" : "checks")"
      return ChecklistItem(id: .minimumControls, passed: true, detail: detail, gaps: [])
    }
    let floors = ControlsList.floors(captures.map { ControlsFloor(capture: $0) })
    let gaps = ControlsList.gaps(floors: floors, controls: controls, policy: policy)
    guard !gaps.isEmpty else {
      return ChecklistItem(
        id: .minimumControls, passed: true, detail: "All minimum controls recorded", gaps: [])
    }
    let showCapture = floors.count > 1
    let showPair = floors.count > 2
    var parts: [String] = []
    var index = 0
    while index < gaps.count {
      // A floor with nothing recorded is one "Floor 2 set", not three gaps.
      if case .missingDistance(let capture, .a) = gaps[index], index + 2 < gaps.count,
        gaps[index + 1] == .missingDistance(capture: capture, axis: .b),
        gaps[index + 2] == .missingCeilingHeight(capture: capture)
      {
        parts.append("\(capture) set")
        index += 3
        continue
      }
      parts.append(gaps[index].compactText(showCapture: showCapture, showPair: showPair))
      index += 1
    }
    return ChecklistItem(
      id: .minimumControls, passed: false, detail: parts.joined(separator: " \u{00B7} "),
      gaps: gaps)
  }

  /// Who measured a visit's floors, for the controls item when manual controls are optional:
  /// the LiDAR scan, the sketch (spec F14), the AR walkthrough (spec F15), or both of the last.
  static func measuredBy(_ captures: [CaptureRecord.Capture]) -> String {
    guard !captures.isEmpty, captures.allSatisfy({ $0.source.isMeasuredPlan }) else {
      return "Measured by the LiDAR scan"
    }
    if captures.allSatisfy({ $0.source == .sketch }) { return "Measured from the sketch" }
    if captures.allSatisfy({ $0.source == .walkthrough }) { return "Measured by the AR walkthrough" }
    return "Measured from the sketch and the AR walkthrough"
  }

  // MARK: 5 Compass reading (advisory)

  /// Passes when every capture's compass is verified; otherwise ▲ with the per-capture words
  /// and what the plans will say. Never blocks and carries no gaps. A visit of sketch or AR
  /// walkthrough captures only has no compass to read (spec F14 1.7, F15 5): the item passes
  /// and says so.
  private static func compassItem(
    _ entries: [CompassSummary.Entry], captures: [CaptureRecord.Capture]
  ) -> ChecklistItem {
    guard !entries.isEmpty else {
      if !captures.isEmpty {
        return ChecklistItem(
          id: .compass, passed: true, detail: CompassSummary.noScanDetail(captures), gaps: [])
      }
      return ChecklistItem(
        id: .compass, passed: false, detail: "No floor or area has been captured", gaps: [])
    }
    return ChecklistItem(
      id: .compass, passed: CompassSummary.allVerified(entries),
      detail: CompassSummary.detail(entries), gaps: [])
  }

  // MARK: 6 Device, mode, date, operator

  /// The capture mode is a required enum on every capture, so it cannot be missing; device,
  /// operator and the visit and capture dates can.
  private static func visitDetails(_ input: ChecklistInput, _ wording: Wording) -> ChecklistItem {
    let record = input.record
    var gaps: [ChecklistGap] = []
    if isBlank(record.device.model) { gaps.append(.missingDetail(.device)) }
    if isBlank(record.device.osVersion) { gaps.append(.missingDetail(.operatingSystem)) }
    if isBlank(record.operator.name) { gaps.append(.missingDetail(.operatorName)) }
    if record.visitedAt.secondsSince1970 <= 0 { gaps.append(.missingDetail(.visitDate)) }
    for capture in record.captures where capture.capturedAt.secondsSince1970 <= 0 {
      gaps.append(.missingDetail(.captureDate(capture: capture.label)))
    }
    return item(.visitDetails, gaps: gaps, passedDetail: "Filled automatically", wording)
  }
}
