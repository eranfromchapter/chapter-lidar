#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import FieldRules
  import Foundation
  import Observation

  /// State of "Field controls" (design v2, artboard 2d-2): the guided list of every floor's
  /// minimum set and what lies between floors (`ControlsList`), and the entry sheet of the row
  /// the operator tapped (`entry`). Every saved measurement is passed to `persist`, which the app
  /// wires to `FieldControlsFile.write`; nothing is kept when that fails.
  @MainActor @Observable
  public final class FieldControlsModel {
    /// Every capture of the visit, exterior included, as the app gave them.
    public let captures: [FieldCaptureOption]
    /// The floors and areas that need controls (every capture except exterior), by capture time.
    public let floors: [FieldCaptureOption]
    public let policy: ChecklistPolicy
    /// The visit is sealed (and not in revision mode): rows open their sheet with every field
    /// disabled and no Save (phone-field addendum B4).
    public let isReadOnly: Bool
    /// The sealed revision, for the read-only footnote.
    public let sealedRevision: Int
    public private(set) var editor: FieldControlsEditor
    /// The open entry sheet; nil when none.
    public var entry: ControlEntryModel?
    /// The row to scroll into view (`focus(rowId:)`); the list clears it once it scrolled.
    public var scrollTarget: String?

    private let persist: @MainActor (FieldControls) throws -> Void
    private let now: @Sendable () -> UTCTimestamp

    public init(
      captures: [FieldCaptureOption],
      controls: FieldControls,
      policy: ChecklistPolicy = .shipping,
      isReadOnly: Bool = false,
      sealedRevision: Int = 1,
      persist: @escaping @MainActor (FieldControls) throws -> Void,
      now: @escaping @Sendable () -> UTCTimestamp = { UTCTimestamp.now() }
    ) {
      self.captures = captures
      let ordered = ControlsList.floors(captures.map(\.controlsFloor)).map(\.id)
      self.floors = ordered.compactMap { id in captures.first { $0.id == id } }
      self.editor = FieldControlsEditor(controls: controls)
      self.policy = policy
      self.isReadOnly = isReadOnly
      self.sealedRevision = sealedRevision
      self.persist = persist
      self.now = now
    }

    public var controls: FieldControls { editor.controls }

    // MARK: List

    public var sections: [ControlSection] {
      ControlsList.sections(
        floors: captures.map(\.controlsFloor), controls: editor.controls, policy: policy)
    }

    /// `4 of 9 required`, shown only under the manual policy.
    public var progress: ControlsProgress? {
      guard policy.manualControlsRequired else { return nil }
      return ControlsList.progress(
        floors: captures.map(\.controlsFloor), controls: editor.controls, policy: policy)
    }

    /// The line under the title.
    public var subtitle: String {
      policy.manualControlsRequired
        ? "Tape or laser only. Never copy numbers from the scan."
        : "Measured by the LiDAR scan. Tap a row to add an optional tape or laser check."
    }

    /// What the screen says instead of the list when there is nothing to measure.
    public var emptyMessage: String? { ControlsList.emptyMessage(captures.map(\.controlsFloor)) }

    /// The footnote after the last card.
    public var footnote: String {
      isReadOnly
        ? ReadOnlyText.sealed(revision: sealedRevision)
        : "Stored in mm, shown in both units. Tap a row to add or change it."
    }

    /// The row with this id (`floor-1.distanceA`), if the list has it.
    public func row(_ id: String) -> ControlRow? {
      sections.lazy.flatMap(\.rows).first { $0.id == id }
    }

    // MARK: Opening the entry sheet

    /// Before you leave "Add": scrolls the row into view and opens its sheet. The sheet is
    /// presented when the list appears if it is not on screen yet.
    public func focus(rowId: String) {
      scrollTarget = rowId
      if let row = row(rowId) { open(row) }
    }

    /// "Add" on Before you leave's "Minimum field controls": the row of its first gap.
    public func focusFirstGap(of item: ChecklistItem) {
      for gap in item.gaps {
        if let id = ControlsList.rowId(for: gap, floors: captures.map(\.controlsFloor)) {
          focus(rowId: id)
          return
        }
      }
    }

    /// A row was tapped: single-value rows (A, B, floor to floor) open prefilled when recorded;
    /// list rows (ceiling heights, openings, landmarks) open a new entry under the list of what
    /// is recorded.
    public func open(_ row: ControlRow) {
      let entry = ControlEntryModel(
        kind: row.kind, target: row.target, rowId: row.id, rooms: rooms(of: row.target),
        floors: floors, isReadOnly: isReadOnly,
        value: MeasurementEntryDraft(unit: defaultUnit(for: row.target), method: defaultMethod))
      entry.targetLabels = labels(of: row.target)
      switch row.kind {
      case .distanceA, .distanceB:
        if case .floor(let id) = row.target,
          let item = editor.controls.distances.first(where: {
            $0.capture.captureId == id && $0.axis == (row.kind == .distanceA ? .a : .b)
          })
        {
          entry.load(distance: item, defaultUnit: defaultUnit(for: row.target))
        }
      case .floorToFloor:
        if case .pair(let lower, let upper) = row.target,
          let item = editor.controls.floorToFloor.first(where: {
            Set([$0.lower.captureId, $0.upper.captureId]) == Set([lower, upper])
          })
        {
          entry.load(floorToFloor: item, defaultUnit: defaultUnit(for: row.target))
        } else {
          entry.location = "At the stair"
        }
      case .landmark:
        if case .pair(let lower, let upper) = row.target {
          entry.landmarkFloors = [lower, upper]
        }
      case .ceilingHeight, .opening:
        break
      }
      entry.recorded = recorded(for: row)
      self.entry = entry
    }

    /// Loads a recorded entry of a list row into the open sheet (§5.6).
    public func edit(recordedId id: String) {
      guard let entry else { return }
      let unit = defaultUnit(for: entry.target)
      if let item = editor.controls.ceilingHeights.first(where: { $0.id == id }) {
        entry.load(ceiling: item, defaultUnit: unit)
      } else if let item = editor.controls.openings.first(where: { $0.id == id }) {
        entry.load(opening: item, defaultUnit: unit)
      } else if let item = editor.controls.landmarks.first(where: { $0.id == id }) {
        entry.load(landmark: item)
      }
    }

    /// Cancel or swipe down: nothing is kept.
    public func cancelEntry() {
      entry = nil
    }

    // MARK: Saving

    /// Saves the open entry into a copy of the controls (removing the entry it replaces when
    /// its id changes), passes the whole document to `persist`, then keeps it and closes the
    /// sheet. On any failure nothing is kept, the sheet stays and its footnote says why.
    public func saveEntry() {
      guard let entry, !isReadOnly, entry.canSave else { return }
      var next = editor
      do {
        let recordedAt = now()
        let id: String
        switch (entry.kind, entry.target) {
        case (.distanceA, .floor(let floor)), (.distanceB, .floor(let floor)):
          id = try next.setDistance(
            capture: try ref(floor), axis: entry.kind == .distanceA ? .a : .b, from: entry.from,
            to: entry.to, measurement: entry.value.measurement(recordedAt: recordedAt))
        case (.ceilingHeight, .floor(let floor)):
          id = try next.setCeilingHeight(
            capture: try ref(floor), room: entry.room, location: entry.location,
            measurement: entry.value.measurement(recordedAt: recordedAt))
        case (.opening, .floor(let floor)):
          var height: FieldControls.Measurement?
          if !entry.height.isEmpty { height = try entry.height.measurement(recordedAt: recordedAt) }
          id = try next.setOpening(
            capture: try ref(floor), room: entry.room, label: entry.label,
            width: entry.value.measurement(recordedAt: recordedAt), height: height)
        case (.floorToFloor, .pair(let lower, let upper)):
          id = try next.setFloorToFloor(
            lower: try ref(lower), upper: try ref(upper), location: entry.location,
            measurement: entry.value.measurement(recordedAt: recordedAt))
        case (.landmark, _):
          let kept = entry.editingId.flatMap { old in
            editor.controls.landmarks.first { $0.id == old }
          }
          id = try next.setLandmark(
            label: entry.label, description: kept?.description,
            captures: floors.filter { entry.landmarkFloors.contains($0.id) }.map(\.ref),
            photoPaths: kept?.photoPaths)
        default:
          return
        }
        if let old = entry.editingId, old != id { next.remove(id: old) }
        try persist(next.controls)
        editor = next
        self.entry = nil
      } catch let error as LengthParseError {
        entry.errorMessage = error.message
      } catch let error as FieldControlsEditError {
        entry.errorMessage = error.description
      } catch {
        entry.errorMessage = "The measurement could not be saved: \(userMessage(for: error))"
      }
    }

    // MARK: Helpers

    private struct UnknownCapture: Error, CustomStringConvertible {
      var description: String { "The floor is no longer part of this visit." }
    }

    private func ref(_ id: LowercaseUUID) throws -> FieldControls.CaptureRef {
      guard let capture = captures.first(where: { $0.id == id }) else { throw UnknownCapture() }
      return capture.ref
    }

    private func rooms(of target: ControlTarget) -> [String] {
      guard case .floor(let id) = target else { return [] }
      return PhotoCoverage.rooms(captures.first { $0.id == id }?.rooms ?? [])
    }

    private func labels(of target: ControlTarget) -> [String] {
      switch target {
      case .floor(let id):
        return captures.first { $0.id == id }.map { [$0.label] } ?? []
      case .pair(let lower, let upper):
        return [lower, upper].compactMap { id in captures.first { $0.id == id }?.label }
      }
    }

    /// Every measurement of the visit, newest last.
    private var measurements: [FieldControls.Measurement] {
      let controls = editor.controls
      var all = controls.distances.map(\.measurement) + controls.ceilingHeights.map(\.measurement)
      all += controls.openings.flatMap { [$0.width, $0.height].compactMap { $0 } }
      all += controls.floorToFloor.map(\.measurement)
      return all.sorted { $0.recordedAt < $1.recordedAt }
    }

    /// The unit last used in this visit; else feet and inches for an imperial capture,
    /// millimetres for a metric one.
    private func defaultUnit(for target: ControlTarget) -> EnteredUnit {
      if let last = measurements.last(where: { UnitChoice.offered.contains($0.enteredUnit) }) {
        return last.enteredUnit
      }
      let id: LowercaseUUID
      switch target {
      case .floor(let floor): id = floor
      case .pair(let lower, _): id = lower
      }
      return UnitChoice.defaultUnit(for: captures.first { $0.id == id }?.displayUnits ?? .imperial)
    }

    /// The instrument last used in this visit, else tape.
    private var defaultMethod: MeasurementMethod { measurements.last?.method ?? .tape }

    /// The `RECORDED …` list of a list row (§5.6).
    private func recorded(for row: ControlRow) -> [RecordedControl] {
      let controls = editor.controls
      switch (row.kind, row.target) {
      case (.ceilingHeight, .floor(let id)):
        return controls.ceilingHeights.filter { $0.capture.captureId == id }.map {
          RecordedControl(
            id: $0.id, title: $0.room, subtitle: $0.location,
            valuePrimary: LengthFormatter.millimetres($0.measurement.valueMm),
            valueSecondary: LengthFormatter.feetInches($0.measurement.valueMm))
        }
      case (.opening, .floor(let id)):
        return controls.openings.filter { $0.capture.captureId == id }.map { opening in
          let width = LengthFormatter.millimetres(opening.width.valueMm)
          let size = opening.height.map {
            "\(width) \u{00D7} \(LengthFormatter.millimetres($0.valueMm))"
          }
          return RecordedControl(
            id: opening.id, title: "\(opening.room) \u{00B7} \(opening.label)",
            subtitle: size ?? width, valuePrimary: nil, valueSecondary: nil)
        }
      case (.landmark, .pair(let lower, let upper)):
        let pair: Set<LowercaseUUID> = [lower, upper]
        return controls.landmarks.filter { pair.isSubset(of: Set($0.captures.map(\.captureId))) }
          .map { landmark in
            let names = landmark.captures.compactMap { ref in
              captures.first { $0.id == ref.captureId }?.label
            }
            return RecordedControl(
              id: landmark.id, title: landmark.label, subtitle: names.joined(separator: ", "),
              valuePrimary: nil, valueSecondary: nil)
          }
      default:
        return []
      }
    }
  }

  /// One recorded entry in the `RECORDED …` list of the entry sheet.
  public struct RecordedControl: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var valuePrimary: String?
    public var valueSecondary: String?
  }

  /// The words and value of the open entry sheet (phone-field §5, artboard 2d-3).
  @MainActor @Observable
  public final class ControlEntryModel: Identifiable {
    public enum Field: Hashable, Sendable {
      case from
      case to
      case room
      case location
      case label
      case firstValue
    }

    public let id = UUID()
    public let kind: ControlKind
    public let target: ControlTarget
    /// The list row that opened the sheet.
    public let rowId: String
    /// The floor's rooms, offered as chips (ceiling height, opening); empty: a text field.
    public let rooms: [String]
    /// Every floor of the visit, offered as "Visible from" chips (landmark).
    public let floors: [FieldCaptureOption]
    public let isReadOnly: Bool
    /// The floor (or the two floors) of the row: `Floor 1`, or `Floor 1`, `Floor 2`.
    public var targetLabels: [String] = []
    /// The control being edited; nil for a new entry.
    public private(set) var editingId: String?
    /// What the sheet's title adds when a list entry is edited: `Kitchen`, `Entry door`.
    public private(set) var editingName: String?

    public var from = ""
    public var to = ""
    public var room = ""
    public var location = ""
    public var label = ""
    public var landmarkFloors: Set<LowercaseUUID> = []
    public var value: MeasurementEntryDraft
    /// An opening's height (value fields only, in the width's unit).
    public var height: MeasurementEntryDraft
    /// Why the last Save failed.
    public var errorMessage: String?
    /// The `RECORDED …` list (ceiling heights, openings, landmarks).
    public internal(set) var recorded: [RecordedControl] = []

    init(
      kind: ControlKind, target: ControlTarget, rowId: String, rooms: [String],
      floors: [FieldCaptureOption], isReadOnly: Bool, value: MeasurementEntryDraft
    ) {
      self.kind = kind
      self.target = target
      self.rowId = rowId
      self.rooms = rooms
      self.floors = floors
      self.isReadOnly = isReadOnly
      self.value = value
      self.height = MeasurementEntryDraft(unit: value.unit, method: value.method)
    }

    /// `Floor to floor`, `Ceiling height · Kitchen` while a recorded one is edited.
    public var title: String {
      guard let editingName else { return kind.entryTitle }
      return "\(kind.entryTitle) \u{00B7} \(editingName)"
    }

    /// `Recorded on Floor 1`, `Recorded between Floor 1 and Floor 2`; nil when nothing is.
    public var recordedCaption: String? {
      guard !recorded.isEmpty else { return nil }
      if targetLabels.count == 2 {
        return "Recorded between \(targetLabels[0]) and \(targetLabels[1])"
      }
      return "Recorded on \(targetLabels.first ?? "")"
    }

    /// The caption of the value card: `Width` for an opening, else `Measurement`.
    public var measurementCaption: String { kind == .opening ? "Width" : "Measurement" }

    public var hasMeasurement: Bool { kind != .landmark }

    private static func filled(_ text: String) -> Bool {
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The words the kind needs are there.
    public var wordsComplete: Bool {
      switch kind {
      case .distanceA, .distanceB: return Self.filled(from) && Self.filled(to)
      case .ceilingHeight: return Self.filled(room)
      case .opening: return Self.filled(room) && Self.filled(label)
      case .floorToFloor: return Self.filled(location)
      case .landmark: return Self.filled(label) && landmarkFloors.count >= 2
      }
    }

    /// Save is enabled: the words are there and the value parses (an opening's height too,
    /// when typed). Never while read-only.
    public var canSave: Bool {
      guard !isReadOnly, wordsComplete else { return false }
      guard hasMeasurement else { return true }
      guard case .success = value.result else { return false }
      if kind == .opening, !height.isEmpty, case .failure = height.result { return false }
      return true
    }

    /// The footnote under the value card (§5.3) and whether it is an error.
    public var footnote: (text: String, isError: Bool) {
      if let errorMessage { return (errorMessage, true) }
      guard hasMeasurement else {
        return ("Pick something you can see from both floors, for example the stair newel post.", false)
      }
      let prefix = kind == .distanceB ? "At a right angle to A. " : ""
      if let error = value.errorMessage ?? (kind == .opening ? height.errorMessage : nil) {
        return (prefix + error, true)
      }
      let rest = "Shown in both units everywhere. Tape or laser only."
      if let stored = value.storedText { return ("\(prefix)Stored as \(stored). \(rest)", false) }
      return ("\(prefix)Stored in mm. \(rest)", false)
    }

    /// The unit segment changed: the value fields are cleared (nothing is converted).
    public func chooseUnit(_ unit: EnteredUnit) {
      guard unit != value.unit else { return }
      value = value.cleared(unit: unit)
      height = height.cleared(unit: unit)
    }

    public func chooseMethod(_ method: MeasurementMethod) {
      value.method = method
      height.method = method
    }

    public func toggleLandmarkFloor(_ id: LowercaseUUID) {
      if landmarkFloors.contains(id) {
        landmarkFloors.remove(id)
      } else {
        landmarkFloors.insert(id)
      }
    }

    /// The field focused when the sheet opens: the value when the words are prefilled or
    /// optional (floor to floor, a chosen room, an edit), else the first empty word field; nil
    /// when the next step is a chip.
    public var initialFocus: Field? {
      guard !isReadOnly else { return nil }
      if editingId != nil { return hasMeasurement ? .firstValue : nil }
      switch kind {
      case .distanceA, .distanceB:
        if !Self.filled(from) { return .from }
        return Self.filled(to) ? .firstValue : .to
      case .ceilingHeight:
        if Self.filled(room) { return .firstValue }
        return rooms.isEmpty ? .room : nil
      case .opening:
        if !Self.filled(room) { return rooms.isEmpty ? .room : nil }
        return Self.filled(label) ? .firstValue : .label
      case .floorToFloor:
        return .firstValue
      case .landmark:
        return Self.filled(label) ? nil : .label
      }
    }

    /// Where Return in a word field goes: From → To, a typed room → where in the room (ceiling)
    /// or which opening, else the first value field; nil (the keyboard goes) for a landmark,
    /// whose next step is a chip.
    public func focus(after field: Field) -> Field? {
      switch (kind, field) {
      case (.distanceA, .from), (.distanceB, .from): return .to
      case (.ceilingHeight, .room): return .location
      case (.opening, .room): return .label
      default: return hasMeasurement ? .firstValue : nil
      }
    }

    /// Words as one line: a line break (Return, or pasted) becomes one space between the words
    /// around it and nothing at either end.
    public static func oneLine(_ text: String) -> String {
      guard text.contains(where: \.isNewline) else { return text }
      return text.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    // MARK: Loading recorded controls

    func load(distance: FieldControls.Distance, defaultUnit: EnteredUnit) {
      editingId = distance.id
      from = distance.from
      to = distance.to
      value = .editing(distance.measurement, defaultUnit: defaultUnit)
    }

    func load(floorToFloor: FieldControls.FloorToFloor, defaultUnit: EnteredUnit) {
      editingId = floorToFloor.id
      location = floorToFloor.location
      value = .editing(floorToFloor.measurement, defaultUnit: defaultUnit)
    }

    func load(ceiling: FieldControls.CeilingHeight, defaultUnit: EnteredUnit) {
      editingId = ceiling.id
      editingName = ceiling.room
      room = ceiling.room
      location = ceiling.location ?? ""
      value = .editing(ceiling.measurement, defaultUnit: defaultUnit)
      errorMessage = nil
    }

    func load(opening: FieldControls.Opening, defaultUnit: EnteredUnit) {
      editingId = opening.id
      editingName = opening.label
      room = opening.room
      label = opening.label
      value = .editing(opening.width, defaultUnit: defaultUnit)
      height =
        opening.height.map { .editing($0, defaultUnit: value.unit) }
        ?? MeasurementEntryDraft(unit: value.unit, method: value.method)
      if height.unit != value.unit { height = height.cleared(unit: value.unit) }
      errorMessage = nil
    }

    func load(landmark: FieldControls.Landmark) {
      editingId = landmark.id
      editingName = landmark.label
      label = landmark.label
      landmarkFloors = Set(landmark.captures.map(\.captureId))
      errorMessage = nil
    }
  }
#endif
