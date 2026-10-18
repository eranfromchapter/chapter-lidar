#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import FieldRules
  import Foundation
  import Observation

  /// One row of the Field controls list.
  public struct ControlRowContent: Identifiable, Hashable, Sendable {
    public var kind: ControlKind
    public var title: String
    public var subtitle: String
    /// Right-hand lines, for example `["7 518 mm", "24′ 8″"]`.
    public var valueLines: [String]
    /// Shown as "■ Missing" in the blocked colour.
    public var isMissing: Bool

    public var id: ControlKind { kind }
  }

  /// State of the "Field controls" screen. Edits the visit's `FieldControls`; every saved
  /// measurement is passed to `persist`, which the app wires to `FieldControlsFile.write`.
  @MainActor @Observable
  public final class FieldControlsModel {
    /// Floors and areas that need controls (every capture except exterior), in capture order.
    public let floors: [FieldCaptureOption]
    public private(set) var editor: FieldControlsEditor
    public var selectedFloorIndex = 0
    public private(set) var activeKind: ControlKind?

    public var entry = MeasurementEntryDraft()
    public var heightText = ""
    public var fromText = ""
    public var toText = ""
    public var roomText = ""
    public var labelText = ""
    public var locationText = ""
    public var upperFloorIndex = 0
    public var landmarkFloorIDs: Set<LowercaseUUID> = []
    public private(set) var errorMessage: String?

    private let policy: ChecklistPolicy
    private let persist: @MainActor (FieldControls) throws -> Void
    private let now: @Sendable () -> UTCTimestamp

    public init(
      captures: [FieldCaptureOption],
      controls: FieldControls,
      policy: ChecklistPolicy = .standard,
      persist: @escaping @MainActor (FieldControls) throws -> Void,
      now: @escaping @Sendable () -> UTCTimestamp = { UTCTimestamp.now() }
    ) {
      let ordered = captures.enumerated()
        .filter { $0.element.mode != .exterior }
        .sorted { ($0.element.capturedAt, $0.offset) < ($1.element.capturedAt, $1.offset) }
        .map(\.element)
      self.floors = ordered
      self.editor = FieldControlsEditor(controls: controls)
      self.policy = policy
      self.persist = persist
      self.now = now
    }

    public var controls: FieldControls { editor.controls }

    public var selectedFloor: FieldCaptureOption? {
      floors.indices.contains(selectedFloorIndex) ? floors[selectedFloorIndex] : nil
    }

    /// The floor above the selected one, when there is one.
    private var nextFloor: FieldCaptureOption? {
      floors.indices.contains(selectedFloorIndex + 1) ? floors[selectedFloorIndex + 1] : nil
    }

    // MARK: Rows

    public var rows: [ControlRowContent] {
      guard let floor = selectedFloor else { return [] }
      let id = floor.ref.captureId
      let controls = editor.controls
      let scan = floor.scan
      // Under the standard policy the LiDAR scan provides the measurements and tape or laser
      // checks are optional, so nothing shows as missing.
      let required = policy.manualControlsRequired
      let fromScan = "From the LiDAR scan \u{00B7} tap to check with tape"
      var rows: [ControlRowContent] = []

      for (kind, axis) in [(ControlKind.distanceA, DistanceAxis.a), (.distanceB, .b)] {
        let scanned = axis == .a ? scan?.distanceAMm : scan?.distanceBMm
        if let item = controls.distances.first(where: {
          $0.capture.captureId == id && $0.axis == axis
        }) {
          rows.append(
            ControlRowContent(
              kind: kind, title: kind.rowTitle, subtitle: "\(item.from) \u{2192} \(item.to)",
              valueLines: Self.lines(item.measurement) + Self.scanLine(scanned), isMissing: false))
        } else if let scanned {
          rows.append(
            ControlRowContent(
              kind: kind, title: kind.rowTitle, subtitle: fromScan,
              valueLines: Self.lines(scanned), isMissing: false))
        } else {
          rows.append(
            ControlRowContent(
              kind: kind, title: kind.rowTitle, subtitle: "Not measured yet", valueLines: [],
              isMissing: required))
        }
      }

      let ceilings = controls.ceilingHeights.filter { $0.capture.captureId == id }
      let scannedHeights = scan?.ceilingHeights.map(\.heightMm) ?? []
      if let low = ceilings.map(\.measurement.valueMm).min(),
        let high = ceilings.map(\.measurement.valueMm).max()
      {
        let rooms = Set(ceilings.map(\.room)).count
        rows.append(
          ControlRowContent(
            kind: .ceilingHeight, title: ControlKind.ceilingHeight.rowTitle,
            subtitle: "\(rooms) \(rooms == 1 ? "room" : "rooms")",
            valueLines: [LengthFormatter.millimetreRange(low, high)], isMissing: false))
      } else if let low = scannedHeights.min(), let high = scannedHeights.max() {
        let rooms = scannedHeights.count
        rows.append(
          ControlRowContent(
            kind: .ceilingHeight, title: ControlKind.ceilingHeight.rowTitle,
            subtitle: "From the LiDAR scan \u{00B7} \(rooms) \(rooms == 1 ? "room" : "rooms")",
            valueLines: [
              LengthFormatter.millimetreRange(low, high),
              low == high
                ? LengthFormatter.feetInches(low)
                : "\(LengthFormatter.feetInches(low)) \u{2013} \(LengthFormatter.feetInches(high))",
            ], isMissing: false))
      } else {
        rows.append(
          ControlRowContent(
            kind: .ceilingHeight, title: ControlKind.ceilingHeight.rowTitle,
            subtitle: "Not measured yet", valueLines: [], isMissing: required))
      }

      let openings = controls.openings.filter { $0.capture.captureId == id }
      if openings.isEmpty, let scan {
        rows.append(
          ControlRowContent(
            kind: .opening, title: ControlKind.opening.rowTitle,
            subtitle: "From the LiDAR scan \u{00B7} \(scan.openingsSummary)",
            valueLines: [String(scan.doors + scan.windows + scan.openings)], isMissing: false))
      } else {
        rows.append(
          ControlRowContent(
            kind: .opening, title: ControlKind.opening.rowTitle,
            subtitle: openings.isEmpty
              ? "Doors and windows" : openings.map(\.label).joined(separator: ", "),
            valueLines: [String(openings.count)], isMissing: false))
      }

      if let upper = nextFloor {
        let pair: Set<LowercaseUUID> = [id, upper.ref.captureId]
        let levels = controls.floorToFloor.filter {
          Set([$0.lower.captureId, $0.upper.captureId]) == pair
        }
        if let level = levels.first {
          rows.append(
            ControlRowContent(
              kind: .floorToFloor, title: ControlKind.floorToFloor.rowTitle,
              subtitle: levels.map(\.location).joined(separator: ", "),
              valueLines: Self.lines(level.measurement), isMissing: false))
        } else {
          rows.append(
            ControlRowContent(
              kind: .floorToFloor, title: ControlKind.floorToFloor.rowTitle,
              subtitle: "To \(upper.label)", valueLines: [], isMissing: required))
        }
        let shared = controls.landmarks.filter {
          pair.isSubset(of: Set($0.captures.map(\.captureId)))
        }.count
        rows.append(
          ControlRowContent(
            kind: .landmark, title: ControlKind.landmark.rowTitle,
            subtitle: "Visible from two floors",
            valueLines: shared == 0
              ? [] : ["\(shared) of \(policy.minimumLandmarksPerFloorPair)"],
            isMissing: required && shared == 0))
      }
      return rows
    }

    /// True when the scan provides the measurements and tape or laser checks are optional.
    public var measurementsFromScan: Bool { !policy.manualControlsRequired }

    private static func lines(_ valueMm: Double) -> [String] {
      [LengthFormatter.millimetres(valueMm), LengthFormatter.feetInches(valueMm)]
    }

    /// "Scan 7 512 mm" under a tape or laser value, when the scan has the same quantity.
    private static func scanLine(_ valueMm: Double?) -> [String] {
      valueMm.map { ["Scan \(LengthFormatter.millimetres($0))"] } ?? []
    }

    private static func lines(_ measurement: FieldControls.Measurement) -> [String] {
      [
        LengthFormatter.millimetres(measurement.valueMm),
        LengthFormatter.feetInches(measurement.valueMm),
      ]
    }

    // MARK: Entry

    /// Opens the "New measurement" card for a row.
    public func beginEntry(_ kind: ControlKind) {
      activeKind = kind
      errorMessage = nil
      let unit = entry.unit
      entry = MeasurementEntryDraft(unit: unit)
      heightText = ""
      fromText = ""
      toText = ""
      roomText = ""
      labelText = ""
      locationText = kind == .floorToFloor ? "At stair" : ""
      upperFloorIndex = min(selectedFloorIndex + 1, max(floors.count - 1, 0))
      landmarkFloorIDs = []
      if kind == .landmark, let floor = selectedFloor {
        landmarkFloorIDs.insert(floor.ref.captureId)
        if let upper = nextFloor { landmarkFloorIDs.insert(upper.ref.captureId) }
      }
    }

    public func cancelEntry() {
      activeKind = nil
      errorMessage = nil
    }

    public func toggleLandmarkFloor(_ id: LowercaseUUID) {
      if landmarkFloorIDs.contains(id) {
        landmarkFloorIDs.remove(id)
      } else {
        landmarkFloorIDs.insert(id)
      }
    }

    /// True when the card has everything its kind needs.
    public var canSave: Bool {
      guard let kind = activeKind else { return false }
      func filled(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      switch kind {
      case .distanceA, .distanceB:
        return entry.bothUnits != nil && filled(fromText) && filled(toText)
      case .ceilingHeight:
        return entry.bothUnits != nil && filled(roomText)
      case .opening:
        return entry.bothUnits != nil && filled(roomText) && filled(labelText)
      case .floorToFloor:
        return entry.bothUnits != nil && filled(locationText)
          && upperFloorIndex != selectedFloorIndex
          && floors.indices.contains(upperFloorIndex)
      case .landmark:
        return filled(labelText) && landmarkFloorIDs.count >= 2
      }
    }

    /// Saves the entry into the controls, then passes the whole document to `persist`.
    /// On any failure nothing is kept and `errorMessage` says why.
    public func saveEntry() {
      guard let kind = activeKind, let floor = selectedFloor else { return }
      var next = editor
      do {
        let recordedAt = now()
        switch kind {
        case .distanceA, .distanceB:
          try next.setDistance(
            capture: floor.ref, axis: kind == .distanceA ? .a : .b, from: fromText, to: toText,
            measurement: entry.measurement(recordedAt: recordedAt))
        case .ceilingHeight:
          try next.setCeilingHeight(
            capture: floor.ref, room: roomText, location: locationText,
            measurement: entry.measurement(recordedAt: recordedAt))
        case .opening:
          let hasHeight = !heightText.trimmingCharacters(in: .whitespaces).isEmpty
          let height: FieldControls.Measurement? =
            try hasHeight
            ? FieldMeasurement.make(
              text: heightText, unit: entry.unit, method: entry.method, recordedAt: recordedAt)
            : nil
          try next.setOpening(
            capture: floor.ref, room: roomText, label: labelText,
            width: entry.measurement(recordedAt: recordedAt), height: height)
        case .floorToFloor:
          guard floors.indices.contains(upperFloorIndex) else { return }
          try next.setFloorToFloor(
            lower: floor.ref, upper: floors[upperFloorIndex].ref, location: locationText,
            measurement: entry.measurement(recordedAt: recordedAt))
        case .landmark:
          try next.setLandmark(
            label: labelText,
            captures: floors.filter { landmarkFloorIDs.contains($0.ref.captureId) }.map(\.ref))
        }
        try persist(next.controls)
        editor = next
        activeKind = nil
        errorMessage = nil
      } catch let error as LengthParseError {
        errorMessage = error.message
      } catch let error as FieldControlsEditError {
        errorMessage = error.description
      } catch let error as FieldControlsFileError {
        errorMessage = error.description
      } catch {
        errorMessage = "The measurement could not be saved: \(error.localizedDescription)"
      }
    }
  }
#endif
