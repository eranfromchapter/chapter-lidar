#if canImport(Observation)
  import CaptureContract
  import Foundation
  import Observation

  /// How a capture without LiDAR is measured (spec F15 2, step 2 of 5): the operator walks the
  /// rooms with the camera and taps the corners (recommended), or enters the measurements from
  /// a sketch (spec F14, unchanged).
  public enum MeasureMethod: String, Sendable, Equatable, CaseIterable {
    case walk
    case sketch
  }

  /// Words of the method choice and the walkthrough screens, so the screens and the tests agree.
  public enum MeasureMethodText {
    /// The screen's title (the large title has room for no more); the question is its first
    /// section's header.
    public static let title = "How to measure"
    public static let question = "How do you want to measure?"
    public static let walkTitle = "Walk the rooms with the camera"
    public static let walkSubtitle =
      "Recommended. Tap the corners, doors and windows on screen"
    public static let sketchTitle = "Enter from a sketch"
    public static let sketchSubtitle = "Type the measurements from a sketch or a plan"
    public static let walkUnsupported = "This phone cannot track the camera"
    /// The Continue button for each method.
    public static func continueTitle(_ method: MeasureMethod) -> String {
      method == .walk ? "Walk the rooms" : "Continue"
    }
  }

  /// State behind How do you want to measure? (spec F15 2): the method, and for a walkthrough
  /// the floor or area name, what is walked and the units, as What are you drawing from? asks
  /// them for a sketch (the sketch screens keep asking them there, unchanged). The host reads
  /// `method` and the values at Continue.
  @MainActor
  @Observable
  public final class MeasureMethodModel {
    /// Walk (the default when the phone can track the camera) or sketch.
    public var method: MeasureMethod
    /// The phone runs ARKit world tracking (every iOS 17 iPhone): the walk can be chosen.
    public let canWalk: Bool
    public var floorLabel: String
    public var mode: CaptureMode?
    public var displayUnits: DisplayUnitSystem
    public var existingAreaKeys: Set<String>
    @ObservationIgnored private let areaKeyRule: @Sendable (String) -> String?

    public init(
      canWalk: Bool, floorLabel: String = "Floor 1", mode: CaptureMode? = .floor,
      displayUnits: DisplayUnitSystem = .imperial, existingAreaKeys: Set<String> = [],
      areaKey: @escaping @Sendable (String) -> String? = SketchEntryModel.simpleAreaKey
    ) {
      self.canWalk = canWalk
      self.method = canWalk ? .walk : .sketch
      self.floorLabel = floorLabel
      self.mode = mode
      self.displayUnits = displayUnits
      self.existingAreaKeys = existingAreaKeys
      self.areaKeyRule = areaKey
    }

    /// Chooses the method; the walk only when the phone can track the camera.
    public func choose(_ method: MeasureMethod) {
      guard method == .sketch || canWalk else { return }
      self.method = method
    }

    public var cleanedLabel: String { floorLabel.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The capture's area key from its label; nil when the label has no letters or digits.
    public var areaKey: String? { areaKeyRule(cleanedLabel) }

    /// Why Continue is disabled, as its label says it; nil when enabled. The sketch path asks
    /// its floor questions on its own source screen, so only the walk is checked here.
    public var blocker: String? {
      guard method == .walk else { return nil }
      if !canWalk { return MeasureMethodText.walkUnsupported }
      if cleanedLabel.isEmpty { return "Enter the floor or area" }
      guard let key = areaKey else { return "Use letters or numbers in the name" }
      if existingAreaKeys.contains(key) { return "\(cleanedLabel) is already captured. Use another name" }
      if mode == nil { return "Choose what you are walking" }
      return nil
    }

    public var canContinue: Bool { blocker == nil }

    /// "Walk the rooms" / "Continue", or the blocker.
    public var continueTitle: String { blocker ?? MeasureMethodText.continueTitle(method) }
  }
#endif
