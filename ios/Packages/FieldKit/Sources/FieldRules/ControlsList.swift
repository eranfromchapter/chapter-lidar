import CaptureContract
import Foundation

// The Field controls list (phone-field §4, artboard 2d-2): one section per floor or area with its
// minimum set, and a "between" section after each floor that has a next floor. Every row, value,
// status and the "4 of 9 required" counter is decided here so it is unit-tested; FieldKitUI only
// renders. Before you leave's "Minimum field controls" uses the same counting
// (`ControlsList.gaps`), so the two screens always agree.

/// One floor or area of the visit as the controls list needs it.
public struct ControlsFloor: Hashable, Sendable, Identifiable {
  public var ref: FieldControls.CaptureRef
  /// Label shown to people, for example "Floor 1".
  public var label: String
  public var mode: CaptureMode
  public var capturedAt: UTCTimestamp
  /// Room labels from the capture model (renamed labels), in model order.
  public var rooms: [String]
  /// Measurements read from the capture's LiDAR model; nil before the model exists.
  public var scan: ScanMeasurements?

  public var id: LowercaseUUID { ref.captureId }

  public init(
    ref: FieldControls.CaptureRef, label: String, mode: CaptureMode, capturedAt: UTCTimestamp,
    rooms: [String] = [], scan: ScanMeasurements? = nil
  ) {
    self.ref = ref
    self.label = label
    self.mode = mode
    self.capturedAt = capturedAt
    self.rooms = rooms
    self.scan = scan
  }

  /// A capture of the record (rooms and scan from its model, when the caller has them).
  public init(
    capture: CaptureRecord.Capture, rooms: [String] = [], scan: ScanMeasurements? = nil
  ) {
    self.init(
      ref: FieldControls.CaptureRef(captureId: capture.captureId, areaKey: capture.areaKey),
      label: capture.label.trimmingCharacters(in: .whitespaces), mode: capture.mode,
      capturedAt: capture.capturedAt, rooms: rooms, scan: scan)
  }
}

/// What a row is about: one floor, or a pair of consecutive floors.
public enum ControlTarget: Hashable, Sendable {
  case floor(LowercaseUUID)
  case pair(lower: LowercaseUUID, upper: LowercaseUUID)
}

/// The glyph of a row: ● recorded (or from the scan), ■ missing (manual policy only),
/// ○ optional.
public enum ControlStatus: String, CaseIterable, Sendable {
  case done
  case missing
  case optional

  /// What VoiceOver reads for the glyph.
  public var spokenWord: String {
    switch self {
    case .done: return "Done"
    case .missing: return "Missing"
    case .optional: return "Optional"
    }
  }
}

/// Colour of a row's first value: ink (`7,520 mm`, `2 recorded`), blocked (`Missing`, `1 of 2`),
/// muted (`None`, `Optional`).
public enum ControlValueTone: String, CaseIterable, Sendable {
  case ink
  case blocked
  case muted
}

/// One row of the list.
public struct ControlRow: Hashable, Sendable, Identifiable {
  /// `floor-1.distanceA`, `floor-1~floor-2.floorToFloor`: the end of the accessibility
  /// identifier and the id `FieldControlsModel.focus(rowId:)` takes.
  public var id: String
  public var kind: ControlKind
  public var target: ControlTarget
  public var title: String
  public var subtitle: String?
  /// `7,520 mm`, `2,690–2,740 mm`, `2 recorded`, `Missing`, `1 of 2`, `Optional`, `None`.
  public var valuePrimary: String?
  public var valueTone: ControlValueTone
  /// Feet and inches under the millimetres (`24' 8.1"`, SF Mono on screen).
  public var valueSecondary: String?
  /// The scan's value under a tape or laser value (standard policy): `Scan 7,512 mm`.
  public var extraLine: String?
  public var status: ControlStatus
  /// One line, no subtitle (min height 42 instead of 50).
  public var isCompact: Bool
  /// The values as VoiceOver reads them: `7,520 millimetres, 24 feet 8.1 inches`.
  public var spokenValue: String

  /// `controls.row.floor-1.distanceA`.
  public var accessibilityIdentifier: String { "controls.row.\(id)" }

  /// The row as one accessibility element: `Long distance A, Kitchen east wall to living west
  /// wall, 7,520 millimetres, 24 feet 8.1 inches, Done`; `Long distance A, Missing` when the
  /// value already is the status word.
  public var accessibilityLabel: String {
    let status = status.spokenWord == spokenValue ? nil : status.spokenWord
    return [title, subtitle, spokenValue, extraLine, status]
      .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
  }
}

/// A section of the list: a floor's minimum set, or what lies between two floors.
public struct ControlSection: Hashable, Sendable, Identifiable {
  /// The floor's area key, or `{lower}~{upper}`.
  public var id: String
  /// `Floor 1 · minimum set`, `Between Floor 1 and Floor 2` (shown uppercased).
  public var header: String
  public var target: ControlTarget
  public var rows: [ControlRow]
}

/// The manual policy's counter: `4 of 9 required`.
public struct ControlsProgress: Hashable, Sendable {
  public var done: Int
  public var total: Int

  public var text: String { "\(done) of \(total) required" }
  public var isComplete: Bool { done >= total }
}

/// The word of a floor's controls on the capture overview's floor row: `controls complete`,
/// `controls missing`, `controls incomplete` (manual policy), `controls from the scan`,
/// `controls optional` (standard policy). phone-capture addendum A6.
public enum FloorControlsState: String, CaseIterable, Sendable {
  case complete
  case incomplete
  case missing
  case fromScan = "from the scan"
  case optional

  public var text: String { "controls \(rawValue)" }
}

public enum ControlsList {
  /// The floors that need controls: every capture except exterior, by `capturedAt`, then in the
  /// order given.
  public static func floors(_ captures: [ControlsFloor]) -> [ControlsFloor] {
    captures.enumerated()
      .filter { $0.element.mode != .exterior }
      .sorted { ($0.element.capturedAt, $0.offset) < ($1.element.capturedAt, $1.offset) }
      .map(\.element)
  }

  /// What the list says instead of sections: no capture at all, or only exterior captures; nil
  /// when there are floors.
  public static func emptyMessage(_ captures: [ControlsFloor]) -> String? {
    if captures.isEmpty { return "No floor or area has been scanned yet." }
    if floors(captures).isEmpty { return "Exterior captures need no field controls." }
    return nil
  }

  /// Floor 1 · between 1 and 2 · Floor 2 · between 2 and 3 · Floor 3 …
  public static func sections(
    floors captures: [ControlsFloor], controls: FieldControls, policy: ChecklistPolicy
  ) -> [ControlSection] {
    let floors = floors(captures)
    let index = Index(controls)
    var sections: [ControlSection] = []
    for (offset, floor) in floors.enumerated() {
      sections.append(
        ControlSection(
          id: floor.ref.areaKey, header: "\(floor.label) \u{00B7} minimum set",
          target: .floor(floor.id),
          rows: floorRows(floor, index, required: policy.manualControlsRequired)))
      guard offset + 1 < floors.count else { continue }
      let upper = floors[offset + 1]
      sections.append(
        ControlSection(
          id: pairKey(floor, upper), header: "Between \(floor.label) and \(upper.label)",
          target: .pair(lower: floor.id, upper: upper.id),
          rows: pairRows(floor, upper, index, policy)))
    }
    return sections
  }

  /// `total = 3 × floors + Σ pairs (1 + minimum landmarks)`; `done` counts A, B and one ceiling
  /// height per floor, one floor-to-floor level and up to the minimum of shared landmarks per
  /// pair. Openings never count. (Artboard: Floor 1 complete + 1 landmark = 4 of 9.)
  public static func progress(
    floors captures: [ControlsFloor], controls: FieldControls, policy: ChecklistPolicy
  ) -> ControlsProgress {
    let floors = floors(captures)
    let index = Index(controls)
    let minimum = policy.minimumLandmarksPerFloorPair
    var done = 0
    var total = 0
    for floor in floors {
      total += 3
      done += (index.distance(floor.id, .a) == nil ? 0 : 1)
      done += (index.distance(floor.id, .b) == nil ? 0 : 1)
      done += (index.ceilings(floor.id).isEmpty ? 0 : 1)
    }
    for (lower, upper) in zip(floors, floors.dropFirst()) {
      total += 1 + minimum
      done += (index.floorToFloor(lower.id, upper.id).isEmpty ? 0 : 1)
      done += min(index.landmarkCount(lower.id, upper.id), minimum)
    }
    return ControlsProgress(done: done, total: total)
  }

  /// What is missing for the manual policy, in list order (Floor 1, between 1 and 2, Floor 2, …).
  /// The checklist's "Minimum field controls" item is built from these.
  public static func gaps(
    floors captures: [ControlsFloor], controls: FieldControls, policy: ChecklistPolicy
  ) -> [ChecklistGap] {
    let floors = floors(captures)
    let index = Index(controls)
    var gaps: [ChecklistGap] = []
    for (offset, floor) in floors.enumerated() {
      for axis in [DistanceAxis.a, .b] where index.distance(floor.id, axis) == nil {
        gaps.append(.missingDistance(capture: floor.label, axis: axis))
      }
      if index.ceilings(floor.id).isEmpty {
        gaps.append(.missingCeilingHeight(capture: floor.label))
      }
      guard offset + 1 < floors.count else { continue }
      let upper = floors[offset + 1]
      if index.floorToFloor(floor.id, upper.id).isEmpty {
        gaps.append(.missingFloorToFloor(lower: floor.label, upper: upper.label))
      }
      let shared = index.landmarkCount(floor.id, upper.id)
      if shared < policy.minimumLandmarksPerFloorPair {
        gaps.append(
          .missingLandmarks(
            lower: floor.label, upper: upper.label, have: shared,
            need: policy.minimumLandmarksPerFloorPair))
      }
    }
    return gaps
  }

  /// The row a gap of "Minimum field controls" is about (Before you leave "Add" opens it).
  /// Gap labels are resolved to area keys through `captures` (the first floor with that label).
  public static func rowId(for gap: ChecklistGap, floors captures: [ControlsFloor]) -> String? {
    let floors = floors(captures)
    func key(_ label: String) -> String? {
      floors.first { $0.label == label.trimmingCharacters(in: .whitespaces) }?.ref.areaKey
    }
    switch gap {
    case .missingDistance(let capture, let axis):
      return key(capture).map {
        "\($0).\(axis == .a ? ControlKind.distanceA.rowKey : ControlKind.distanceB.rowKey)"
      }
    case .missingCeilingHeight(let capture):
      return key(capture).map { "\($0).\(ControlKind.ceilingHeight.rowKey)" }
    case .missingFloorToFloor(let lower, let upper):
      guard let lower = key(lower), let upper = key(upper) else { return nil }
      return "\(lower)~\(upper).\(ControlKind.floorToFloor.rowKey)"
    case .missingLandmarks(let lower, let upper, _, _):
      guard let lower = key(lower), let upper = key(upper) else { return nil }
      return "\(lower)~\(upper).\(ControlKind.landmark.rowKey)"
    default:
      return nil
    }
  }

  /// The overview word of one floor's controls, from its section's A, B and ceiling rows.
  public static func floorState(_ section: ControlSection, policy: ChecklistPolicy)
    -> FloorControlsState
  {
    let required = section.rows.filter {
      [.distanceA, .distanceB, .ceilingHeight].contains($0.kind)
    }
    if policy.manualControlsRequired {
      if required.allSatisfy({ $0.status == .missing }) { return .missing }
      return section.rows.contains { $0.status == .missing } ? .incomplete : .complete
    }
    return required.allSatisfy { $0.status == .done } ? .fromScan : .optional
  }

  // MARK: Rows

  private static let fromScan = "From the LiDAR scan"

  private static func floorRows(_ floor: ControlsFloor, _ index: Index, required: Bool)
    -> [ControlRow]
  {
    let target = ControlTarget.floor(floor.id)
    let scan = floor.scan
    var rows: [ControlRow] = []

    for (kind, axis) in [(ControlKind.distanceA, DistanceAxis.a), (.distanceB, .b)] {
      let id = "\(floor.ref.areaKey).\(kind.rowKey)"
      let scanned = axis == .a ? scan?.distanceAMm : scan?.distanceBMm
      if let item = index.distance(floor.id, axis) {
        rows.append(
          valueRow(
            id: id, kind: kind, target: target, title: kind.rowTitle,
            subtitle: "\(item.from) to \(item.to)", valueMm: item.measurement.valueMm,
            extraLine: required ? nil : scanned.map { "Scan \(LengthFormatter.millimetres($0))" }))
      } else if !required, let scanned {
        rows.append(
          valueRow(
            id: id, kind: kind, target: target, title: kind.rowTitle,
            subtitle: "\(fromScan) \u{00B7} tap to check with tape", valueMm: scanned))
      } else {
        rows.append(
          emptyRow(
            id: id, kind: kind, target: target, title: kind.entryTitle, subtitle: nil,
            required: required))
      }
    }

    let ceilingId = "\(floor.ref.areaKey).\(ControlKind.ceilingHeight.rowKey)"
    let ceilings = index.ceilings(floor.id)
    let scannedHeights = scan?.ceilingHeights.map(\.heightMm) ?? []
    if !ceilings.isEmpty {
      let rooms = Set(ceilings.map { FieldControlsEditor.labelKey($0.room) }).count
      let roomsText = "\(rooms) \(rooms == 1 ? "room" : "rooms")"
      rows.append(
        rangeRow(
          id: ceilingId, target: target,
          subtitle: required ? "\(roomsText) \u{00B7} at least 1 required" : roomsText,
          values: ceilings.map(\.measurement.valueMm),
          extraLine: required || scannedHeights.isEmpty
            ? nil : "Scan \(range(scannedHeights))"))
    } else if !required, !scannedHeights.isEmpty {
      let rooms = scannedHeights.count
      rows.append(
        rangeRow(
          id: ceilingId, target: target,
          subtitle: "\(fromScan) \u{00B7} \(rooms) \(rooms == 1 ? "room" : "rooms")",
          values: scannedHeights, extraLine: nil))
    } else {
      rows.append(
        emptyRow(
          id: ceilingId, kind: .ceilingHeight, target: target,
          title: ControlKind.ceilingHeight.entryTitle, subtitle: nil, required: required))
    }

    let openingsId = "\(floor.ref.areaKey).\(ControlKind.opening.rowKey)"
    let recorded = index.openings(floor.id).count
    let scanned = scan.map { $0.doors + $0.windows + $0.openings } ?? 0
    if recorded > 0 {
      rows.append(
        countRow(
          id: openingsId, kind: .opening, target: target, subtitle: nil,
          value: "\(recorded) recorded", compact: true))
    } else if !required, scanned > 0 {
      rows.append(
        countRow(
          id: openingsId, kind: .opening, target: target, subtitle: nil,
          value: "\(scanned) from the scan", compact: true))
    } else {
      rows.append(
        ControlRow(
          id: openingsId, kind: .opening, target: target, title: ControlKind.opening.rowTitle,
          subtitle: nil, valuePrimary: "None", valueTone: .muted, valueSecondary: nil,
          extraLine: nil, status: .optional, isCompact: true, spokenValue: "None"))
    }
    return rows
  }

  private static func pairRows(
    _ lower: ControlsFloor, _ upper: ControlsFloor, _ index: Index, _ policy: ChecklistPolicy
  ) -> [ControlRow] {
    let required = policy.manualControlsRequired
    let target = ControlTarget.pair(lower: lower.id, upper: upper.id)
    let key = pairKey(lower, upper)
    var rows: [ControlRow] = []

    let levelId = "\(key).\(ControlKind.floorToFloor.rowKey)"
    if let level = index.floorToFloor(lower.id, upper.id).first {
      rows.append(
        valueRow(
          id: levelId, kind: .floorToFloor, target: target, title: ControlKind.floorToFloor.rowTitle,
          subtitle: level.location, valueMm: level.measurement.valueMm))
    } else {
      rows.append(
        emptyRow(
          id: levelId, kind: .floorToFloor, target: target,
          title: ControlKind.floorToFloor.rowTitle,
          subtitle: "Level difference, measured at the stair", required: required))
    }

    let landmarksId = "\(key).\(ControlKind.landmark.rowKey)"
    let minimum = policy.minimumLandmarksPerFloorPair
    let shared = index.landmarkCount(lower.id, upper.id)
    let subtitle =
      required ? "Visible from both floors \u{00B7} \(minimum) required" : "Visible from both floors"
    if shared >= minimum || (!required && shared > 0) {
      rows.append(
        countRow(
          id: landmarksId, kind: .landmark, target: target, subtitle: subtitle,
          value: "\(shared) recorded", compact: false))
    } else if required, shared > 0 {
      rows.append(
        ControlRow(
          id: landmarksId, kind: .landmark, target: target, title: ControlKind.landmark.rowTitle,
          subtitle: subtitle, valuePrimary: "\(shared) of \(minimum)", valueTone: .blocked,
          valueSecondary: nil, extraLine: nil, status: .missing, isCompact: false,
          spokenValue: "\(shared) of \(minimum)"))
    } else {
      rows.append(
        emptyRow(
          id: landmarksId, kind: .landmark, target: target, title: ControlKind.landmark.rowTitle,
          subtitle: subtitle, required: required))
    }
    return rows
  }

  /// A recorded single value: millimetres over feet and inches.
  private static func valueRow(
    id: String, kind: ControlKind, target: ControlTarget, title: String, subtitle: String?,
    valueMm: Double, extraLine: String? = nil
  ) -> ControlRow {
    ControlRow(
      id: id, kind: kind, target: target, title: title, subtitle: subtitle,
      valuePrimary: LengthFormatter.millimetres(valueMm), valueTone: .ink,
      valueSecondary: LengthFormatter.feetInches(valueMm), extraLine: extraLine, status: .done,
      isCompact: false,
      spokenValue:
        "\(LengthFormatter.spokenMillimetres(valueMm)), \(LengthFormatter.spokenFeetInches(valueMm))"
    )
  }

  /// Ceiling heights: one line `2,690–2,740 mm` when they differ by a whole millimetre, else the
  /// one height in both units.
  private static func rangeRow(
    id: String, target: ControlTarget, subtitle: String, values: [Double], extraLine: String?
  ) -> ControlRow {
    let low = values.min() ?? 0
    let high = values.max() ?? 0
    let text = LengthFormatter.millimetreRange(low, high)
    guard text.contains("\u{2013}") else {
      return valueRow(
        id: id, kind: .ceilingHeight, target: target, title: ControlKind.ceilingHeight.rowTitle,
        subtitle: subtitle, valueMm: low, extraLine: extraLine)
    }
    let spoken = text.replacingOccurrences(of: "\u{2013}", with: " to ")
      .replacingOccurrences(of: " mm", with: " millimetres")
    return ControlRow(
      id: id, kind: .ceilingHeight, target: target, title: ControlKind.ceilingHeight.rowTitle,
      subtitle: subtitle, valuePrimary: text, valueTone: .ink, valueSecondary: nil,
      extraLine: extraLine, status: .done, isCompact: false, spokenValue: spoken)
  }

  private static func countRow(
    id: String, kind: ControlKind, target: ControlTarget, subtitle: String?, value: String,
    compact: Bool
  ) -> ControlRow {
    ControlRow(
      id: id, kind: kind, target: target, title: kind.rowTitle, subtitle: subtitle,
      valuePrimary: value, valueTone: .ink, valueSecondary: nil, extraLine: nil, status: .done,
      isCompact: compact, spokenValue: value)
  }

  /// Nothing recorded: ■ `Missing` (manual policy) or ○ `Optional` (standard policy). Rows
  /// without a subtitle are compact.
  private static func emptyRow(
    id: String, kind: ControlKind, target: ControlTarget, title: String, subtitle: String?,
    required: Bool
  ) -> ControlRow {
    let value = required ? "Missing" : "Optional"
    return ControlRow(
      id: id, kind: kind, target: target, title: title, subtitle: subtitle, valuePrimary: value,
      valueTone: required ? .blocked : .muted, valueSecondary: nil, extraLine: nil,
      status: required ? .missing : .optional, isCompact: subtitle == nil, spokenValue: value)
  }

  private static func range(_ values: [Double]) -> String {
    LengthFormatter.millimetreRange(values.min() ?? 0, values.max() ?? 0)
  }

  static func pairKey(_ lower: ControlsFloor, _ upper: ControlsFloor) -> String {
    "\(lower.ref.areaKey)~\(upper.ref.areaKey)"
  }

  // MARK: Lookups

  /// The controls of the visit by floor and pair, in document order.
  struct Index {
    let controls: FieldControls

    init(_ controls: FieldControls) {
      self.controls = controls
    }

    func distance(_ floor: LowercaseUUID, _ axis: DistanceAxis) -> FieldControls.Distance? {
      controls.distances.first { $0.capture.captureId == floor && $0.axis == axis }
    }

    func ceilings(_ floor: LowercaseUUID) -> [FieldControls.CeilingHeight] {
      controls.ceilingHeights.filter { $0.capture.captureId == floor }
    }

    func openings(_ floor: LowercaseUUID) -> [FieldControls.Opening] {
      controls.openings.filter { $0.capture.captureId == floor }
    }

    func floorToFloor(_ lower: LowercaseUUID, _ upper: LowercaseUUID)
      -> [FieldControls.FloorToFloor]
    {
      let pair: Set<LowercaseUUID> = [lower, upper]
      return controls.floorToFloor.filter { Set([$0.lower.captureId, $0.upper.captureId]) == pair }
    }

    /// Landmarks whose captures include both floors.
    func landmarks(_ lower: LowercaseUUID, _ upper: LowercaseUUID) -> [FieldControls.Landmark] {
      let pair: Set<LowercaseUUID> = [lower, upper]
      return controls.landmarks.filter { pair.isSubset(of: Set($0.captures.map(\.captureId))) }
    }

    func landmarkCount(_ lower: LowercaseUUID, _ upper: LowercaseUUID) -> Int {
      landmarks(lower, upper).count
    }
  }
}
