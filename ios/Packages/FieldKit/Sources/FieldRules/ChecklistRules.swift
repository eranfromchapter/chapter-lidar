import CaptureContract
import Foundation

// The before-leaving checklist. Pure rules over the capture record, the saved photos and the
// field controls; nothing here touches the file system, a camera or the UI. "Finish capture" is
// blocked until `ChecklistReport.canFinish`, and `ChecklistReport.gaps` lists exactly what is
// missing.

/// Everything the checklist looks at.
public struct ChecklistInput: Sendable {
  public var record: CaptureRecord
  /// Room labels of each capture, from its capture model (`CaptureModel.rooms[].label`).
  /// A capture with no entry or an empty list needs at least one photo of any kind.
  public var capturedRooms: [LowercaseUUID: [String]]
  public var photos: [PhotoRecord]
  public var controls: FieldControls
  /// The operator confirmed that no room was omitted or inaccessible. Needed only when the
  /// capture record lists none.
  public var noRoomsSkippedConfirmed: Bool

  public init(
    record: CaptureRecord,
    capturedRooms: [LowercaseUUID: [String]] = [:],
    photos: [PhotoRecord] = [],
    controls: FieldControls,
    noRoomsSkippedConfirmed: Bool = false
  ) {
    self.record = record
    self.capturedRooms = capturedRooms
    self.photos = photos
    self.controls = controls
    self.noRoomsSkippedConfirmed = noRoomsSkippedConfirmed
  }
}

/// Tunable minimums. `standard` is the v1 rule set.
public struct ChecklistPolicy: Hashable, Sendable {
  /// Shared landmarks needed between each pair of consecutive floors. Two landmarks fix both the
  /// position and the rotation of one floor against the next.
  public var minimumLandmarksPerFloorPair: Int

  public init(minimumLandmarksPerFloorPair: Int = 2) {
    self.minimumLandmarksPerFloorPair = minimumLandmarksPerFloorPair
  }

  public static let standard = ChecklistPolicy()
}

public enum ChecklistItemID: String, CaseIterable, Sendable {
  case floorsLabeled
  case skippedRoomsRecorded
  case photoPerRoom
  case minimumControls
  case visitDetails

  /// Wording of the checklist row (frozen design).
  public var title: String {
    switch self {
    case .floorsLabeled: return "Every floor and area labeled"
    case .skippedRoomsRecorded: return "Skipped rooms recorded"
    case .photoPerRoom: return "A photo for every room"
    case .minimumControls: return "Minimum field controls"
    case .visitDetails: return "Device, mode, date, operator"
    }
  }
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
      return "Record skipped rooms, or confirm none were skipped"
    case .skippedRoomWithoutName(let kind):
      return "A \(kind.rawValue) room has no name"
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
}

extension ChecklistGap: CustomStringConvertible {
  public var description: String { text(showCapture: true, showPair: true) }
}

public struct ChecklistItem: Hashable, Sendable {
  public let id: ChecklistItemID
  public let passed: Bool
  /// Second line of the row: what was found, or what is missing.
  public let detail: String
  /// Exactly what is missing; empty when `passed`.
  public let gaps: [ChecklistGap]

  public var title: String { id.title }
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

  public var failedItems: [ChecklistItem] { items.filter { !$0.passed } }
  /// "Finish capture" is allowed only when every item passes.
  public var canFinish: Bool { failedItems.isEmpty }
  /// Every missing thing across all items, in checklist order.
  public var gaps: [ChecklistGap] { items.flatMap(\.gaps) }

  /// Label of the primary button: "Finish capture" or "Fix 2 items to finish".
  public var finishButtonTitle: String {
    let count = failedItems.count
    if count == 0 { return "Finish capture" }
    return "Fix \(count) \(count == 1 ? "item" : "items") to finish"
  }

  public func item(_ id: ChecklistItemID) -> ChecklistItem {
    items.first { $0.id == id }!
  }

  /// Throws `ChecklistBlockedError` listing every gap unless the checklist passed.
  public func requireCanFinish() throws {
    guard canFinish else { throw ChecklistBlockedError(gaps: gaps) }
  }
}

public enum ChecklistRules {
  public static func evaluate(
    _ input: ChecklistInput, policy: ChecklistPolicy = .standard
  ) -> ChecklistReport {
    let captures = input.record.captures
    let wording = Wording(showCapture: captures.count > 1, showPair: captures.count > 2)
    return ChecklistReport(items: [
      floorsLabeled(captures, wording),
      skippedRooms(captures, input, wording),
      photoPerRoom(captures, input, wording),
      minimumControls(captures, input, policy, wording),
      visitDetails(input, wording),
    ])
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

  private static func normalized(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

  // MARK: 2 Skipped rooms recorded

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
      passedDetail: found.isEmpty ? "No rooms skipped" : found.joined(separator: "; "), wording)
  }

  // MARK: 3 A photo for every room

  private static func photoPerRoom(
    _ captures: [CaptureRecord.Capture], _ input: ChecklistInput, _ wording: Wording
  ) -> ChecklistItem {
    var gaps: [ChecklistGap] = []
    var roomCount = 0
    for capture in captures {
      let photos = input.photos.filter { $0.captureId == capture.captureId }
      var seen = Set<String>()
      let rooms = (input.capturedRooms[capture.captureId] ?? []).filter {
        !isBlank($0) && seen.insert(normalized($0)).inserted
      }
      if rooms.isEmpty {
        if photos.isEmpty { gaps.append(.captureWithoutPhoto(capture: capture.label)) }
        continue
      }
      for room in rooms {
        roomCount += 1
        if !photos.contains(where: { normalized($0.room) == normalized(room) }) {
          gaps.append(.roomWithoutPhoto(capture: capture.label, room: room))
        }
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
  /// floor-to-floor level and the policy's number of shared landmarks.
  private static func minimumControls(
    _ captures: [CaptureRecord.Capture], _ input: ChecklistInput, _ policy: ChecklistPolicy,
    _ wording: Wording
  ) -> ChecklistItem {
    let floors = captures.enumerated()
      .filter { $0.element.mode != .exterior }
      .sorted {
        ($0.element.capturedAt, $0.offset) < ($1.element.capturedAt, $1.offset)
      }
      .map(\.element)
    let controls = input.controls
    var gaps: [ChecklistGap] = []

    for floor in floors {
      let id = floor.captureId
      for axis in [DistanceAxis.a, .b]
      where !controls.distances.contains(where: { $0.capture.captureId == id && $0.axis == axis }) {
        gaps.append(.missingDistance(capture: floor.label, axis: axis))
      }
      if !controls.ceilingHeights.contains(where: { $0.capture.captureId == id }) {
        gaps.append(.missingCeilingHeight(capture: floor.label))
      }
    }

    for (lower, upper) in zip(floors, floors.dropFirst()) {
      let ids: Set<LowercaseUUID> = [lower.captureId, upper.captureId]
      let hasLevel = controls.floorToFloor.contains {
        Set([$0.lower.captureId, $0.upper.captureId]) == ids
      }
      if !hasLevel {
        gaps.append(.missingFloorToFloor(lower: lower.label, upper: upper.label))
      }
      let shared = controls.landmarks.filter { landmark in
        let landmarkIds = Set(landmark.captures.map(\.captureId))
        return ids.isSubset(of: landmarkIds)
      }.count
      if shared < policy.minimumLandmarksPerFloorPair {
        gaps.append(
          .missingLandmarks(
            lower: lower.label, upper: upper.label, have: shared,
            need: policy.minimumLandmarksPerFloorPair))
      }
    }
    return item(
      .minimumControls, gaps: gaps, passedDetail: "All minimum controls recorded", wording)
  }

  // MARK: 5 Device, mode, date, operator

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
