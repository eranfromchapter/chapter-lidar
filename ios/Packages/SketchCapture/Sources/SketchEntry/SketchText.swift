import CaptureContract
import Foundation

/// Words of the sketch screens, so the screens and the tests agree on them.
public enum SketchText {
  /// The Captures home's second button and its footnote (spec F14 2.1).
  public static let homeButton = "Sketch capture"
  public static let homeFootnote =
    "No LiDAR? Photograph a sketch or plan and enter the measurements."

  /// The room type as the picker shows it; the capture model's labels use the same words
  /// (`RoomTyping.label(of:)`), with "Other" for a room of no particular type.
  public static func roomTypeTitle(_ type: RoomType) -> String {
    switch type {
    case .livingRoom: return "Living Room"
    case .diningRoom: return "Dining Room"
    case .kitchen: return "Kitchen"
    case .bedroom: return "Bedroom"
    case .bathroom: return "Bathroom"
    case .closet: return "Closet"
    case .hallway: return "Hallway"
    case .laundry: return "Laundry"
    case .office: return "Office"
    case .utility: return "Utility"
    case .other: return "Other"
    }
  }

  /// "Wall 1" for the wall at `index` (0-based).
  public static func wallTitle(index: Int) -> String { "Wall \(index + 1)" }

  /// "Corner 1" for the corner at `index` (0-based).
  public static func cornerTitle(index: Int) -> String { "Corner \(index + 1)" }

  /// "Door 1", "Window 2", "Opening 1": the kind and the id's number.
  public static func openingTitle(id: String, kind: SketchOpeningKind) -> String {
    let number = id.split(separator: "-").last.map(String.init) ?? id
    return "\(kindTitle(kind)) \(number)"
  }

  public static func kindTitle(_ kind: SketchOpeningKind) -> String {
    switch kind {
    case .door: return "Door"
    case .window: return "Window"
    case .opening: return "Opening"
    }
  }

  public static func turnTitle(_ turn: SketchTurn) -> String {
    switch turn {
    case .left: return "Left"
    case .right: return "Right"
    case .unsquare: return "Not square"
    }
  }

  public static func cornerTitle(_ corner: SketchWallCorner) -> String {
    switch corner {
    case .start: return "Start"
    case .end: return "End"
    }
  }

  public static func sourceKindTitle(_ kind: SketchSourceKind) -> String {
    switch kind {
    case .handSketch: return "Hand sketch"
    case .existingPlan: return "Existing plan"
    case .none: return "No sketch"
    }
  }

  /// "Whole floor" / "One room", as the capture screens say them.
  public static func modeTitle(_ mode: CaptureMode) -> String {
    switch mode {
    case .room: return "One room"
    case .floor: return "Whole floor"
    case .exterior: return "Exterior"
    }
  }

  /// "4 walls · 2 openings".
  public static func roomSummary(walls: Int, openings: Int) -> String {
    "\(plural(walls, "wall", "walls")) \u{00B7} \(plural(openings, "opening", "openings"))"
  }

  public static func plural(_ count: Int, _ one: String, _ many: String) -> String {
    "\(count) \(count == 1 ? one : many)"
  }
}
