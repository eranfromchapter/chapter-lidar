#if canImport(Observation)
  import CaptureContract
  import Foundation
  import Observation

  /// How a capture without LiDAR is measured (spec F16 2, step 2 of 5): the operator
  /// photographs a sketch and Claude reads it (recommended, spec F16), walks the rooms with the
  /// camera and taps the corners (spec F15), or enters the measurements from a sketch (spec F14,
  /// unchanged). In this order on the screen.
  public enum MeasureMethod: String, Sendable, Equatable, CaseIterable {
    case photo
    case walk
    case sketch
  }

  /// Words of the method choice and the walkthrough screens, so the screens and the tests agree.
  public enum MeasureMethodText {
    /// The screen's title (the large title has room for no more); the question is its first
    /// section's header.
    public static let title = "How to measure"
    public static let question = "How do you want to measure?"
    public static let photoTitle = "Photograph a sketch"
    public static let photoSubtitle =
      "Recommended. Claude reads the rooms, doors, windows and furniture from one photo"
    public static let walkTitle = "Walk the rooms with the camera"
    public static let walkSubtitle = "Tap the corners, doors and windows on screen"
    public static let sketchTitle = "Enter from a sketch"
    public static let sketchSubtitle = "Type the measurements from a sketch or a plan"
    public static let walkUnsupported = "This phone cannot track the camera"
    /// The Continue button for each method.
    public static func continueTitle(_ method: MeasureMethod) -> String {
      switch method {
      case .photo: return "Photograph the sketch"
      case .walk: return "Walk the rooms"
      case .sketch: return "Continue"
      }
    }
  }

  /// State behind How do you want to measure? (spec F15 2, F16 2): the method, and for a sketch
  /// photo or a walkthrough the floor or area name, what is captured and the units, as What are
  /// you drawing from? asks them for a typed sketch (the sketch screens keep asking them there,
  /// unchanged). The host reads `method` and the values at Continue.
  @MainActor
  @Observable
  public final class MeasureMethodModel {
    /// Photograph a sketch (the default), walk (when the phone can track the camera) or sketch.
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
      self.method = .photo
      self.floorLabel = floorLabel
      self.mode = mode
      self.displayUnits = displayUnits
      self.existingAreaKeys = existingAreaKeys
      self.areaKeyRule = areaKey
    }

    /// Chooses the method; the walk only when the phone can track the camera.
    public func choose(_ method: MeasureMethod) {
      guard method != .walk || canWalk else { return }
      self.method = method
    }

    public var cleanedLabel: String { floorLabel.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The capture's area key from its label; nil when the label has no letters or digits.
    public var areaKey: String? { areaKeyRule(cleanedLabel) }

    /// The method asks the floor or area, what is captured and the units on this screen: the
    /// sketch photo and the walk (a typed sketch asks them on its own source screen).
    public var asksFloor: Bool { method != .sketch }

    /// Why Continue is disabled, as its label says it; nil when enabled. The sketch path asks
    /// its floor questions on its own source screen, so only the photo and the walk are checked.
    public var blocker: String? {
      guard asksFloor else { return nil }
      if method == .walk, !canWalk { return MeasureMethodText.walkUnsupported }
      if cleanedLabel.isEmpty { return "Enter the floor or area" }
      guard let key = areaKey else { return "Use letters or numbers in the name" }
      if existingAreaKeys.contains(key) { return "\(cleanedLabel) is already captured. Use another name" }
      if mode == nil {
        return method == .walk ? "Choose what you are walking" : "Choose what the sketch shows"
      }
      return nil
    }

    public var canContinue: Bool { blocker == nil }

    /// "Walk the rooms" / "Continue", or the blocker.
    public var continueTitle: String { blocker ?? MeasureMethodText.continueTitle(method) }
  }
#endif
