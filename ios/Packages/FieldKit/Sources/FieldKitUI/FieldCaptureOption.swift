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

    public var id: LowercaseUUID { ref.captureId }

    public init(
      ref: FieldControls.CaptureRef, label: String, mode: CaptureMode,
      capturedAt: UTCTimestamp, rooms: [String] = [], scan: ScanMeasurements? = nil
    ) {
      self.ref = ref
      self.label = label
      self.mode = mode
      self.capturedAt = capturedAt
      self.rooms = rooms
      self.scan = scan
    }
  }
#endif
