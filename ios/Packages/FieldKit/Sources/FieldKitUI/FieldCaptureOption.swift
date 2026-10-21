#if canImport(SwiftUI) && canImport(UIKit)
  import CaptureContract
  import FieldRules
  import Foundation

  /// One capture (floor or area) of the visit as the photo and controls screens need it.
  /// The app builds these from the capture record and each capture's model.
  public struct FieldCaptureOption: Hashable, Sendable, Identifiable {
    public var ref: FieldControls.CaptureRef
    /// Label shown to people, for example "Floor 1".
    public var label: String
    public var mode: CaptureMode
    public var capturedAt: UTCTimestamp
    /// Room labels from the capture model, offered as Room chips.
    public var rooms: [String]
    /// Measurements read from this capture's LiDAR model; nil before the model exists.
    public var scan: ScanMeasurements?
    /// The capture's display units (`units.display`): the entry sheet starts in feet and inches
    /// for imperial, millimetres for metric, until something was entered in this visit.
    public var displayUnits: DisplayUnitSystem

    public var id: LowercaseUUID { ref.captureId }

    public init(
      ref: FieldControls.CaptureRef, label: String, mode: CaptureMode,
      capturedAt: UTCTimestamp, rooms: [String] = [], scan: ScanMeasurements? = nil,
      displayUnits: DisplayUnitSystem = .imperial
    ) {
      self.ref = ref
      self.label = label
      self.mode = mode
      self.capturedAt = capturedAt
      self.rooms = rooms
      self.scan = scan
      self.displayUnits = displayUnits
    }

    /// The capture as the Field controls list sees it.
    public var controlsFloor: ControlsFloor {
      ControlsFloor(
        ref: ref, label: label, mode: mode, capturedAt: capturedAt, rooms: rooms, scan: scan)
    }
  }
#endif
