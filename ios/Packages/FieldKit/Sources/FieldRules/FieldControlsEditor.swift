import CaptureContract
import Foundation

/// Why a control could not be added.
public enum FieldControlsEditError: Error, Equatable, Sendable, CustomStringConvertible {
  case emptyText(field: String)
  case textTooLong(field: String, maximum: Int)
  case landmarkNeedsTwoCaptures
  case floorToFloorNeedsTwoCaptures

  public var description: String {
    switch self {
    case .emptyText(let field): return "\(field) is required."
    case .textTooLong(let field, let maximum):
      return "\(field) must be at most \(maximum) characters."
    case .landmarkNeedsTwoCaptures:
      return "A shared landmark must be visible from two or more different floors or captures."
    case .floorToFloorNeedsTwoCaptures:
      return "Floor to floor needs two different captures, the lower and the upper floor."
    }
  }
}

/// Edits the visit-wide `FieldControls` document. Every `set...` replaces the control with the
/// same id, so measuring something again corrects the earlier value instead of adding a second.
///
/// Ids are built from the capture area key and the entered words, for example
/// `floor-1-distance-a` or `landmark-stair-newel-post`, so they are unique within the document
/// and stable across edits. Two entries whose words differ only in punctuation or case share an id
/// and replace each other.
public struct FieldControlsEditor: Hashable, Sendable {
  public private(set) var controls: FieldControls

  public init(visitId: LowercaseUUID) {
    controls = FieldControls(visitId: visitId)
  }

  public init(controls: FieldControls) {
    self.controls = controls
  }

  /// A long distance on a floor; `axis` B is perpendicular to A.
  public mutating func setDistance(
    capture: FieldControls.CaptureRef,
    axis: DistanceAxis,
    from: String,
    to: String,
    measurement: FieldControls.Measurement
  ) throws {
    let item = FieldControls.Distance(
      id: "\(capture.areaKey)-distance-\(axis.rawValue.lowercased())",
      capture: capture,
      axis: axis,
      from: try Self.text(from, field: "From"),
      to: try Self.text(to, field: "To"),
      measurement: measurement)
    Self.upsert(item, id: item.id, in: &controls.distances) { $0.id }
  }

  public mutating func setCeilingHeight(
    capture: FieldControls.CaptureRef,
    room: String,
    location: String? = nil,
    measurement: FieldControls.Measurement
  ) throws {
    let room = try Self.text(room, field: "Room")
    let location = try Self.optionalText(location, field: "Location")
    var id = "\(capture.areaKey)-ceiling-\(Self.slug(room))"
    if let location { id += "-\(Self.slug(location))" }
    let item = FieldControls.CeilingHeight(
      id: id, capture: capture, room: room, location: location, measurement: measurement)
    Self.upsert(item, id: id, in: &controls.ceilingHeights) { $0.id }
  }

  public mutating func setOpening(
    capture: FieldControls.CaptureRef,
    room: String,
    label: String,
    width: FieldControls.Measurement,
    height: FieldControls.Measurement? = nil
  ) throws {
    let room = try Self.text(room, field: "Room")
    let label = try Self.text(label, field: "Opening")
    let id = "\(capture.areaKey)-opening-\(Self.slug(room))-\(Self.slug(label))"
    let item = FieldControls.Opening(
      id: id, capture: capture, room: room, label: label, width: width, height: height)
    Self.upsert(item, id: id, in: &controls.openings) { $0.id }
  }

  /// Finished floor of the lower floor to finished floor of the upper floor.
  public mutating func setFloorToFloor(
    lower: FieldControls.CaptureRef,
    upper: FieldControls.CaptureRef,
    location: String,
    measurement: FieldControls.Measurement
  ) throws {
    guard lower.captureId != upper.captureId else {
      throw FieldControlsEditError.floorToFloorNeedsTwoCaptures
    }
    let location = try Self.text(location, field: "Location")
    let id = "floor-to-floor-\(lower.areaKey)-\(upper.areaKey)-\(Self.slug(location))"
    let item = FieldControls.FloorToFloor(
      id: id, lower: lower, upper: upper, location: location, measurement: measurement)
    Self.upsert(item, id: id, in: &controls.floorToFloor) { $0.id }
  }

  /// A landmark visible from two or more different captures.
  public mutating func setLandmark(
    label: String,
    description: String? = nil,
    captures: [FieldControls.CaptureRef],
    photoPaths: [String]? = nil
  ) throws {
    let label = try Self.text(label, field: "Landmark")
    let description = try Self.optionalText(description, field: "Description", maximum: 1000)
    var unique: [FieldControls.CaptureRef] = []
    for capture in captures where !unique.contains(capture) { unique.append(capture) }
    guard Set(unique.map(\.captureId)).count >= 2 else {
      throw FieldControlsEditError.landmarkNeedsTwoCaptures
    }
    let id = "landmark-\(Self.slug(label))"
    let item = FieldControls.Landmark(
      id: id, label: label, description: description, captures: unique,
      photoPaths: (photoPaths?.isEmpty ?? true) ? nil : photoPaths)
    Self.upsert(item, id: id, in: &controls.landmarks) { $0.id }
  }

  /// Removes the control with this id from whichever list holds it. True when one was removed.
  @discardableResult
  public mutating func remove(id: String) -> Bool {
    let before = controls
    controls.distances.removeAll { $0.id == id }
    controls.ceilingHeights.removeAll { $0.id == id }
    controls.openings.removeAll { $0.id == id }
    controls.floorToFloor.removeAll { $0.id == id }
    controls.landmarks.removeAll { $0.id == id }
    return controls != before
  }

  // MARK: Helpers

  private static func upsert<Item>(
    _ item: Item, id: String, in list: inout [Item], idOf: (Item) -> String
  ) {
    if let index = list.firstIndex(where: { idOf($0) == id }) {
      list[index] = item
    } else {
      list.append(item)
    }
  }

  private static func text(_ value: String, field: String, maximum: Int = 200) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw FieldControlsEditError.emptyText(field: field) }
    guard trimmed.count <= maximum else {
      throw FieldControlsEditError.textTooLong(field: field, maximum: maximum)
    }
    return trimmed
  }

  private static func optionalText(_ value: String?, field: String, maximum: Int = 200) throws
    -> String?
  {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return try text(value, field: field, maximum: maximum)
  }

  /// Lowercase ASCII letters and digits separated by single dashes, at most 40 characters.
  static func slug(_ value: String) -> String {
    var result = ""
    var pendingDash = false
    for scalar in value.lowercased().unicodeScalars {
      let isAlphanumeric =
        (scalar.value >= 0x30 && scalar.value <= 0x39)
        || (scalar.value >= 0x61 && scalar.value <= 0x7A)
      if isAlphanumeric {
        if pendingDash, !result.isEmpty { result.append("-") }
        pendingDash = false
        result.unicodeScalars.append(scalar)
      } else {
        pendingDash = true
      }
    }
    result = String(result.prefix(40))
    while result.hasSuffix("-") { result.removeLast() }
    return result.isEmpty ? "x" : result
  }
}
