import CaptureContract
import Foundation

/// What a room is filled with on the plan sheet and in the station's spatial report (plan-sheet
/// §3.4.1, one rule for both documents, critique R-35): habitable rooms nude, wet rooms the wet
/// tint, every other room ground, and outdoor rooms not filled (a dashed edge). The station's
/// TypeScript port must match it; `fixtures/report-parity` carries the class of every fixture
/// room and the rule's own cases.
public enum RoomFillClass: String, CaseIterable, Codable, Sendable {
  case habitable
  case wet
  case other
  case outdoor

  /// Labels (any case) that make a room outdoor.
  static let outdoorWords = ["balcony", "terrace", "patio", "deck", "porch"]
  static let wetWords = ["bath", "kitchen", "laundry", "wc", "toilet", "shower"]
  static let habitableWords = ["bed", "living", "dining", "office", "study"]
  static let wetTypes: Set<RoomType> = [.bathroom, .kitchen, .laundry]
  static let habitableTypes: Set<RoomType> = [.bedroom, .livingRoom, .diningRoom, .office]
  static let wetObjects: Set<ObjectCategory> = [.toilet, .bathtub, .sink, .stove, .washerDryer]

  /// The class of a room labelled `label`, of `type` (the capture model's `Room.type`; nil in a
  /// 1.0.0 model, when the type is taken from the label as `FloorPlanStyle.type(fromLabel:)`
  /// does), holding objects of `objects` (by their `PlanGeometry` room), in a capture of
  /// `mode`. In order:
  ///
  /// 0. every room of an `exterior` capture is outdoor;
  /// 1. outdoor when the label contains balcony, terrace, patio, deck or porch;
  /// 2. wet when the type is bathroom, kitchen or laundry, or the label contains bath, kitchen,
  ///    laundry, wc, toilet or shower (so a closet renamed "Shower" is wet);
  /// 3. habitable when the type is bedroom, living room, dining room or office, or the label
  ///    contains bed, living, dining, office or study;
  /// 4. with no type (or `other`): wet when it holds a toilet, bathtub, sink, stove or washer
  ///    and dryer, habitable when it holds a bed;
  /// 5. otherwise other (closets, halls, utility, unlabeled "Room N").
  public static func of(
    label: String, type: RoomType?, objects: [ObjectCategory], mode: CaptureMode?
  ) -> RoomFillClass {
    if mode == .exterior { return .outdoor }
    let text = label.lowercased()
    func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
    if has(outdoorWords) { return .outdoor }
    let type = type ?? FloorPlanStyle.type(fromLabel: label)
    if let type, wetTypes.contains(type) { return .wet }
    if has(wetWords) { return .wet }
    if let type, habitableTypes.contains(type) { return .habitable }
    if has(habitableWords) { return .habitable }
    if type == nil || type == .other {
      if objects.contains(where: { wetObjects.contains($0) }) { return .wet }
      if objects.contains(.bed) { return .habitable }
    }
    return .other
  }

  /// The fill of the class on the sheet; nil for an outdoor room (dashed edge, no fill).
  var fill: DrawingColor? {
    switch self {
    case .habitable: return ChapterBrand.Sheet.nude
    case .wet: return ChapterBrand.Sheet.wet
    case .other: return ChapterBrand.Sheet.ground
    case .outdoor: return nil
    }
  }
}
