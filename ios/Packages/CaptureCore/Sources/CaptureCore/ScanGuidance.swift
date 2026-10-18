import CaptureContract

/// The direction card on the live scan screen: what the operator should do next, worked out from
/// what RoomPlan has found so far. RoomPlan's own coaching (drawn by its view) covers the moment
/// to moment hints; this card covers the order of the work.
public struct ScanGuidance: Sendable, Equatable {
  /// 1-based step, or nil when the card is a warning or a pause note rather than a step.
  public var step: Int?
  public static let stepCount = 4
  public var title: String
  public var detail: String
  /// True when RoomPlan reported a problem (too fast, too dark, too close...).
  public var isWarning: Bool

  public init(step: Int?, title: String, detail: String, isWarning: Bool = false) {
    self.step = step
    self.title = title
    self.detail = detail
    self.isWarning = isWarning
  }

  public static func next(
    counts: ScanCounts, mode: CaptureMode?, isPaused: Bool, instruction: ScanInstruction
  ) -> ScanGuidance {
    if isPaused {
      return ScanGuidance(
        step: nil, title: "Paused",
        detail: "Walk to the next room or area, point at a wall you already scanned, then tap Resume.")
    }
    if instruction != .normal {
      return ScanGuidance(
        step: nil, title: instruction.message, detail: warningDetail(instruction), isWarning: true)
    }
    if mode == .exterior {
      return ScanGuidance(
        step: nil, title: "Walk the outside slowly",
        detail: "Keep the facade in view from 2 to 4 m away. Tap Finish floor when you are back at the start.")
    }
    let openings = counts.doors + counts.windows
    if counts.walls == 0 {
      return ScanGuidance(
        step: 1, title: "Start at a corner",
        detail: "Hold the phone at chest height, point at a wall and move slowly until a white outline appears.")
    }
    if counts.walls < 4 {
      return ScanGuidance(
        step: 2, title: "Follow the walls",
        detail: "Walk along each wall to the next corner, 1 to 3 m away. Sweep up to the ceiling edge and down to the floor.")
    }
    if openings == 0 {
      return ScanGuidance(
        step: 3, title: "Doors and windows",
        detail: "Pan slowly across every door, window and opening until each one has an outline.")
    }
    let next =
      mode == .floor
      ? "Walk through a doorway into the next room, or tap Finish floor when every room is done."
      : "Look around once more for any wall without an outline, then tap Finish floor."
    return ScanGuidance(step: 4, title: "Check and finish", detail: next)
  }

  private static func warningDetail(_ instruction: ScanInstruction) -> String {
    switch instruction {
    case .moveCloseToWall: return "Stay 1 to 3 m from the walls."
    case .moveAwayFromWall: return "Step back so more of the wall is in view."
    case .slowDown: return "Move the phone slowly and steadily."
    case .turnOnLight: return "The room is too dark to scan. Turn on the lights or open the blinds."
    case .lowTexture: return "Plain surfaces are hard to track. Include a corner, a door or furniture in view."
    case .normal: return ""
    }
  }
}
